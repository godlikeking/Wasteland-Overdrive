extends Node
## Procedural TileSet + map generator. Builds a 5-tile wasteland TileSet at
## runtime (sandy ground + rubble + scrap metal + pit + toxic swamp) and
## paints a 64x64 map. Exposes `swamp_cells` so player/enemy can look up
## "am I in a swamp" without colliding with it (swamp is non-blocking).
##
## Performance: paints ~4096 cells once at _ready. The 5 sub-textures are
## 64x64 each, generated via per-pixel loops; under 30ms on a modest CPU.

class_name TilemapBuilder

const TS := 64                       # tile pixel size

# --- Tile IDs (match WastelandConfig.TileId) ---
const T_SAND := 0
const T_RUBBLE := 1
const T_SCRAP := 2
const T_PIT := 3
const T_SWAMP := 4

# Atlased tileset: 5 columns x 1 row, each 64x64.
const ATLAS_COLS := 5
const ATLAS_W := TS * ATLAS_COLS
const ATLAS_H := TS

var config: WastelandConfig
var tilemap: TileMap
var swamp_cells: Dictionary = {}     # Vector2i -> true

# --- Public API ---

func build(p_tilemap: TileMap, p_config: WastelandConfig) -> void:
	tilemap = p_tilemap
	config = p_config
	if tilemap == null or config == null:
		push_error("[TilemapBuilder] missing tilemap or config")
		return
	_build_tileset()
	_paint_map()
	_paint_borders()
	print("[TilemapBuilder] %dx%d map painted. Swamp cells: %d" % [
		config.map_size_tiles, config.map_size_tiles, swamp_cells.size()
	])

func is_swamp(world_pos: Vector2) -> bool:
	var cell: Vector2i = tilemap.local_to_map(tilemap.to_local(world_pos))
	return swamp_cells.has(cell)

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

func _draw_blob(img: Image, cx: int, cy: int, r: int, c: Color, alpha: float) -> void:
	for y in range(cy - r, cy + r + 1):
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
	# Center the map so world origin is in the middle of the level.
	var offset: Vector2i = Vector2i(-size / 2, -size / 2)
	tilemap.position = Vector2(offset) * TS
	# Use two independent noise fields:
	#   - swamp_field: a regular simplex noise. Cells where the value falls
	#     into the bottom `swamp_density` of [-1,1] become swamp.
	#   - obstacle_field: same idea, with `rubble+scrap+pit` density. We
	#     multiply it by a "clustering" mask derived from a cellular noise
	#     so obstacles bunch up instead of scattering.
	var swamp_field: FastNoiseLite = _make_density_noise(config.seed_value, config.swamp_cluster_scale)
	var obstacle_field: FastNoiseLite = _make_density_noise(config.seed_value + 100, config.obstacle_cluster_scale)
	var cluster_mask: FastNoiseLite = _make_cluster_mask(config.seed_value + 200, config.obstacle_cluster_scale)
	for y in size:
		for x in size:
			var cell: Vector2i = Vector2i(x - size / 2, y - size / 2)
			# Spawn safety: no swamp within N tiles, no obstacles within M.
			if absi(cell.x) <= config.spawn_clear_radius and absi(cell.y) <= config.spawn_clear_radius:
				continue
			# Compute per-cell flags.
			var n_swamp: float = swamp_field.get_noise_2d(x, y)
			var n_obs: float = obstacle_field.get_noise_2d(x, y)
			var cluster: float = cluster_mask.get_noise_2d(x, y)
			var is_swamp: bool = _is_swamp_cell(cell, n_swamp)
			var is_obs: bool = _is_obstacle_cell(cell, n_obs, cluster)
			if is_obs and not is_swamp:
				tilemap.set_cell(0, cell, 0, _pick_obstacle_tile(cell))
			elif is_swamp:
				tilemap.set_cell(0, cell, 0, _atlas(T_SWAMP))
				swamp_cells[cell] = true
			# else: leave as SAND (tile id 0, default; nothing to set)

func _is_swamp_cell(cell: Vector2i, noise_val: float) -> bool:
	# Spawn safety: never put a swamp underfoot.
	var spawn_clear: int = config.spawn_no_swamp_radius
	if absi(cell.x) <= spawn_clear and absi(cell.y) <= spawn_clear:
		return false
	# density = 0.05 -> bottom 5% of [-1,1] range, threshold = -0.90.
	var thr: float = -1.0 + 2.0 * config.swamp_density
	return noise_val < thr

func _is_obstacle_cell(cell: Vector2i, noise_val: float, cluster: float) -> bool:
	var spawn_clear: int = config.spawn_clear_radius
	if absi(cell.x) <= spawn_clear and absi(cell.y) <= spawn_clear:
		return false
	var total: float = config.rubble_density + config.scrap_density + config.pit_density
	if total <= 0.0:
		return false
	# Cluster > 0.3 = inside a "potential obstacle blob". Without clustering
	# we'd just have a flat Poisson scatter; the cluster mask groups them.
	if cluster < 0.3:
		return false
	var thr: float = -1.0 + 2.0 * total
	return noise_val < thr

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

func _paint_borders() -> void:
	# Edge band = pit so enemies/player can't escape.
	var size: int = config.map_size_tiles
	for x in range(-size / 2, size / 2):
		for dy in range(2):
			var t1: Vector2i = Vector2i(x, -size / 2 + dy)
			var t2: Vector2i = Vector2i(x, size / 2 - 1 - dy)
			tilemap.set_cell(0, t1, 0, _atlas(T_PIT))
			tilemap.set_cell(0, t2, 0, _atlas(T_PIT))
			swamp_cells.erase(t1)
			swamp_cells.erase(t2)
	for y in range(-size / 2, size / 2):
		for dx in range(2):
			var t1: Vector2i = Vector2i(-size / 2 + dx, y)
			var t2: Vector2i = Vector2i(size / 2 - 1 - dx, y)
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
