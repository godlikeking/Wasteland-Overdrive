extends Node2D
## Headless self-test for 巨型机器人（GOBOT，第二关 BOSS）的三招进阶技。
##   godot --headless res://scenes/dev/gobot_selftest.tscn
## Exits 0 when green, 1 when any check fails.
##
## GOBOT 原本**零覆盖**：激光那段长条判定数学一行测试都没有，三招新技的解锁
## 节奏也只能靠真打一场才看得到。这里按项目惯例把能算的部分（in_beam /
## bolt_angles / gobot_attack_unlocked）当纯函数断言，再对电球和地雷做最小的
## 集成验证（生成了什么、伤了谁）。

const ORB_SCENE: PackedScene = preload("res://scenes/fx/gobot_orb.tscn")
const MINE_SCENE: PackedScene = preload("res://scenes/fx/gobot_mine.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/enemy_projectile.tscn")
## 用来在场景树里认出小电球（见 _count_enemy_projectiles 为什么不按名字认）。
const PROJECTILE_SCRIPT: GDScript = preload("res://scripts/enemy_projectile.gd")
## enemy.gd 没有 class_name（它是场景脚本，不是全局类），所以按路径预载，
## 靠它取常量和静态函数 —— 只为自检给它加一个全局类名不值当。
const ENEMY: GDScript = preload("res://scripts/enemy.gd")

var _failures: int = 0

@onready var player: CharacterBody2D = $Player

func _ready() -> void:
	await get_tree().process_frame
	print("=== gobot selftest ===")
	_test_in_beam()
	_test_bolt_angles()
	_test_phase_unlocks()
	_test_config_filled()
	await _test_orb_burst()
	await _test_mine_hits_player()
	await _test_mine_arming()
	print("=== gobot selftest failures: %d ===" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

# --- 纯函数：长条命中 ---

## 激光和多道闪电共用的长条矩形判定。六条性质各自对应一种真实的写错方式。
func _test_in_beam() -> void:
	var from := Vector2.ZERO
	var facing := Vector2.RIGHT
	var length: float = 800.0
	var width: float = 100.0
	# 正前方、宽度内 -> 命中
	if not GobotBolts.in_beam(from, facing, Vector2(400, 0), length, width):
		_fail("in_beam", "a target straight ahead was not hit")
	else:
		_ok("in_beam", "hits a target straight ahead")
	# 身后 -> 不中（光束只朝前打）
	if GobotBolts.in_beam(from, facing, Vector2(-400, 0), length, width):
		_fail("in_beam", "a target BEHIND the beam was hit")
	else:
		_ok("in_beam", "a target behind the beam is missed")
	# 超出长度 -> 不中
	if GobotBolts.in_beam(from, facing, Vector2(length + 10.0, 0), length, width):
		_fail("in_beam", "a target beyond the beam length was hit")
	else:
		_ok("in_beam", "a target beyond the length is missed")
	# 超出半宽 -> 不中
	if GobotBolts.in_beam(from, facing, Vector2(400, width * 0.5 + 5.0), length, width):
		_fail("in_beam", "a target outside the half-width was hit")
	else:
		_ok("in_beam", "a target outside the half-width is missed")
	# 恰好在边界（半宽 / 末端）-> 命中（"范围以内"含边界）
	var edge_w: bool = GobotBolts.in_beam(from, facing, Vector2(400, width * 0.5), length, width)
	var edge_l: bool = GobotBolts.in_beam(from, facing, Vector2(length, 0), length, width)
	if edge_w and edge_l:
		_ok("in_beam", "targets exactly on the width/length edge count as hits")
	else:
		_fail("in_beam", "edge cases missed (width edge=%s, length edge=%s)" % [edge_w, edge_l])
	# 零朝向 -> false 而不是崩
	if GobotBolts.in_beam(from, Vector2.ZERO, Vector2(10, 0), length, width):
		_fail("in_beam", "a zero facing reported a hit")
	else:
		_ok("in_beam", "a zero-length facing degrades to a miss, not an error")
	# 斜向也要成立（不能只在轴对齐时对）
	var diag := Vector2(1, 1).normalized()
	if not GobotBolts.in_beam(from, diag, diag * 300.0, length, width):
		_fail("in_beam", "a diagonal beam missed a target on its own axis")
	else:
		_ok("in_beam", "works off-axis (diagonal beam)")

# --- 纯函数：闪电角度 ---

## 视觉画线和命中判定必须用**同一份**角度，所以这条来源本身要对。
func _test_bolt_angles() -> void:
	var base: float = 0.0
	var spread: float = 1.5
	var a: PackedFloat32Array = GobotBolts.bolt_angles(base, 5, spread)
	if a.size() != 5:
		_fail("bolt_angles", "asked for 5 bolts, got %d" % a.size())
		return
	# 对称：中轴两侧张角相等，中间一条正好在中轴上。
	if absf(a[0] - (base - spread * 0.5)) > 0.001 or absf(a[4] - (base + spread * 0.5)) > 0.001:
		_fail("bolt_angles", "fan is not centred: %.3f .. %.3f (want %.3f .. %.3f)" % [
			a[0], a[4], base - spread * 0.5, base + spread * 0.5])
	elif absf(a[2] - base) > 0.001:
		_fail("bolt_angles", "middle bolt is %.3f, expected the base angle %.3f" % [a[2], base])
	else:
		_ok("bolt_angles", "5 bolts fan symmetrically across the aim direction")
	# 单道退化成正中一条（spread 此时无意义，不能把唯一一道甩到边上）。
	var one: PackedFloat32Array = GobotBolts.bolt_angles(base, 1, spread)
	if one.size() != 1 or absf(one[0] - base) > 0.001:
		_fail("bolt_angles", "count=1 did not degrade to a single centred bolt")
	else:
		_ok("bolt_angles", "count=1 degrades to one bolt on the aim direction")

# --- 纯函数：阶段解锁 ---

## 用户要的解锁节奏：电球 P1 起、闪电 P2 起、地雷 P3 起。
func _test_phase_unlocks() -> void:
	var want := {
		ENEMY.ATK_ORB: 1,
		ENEMY.ATK_BOLTS: 2,
		ENEMY.ATK_MINES: 3,
	}
	var names := {ENEMY.ATK_ORB: "orb", ENEMY.ATK_BOLTS: "bolts", ENEMY.ATK_MINES: "mines"}
	var bad: String = ""
	for atk in want.keys():
		var from_phase: int = int(want[atk])
		for phase in range(1, 4):
			var unlocked: bool = ENEMY.gobot_attack_unlocked(atk, phase)
			var should: bool = phase >= from_phase
			if unlocked != should:
				bad = "%s at P%d: unlocked=%s, expected %s" % [names[atk], phase, unlocked, should]
				break
		if bad != "":
			break
	if bad == "":
		_ok("unlocks", "orb from P1, bolts from P2, mines from P3")
	else:
		_fail("unlocks", bad)
	# 未知招式不能"默认解锁"，否则打错编号会变成一招凭空出现的攻击。
	if ENEMY.gobot_attack_unlocked(999, 3):
		_fail("unlocks", "an unknown attack id reported unlocked")
	else:
		_ok("unlocks", "an unknown attack id stays locked")

## 配置漏填会让招式静默不发动（冷却 0 或数量 0），所以数值本身也要断言。
func _test_config_filled() -> void:
	var cfg: EnemyConfig = load("res://data/enemies/giant_robot.tres") as EnemyConfig
	if cfg == null:
		_fail("config", "cannot load giant_robot.tres")
		return
	var checks := {
		"gobot_orb_damage": cfg.gobot_orb_damage,
		"gobot_orb_cooldown": cfg.gobot_orb_cooldown,
		"gobot_orb_shard_count": float(cfg.gobot_orb_shard_count),
		"gobot_bolt_damage": cfg.gobot_bolt_damage,
		"gobot_bolt_cooldown": cfg.gobot_bolt_cooldown,
		"gobot_bolt_count": float(cfg.gobot_bolt_count),
		"gobot_mine_damage": cfg.gobot_mine_damage,
		"gobot_mine_cooldown": cfg.gobot_mine_cooldown,
		"gobot_mine_count": float(cfg.gobot_mine_count),
	}
	var zero: Array[String] = []
	for k in checks.keys():
		if float(checks[k]) <= 0.0:
			zero.append(String(k))
	if zero.is_empty():
		_ok("config", "all three new attacks carry non-zero tuning")
	else:
		_fail("config", "zero/missing in giant_robot.tres: %s" % ", ".join(zero))

# --- 集成：电球炸开 ---

## 电球抵达落点必须做两件事：范围内伤玩家一次 + 喷出 N 颗小电球。
## 两件事分两次测：小电球是**打玩家的**弹，落点压在玩家身上时它们会在生成的
## 同一瞬间命中并自毁，数出来永远是 0 —— 第一版就踩了这个坑。
func _test_orb_burst() -> void:
	# (1) 范围伤害：落点压在玩家身上。
	player.global_position = Vector2.ZERO
	player.hp = player.max_hp
	var orb: Node2D = ORB_SCENE.instantiate() as Node2D
	add_child(orb)
	# 落点就在玩家身上，起点稍远一点，让它自己飞过去炸。
	orb.global_position = Vector2(-60, 0)
	orb.setup(Vector2.ZERO, 600.0, 45.0, 130.0, 8, 12.0, 300.0, PROJECTILE_SCENE)
	await _advance(0.6)
	if is_instance_valid(orb) and not orb.is_queued_for_deletion():
		_fail("orb", "the orb never burst after reaching its target")
		orb.queue_free()
		return
	_ok("orb", "the orb bursts on reaching its target point")
	if player.hp >= player.max_hp:
		_fail("orb", "the burst did not damage the player inside its radius")
	else:
		_ok("orb", "the burst damages a player inside the radius (-%.0f hp)" % (player.max_hp - player.hp))
	_clear_enemy_projectiles()
	await get_tree().process_frame

	# (2) 碎片数量：把玩家挪远，小电球才不会一生成就命中自毁。
	player.global_position = Vector2(4000, 4000)
	var before: int = _count_enemy_projectiles()
	var orb2: Node2D = ORB_SCENE.instantiate() as Node2D
	add_child(orb2)
	orb2.global_position = Vector2(-60, 0)
	orb2.setup(Vector2.ZERO, 600.0, 45.0, 130.0, 8, 12.0, 300.0, PROJECTILE_SCENE)
	await _advance(0.6)
	var spawned: int = _count_enemy_projectiles() - before
	if spawned < 8:
		_fail("orb", "the burst spawned %d shards, expected 8" % spawned)
	else:
		_ok("orb", "the burst sprays %d small orbs" % spawned)
	if is_instance_valid(orb2) and not orb2.is_queued_for_deletion():
		orb2.queue_free()
	_clear_enemy_projectiles()
	player.global_position = Vector2.ZERO
	await get_tree().process_frame

# --- 集成：敌方地雷 ---

## 布防后踩上去必须伤玩家（这是这招唯一的意义）。
func _test_mine_hits_player() -> void:
	player.global_position = Vector2.ZERO
	player.hp = player.max_hp
	var mine: Node2D = MINE_SCENE.instantiate() as Node2D
	add_child(mine)
	mine.global_position = Vector2.ZERO   # 直接压在玩家身上
	mine.setup(140.0, 50.0, 0.1, 5.0)     # 0.1s 布防
	await _advance(0.5)
	if player.hp >= player.max_hp:
		_fail("mine", "an armed mine under the player did no damage")
	else:
		_ok("mine", "an armed mine damages the player (-%.0f hp)" % (player.max_hp - player.hp))
	if is_instance_valid(mine) and not mine.is_queued_for_deletion():
		_fail("mine", "the mine survived its own detonation")
		mine.queue_free()
	else:
		_ok("mine", "the mine is consumed by its detonation")
	await get_tree().process_frame

## 布防延迟必须真的存在：没有它，雷就是一发无法反应的即时伤害。
## 到期也必须自爆，否则踩不到的雷会永远躺在地上。
func _test_mine_arming() -> void:
	player.global_position = Vector2.ZERO
	player.hp = player.max_hp
	var mine: Node2D = MINE_SCENE.instantiate() as Node2D
	add_child(mine)
	mine.global_position = Vector2.ZERO
	mine.setup(140.0, 50.0, 5.0, 6.0)   # 5s 才布防，这段时间踩上去不该炸
	await _advance(0.4)
	if player.hp < player.max_hp:
		_fail("mine_arm", "an UNARMED mine already damaged the player")
	else:
		_ok("mine_arm", "an unarmed mine does not go off under the player")
	mine.queue_free()
	await get_tree().process_frame
	# 到期自爆：布防很快、寿命很短，且玩家站得远（只验证它会自己消失）。
	player.global_position = Vector2(3000, 3000)
	var expiring: Node2D = MINE_SCENE.instantiate() as Node2D
	add_child(expiring)
	expiring.global_position = Vector2.ZERO
	expiring.setup(140.0, 50.0, 0.05, 0.3)
	await _advance(0.7)
	if is_instance_valid(expiring) and not expiring.is_queued_for_deletion():
		_fail("mine_arm", "a mine outlived its lifetime instead of self-detonating")
		expiring.queue_free()
	else:
		_ok("mine_arm", "a mine self-detonates when its lifetime runs out")
	player.global_position = Vector2.ZERO
	await get_tree().process_frame

# --- helpers ---

## 小电球是 enemy_projectile.tscn 的实例，由电球挂到 current_scene 下（也就是
## 这个自检的根节点）。**按脚本认而不是按节点名**：add_child 遇到重名会给出
## `@EnemyProjectile@12345` 这种内部名，按名字前缀数 8 颗只能数到 1 颗 ——
## 第一版就是这么假失败的。
func _count_enemy_projectiles() -> int:
	var n: int = 0
	for c in get_tree().current_scene.get_children():
		if c.get_script() == PROJECTILE_SCRIPT:
			n += 1
	return n

func _clear_enemy_projectiles() -> void:
	for c in get_tree().current_scene.get_children():
		if c.get_script() == PROJECTILE_SCRIPT:
			c.queue_free()

func _advance(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

func _ok(name: String, msg: String) -> void:
	print("  [ok] %-11s %s" % [name, msg])

func _fail(name: String, msg: String) -> void:
	_failures += 1
	print("  [FAIL] %-11s %s" % [name, msg])
