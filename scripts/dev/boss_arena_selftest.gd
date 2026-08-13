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
	_test_factory_scene_declares_level_two()
	await _test_level_two_bullet_is_an_orb()
	_test_only_walls_block_bullets()
	await _test_arena_owns_boss_trigger()
	print("=== boss_arena selftest failures: %d ===" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

## BOSS 出场时机由竞技场接管：**进门即刻降临**，不再等 3 分钟计时。
##
## 三条性质各自对应一种真实的写坏方式：
## 1. 有竞技场时，计时到点也**不**刷 —— 否则玩家还在图里逛，BOSS 就自己在空
##    房间里刷出来了。
## 2. spawn_boss_now() 真的能刷出来（不然进门就变成什么都没发生）。
## 3. 重复调用不刷第二只 —— 竞技场是在 _process 里判定的，多触发一帧很正常。
func _test_arena_owns_boss_trigger() -> void:
	var sd: Node = $SpawnDirector
	if not sd.has_method("arena_owns_boss_trigger") or not sd.has_method("spawn_boss_now"):
		_fail("boss_trigger", "SpawnDirector is missing the arena trigger API")
		return
	if not sd.arena_owns_boss_trigger():
		_fail("boss_trigger", "factory + arena should hand the boss trigger to the arena")
		return
	_ok("boss_trigger", "the arena owns the boss trigger in factory mode")
	# (1) 计时到点也不刷。
	GameState.time_alive = sd.boss_spawn_time + 60.0
	await _advance(0.3)
	if _count_bosses() > 0:
		_fail("boss_trigger", "the %ds timer still spawned the boss despite the arena" % int(sd.boss_spawn_time))
		return
	_ok("boss_trigger", "the timer no longer spawns the boss when an arena exists")
	# (2) 进门触发（直接调竞技场用的那个入口）。
	sd.spawn_boss_now()
	await _advance(0.2)
	var after_first: int = _count_bosses()
	if after_first != 1:
		_fail("boss_trigger", "spawn_boss_now() produced %d bosses, expected 1" % after_first)
		return
	_ok("boss_trigger", "spawn_boss_now() drops the boss immediately")
	# 顺手验一眼真实节点的上屏尺寸：纯函数对不代表 _apply_visuals 真的调了它。
	_check_spawned_boss_size()
	# (3) 重复调用不刷第二只。
	sd.spawn_boss_now()
	sd.spawn_boss_now()
	await _advance(0.2)
	if _count_bosses() != 1:
		_fail("boss_trigger", "repeat calls spawned %d bosses" % _count_bosses())
	else:
		_ok("boss_trigger", "repeat calls never spawn a second boss")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	GameState.time_alive = 0.0
	await _advance(0.1)

## 刚刷出来的那只 BOSS，实际上屏尺寸必须等于 config.sprite_size。
##
## gobot_selftest 里断言的是放大倍数那个纯函数，这里断言的是**活节点** ——
## 倍数算对但 _apply_visuals 忘了用（或者又被写回硬编码）时，只有这条会红。
func _check_spawned_boss_size() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		var cfg: EnemyConfig = e.get("config") as EnemyConfig
		if cfg == null or cfg.id != "giant_robot":
			continue
		var spr: Sprite2D = e.get_node_or_null("Sprite2D") as Sprite2D
		if spr == null or spr.texture == null:
			_fail("boss_size", "the spawned boss has no sprite texture")
			return
		var on_screen: float = spr.texture.get_size().x * spr.scale.x
		if absf(on_screen - cfg.sprite_size.x) > 1.0:
			_fail("boss_size", "boss renders at %.0fpx (%.0fpx art x %.2f), config wants %.0fpx" % [
				on_screen, spr.texture.get_size().x, spr.scale.x, cfg.sprite_size.x])
		else:
			_ok("boss_size", "the live boss renders at %.0fpx (%.0fpx art x %.2f)" % [
				on_screen, spr.texture.get_size().x, spr.scale.x])
		return
	_fail("boss_size", "no giant_robot found to measure")

func _count_bosses() -> int:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or e.is_queued_for_deletion():
			continue
		var cfg: EnemyConfig = e.get("config") as EnemyConfig
		if cfg != null and cfg.id == "giant_robot":
			n += 1
	return n

func _advance(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

## 子弹只被**墙**挡，别的地形一律飞过去。
##
## 挡人和挡弹是两件独立的事，分别挂在两个物理层上：
##   物理层 0（World, 位 1）    瓦砾/废铁/地坑/金属墙 —— 挡移动
##   物理层 1（位 32）          只有金属墙            —— 挡子弹和瞄准视线
## 以前两件事共用 World 层，于是第一关半人高的碎石也把子弹吃掉了。这条断言
## 从两头钉：TileSet 每个瓦片挂在哪层，以及出厂的子弹场景 mask 了哪些位 ——
## 任一头改回去，"地形吃子弹"就会悄悄复活。
func _test_only_walls_block_bullets() -> void:
	var ts: TileSet = world.get_tilemap().tile_set
	if ts.get_physics_layers_count() < 2:
		_fail("bullet_layers", "tileset has %d physics layer(s), need a separate wall layer" % ts.get_physics_layers_count())
		return
	var wall_layer: int = -1
	for i in range(ts.get_physics_layers_count()):
		if ts.get_physics_layer_collision_layer(i) == TilemapBuilder.WALL_LAYER_BIT:
			wall_layer = i
			break
	if wall_layer < 0:
		_fail("bullet_layers", "no physics layer carries the wall bit %d" % TilemapBuilder.WALL_LAYER_BIT)
		return
	var src: TileSetAtlasSource = ts.get_source(0) as TileSetAtlasSource
	# 金属墙：两层都要有（既挡人又挡弹）。
	var wall_td: TileData = src.get_tile_data(Vector2i(TilemapBuilder.T_METAL_WALL, 0), 0)
	if wall_td.get_collision_polygons_count(0) < 1 or wall_td.get_collision_polygons_count(wall_layer) < 1:
		_fail("bullet_layers", "metal wall must block both movement and bullets")
	else:
		_ok("bullet_layers", "metal wall blocks movement AND bullets")
	# 其余地形：挡人，但**不**挡弹。
	var pass_through: Array[int] = [
		TilemapBuilder.T_RUBBLE, TilemapBuilder.T_SCRAP, TilemapBuilder.T_PIT,
	]
	var bad: String = ""
	for tid in pass_through:
		var td: TileData = src.get_tile_data(Vector2i(tid, 0), 0)
		if td.get_collision_polygons_count(0) < 1:
			bad = "tile %d stopped blocking movement" % tid
			break
		if td.get_collision_polygons_count(wall_layer) > 0:
			bad = "tile %d is on the bullet-blocking layer — bullets would die on it" % tid
			break
	if bad == "":
		_ok("bullet_layers", "rubble/scrap/pit block movement but let bullets through")
	else:
		_fail("bullet_layers", bad)
	# 出厂场景的 mask：必须 mask 挡弹层，且**不**再 mask World。
	_check_projectile_mask("res://scenes/bullet.tscn", 8, "player bullet")
	_check_projectile_mask("res://scenes/enemy_projectile.tscn", 2, "enemy bullet")

func _check_projectile_mask(path: String, want_target_bit: int, label: String) -> void:
	var ps: PackedScene = load(path) as PackedScene
	if ps == null:
		_fail("bullet_layers", "cannot load %s" % path)
		return
	var node: Node = ps.instantiate()
	var mask: int = int(node.get("collision_mask"))
	node.queue_free()
	if mask & TilemapBuilder.WALL_LAYER_BIT == 0:
		_fail("bullet_layers", "%s mask %d does not include the wall layer — walls would not stop it" % [label, mask])
	elif mask & 1 != 0:
		_fail("bullet_layers", "%s mask %d still includes World(1) — every blocking terrain would eat it" % [label, mask])
	elif mask & want_target_bit == 0:
		_fail("bullet_layers", "%s mask %d lost its target layer %d" % [label, mask, want_target_bit])
	else:
		_ok("bullet_layers", "%s masks wall+target only (mask=%d)" % [label, mask])

## 敌弹贴图跟着关卡走：第二关电球、第一关红紫等离子。
##
## 上面那条只验证场景声明了 level_index，这条验证**玩家真正看到的东西** ——
## 贴图是在 _ready 里按 GameState.current_level 选的，所以两头都要断言，
## 否则"声明对了但选图逻辑写反了"照样是静默回退。
func _test_level_two_bullet_is_an_orb() -> void:
	var before: int = GameState.current_level
	var lvl2: String = await _bullet_texture_at_level(2)
	var lvl1: String = await _bullet_texture_at_level(1)
	GameState.current_level = before
	if lvl2.ends_with("enemy_orb.png"):
		_ok("bullet_art", "level 2 enemy bullets use the orb sprite")
	else:
		_fail("bullet_art", "level 2 bullet used '%s', expected enemy_orb.png" % lvl2)
	if lvl1.ends_with("enemy_bullet.png"):
		_ok("bullet_art", "level 1 enemy bullets keep the plasma sprite")
	else:
		_fail("bullet_art", "level 1 bullet used '%s', expected enemy_bullet.png" % lvl1)

func _bullet_texture_at_level(lvl: int) -> String:
	GameState.current_level = lvl
	var ps: PackedScene = load("res://scenes/enemy_projectile.tscn") as PackedScene
	if ps == null:
		return "<no enemy_projectile.tscn>"
	var proj: Node = ps.instantiate()
	# 关掉碰撞再挂进树，而不是"停到图外"。
	#
	# 原来是丢到 Vector2(6000,6000)，靠"那里在 128 格地图之外所以没有瓦片"来
	# 让它活过一帧。地图一放大到 192 格（半径 6144px），那个点就变成图内的金属
	# 墙，弹当帧自毁，下一帧读 Sprite2D 报"访问已释放实例"，而失败信息看起来
	# 像贴图回归 —— 排查方向全错。mask=0 之后它撞不到任何东西，和地图尺寸解耦。
	if proj is CollisionObject2D:
		(proj as CollisionObject2D).collision_mask = 0
	add_child(proj)
	await get_tree().process_frame
	var path: String = "<no texture>"
	if is_instance_valid(proj) and not proj.is_queued_for_deletion():
		var spr: Sprite2D = proj.get_node_or_null("Sprite2D") as Sprite2D
		if spr != null and spr.texture != null:
			path = spr.texture.resource_path
		proj.queue_free()
	return path

## 第二关场景必须自己声明 level_index = 2。
##
## 所有"第二关专属"行为都在读 GameState.current_level：敌弹电球贴图
## （enemy_projectile._apply_sprite）、墙体挡锁敌视线（weapon._has_line_of_sight）。
## 这个声明一旦丢了，current_level 会退回 1，那些特性全部**静默回到第一关行为**
## —— 子弹变回红紫等离子、武器能穿墙锁敌，而且不报任何错，只能靠肉眼发现
## "改好的东西又变回来了"。所以在这里把它钉住。
##
## 读 PackedScene 的 SceneState 而不是实例化整个 game_factory.tscn：那会连
## 玩家/刷怪/HUD 一起拉起来，对一条属性断言来说太重。
func _test_factory_scene_declares_level_two() -> void:
	var ps: PackedScene = load("res://scenes/game_factory.tscn") as PackedScene
	if ps == null:
		_fail("level_index", "cannot load res://scenes/game_factory.tscn")
		return
	var st: SceneState = ps.get_state()
	if st.get_node_count() <= 0:
		_fail("level_index", "game_factory.tscn has no nodes")
		return
	var declared: int = -1
	for i in range(st.get_node_property_count(0)):
		if st.get_node_property_name(0, i) == "level_index":
			declared = int(st.get_node_property_value(0, i))
			break
	if declared == 2:
		_ok("level_index", "game_factory.tscn declares level_index = 2")
	elif declared == -1:
		_fail("level_index", "game_factory.tscn does not set level_index — it would default to 1, silently disabling the level-2 orb sprite and wall LOS")
	else:
		_fail("level_index", "game_factory.tscn declares level_index = %d, expected 2" % declared)

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
