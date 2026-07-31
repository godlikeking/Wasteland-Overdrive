extends Node2D
## FX manager. Listens to GameState feedback signals and spawns particles,
## floating labels, camera shake, and hit-stop. Attached under Game so all
## FX live in world space with the arena.

@export var camera_path: NodePath          # ShakeCamera (in Player)
@export var floating_label_scene: PackedScene
@export var enemy_death_particles_scene: PackedScene
@export var bullet_hit_particles_scene: PackedScene

var _camera: Node

func _ready() -> void:
	add_to_group("fx_manager")
	# Resolve camera lazily; the player scene may not be fully ready yet.
	call_deferred("_resolve_camera")
	GameState.enemy_died.connect(_on_enemy_died)
	GameState.bullet_hit.connect(_on_bullet_hit)
	GameState.player_hurt.connect(_on_player_hurt)
	GameState.xp_collected.connect(_on_xp_collected)
	GameState.leveled_up.connect(_on_leveled_up)
	GameState.request_camera_shake.connect(_on_shake)
	GameState.request_hit_stop.connect(_on_hit_stop)

func _resolve_camera() -> void:
	if camera_path != NodePath():
		_camera = get_node_or_null(camera_path)
	if _camera == null:
		# Fallback: find Camera2D anywhere under the current scene
		var found: Array = get_tree().get_nodes_in_group("shake_camera")
		if not found.is_empty():
			_camera = found[0]

# --- Signal handlers ---

func _on_enemy_died(pos: Vector2, dir: Vector2) -> void:
	_spawn_particles(enemy_death_particles_scene, pos, dir)
	GameState.request_camera_shake.emit(3.0, 0.12)
	GameState.request_hit_stop.emit(0.04)

func _on_bullet_hit(pos: Vector2) -> void:
	_spawn_particles(bullet_hit_particles_scene, pos, Vector2.ZERO)
	GameState.request_camera_shake.emit(1.2, 0.06)

func _on_player_hurt(_pos: Vector2) -> void:
	GameState.request_camera_shake.emit(6.0, 0.35)
	GameState.request_hit_stop.emit(0.08)

func _on_xp_collected(pos: Vector2, amount: float) -> void:
	_spawn_label(pos, "+%d XP" % max(1, int(amount)), Color(0.4, 0.9, 1.0))

func _on_leveled_up(level: int) -> void:
	# Show over player (found via group).
	var player_pos: Vector2 = Vector2.ZERO
	var players: Array = get_tree().get_nodes_in_group("player")
	if not players.is_empty() and players[0] is Node2D:
		player_pos = (players[0] as Node2D).global_position
	_spawn_label(player_pos, "Lv. %d!" % level, Color(1.0, 0.85, 0.3), 36, 1.2)
	GameState.request_camera_shake.emit(4.0, 0.25)

func _on_shake(strength: float, duration: float) -> void:
	if _camera == null:
		_resolve_camera()
	if _camera and _camera.has_method("shake"):
		_camera.shake(strength, duration)

func _on_hit_stop(duration: float) -> void:
	# Freeze physics/process for `duration` real seconds by scaling time.
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0

# --- Helpers ---

func _spawn_particles(scene: PackedScene, pos: Vector2, dir: Vector2) -> void:
	if scene == null:
		return
	var p: Node = scene.instantiate()
	add_child(p)
	if p is Node2D:
		(p as Node2D).global_position = pos
	if p.has_method("set_hit_direction"):
		p.set_hit_direction(dir)

func _spawn_label(pos: Vector2, text: String, color: Color,
		font_size: int = 20, life: float = 0.7) -> void:
	if floating_label_scene == null:
		return
	var lbl: Node = floating_label_scene.instantiate()
	add_child(lbl)
	if lbl is Node2D:
		(lbl as Node2D).global_position = pos
	if lbl.has_method("setup"):
		lbl.setup(text, color, font_size, life)
