extends Node
## Procedural TileSet + map generator. Builds a 6-tile wasteland TileSet at
## runtime (sandy ground + rubble + scrap metal + pit + toxic swamp + elite
## camp) and paints a `map_size_tiles` square map. Exposes `swamp_cells` so
## player/enemy can look up "am I in a swamp" without colliding with it (swamp is
## non-blocking), and `elite_camps` so EliteCampDirector knows where the arenas
## are.
##
## The map edge is NOT walled. There used to be a 2-cell pit band around the
## whole map so nothing could escape; it is gone on purpose. A wall you can walk
## up to and lean on teaches the player that the edge is a safe place to kite
## against. Instead the map simply ends: `map_rect()` / `out_of_bounds_depth()`
## define where, and the OutOfBounds component on the player turns "outside" into
## escalating damage. The consequence lives in one place instead of being baked
## into terrain.
##
## Performance: paints map_size_tiles² cells once at _ready (16384 at 128).
## The 6 sub-textures are 64x64 each, generated via per-pixel loops.

class_name TilemapBuilder

const TS := 64                       # tile pixel size

# --- Tile IDs (match WastelandConfig.TileId) ---
const T_SAND := 0
const T_RUBBLE := 1
const T_SCRAP := 2
const T_PIT := 3
const T_SWAMP := 4
const T_CAMP := 5
const T_METAL_WALL := 6
const T_FACTORY_FLOOR := 7

# Atlased tileset: 8 columns x 1 row, each 64x64.
const ATLAS_COLS := 8
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
	if config.map_style == 1:
		_paint_rooms()
	else:
		_paint_map()
	# Camps come last so they can carve obstacles/swamp out of their arena. There
	# is no border pass any more (see the class docs), so nothing overwrites them.
	_place_elite_camps()
	print("[TilemapBuilder] %dx%d map painted. Swamp cells: %d, elite camps: %d" % [
		config.map_size_tiles, config.map_size_tiles, swamp_cells.size(), elite_camps.size()
	])

func is_swamp(world_pos: Vector2) -> bool:
	var cell: Vector2i = tilemap.local_to_map(tilemap.to_local(world_pos))
	return swamp_cells.has(cell)

## World-space rectangle the map covers.
##
## Cells run (-size/2 .. size/2-1) on both axes and cell (x, y) occupies pixels
## (x*TS .. x*TS+TS), so the rect starts at -size/2*TS and is size*TS wide. The
## TileMap sits at the origin (`_paint_map` pins `tilemap.position`), so map
## space and world space coincide.
func map_rect() -> Rect2:
	var size: int = config.map_size_tiles if config != null else 0
	var half: float = float(size / 2) * float(TS)
	return Rect2(Vector2(-half, -half), Vector2(float(size) * float(TS), float(size) * float(TS)))

## How far outside `map_rect()` `world_pos` is, in pixels; 0.0 when inside.
##
## Returns a DISTANCE rather than a bool on purpose: the HUD warning has to be
## able to fade in with how far out you are, and the damage ramp reads more
## naturally as "deeper = worse". Diagonal exits use the true euclidean distance
## to the rect, so cutting a corner is not cheaper than crossing an edge.
func out_of_bounds_depth(world_pos: Vector2) -> float:
	var r: Rect2 = map_rect()
	var dx: float = maxf(maxf(r.position.x - world_pos.x, 0.0),
		world_pos.x - (r.position.x + r.size.x))
	var dy: float = maxf(maxf(r.position.y - world_pos.y, 0.0),
		world_pos.y - (r.position.y + r.size.y))
	if dx <= 0.0 and dy <= 0.0:
		return 0.0
	return Vector2(dx, dy).length()

## Outermost cell index an elite camp centre may use.
##
## Single source of truth, shared with elite_camp_selftest: the formula used to
## be written out in both places, so changing one silently left the other
## asserting the old geometry. One cell of slack keeps a camp disc from hanging
## off the map edge into the out-of-bounds zone.
func camp_placement_limit() -> int:
	if config == null:
		return 0
	return config.map_size_tiles / 2 - 1 - config.elite_camp_radius_tiles

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
		var td: TileData = atlas.get_tile_data(at, 0)
		if td == null:
			continue
		# Per-tile physics: blockers (rubble, scrap, pit, metal wall).
		if tid == T_RUBBLE or tid == T_SCRAP or tid == T_PIT or tid == T_METAL_WALL:
			td.set_collision_polygons_count(0, 1)
			td.set_collision_polygon_points(0, 0, _square_polygon())
		# Per-tile navigation: **walkable** tiles get nav polygons — the
		# navigation mesh is the FLOOR, not the walls. Godot 4 tile nav
		# polygons mark where agents may walk; putting them on blockers made
		# the navmesh cover only obstacle cells (inverted). Walkable tiles:
		# sand / swamp / camp / factory floor.
		if tid == T_SAND or tid == T_SWAMP or tid == T_CAMP or tid == T_FACTORY_FLOOR:
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
	# Column 6: factory metal wall
	_paint_into(img, 6, _gen_metal_wall)
	# Column 7: factory floor plate
	_paint_into(img, 7, _gen_factory_floor)
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

## 未来科幻工厂墙：暗色船体钢板 + 面板接缝 + 顶边青色能量条 + 指示灯。
## 视觉上必须是"墙"——比地板更黑、顶边一条冷光描边读作"高能舱壁"，
## 和废土的暖锈墙拉开代差。物理阻挡由 _build_tileset 的碰撞多边形负责。
func _gen_metal_wall() -> Image:
	var img: Image = Image.create(TS, TS, false, Image.FORMAT_RGBA8)
	var base := Color(0.09, 0.11, 0.15)
	var seam := Color(0.17, 0.21, 0.27)
	var panel := Color(0.13, 0.16, 0.21)
	for y in TS:
		for x in TS:
			var n: float = _hash2(x, y, 23)
			var c: Color = base * (0.88 + 0.34 * n)
			# 面板接缝：每 16px 一条略亮的横缝，读作装配钢板而非整块墙。
			if y % 16 == 0:
				c = c.lerp(seam, 0.55)
			# 垂直方向每两块一个淡色面板微差，避免整墙平涂。
			elif ((x / 16) + (y / 16)) % 2 == 0:
				c = c.lerp(panel, 0.5)
			c.a = 1.0
			img.set_pixel(x, y, c)
	# 顶边青色能量条：双层渐冷光，读作"通电的舱壁边缘"。
	var glow := Color(0.18, 0.95, 1.0)
	for i in TS:
		img.set_pixel(i, 0, glow)
		img.set_pixel(i, 1, glow.lerp(base, 0.5))
		img.set_pixel(i, 2, glow.lerp(base, 0.78))
	# 四个角：淡青色指示灯（取代旧铆钉，科技感）。
	for px in [6, TS - 7]:
		for py in [6, TS - 7]:
			_draw_blob(img, px, py, 1, Color(0.35, 0.9, 1.0), 0.7)
	return img

## 未来科幻工厂地板：水泥金属地板 —— 灰水泥基底 + 预制板接缝 + 金属加强筋条。
## 视觉上必须是"能走的地"：比墙更亮、偏中性灰，暖色敌人（红/橙/紫）站上去
## 对比够。导航多边形由 _build_tileset 提供。
func _gen_factory_floor() -> Image:
	var img: Image = Image.create(TS, TS, false, Image.FORMAT_RGBA8)
	var base := Color(0.40, 0.42, 0.46)   # 水泥灰
	var seam := Color(0.26, 0.27, 0.30)   # 面板接缝
	for y in TS:
		for x in TS:
			var n: float = _hash2(x, y, 29)
			var c: Color = base * (0.9 + 0.22 * n)
			# 16px 网格接缝，读作预制水泥板。
			if x % 16 == 0 or y % 16 == 0:
				c = c.lerp(seam, 0.55)
			c.a = 1.0
			img.set_pixel(x, y, c)
	# 横向金属加强筋：两条稍亮的钢条，读作预埋的金属增强带。
	for row in [10, 42]:
		for i in TS:
			img.set_pixel(i, row, Color(0.52, 0.56, 0.60).lerp(base, 0.25))
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

## 第二关：机器人工厂 —— BSP 房间分割。
##
## 把地图切成 room_grid × room_grid 的网格，每个格子递归二分出小房间，
## 房间之间用走廊相连，走廊宽 corridor_width 格（保证敌人能走）。
## 墙壁用 T_METAL_WALL（物理阻挡、不可走），地板用 T_FACTORY_FLOOR
## （可走、有导航多边形）。
##
## 关键约束：
## - 玩家出生点 (0,0) 周围 spawn_clear_radius 格必须清空（不能生在水箱里）
## - 走廊宽度 >= 2 格：NavigationAgent 的 agent 半径约 12px = 0.19 格，
##   1 格走廊太窄，拐角会卡住。
func _paint_rooms() -> void:
	var size: int = config.map_size_tiles
	tilemap.position = Vector2.ZERO
	var half: int = size / 2

	# 先全图铺墙，再挖房间和走廊 —— 墙就是"没被挖掉的地"。
	for y in range(-half, half):
		for x in range(-half, half):
			tilemap.set_cell(0, Vector2i(x, y), 0, _atlas(T_METAL_WALL))

	# 网格分房间：每格内随机内缩出一个房间矩形。
	var grid: int = maxi(2, config.room_grid)
	var cell_w: int = size / grid
	var rooms: Array[Rect2i] = []
	for gy in range(grid):
		for gx in range(grid):
			var x0: int = gx * cell_w - half
			var y0: int = gy * cell_w - half
			var inset: int = maxi(1, cell_w / 4)
			var rx0: int = x0 + inset
			var ry0: int = y0 + inset
			var rx1: int = x0 + cell_w - 1 - inset
			var ry1: int = y0 + cell_w - 1 - inset
			if rx1 - rx0 < config.room_min_size:
				rx1 = rx0 + config.room_min_size - 1
			if ry1 - ry0 < config.room_min_size:
				ry1 = ry0 + config.room_min_size - 1
			rooms.append(Rect2i(rx0, ry0, rx1 - rx0 + 1, ry1 - ry0 + 1))

	# 房间内挖空成地板。
	for r in rooms:
		_paint_rect(r, T_FACTORY_FLOOR)

	# 走廊：每对相邻房间中心连一条 L 形走廊（先横后竖），宽 corridor_width。
	var cw: int = maxi(1, config.corridor_width)
	for gy in range(grid):
		for gx in range(grid):
			var idx: int = gy * grid + gx
			var room: Rect2i = rooms[idx]
			var cx: int = room.get_center().x
			var cy: int = room.get_center().y
			# 连右侧邻居
			if gx + 1 < grid:
				var other: Rect2i = rooms[gy * grid + gx + 1]
				var ox: int = other.get_center().x
				var oy: int = other.get_center().y
				_carve_corridor(cx, cy, ox, oy, cw)
			# 连下方邻居
			if gy + 1 < grid:
				var other: Rect2i = rooms[(gy + 1) * grid + gx]
				var ox: int = other.get_center().x
				var oy: int = other.get_center().y
				_carve_corridor(cx, cy, ox, oy, cw)

	# 出生点安全区：清掉周围 spawn_clear_radius 格的墙。
	var clear: int = config.spawn_clear_radius
	for y in range(-clear, clear + 1):
		for x in range(-clear, clear + 1):
			tilemap.set_cell(0, Vector2i(x, y), 0, _atlas(T_FACTORY_FLOOR))

## 房间内铺满某一种瓦片（不覆盖已存在的非地板格）。
func _paint_rect(r: Rect2i, tid: int) -> void:
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			tilemap.set_cell(0, Vector2i(x, y), 0, _atlas(tid))

## L 形走廊：先沿 X 走到底再沿 Y 走，宽 cw 格。
func _carve_corridor(x0: int, y0: int, x1: int, y1: int, cw: int) -> void:
	var w: int = cw / 2
	for y in range(y0 - w, y0 + w + 1):
		for x in range(mini(x0, x1), maxi(x0, x1) + 1):
			tilemap.set_cell(0, Vector2i(x, y), 0, _atlas(T_FACTORY_FLOOR))
	for x in range(x1 - w, x1 + w + 1):
		for y in range(mini(y0, y1), maxi(y0, y1) + 1):
			tilemap.set_cell(0, Vector2i(x, y), 0, _atlas(T_FACTORY_FLOOR))

## 世界坐标下该格是否阻挡（供生成点/子弹/寻路查询）。
func is_solid(world_pos: Vector2) -> bool:
	if tilemap == null:
		return false
	var cell: Vector2i = tilemap.local_to_map(tilemap.to_local(world_pos))
	var coords: Vector2i = tilemap.get_cell_atlas_coords(0, cell)
	if coords.x < 0:
		return false
	var src: TileSetAtlasSource = tilemap.tile_set.get_source(0) as TileSetAtlasSource
	if src == null:
		return false
	var td: TileData = src.get_tile_data(coords, 0)
	if td == null:
		return false
	return td.get_collision_polygons_count(0) > 0

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
	var limit: int = camp_placement_limit()
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

# --- Helpers ---

func _atlas(tid: int) -> Vector2i:
	return Vector2i(tid, 0)

func _square_polygon() -> PackedVector2Array:
	# Godot 4 TileData 碰撞多边形坐标是 tile-local、以格子中心为原点，不是
	# 左上角。所以 (-TS/2, -TS/2) … (TS/2, TS/2) 才正好盖住整格纹理；
	# 以前 (0,0) … (TS,TS) 向右下偏移了半格 —— 碰撞体在纹理下面，踩上去才
	# 被挡住，看起来就是"墙体阻挡效果在图片下面"。
	var h: float = float(TS) * 0.5
	return PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])

func _square_navigation_polygon() -> NavigationPolygon:
	var h: float = float(TS) * 0.5
	var np := NavigationPolygon.new()
	np.add_outline(PackedVector2Array([
		Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)
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
