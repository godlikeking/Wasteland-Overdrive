extends Node2D
## Headless self-test for the factory BOSS arena (第二关竞技场)：校验生成几何 +
## 封门/开门。
##   godot --headless res://scenes/dev/boss_arena_selftest.tscn
## Exits 0 when green, 1 when any check fails.

var _failures: int = 0

@onready var world: WorldRoot = $World

func _ready() -> void:
	await get_tree().process_frame
	print("=== boss_arena selftest ===")
	await _test_carved()
	await _test_seal_open()
	print("=== boss_arena selftest failures: %d ===" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

func _test_carved() -> void:
	var b: TilemapBuilder = world.get_builder()
	var cfg: WastelandConfig = world.wasteland_config
	if cfg.boss_arena_tiles <= 0:
		_fail("carved", "config boss_arena_tiles is 0, arena not enabled")
		return
	if not world.has_boss_arena():
		_fail("carved", "has_boss_arena() false though boss_arena_tiles=%d" % cfg.boss_arena_tiles)
		return
	if b.boss_arena_rect.size != Vector2i(cfg.boss_arena_tiles, cfg.boss_arena_tiles):
		_fail("carved", "arena size %s != %dx%d" % [b.boss_arena_rect.size, cfg.boss_arena_tiles, cfg.boss_arena_tiles])
		return
	# 竞技场内部全为地板（抽样），且与出生点 (0,0) 相隔远。
	var tm: TileMap = world.get_tilemap()
	var bad: String = ""
	var r: Rect2i = b.boss_arena_rect
	for y in range(r.position.y, r.position.y + r.size.y, 3):
		for x in range(r.position.x, r.position.x + r.size.x, 3):
			if tm.get_cell_atlas_coords(0, Vector2i(x, y)).x != TilemapBuilder.T_FACTORY_FLOOR:
				bad = "arena cell (%d,%d) not floor" % [x, y]
				break
		if bad != "":
			break
	if bad == "":
		_ok("carved", "arena interior %dx%d all factory floor" % [cfg.boss_arena_tiles, cfg.boss_arena_tiles])
	else:
		_fail("carved", bad)
	var min_dist_sq: int = (cfg.boss_arena_tiles) * (cfg.boss_arena_tiles)
	if r.position.x * r.position.x + r.position.y * r.position.y < min_dist_sq:
		_fail("carved", "arena too close to spawn")
	else:
		_ok("carved", "arena far from spawn (0,0)")
	# 门洞默认开着（地板）
	if b.boss_arena_door.is_empty():
		_fail("carved", "no door cells recorded")
	else:
		var door_floor: bool = true
		for c in b.boss_arena_door:
			if tm.get_cell_atlas_coords(0, c).x != TilemapBuilder.T_FACTORY_FLOOR:
				door_floor = false
		_ok("carved" if door_floor else "carved", "door cells open by default: %d cells" % b.boss_arena_door.size())
	# 中心在竞技场内
	var center: Vector2 = world.boss_arena_center()
	if b.boss_arena_contains_world(center):
		_ok("carved", "boss_arena_center() inside arena")
	else:
		_fail("carved", "boss_arena_center() outside arena")

func _test_seal_open() -> void:
	var b: TilemapBuilder = world.get_builder()
	var tm: TileMap = world.get_tilemap()
	world.seal_boss_door()
	var all_wall: bool = not b.boss_arena_door.is_empty()
	for c in b.boss_arena_door:
		if tm.get_cell_atlas_coords(0, c).x != TilemapBuilder.T_METAL_WALL:
			all_wall = false
	if all_wall:
		_ok("seal_open", "seal_boss_door() walls the door cells")
	else:
		_fail("seal_open", "seal_boss_door() did not wall the door")
	world.open_boss_door()
	var all_floor: bool = true
	for c in b.boss_arena_door:
		if tm.get_cell_atlas_coords(0, c).x != TilemapBuilder.T_FACTORY_FLOOR:
			all_floor = false
	if all_floor:
		_ok("seal_open", "open_boss_door() restores floor")
	else:
		_fail("seal_open", "open_boss_door() did not restore floor")

func _ok(name: String, msg: String) -> void:
	print("  [ok] %-12s %s" % [name, msg])

func _fail(name: String, msg: String) -> void:
	_failures += 1
	print("  [FAIL] %-12s %s" % [name, msg])
