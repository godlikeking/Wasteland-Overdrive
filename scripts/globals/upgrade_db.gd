extends Node
## Data table of passive upgrades that can be rolled on level-up. Autoloaded as
## `UpgradeDB`. Each entry has an `id`, a display `name`, a `description`, and
## an `apply` Callable that mutates GameState.
##
## Weapons are no longer offered on level-up cards — they come from monster
## drops and level via the 3-into-1 merge (see WeaponDirector), so every card
## here is a passive. The `kind` field is kept (default "passive") so the
## Upgrade struct shape is unchanged, but nothing branches on it.
##
## Uses an untyped Array (rather than Array[Upgrade]) because typed
## arrays of inner classes are fragile inside autoloaded scripts.

class Upgrade:
	var id: String
	var name: String
	var description: String
	var apply: Callable
	# Always "passive"; kept for Upgrade's shape. Cards never offer weapons.
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
	print("[UpgradeDB] loaded %d upgrades" % _all.size())

## Return up to `count` random upgrades. Every entry is a passive, so the pool
## is the whole table shuffled. 12 passives > 3, so this never comes up short.
func roll(count: int) -> Array:
	var pool: Array = _all.duplicate()
	pool.shuffle()
	var result: Array = []
	for i in range(min(count, pool.size())):
		result.append(pool[i])
	return result

## Display name for an upgrade id. GameState's ledger only stores ids, so the
## pause panel needs this to turn them back into card names. Falls back to the
## raw id, which is visible in the list rather than a blank row.
func name_of(id: String) -> String:
	for u in _all:
		if u.id == id:
			return String(u.name)
	return id

## One-line "what it does" for an upgrade id, same lookup as `name_of`.
func description_of(id: String) -> String:
	for u in _all:
		if u.id == id:
			return String(u.description)
	return ""
