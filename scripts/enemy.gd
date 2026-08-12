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
var _boss_poison_accum: float = 0.0
## 爪击冷却计时（从 0 往上累，>= cooldown 才能起手）。
var _claw_accum: float = 0.0
## 预警剩余秒数；> 0 表示正在举爪，此时巨兽定住脚。
var _claw_wind_left: float = 0.0
## 起手瞬间锁定的朝向。锁死是有意的：这是玩家横向拉开就能躲的那个反制点，
## 如果每帧跟着玩家转，爪击就变成了不可躲的必中伤害。
var _claw_facing: Vector2 = Vector2.ZERO
var _claw_fx: Node2D = null
## 冲刺冷却计时（从 0 往上累，>= cooldown 才能起手）。
var _dash_accum: float = 0.0
## 蓄力剩余秒数；> 0 表示正在蓄力，此时巨兽定住脚。
var _dash_wind_left: float = 0.0
## 冲刺剩余秒数；> 0 表示正在冲，此时只沿 _dash_facing 直线移动。
## （名字避开通用 DASHER 行为占用的 `_dash_time_left` —— 两个行为互不相干，
## 共用一个字段是埋雷。）
var _dash_run_left: float = 0.0
## 冲完的硬直剩余秒数；> 0 表示定在原地，这是玩家反打的窗口。
var _dash_recover_left: float = 0.0
## 起手瞬间锁定的冲刺方向。和 _claw_facing 同一个锁死理由。
var _dash_facing: Vector2 = Vector2.ZERO
## 本次冲刺是否已经结算过命中：一次冲刺至多打一次。
var _dash_hit_done: bool = false
var _dash_fx: Node2D = null

# 巨型机器人（GOBOT）状态
var _gobot_laser_accum: float = 0.0
var _gobot_laser_wind_left: float = 0.0
var _gobot_laser_facing: Vector2 = Vector2.ZERO
var _gobot_missile_accum: float = 0.0
var _gobot_stomp_accum: float = 0.0
var _gobot_stomp_wind_left: float = 0.0
var _gobot_stomp_air_left: float = 0.0
var _gobot_stomp_recover_left: float = 0.0
var _gobot_stomp_hit_done: bool = false
# 进阶三招（按阶段解锁）：电球 P1 起、多道闪电 P2 起、扔地雷 P3 起。
var _gobot_orb_accum: float = 0.0
var _gobot_bolt_accum: float = 0.0
var _gobot_bolt_wind_left: float = 0.0
var _gobot_bolt_angles: PackedFloat32Array = PackedFloat32Array()
var _gobot_bolt_fx: Node2D = null
var _gobot_mine_accum: float = 0.0
## BOSS 竞技场（第二关）活动范围，世界坐标。空矩形 = 不牵制。
## 由 SpawnDirector 在竞技场刷 BOSS 时设置，防止玩家未进门前 BOSS 追出房间。
var arena_rect: Rect2 = Rect2()

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
		# BOSS 上屏 config.sprite_size（448px），杂兵/精英固定 3×（16px → 48px）。
		#
		# BOSS 的倍数**从贴图原生尺寸算**，不写死：这里原来是硬编码 28×，那是
		# 按 16×16 素材算的（16 × 28 = 448）。giant_robot.png 换成 160×160 之后
		# 那个 28 直接把它渲染成 4480px —— 十倍大，而且不报任何错。换算成
		# sprite_size ÷ 原生尺寸就自愈了：16px 素材得 28×、160px 素材得 2.8×，
		# 两者上屏都是 448px，判定框（collision_radius 224）不用跟着动。
		# 杂兵**不**能这么算：它们的 sprite_size 是遗留占位值（16~20），不是
		# 想要的上屏尺寸，按它算会把杂兵缩到 20px。
		if config.behavior == EnemyConfig.Behavior.BOSS \
				or config.behavior == EnemyConfig.Behavior.GOBOT:
			sprite.scale = Vector2.ONE * boss_sprite_scale(
				config.sprite_size.x, sprite.texture.get_size().x)
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
	if config.behavior == EnemyConfig.Behavior.BOSS:
		# 直径 224px 的身体放不进 64px 的障碍格缝隙，会被地形卡死在废墟后面
		# 干瞪眼。巨兽踏碎废墟：清掉 World 层（bit 1）的碰撞遮罩，只留玩家层
		# （bit 2）—— 接触伤害靠 get_slide_collision 走玩家层，不受影响。
		# 寻路照旧：NavigationAgent 绕的是它现在已经能踩过去的障碍，
		# 路径次优但不会错，比重写一套 BOSS 专用寻路安全。
		set_collision_mask_value(1, false)

## BOSS 精灵的放大倍数：想要的上屏尺寸 ÷ 贴图原生尺寸。
##
## 纯函数，所以"换了贴图还能不能正确上屏"这件事能被自检直接断言 —— 这正是
## 硬编码 28× 那版悄悄坏掉的地方（素材从 16px 换成 160px，渲染成了 4480px，
## 没有任何报错）。原生尺寸为 0（贴图缺失）时退回 1.0 而不是除零。
static func boss_sprite_scale(want_px: float, native_px: float) -> float:
	if native_px <= 0.0:
		return 1.0
	return maxf(0.01, want_px) / native_px

## HUD 的 BOSS 血条用：第一关是废土巨兽，第二关是巨型机器人。
func get_boss_display_name() -> String:
	if config != null:
		return config.display_name
	return "废土巨兽"

func _sprite_path_for(id: String) -> String:
	match id:
		"chaser": return "res://assets/sprites/enemies/chaser.png"
		"dasher": return "res://assets/sprites/enemies/dasher.png"
		"shooter": return "res://assets/sprites/enemies/shooter.png"
		"elite_brute": return "res://assets/sprites/enemies/elite.png"
		"boss": return "res://assets/sprites/enemies/boss.png"
		"machine_dog": return "res://assets/sprites/enemies/machine_dog.png"
		"robot": return "res://assets/sprites/enemies/robot.png"
		"decay_knight": return "res://assets/sprites/enemies/decay_knight.png"
		"giant_robot": return "res://assets/sprites/enemies/giant_robot.png"
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
		EnemyConfig.Behavior.GOBOT:
			_behavior_gobot(delta)

func _behavior_chaser(delta: float) -> void:
	_maybe_repath(delta)
	var dir: Vector2 = _steer_dir()
	velocity = dir * _effective_speed()
	move_and_slide()
	_apply_contact_damage()

# 突袭者跳跃状态（和 BOSS 的 _dash_* 字段互不冲突，避开共用）。
var _jump_accum: float = 0.0
var _jump_wind_left: float = 0.0
var _jump_air_left: float = 0.0
var _jump_recover_left: float = 0.0
var _jump_facing: Vector2 = Vector2.ZERO
var _jump_hit_done: bool = false
var _jump_fx: Node2D = null

func _behavior_dasher(delta: float) -> void:
	# 跳跃优先：蓄力期和落地硬直都定住脚，和 BOSS 爪击/冲刺同一套否决逻辑。
	var jumping: bool = _dasher_jump(delta)
	if jumping:
		# 跳跃中自己 move_and_collide，跳过接触伤害（单一伤害来源 = jump_damage）。
		return
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
		# 靠近玩家时加速逼近：远距离慢速接近(35%)，进入逼近距离后随距离变近
		# 线性加速到满速，让"贴近"读作追击而不是原地爬行。
		var aggro: float = 0.35
		if _player != null and is_instance_valid(_player):
			var dist: float = global_position.distance_to(_player.global_position)
			var ramp: float = clampf(1.0 - dist / maxf(1.0, config.jump_max_range), 0.0, 1.0)
			aggro = lerpf(0.35, 1.0, ramp)
		velocity = dir * _effective_speed() * aggro
		# 静止/减速期也定住脚（蓄力 / 硬直）。
		if _jump_wind_left > 0.0 or _jump_recover_left > 0.0:
			velocity = Vector2.ZERO
		move_and_slide()
	_apply_contact_damage()

## 突袭者跳跃状态机。和 BOSS 冲刺同一套骨架：蓄力（定脚 + 锁方向）→
## 空中直线跃起 → 落地 AoE 伤害 → 硬直（惩罚窗口）→ 冷却。
## 返回 true 表示本帧处于跳跃中（调用方跳过自己的 move_and_slide 和接触伤害）。
func _dasher_jump(delta: float) -> bool:
	if _jump_wind_left > 0.0:
		_jump_wind_left -= delta
		if _jump_wind_left <= 0.0:
			_jump_start()
		return false
	if _jump_air_left > 0.0:
		_jump_air_left -= delta
		velocity = _jump_facing * config.jump_speed
		move_and_collide(velocity * delta)
		if _jump_air_left <= 0.0:
			_jump_air_left = 0.0
			_jump_land()
			_jump_recover_left = config.jump_recover
			GameState.request_camera_shake.emit(3.0, 0.15)
		return true
	if _jump_recover_left > 0.0:
		_jump_recover_left -= delta
		if _jump_recover_left <= 0.0:
			_jump_recover_left = 0.0
		return false
	# 冷却：够近就起手。
	_jump_accum += delta
	if _jump_accum < config.jump_cooldown:
		return false
	if _player == null or not is_instance_valid(_player):
		return false
	var to_player: Vector2 = _player.global_position - global_position
	var dist: float = to_player.length()
	if dist < config.jump_min_range or dist > config.jump_max_range:
		return false
	# 起手：锁定方向、生成预告线。
	_jump_accum = 0.0
	_jump_wind_left = config.jump_windup
	_jump_facing = to_player.normalized()
	_jump_hit_done = false
	var expect_len: float = config.jump_speed * config.jump_duration
	_jump_fx = DashTelegraph.new()
	(_jump_fx as DashTelegraph).setup(_jump_facing, expect_len, config.jump_windup)
	add_child(_jump_fx)
	GameState.request_camera_shake.emit(1.0, 0.08)
	return false

func _jump_start() -> void:
	_jump_wind_left = 0.0
	_jump_air_left = config.jump_duration
	if _jump_fx != null and is_instance_valid(_jump_fx) and _jump_fx.has_method("strike"):
		_jump_fx.strike()
	_jump_fx = null
	SfxPlayer.play("boom")

func _jump_land() -> void:
	# 落地范围伤害：对跳跃落点半径内的玩家结算一次。
	if _jump_hit_done:
		return
	if _player == null or not is_instance_valid(_player):
		return
	if global_position.distance_to(_player.global_position) > config.jump_impact_radius:
		return
	_jump_hit_done = true
	if _player.has_method("take_damage"):
		_player.take_damage(config.jump_damage)
	# 落地粒子：复用爆炸场景的 `_draw()` 视觉（explosion.tscn 只打敌人组，
	# 伤害已在上面结算），纯画面。
	var fx_scene: PackedScene = load("res://scenes/fx/explosion.tscn") as PackedScene
	var fx: Node = fx_scene.instantiate()
	fx.setup(config.jump_impact_radius, 0.0, Color(1.0, 0.55, 0.2, 0.7))
	_add_to_scene(fx)
	fx.global_position = global_position

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
#   P1 (>60%):    慢追 + 每 4s 召唤 2 只 chaser + 毒物 + 爪击
#   P2 (30-60%):  稍快追 + 每 3s 召唤 3 只 + 每 1.2s 1 发 + 毒物加量
#   P3 (<30%):    再快 + 每 2.5s 召唤 4 只 + 每 0.8s 3 发扇形 + 毒物再加量
#
# 两套攻击分工明确、覆盖不同距离，所以近身和拉开都各有一种压力：
#   近战爪击（<= boss_claw_reach ≈ 190px）：预警 0.45s，起手即锁朝向，
#     打的是一次离散重击（走 take_damage，无敌帧和护盾都生效）。
#   远程毒物（任意距离）：抛毒团落地成毒池，走 DoT 通道（绕过护盾/无敌帧），
#     打的是"这块地不能站"的空间压力。
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
		GameState.boss_state_changed.emit(hp_frac, _boss_phase)

	# 爪击先算：举爪期间要定住脚（那正是"预告"本身），所以它必须能否决移动。
	_boss_claw(delta)
	# 冲刺其次。返回 true 表示这一帧巨兽在冲刺中 —— 冲刺分支自己
	# move_and_slide + 命中检查，这里的普通移动必须整个跳过，否则一帧动两次。
	var dashing: bool = _boss_dash(delta)

	# 速度：P1 1.0×  P2 1.2×  P3 1.4×
	var speed_mult: float = [1.0, 1.0, 1.2, 1.4][_boss_phase]
	if not dashing:
		# 举爪 / 蓄力 / 硬直都定住脚 —— 定住本身就是预警的一部分。
		if _claw_wind_left > 0.0 or _dash_wind_left > 0.0 or _dash_recover_left > 0.0:
			velocity = Vector2.ZERO
		else:
			var dir: Vector2 = _steer_dir()
			velocity = dir * _effective_speed() * speed_mult
		move_and_slide()
		# 冲刺期间跳过接触伤害：冲刺命中由 _boss_dash 自己结算，单一伤害来源，
		# 否则冲过去的一帧会吃到 25（接触）+ 45（冲刺）两份。
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

	# 毒物：全阶段都有，阶段越高越密集。毒池是空间压力，不该只在残血才出现，
	# 否则前 40% 的血量玩家可以站着不动纯输出。
	var poison_int: float = config.boss_poison_interval
	var poison_n: int = config.boss_poison_count
	match _boss_phase:
		2: poison_int *= 0.8;  poison_n += 1
		3: poison_int *= 0.65; poison_n += 2
	_boss_poison_accum += delta
	if _boss_poison_accum >= poison_int:
		_boss_poison_accum = 0.0
		_boss_spit_poison(poison_n)

	# 弹幕（P2 / P3）
	if _boss_phase >= 2:
			_boss_bullet_accum += delta
			var bullet_int: float = config.boss_bullet_interval
			if _boss_phase == 3:
				bullet_int *= 0.65
			if _boss_bullet_accum >= bullet_int:
				_boss_bullet_accum = 0.0
				_boss_volley()

## 巨型机器人（GOBOT）行为。三套攻击：激光（4s 冷却，1s 蓄力，宽光束）、
## 导弹（3s 冷却，5 发齐射）、震地（6s 冷却，跃起落地 AoE）。
## 阶段缩放同废土巨兽：P2 冷却 ×0.8、P3 ×0.65。
func _behavior_gobot(delta: float) -> void:
	_maybe_repath(delta)
	# 阶段
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
		GameState.boss_state_changed.emit(hp_frac, _boss_phase)

	var speed_mult: float = [1.0, 1.0, 1.2, 1.4][_boss_phase]
	var phase_cd: float = [1.0, 1.0, 0.8, 0.65][_boss_phase]

	# 激光蓄力中：定脚，逼近玩家时锁定方向。
	if _gobot_laser_wind_left > 0.0:
		_gobot_laser_wind_left -= delta
		velocity = Vector2.ZERO
		if _gobot_laser_wind_left <= 0.0:
			_gobot_laser_strike()
	elif _gobot_bolt_wind_left > 0.0:
		# 多道闪电蓄力：定脚（和激光同一套否决逻辑），到点齐射。
		_gobot_bolt_wind_left -= delta
		velocity = Vector2.ZERO
		if _gobot_bolt_wind_left <= 0.0:
			_gobot_bolt_strike()
	elif _gobot_stomp_wind_left > 0.0:
		_gobot_stomp_wind_left -= delta
		velocity = Vector2.ZERO
		if _gobot_stomp_wind_left <= 0.0:
			_gobot_stomp_start()
	elif _gobot_stomp_air_left > 0.0:
		_gobot_stomp_air_left -= delta
		velocity = _gobot_laser_facing * maxf(100.0, config.speed * 3.0)
		move_and_collide(velocity * delta)
		if _gobot_stomp_air_left <= 0.0:
			_gobot_stomp_air_left = 0.0
			_gobot_stomp_land()
			_gobot_stomp_recover_left = config.gobot_stomp_recover
			GameState.request_camera_shake.emit(6.0, 0.25)
	elif _gobot_stomp_recover_left > 0.0:
		_gobot_stomp_recover_left -= delta
		velocity = Vector2.ZERO
	else:
		var dir: Vector2 = _steer_dir()
		velocity = dir * _effective_speed() * speed_mult
		if _player != null and is_instance_valid(_player):
			var to_player: Vector2 = _player.global_position - global_position
			# 激光
			_gobot_laser_accum += delta
			if _gobot_laser_accum >= config.gobot_laser_cooldown * phase_cd:
				_gobot_laser_accum = 0.0
				_gobot_laser_wind_left = config.gobot_laser_windup
				_gobot_laser_facing = to_player.normalized()
				GameState.request_camera_shake.emit(1.5, 0.1)
			# 导弹
			_gobot_missile_accum += delta
			if _gobot_missile_accum >= config.gobot_missile_cooldown * phase_cd:
				_gobot_missile_accum = 0.0
				_gobot_fire_missiles(to_player.normalized())
			# 震地（只在不用别的技能时）
			_gobot_stomp_accum += delta
			if _gobot_stomp_accum >= config.gobot_stomp_cooldown * phase_cd \
					and _gobot_stomp_wind_left <= 0.0 and _gobot_stomp_air_left <= 0.0 \
					and _gobot_stomp_recover_left <= 0.0:
				_gobot_stomp_accum = 0.0
				_gobot_stomp_wind_left = config.gobot_stomp_windup
				_gobot_laser_facing = to_player.normalized()
				GameState.request_camera_shake.emit(2.0, 0.12)
			# --- 进阶三招，按阶段解锁（见 gobot_attack_unlocked）---
			# 电球（P1 起）：即时发射，飞到落点炸开。
			if gobot_attack_unlocked(ATK_ORB, _boss_phase):
				_gobot_orb_accum += delta
				if _gobot_orb_accum >= config.gobot_orb_cooldown * phase_cd:
					_gobot_orb_accum = 0.0
					_gobot_fire_orb(_player.global_position)
			# 多道长条闪电（P2 起）：起手锁方向 + 生成预警线，蓄力结束才结算。
			if gobot_attack_unlocked(ATK_BOLTS, _boss_phase):
				_gobot_bolt_accum += delta
				if _gobot_bolt_accum >= config.gobot_bolt_cooldown * phase_cd:
					_gobot_bolt_accum = 0.0
					_gobot_bolt_windup_start(to_player.normalized())
			# 扔地雷（P3 起）：即时在玩家周围散点布雷。
			if gobot_attack_unlocked(ATK_MINES, _boss_phase):
				_gobot_mine_accum += delta
				if _gobot_mine_accum >= config.gobot_mine_cooldown * phase_cd:
					_gobot_mine_accum = 0.0
					_gobot_throw_mines(_player.global_position)
	# 竞技场牵制：把 BOSS 位置钳回竞技场内（内缩其碰撞半径），避免玩家未进门前
	# BOSS 追出房间。arena_rect 空矩形 = 不牵制（第一关废土 BOSS 不受影响）。
	if arena_rect.size != Vector2.ZERO:
		var m: float = maxf(200.0, config.collision_radius)
		var r: Rect2 = arena_rect.grow(-m)
		global_position.x = clampf(global_position.x, r.position.x, r.position.x + r.size.x)
		global_position.y = clampf(global_position.y, r.position.y, r.position.y + r.size.y)
	move_and_slide()
	_apply_contact_damage()

## 激光命中帧。宽光束沿锁定方向，对矩形内的玩家造成伤害。
## 长条矩形那段数学在 GobotBolts.in_beam 里（和多道闪电共用的纯函数）。
func _gobot_laser_strike() -> void:
	_gobot_laser_wind_left = 0.0
	if _player == null or not is_instance_valid(_player):
		return
	if not GobotBolts.in_beam(global_position, _gobot_laser_facing,
			_player.global_position, config.gobot_laser_length, config.gobot_laser_width):
		return
	if _player.has_method("take_damage"):
		_player.take_damage(config.gobot_laser_damage)
	GameState.request_camera_shake.emit(5.0, 0.2)
	SfxPlayer.play("boom")

# --- 进阶三招（按阶段解锁）---

## 招式编号，给 gobot_attack_unlocked 用。
const ATK_ORB: int = 0
const ATK_BOLTS: int = 1
const ATK_MINES: int = 2

## 某招在某阶段是否解锁。纯函数，让"解锁节奏"能被自检直接断言 ——
## 否则要验证它得真打一场把 BOSS 血量刷到对应阶段。
##
## 电球 P1 起、多道闪电 P2 起、扔地雷 P3 起：战斗逐阶升级，不会一上来
## 就 6 招齐发糊成一片。未知招式返回 false（宁可不发动，也不要靠"默认解锁"
## 让打错的编号变成一招凭空出现的攻击）。
static func gobot_attack_unlocked(attack: int, phase: int) -> bool:
	match attack:
		ATK_ORB: return phase >= 1
		ATK_BOLTS: return phase >= 2
		ATK_MINES: return phase >= 3
	return false

## 电球：朝**此刻**玩家所在的点发射（不追踪，走开能躲），抵达后炸开成小电球。
func _gobot_fire_orb(target: Vector2) -> void:
	var scene: PackedScene = load("res://scenes/fx/gobot_orb.tscn") as PackedScene
	if scene == null:
		return
	var orb: Node = scene.instantiate()
	_add_to_scene(orb)
	if not is_instance_valid(orb) or not orb.is_inside_tree():
		return
	if orb is Node2D:
		(orb as Node2D).global_position = global_position
	if orb.has_method("setup"):
		orb.setup(target, config.gobot_orb_speed, config.gobot_orb_damage,
			config.gobot_orb_burst_radius, config.gobot_orb_shard_count,
			config.gobot_orb_shard_damage, config.gobot_orb_shard_speed,
			config.projectile_scene)
	GameState.request_camera_shake.emit(1.5, 0.1)
	SfxPlayer.play("fire")

## 多道闪电起手：锁方向、算好每道的角度、生成预警线。锁定之后再转向就没有
## 可躲性了，所以角度在这一刻定死，命中帧直接用同一份。
func _gobot_bolt_windup_start(facing: Vector2) -> void:
	var dir: Vector2 = facing if facing.length_squared() > 0.0 else Vector2.RIGHT
	_gobot_bolt_angles = GobotBolts.bolt_angles(dir.angle(),
		config.gobot_bolt_count, config.gobot_bolt_spread)
	_gobot_bolt_wind_left = config.gobot_bolt_windup
	var fx := GobotBolts.new()
	fx.setup(_gobot_bolt_angles, config.gobot_bolt_length,
		config.gobot_bolt_width, config.gobot_bolt_windup)
	add_child(fx)
	_gobot_bolt_fx = fx
	GameState.request_camera_shake.emit(1.5, 0.12)

## 多道闪电命中帧：逐道做长条判定，**命中也只结算一次伤害**（多道重叠不叠伤，
## 否则站在扇形中心会被 5 道同时打成瞬杀）。
func _gobot_bolt_strike() -> void:
	_gobot_bolt_wind_left = 0.0
	if _gobot_bolt_fx != null and is_instance_valid(_gobot_bolt_fx) \
			and _gobot_bolt_fx.has_method("strike"):
		_gobot_bolt_fx.strike()
	_gobot_bolt_fx = null
	GameState.request_camera_shake.emit(5.0, 0.22)
	SfxPlayer.play("boom")
	if _player == null or not is_instance_valid(_player):
		return
	for a in _gobot_bolt_angles:
		if GobotBolts.in_beam(global_position, Vector2(cos(a), sin(a)),
				_player.global_position, config.gobot_bolt_length, config.gobot_bolt_width):
			if _player.has_method("take_damage"):
				_player.take_damage(config.gobot_bolt_damage)
			return   # 只结算一次

## 扔地雷：在玩家周围散点布 N 颗。落点避开墙 —— 扔进墙里的雷玩家永远踩不到，
## 那一颗就白扔了。
func _gobot_throw_mines(around: Vector2) -> void:
	var scene: PackedScene = load("res://scenes/fx/gobot_mine.tscn") as PackedScene
	if scene == null:
		return
	var n: int = maxi(1, config.gobot_mine_count)
	for i in range(n):
		var pos: Vector2 = _gobot_pick_mine_spot(around, i, n)
		var mine: Node = scene.instantiate()
		_add_to_scene(mine)
		if not is_instance_valid(mine) or not mine.is_inside_tree():
			return
		if mine is Node2D:
			(mine as Node2D).global_position = pos
		if mine.has_method("setup"):
			mine.setup(config.gobot_mine_radius, config.gobot_mine_damage,
				config.gobot_mine_arm, config.gobot_mine_life)
	GameState.request_camera_shake.emit(2.0, 0.12)
	SfxPlayer.play("fire")

## 第 i 颗雷的落点：以 around 为中心均匀铺一圈 + 抖动，撞墙就往里收几次。
func _gobot_pick_mine_spot(around: Vector2, i: int, n: int) -> Vector2:
	var base_ang: float = TAU * float(i) / float(n) + randf() * 0.4
	var world: Node = _gobot_world()
	for attempt in range(4):
		# 每次重试把半径往内收，越靠近玩家越可能是空地（玩家脚下必然可站）。
		var r: float = config.gobot_mine_scatter * (1.0 - 0.22 * float(attempt)) \
			* randf_range(0.45, 1.0)
		var p: Vector2 = around + Vector2(cos(base_ang), sin(base_ang)) * r
		if world == null or not world.is_solid(p):
			return p
	return around

## 地图（"world" 组），用来查落点是否在墙里。自检场景没有 World，必须干净地
## 退化成"不做过滤"而不是报错。
func _gobot_world() -> Node:
	if not is_inside_tree():
		return null
	for w in get_tree().get_nodes_in_group("world"):
		if w != null and w.has_method("is_solid"):
			return w
	return null

## 五发导弹齐射，扇形散开。
func _gobot_fire_missiles(facing: Vector2) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var base: float = facing.angle()
	var spread: float = 0.25
	for i in range(config.gobot_missile_count):
		var ang: float = base + lerpf(-spread, spread, float(i) / maxf(1, config.gobot_missile_count - 1))
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		_fire_projectile(dir, config.gobot_missile_speed, config.gobot_missile_damage)
	SfxPlayer.play("fire")

## 震地跃起。
func _gobot_stomp_start() -> void:
	_gobot_stomp_wind_left = 0.0
	_gobot_stomp_air_left = config.gobot_stomp_duration
	_gobot_stomp_hit_done = false

## 震地落地 —— 范围 AoE 伤害。
func _gobot_stomp_land() -> void:
	_gobot_stomp_air_left = 0.0
	if _gobot_stomp_hit_done:
		return
	if _player == null or not is_instance_valid(_player):
		return
	if global_position.distance_to(_player.global_position) > config.gobot_stomp_radius:
		return
	_gobot_stomp_hit_done = true
	if _player.has_method("take_damage"):
		_player.take_damage(config.gobot_stomp_damage)
	# 落地粒子
	var fx_scene: PackedScene = load("res://scenes/fx/explosion.tscn") as PackedScene
	var fx: Node = fx_scene.instantiate()
	fx.setup(config.gobot_stomp_radius, 0.0, Color(1.0, 0.55, 0.2, 0.7))
	_add_to_scene(fx)
	fx.global_position = global_position

## 爪击状态机。两条分支：举爪中（推进预警、到点结算）和冷却中（够近就起手）。
func _boss_claw(delta: float) -> void:
	if _claw_wind_left > 0.0:
		_claw_wind_left -= delta
		if _claw_wind_left <= 0.0:
			_claw_strike()
		return
	_claw_accum += delta
	if _claw_accum < config.boss_claw_cooldown:
		return
	if _player == null or not is_instance_valid(_player):
		return
	var to_player: Vector2 = _player.global_position - global_position
	if to_player.length() > config.boss_claw_reach:
		return
	# 起手：锁定朝向、生成预警特效。这一刻之后再转向就没有可躲性了。
	_claw_accum = 0.0
	_claw_wind_left = config.boss_claw_windup
	_claw_facing = to_player.normalized()
	_claw_fx = ClawSlash.new()
	(_claw_fx as ClawSlash).setup(_claw_facing, config.boss_claw_reach,
		config.boss_claw_arc, config.boss_claw_windup)
	# 挂在自己名下，跟着身体走 —— 巨兽被击退时爪子不该留在原地。
	add_child(_claw_fx)
	GameState.request_camera_shake.emit(2.0, 0.12)

## 预警结束的那一帧结算。用锁定的 _claw_facing 判定，不是当前朝向。
func _claw_strike() -> void:
	_claw_wind_left = 0.0
	if _claw_fx != null and is_instance_valid(_claw_fx) and _claw_fx.has_method("strike"):
		_claw_fx.strike()
		# 特效留在巨兽名下自己活完 STRIKE_TIME。刻意不 reparent 到场景根：
		# 在 _physics_process 里改父节点会撞上 "flushing queries" 报错，
		# 而代价只是巨兽恰好在这 0.18s 内被打死时闪光跟着消失。
	_claw_fx = null
	GameState.request_camera_shake.emit(5.0, 0.2)
	SfxPlayer.play("boom")
	if _player == null or not is_instance_valid(_player):
		return
	if not ClawSlash.in_arc(global_position, _claw_facing,
			_player.global_position, config.boss_claw_reach, config.boss_claw_arc):
		return
	if _player.has_method("take_damage"):
		# 走正常受伤通道：一次离散重击就是无敌帧和护盾要挡的东西。
		_player.take_damage(config.boss_claw_damage)

## 冲刺状态机。四段：蓄力（定住脚画预告线）→ 冲刺（沿锁定的 _dash_facing
## 直线高速移动，途中结算一次命中）→ 硬直（定住脚，玩家反打窗口）→ 冷却。
##
## 返回 true 表示本帧正处于冲刺中 —— 调用方（_behavior_boss）必须跳过它
## 自己的 move_and_slide，因为冲刺分支已经动过身体了。
##
## 命中判定是**位置**检查而不是 get_slide_collision：冲刺速度 950px/s 下
## 一帧走 ~16px，玩家碰撞圈（14）+ 巨兽身体（112）的叠加窗口足够宽，位置
## 判定不会漏；而接触伤害通道走碰撞，两条通道同帧触发会双份伤害，所以冲刺
## 期间_behavior_boss 会跳过 _apply_contact_damage，这里就是唯一伤害来源。
func _boss_dash(delta: float) -> bool:
	if _dash_wind_left > 0.0:
		# 蓄力：只数秒。定脚由 _behavior_boss 的速度否决完成。
		_dash_wind_left -= delta
		if _dash_wind_left <= 0.0:
			_dash_start()
		return false
	if _dash_run_left > 0.0:
		# 冲刺：沿锁定方向直线冲。move_and_collide 带显式位移 —— 和爪击测试
		# 一样，自检要能直接用假 delta 驱动状态机并断言精确位移；move_and_slide
		# 用的是真实物理帧 delta，会破坏这种可测性。撞上玩家身体会自然截停
		# —— "撞到人就是终点"；玩家让开则冲满全程。
		_dash_run_left -= delta
		velocity = _dash_facing * _dash_speed_now()
		move_and_collide(velocity * delta)
		_dash_hit_check()
		if _dash_run_left <= 0.0:
			_dash_run_left = 0.0
			_dash_recover_left = config.boss_dash_recover
			GameState.request_camera_shake.emit(3.0, 0.15)
		return true
	if _dash_recover_left > 0.0:
		_dash_recover_left -= delta
		if _dash_recover_left <= 0.0:
			_dash_recover_left = 0.0
		return false
	# 冷却：够近（但别近到爪击范围内）就起手。
	_dash_accum += delta
	if _dash_accum < config.boss_dash_cooldown:
		return false
	if _player == null or not is_instance_valid(_player):
		return false
	var to_player: Vector2 = _player.global_position - global_position
	var dist: float = to_player.length()
	if dist < config.boss_dash_min_range or dist > config.boss_dash_max_range:
		return false
	# 起手：锁定方向、生成预告线。这一刻之后再转向就没有可躲性了。
	_dash_accum = 0.0
	_dash_wind_left = config.boss_dash_windup
	_dash_facing = to_player.normalized()
	_dash_hit_done = false
	var expect_len: float = config.boss_dash_speed * config.boss_dash_duration
	_dash_fx = DashTelegraph.new()
	(_dash_fx as DashTelegraph).setup(_dash_facing, expect_len, config.boss_dash_windup)
	add_child(_dash_fx)
	GameState.request_camera_shake.emit(1.5, 0.1)
	return false

## 蓄力结束：预告线转命中残影，开始移动。
func _dash_start() -> void:
	_dash_wind_left = 0.0
	_dash_run_left = config.boss_dash_duration
	if _dash_fx != null and is_instance_valid(_dash_fx) and _dash_fx.has_method("strike"):
		_dash_fx.strike()
	_dash_fx = null
	SfxPlayer.play("boom")

## 冲刺速度：基础 dash_speed 乘阶段倍率（P2 1.2× / P3 1.4×，和步行同一套）。
func _dash_speed_now() -> float:
	var mult: float = [1.0, 1.0, 1.2, 1.4][_boss_phase]
	return config.boss_dash_speed * mult

## 冲刺中的命中结算。位置判定，一次冲刺至多打一次（_dash_hit_done）。
func _dash_hit_check() -> void:
	if _dash_hit_done:
		return
	if _player == null or not is_instance_valid(_player):
		return
	if global_position.distance_to(_player.global_position) > config.boss_dash_hit_radius:
		return
	_dash_hit_done = true
	if _player.has_method("take_damage"):
		# 正常受伤通道：离散重击，护盾和无敌帧按设计抵挡。无敌帧在身时
		# 打空也正常 —— 和爪击同一套规则。
		_player.take_damage(config.boss_dash_damage)

## 朝玩家方向抛 n 团毒液。落点扇形铺开而不是全砸一点：目的是逼玩家移动，
## 一坨叠在一起只会变成"绕开这一个圆"。
func _boss_spit_poison(n: int) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var to_player: Vector2 = _player.global_position - global_position
	var dist: float = to_player.length()
	if dist < 0.01:
		return
	var base: float = to_player.angle()
	var count: int = maxi(1, n)
	# 单团直接砸脚下；多团时以玩家为中心张开一把扇子，中间那团仍然对准玩家，
	# 所以站着不动永远是最差选择。
	for i in range(count):
		var spread: float = 0.0 if count == 1 else \
			lerpf(-0.5, 0.5, float(i) / float(count - 1))
		var ang: float = base + spread
		var reach: float = dist * randf_range(0.85, 1.15)
		var target: Vector2 = global_position + Vector2(cos(ang), sin(ang)) * reach
		var glob := PoisonGlob.new()
		glob.setup(global_position, target, config.boss_poison_flight,
			config.boss_poison_pool_radius, config.boss_poison_dps,
			config.boss_poison_tick, config.boss_poison_pool_life)
		_add_to_scene(glob)

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
	_add_to_scene(p)
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
	# The boss health bar is driven off this rather than polled: damage is the
	# only thing that moves the bar, and it is already a per-hit event.
	if config != null and (config.behavior == EnemyConfig.Behavior.BOSS
			or config.behavior == EnemyConfig.Behavior.GOBOT):
		GameState.boss_state_changed.emit(
			clampf(hp / maxf(1.0, config.max_hp), 0.0, 1.0), _boss_phase)
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
	var was_boss: bool = config != null and (config.behavior == EnemyConfig.Behavior.BOSS
		or config.behavior == EnemyConfig.Behavior.GOBOT)
	GameState.enemy_died.emit(global_position, _last_hit_dir, was_elite or was_boss)
	if is_inside_tree() and has_node("/root/MetaProgress"):
		MetaProgress.record_kill()
	if was_boss:
		GameState.request_camera_shake.emit(config.boss_shake_on_death, 0.8)
		GameState.request_hit_stop.emit(0.18)
		# 额外震屏
		GameState.request_camera_shake.emit(6.0, 0.5)
		# Tears down the HUD bar and the off-screen marker. Emitted before
		# queue_free so nothing is left holding a freed node.
		GameState.boss_defeated.emit()
		if is_inside_tree() and has_node("/root/MetaProgress"):
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
		elif config.behavior == EnemyConfig.Behavior.BOSS \
				or config.behavior == EnemyConfig.Behavior.GOBOT:
			gem_xp *= config.boss_xp_multiplier
		if gem.has_method("set_value"):
			gem.set_value(gem_xp)
		_add_to_scene(gem)
	_drop_items()
	queue_free()

## Scatter `config.item_drop_count` pickups around the corpse. Driven by the
## config rather than by "was this camp-spawned", so a time-based ELITE WAVE
## elite drops exactly like a camp elite does. `item_drop_chance` gates the whole
## drop so trash mobs can carry a small chance instead of a guaranteed pile.
##
## 补血道具**只从精英怪极低概率掉落**：HEAL 已从 roll_kind 的普通池移除，普通
## 怪/其余敌人永远不掉血；这里在正常掉落之后再对精英怪额外掷一次极低概率补血。
const ELITE_HEAL_CHANCE: float = 0.06
func _drop_items() -> void:
	if config == null or config.item_drop_scene == null:
		return
	# 精英档掉落（精英 / BOSS）：磁轨激光和火焰喷射器只在这一档的武器掉落里
	# 出现，杂兵永远掉不出这两把（见 WeaponDirector 的 elite_only）。
	var elite_tier: bool = config.behavior == EnemyConfig.Behavior.ELITE \
		or config.behavior == EnemyConfig.Behavior.BOSS \
		or config.behavior == EnemyConfig.Behavior.GOBOT
	if config.item_drop_count > 0 and randf() <= config.item_drop_chance:
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
				item.setup(PickupItem.roll_kind(), elite_tier)
			_add_to_scene(item)
	# 补血：只有精英怪才有极低概率额外掉一个（独立于 item_drop_chance 掷骰）。
	if config.behavior == EnemyConfig.Behavior.ELITE and randf() < ELITE_HEAL_CHANCE:
		var heal: Node = config.item_drop_scene.instantiate()
		if heal is Node2D:
			(heal as Node2D).global_position = global_position \
				+ Vector2(randf_range(-18, 18), randf_range(-18, 18))
		if heal.has_method("setup"):
			heal.setup(PickupItem.Kind.HEAL, true)
		_add_to_scene(heal)

## 把节点挂到当前场景。**必须在关卡切换的瞬间也能安全调用**：杀 BOSS 触发
## _advance_to_level → change_scene 时，_die() 还在往下走（掉宝石、掉道具、
## 爆炸粒子），此刻敌人已被移出场景树 —— 对树外节点调 get_tree() 本身就会
## 报 "Parameter data.tree is null"，所以先查 is_inside_tree() 再碰树。
## 挂不上去就把节点删掉：关卡正在切，掉的东西本来就活不到下一关。
func _add_to_scene(node: Node) -> void:
	if not is_inside_tree():
		node.queue_free()
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		node.queue_free()
		return
	tree.current_scene.add_child(node)

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
