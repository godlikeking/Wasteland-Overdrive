extends CharacterBody2D
## Player scavenger. Handles movement, health, damage-flash, pickup radius,
## and hosts an AutoGun child that fires automatically.

signal died

@export var base_speed: float = 220.0
@export var base_max_hp: float = 100.0
@export var invuln_time: float = 0.4
@export var base_pickup_radius: float = 60.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var pickup_area: Area2D = $PickupArea
@onready var pickup_shape: CollisionShape2D = $PickupArea/CollisionShape2D
@onready var invuln_timer: Timer = $InvulnTimer

var max_hp: float
var hp: float
var invulnerable: bool = false
var alive: bool = true

func _ready() -> void:
	add_to_group("player")
	max_hp = base_max_hp + float(GameState.max_hp_bonus)
	hp = max_hp
	_update_pickup_radius()
	invuln_timer.wait_time = invuln_time
	invuln_timer.one_shot = true
	invuln_timer.timeout.connect(_on_invuln_end)
	GameState.player_health_changed.emit(hp, max_hp)

func _physics_process(delta: float) -> void:
	if not alive:
		return

	# Movement input
	var dir: Vector2 = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if dir.length_squared() > 1.0:
		dir = dir.normalized()

	var speed_mult: float = float(GameState.move_speed_mult)
	velocity = dir * base_speed * speed_mult
	move_and_slide()

	# Regen and dynamic max_hp adjustments each frame
	max_hp = base_max_hp + float(GameState.max_hp_bonus)
	var regen: float = float(GameState.hp_regen_per_sec)
	if regen > 0.0 and hp < max_hp:
		hp = min(max_hp, hp + regen * delta)
		GameState.player_health_changed.emit(hp, max_hp)

	_update_pickup_radius()

func take_damage(amount: float) -> void:
	if not alive or invulnerable:
		return
	hp -= amount
	invulnerable = true
	invuln_timer.start()
	_flash_damage()
	GameState.player_hurt.emit(global_position)
	GameState.player_health_changed.emit(hp, max_hp)
	if hp <= 0.0:
		_die()

func _flash_damage() -> void:
	sprite.modulate = Color(1.6, 0.4, 0.4)
	var tw: Tween = create_tween()
	tw.tween_property(sprite, "modulate", Color(1, 1, 1), 0.25)

func _on_invuln_end() -> void:
	invulnerable = false

func _update_pickup_radius() -> void:
	var r: float = base_pickup_radius * float(GameState.pickup_radius_mult)
	if pickup_shape.shape is CircleShape2D:
		(pickup_shape.shape as CircleShape2D).radius = r

func _die() -> void:
	alive = false
	velocity = Vector2.ZERO
	died.emit()
	GameState.player_died.emit()
