extends Node2D
## Headless self-test for **随机地形生成**（两关）+ 第二关放大后的连通性。
##   godot --headless res://scenes/dev/mapgen_selftest.tscn
## Exits 0 when green, 1 when any check fails.
##
## 这个自检守三件事，每一件都对应一种"改坏了但不报错"的方式：
##
## 1. **同 seed → 同图**：随机化不能把可复现性弄丢。丢了之后没人能复现一张出问
##    题的图，所有地形 bug 都变成玄学。
## 2. **不同 seed → 不同图**：随机化必须真的生效。这条不是废话 —— 改动之前
##    `_hash2` 那几处压根没带 seed（毒沼、障碍类型每局完全一样），第二关的
##    `_paint_rooms` 更是一行随机都没有，换 seed 屁事不变。没有这条断言，
##    "随机地形"随时会静默退化回固定图。
## 3. **走得到 BOSS 房间**：泛洪从出生点出发，必须能到竞技场内部。随机房间 +
##    放大地图之后，"出生点被墙围死"和"竞技场连不上"都是真实可能，而且在自检
##    里是唯一能便宜地抓住的方式（实机要走过去才知道）。

const WASTE_CFG: String = "res://data/world/default_wasteland.tres"
const FACTORY_CFG: String = "res://data/world/factory_world.tres"

var _failures: int = 0

func _ready() -> void:
	await get_tree().process_frame
	print("=== mapgen selftest ===")
	_test_same_seed_same_map(WASTE_CFG, "wasteland")
	_test_same_seed_same_map(FACTORY_CFG, "factory")
	_test_different_seed_different_map(WASTE_CFG, "wasteland")
	_test_different_seed_different_map(FACTORY_CFG, "factory")
	_test_spawn_area_safe()
	_test_arena_reachable_from_spawn()
	print("=== mapgen selftest failures: %d ===" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

# --- 可复现性 ---

func _test_same_seed_same_map(cfg_path: String, label: String) -> void:
	var a: Dictionary = _build(cfg_path, 12345)
	var b: Dictionary = _build(cfg_path, 12345)
	if _fingerprint(a) == _fingerprint(b):
		_ok("same_seed", "%s: the same seed rebuilds an identical map" % label)
	else:
		_fail("same_seed", "%s: the same seed produced two different maps" % label)
	_drop(a)
	_drop(b)

func _test_different_seed_different_map(cfg_path: String, label: String) -> void:
	var a: Dictionary = _build(cfg_path, 1000)
	var b: Dictionary = _build(cfg_path, 2000)
	if _fingerprint(a) != _fingerprint(b):
		_ok("rand_seed", "%s: a different seed produces a different map" % label)
	else:
		_fail("rand_seed", "%s: two different seeds gave the SAME map — the seed is not reaching terrain generation" % label)
	_drop(a)
	_drop(b)

# --- 出生点 ---

## 出生点脚下必须干净：不阻挡、不是毒沼。两关都查，且换几个 seed 都要成立。
func _test_spawn_area_safe() -> void:
	var bad: String = ""
	for cfg_path in [WASTE_CFG, FACTORY_CFG]:
		for s in [7, 777, 31337]:
			var m: Dictionary = _build(cfg_path, s)
			var b: TilemapBuilder = m["builder"]
			var r: int = (m["config"] as WastelandConfig).spawn_clear_radius
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var world_pos: Vector2 = Vector2(dx, dy) * float(TilemapBuilder.TS)
					if b.is_solid(world_pos):
						bad = "%s seed %d: spawn cell (%d,%d) blocks movement" % [cfg_path.get_file(), s, dx, dy]
						break
					if b.is_swamp(world_pos):
						bad = "%s seed %d: spawn cell (%d,%d) is swamp" % [cfg_path.get_file(), s, dx, dy]
						break
				if bad != "":
					break
			_drop(m)
			if bad != "":
				break
		if bad != "":
			break
	if bad == "":
		_ok("spawn_safe", "spawn area is walkable and swamp-free on both levels across 3 seeds")
	else:
		_fail("spawn_safe", bad)

# --- 连通性（这条最重要）---

## 从出生点泛洪，必须走得到 BOSS 竞技场内部。
##
## 随机房间尺寸 + 放大地图之后这不再是显然的：`cell_w = map_size/room_grid`
## 一变，中心房间就可能不再盖住出生区，出生点会变成四周全是墙的孤岛；竞技场也
## 可能因为接入走廊没搭上而变成飞地。多试几个 seed，随机布局的尾部情况才盖得到。
func _test_arena_reachable_from_spawn() -> void:
	var bad: String = ""
	for s in [1, 42, 999, 20240607]:
		var m: Dictionary = _build(FACTORY_CFG, s)
		var b: TilemapBuilder = m["builder"]
		if not b.has_boss_arena():
			bad = "seed %d: no boss arena was carved" % s
			_drop(m)
			break
		var reached: Dictionary = _flood_from_spawn(b, m["config"] as WastelandConfig)
		# 竞技场内部随便取几个点（含中心和四个内角），都必须在泛洪结果里。
		var arena: Rect2i = b.boss_arena_rect
		var probes: Array[Vector2i] = [
			arena.get_center(),
			arena.position + Vector2i(1, 1),
			Vector2i(arena.position.x + arena.size.x - 2, arena.position.y + 1),
			Vector2i(arena.position.x + 1, arena.position.y + arena.size.y - 2),
			arena.position + arena.size - Vector2i(2, 2),
		]
		for p in probes:
			if not reached.has(p):
				bad = "seed %d: arena cell %s is NOT reachable from spawn (flood covered %d cells)" % [
					s, p, reached.size()]
				break
		_drop(m)
		if bad != "":
			break
	if bad == "":
		_ok("reachable", "the boss arena is walkable-reachable from spawn on 4 seeds")
	else:
		_fail("reachable", bad)

## 从 (0,0) 沿**不阻挡**的格子四邻泛洪，返回所有到达的格子。
func _flood_from_spawn(b: TilemapBuilder, cfg: WastelandConfig) -> Dictionary:
	var half: int = cfg.map_size_tiles / 2
	var seen: Dictionary = {}
	var start := Vector2i(0, 0)
	if _cell_solid(b, start):
		return seen
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in dirs:
			var nxt: Vector2i = cur + d
			if seen.has(nxt):
				continue
			if nxt.x < -half or nxt.x >= half or nxt.y < -half or nxt.y >= half:
				continue
			if _cell_solid(b, nxt):
				continue
			seen[nxt] = true
			queue.append(nxt)
	return seen

func _cell_solid(b: TilemapBuilder, cell: Vector2i) -> bool:
	return b.is_solid(Vector2(cell) * float(TilemapBuilder.TS))

# --- helpers ---

## 用给定 seed 建一张图，返回 {builder, tilemap, config}。
func _build(cfg_path: String, seed_val: int) -> Dictionary:
	var cfg: WastelandConfig = load(cfg_path) as WastelandConfig
	var tm := TileMap.new()
	add_child(tm)
	var b := TilemapBuilder.new()
	add_child(b)
	b.build(tm, cfg, seed_val)
	return {"builder": b, "tilemap": tm, "config": cfg}

func _drop(m: Dictionary) -> void:
	(m["tilemap"] as Node).queue_free()
	(m["builder"] as Node).queue_free()

## 地图指纹：抽样格子的瓦片 id + 毒沼数 + 营地位置。
##
## 抽样（步长 3）而不是全图逐格：128²/192² 全比一遍要跑六次（这个自检建 12 张
## 图），而抽样已经足够区分"同一张图"和"两张不同的图"。
func _fingerprint(m: Dictionary) -> String:
	var b: TilemapBuilder = m["builder"]
	var tm: TileMap = m["tilemap"]
	var cfg: WastelandConfig = m["config"]
	var half: int = cfg.map_size_tiles / 2
	var parts: PackedStringArray = PackedStringArray()
	for y in range(-half, half, 3):
		var row: PackedByteArray = PackedByteArray()
		for x in range(-half, half, 3):
			row.append(tm.get_cell_atlas_coords(0, Vector2i(x, y)).x + 1)
		parts.append(row.hex_encode())
	parts.append("swamp=%d" % b.swamp_cells.size())
	parts.append("camps=%s" % str(b.elite_camps))
	return "|".join(parts)

func _ok(name: String, msg: String) -> void:
	print("  [ok] %-11s %s" % [name, msg])

func _fail(name: String, msg: String) -> void:
	_failures += 1
	print("  [FAIL] %-11s %s" % [name, msg])
