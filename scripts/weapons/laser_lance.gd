extends BaseWeapon
class_name LaserLanceWeapon
## Hitscan beam. Every `laser_cooldown` it picks the nearest enemy, then damages
## everything inside a `laser_length` x `laser_width` band along that direction —
## so it rewards lining enemies up instead of just pointing at the closest one.
##
## No projectile scene: the hit test is pure geometry and the visual is a Line2D
## that fades out, same throwaway-node trick ChainLightningWeapon uses.

@onready var timer: Timer = $Timer

## How long the beam graphic lingers. Long enough to see, short enough that a
## fast fire rate doesn't leave a permanent stripe on screen.
const BEAM_FADE: float = 0.16

func _ready() -> void:
	super._ready()
	if timer:
		timer.one_shot = false
		timer.timeout.connect(_on_tick)

func _post_setup() -> void:
	if timer == null:
		return
	timer.wait_time = _interval()
	timer.start()

func _process(_delta: float) -> void:
	if timer and config != null and absf(timer.wait_time - _interval()) > 0.02:
		timer.wait_time = _interval()
		if timer.is_stopped():
			timer.start()

## The beam is on its own cooldown rather than base_fire_rate, but the player's
## fire-rate upgrades still have to matter, so fold them in here.
func _interval() -> float:
	if config == null:
		return 1.0
	return maxf(0.1, config.laser_cooldown / maxf(0.05, float(GameState.fire_rate_mult)))

func _on_tick() -> void:
	_fire()

func _fire() -> void:
	if config == null or not is_instance_valid(_owner):
		return
	var target: Node2D = _find_nearest_enemy(_length())
	if target == null:
		return
	var origin: Vector2 = _owner.global_position
	var dir: Vector2 = (target.global_position - origin).normalized()
	var length: float = _length()
	var half_width: float = config.laser_width * 0.5
	var damage: float = get_damage()
	var hits: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D) or e.is_queued_for_deletion():
			continue
		if not e.has_method("take_damage"):
			continue
		var to_e: Vector2 = (e as Node2D).global_position - origin
		# Project onto the beam axis: `along` must land inside the beam, and the
		# perpendicular component inside its half-width. Cheaper and more
		# predictable than a physics shapecast, and it can't be blocked by
		# terrain the beam is supposed to ignore.
		var along: float = to_e.dot(dir)
		if along < 0.0 or along > length:
			continue
		if absf(to_e.dot(Vector2(-dir.y, dir.x))) > half_width:
			continue
		var mult: float = GameState.roll_crit()
		var final_dmg: float = damage * mult
		(e as Node2D).take_damage(final_dmg, dir)
		GameState.bullet_hit.emit((e as Node2D).global_position, mult > 1.001, final_dmg)
		hits += 1
	SfxPlayer.play("fire")
	_spawn_beam(origin, origin + dir * length)
	if hits > 0:
		GameState.request_camera_shake.emit(2.0, 0.1)

## Effective beam length, scaled by the player's range upgrades so the stat
## applies here as well as to projectile weapons.
func _length() -> float:
	if config == null:
		return 0.0
	return config.laser_length * float(GameState.weapon_range_mult)

func _spawn_beam(from: Vector2, to: Vector2) -> void:
	var line := Line2D.new()
	line.top_level = true
	line.width = config.laser_width
	line.default_color = Color(0.55, 0.9, 1.0, 0.75)
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.points = PackedVector2Array([from, to])
	get_tree().current_scene.add_child(line)
	# A bright thin core over the wide glow, so the beam reads as focused rather
	# than as a fat translucent bar.
	var core := Line2D.new()
	core.top_level = true
	core.width = maxf(2.0, config.laser_width * 0.25)
	core.default_color = Color(1.0, 1.0, 1.0, 0.95)
	core.points = line.points
	get_tree().current_scene.add_child(core)
	for l in [line, core]:
		var tw: Tween = l.create_tween()
		tw.tween_property(l, "modulate:a", 0.0, BEAM_FADE)
		tw.tween_callback(l.queue_free)
