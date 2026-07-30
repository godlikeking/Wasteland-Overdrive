extends Node
## Data table of passive upgrades that can be rolled on level-up.
## Autoloaded as `UpgradeDB`. Each entry has an `id`, a display `name`,
## a `description`, and an `apply` Callable that mutates GameState.
##
## Uses an untyped Array (rather than Array[Upgrade]) because typed
## arrays of inner classes are fragile inside autoloaded scripts.

class Upgrade:
	var id: String
	var name: String
	var description: String
	var apply: Callable

	func _init(p_id: String, p_name: String, p_desc: String, p_apply: Callable) -> void:
		id = p_id
		name = p_name
		description = p_desc
		apply = p_apply

var _all: Array = []

func _ready() -> void:
	_all.append(Upgrade.new(
		"damage_up", "枪管增强",
		"武器伤害 +15%",
		func(): GameState.damage_mult *= 1.15
	))
	_all.append(Upgrade.new(
		"fire_rate_up", "过载电容",
		"射速 +15%",
		func(): GameState.fire_rate_mult *= 1.15
	))
	_all.append(Upgrade.new(
		"move_speed_up", "机动伺服",
		"移动速度 +10%",
		func(): GameState.move_speed_mult *= 1.10
	))
	_all.append(Upgrade.new(
		"max_hp_up", "钛合金外骨骼",
		"生命上限 +25",
		func(): GameState.max_hp_bonus += 25.0
	))
	_all.append(Upgrade.new(
		"pickup_radius_up", "磁力回收",
		"拾取半径 +30%",
		func(): GameState.pickup_radius_mult *= 1.30
	))
	_all.append(Upgrade.new(
		"xp_gain_up", "神经加速",
		"经验获取 +15%",
		func(): GameState.xp_gain_mult *= 1.15
	))
	_all.append(Upgrade.new(
		"extra_projectile", "分歧弹道",
		"子弹数 +1",
		func(): GameState.extra_projectiles += 1
	))
	_all.append(Upgrade.new(
		"regen_up", "纳米修复",
		"每秒回血 +0.5",
		func(): GameState.hp_regen_per_sec += 0.5
	))
	print("[UpgradeDB] loaded %d upgrades" % _all.size())

## Return up to `count` random upgrades (unique).
func roll(count: int) -> Array:
	var pool: Array = _all.duplicate()
	pool.shuffle()
	var result: Array = []
	for i in range(min(count, pool.size())):
		result.append(pool[i])
	return result
