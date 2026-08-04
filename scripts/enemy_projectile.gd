extends Area2D
## Enemy-fired bullet. Slow, decent damage, despawns on lifetime or player hit.

@onready var sprite: Sprite2D = $Sprite2D

var velocity: Vector2 = Vector2.ZERO
var damage: float = 8.0
var lifetime: float = 1.4
var _age: float = 0.0
var _enemy_bullet: bool = true

const ENEMY_BULLET_SPRITE: String = "res://assets/sprites/bullets/enemy_bullet.png"
const ENEMY_BULLET_SPRITE_SCALE: float = 2.0

func _apply_sprite() -> void:
	if sprite == null:
		return
	var tex: Texture2D = load(ENEMY_BULLET_SPRITE) as Texture2D
	if tex:
		sprite.texture = tex
		sprite.scale = Vector2(ENEMY_BULLET_SPRITE_SCALE, ENEMY_BULLET_SPRITE_SCALE)

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
	_apply_sprite()
	# 不再染色：红紫配色已经烘进 enemy_bullet.png，再叠一层红会把品红高光压死。
	# 玩家弹 / 敌弹靠造型区分（细长金黄曳光弹 vs 短粗等离子球），不靠 modulate。
	SfxPlayer.play("fire")

func _physics_process(delta: float) -> void:
	# Time-stop item: bullets already in flight hang in the air. Their lifetime
	# is frozen too, so the freeze can't be used to make them expire harmlessly.
	if GameState.is_time_stopped():
		return
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
