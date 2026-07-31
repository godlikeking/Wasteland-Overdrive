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
}

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
