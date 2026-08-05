extends Node2D
## Headless self-test for the map boundary.
##   godot --headless res://scenes/dev/bounds_selftest.tscn
## Exits 0 when green, 1 when any check fails.
##
## The edge of the map used to be a 2-cell ring of PIT tiles — a wall. It is gone
## on purpose (a wall teaches the player that the edge is a safe place to kite
## against), and the consequence now lives in code: `map_rect()` says where the
## map ends, `out_of_bounds_depth()` says how far past it you are, and the
## OutOfBounds component on the player turns that into escalating damage.
##
## This file guards both halves of that trade. `no_wall` is the positive
## assertion that the ring is really gone, so restoring `_paint_borders()` turns
## it red; the damage tests are the negative one, so deleting the punishment
## leaves the map with neither a wall nor a cost.
##
## Damage is measured by driving the component's own `_physics_process` over real
## frames — the point is that it is WIRED, not that the arithmetic parses. The
## clock is `physics_frame`, never `process_frame`: headless runs uncapped at
## roughly 160fps, so process frames and game seconds are unrelated here, and
## every threshold below is derived from the component's knobs times the real
## elapsed physics time. The player is parked at the origin between tests because
## that is the one cell the generator guarantees is plain sand
## (`spawn_no_swamp_radius`), so the swamp component cannot add damage to a reading.

var _failures: int = 0

@onready var world: Node2D = $World
@onready var player: CharacterBody2D = $Player
@onready var director: Node2D = $SpawnDirector

func _ready() -> void:
	await get_tree().process_frame
	print("=== bounds selftest ===")
	player.max_hp = 100000.0
	player.hp = player.max_hp
	_test_map_size()
	_test_no_wall()
	_test_depth()
	_test_ramp_curve()
	await _test_inside_safe()
	await _test_outside_damages()
	await _test_bypasses_shield_and_iframes()
	_test_camps_inside()
	await _test_spawn_points_inside()
	print("=== bounds selftest failures: %d ===" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

# --- Geometry -----------------------------------------------------------

## The map is 128 tiles of 64px, centred on the origin: 8192x8192 from
## (-4096, -4096). The player spawns at (0, 0), so a rect that is not centred
## would put the run either half outside the world or nowhere near the terrain.
func _test_map_size() -> void:
	var cfg: WastelandConfig = world.wasteland_config
	var expect_side: float = float(cfg.map_size_tiles) * float(cfg.tile_size)
	var r: Rect2 = world.map_rect()
	if absf(r.size.x - expect_side) > 0.01 or absf(r.size.y - expect_side) > 0.01:
		_fail("map_size", "map is %s px, config says %.0fx%.0f" % [str(r.size), expect_side, expect_side])
		return
	if absf(r.get_center().x) > 0.01 or absf(r.get_center().y) > 0.01:
		_fail("map_size", "map centre is %s, not the origin the player spawns on" % str(r.get_center()))
		return
	_ok("map_size", "%.0fx%.0f px centred on the origin" % [r.size.x, r.size.y])

## The positive assertion that the wall is gone.
##
## NOT "no edge cell is solid": rubble/scrap/pit are scattered by noise, so a few
## solid cells land on the edge by chance and always will. What the old border
## pass did was make the ring 100% solid, so the test is on the DENSITY — the
## outer band must look like ordinary terrain, not like a fence. Restoring
## `_paint_borders()` takes this straight from ~10% to 100%.
func _test_no_wall() -> void:
	var builder: Node = world.get_builder()
	if builder == null:
		_fail("no_wall", "no tilemap builder to inspect")
		return
	var tm: TileMap = builder.tilemap as TileMap
	var cfg: WastelandConfig = world.wasteland_config
	var lo: int = -cfg.map_size_tiles / 2
	var hi: int = cfg.map_size_tiles / 2 - 1
	var band: Array[Vector2i] = []
	for x in range(lo, hi + 1):
		for d in range(2):
			band.append(Vector2i(x, lo + d))
			band.append(Vector2i(x, hi - d))
	for y in range(lo + 2, hi - 1):
		for d in range(2):
			band.append(Vector2i(lo + d, y))
			band.append(Vector2i(hi - d, y))

	var solid: int = 0
	var pits: int = 0
	for cell in band:
		var tid: int = tm.get_cell_atlas_coords(0, cell).x
		if tid == TilemapBuilder.T_PIT:
			pits += 1
		if _cell_blocks(tm, cell):
			solid += 1
	var frac: float = float(solid) / float(maxi(1, band.size()))
	# The old ring was every cell of the band; ordinary terrain is ~10% solid.
	if frac > 0.3:
		_fail("no_wall", "%.0f%% of the outer 2-cell band blocks movement (%d/%d) — that is a wall, not terrain" % [
			frac * 100.0, solid, band.size()])
	else:
		_ok("no_wall", "the outer 2-cell band is %.0f%% solid (%d pits), same as ordinary terrain" % [
			frac * 100.0, pits])

	# And the corner specifically: it is where a player leaning on a wall would
	# park, so a ring that survived only at the corners would still teach the
	# wrong lesson.
	var corner_solid: int = 0
	var corners: Array[Vector2i] = [
		Vector2i(lo, lo), Vector2i(hi, lo), Vector2i(lo, hi), Vector2i(hi, hi)]
	for c in corners:
		if _cell_blocks(tm, c):
			corner_solid += 1
	if corner_solid == corners.size():
		_fail("no_wall", "all 4 map corners block movement — the ring survived at the corners")
	else:
		_ok("no_wall", "%d of 4 corners are walkable" % (corners.size() - corner_solid))

## Depth is a distance, not a flag, because the HUD tint has to grow with it.
## The diagonal case is the one a per-axis maximum gets wrong: cutting a corner
## must not be cheaper than crossing an edge head-on.
func _test_depth() -> void:
	var r: Rect2 = world.map_rect()
	var bad: Array[String] = []
	if world.out_of_bounds_depth(Vector2.ZERO) != 0.0:
		bad.append("the origin reported as outside")
	if world.out_of_bounds_depth(r.position + Vector2(1, 1)) != 0.0:
		bad.append("a point 1px inside the corner reported as outside")
	var d_right: float = world.out_of_bounds_depth(Vector2(r.end.x + 100.0, 0.0))
	if absf(d_right - 100.0) > 0.01:
		bad.append("100px past the right edge read %.1f" % d_right)
	var d_up: float = world.out_of_bounds_depth(Vector2(0.0, r.position.y - 250.0))
	if absf(d_up - 250.0) > 0.01:
		bad.append("250px above the top edge read %.1f" % d_up)
	# 3-4-5: 30px right and 40px down of the corner is 50px out, not 40.
	var d_diag: float = world.out_of_bounds_depth(r.end + Vector2(30.0, 40.0))
	if absf(d_diag - 50.0) > 0.01:
		bad.append("30px+40px past the corner read %.1f, expected the euclidean 50" % d_diag)
	if bad.is_empty():
		_ok("depth", "0 inside, exact past each edge, euclidean past a corner")
	else:
		_fail("depth", "; ".join(bad))

## The damage ramp, as a pure function. It has to start at the base rate (so
## clipping a corner is survivable), climb (so camping outside is not a
## strategy), and stop climbing (so the number stays a number).
func _test_ramp_curve() -> void:
	var oob: Node = player.get_node_or_null("OutOfBounds")
	if oob == null:
		_fail("ramp", "the player has no OutOfBounds component — nothing enforces the edge")
		return
	var bad: Array[String] = []
	if absf(oob.current_dps(0.0) - oob.base_dps) > 0.01:
		bad.append("t=0 is %.1f/s, expected the base %.1f/s" % [oob.current_dps(0.0), oob.base_dps])
	if oob.current_dps(oob.ramp) <= oob.current_dps(0.0):
		bad.append("one ramp period later it still does %.1f/s" % oob.current_dps(oob.ramp))
	var cap: float = oob.base_dps * oob.ramp_max
	if absf(oob.current_dps(9999.0) - cap) > 0.01:
		bad.append("it climbs to %.1f/s instead of capping at %.1f/s" % [oob.current_dps(9999.0), cap])
	var prev: float = -1.0
	for i in range(0, 40):
		var d: float = oob.current_dps(float(i) * 0.5)
		if d < prev - 0.01:
			bad.append("the ramp dips at t=%.1fs" % (float(i) * 0.5))
			break
		prev = d
	# The number that decides whether the edge is a real boundary: how long a
	# fresh 100hp player survives out there.
	var hp: float = 100.0
	var t: float = 0.0
	while hp > 0.0 and t < 60.0:
		hp -= oob.current_dps(t) * oob.tick
		t += oob.tick
	if t > 6.0:
		bad.append("a 100hp player survives %.1fs outside — that is a suggestion, not a boundary" % t)
	if bad.is_empty():
		_ok("ramp", "%.0f/s base ramping to %.0f/s; 100hp dies in %.1fs outside" % [oob.base_dps, cap, t])
	else:
		_fail("ramp", "; ".join(bad))

# --- Damage -------------------------------------------------------------

## The guard against the whole rule misfiring inward. An off-by-one in the rect
## or a zero-size rect read as "everything is outside" would burn the player down
## on the spawn tile, and every other test here would still pass.
func _test_inside_safe() -> void:
	await _park_player()
	var before: float = player.hp
	await _physics_frames(90)
	if player.hp < before - 0.01:
		_fail("inside_safe", "a player standing on the spawn tile lost %.1f hp in %.1fs" % [
			before - player.hp, _phys_seconds(90)])
	else:
		_ok("inside_safe", "no damage in %.1fs inside the map" % _phys_seconds(90))

## The replacement for the wall. Crossing the line has to cost, and the cost has
## to grow, or the edge is a suggestion.
func _test_outside_damages() -> void:
	await _park_player()
	var oob: Node = player.get_node_or_null("OutOfBounds")
	if oob == null:
		_fail("outside_damages", "the player has no OutOfBounds component")
		return
	var r: Rect2 = world.map_rect()
	player.global_position = Vector2(r.end.x + 300.0, 0.0)
	var before: float = player.hp
	var seen: Array[float] = []
	var on_oob: Callable = func(depth: float, dps: float) -> void: seen.append(dps)
	GameState.out_of_bounds_changed.connect(on_oob)
	await _physics_frames(90)
	GameState.out_of_bounds_changed.disconnect(on_oob)
	var secs: float = _phys_seconds(90)
	var dealt: float = before - player.hp
	# A band, not just "> 0". The floor catches damage that never fires; the
	# ceiling catches damage applied per FRAME instead of per tick, which would
	# be 60x over and is exactly the bug the `tick` accumulator exists to avoid.
	# Both ends come from the component's own knobs so retuning cannot make this
	# lie, and the ceiling is the ramp cap, which the dps provably cannot exceed.
	var lo: float = oob.base_dps * secs * 0.6
	var hi: float = oob.base_dps * oob.ramp_max * secs
	if dealt < lo:
		_fail("outside_damages", "%.1fs outside cost only %.1f hp (expected at least %.1f) — the edge has neither a wall nor a price" % [
			secs, dealt, lo])
	elif dealt > hi:
		_fail("outside_damages", "%.1fs outside cost %.1f hp, above the %.1f the ramp cap allows — damage is firing per frame, not per tick" % [
			secs, dealt, hi])
	else:
		_ok("outside_damages", "%.1fs outside cost %.0f hp (band %.0f-%.0f)" % [secs, dealt, lo, hi])
	if seen.is_empty():
		_fail("outside_damages", "no out_of_bounds_changed emitted — the HUD would never warn")
	elif seen[seen.size() - 1] <= seen[0] + 0.01:
		_fail("outside_damages", "dps stayed at %.1f over %.1fs outside; it must ramp" % [seen[0], secs])
	else:
		_ok("outside_damages", "dps ramped %.0f/s -> %.0f/s while out there" % [seen[0], seen[seen.size() - 1]])
	await _park_player()

## Out-of-bounds damage is a DoT, so it goes down the same channel as the poison
## pool: the shield neither blocks it nor is spent by it, and i-frames do not
## throttle it. Routing it through `take_damage` would let a player park outside
## the map behind two shield charges, and would cap the "high damage" ramp at
## 2.5 ticks/second.
func _test_bypasses_shield_and_iframes() -> void:
	await _park_player()
	var oob: Node = player.get_node_or_null("OutOfBounds")
	if oob == null:
		_fail("bypass", "the player has no OutOfBounds component")
		return
	GameState.shield_charges = 0
	GameState.shield_left = 0.0
	GameState.add_shield(2, 30.0)
	player.invulnerable = true
	var charges_before: int = GameState.shield_charges
	var r: Rect2 = world.map_rect()
	player.global_position = Vector2(r.end.x + 300.0, 0.0)
	var before: float = player.hp
	await _physics_frames(60)
	var secs: float = _phys_seconds(60)
	var dealt: float = before - player.hp
	# Derived from the component's knobs and the physics tick rate, never from an
	# assumed 60fps: the same `dealt` reading is correct at any frame rate.
	var floor_dmg: float = oob.base_dps * secs * 0.6
	if dealt < floor_dmg:
		_fail("bypass", "%.1fs outside behind a 2-charge shield with i-frames up cost only %.1f (expected at least %.1f)" % [
			secs, dealt, floor_dmg])
	else:
		_ok("bypass", "%.0f hp lost in %.1fs outside despite a full shield and open i-frames" % [dealt, secs])
	if GameState.shield_charges != charges_before:
		_fail("bypass", "being outside spent %d shield charge(s) — a DoT would strip the shield in a second" % (charges_before - GameState.shield_charges))
	else:
		_ok("bypass", "the shield still has %d charge(s)" % GameState.shield_charges)
	player.invulnerable = false
	GameState.shield_charges = 0
	GameState.shield_left = 0.0
	GameState.shield_changed.emit(0)
	await _park_player()

# --- Things that must not be placed in the void --------------------------

## Camps are the reason `camp_placement_limit()` exists. Without the wall there is
## nothing stopping a camp disc from hanging off the edge, which would put an
## elite — and its loot — in the kill zone.
func _test_camps_inside() -> void:
	var builder: Node = world.get_builder()
	var cfg: WastelandConfig = world.wasteland_config
	var limit: int = builder.camp_placement_limit()
	var cells: Array[Vector2i] = builder.elite_camps
	if cells.size() != cfg.elite_camp_count:
		_fail("camps_inside", "%d camps placed, config asks for %d" % [cells.size(), cfg.elite_camp_count])
	else:
		_ok("camps_inside", "all %d configured camps were placed" % cells.size())
	var bad: Array[String] = []
	for c in cells:
		if absi(c.x) > limit or absi(c.y) > limit:
			bad.append("%s past the %d-cell limit" % [str(c), limit])
	# And in world space, disc edge included, not just the centre cell.
	var pad: float = float(cfg.elite_camp_radius_tiles * cfg.tile_size)
	for p in builder.camp_centers():
		if world.out_of_bounds_depth(p) > 0.0 or world.out_of_bounds_depth(p + Vector2(pad, pad)) > 0.0 \
				or world.out_of_bounds_depth(p - Vector2(pad, pad)) > 0.0:
			bad.append("camp disc at %s reaches outside the map" % str(p))
	if bad.is_empty():
		_ok("camps_inside", "every camp disc sits inside the map")
	else:
		_fail("camps_inside", "; ".join(bad))

## Spawn points used to be picked purely relative to the camera, which put half
## of them in the void once the player reached an edge. The fix retries the four
## sides instead of clamping — a clamped point would land ON SCREEN, and an enemy
## appearing in the player's face is worse than one standing outside the map.
func _test_spawn_points_inside() -> void:
	var r: Rect2 = world.map_rect()
	# The visible half-extent as the CAMERA sees it, zoom included. Using the raw
	# viewport size here is wrong and reads as a bug in the director: at zoom 1.2
	# the camera only shows vp/1.2 world pixels, so a point 613px out is off
	# screen even though it is inside a 640px half-viewport box.
	var vis: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var cam: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		vis /= cam.zoom
	# Hugging one edge: at least one side is always usable, so this is strict.
	player.global_position = Vector2(r.end.x - 100.0, 0.0)
	await _physics_frames(1)
	var outside: int = 0
	var on_screen: int = 0
	for i in range(200):
		var p: Vector2 = director._random_offscreen_point()
		if world.out_of_bounds_depth(p) > 0.0:
			outside += 1
		# The point of retrying instead of clamping: it must still be off-screen.
		# Off-screen means outside the visible rect on EITHER axis.
		var d: Vector2 = (p - player.global_position).abs()
		if d.x <= vis.x and d.y <= vis.y:
			on_screen += 1
	if outside > 0:
		_fail("spawn_points", "%d/200 spawn points landed outside the map with the player on an edge" % outside)
	else:
		_ok("spawn_points", "200/200 spawn points inside the map with the player on an edge")
	if on_screen > 0:
		_fail("spawn_points", "%d/200 spawn points landed on screen — enemies would pop into view" % on_screen)
	else:
		_ok("spawn_points", "none of the 200 landed on screen")

	# A corner is the hard case: two of the four sides are unusable and the other
	# two only partly, so the retry cannot always win. It falls back to the old
	# behaviour on purpose — spawning into the void beats a run where the enemies
	# stop coming because the player stood in a corner. Assert it is mostly
	# right, and record the rate rather than pretending it is perfect.
	player.global_position = r.end - Vector2(100.0, 100.0)
	await _physics_frames(1)
	var corner_out: int = 0
	for i in range(200):
		if world.out_of_bounds_depth(director._random_offscreen_point()) > 0.0:
			corner_out += 1
	var inside_frac: float = 1.0 - float(corner_out) / 200.0
	if inside_frac < 0.6:
		_fail("spawn_points", "only %.0f%% of corner spawn points are inside the map" % (inside_frac * 100.0))
	else:
		_ok("spawn_points", "%.0f%% inside at a corner (the rest fall back rather than stop spawning)" % (inside_frac * 100.0))
	player.global_position = Vector2.ZERO

# --- Helpers ------------------------------------------------------------

## True when the tile in `cell` carries a collision polygon, i.e. blocks movement.
## Read off the generated TileSet rather than a tile-id list, so a change to which
## ids are physical cannot make this test lie.
func _cell_blocks(tm: TileMap, cell: Vector2i) -> bool:
	var src: TileSetAtlasSource = tm.tile_set.get_source(0) as TileSetAtlasSource
	if src == null:
		return false
	var coords: Vector2i = tm.get_cell_atlas_coords(0, cell)
	if coords.x < 0:
		return false
	var td: TileData = src.get_tile_data(coords, 0)
	if td == null:
		return false
	return td.get_collision_polygons_count(0) > 0

## Back to the guaranteed-clean spawn tile, full hp, no leftover i-frames.
func _park_player() -> void:
	player.global_position = Vector2.ZERO
	player.invulnerable = false
	player.alive = true
	player.hp = player.max_hp
	# Physics frames, so the component actually runs and clears its `_out_time`;
	# a process frame does not guarantee a `_physics_process` call, which would
	# leave the ramp part-way up and the next test measuring the wrong slope.
	await _physics_frames(2)
	player.hp = player.max_hp

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

## Wait `n` PHYSICS frames, i.e. exactly `n` calls to the component's
## `_physics_process`, i.e. exactly `n / physics_ticks_per_second` seconds of
## game time.
##
## `process_frame` is the WRONG clock for anything that measures damage. Headless
## runs uncapped — around 160fps here — so 60 process frames is about a third of
## a second of physics, and a threshold derived from "60 frames = 1 second" fails
## against a perfectly working feature. That mistake cost a red `bypass` line.
func _physics_frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame

## Game seconds that `_physics_frames(n)` covers. Used in the messages too, so a
## printed duration can never drift from the loop that produced it.
func _phys_seconds(n: int) -> float:
	return float(n) / float(Engine.physics_ticks_per_second)

func _ok(tag: String, msg: String) -> void:
	print("  [ok] %s: %s" % [tag, msg])

func _fail(tag: String, msg: String) -> void:
	_failures += 1
	printerr("  [FAIL] %s: %s" % [tag, msg])
