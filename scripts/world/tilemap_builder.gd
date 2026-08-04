extends Node
## Procedural TileSet + map generator. Builds a 6-tile wasteland TileSet at
## runtime (sandy ground + rubble + scrap metal + pit + toxic swamp + elite
## camp) and paints a 64x64 map. Exposes `swamp_cells` so player/enemy can
## look up "am I in a swamp" without colliding with it (swamp is non-blocking),
## and `elite_camps` so EliteCampDirector knows where the arenas are.
##
## Performance: paints ~4096 cells once at _ready. The 6 sub-textures are
## 64x64 each, generated via per-pixel loops; under 30ms on a modest CPU.

class_name TilemapBuilder

const TS := 64                       # tile pixel size

# --- Tile IDs (match WastelandConfig.TileId) ---
const T_SAND := 0
const T_RUBBLE := 1
const T_SCRAP := 2
const T_PIT := 3
const T_SWAMP := 4
const T_CAMP := 5

# Atlased tileset: 6 columns x 1 row, each 64x64.
const ATLAS_COLS := 6
const ATLAS_W := TS * ATLAS_COLS
const ATLAS_H := TS

# How far an elite camp may drift from the centre of its angular sector, as a
# fraction of the sector width. Keeps the ring from looking mechanical while
# still leaving a provable angular gap between neighbours.
const CAMP_ANGLE_JITTER := 0.08

var config: WastelandConfig
var tilemap: TileMap
var swamp_cells: Dictionary = {}     # Vector2i -> true
var elite_camps: Array[Vector2i] = []  # camp centre cells

# --- Public API ---

func build(p_tilemap: TileMap, p_config: WastelandConfig) -> void:
	tilemap = p_tilemap
	config = p_config
	if tilemap == null or config == null:
		push_error("[TilemapBuilder] missing tilemap or config")
		return
	_build_tileset()
	_paint_map()
	# Camps come after the terrain so they can carve obstacles/swamp out of
	# their arena, but before the borders so the escape-proof pit band still
	# wins on the map edge.
	_place_elite_camps()
	_paint_borders()
	print("[TilemapBuilder] %dx%d map painted. Swamp cells: %d, elite camps: %d" % [
		config.map_size_tiles, config.map_size_tiles, swamp_cells.size(), elite_camps.size()
	])

func is_swamp(world_pos: Vector2) -> bool:
	var cell: Vector2i = tilemap.local_to_map(tilemap.to_local(world_pos))
	return swamp_cells.has(cell)

## Camp centres in world space, for EliteCampDirector.
func camp_centers() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if tilemap == null:
		return out
	for cell in elite_camps:
		out.append(tilemap.to_global(tilemap.map_to_local(cell)))
	return out

# --- TileSet generation ---

func _build_tileset() -> void:
	var ts: TileSet = TileSet.new()
	ts.tile_size = Vector2(TS, TS)
	# Physics layer 0 = blockers (rubble, scrap, pit). Swamp is NOT here.
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)        # on layer 1 = World
	ts.set_physics_layer_collision_mask(0, 1)          # collides with layer 1
	# Navigation layer 0 = same blocker set; baked into navmesh.
	ts.add_navigation_layer()
	var atlas: TileSetAtlasSource = TileSetAtlasSource.new()
	var img: Image = _make_atlas_image()
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	atlas.texture = tex
	atlas.texture_region_size = Vector2(TS, TS)
	# Tiles sit side-by-side in the atlas. Atlas is 320x64 (5 tiles * 64).
	atlas.margins = Vector2.ZERO
	atlas.separation = Vector2.ZERO
	atlas.use_texture_padding = false
	ts.add_source(atlas, 0)
	# Create one tile per column. create_tile() is on TileSetAtlasSource,
	# not on TileSet itself (Godot 4.x).
	for tid in ATLAS_COLS:
		var at: Vector2i = Vector2i(tid, 0)
		atlas.create_tile(at)
		# Per-tile physics + navigation only for blockers.
		if tid == T_RUBBLE or tid == T_SCRAP or tid == T_PIT:
			var td: TileData = atlas.get_tile_data(at, 0)
			if td:
				td.set_collision_polygons_count(0, 1)
				td.set_collision_polygon_points(0, 0, _square_polygon())
				td.set_navigation_polygon(0, _square_navigation_polygon())
	tilemap.tile_set = ts

func _make_atlas_image() -> Image:
	var img: Image = Image.create(ATLAS_W, ATLAS_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Column 0: sand
	_paint_into(img, 0, _gen_sand)
	# Column 1: rubble
	_paint_into(img, 1, _gen_rubble)
	# Column 2: scrap
	_paint_into(img, 2, _gen_scrap)
	# Column 3: pit
	_paint_into(img, 3, _gen_pit)
	# Column 4: swamp
	_paint_into(img, 4, _gen_swamp)
	# Column 5: elite camp floor
	_paint_into(img, 5, _gen_camp)
	return img

func _paint_into(img: Image, col: int, fn: Callable) -> void:
	var sub: Image = fn.call()
	img.blit_rect(sub, Rect2i(0, 0, TS, TS), Vector2i(col * TS, 0))

# --- Tile painters (each returns a fresh 64x64 Image) ---

func _gen_sand() -> Image:
	var img: Image = Image.create(TS, TS, false, Image.FORMAT_RGBA8)
	var base := Color(0.55, 0.45, 0.30)
	for y in TS:
		for x in TS:
			var n: float = _hash2(x, y, 11)
			var t: float = 0.85 + 0.30 * n
			var c: Color = base * t
			c.a = 1.0
			img.set_pixel(x, y, c)
	return img

func _gen_rubble() -> Image:
	var img: Image = _gen_sand()
	# 4-6 dark grey chunks.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in range(rng.randi_range(4, 6)):
		var cx: int = rng.randi_range(8, TS - 8)
		var cy: int = rng.randi_range(8, TS - 8)
		var r: int = rng.randi_range(4, 9)
		var c := Color(0.32, 0.32, 0.30)
		_draw_blob(img, cx, cy, r, c, 0.85)
		# Highlight
		_draw_blob(img, cx - 1, cy - 1, max(2, r / 2), Color(0.55, 0.55, 0.50), 0.4)
	return img

func _gen_scrap() -> Image:
	var img: Image = _gen_sand()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001
	# 1-2 dark bluish metal slabs.
	for i in range(rng.randi_range(1, 2)):
		var x0: int = rng.randi_range(4, TS - 28)
		var y0: int = rng.randi_range(8, TS - 16)
		var w: int = rng.randi_range(18, 28)
		var h: int = rng.randi_range(8, 14)
		for y in range(y0, y0 + h):
			for x in range(x0, x0 + w):
				img.set_pixel(x, y, Color(0.22, 0.25, 0.30))
		# Rusty accent on top
		for x in range(x0, x0 + w):
			img.set_pixel(x, y0, Color(0.45, 0.25, 0.15))
	return img

func _gen_pit() -> Image:
	var img: Image = Image.create(TS, TS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.10, 0.08))
	# Edge gradient: lighten at the rim
	for y in TS:
		for x in TS:
			var dx: float = min(x, TS - 1 - x) / float(TS / 2)
			var dy: float = min(y, TS - 1 - y) / float(TS / 2)
			var d: float = min(dx, dy)
			var t: float = clamp(1.0 - d, 0.0, 1.0)
			var c: Color = Color(0.30, 0.22, 0.15).lerp(Color(0.12, 0.10, 0.08), 1.0 - t)
			c.a = 1.0
			img.set_pixel(x, y, c)
	return img

func _gen_swamp() -> Image:
	var img: Image = Image.create(TS, TS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.22, 0.36, 0.16))
	# Bubbly highlights
	var rng := RandomNumberGenerator.new()
	rng.seed = 7777
	for i in range(18):
		var x: int = rng.randi_range(2, TS - 3)
		var y: int = rng.randi_range(2, TS - 3)
		var r: int = rng.randi_range(1, 2)
		_draw_blob(img, x, y, r, Color(0.55, 0.75, 0.30), 0.65)
	# Dark pools
	for i in range(8):
		var x: int = rng.randi_range(4, TS - 5)
		var y: int = rng.randi_range(4, TS - 5)
		_draw_blob(img, x, y, rng.randi_range(2, 4), Color(0.10, 0.20, 0.10), 0.55)
	return img

## Elite camp floor: dark cracked concrete with rust-red hazard stripes.
## Deliberately the darkest, coldest tile in the set so a camp reads as a
## distinct arena from 3 screens away, and so the red-tinted elite standing
## on it still separates from the ground.
## Registers no physics/navigation layer (see _build_tileset) — the arena has
## to be walkable and navigable or the elite would be stuck in its own camp.
func _gen_camp() -> Image:
	var img: Image = Image.create(TS, TS, false, Image.FORMAT_RGBA8)
	var base := Color(0.16, 0.16, 0.18)
	for y in TS:
		for x in TS:
			var n: float = _hash2(x, y, 23)
			var c: Color = base * (0.85 + 0.30 * n)
			c.a = 1.0
			img.set_pixel(x, y, c)
	# Diagonal hazard stripes, rust red on the dark slab.
	var stripe := Color(0.45, 0.16, 0.12)
	for y in TS:
		for x in TS:
			if ((x + y) / 8) % 4 == 0:
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(stripe, 0.55))
	# Cracks: a few dark scratches so the slab doesn't read as flat.
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	for i in range(5):
		var cx: int = rng.randi_range(6, TS - 7)
		var cy: int = rng.randi_range(6, TS - 7)
		_draw_blob(img, cx, cy, rng.randi_range(1, 3), Color(0.07, 0.07, 0.08), 0.7)
	# Rim: lighter edge so adjacent camp tiles still show a grid, which helps
	# the player judge the arena's size while kiting.
	for i in TS:
		var edge := Color(0.28, 0.27, 0.30)
		img.set_pixel(i, 0, edge)
		img.set_pixel(i, TS - 1, edge)
		img.set_pixel(0, i, edge)
		img.set_pixel(TS - 1, i, edge)
	return img

func _draw_blob(img: Image, cx: int, cy: int, r: int, c: Color, alpha: float) -> void:	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x < 0 or y < 0 or x >= TS or y >= TS:
				continue
			var dx: float = float(x - cx)
			var dy: float = float(y - cy)
			if dx * dx + dy * dy <= float(r * r):
				var blended: Color = img.get_pixel(x, y).lerp(c, alpha)
				img.set_pixel(x, y, blended)

# --- Map painting ---

func _paint_map() -> void:
	var size: int = config.map_size_tiles
	# World (0,0) sits at cell (0,0) — no offset. Player spawns at (0,0).
	tilemap.position = Vector2.ZERO
	# Use two independent noise fields:
	#   - swamp_field: a regular simplex noise. Cells where the value falls
	#     into the bottom `swamp_density` of [-1,1] become swamp.
	#   - obstacle_field: same idea, with `rubble+scrap+pit` density. We
	#     multiply it by a "clustering" mask derived from a cellular noise
	#     so obstacles bunch up instead of scattering.
	var swamp_field: FastNoiseLite = _make_density_noise(config.seed_value, config.swamp_cluster_scale)
	var obstacle_field: FastNoiseLite = _make_density_noise(config.seed_value + 100, config.obstacle_cluster_scale)
	var cluster_mask: FastNoiseLite = _make_cluster_mask(config.seed_value + 200, config.obstacle_cluster_scale)
	# Center the noise around world origin so the spawn point sits in the
	# middle of the noise field (more interesting terrain around player).
	var half: int = size / 2
	for y in size:
		for x in size:
			var wx: int = x - half
			var wy: int = y - half
			var cell: Vector2i = Vector2i(wx, wy)
			# Spawn safety: no swamp within N tiles, no obstacles within M.
			if absi(wx) <= config.spawn_clear_radius and absi(wy) <= config.spawn_clear_radius:
				continue
			# Compute per-cell flags.
			var n_swamp: float = swamp_field.get_noise_2d(wx, wy)
			var n_obs: float = obstacle_field.get_noise_2d(wx, wy)
			var cluster: float = cluster_mask.get_noise_2d(wx, wy)
			var is_swamp: bool = _is_swamp_cell(cell, n_swamp)
			var is_obs: bool = _is_obstacle_cell(cell, n_obs, cluster)
			if is_obs and not is_swamp:
				tilemap.set_cell(0, cell, 0, _pick_obstacle_tile(cell))
			elif is_swamp:
				tilemap.set_cell(0, cell, 0, _atlas(T_SWAMP))
				swamp_cells[cell] = true
			else:
				# Explicitly paint SAND so it has visual + a tile presence.
				tilemap.set_cell(0, cell, 0, _atlas(T_SAND))

func _is_swamp_cell(cell: Vector2i, noise_val: float) -> bool:
	# Spawn safety: never put a swamp underfoot.
	var spawn_clear: int = config.spawn_no_swamp_radius
	if absi(cell.x) <= spawn_clear and absi(cell.y) <= spawn_clear:
		return false
	# Direct density gate: swamp_density = 0.05 -> 5% of cells. simplex
	# noise's [-1,1] range is unreliable for tight thresholds, so use a
	# deterministic hash on (cell.x, cell.y) against density.
	var n: float = _hash2(cell.x + 53, cell.y + 71, 11)
	return n < config.swamp_density

func _is_obstacle_cell(cell: Vector2i, noise_val: float, cluster: float) -> bool:
	var spawn_clear: int = config.spawn_clear_radius
	if absi(cell.x) <= spawn_clear and absi(cell.y) <= spawn_clear:
		return false
	var total: float = config.rubble_density + config.scrap_density + config.pit_density
	if total <= 0.0:
		return false
	# Cellular RETURN_DISTANCE: 0 = on top of a feature point, 1 = far away.
	# Use the cluster mask as a direct on/off gate — gates obstacles to
	# inside-blob regions. The actual fraction of obstacle cells vs sand
	# is tuned by `total` (the sum of obstacle densities): the lower the
	# total, the smaller the in-cluster area that ends up as an obstacle.
	# Concretely: we keep the cell as obstacle iff it's inside the blob
	# AND a deterministic hash falls below `total`.
	if cluster > 0.5:
		return false
	var n: float = _hash2(cell.x + 17, cell.y + 31, 7)
	return n < total

func _pick_obstacle_tile(cell: Vector2i) -> Vector2i:
	var total: float = config.rubble_density + config.scrap_density + config.pit_density
	if total <= 0.0:
		return _atlas(T_RUBBLE)
	var n: float = _hash2(cell.x + 1000, cell.y + 1000, 17)
	var r_share: float = config.rubble_density / total
	var s_share: float = config.scrap_density / total
	if n < r_share:
		return _atlas(T_RUBBLE)
	elif n < r_share + s_share:
		return _atlas(T_SCRAP)
	return _atlas(T_PIT)

## Pick `elite_camp_count` camp centres and carve a walkable disc at each.
##
## Camp i gets its own angular sector around the spawn point, so the camps ring
## the player instead of clumping and every requested camp actually lands.
## Rejection sampling on raw hashed coordinates was tried first and starved:
## the mutual-gap test threw away most candidates and only ~5 of 8 placed.
##
## Deterministic for a given seed: angle and radius come from `_hash2` keyed on
## (seed + camp index, attempt), so the same seed always produces the same camps.
func _place_elite_camps() -> void:
	elite_camps.clear()
	var want: int = maxi(0, config.elite_camp_count)
	if want == 0:
		return
	var size: int = config.map_size_tiles
	var half: int = size / 2
	# Stay clear of the 2-cell pit border, plus the camp radius so no camp
	# tile lands inside the band and gets overwritten by _paint_borders.
	var limit: int = half - 3 - config.elite_camp_radius_tiles
	if limit <= config.elite_camp_min_dist_tiles:
		push_warning("[TilemapBuilder] map too small for elite camps")
		return
	var gap: float = float(config.elite_camp_min_gap_tiles)
	var sector: float = TAU / float(want)
	# Worst-case angular separation between two neighbouring camps, given that
	# each may be jittered towards the other by CAMP_ANGLE_JITTER of a sector.
	var min_sep: float = sector * (1.0 - 2.0 * CAMP_ANGLE_JITTER)
	# Two camps that far apart in angle are `2*r*sin(sep/2)` apart in space, so
	# invert that for the smallest radius which still guarantees the gap. This
	# makes the gap a property of the geometry instead of something we have to
	# sample until we get lucky.
	var r_floor: float = gap / maxf(0.001, 2.0 * sin(min_sep * 0.5))
	var r_min: float = maxf(float(config.elite_camp_min_dist_tiles), r_floor)
	var r_max: float = float(limit)
	if r_min > r_max:
		push_warning("[TilemapBuilder] map too small for %d elite camps %d tiles apart" % [want, config.elite_camp_min_gap_tiles])
		return
	var min_dist_sq: int = config.elite_camp_min_dist_tiles * config.elite_camp_min_dist_tiles
	var min_gap_sq: int = config.elite_camp_min_gap_tiles * config.elite_camp_min_gap_tiles
	for i in range(want):
		var placed: bool = false
		# The geometry above makes attempt 0 valid in practice; the extra
		# attempts only matter if a config edit makes the sectors tight.
		for attempt in range(24):
			var h_ang: float = _hash2(config.seed_value + i, 613 + attempt, 41)
			var h_rad: float = _hash2(config.seed_value + i, 977 + attempt, 43)
			var ang: float = sector * (float(i) + (h_ang * 2.0 - 1.0) * CAMP_ANGLE_JITTER)
			var rad: float = lerpf(r_min, r_max, h_rad)
			var cell := Vector2i(
				clampi(roundi(cos(ang) * rad), -limit, limit),
				clampi(roundi(sin(ang) * rad), -limit, limit)
			)
			# Too close to the player's spawn at (0,0)?
			if cell.x * cell.x + cell.y * cell.y < min_dist_sq:
				continue
			# Too close to a camp we already placed? Two camps inside one
			# activation radius would spawn two elites at once.
			var too_close: bool = false
			for other in elite_camps:
				var d: Vector2i = cell - other
				if d.x * d.x + d.y * d.y < min_gap_sq:
					too_close = true
					break
			if too_close:
				continue
			elite_camps.append(cell)
			_carve_camp(cell)
			placed = true
			break
		if not placed:
			push_warning("[TilemapBuilder] could not place elite camp %d" % i)

## Paint a filled disc of CAMP tiles, replacing whatever terrain was there.
## Obstacles are overwritten (CAMP has no physics layer) and swamp bookkeeping
## is erased, so the arena is a clean walkable, navigable floor.
func _carve_camp(centre: Vector2i) -> void:
	var r: int = maxi(1, config.elite_camp_radius_tiles)
	var r_sq: int = r * r
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r_sq:
				continue
			var cell := Vector2i(centre.x + dx, centre.y + dy)
			tilemap.set_cell(0, cell, 0, _atlas(T_CAMP))
			swamp_cells.erase(cell)

func _paint_borders() -> void:
	# Edge band = pit so enemies/player can't escape. The map occupies
	# cells (-size/2 .. size/2-1, ...). We write the two outermost cells
	# on each side; spawn_clear_radius is well inside that.
	var size: int = config.map_size_tiles
	var lo: int = -size / 2
	var hi: int = size / 2 - 1
	for x in range(lo, hi + 1):
		for dy in range(2):
			var t1: Vector2i = Vector2i(x, lo + dy)
			var t2: Vector2i = Vector2i(x, hi - dy)
			tilemap.set_cell(0, t1, 0, _atlas(T_PIT))
			tilemap.set_cell(0, t2, 0, _atlas(T_PIT))
			swamp_cells.erase(t1)
			swamp_cells.erase(t2)
	for y in range(lo, hi + 1):
		for dx in range(2):
			var t1: Vector2i = Vector2i(lo + dx, y)
			var t2: Vector2i = Vector2i(hi - dx, y)
			tilemap.set_cell(0, t1, 0, _atlas(T_PIT))
			tilemap.set_cell(0, t2, 0, _atlas(T_PIT))
			swamp_cells.erase(t1)
			swamp_cells.erase(t2)

# --- Helpers ---

func _atlas(tid: int) -> Vector2i:
	return Vector2i(tid, 0)

func _square_polygon() -> PackedVector2Array:
	# 4-vertex square covering the tile, in tile-local pixels.
	return PackedVector2Array([Vector2(0, 0), Vector2(TS, 0), Vector2(TS, TS), Vector2(0, TS)])

func _square_navigation_polygon() -> NavigationPolygon:
	var np := NavigationPolygon.new()
	np.add_outline(PackedVector2Array([
		Vector2(0, 0), Vector2(TS, 0), Vector2(TS, TS), Vector2(0, TS)
	]))
	np.make_polygons_from_outlines()
	return np

func _make_density_noise(seed_val: int, scale: float) -> FastNoiseLite:
	# Plain simplex/perlin noise, range [-1, 1]. Caller thresholds the value
	# against -1 + 2*density to pick a fraction of cells.
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.seed = seed_val
	n.frequency = 1.0 / maxf(0.5, scale)
	return n

func _make_cluster_mask(seed_val: int, scale: float) -> FastNoiseLite:
	# Cellular noise returns a value in roughly [0, 1] depending on the
	# distance to the nearest feature point. Used to gate obstacles into
	# "blobs" so they cluster instead of scattering uniformly.
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.seed = seed_val
	n.frequency = 1.0 / maxf(0.5, scale)
	n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	return n

func _hash2(x: int, y: int, salt: int) -> float:
	# Cheap deterministic hash, [0,1).
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	h = (h << 13) ^ h
	var v: float = float(h & 0x7fffffff) / float(0x7fffffff)
	return v
