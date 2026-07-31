extends Node2D
## Base class for player weapons. Subclasses implement `_fire()`. Damage
## and fire_rate scale with the player's global multipliers in GameState
## plus the weapon's own level.

class_name BaseWeapon

var config: WeaponConfig
var level: int = 1
var _damage: float = 0.0
var _fire_rate: float = 0.0
var _owner: Node2D            # the player body; we read its group
var _ready_called: bool = false

func _ready() -> void:
	_ready_called = true
	_owner = get_tree().get_first_node_in_group("player")
	# Only recompute if config has been injected before _ready ran. WeaponDirector
	# calls setup() AFTER add_child, so subclasses should defer real work to
	# setup() (or check _ready_called there).
	if config != null:
		_recompute_stats()
		_post_setup()

# Called by subclasses after the weapon is fully configured. Default is a no-op.
func _post_setup() -> void:
	pass

func setup(p_config: WeaponConfig, p_level: int = 1) -> void:
	config = p_config
	level = p_level
	_recompute_stats()
	if _ready_called:
		_post_setup()

func _recompute_stats() -> void:
	if config == null:
		return
	# +25% damage per level above 1, +15% fire rate per level above 1.
	var dmg_mult: float = 1.0 + 0.25 * float(level - 1)
	var rate_mult: float = 1.0 + 0.15 * float(level - 1)
	_damage = config.base_damage * dmg_mult
	_fire_rate = config.base_fire_rate * rate_mult

func get_damage() -> float:
	return _damage * float(GameState.damage_mult)

func get_fire_interval() -> float:
	var r: float = _fire_rate * float(GameState.fire_rate_mult)
	return 1.0 / maxf(0.05, r)

func _find_nearest_enemy() -> Node2D:
	if not is_instance_valid(_owner):
		_owner = get_tree().get_first_node_in_group("player")
	if _owner == null:
		return null
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var best: Node2D = null
	var best_d: float = INF
	for e in enemies:
		if not (e is Node2D):
			continue
		var d: float = (e.global_position - _owner.global_position).length_squared()
		if d < best_d:
			best_d = d
			best = e
	return best

func _find_n_nearest_enemies(n: int) -> Array:
	if not is_instance_valid(_owner):
		_owner = get_tree().get_first_node_in_group("player")
	if _owner == null:
		return []
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var arr: Array = []
	for e in enemies:
		if e is Node2D:
			arr.append(e)
	arr.sort_custom(func(a, b):
		var da: float = (a.global_position - _owner.global_position).length_squared()
		var db: float = (b.global_position - _owner.global_position).length_squared()
		return da < db)
	return arr.slice(0, min(n, arr.size()))

# Subclasses override.
func _fire() -> void:
	pass
