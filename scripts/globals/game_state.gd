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
signal shield_time_changed(remaining: float)
signal time_stop_changed(remaining: float)

# --- Boss ---
## The boss just entered the world. Carries the node because the HUD bar and the
## off-screen marker both need to follow that specific enemy, and there is no
## other way to tell it apart from the elites sharing its scene and script.
signal boss_spawned(boss: Node2D)
## Boss hp fraction (0..1) and phase (1..3). Emitted on damage and on phase
## change, i.e. exactly when a health bar should move.
signal boss_state_changed(hp_frac: float, phase: int)
signal boss_defeated
## Seconds before the boss arrives. 0 means "it is here / not coming".
signal boss_incoming(seconds: float)
## 一局结束（无论胜负）。victory = true 表示杀掉 BOSS 通关，false 表示玩家死亡。
## Game 收到后走结算界面。
signal game_over(victory: bool)

# --- Map boundary ---
## 玩家在地图外多深（像素）以及此刻的每秒伤害。depth = 0 表示回到图内，
## HUD 收到就清警告。刻意只做信号、不加成员变量：HUD 全反应式（见 hud.gd
## 头部），而这个值除了显示以外没有任何人需要查询。
signal out_of_bounds_changed(depth: float, dps: float)

# --- Run state ---
var time_alive: float = 0.0
var is_running: bool = false
## 当前关卡：1 = 废土，2 = 机器人工厂。杀 BOSS 进入下一关，reset() 回到 1。
var current_level: int = 1
## 关间切换的传送带：reset() 不清它，因为新场景的 _ready 会先 reset() 再
## 读 current_level —— 不清的话关卡切换会被新场景的开局重置抹掉。
## 只有"从头开始/再来一次"显式把它拨回 1。
var queued_level: int = 1

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
## Seconds before the remaining charges expire. The shield is a window to fight
## in, not a bank: charges left when this hits 0 are lost. Ticked next to
## `time_stop_left` below so both timed pickups expire on the same rules.
var shield_left: float = 0.0
## Seconds of "enemies frozen" left. Enemies and enemy projectiles check
## `is_time_stopped()` and bail out of their physics step; the player is
## untouched, which is why this never goes near `Engine.time_scale`
## (fx_manager's hit-stop owns that and would fight us for it).
var time_stop_left: float = 0.0
## 本次时停的总时长，用来算 BOSS 的减半窗口（见 is_time_stopped_for_boss）。
## 必须单独记：`time_stop_left` 一直在往下走，光看它算不出"过了一半没有"。
var time_stop_total: float = 0.0
## BOSS 抗时停：只被冻住 `TIME_STOP_BOSS_FACTOR` 那一段。
## 时停本来是"清屏 + 白打一轮"的道具，对着 8 万血的 BOSS 全额生效等于每次
## 捡到就送一段无风险输出窗口；减半让它仍然有用，但不再是 BOSS 战的万能解。
const TIME_STOP_BOSS_FACTOR: float = 0.5

func _process(delta: float) -> void:
	# Ticked outside the `is_running` guard: time-stop is a real-time effect and
	# must expire even while a modal (level-up, shop) has gameplay paused —
	# otherwise a player could bank the whole freeze across a menu.
	if time_stop_left > 0.0:
		time_stop_left = maxf(0.0, time_stop_left - delta)
		time_stop_changed.emit(time_stop_left)
		if time_stop_left <= 0.0:
			time_stop_total = 0.0
	# Same reasoning for the shield. Expiry drops the unspent charges, so the
	# count signal has to fire too or the HUD and the ring would keep showing a
	# shield that no longer absorbs anything.
	if shield_left > 0.0:
		shield_left = maxf(0.0, shield_left - delta)
		shield_time_changed.emit(shield_left)
		if shield_left <= 0.0 and shield_charges > 0:
			shield_charges = 0
			shield_changed.emit(0)
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

## BOSS 专用的时停判定：只在**前半段**为真，也就是冻结时长减半。
##
## 用"剩余 > 总长的一半"而不是另开一个计时器：时停可以被第二个道具续期
## （start_time_stop 取更长的那个），两个计时器会立刻对不上，而这个比值天然
## 跟着续期后的窗口走。
func is_time_stopped_for_boss() -> bool:
	if time_stop_left <= 0.0:
		return false
	return time_stop_left > time_stop_total * (1.0 - TIME_STOP_BOSS_FACTOR)

## Start (or extend) the enemy freeze. Extending takes the longer of the two so
## a second pickup can never shorten an active freeze.
func start_time_stop(seconds: float) -> void:
	time_stop_left = maxf(time_stop_left, seconds)
	# 续期后总长必须跟着涨，否则 BOSS 的减半窗口会按旧总长算，
	# 变成"续了期但 BOSS 早就解冻了"。
	time_stop_total = maxf(time_stop_total, time_stop_left)
	time_stop_changed.emit(time_stop_left)

## Add shield charges lasting `seconds`. Each charge absorbs a full hit, no
## matter its damage, and any charge still unspent when the timer runs out is
## lost. `seconds` is required rather than defaulted: a caller that forgets it
## would silently mint a permanent shield, which is the bug this replaced.
##
## 护盾**不可叠加**：已有护盾（shield_charges>0）时再捡护盾不再加层，避免囤成
## 近似永久无敌。返回 true 表示真的生效，false 表示已有护盾被拒绝（供 UI 提示
## "护盾已激活"）。
func add_shield(charges: int, seconds: float) -> bool:
	if charges <= 0:
		return false
	if shield_charges > 0:
		shield_changed.emit(shield_charges)
		return false
	shield_charges = charges
	shield_left = maxf(shield_left, maxf(0.0, seconds))
	shield_changed.emit(shield_charges)
	shield_time_changed.emit(shield_left)
	return true

## Spend one shield charge. Returns true if a hit was absorbed, which is the
## caller's cue to skip the health loss.
func consume_shield() -> bool:
	if shield_charges <= 0:
		return false
	shield_charges -= 1
	# Spending the last charge ends the effect, so drop the timer with it —
	# otherwise the HUD would count down a shield that is already gone.
	if shield_charges == 0:
		shield_left = 0.0
		shield_time_changed.emit(0.0)
	shield_changed.emit(shield_charges)
	return true

func _reset_combo() -> void:
	combo_count = 0
	_combo_accum = 0.0
	combo_changed.emit(0, _combo_level())

func reset() -> void:
	time_alive = 0.0
	is_running = false
	current_level = 1
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
	shield_left = 0.0
	time_stop_left = 0.0
	time_stop_total = 0.0
	taken_upgrades.clear()
	shield_changed.emit(0)
	shield_time_changed.emit(0.0)
	time_stop_changed.emit(0.0)
	# 上一局死在图外时，HUD 的暗角和警告还挂着。重开必须先清掉，
	# 否则新一局开局就顶着一层红。
	out_of_bounds_changed.emit(0.0, 0.0)
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

## 升级所需经验，逐级上升的二次曲线：5, 12, 25, 44, 69, 100, 137, ...
##
## 二次项是 3 而不是 1：原曲线（5+3(l-1)+(l-1)^2 → 5,9,15,23,33）相对第二关的
## 经验收入太平缓 —— 机器狗/机器人每只 3 点、腐朽骑士 32 点，一波下来能连升
## 好几级，等级差距读不出来。加陡之后累计到 20 级约 7900 点（原来 2717），
## 中后期升级重新变成一件事。
##
## 起点仍是 5：第一级要保持"开局几只小怪就能升"，那是教玩家升级存在的一课。
func xp_needed_for_level(lvl: int) -> float:
	var n: float = float(maxi(1, lvl) - 1)
	return 5.0 + 4.0 * n + 3.0 * n * n

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
