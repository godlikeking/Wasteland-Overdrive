extends Node2D
## Spawns enemies just outside the camera view on a rising cadence.
## Difficulty scales with `GameState.time_alive`.

@export var enemy_scene: PackedScene
@export var camera: Camera2D
@export var player_path: NodePath
@export var base_interval: float = 1.4
@export var min_interval: float = 0.20
@export var difficulty_ramp_time: float = 240.0   # seconds to reach min interval
@export var spawn_padding: float = 80.0            # pixels outside viewport
@export var burst_growth: float = 0.02             # extra enemies per second alive

var _spawn_accum: float = 0.0
var _player: Node2D

func _ready() -> void:
	if player_path != NodePath():
		_player = get_node_or_null(player_path)

func _process(delta: float) -> void:
	if enemy_scene == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return

	var t: float = GameState.time_alive
	var progress: float = clamp(t / difficulty_ramp_time, 0.0, 1.0)
	var interval: float = lerp(base_interval, min_interval, progress)

	_spawn_accum += delta
	if _spawn_accum >= interval:
		_spawn_accum = 0.0
		var burst: int = 1 + int(t * burst_growth)
		for i in range(burst):
			_spawn_one()

func _spawn_one() -> void:
	var enemy: Node = enemy_scene.instantiate()
	if enemy is Node2D:
		(enemy as Node2D).global_position = _random_offscreen_point()
	get_tree().current_scene.add_child(enemy)

func _random_offscreen_point() -> Vector2:
	var vp: Vector2 = get_viewport_rect().size
	var cam_pos: Vector2 = _player.global_position
	var zoom: Vector2 = Vector2.ONE
	if camera and is_instance_valid(camera):
		cam_pos = camera.global_position
		zoom = camera.zoom
	else:
		# The player scene has its own Camera2D. Try to find it.
		var cam: Node = _player.get_node_or_null("Camera2D")
		if cam and cam is Camera2D:
			zoom = (cam as Camera2D).zoom
	# Visible world size = viewport / zoom. Add padding for offscreen spawn.
	var half: Vector2 = (vp / zoom) * 0.5 + Vector2(spawn_padding, spawn_padding)
	var side: int = randi() % 4
	match side:
		0: return cam_pos + Vector2(randf_range(-half.x, half.x), -half.y)
		1: return cam_pos + Vector2(randf_range(-half.x, half.x), half.y)
		2: return cam_pos + Vector2(-half.x, randf_range(-half.y, half.y))
		_: return cam_pos + Vector2(half.x, randf_range(-half.y, half.y))
