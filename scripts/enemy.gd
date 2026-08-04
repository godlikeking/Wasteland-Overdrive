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
const REPATH_INTERVAL: float = 0.3

## Sprite tint this enemy returns to after a flash. Cached because
## `_apply_visuals` gives elites and the boss a red tint, and `_flash()` used to
## tween back to `config.sprite_color` instead — so an elite permanently lost
## its red the first time it was hit.
var _base_tint: Color = Color(1, 1, 1)
## True while the time-stop item has this enemy frozen; used to restore the tint
## exactly once when the freeze lifts.
var _frozen: bool = false
## Tint applied while frozen: drained, cold blue-grey.
const FROZEN_TINT: Color = Color(0.45, 0.62, 0.95)

# Behavior runtime state
var _dash_timer: float = 0.0
var _dashing: bool = false
var _dash_time_left: float = 0.0
var _shoot_timer: float = 0.0

# BOSS-specific runtime
var _boss_summon_accum: float = 0.0
var _boss_bullet_accum: float = 0.0
var _boss_phase: int = 1   # 1, 2, 3

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
	# Real Kenney pixel art (16x16 source, scale up to 48x48 for readability).
	var path: String = _sprite_path_for(config.id)
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
		# Boss is 4.5× (72px), elites stay 3× (48px) with a red tint.
		if config.behavior == EnemyConfig.Behavior.BOSS:
			sprite.scale = Vector2(4.5, 4.5)
			sprite.modulate = Color(1.2, 0.6, 0.6)
		elif config.behavior == EnemyConfig.Behavior.ELITE:
			sprite.scale = Vector2(3.0, 3.0)
			sprite.modulate = Color(1.4, 0.6, 0.6)
		else:
			sprite.scale = Vector2(3.0, 3.0)
			sprite.modulate = Color(1, 1, 1)
	else:
		# Fallback: gradient texture (original placeholder behaviour).
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
	# Whatever branch above ran, that tint is now this enemy's identity colour.
	# Flashes and the time-stop thaw both restore it from here.
	_base_tint = sprite.modulate
	var cs: Node = get_node_or_null("CollisionShape2D")
	if cs and cs.shape is CircleShape2D:
		(cs.shape as CircleShape2D).radius = config.collision_radius

func _sprite_path_for(id: String) -> String:
	match id:
		"chaser": return "res://assets/sprites/enemies/chaser.png"
		"dasher": return "res://assets/sprites/enemies/dasher.png"
		"shooter": return "res://assets/sprites/enemies/shooter.png"
		"elite_brute": return "res://assets/sprites/enemies/elite.png"
		"boss": return "res://assets/sprites/enemies/boss.png"
	return ""

func _physics_process(delta: float) -> void:
	if config == null:
		return
	# Time-stop item: freeze in place, keep the hitbox so the player can farm
	# frozen enemies. Cooldown timers are deliberately NOT ticked, so the freeze
	# does not hand out free attack windups either.
	if GameState.is_time_stopped():
		if not _frozen:
			_frozen = true
			velocity = Vector2.ZERO
			if _flash_tw and _flash_tw.is_valid():
				_flash_tw.kill()
			sprite.modulate = FROZEN_TINT
		return
	if _frozen:
		_frozen = false
		sprite.modulate = _base_tint
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
		EnemyConfig.Behavior.BOSS:
			_behavior_boss(delta)

func _behavior_chaser(delta: float) -> void:
	_maybe_repath(delta)
	var dir: Vector2 = _steer_dir()
	velocity = dir * _effective_speed()
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

# --- BOSS ----------------------------------------------------------
# 3 阶段基于当前 HP 比例：
#   P1 (>60%):    慢追 + 每 4s 召唤 2 只 chaser
#   P2 (30-60%):  稍快追 + 每 3s 召唤 3 只 + 每 1.2s 1 发面向玩家
#   P3 (<30%):    再快 + 每 2.5s 召唤 4 只 + 每 0.8s 3 发扇形弹幕
func _behavior_boss(delta: float) -> void:
	_maybe_repath(delta)
	# 更新阶段
	var hp_frac: float = clampf(hp / max(1.0, config.max_hp), 0.0, 1.0)
	var prev_phase: int = _boss_phase
	if hp_frac <= config.boss_phase3_hp_frac:
		_boss_phase = 3
	elif hp_frac <= config.boss_phase2_hp_frac:
		_boss_phase = 2
	else:
		_boss_phase = 1
	if _boss_phase != prev_phase:
		GameState.request_camera_shake.emit(4.0, 0.25)
		GameState.request_hit_stop.emit(0.05)
		_announce_phase(prev_phase, _boss_phase)

	# 速度：P1 1.0×  P2 1.2×  P3 1.4×
	var speed_mult: float = [1.0, 1.0, 1.2, 1.4][_boss_phase]
	var dir: Vector2 = _steer_dir()
	velocity = dir * _effective_speed() * speed_mult
	move_and_slide()
	_apply_contact_damage()

	# 召唤节奏
	var summon_int: float = config.boss_summon_interval
	var summon_n: int = config.boss_summon_count
	match _boss_phase:
		2: summon_int *= 0.75; summon_n += 1
		3: summon_int *= 0.6;  summon_n += 2
	_boss_summon_accum += delta
	if _boss_summon_accum >= summon_int:
		_boss_summon_accum = 0.0
		_boss_summon_minions(summon_n)

	# 弹幕（P2 / P3）
	if _boss_phase >= 2:
		_boss_bullet_accum += delta
		var bullet_int: float = config.boss_bullet_interval
		if _boss_phase == 3:
			bullet_int *= 0.65
		if _boss_bullet_accum >= bullet_int:
			_boss_bullet_accum = 0.0
			_boss_volley()

func _announce_phase(prev: int, cur: int) -> void:
	var list: Array = get_tree().get_nodes_in_group("fx_manager")
	if list.is_empty():
		return
	var fx: Node = list[0]
	var label: String = "阶段 %d" % cur
	var col: Color = Color(1, 0.7, 0.3)
	if cur == 3: col = Color(1, 0.3, 0.3)
	if fx.has_method("_spawn_label"):
		fx._spawn_label(global_position, label, col, 30, 1.2)

func _boss_summon_minions(n: int) -> void:
	# 通过 BossSpawner 注册的 _summon_minion 回调（如果存在），否则跳过。
	# 简化实现：直接在 Boss 周围生成 chaser 配置的实例。
	var directors: Array = get_tree().get_nodes_in_group("boss_spawner")
	if directors.is_empty():
		return
	var sp: Node = directors[0]
	if sp and sp.has_method("spawn_minion_around"):
		sp.spawn_minion_around(global_position, config.boss_minion_id, n)

func _boss_volley() -> void:
	# 面向玩家发射 boss_bullet_count 发均匀分布的弹
	if _player == null or not is_instance_valid(_player):
		return
	var to_player: Vector2 = _player.global_position - global_position
	if to_player.length_squared() < 0.01:
		return
	var base: float = to_player.angle()
	var n: int = max(1, config.boss_bullet_count)
	if _boss_phase == 3:
		# 三路：再补 2 个偏 ±18°
		for i in range(3):
			var off: float = [-0.32, 0.0, 0.32][i]
			_fire_projectile(Vector2.RIGHT.rotated(base + off),
				config.boss_bullet_speed, 8.0)
	else:
		# 1 发正对玩家
		_fire_projectile(Vector2.RIGHT.rotated(base),
			config.boss_bullet_speed, 8.0)

func _fire_projectile(dir: Vector2, speed: float = -1.0, damage: float = -1.0) -> void:
	if config.projectile_scene == null:
		return
	var p: Node = config.projectile_scene.instantiate()
	get_tree().current_scene.add_child(p)
	if p is Node2D:
		(p as Node2D).global_position = global_position
	var sp: float = speed if speed > 0.0 else config.projectile_speed
	var dm: float = damage if damage > 0.0 else config.projectile_damage
	if p.has_method("setup"):
		p.setup(dir * sp, dm, 1.4)
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
	# 维护连击（任何玩家命中都算）
	GameState.register_hit()
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
	# While frozen the enemy must stay blue, so a hit during time-stop should not
	# leave it tinted the wrong colour once the flash finishes.
	var back_to: Color = FROZEN_TINT if _frozen else _base_tint
	sprite.modulate = Color(2.5, 2.5, 2.5)
	_flash_tw = create_tween()
	_flash_tw.tween_property(sprite, "modulate", back_to, 0.14)

func _die() -> void:
	var was_elite: bool = config != null and config.behavior == EnemyConfig.Behavior.ELITE
	var was_boss: bool = config != null and config.behavior == EnemyConfig.Behavior.BOSS
	GameState.enemy_died.emit(global_position, _last_hit_dir, was_elite or was_boss)
	if has_node("/root/MetaProgress"):
		MetaProgress.record_kill()
	if was_boss:
		GameState.request_camera_shake.emit(config.boss_shake_on_death, 0.8)
		GameState.request_hit_stop.emit(0.18)
		# 额外震屏
		GameState.request_camera_shake.emit(6.0, 0.5)
		if has_node("/root/MetaProgress"):
			MetaProgress.record_boss_kill()
	elif was_elite:
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
		elif config.behavior == EnemyConfig.Behavior.BOSS:
			gem_xp *= config.boss_xp_multiplier
		if gem.has_method("set_value"):
			gem.set_value(gem_xp)
		get_tree().current_scene.add_child(gem)
	_drop_items()
	queue_free()

## Scatter `config.item_drop_count` pickups around the corpse. Driven by the
## config rather than by "was this camp-spawned", so a time-based ELITE WAVE
## elite drops exactly like a camp elite does.
func _drop_items() -> void:
	if config == null or config.item_drop_count <= 0 or config.item_drop_scene == null:
		return
	var n: int = config.item_drop_count
	for i in range(n):
		var item: Node = config.item_drop_scene.instantiate()
		if item is Node2D:
			# Spread the drops on a ring so several items never stack into one
			# unreadable pile.
			var ang: float = TAU * float(i) / float(n) + randf() * 0.5
			var dist: float = 0.0 if n == 1 else randf_range(24.0, 44.0)
			(item as Node2D).global_position = global_position + Vector2(cos(ang), sin(ang)) * dist
		if item.has_method("setup"):
			item.setup(PickupItem.roll_kind())
		get_tree().current_scene.add_child(item)

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
