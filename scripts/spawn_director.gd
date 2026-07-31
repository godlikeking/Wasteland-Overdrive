extends Node2D
## Wave / archetype scheduler. Picks an EnemyConfig based on elapsed time
## (GameState.time_alive) and spawns it just outside the camera view.
##
## Archetype cadence (seconds alive):
##   0:00 -> only chasers
##   1:00 -> introduce dasher (20% chance at any non-elite spawn)
##   2:00 -> introduce shooter (30% chance)
##   3:30 -> mixed: chaser/dasher/shooter at 50/20/30
##   5:00 -> every 30s, an elite spawns in addition to the normal cadence
##
## Difficulty: spawn interval shrinks from `base_interval` to `min_interval`
## over `difficulty_ramp_time`, mirroring the original EnemySpawner.

@export var enemy_scene: PackedScene
@export var xp_gem_scene: PackedScene
@export var enemy_projectile_scene: PackedScene
@export var camera: Camera2D
@export var player_path: NodePath
@export var configs_path: NodePath  # Node that has enemy configs as children
@export var base_interval: float = 1.2
@export var min_interval: float = 0.18
@export var difficulty_ramp_time: float = 240.0
@export var spawn_padding: float = 80.0
@export var burst_growth: float = 0.02
@export var start_wave_shake: float = 5.0
@export var elite_interval: float = 30.0

var _spawn_accum: float = 0.0
var _elite_accum: float = 0.0
var _player: Node2D
var _configs_root: Node
var _configs: Array = []  # Array[EnemyConfig]

func _ready() -> void:
	if player_path != NodePath():
		_player = get_node_or_null(player_path)
	if configs_path != NodePath():
		_configs_root = get_node_or_null(configs_path)
	_cache_configs()
	GameState.leveled_up.connect(_on_leveled_up)
	print("[SpawnDirector] ready with %d configs" % _configs.size())

func _cache_configs() -> void:
	_configs.clear()
	if _configs_root == null:
		# Fallback: load known configs by resource path.
		for path in [
			"res://data/enemies/chaser.tres",
			"res://data/enemies/dasher.tres",
			"res://data/enemies/shooter.tres",
			"res://data/enemies/elite_brute.tres",
		]:
			var res: Resource = ResourceLoader.load(path)
			if res is EnemyConfig:
				_configs.append(res as EnemyConfig)
		_inject_runtime_refs(_configs)
		return
	for child in _configs_root.get_children():
		if child is EnemyConfig:
			_configs.append(child as EnemyConfig)
	_inject_runtime_refs(_configs)

func _inject_runtime_refs(list: Array) -> void:
	for c in list:
		if not (c is EnemyConfig):
			continue
		var ec: EnemyConfig = c as EnemyConfig
		if ec.scene == null:
			ec.scene = enemy_scene
		if ec.xp_gem_scene == null:
			ec.xp_gem_scene = xp_gem_scene
		if ec.behavior == EnemyConfig.Behavior.SHOOTER and ec.projectile_scene == null:
			ec.projectile_scene = enemy_projectile_scene

func _process(delta: float) -> void:
	if _configs.is_empty():
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return

	# --- Difficulty interval ---
	var t: float = GameState.time_alive
	var progress: float = clamp(t / difficulty_ramp_time, 0.0, 1.0)
	var interval: float = lerp(base_interval, min_interval, progress)

	# --- Regular cadence ---
	_spawn_accum += delta
	if _spawn_accum >= interval:
		_spawn_accum = 0.0
		var burst: int = 1 + int(t * burst_growth)
		for i in range(burst):
			_spawn_one(_pick_archetype(false))

	# --- Elite cadence ---
	_elite_accum += delta
	if _elite_accum >= elite_interval and t >= 300.0:
		_elite_accum = 0.0
		_spawn_one(_pick_archetype(true), true)
		GameState.request_camera_shake.emit(start_wave_shake, 0.35)
		GameState.request_hit_stop.emit(0.06)
		# Big floating label
		var player_pos: Vector2 = _player.global_position
		_spawn_label(player_pos, "ELITE WAVE", Color(1, 0.4, 0.4), 30, 1.4)

func _pick_archetype(force_elite: bool) -> EnemyConfig:
	if force_elite:
		return _find_config("elite_brute")
	var t: float = GameState.time_alive
	var roll: float = randf()
	if t < 60.0:
		return _find_config("chaser")
	# t in [60, 120)
	if t < 120.0:
		# chaser 80% / dasher 20%
		return _find_config("dasher") if roll < 0.2 else _find_config("chaser")
	# t in [120, 210)
	if t < 210.0:
		# chaser 60% / dasher 15% / shooter 25%
		if roll < 0.6: return _find_config("chaser")
		if roll < 0.75: return _find_config("dasher")
		return _find_config("shooter")
	# t >= 210
	# chaser 45% / dasher 20% / shooter 30% / elite 5%
	var elite_r: float = 0.05
	if roll < elite_r: return _find_config("elite_brute")
	if roll < elite_r + 0.45: return _find_config("chaser")
	if roll < elite_r + 0.65: return _find_config("dasher")
	return _find_config("shooter")

func _find_config(id: String) -> EnemyConfig:
	for c in _configs:
		if c is EnemyConfig and (c as EnemyConfig).id == id:
			return c as EnemyConfig
	# Hard fallback.
	return _configs[0] if not _configs.is_empty() else null

func _spawn_one(cfg: EnemyConfig, announce: bool = false) -> void:
	if cfg == null or cfg.scene == null:
		return
	var enemy: Node = cfg.scene.instantiate()
	if enemy is Node2D:
		(enemy as Node2D).global_position = _random_offscreen_point()
	# Pass config via a typed method to avoid `set()` Variant assignment
	# tripping the @export strong-typed setter.
	if enemy.has_method("setup_config"):
		enemy.setup_config(cfg)
	get_tree().current_scene.add_child(enemy)
	if announce:
		print("[SpawnDirector] spawned %s" % cfg.id)

func _random_offscreen_point() -> Vector2:
	var vp: Vector2 = get_viewport_rect().size
	var cam_pos: Vector2 = _player.global_position
	var zoom: Vector2 = Vector2.ONE
	if camera and is_instance_valid(camera):
		cam_pos = camera.global_position
		zoom = camera.zoom
	else:
		var cam: Node = _player.get_node_or_null("Camera2D")
		if cam and cam is Camera2D:
			zoom = (cam as Camera2D).zoom
	var half: Vector2 = (vp / zoom) * 0.5 + Vector2(spawn_padding, spawn_padding)
	var side: int = randi() % 4
	match side:
		0: return cam_pos + Vector2(randf_range(-half.x, half.x), -half.y)
		1: return cam_pos + Vector2(randf_range(-half.x, half.x), half.y)
		2: return cam_pos + Vector2(-half.x, randf_range(-half.y, half.y))
		_: return cam_pos + Vector2(half.x, randf_range(-half.y, half.y))

func _spawn_label(pos: Vector2, text: String, color: Color, font_size: int, life: float) -> void:
	var list: Array = get_tree().get_nodes_in_group("fx_manager")
	if list.is_empty():
		return
	var fx: Node = list[0]
	if fx and fx.has_method("_spawn_label"):
		fx._spawn_label(pos, text, color, font_size, life)

func _on_leveled_up(_lvl: int) -> void:
	GameState.request_camera_shake.emit(2.0, 0.15)
