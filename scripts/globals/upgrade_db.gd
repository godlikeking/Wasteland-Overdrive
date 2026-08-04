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
	_all.append(Upgrade.new(
		"crit_rate_up", "暴击瞄准镜",
		"暴击率 +5%",
		func(): GameState.crit_rate = minf(1.0, GameState.crit_rate + 0.05)
	))
	_all.append(Upgrade.new(
		"crit_damage_up", "穿甲弹头",
		"暴击伤害倍率 +0.5×",
		func(): GameState.crit_damage_mult += 0.5
	))
	_all.append(Upgrade.new(
		"pierce_up", "贯穿弹芯",
		"子弹穿透 +1（每次穿透伤害 ×0.8）",
		func(): GameState.pierce_count += 1
	))
	_all.append(Upgrade.new(
		"range_up", "磁轨加速管",
		"子弹射程 +25%",
		func(): GameState.weapon_range_mult *= 1.25
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
	_all.append(Upgrade.new(
		"unlock_shotgun", "解锁 · 散弹枪",
		"近距离扇形喷射多枚弹丸",
		func(): WeaponDirector.add_weapon_by_id("shotgun"),
		"weapon_unlock"
	))
	_all.append(Upgrade.new(
		"unlock_laser_lance", "解锁 · 磁轨激光",
		"瞬发长条光束，贯穿路径上全部敌人",
		func(): WeaponDirector.add_weapon_by_id("laser_lance"),
		"weapon_unlock"
	))
	_all.append(Upgrade.new(
		"unlock_mine_layer", "解锁 · 地雷布设器",
		"在脚下留雷，敌人踩中即爆",
		func(): WeaponDirector.add_weapon_by_id("mine_layer"),
		"weapon_unlock"
	))
	_all.append(Upgrade.new(
		"unlock_flamethrower", "解锁 · 火焰喷射器",
		"面前锥形范围持续灼烧",
		func(): WeaponDirector.add_weapon_by_id("flamethrower"),
		"weapon_unlock"
	))
	_all.append(Upgrade.new(
		"unlock_homing_dart", "解锁 · 追踪飞镖",
		"发射会自动转向最近敌人的飞镖",
		func(): WeaponDirector.add_weapon_by_id("homing_dart"),
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
	_all.append(Upgrade.new(
		"level_shotgun", "散弹枪 +1",
		"散弹枪升 1 级",
		func(): WeaponDirector.level_up_weapon_by_id("shotgun"),
		"weapon_level"
	))
	_all.append(Upgrade.new(
		"level_laser_lance", "磁轨激光 +1",
		"磁轨激光升 1 级",
		func(): WeaponDirector.level_up_weapon_by_id("laser_lance"),
		"weapon_level"
	))
	_all.append(Upgrade.new(
		"level_mine_layer", "地雷布设器 +1",
		"地雷布设器升 1 级",
		func(): WeaponDirector.level_up_weapon_by_id("mine_layer"),
		"weapon_level"
	))
	_all.append(Upgrade.new(
		"level_flamethrower", "火焰喷射器 +1",
		"火焰喷射器升 1 级",
		func(): WeaponDirector.level_up_weapon_by_id("flamethrower"),
		"weapon_level"
	))
	_all.append(Upgrade.new(
		"level_homing_dart", "追踪飞镖 +1",
		"追踪飞镖升 1 级",
		func(): WeaponDirector.level_up_weapon_by_id("homing_dart"),
		"weapon_level"
	))
	print("[UpgradeDB] loaded %d upgrades" % _all.size())

## Return up to `count` random upgrades, filtered against `WeaponDirector`.
## - weapon_unlock: only show those whose id is not yet owned, and only while a
##   weapon slot is still free
## - weapon_level:  only show those whose id is already owned
## - passive:       always shown
func roll(count: int) -> Array:
	var pool: Array = []
	for up in _all:
		if up.kind == "passive":
			pool.append(up)
		elif up.kind == "weapon_unlock":
			var wid: String = up.id.replace("unlock_", "")
			# Hide unlocks the player cannot act on. A full arsenal makes
			# add_weapon_by_id a no-op, so offering the card anyway would waste
			# one of the three level-up choices on nothing.
			if not WeaponDirector.has_weapon(wid) and not WeaponDirector.is_full():
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
