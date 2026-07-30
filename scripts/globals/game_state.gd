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

# --- Run state ---
var time_alive: float = 0.0
var is_running: bool = false

# --- Progression ---
var level: int = 1
var current_xp: float = 0.0

# --- Player stat multipliers (applied on top of base values) ---
var damage_mult: float = 1.0
var fire_rate_mult: float = 1.0     # attacks-per-second multiplier
var move_speed_mult: float = 1.0
var max_hp_bonus: float = 0.0        # flat added to base max hp
var pickup_radius_mult: float = 1.0
var xp_gain_mult: float = 1.0
var extra_projectiles: int = 0
var hp_regen_per_sec: float = 0.0    # flat hp/sec

func _process(delta: float) -> void:
	if is_running:
		time_alive += delta
		time_changed.emit(time_alive)

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
