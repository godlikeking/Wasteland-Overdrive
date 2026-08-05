extends Node
## Global game state and event bus.
## Autoloaded as `GameState`. Holds run-scope values (xp, level, time)
## and player-scope multipliers modified by upgrades.

signal xp_changed(current: float, needed: float)
signal level_changed(level: int)
signal leveled_up(new_level: int)
signal time_changed(seconds: float)
signal player_health_changed(current: float, maximum: float)
signal player_died
signal upgrade_applied(id: String)

# --- Juice / feedback events (fired by gameplay, consumed by FX layer) ---
signal enemy_died(position: Vector2, hit_direction: Vector2, was_elite: bool)
signal bullet_hit(position: Vector2, was_crit: bool, damage: float)
signal player_hurt(position: Vector2)
signal xp_collected(position: Vector2, amount: float)
signal request_camera_shake(strength: float, duration: float)
signal request_hit_stop(duration: float)
signal combo_changed(current: int, level: int)   # 连击变化
signal levelup_anim_done                              # 升级动画结束（预留）

# --- Pickup-item state (Iter8) ---
signal shield_changed(charges: int)
signal time_stop_changed(remaining: float)

# --- Run state ---
var time_alive: float = 0.0
var is_running: bool = false

# --- Progression ---
var level: int = 1
var current_xp: float = 0.0

## Passive cards taken this run: upgrade id -> how many copies were stacked.
## The multipliers below record the *result* of a pick but not which pick caused
## it, so the pause panel's "被动强化" list needs this separate ledger.
## Dictionaries keep insertion order in Godot 4, so iterating this replays the
## picks in the order the player made them.
var taken_upgrades: Dictionary = {}

# --- Player stat multipliers (applied on top of base values) ---
var damage_mult: float = 1.0
var fire_rate_mult: float = 1.0     # attacks-per-second multiplier
var move_speed_mult: float = 1.0
var max_hp_bonus: float = 0.0        # flat added to base max hp
var pickup_radius_mult: float = 1.0
var xp_gain_mult: float = 1.0
var extra_projectiles: int = 0
var hp_regen_per_sec: float = 0.0    # flat hp/sec

# --- Projectile range / pierce ---
var weapon_range_mult: float = 1.0        # 射程倍率，乘在 WeaponConfig.projectile_range 上
var pierce_count: int = 0                 # 一颗子弹可额外穿透的敌人数
var pierce_damage_falloff: float = 0.8    # 每穿透一个，后续伤害乘这个系数

# --- Crit / combo ---
var crit_rate: float = 0.05          # 基础 5% 暴击率
var crit_damage_mult: float = 2.0    # 基础 2× 暴击伤害
var combo_count: int = 0             # 当前连击
var combo_decay: float = 1.5         # 连击 N 秒内无新击杀则归零
var combo_window: float = 1.5        # 击杀间隔上限（秒）
var _combo_accum: float = 0.0        # 自上次击杀以来经过的秒数

# --- Pickup items (Iter8) ---
## Remaining hits the shield will absorb. Each hit consumes one charge.
var shield_charges: int = 0
## Seconds of "enemies frozen" left. Enemies and enemy projectiles check
## `is_time_stopped()` and bail out of their physics step; the player is
## untouched, which is why this never goes near `Engine.time_scale`
## (fx_manager's hit-stop owns that and would fight us for it).
var time_stop_left: float = 0.0

func _process(delta: float) -> void:
	# Ticked outside the `is_running` guard: time-stop is a real-time effect and
	# must expire even while a modal (level-up, shop) has gameplay paused —
	# otherwise a player could bank the whole freeze across a menu.
	if time_stop_left > 0.0:
		time_stop_left = maxf(0.0, time_stop_left - delta)
		time_stop_changed.emit(time_stop_left)
	if is_running:
		time_alive += delta
		time_changed.emit(time_alive)
		# 连击衰减
		if combo_count > 0:
			_combo_accum += delta
			if _combo_accum >= combo_window:
				_reset_combo()

# --- Pickup-item API ---

## True while the time-stop item is active. Enemies must not act.
func is_time_stopped() -> bool:
	return time_stop_left > 0.0

## Start (or extend) the enemy freeze. Extending takes the longer of the two so
## a second pickup can never shorten an active freeze.
func start_time_stop(seconds: float) -> void:
	time_stop_left = maxf(time_stop_left, seconds)
	time_stop_changed.emit(time_stop_left)

## Add shield charges. Each one absorbs a full hit, no matter its damage.
func add_shield(charges: int) -> void:
	if charges <= 0:
		return
	shield_charges += charges
	shield_changed.emit(shield_charges)

## Spend one shield charge. Returns true if a hit was absorbed, which is the
## caller's cue to skip the health loss.
func consume_shield() -> bool:
	if shield_charges <= 0:
		return false
	shield_charges -= 1
	shield_changed.emit(shield_charges)
	return true

func _reset_combo() -> void:
	combo_count = 0
	_combo_accum = 0.0
	combo_changed.emit(0, _combo_level())

func reset() -> void:
	time_alive = 0.0
	is_running = false
	level = 1
	current_xp = 0.0
	damage_mult = 1.0
	fire_rate_mult = 1.0
	move_speed_mult = 1.0
	max_hp_bonus = 0.0
	pickup_radius_mult = 1.0
	xp_gain_mult = 1.0
	extra_projectiles = 0
	hp_regen_per_sec = 0.0
	weapon_range_mult = 1.0
	pierce_count = 0
	pierce_damage_falloff = 0.8
	crit_rate = 0.05
	crit_damage_mult = 2.0
	shield_charges = 0
	time_stop_left = 0.0
	taken_upgrades.clear()
	shield_changed.emit(0)
	time_stop_changed.emit(0.0)
	_reset_combo()

## Single funnel for "the player took a passive card": records the stack count
## and then fires `upgrade_applied`. Callers go through this rather than emitting
## the signal themselves so a pick can never bump a stat without landing in the
## ledger the pause panel reads.
func record_upgrade(id: String) -> void:
	taken_upgrades[id] = int(taken_upgrades.get(id, 0)) + 1
	upgrade_applied.emit(id)

## Roll for a crit hit. Returns the damage multiplier (≥1.0).
## 连击每 +1 暴击率 +1.5%（封顶 +30%）。
func roll_crit() -> float:
	var bonus: float = min(0.30, 0.015 * float(combo_count))
	var chance: float = clampf(crit_rate + bonus, 0.0, 1.0)
	if randf() < chance:
		return crit_damage_mult
	return 1.0

## Register a successful hit (used to maintain the combo timer).
func register_hit() -> void:
	combo_count += 1
	_combo_accum = 0.0
	combo_changed.emit(combo_count, _combo_level())

## 0=none, 1=warm (3+), 2=hot (8+), 3=blazing (15+)
func _combo_level() -> int:
	if combo_count >= 15: return 3
	if combo_count >= 8:  return 2
	if combo_count >= 3:  return 1
	return 0

func xp_needed_for_level(lvl: int) -> float:
	# Simple quadratic curve: 5, 12, 21, 32, 45, ...
	return 5.0 + 3.0 * (lvl - 1) + 1.0 * (lvl - 1) * (lvl - 1)

func add_xp(amount: float) -> void:
	current_xp += amount * xp_gain_mult
	var needed: float = xp_needed_for_level(level)
	while current_xp >= needed:
		current_xp -= needed
		level += 1
		leveled_up.emit(level)
		level_changed.emit(level)
		needed = xp_needed_for_level(level)
	xp_changed.emit(current_xp, needed)
