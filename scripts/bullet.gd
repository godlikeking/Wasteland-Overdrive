extends Area2D
## Simple straight-line bullet. Damages the first enemy it hits and despawns.
## Also emits a `bullet_hit` juice event on impact and drags a Line2D trail.

@export var trail_length: int = 8   # number of points in the trail

@onready var sprite: Sprite2D = $Sprite2D
@onready var trail: Line2D = $Trail

var velocity: Vector2 = Vector2.ZERO
var damage: float = 10.0
var lifetime: float = 1.2
var _age: float = 0.0

const BULLET_SPRITE: String = "res://assets/sprites/bullets/bullet.png"
const BULLET_SPRITE_SCALE: float = 2.0

func _apply_sprite() -> void:
	if sprite == null:
		return
	var tex: Texture2D = load(BULLET_SPRITE) as Texture2D
	if tex:
		sprite.texture = tex
		sprite.scale = Vector2(BULLET_SPRITE_SCALE, BULLET_SPRITE_SCALE)

func setup(p_velocity: Vector2, p_damage: float, p_lifetime: float) -> void:
	velocity = p_velocity
	damage = p_damage
	lifetime = p_lifetime
	rotation = velocity.angle()

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	_apply_sprite()
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
		# 暴击判定：连击 + 基础 crit_rate 提升暴击概率
		var mult: float = GameState.roll_crit()
		var final_dmg: float = damage * mult
		node.take_damage(final_dmg, hit_dir)
		GameState.bullet_hit.emit(global_position, mult > 1.001, final_dmg)
		queue_free()
