extends CharacterBody2D
## Player scavenger. Handles movement, health, damage-flash, pickup radius,
## and hosts an AutoGun child that fires automatically.

signal died

@export var base_speed: float = 220.0
@export var base_max_hp: float = 100.0
@export var invuln_time: float = 0.4
@export var base_pickup_radius: float = 60.0

## 玩家精灵底色。普通敌人也是 16×16 Kenney 图 + scale 3.0 + 不染色，
## 其中 chaser 同样是钢色主导，光换贴图会撞；冷蓝把玩家单独拉出来
## （原色 = 杂兵，红染 = 精英/BOSS）。_flash_damage 必须补间回这个值，
## 不是回 Color(1,1,1)，否则挨一下之后底色就永久丢了。
## 蓝通道故意 >1：只压暗红绿的话（0.62,0.82,1.0）和 chaser 的平均色距只有 32，
## 抬蓝之后是 52。亮钢会溢出成纯蓝白，但亮钢/暗钢/轮廓三层明度仍然分得开。
const BASE_TINT: Color = Color(0.5, 0.75, 1.35)

@onready var sprite: Sprite2D = $Sprite2D
@onready var pickup_area: Area2D = $PickupArea
@onready var pickup_shape: CollisionShape2D = $PickupArea/CollisionShape2D
@onready var invuln_timer: Timer = $InvulnTimer

var max_hp: float
var hp: float
var invulnerable: bool = false
var alive: bool = true
var swamp_slow: float = 1.0   # 1.0 = full speed, 0.5 = half

func _ready() -> void:
	add_to_group("player")
	max_hp = base_max_hp + float(GameState.max_hp_bonus)
	hp = max_hp
	_apply_sprite()
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
	velocity = dir * base_speed * speed_mult * swamp_slow
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
	# The shield eats the whole hit regardless of size, but still grants the
	# usual invulnerability window so a swarm can't strip every charge in one
	# frame.
	if GameState.consume_shield():
		invulnerable = true
		invuln_timer.start()
		_flash_shield()
		GameState.player_hurt.emit(global_position)
		SfxPlayer.play("hit")
		return
	hp -= amount
	invulnerable = true
	invuln_timer.start()
	_flash_damage()
	GameState.player_hurt.emit(global_position)
	GameState.player_health_changed.emit(hp, max_hp)
	if hp <= 0.0:
		_die()

## Restore health, clamped to the current maximum. Used by the heal pickup.
## Returns the amount actually restored, so the caller can skip the "+N" label
## when the player was already at full health.
func heal(amount: float) -> float:
	if not alive or amount <= 0.0:
		return 0.0
	var before: float = hp
	hp = minf(max_hp, hp + amount)
	var gained: float = hp - before
	if gained > 0.0:
		GameState.player_health_changed.emit(hp, max_hp)
		_flash_heal()
	return gained

func _flash_damage() -> void:
	sprite.modulate = Color(1.6, 0.4, 0.4)
	var tw: Tween = create_tween()
	tw.tween_property(sprite, "modulate", BASE_TINT, 0.25)

## Absorbed hit: cyan pop instead of the red damage flash, so "shield held" and
## "I actually lost health" never read the same.
func _flash_shield() -> void:
	sprite.modulate = Color(0.6, 1.8, 2.0)
	var tw: Tween = create_tween()
	tw.tween_property(sprite, "modulate", BASE_TINT, 0.3)

func _flash_heal() -> void:
	sprite.modulate = Color(0.6, 1.6, 0.7)
	var tw: Tween = create_tween()
	tw.tween_property(sprite, "modulate", BASE_TINT, 0.3)

func _on_invuln_end() -> void:
	invulnerable = false

func _update_pickup_radius() -> void:
	var r: float = base_pickup_radius * float(GameState.pickup_radius_mult)
	if pickup_shape.shape is CircleShape2D:
		(pickup_shape.shape as CircleShape2D).radius = r

func _apply_sprite() -> void:
	# Kenney Tiny Dungeon tile_0087（板甲骑士），16x16 原始尺寸，scale 3x 到 48px。
	var tex: Texture2D = load("res://assets/sprites/player/player.png") as Texture2D
	if tex:
		sprite.texture = tex
		sprite.modulate = BASE_TINT
		# Centre the sprite on the body so the camera follows the visual centre.
		var cs: Node = get_node_or_null("CollisionShape2D")
		if cs and cs.shape is CircleShape2D:
			sprite.scale = Vector2(3.0, 3.0)  # 16px -> 48px visual
			sprite.position = Vector2(0, 0)

func _die() -> void:
	alive = false
	velocity = Vector2.ZERO
	died.emit()
	GameState.player_died.emit()

# --- ToxicSwamp hook ---
func set_swamp_slow(factor: float) -> void:
	swamp_slow = maxf(0.05, factor)
