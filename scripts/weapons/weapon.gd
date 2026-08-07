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
	# Steep curve: +100% damage per level above 1, +50% fire rate per level
	# above 1. A Lv2 weapon is 2.0x damage * 1.5x rate = 3.0x output, exactly
	# what 3 Lv1 copies produce — so the first merge (3 same-level weapons into
	# one at level+1) is a DPS-neutral trade that only frees 2 slots. Later
	# merges are deliberately diminishing (3 Lv2 -> 1 Lv3 = 6.0x vs their 9.0x
	# kept apart), since levels are now only reachable through that 3-into-1 cost.
	var dmg_mult: float = 1.0 + 1.0 * float(level - 1)
	var rate_mult: float = 1.0 + 0.5 * float(level - 1)
	_damage = config.base_damage * dmg_mult
	_fire_rate = config.base_fire_rate * rate_mult

## Level + player fire-rate scaling for weapons that run on their own cooldown
## field instead of base_fire_rate. Without this a merge would be worth 3.0x
## output on rate-driven weapons but only 2.0x on cooldown-driven ones, so the
## chain lightning / laser / flamethrower / mine weapons all route their
## interval through here to stay consistent with the merge curve.
func scale_cooldown(base: float, floor_sec: float) -> float:
	var r: float = 1.0 + 0.5 * float(level - 1)   # must match _recompute_stats rate_mult
	r *= float(GameState.fire_rate_mult)
	return maxf(floor_sec, base / maxf(0.05, r))

func get_damage() -> float:
	return _damage * float(GameState.damage_mult)

func get_fire_interval() -> float:
	var r: float = _fire_rate * float(GameState.fire_rate_mult)
	return 1.0 / maxf(0.05, r)

## Effective projectile range in px, scaled by the player's range upgrades.
## Returns 0.0 when the config leaves projectile_range unset, which every
## caller treats as "unlimited".
func get_range() -> float:
	if config == null or config.projectile_range <= 0.0:
		return 0.0
	return config.projectile_range * GameState.weapon_range_mult

## Nearest enemy, optionally capped to `max_range` px. max_range <= 0 means
## unlimited — that's the default, so existing callers are unaffected.
func _find_nearest_enemy(max_range: float = 0.0) -> Node2D:
	if not is_instance_valid(_owner):
		_owner = get_tree().get_first_node_in_group("player")
	if _owner == null:
		return null
	var limit_sq: float = INF
	if max_range > 0.0:
		limit_sq = max_range * max_range
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var best: Node2D = null
	var best_d: float = INF
	for e in enemies:
		if not (e is Node2D):
			continue
		var d: float = (e.global_position - _owner.global_position).length_squared()
		if d > limit_sq:
			continue
		if not _has_line_of_sight(e as Node2D):
			continue
		if d < best_d:
			best_d = d
			best = e
	return best

## 武器能否在墙外看见敌人：第二关（工厂房间）里隔着墙的敌人不能被锁定，
## 否则所有武器都会隔墙射击，房间战就失去了意义。第一关噪声地形不启用
## （那里本来就该全图自由开火）。
## 射线走 World 层（1），只挡一次墙。没有世界物理空间（自检场景）时
## 退化为"看得见"。
func _has_line_of_sight(target: Node2D) -> bool:
	if not is_instance_valid(_owner) or GameState.current_level != 2:
		return true
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return true
	var q := PhysicsRayQueryParameters2D.create(
		_owner.global_position, target.global_position)
	q.collision_mask = 1  # World only
	q.hit_from_inside = false
	return space.intersect_ray(q).is_empty()

## Direction this weapon currently aims, used by WeaponMounts to rotate the
## icon it draws on the player. Vector2.ZERO means "no target" — the icon then
## keeps whatever angle it already had instead of snapping back to 0.
func get_aim_direction() -> Vector2:
	var t: Node2D = _find_nearest_enemy(get_range())
	if t == null or not is_instance_valid(_owner):
		return Vector2.ZERO
	return (t.global_position - _owner.global_position).normalized()

## Nearest N enemies, optionally capped to `max_range` px. max_range <= 0
## means unlimited (existing callers with the old signature are unchanged).
func _find_n_nearest_enemies(n: int, max_range: float = 0.0) -> Array:
	if not is_instance_valid(_owner):
		_owner = get_tree().get_first_node_in_group("player")
	if _owner == null:
		return []
	var limit_sq: float = INF
	if max_range > 0.0:
		limit_sq = max_range * max_range
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var arr: Array = []
	for e in enemies:
		if e is Node2D:
			if limit_sq < INF and (e.global_position - _owner.global_position).length_squared() > limit_sq:
				continue
			if not _has_line_of_sight(e as Node2D):
				continue
			arr.append(e)
	arr.sort_custom(func(a, b):
		var da: float = (a.global_position - _owner.global_position).length_squared()
		var db: float = (b.global_position - _owner.global_position).length_squared()
		return da < db)
	return arr.slice(0, min(n, arr.size()))

# Subclasses override.
func _fire() -> void:
	pass
