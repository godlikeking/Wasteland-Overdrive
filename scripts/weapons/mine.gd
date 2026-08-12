extends Area2D
## One proximity mine dropped by MineLayerWeapon. Arms after a short delay, then
## detonates on enemy contact or when its lifetime runs out — either way through
## the shared explosion scene, so a mine blast and a bomb-pickup blast behave
## identically.
##
## The arming delay exists because the mine is laid at the player's feet: without
## it, a mine would go off in the player's face the instant an enemy is already
## touching them.

@export var explosion_scene: PackedScene

@onready var sprite: Sprite2D = $Sprite2D

var blast_radius: float = 150.0
var damage: float = 40.0
var arm_time: float = 0.4
var life: float = 8.0

var _age: float = 0.0
var _armed: bool = false
## Guards against a double detonation when contact and expiry land on the same
## frame; queue_free only takes effect at the end of it.
var _spent: bool = false

## Blink period once the mine is armed, so a live mine is distinguishable from
## one still settling.
const BLINK_TIME: float = 0.5
## Last seconds before expiry are spent blinking fast as a warning.
const PANIC_LEAD: float = 1.5
const PANIC_BLINK_TIME: float = 0.14

func setup(p_radius: float, p_damage: float, p_arm_time: float, p_life: float) -> void:
	blast_radius = maxf(1.0, p_radius)
	damage = maxf(0.0, p_damage)
	arm_time = maxf(0.0, p_arm_time)
	life = maxf(0.1, p_life)

func _ready() -> void:
	add_to_group("mines")
	# 躺在地上，但**不能用负 z**：TileMap 在 z=0，负 z 会被整张地图盖掉，雷就
	# 彻底看不见、只剩爆炸那一下。想画在角色下面靠的是"挂在 World 名下"
	# （见 mine_layer._lay），不是负 z。毒池踩过同一个坑（以前用 -5）。
	z_index = 0
	body_entered.connect(_on_touch)
	area_entered.connect(_on_touch)

func _physics_process(delta: float) -> void:
	# Time-stop freezes mines too: their fuse is enemy-facing, and letting it
	# burn down during a freeze would quietly waste the item.
	if GameState.is_time_stopped():
		return
	_age += delta
	if not _armed and _age >= arm_time:
		_armed = true
	_update_blink()
	if _age >= life:
		_detonate()
		return
	# Contact only reports enemies that ENTER the area, so an enemy already
	# standing on an unarmed mine would never trigger it. Re-scan once armed.
	if _armed:
		for e in get_overlapping_bodies():
			if e.is_in_group("enemies"):
				_detonate()
				return

func _on_touch(node: Node) -> void:
	if not _armed or not node.is_in_group("enemies"):
		return
	_detonate()

func _detonate() -> void:
	if _spent:
		return
	_spent = true
	if explosion_scene:
		var boom: Node = explosion_scene.instantiate()
		if boom is Node2D:
			(boom as Node2D).global_position = global_position
		if boom.has_method("setup"):
			boom.setup(blast_radius, damage, Color(1.0, 0.62, 0.25))
		# Parented to the scene, not to us: we are about to free ourselves.
		get_tree().current_scene.add_child(boom)
	queue_free()

func _update_blink() -> void:
	if sprite == null:
		return
	if not _armed:
		sprite.modulate = Color(0.6, 0.6, 0.65)
		return
	var left: float = life - _age
	var period: float = PANIC_BLINK_TIME if left <= PANIC_LEAD else BLINK_TIME
	var lit: bool = fmod(_age, period) < period * 0.45
	sprite.modulate = Color(1.6, 0.5, 0.4) if lit else Color(0.7, 0.55, 0.5)
