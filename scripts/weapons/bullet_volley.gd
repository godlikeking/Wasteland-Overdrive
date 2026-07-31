extends BaseWeapon
class_name BulletVolleyWeapon
## Shoots N bullets at the nearest enemy every fire cycle. N defaults to 1
## and grows with GameState.extra_projectiles (existing upgrade).

@onready var timer: Timer = $Timer

func _ready() -> void:
	super._ready()
	# Hook up the signal now, but DON'T start the timer until setup() injects
	# the config. Otherwise the first wait_time = 0/0 = ~20s.
	if timer:
		timer.one_shot = false
		timer.timeout.connect(_on_fire)

func _post_setup() -> void:
	if timer == null:
		return
	timer.wait_time = get_fire_interval()
	timer.start()

func _process(_delta: float) -> void:
	# Keep fire interval in sync with dynamic multipliers.
	if timer and config != null and abs(timer.wait_time - get_fire_interval()) > 0.02:
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
	var target: Node2D = _find_nearest_enemy()
	if target == null:
		return
	var to_target: Vector2 = (target.global_position - _owner.global_position).normalized()
	var count: int = 1 + int(GameState.extra_projectiles)
	var damage: float = get_damage()

	for i in range(count):
		var offset_index: float = float(i) - float(count - 1) / 2.0
		var angle: float = deg_to_rad(config.projectile_spread_deg) * offset_index
		var dir: Vector2 = to_target.rotated(angle)
		_spawn_bullet(dir, damage)
	SfxPlayer.play("fire")

func _spawn_bullet(dir: Vector2, damage: float) -> void:
	var b: Node = config.projectile_scene.instantiate()
	get_tree().current_scene.add_child(b)
	b.global_position = _owner.global_position
	if b.has_method("setup"):
		b.setup(dir * config.projectile_speed, damage, config.projectile_lifetime)
