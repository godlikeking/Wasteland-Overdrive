extends Area2D
## Enemy-fired bullet. Slow, decent damage, despawns on lifetime or player hit.

var velocity: Vector2 = Vector2.ZERO
var damage: float = 8.0
var lifetime: float = 1.4
var _age: float = 0.0
var _enemy_bullet: bool = true

func setup(p_velocity: Vector2, p_damage: float, p_lifetime: float) -> void:
	velocity = p_velocity
	damage = p_damage
	lifetime = p_lifetime
	rotation = velocity.angle()

func set_enemy_bullet(v: bool) -> void:
	_enemy_bullet = v

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	modulate = Color(1.0, 0.5, 0.5, 1)

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	_age += delta
	if _age >= lifetime:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	# The player's PickupArea also counts as area entered; ignore.
	if area.get_parent() and area.get_parent().is_in_group("player"):
		return
