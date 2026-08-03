extends Area2D
## Straight-line bullet. Damages enemies it touches and despawns once it runs
## out of pierces, travel distance, or lifetime. Also emits a `bullet_hit`
## juice event on impact.

@onready var sprite: Sprite2D = $Sprite2D

var velocity: Vector2 = Vector2.ZERO
var damage: float = 10.0
var lifetime: float = 1.2
var max_distance: float = 0.0     # px; 0 = unlimited, fall back to lifetime
var pierce_left: int = 0          # extra enemies this bullet may punch through
var _age: float = 0.0
var _travelled: float = 0.0
var _hit_ids: Dictionary = {}     # instance_id -> true, so one enemy is hit once

const BULLET_SPRITE: String = "res://assets/sprites/bullets/bullet.png"
const BULLET_SPRITE_SCALE: float = 2.0

func _apply_sprite() -> void:
	if sprite == null:
		return
	var tex: Texture2D = load(BULLET_SPRITE) as Texture2D
	if tex:
		sprite.texture = tex
		sprite.scale = Vector2(BULLET_SPRITE_SCALE, BULLET_SPRITE_SCALE)

func setup(p_velocity: Vector2, p_damage: float, p_lifetime: float, p_max_distance: float = 0.0) -> void:
	velocity = p_velocity
	damage = p_damage
	lifetime = p_lifetime
	max_distance = p_max_distance
	rotation = velocity.angle()
	# When a range is set it becomes the authoritative cap, so stretch lifetime
	# to just past it. Otherwise lifetime would silently clip the range and any
	# range upgrade the player bought would do nothing.
	var speed: float = velocity.length()
	if max_distance > 0.0 and speed > 0.0:
		lifetime = maxf(lifetime, max_distance / speed + 0.1)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	pierce_left = GameState.pierce_count
	_apply_sprite()

func _physics_process(delta: float) -> void:
	var step: Vector2 = velocity * delta
	global_position += step
	_age += delta
	_travelled += step.length()
	if max_distance > 0.0 and _travelled >= max_distance:
		queue_free()
		return
	if _age >= lifetime:
		queue_free()

func _on_body_entered(body: Node) -> void:
	_try_hit(body)

func _on_area_entered(area: Area2D) -> void:
	_try_hit(area)

func _try_hit(node: Node) -> void:
	# Enemy projectiles share the Enemy collision layer, so area_entered fires
	# for them too. Everything below — the pierce spend included — has to stay
	# behind this group check, or flying through enemy fire would eat pierces.
	if not node.is_in_group("enemies") or not node.has_method("take_damage"):
		return
	# Enemies have no i-frames and can re-enter our 5px circle while we keep
	# flying, so remember who we already hit.
	var id: int = node.get_instance_id()
	if _hit_ids.has(id):
		return
	_hit_ids[id] = true

	var hit_dir: Vector2 = velocity.normalized() if velocity.length_squared() > 0.0 else Vector2.ZERO
	# 暴击判定：连击 + 基础 crit_rate 提升暴击概率
	var mult: float = GameState.roll_crit()
	var final_dmg: float = damage * mult
	node.take_damage(final_dmg, hit_dir)
	GameState.bullet_hit.emit(global_position, mult > 1.001, final_dmg)

	if pierce_left <= 0:
		queue_free()
		return
	# Punch through, but each subsequent enemy takes less.
	pierce_left -= 1
	damage *= GameState.pierce_damage_falloff
