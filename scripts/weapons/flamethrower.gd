extends BaseWeapon
class_name FlamethrowerWeapon
## Sustained cone of fire pointed at the nearest enemy. Damages everything inside
## `flame_arc_deg` / `flame_range` every `flame_tick` — short reach, but it hits
## a whole crowd continuously instead of one enemy per shot.
##
## Per-tick damage is deliberately small: the DPS comes from ticking ~7x/sec, so
## a single tick landing or not landing never swings a fight.

## Ticks are frequent enough that the cone is redrawn every frame instead of
## being spawned as throwaway nodes like the laser beam.
const CONE_SEGMENTS: int = 14
## Cone alpha right after a tick, decaying to zero over one tick interval — it
## pulses in time with the damage instead of sitting there as a static wedge.
const FLARE_ALPHA: float = 0.42

var _tick_accum: float = 0.0
var _aim: Vector2 = Vector2.ZERO
var _flare: float = 0.0

func _post_setup() -> void:
	# Nothing to start: the cone runs off _process rather than a Timer, because
	# it has to follow the aim direction every frame anyway.
	_tick_accum = 0.0

func _process(delta: float) -> void:
	if config == null or not is_instance_valid(_owner):
		return
	var target: Node2D = _find_nearest_enemy(_range())
	if target != null:
		_aim = (target.global_position - _owner.global_position).normalized()
	if _flare > 0.0:
		_flare = maxf(0.0, _flare - delta / maxf(0.01, _interval()))
	queue_redraw()
	if target == null:
		return
	_tick_accum += delta
	if _tick_accum < _interval():
		return
	_tick_accum = 0.0
	_burn()

## Tick interval, sped up by the player's fire-rate upgrades.
func _interval() -> float:
	if config == null:
		return 0.15
	return maxf(0.03, config.flame_tick / maxf(0.05, float(GameState.fire_rate_mult)))

func _range() -> float:
	if config == null:
		return 0.0
	return config.flame_range * float(GameState.weapon_range_mult)

func _burn() -> void:
	if _aim == Vector2.ZERO:
		return
	var origin: Vector2 = _owner.global_position
	var reach: float = _range()
	# Compare cosines instead of calling angle_to per enemy: one dot product per
	# candidate, and the threshold is constant for the whole tick.
	var cos_limit: float = cos(deg_to_rad(config.flame_arc_deg) * 0.5)
	var damage: float = get_damage()
	var hit: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D) or e.is_queued_for_deletion():
			continue
		if not e.has_method("take_damage"):
			continue
		var to_e: Vector2 = (e as Node2D).global_position - origin
		var dist: float = to_e.length()
		if dist > reach or dist <= 0.001:
			continue
		if (to_e / dist).dot(_aim) < cos_limit:
			continue
		var mult: float = GameState.roll_crit()
		var final_dmg: float = damage * mult
		(e as Node2D).take_damage(final_dmg, to_e / dist)
		GameState.bullet_hit.emit((e as Node2D).global_position, mult > 1.001, final_dmg)
		hit += 1
	_flare = 1.0
	if hit > 0:
		SfxPlayer.play("fire")

func _draw() -> void:
	if config == null or _aim == Vector2.ZERO or _flare <= 0.0:
		return
	# Drawn in local space: the weapon node sits at the player's origin, so the
	# cone tracks the body for free.
	var reach: float = _range()
	var half: float = deg_to_rad(config.flame_arc_deg) * 0.5
	var base: float = _aim.angle()
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(Vector2.ZERO)
	for i in range(CONE_SEGMENTS + 1):
		var a: float = base - half + (2.0 * half) * float(i) / float(CONE_SEGMENTS)
		pts.append(Vector2.from_angle(a) * reach)
	var col := Color(1.0, 0.62, 0.22, FLARE_ALPHA * _flare)
	draw_colored_polygon(pts, col)
	# Hotter inner core, so the near half of the cone reads as the dangerous part.
	var inner: PackedVector2Array = PackedVector2Array()
	inner.append(Vector2.ZERO)
	for i in range(CONE_SEGMENTS + 1):
		var a: float = base - half * 0.55 + (half * 1.1) * float(i) / float(CONE_SEGMENTS)
		inner.append(Vector2.from_angle(a) * reach * 0.6)
	draw_colored_polygon(inner, Color(1.0, 0.9, 0.55, FLARE_ALPHA * _flare * 0.8))
