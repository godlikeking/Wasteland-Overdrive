extends Area2D
## Simple straight-line bullet. Damages the first enemy it hits and despawns.
## Also emits a `bullet_hit` juice event on impact and drags a Line2D trail.

@export var trail_length: int = 8   # number of points in the trail

@onready var trail: Line2D = $Trail

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
	# Trail draws in global space so it stays behind while bullet moves.
	if trail:
		trail.top_level = true
		trail.clear_points()
		trail.add_point(global_position)

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	_age += delta
	if trail:
		trail.add_point(global_position)
		while trail.get_point_count() > trail_length:
			trail.remove_point(0)
	if _age >= lifetime:
		queue_free()

func _on_body_entered(body: Node) -> void:
	_try_hit(body)

func _on_area_entered(area: Area2D) -> void:
	_try_hit(area)

func _try_hit(node: Node) -> void:
	if node.is_in_group("enemies") and node.has_method("take_damage"):
		var hit_dir: Vector2 = velocity.normalized() if velocity.length_squared() > 0.0 else Vector2.ZERO
		node.take_damage(damage, hit_dir)
		GameState.bullet_hit.emit(global_position)
		queue_free()
