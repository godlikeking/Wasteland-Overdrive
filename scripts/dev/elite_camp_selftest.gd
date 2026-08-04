extends Node2D
## Headless self-test for the elite camp system (Iter8).
##   godot --headless res://scenes/dev/elite_camp_selftest.tscn
## Exits 0 when green, 1 when any check fails.
##
## Covers the two halves separately: TilemapBuilder's placement rules (count,
## determinism, spacing, walkability) and EliteCampDirector's lifecycle
## (proximity trigger, one-elite-per-camp, respawn cooldown).

var _failures: int = 0

@onready var world: WorldRoot = $World
@onready var camps: Node2D = $EliteCampDirector
@onready var player: CharacterBody2D = $Player

func _ready() -> void:
	await get_tree().process_frame
	print("=== elite_camp selftest ===")
	await _test_placement()
	await _test_determinism()
	await _test_spacing()
	await _test_walkable()
	await _test_trigger()
	await _test_respawn_cooldown()
	print("=== elite_camp selftest failures: %d ===" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

# --- Builder placement ---

func _test_placement() -> void:
	var b: TilemapBuilder = world.get_builder()
	if b == null:
		_fail("placement", "no builder")
		return
	var cfg: WastelandConfig = world.wasteland_config
	if b.elite_camps.size() != cfg.elite_camp_count:
		_fail("placement", "placed %d camps, wanted %d" % [b.elite_camps.size(), cfg.elite_camp_count])
	else:
		_ok("placement", "%d camps placed" % b.elite_camps.size())
	# camp_centers() must convert to world space, i.e. 64px per tile.
	var centers: Array[Vector2] = b.camp_centers()
	if centers.size() != b.elite_camps.size():
		_fail("placement", "camp_centers() size mismatch")
		return
	var cell: Vector2i = b.elite_camps[0]
	var expect: Vector2 = Vector2(cell) * float(cfg.tile_size) + Vector2(cfg.tile_size, cfg.tile_size) * 0.5
	if centers[0].distance_to(expect) > 1.0:
		_fail("placement", "camp_centers()[0] = %s, expected ~%s" % [centers[0], expect])
	else:
		_ok("placement", "camp_centers() maps cell -> world px")

func _test_determinism() -> void:
	# Same config -> same camps. Build a throwaway map with the same resource.
	var cfg: WastelandConfig = world.wasteland_config
	var tm := TileMap.new()
	add_child(tm)
	var b2 := TilemapBuilder.new()
	add_child(b2)
	b2.build(tm, cfg)
	var a: Array[Vector2i] = world.get_builder().elite_camps
	var b: Array[Vector2i] = b2.elite_camps
	var same: bool = a.size() == b.size()
	if same:
		for i in range(a.size()):
			if a[i] != b[i]:
				same = false
				break
	if same:
		_ok("determinism", "same seed -> identical camps")
	else:
		_fail("determinism", "%s != %s" % [a, b])
	tm.queue_free()
	b2.queue_free()
	await get_tree().process_frame

func _test_spacing() -> void:
	var cfg: WastelandConfig = world.wasteland_config
	var cells: Array[Vector2i] = world.get_builder().elite_camps
	var half: int = cfg.map_size_tiles / 2
	var limit: int = half - 3 - cfg.elite_camp_radius_tiles
	var min_d: int = cfg.elite_camp_min_dist_tiles
	var min_gap: int = cfg.elite_camp_min_gap_tiles
	var bad: String = ""
	for i in range(cells.size()):
		var c: Vector2i = cells[i]
		if c.x * c.x + c.y * c.y < min_d * min_d:
			bad = "camp %s within %d tiles of spawn" % [c, min_d]
			break
		if absi(c.x) > limit or absi(c.y) > limit:
			bad = "camp %s outside safe limit %d (would hit the pit border)" % [c, limit]
			break
		for j in range(i + 1, cells.size()):
			var d: Vector2i = c - cells[j]
			if d.x * d.x + d.y * d.y < min_gap * min_gap:
				bad = "camps %s and %s closer than %d tiles" % [c, cells[j], min_gap]
				break
		if bad != "":
			break
	if bad == "":
		_ok("spacing", "all camps respect spawn distance, map bounds and mutual gap")
	else:
		_fail("spacing", bad)

func _test_walkable() -> void:
	# Every cell of a camp disc must be the CAMP tile, carry no collision
	# polygon (or the elite would be trapped in its own arena) and not be
	# registered as swamp.
	var b: TilemapBuilder = world.get_builder()
	var tm: TileMap = world.get_tilemap()
	var cfg: WastelandConfig = world.wasteland_config
	var r: int = cfg.elite_camp_radius_tiles
	var bad: String = ""
	for centre in b.elite_camps:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dy * dy > r * r:
					continue
				var cell := Vector2i(centre.x + dx, centre.y + dy)
				var atlas: Vector2i = tm.get_cell_atlas_coords(0, cell)
				if atlas.x != TilemapBuilder.T_CAMP:
					bad = "cell %s is atlas %s, expected CAMP" % [cell, atlas]
					break
				if b.swamp_cells.has(cell):
					bad = "cell %s still registered as swamp" % cell
					break
				var td: TileData = tm.get_cell_tile_data(0, cell)
				if td and td.get_collision_polygons_count(0) > 0:
					bad = "cell %s has a collision polygon" % cell
					break
			if bad != "":
				break
		if bad != "":
			break
	if bad == "":
		_ok("walkable", "camp discs are CAMP tiles, collision-free and swamp-free")
	else:
		_fail("walkable", bad)

# --- Director lifecycle ---

func _test_trigger() -> void:
	if camps.camp_count() == 0:
		_fail("trigger", "director tracked 0 camps")
		return
	_ok("trigger", "director tracked %d camps" % camps.camp_count())
	var positions: Array[Vector2] = camps.camp_positions()
	# Far away + still within arm_delay: nothing should spawn.
	player.global_position = positions[0] + Vector2(5000, 5000)
	await _advance(0.4)
	if camps.live_elite_count() != 0:
		_fail("trigger", "elite spawned while player was 5000px away")
	else:
		_ok("trigger", "no spawn out of range")
	# Walk onto the camp, with the arming delay skipped.
	camps.force_arm()
	player.global_position = positions[0]
	await _advance(0.4)
	if camps.live_elite_count() != 1:
		_fail("trigger", "expected 1 elite on camp entry, got %d" % camps.live_elite_count())
		return
	_ok("trigger", "camp spawned its elite on player approach")
	# Sitting on the camp must not stack a second elite.
	await _advance(0.6)
	if camps.live_elite_count() != 1:
		_fail("trigger", "camp stacked %d elites" % camps.live_elite_count())
	else:
		_ok("trigger", "camp holds at most one elite")

func _test_respawn_cooldown() -> void:
	var elites: Array = get_tree().get_nodes_in_group("enemies")
	if elites.is_empty():
		_fail("respawn", "no elite to kill")
		return
	for e in elites:
		e.queue_free()
	# A camp only counts its elite as gone once the node is queued for
	# deletion, so a single throttled scan (0.25s) is enough to see the death.
	await _advance(0.4)
	if camps.live_elite_count() != 0:
		_fail("respawn", "%d elites still counted as live after the kill" % camps.live_elite_count())
		return
	if camps.cooldown_of(0) <= 0.0:
		_fail("respawn", "cooldown not armed after the elite died (got %f)" % camps.cooldown_of(0))
	else:
		_ok("respawn", "cooldown armed at %.1fs after death" % camps.cooldown_of(0))
	# And the camp must stay empty while the cooldown runs, even though the
	# player is standing right on it.
	await _advance(0.6)
	if camps.live_elite_count() != 0:
		_fail("respawn", "camp respawned during cooldown")
	else:
		_ok("respawn", "camp stays empty during cooldown")

# --- Helpers ---

func _advance(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

func _ok(tag: String, msg: String) -> void:
	print("  [ok] %s: %s" % [tag, msg])

func _fail(tag: String, msg: String) -> void:
	_failures += 1
	printerr("  [FAIL] %s: %s" % [tag, msg])
