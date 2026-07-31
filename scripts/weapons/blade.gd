extends Area2D
## One orbiting blade. Has two modes:
##  - orbit: called by OrbitingBladesWeapon._process (no logic here, just sits)
##  - dash:  called via launch_dash(); flies straight, deals damage on hit,
##           returns to orbit when finished.

@onready var sprite: Sprite2D = $Sprite2D
@onready var hit_shape: CollisionShape2D = $CollisionShape2D

var _velocity: Vector2 = Vector2.ZERO
var _damage: float = 0.0
var _age: float = 0.0
var _lifetime: float = 0.6
var _dashing: bool = false
var _owner_weapon: Node = null

func _ready() -> void:
	body_entered.connect(_on_hit)
	area_entered.connect(_on_hit)
	if hit_shape:
		hit_shape.disabled = true
	add_to_group("blades")

func launch_dash(direction: Vector2, damage: float, lifetime: float, owner_weapon: Node) -> void:
	_velocity = direction
	_damage = damage
	_lifetime = max(0.1, lifetime)
	_age = 0.0
	_dashing = true
	_owner_weapon = owner_weapon
	rotation = direction.angle()
	if hit_shape:
		hit_shape.disabled = false
	sprite.modulate = Color(1.4, 1.4, 1.4)

func _physics_process(delta: float) -> void:
	if not _dashing:
		return
	global_position += _velocity * delta
	_age += delta
	if _age >= _lifetime:
		_return_to_orbit()

func _on_hit(node: Node) -> void:
	if not _dashing:
		return
	if node.is_in_group("enemies") and node.has_method("take_damage"):
		node.take_damage(_damage, _velocity.normalized())
		GameState.bullet_hit.emit(global_position)
		_return_to_orbit()

func _return_to_orbit() -> void:
	_dashing = false
	_age = 0.0
	if hit_shape:
		hit_shape.disabled = true
	sprite.modulate = Color(1, 1, 1)
	if _owner_weapon and is_instance_valid(_owner_weapon):
		var root: Node2D = _owner_weapon.get_node_or_null("Blades")
		if root and root.is_inside_tree():
			root.add_child(self)
			remove_meta("dashing")
