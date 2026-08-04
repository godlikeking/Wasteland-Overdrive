extends BaseWeapon
class_name HomingDartWeapon
## Fires guided darts that bend toward the nearest enemy. Low damage per dart and
## a slow turn rate, so it can't chase a fast dasher forever — it exists to punish
## the player never having to aim, while still missing anything that keeps moving.
##
## The guidance itself lives in bullet.gd (`set_homing`); this weapon only decides
## how many darts to launch and how hard they may turn.

@onready var timer: Timer = $Timer

func _ready() -> void:
	super._ready()
	if timer:
		timer.one_shot = false
		timer.timeout.connect(_on_fire)

func _post_setup() -> void:
	if timer == null:
		return
	timer.wait_time = get_fire_interval()
	timer.start()

func _process(_delta: float) -> void:
	if timer and config != null and absf(timer.wait_time - get_fire_interval()) > 0.02:
		timer.wait_time = get_fire_interval()
		if timer.is_stopped():
			timer.start()

func _on_fire() -> void:
	_fire()

func _fire() -> void:
	if config == null or config.projectile_scene == null:
		return
	if not is_instance_valid(_owner):
		return
	var target: Node2D = _find_nearest_enemy(get_range())
	if target == null:
		return
	var to_target: Vector2 = (target.global_position - _owner.global_position).normalized()
	var count: int = 1 + int(GameState.extra_projectiles)
	var damage: float = get_damage()
	for i in range(count):
		var offset_index: float = float(i) - float(count - 1) / 2.0
		# Launch the darts wide on purpose: they curve back in, which is what
		# makes the homing legible instead of looking like a straight shot.
		var angle: float = deg_to_rad(config.projectile_spread_deg) * offset_index
		_spawn_dart(to_target.rotated(angle), damage)
	SfxPlayer.play("fire")

func _spawn_dart(dir: Vector2, damage: float) -> void:
	var b: Node = config.projectile_scene.instantiate()
	get_tree().current_scene.add_child(b)
	b.global_position = _owner.global_position
	if b.has_method("setup"):
		b.setup(dir * config.projectile_speed, damage, config.projectile_lifetime, get_range())
	if b.has_method("set_homing"):
		b.set_homing(config.homing_turn_rate)
