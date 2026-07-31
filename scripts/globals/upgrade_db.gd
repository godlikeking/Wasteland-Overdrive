extends Node
## Data table of passive and weapon upgrades that can be rolled on level-up.
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
	# "passive" or "weapon". Weapon upgrades are level-rolled by
	# level_up.gd using the active weapons from WeaponDirector.
	var kind: String

	func _init(p_id: String, p_name: String, p_desc: String, p_apply: Callable, p_kind: String = "passive") -> void:
		id = p_id
		name = p_name
		description = p_desc
		apply = p_apply
		kind = p_kind

var _all: Array = []

func _ready() -> void:
	# --- Passive upgrades (always available) ---
	_all.append(Upgrade.new(
		"damage_up", "枪管增强",
		"全部武器伤害 +15%",
		func(): GameState.damage_mult *= 1.15
	))
	_all.append(Upgrade.new(
		"fire_rate_up", "过载电容",
		"全部武器射速 +15%",
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
		"弹雨子弹数 +1",
		func(): GameState.extra_projectiles += 1
	))
	_all.append(Upgrade.new(
		"regen_up", "纳米修复",
		"每秒回血 +0.5",
		func(): GameState.hp_regen_per_sec += 0.5
	))
	# --- Weapon "unlock" upgrades (only one of each, only when not yet owned) ---
	_all.append(Upgrade.new(
		"unlock_orbiting_blades", "解锁 · 刀阵",
		"获得 1 圈旋转刀刃",
		func(): WeaponDirector.add_weapon_by_id("orbiting_blades"),
		"weapon_unlock"
	))
	_all.append(Upgrade.new(
		"unlock_chain_lightning", "解锁 · 闪电链",
		"获得闪电链武器",
		func(): WeaponDirector.add_weapon_by_id("chain_lightning"),
		"weapon_unlock"
	))
	# --- Weapon "level up" upgrades (one of each, only when already owned) ---
	_all.append(Upgrade.new(
		"level_bullet_volley", "弹雨 +1",
		"弹雨升 1 级",
		func(): WeaponDirector.level_up_weapon_by_id("bullet_volley"),
		"weapon_level"
	))
	_all.append(Upgrade.new(
		"level_orbiting_blades", "刀阵 +1",
		"刀阵升 1 级",
		func(): WeaponDirector.level_up_weapon_by_id("orbiting_blades"),
		"weapon_level"
	))
	_all.append(Upgrade.new(
		"level_chain_lightning", "闪电链 +1",
		"闪电链升 1 级",
		func(): WeaponDirector.level_up_weapon_by_id("chain_lightning"),
		"weapon_level"
	))
	print("[UpgradeDB] loaded %d upgrades" % _all.size())

## Return up to `count` random upgrades, filtered against `WeaponDirector`.
## - weapon_unlock: only show those whose id is not yet owned
## - weapon_level:  only show those whose id is already owned
## - passive:       always shown
func roll(count: int) -> Array:
	var pool: Array = []
	for up in _all:
		if up.kind == "passive":
			pool.append(up)
		elif up.kind == "weapon_unlock":
			var wid: String = up.id.replace("unlock_", "")
			if not WeaponDirector.has_weapon(wid):
				pool.append(up)
		elif up.kind == "weapon_level":
			var wid2: String = up.id.replace("level_", "")
			if WeaponDirector.has_weapon(wid2):
				pool.append(up)
	pool.shuffle()
	var result: Array = []
	for i in range(min(count, pool.size())):
		result.append(pool[i])
	return result
