extends Resource
## Procedural wasteland world config. Consumed by World/TilemapBuilder to
## generate the TileSet + paint the level. Editable from the inspector and
## stable across runs when the seed is fixed.

class_name WastelandConfig

# World dimensions (in tiles, square map).
@export var map_size_tiles: int = 64
@export var tile_size: int = 64

# Deterministic seed for the noise. Same seed -> same map.
@export var seed_value: int = 1337

# Visual tile IDs (must match TilemapBuilder.TileId enum).
enum TileId {
	SAND = 0,
	RUBBLE = 1,
	SCRAP = 2,
	PIT = 3,
	SWAMP = 4,
	CAMP = 5,
	METAL_WALL = 6,
	FACTORY_FLOOR = 7,
}

## 地图风格：0 = 废土（噪声地形），1 = 机器人工厂（BSP 房间）。
@export var map_style: int = 0

# 房间风格参数（map_style = 1 时使用）
## 房间网格行列数。128 格 / 8 = 每格 16 格。
@export var room_grid: int = 8
## 房间最小边长（格）。
@export var room_min_size: int = 6
## 走廊宽度（格）。
@export var corridor_width: int = 2

# Distribution probabilities for a non-sand tile.
# Sum of these three should be <= 1.0; remaining share defaults to SAND.
@export_range(0.0, 0.5, 0.005) var rubble_density: float = 0.05
@export_range(0.0, 0.5, 0.005) var scrap_density: float = 0.025
@export_range(0.0, 0.5, 0.005) var pit_density: float = 0.025
@export_range(0.0, 0.5, 0.005) var swamp_density: float = 0.05

# Per-tile physics: anything in PHYSICAL_TILES blocks movement.
const PHYSICAL_TILES: Array = [TileId.RUBBLE, TileId.SCRAP, TileId.PIT]

# Cells around (0,0) that must be left clear (sand) for player spawn safety.
@export var spawn_clear_radius: int = 5
# And no swamp within this many tiles of spawn.
@export var spawn_no_swamp_radius: int = 8

# Toxic swamp tuning.
@export var swamp_slow_factor: float = 0.5       # 0..1; lower = slower
@export var swamp_damage_per_tick: float = 1.0
@export var swamp_tick_interval: float = 0.5

# Worley / FBM noise blend. Higher = more clustered blobs.
@export var swamp_cluster_scale: float = 0.18    # smaller => bigger blobs
@export var obstacle_cluster_scale: float = 0.22

# --- Elite camps (精英营地) ---
# Fixed arenas scattered over the map, painted with the CAMP tile so the
# player can see them from a distance. EliteCampDirector spawns an elite at
# each camp centre when the player gets close. Placement is deterministic
# for a given `seed_value`, same as the terrain.
@export var elite_camp_count: int = 6
# Radius of the cleared camp disc, in tiles. 3 => a 7x7 arena, big enough to
# kite a 48px elite inside without clipping the surrounding terrain.
@export var elite_camp_radius_tiles: int = 3
# Camps must sit at least this far from spawn (0,0), so the player never
# starts on top of one.
@export var elite_camp_min_dist_tiles: int = 14
# And this far from each other. This MUST stay above
# EliteCampDirector.activation_radius (700px = ~11 tiles), otherwise one
# approach would trigger two camps and drop two elites on the player at once.
@export var elite_camp_min_gap_tiles: int = 14
