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
