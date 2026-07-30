extends Node2D
## Auto-firing weapon attached to the player. Every fire cycle it selects
## the nearest enemy and shoots one (or more) bullets toward it.

@export var bullet_scene: PackedScene
@export var base_fire_rate: float = 2.5   # shots per second
@export var base_damage: float = 10.0
@export var bullet_speed: float = 520.0
@export var bullet_lifetime: float = 1.2
@export var spread_deg: float = 6.0        # angle between extra projectiles

@onready var timer: Timer = $Timer

func _ready() -> void:
	timer.one_shot = false
	timer.timeout.connect(_on_fire)
	_restart_timer()

func _process(_delta: float) -> void:
	# Keep timer in sync with dynamic fire-rate multiplier.
	# NOTE: Autoload members are seen as Variant by the static analyzer,
	# so we spell out `float` on every local var that touches them.
	var rate_mult: float = float(GameState.fire_rate_mult)
	var expected: float = 1.0 / maxf(0.05, base_fire_rate * rate_mult)
	if abs(timer.wait_time - expected) > 0.02:
		timer.wait_time = expected

func _restart_timer() -> void:
	var rate_mult: float = float(GameState.fire_rate_mult)
	timer.wait_time = 1.0 / maxf(0.05, base_fire_rate * rate_mult)
	timer.start()

func _on_fire() -> void:
	if bullet_scene == null:
		return
	var target: Node2D = _nearest_enemy()
	if target == null:
		return
	var to_target: Vector2 = (target.global_position - global_position).normalized()
	var extra: int = int(GameState.extra_projectiles)
	var count: int = 1 + extra
	var damage: float = base_damage * float(GameState.damage_mult)

	# Fan out extra projectiles symmetrically around the aim vector.
	for i in range(count):
		var offset_index: float = float(i) - float(count - 1) / 2.0
		var angle: float = deg_to_rad(spread_deg) * offset_index
		var dir: Vector2 = to_target.rotated(angle)
		_spawn_bullet(dir, damage)

func _spawn_bullet(dir: Vector2, damage: float) -> void:
	var b: Node = bullet_scene.instantiate()
	get_tree().current_scene.add_child(b)
	b.global_position = global_position
	if b.has_method("setup"):
		b.setup(dir * bullet_speed, damage, bullet_lifetime)

func _nearest_enemy() -> Node2D:
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var best: Node2D = null
	var best_d: float = INF
	for e in enemies:
		if not (e is Node2D):
			continue
		var d: float = (e.global_position - global_position).length_squared()
		if d < best_d:
			best_d = d
			best = e
	return best
