extends Area2D
## Simple straight-line bullet. Damages the first enemy it hits and despawns.

var velocity: Vector2 = Vector2.ZERO
var damage: float = 10.0
var lifetime: float = 1.2
var _age: float = 0.0

func setup(p_velocity: Vector2, p_damage: float, p_lifetime: float) -> void:
	velocity = p_velocity
	damage = p_damage
	lifetime = p_lifetime
	rotation = velocity.angle()

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	_age += delta
	if _age >= lifetime:
		queue_free()

func _on_body_entered(body: Node) -> void:
	_try_hit(body)

func _on_area_entered(area: Area2D) -> void:
	_try_hit(area)

func _try_hit(node: Node) -> void:
	if node.is_in_group("enemies") and node.has_method("take_damage"):
		node.take_damage(damage)
		queue_free()
