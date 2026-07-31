extends Area2D
## Experience gem dropped by dead enemies. Homes to the player when
## picked-up by the player's PickupArea, then grants XP.

@export var pickup_scene_speed: float = 320.0
@export var seek_accel: float = 900.0

@onready var sprite: Sprite2D = $Sprite2D

var value: float = 1.0
var _seeking: bool = false
var _target: Node2D
var _velocity: Vector2 = Vector2.ZERO

const XP_GEM_SPRITE: String = "res://assets/sprites/gems/xp_gem.png"
const XP_GEM_SPRITE_SCALE: float = 2.0

func _apply_sprite() -> void:
	if sprite == null:
		return
	var tex: Texture2D = load(XP_GEM_SPRITE) as Texture2D
	if tex:
		sprite.texture = tex
		sprite.scale = Vector2(XP_GEM_SPRITE_SCALE, XP_GEM_SPRITE_SCALE)
		# Gem png is upright; undo the 45° rotation used by the placeholder.
		sprite.rotation = 0.0

func _ready() -> void:
	add_to_group("xp_gems")
	_apply_sprite()
	area_entered.connect(_on_area_entered)

func set_value(v: float) -> void:
	value = v

func _physics_process(delta: float) -> void:
	if not _seeking or _target == null or not is_instance_valid(_target):
		return
	var to_target: Vector2 = (_target.global_position - global_position).normalized()
	_velocity = _velocity.move_toward(to_target * pickup_scene_speed, seek_accel * delta)
	global_position += _velocity * delta
	if global_position.distance_to(_target.global_position) < 10.0:
		GameState.add_xp(value)
		GameState.xp_collected.emit(global_position, value)
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	# The player's PickupArea starts the seek behavior.
	if _seeking:
		return
	var parent := area.get_parent()
	if parent and parent.is_in_group("player"):
		_target = parent
		_seeking = true
