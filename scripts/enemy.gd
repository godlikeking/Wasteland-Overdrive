extends CharacterBody2D
## Multi-behavior enemy. Movement and combat are driven by an EnemyConfig
## resource so we can spawn chasers, shooters, dashers, and elites from
## a single class.

@export var config: EnemyConfig

@onready var sprite: Sprite2D = $Sprite2D
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

var hp: float
var _attack_timer: float = 0.0
var _player: Node2D
var _flash_tw: Tween
var _last_hit_dir: Vector2 = Vector2.ZERO
var swamp_slow: float = 1.0   # toxic swamp slow multiplier
var _repath_accum: float = 0.0
var _nav_warmup: float = 0.4
var _debug_printed: bool = false
const REPATH_INTERVAL: float = 0.3

# Behavior runtime state
var _dash_timer: float = 0.0
var _dashing: bool = false
var _dash_time_left: float = 0.0
var _shoot_timer: float = 0.0

func setup_config(p_config: EnemyConfig) -> void:
	config = p_config
	if is_node_ready():
		_apply_visuals()
		hp = config.max_hp

func _ready() -> void:
	add_to_group("enemies")
	if config:
		hp = config.max_hp
		_apply_visuals()
	_player = get_tree().get_first_node_in_group("player")
	# Randomize phase a bit so they don't sync up.
	if config:
		_dash_timer = randf_range(0.5, max(0.5, config.dash_interval))
		_shoot_timer = randf_range(0.2, 1.0)
	# Initial target. The first frame's nav path may be empty if the agent
	# hasn't synced with the world navigation map yet; that's fine.
	if nav_agent and _player and is_instance_valid(_player):
		nav_agent.target_position = _player.global_position

func _apply_visuals() -> void:
	if config == null:
		return
	# Always give the enemy an opaque gradient sprite at the configured size.
	if sprite.texture == null:
		var grad: Gradient = Gradient.new()
		grad.colors = PackedColorArray()
		grad.colors.append(config.sprite_color)
		grad.colors.append(config.sprite_color)
		var tex: GradientTexture2D = GradientTexture2D.new()
		tex.gradient = grad
		tex.width = int(config.sprite_size.x)
		tex.height = int(config.sprite_size.y)
		sprite.texture = tex
	else:
		sprite.modulate = config.sprite_color
	var cs: Node = get_node_or_null("CollisionShape2D")
	if cs and cs.shape is CircleShape2D:
		(cs.shape as CircleShape2D).radius = config.collision_radius

func _physics_process(delta: float) -> void:
	if config == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return
	if _nav_warmup > 0.0:
		_nav_warmup -= delta

	if _attack_timer > 0.0:
		_attack_timer -= delta

	match config.behavior:
		EnemyConfig.Behavior.CHASER:
			_behavior_chaser(delta)
		EnemyConfig.Behavior.DASHER:
			_behavior_dasher(delta)
		EnemyConfig.Behavior.SHOOTER:
			_behavior_shooter(delta)
		EnemyConfig.Behavior.ELITE:
			_behavior_chaser(delta)  # elites just chase but are tanky

func _behavior_chaser(delta: float) -> void:
	_maybe_repath(delta)
	var dir: Vector2 = _steer_dir()
	velocity = dir * _effective_speed()
	if not _debug_printed:
		_debug_printed = true
		print("[Enemy] pos=%s player=%s dir=%s vel=%s speed=%s nav_agent=%s path_size=%d warmup=%s hp=%s" % [
			str(global_position), str(_player.global_position), str(dir),
			str(velocity), str(_effective_speed()),
			"null" if nav_agent == null else "ok",
			nav_agent.get_current_navigation_path().size() if nav_agent else -1,
			str(_nav_warmup), str(hp)
		])
	move_and_slide()
	_apply_contact_damage()

func _behavior_dasher(delta: float) -> void:
	_dash_timer -= delta
	if _dashing:
		_dash_time_left -= delta
		if _dash_time_left <= 0.0:
			_dashing = false
		# Dash: still steer around walls, but the next path point.
		_maybe_repath(delta)
		var dir: Vector2 = _steer_dir()
		velocity = dir * _effective_speed() * config.dash_speed_multiplier
		move_and_slide()
	elif _dash_timer <= 0.0:
		_dashing = true
		_dash_time_left = config.dash_duration
		_dash_timer = config.dash_interval
		GameState.request_camera_shake.emit(1.5, 0.10)
	else:
		_maybe_repath(delta)
		var dir: Vector2 = _steer_dir()
		velocity = dir * _effective_speed() * 0.35
		move_and_slide()
	_apply_contact_damage()

func _behavior_shooter(delta: float) -> void:
	_maybe_repath(delta)
	# Keep preferred range: steer toward or away to maintain shoot_range.
	var to_player: Vector2 = _player.global_position - global_position
	var dist: float = to_player.length()
	var dir: Vector2 = to_player / max(0.001, dist)
	var steer: Vector2 = _steer_dir()
	var target_speed: float = _effective_speed()
	if dist > config.shoot_range + 30.0:
		velocity = steer * target_speed
	elif dist < config.shoot_range - 30.0:
		velocity = -steer * target_speed
	else:
		# Strafe: small lateral motion so it doesn't feel static.
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		velocity = perp * target_speed * 0.5
	move_and_slide()
	_apply_contact_damage()

	_shoot_timer -= delta
	if _shoot_timer <= 0.0:
		_shoot_timer = config.shoot_cooldown
		_fire_projectile(dir)

func _fire_projectile(dir: Vector2) -> void:
	if config.projectile_scene == null:
		return
	var p: Node = config.projectile_scene.instantiate()
	get_tree().current_scene.add_child(p)
	if p is Node2D:
		(p as Node2D).global_position = global_position
	if p.has_method("setup"):
		p.setup(dir * config.projectile_speed, config.projectile_damage, 1.4)
	# Mark the projectile as enemy bullet — see scripts/enemy_projectile.gd.
	if p.has_method("set_enemy_bullet"):
		p.set_enemy_bullet(true)

func _apply_contact_damage() -> void:
	if _attack_timer > 0.0:
		return
	for i in range(get_slide_collision_count()):
		var col: KinematicCollision2D = get_slide_collision(i)
		var collider: Object = col.get_collider()
		if collider and collider.is_in_group("player") and _attack_timer <= 0.0:
			if collider.has_method("take_damage"):
				collider.take_damage(config.contact_damage)
				_attack_timer = config.contact_cooldown

func take_damage(amount: float, hit_dir: Vector2 = Vector2.ZERO) -> void:
	hp -= amount
	if hit_dir != Vector2.ZERO:
		_last_hit_dir = hit_dir
	_flash()
	if hp <= 0.0:
		_die()

# --- ToxicSwamp hook ---
func set_swamp_slow(factor: float) -> void:
	swamp_slow = maxf(0.05, factor)

func _effective_speed() -> float:
	return config.speed * swamp_slow

func _flash() -> void:
	if _flash_tw and _flash_tw.is_valid():
		_flash_tw.kill()
	sprite.modulate = Color(2.5, 2.5, 2.5)
	_flash_tw = create_tween()
	_flash_tw.tween_property(sprite, "modulate", config.sprite_color if config else Color(1, 1, 1), 0.14)

func _die() -> void:
	GameState.enemy_died.emit(global_position, _last_hit_dir)
	if config and config.behavior == EnemyConfig.Behavior.ELITE:
		GameState.request_camera_shake.emit(config.elite_shake, 0.45)
		GameState.request_hit_stop.emit(0.12)
	# Drop XP
	if config and config.xp_gem_scene:
		var gem: Node = config.xp_gem_scene.instantiate()
		if gem is Node2D:
			(gem as Node2D).global_position = global_position
		var gem_xp: float = config.xp_value
		if config.behavior == EnemyConfig.Behavior.ELITE:
			gem_xp *= config.elite_xp_multiplier
		if gem.has_method("set_value"):
			gem.set_value(gem_xp)
		get_tree().current_scene.add_child(gem)
	queue_free()

# --- Navigation ---

func _maybe_repath(delta: float) -> void:
	_repath_accum += delta
	if _repath_accum < REPATH_INTERVAL:
		return
	_repath_accum = 0.0
	if nav_agent == null or _player == null or not is_instance_valid(_player):
		return
	nav_agent.target_position = _player.global_position

func _steer_dir() -> Vector2:
	# During the warmup window (NavigationServer syncing TileMap polygons),
	# fall back to direct chase so enemies don't freeze on spawn.
	if _nav_warmup > 0.0 or nav_agent == null or _player == null or not is_instance_valid(_player):
		return (_player.global_position - global_position).normalized()
	# Always refresh the target every frame — cheap, and avoids the
	# 0.3s-stale target issue when the player moves.
	nav_agent.target_position = _player.global_position
	# Trust get_current_navigation_path().size() over is_navigation_finished():
	# the latter can return false while get_next_path_position() still
	# returns the agent's own position (mid-computation). If the path
	# array has fewer than 2 points (no start + end), we don't have a
	# real path yet.
	var path: PackedVector2Array = nav_agent.get_current_navigation_path()
	if path.size() < 2:
		return (_player.global_position - global_position).normalized()
	var next: Vector2 = nav_agent.get_next_path_position()
	var d: Vector2 = next - global_position
	if d.length_squared() < 1.0:
		return (_player.global_position - global_position).normalized()
	return d.normalized()
