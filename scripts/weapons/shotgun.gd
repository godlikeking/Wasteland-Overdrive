extends BaseWeapon
class_name ShotgunWeapon
## Fires a tight fan of `config.pellet_count` pellets at the nearest enemy.
## Short range, no crowd control, but every pellet rolls its own crit — so it
## deletes whatever it is pressed against.
##
## Deliberately a near-copy of BulletVolleyWeapon rather than a subclass of it:
## the two differ only in how the fan is sized, and inheriting would make the
## volley's "count = 1 + extras" the base case for a weapon whose whole identity
## is "count = many".

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
	var count: int = maxi(1, config.pellet_count) + int(GameState.extra_projectiles)
	var damage: float = get_damage()
	for i in range(count):
		var offset_index: float = float(i) - float(count - 1) / 2.0
		# Jitter each pellet a little so two volleys never lay down the exact
		# same pattern — a shotgun that fires a rigid comb reads as a laser rake.
		var jitter: float = randf_range(-0.35, 0.35)
		var angle: float = deg_to_rad(config.projectile_spread_deg) * (offset_index + jitter)
		_spawn_pellet(to_target.rotated(angle), damage)
	SfxPlayer.play("fire")

func _spawn_pellet(dir: Vector2, damage: float) -> void:
	var b: Node = config.projectile_scene.instantiate()
	get_tree().current_scene.add_child(b)
	b.global_position = _owner.global_position
	if b.has_method("setup"):
		# Vary the speed slightly too, so the fan spreads out as it travels
		# instead of staying a perfect arc.
		var speed: float = config.projectile_speed * randf_range(0.9, 1.1)
		b.setup(dir * speed, damage, config.projectile_lifetime, get_range())
