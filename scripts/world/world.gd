extends Node2D
## Owns the procedural wasteland world: a TileMap built at runtime from
## a WastelandConfig resource. The TileMap serves as both physics body
## (layer 1 = World) and navigation source (collected automatically by
## the World2D navigation map). Enemies will use NavigationAgent2D in a
## later iteration; for now they still move via straight-line steering.

class_name WorldRoot

@export var wasteland_config: WastelandConfig

var tilemap: TileMap
var builder: TilemapBuilder

func _ready() -> void:
	add_to_group("world")
	if wasteland_config == null:
		push_error("[World] missing WastelandConfig")
		return
	# TileMap is created in code so the .tscn stays clean.
	tilemap = TileMap.new()
	tilemap.name = "TileMap"
	add_child(tilemap)
	builder = TilemapBuilder.new()
	builder.name = "TilemapBuilder"
	add_child(builder)
	builder.build(tilemap, wasteland_config)
	print("[World] ready, %dx%d px" % [
		wasteland_config.map_size_tiles * wasteland_config.tile_size,
		wasteland_config.map_size_tiles * wasteland_config.tile_size,
	])

func get_builder() -> TilemapBuilder:
	return builder

func get_tilemap() -> TileMap:
	return tilemap

## Elite camp centres in world space. Empty until the builder has run.
func camp_centers() -> Array[Vector2]:
	if builder == null:
		return []
	return builder.camp_centers()

## World rectangle the map covers. Zero-size until the builder has run, which
## reads as "everything is out of bounds" — so callers must treat a zero-size
## rect as "no map yet" rather than trusting it. See OutOfBounds, which skips
## its whole tick while the rect is empty.
func map_rect() -> Rect2:
	if builder == null:
		return Rect2()
	return builder.map_rect()

## Pixels outside the map, 0.0 when inside. See TilemapBuilder for the semantics;
## this forwarder exists so gameplay code can ask the "world" group directly
## instead of reaching through get_builder().
func out_of_bounds_depth(world_pos: Vector2) -> float:
	if builder == null:
		return 0.0
	return builder.out_of_bounds_depth(world_pos)

## True when the tile under `world_pos` blocks movement (has a collision polygon).
## Used by the spawn director so enemies never spawn inside a factory wall.
func is_solid(world_pos: Vector2) -> bool:
	if builder == null:
		return false
	return builder.is_solid(world_pos)

# --- BOSS 竞技场转发（第二关） ---

func has_boss_arena() -> bool:
	return builder != null and builder.has_boss_arena()

func boss_arena_center() -> Vector2:
	return builder.boss_arena_center()

func boss_arena_world_rect() -> Rect2:
	return builder.boss_arena_world_rect()

func boss_arena_contains(pos: Vector2) -> bool:
	if builder == null:
		return false
	return builder.boss_arena_contains_world(pos)

func seal_boss_door() -> void:
	if builder != null:
		builder.seal_boss_door()

func open_boss_door() -> void:
	if builder != null:
		builder.open_boss_door()
