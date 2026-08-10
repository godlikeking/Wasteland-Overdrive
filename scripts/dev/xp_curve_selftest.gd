extends Node
## Headless self-test for the XP / level curve.
##   godot --headless res://scenes/dev/xp_curve_selftest.tscn
## Exits 0 when green, 1 when any check fails.
##
## 这个自检的核心是那条用户要求的性质：**升级所需经验逐级上升**。曲线的具体
## 数值可以随手调，但"下一级一定比上一级贵"这条不能被调没了 —— 曲线一旦写平
## （或某一级反而变便宜），升级就会在某个等级段突然变成连击，而且没有任何报错。
##
## 另外钉住 add_xp 的进位行为：它的 while 循环每轮都要重新读 needed，否则一次
## 大额经验（BOSS 宝石 25 倍）会用第一级的门槛连升好几级。

const MAX_LEVEL_CHECKED: int = 60

var _failures: int = 0

func _ready() -> void:
	await get_tree().process_frame
	print("=== xp_curve selftest ===")
	_test_monotonic()
	_test_first_level_cheap()
	_test_growth_is_real()
	_test_add_xp_carries_remainder()
	_test_big_grant_uses_each_level_threshold()
	_test_reset()
	print("=== xp_curve selftest failures: %d ===" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

## 逐级上升：这是本次改动的验收条件本身。
func _test_monotonic() -> void:
	var bad: String = ""
	for lvl in range(1, MAX_LEVEL_CHECKED):
		var a: float = GameState.xp_needed_for_level(lvl)
		var b: float = GameState.xp_needed_for_level(lvl + 1)
		if b <= a:
			bad = "level %d needs %.1f but level %d needs %.1f (not rising)" % [lvl, a, lvl + 1, b]
			break
	if bad == "":
		_ok("monotonic", "every level costs strictly more than the last (1..%d)" % MAX_LEVEL_CHECKED)
	else:
		_fail("monotonic", bad)

## 第一级必须便宜：开局几只小怪就该升一级，那是教玩家"升级存在"的一课。
func _test_first_level_cheap() -> void:
	var first: float = GameState.xp_needed_for_level(1)
	if first > 8.0:
		_fail("first_level", "level 1 needs %.1f xp — too slow to teach the mechanic" % first)
	else:
		_ok("first_level", "level 1 costs %.0f xp" % first)

## 上升幅度要真的存在：曲线必须是超线性的（差值本身递增），否则"逐级上升"会
## 退化成每级只贵一点点，中后期照旧连升。
func _test_growth_is_real() -> void:
	var d1: float = GameState.xp_needed_for_level(3) - GameState.xp_needed_for_level(2)
	var d2: float = GameState.xp_needed_for_level(12) - GameState.xp_needed_for_level(11)
	if d2 <= d1:
		_fail("growth", "step stays flat: L2->L3 costs +%.1f, L11->L12 costs +%.1f" % [d1, d2])
	else:
		_ok("growth", "the step itself grows (+%.0f early vs +%.0f later)" % [d1, d2])
	# 高等级必须明显贵于低等级，挡住"把二次项调成 0"这类回归。
	var ratio: float = GameState.xp_needed_for_level(20) / maxf(1.0, GameState.xp_needed_for_level(2))
	if ratio < 10.0:
		_fail("growth", "level 20 is only %.1fx level 2 — the curve is nearly flat" % ratio)
	else:
		_ok("growth", "level 20 costs %.0fx level 2" % ratio)

## 升级要把多余经验带进下一级，不能清零（否则每次升级都在悄悄吞经验）。
func _test_add_xp_carries_remainder() -> void:
	GameState.reset()
	var need: float = GameState.xp_needed_for_level(1)
	GameState.add_xp(need + 2.0)
	if GameState.level != 2:
		_fail("remainder", "granting one level's xp gave level %d" % GameState.level)
		return
	if absf(GameState.current_xp - 2.0) > 0.01:
		_fail("remainder", "leftover xp is %.2f, expected 2.00" % GameState.current_xp)
	else:
		_ok("remainder", "level-up carries the leftover xp forward")

## 一次大额经验（BOSS 宝石）必须按**每一级各自的门槛**逐级扣，不能用第一级的
## 门槛连升。这条是 add_xp 里 while 循环重读 needed 的回归闸门。
func _test_big_grant_uses_each_level_threshold() -> void:
	GameState.reset()
	# 正好给到 3 级所需的总量，应当停在 3 级、余 0。
	var total: float = GameState.xp_needed_for_level(1) + GameState.xp_needed_for_level(2)
	GameState.add_xp(total)
	if GameState.level != 3:
		_fail("big_grant", "xp for exactly 2 level-ups landed on level %d" % GameState.level)
	elif GameState.current_xp > 0.01:
		_fail("big_grant", "expected 0 leftover, got %.2f" % GameState.current_xp)
	else:
		_ok("big_grant", "a multi-level grant spends each level's own threshold")

func _test_reset() -> void:
	GameState.add_xp(500.0)
	GameState.reset()
	if GameState.level != 1 or GameState.current_xp != 0.0:
		_fail("reset", "after reset: level=%d xp=%.1f" % [GameState.level, GameState.current_xp])
	else:
		_ok("reset", "reset() puts the run back to level 1 with no xp")

func _ok(name: String, msg: String) -> void:
	print("  [ok] %-12s %s" % [name, msg])

func _fail(name: String, msg: String) -> void:
	_failures += 1
	print("  [FAIL] %-12s %s" % [name, msg])
