extends CharacterBody2D
## Melee enemy that walks toward the player and damages on contact.
## Drops an XP gem on death.

@export var speed: float = 90.0
@export var max_hp: float = 20.0
@export var contact_damage: float = 12.0
@export var attack_cooldown: float = 0.6
@export var xp_value: float = 1.0
@export var xp_gem_scene: PackedScene

@onready var sprite: Sprite2D = $Sprite2D

var hp: float
var _attack_timer: float = 0.0
var _player: Node2D
var _flash_tw: Tween
var _last_hit_dir: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("enemies")
	hp = max_hp
	_player = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return

	# Chase the player. Scale to full speed regardless of framerate.
	var dir: Vector2 = (_player.global_position - global_position).normalized()
	velocity = dir * speed
	move_and_slide()

	if _attack_timer > 0.0:
		_attack_timer -= delta

	# Contact damage while overlapping.
	for i in range(get_slide_collision_count()):
		var col: KinematicCollision2D = get_slide_collision(i)
		var collider: Object = col.get_collider()
		if collider and collider.is_in_group("player") and _attack_timer <= 0.0:
			if collider.has_method("take_damage"):
				collider.take_damage(contact_damage)
				_attack_timer = attack_cooldown

func take_damage(amount: float, hit_dir: Vector2 = Vector2.ZERO) -> void:
	hp -= amount
	if hit_dir != Vector2.ZERO:
		_last_hit_dir = hit_dir
	_flash()
	if hp <= 0.0:
		_die()

func _flash() -> void:
	if _flash_tw and _flash_tw.is_valid():
		_flash_tw.kill()
	sprite.modulate = Color(2.5, 2.5, 2.5)
	_flash_tw = create_tween()
	_flash_tw.tween_property(sprite, "modulate", Color(1, 1, 1), 0.14)

func _die() -> void:
	GameState.enemy_died.emit(global_position, _last_hit_dir)
	if xp_gem_scene:
		var gem: Node = xp_gem_scene.instantiate()
		if gem is Node2D:
			(gem as Node2D).global_position = global_position
		if gem.has_method("set_value"):
			gem.set_value(xp_value)
		get_tree().current_scene.add_child(gem)
	queue_free()
