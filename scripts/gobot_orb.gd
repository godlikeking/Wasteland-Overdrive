extends Area2D
class_name GobotOrb
## 巨型机器人的「电球」：飞到落点炸开成一圈小电球。
##
## 落点是**开火那一刻**玩家所在的位置，不追踪 —— 走开就能躲掉，这是这招的
## 可玩性所在（追踪版本已经由导弹齐射负责了）。
##
## 炸开时做两件事：对范围内的玩家结算一次伤害，然后向四周喷 shard_count 颗
## 小电球（复用敌弹场景，第二关它本来就是青色电球贴图）。
## 伤害自己结算而不是丢给 explosion.tscn —— 那个只打敌人组。和
## enemy.gd 的 `_gobot_stomp_land` 同一手法：爆炸特效只当画面。

## 判定为"已抵达落点"的距离。比一帧位移（260px/s ÷ 60 ≈ 4.3px）宽裕，
## 否则高速下会越过落点再回头，视觉上像抽了一下。
const ARRIVE_EPS: float = 14.0
## 兜底寿命：撞不到墙也没抵达（落点在墙里之类）时也必须炸掉，不能永远飞。
const MAX_LIFE: float = 4.0
## 半径（视觉 + 撞玩家判定）。
const RADIUS: float = 18.0

var target: Vector2 = Vector2.ZERO
var speed: float = 260.0
var damage: float = 45.0
var burst_radius: float = 130.0
var shard_count: int = 8
var shard_damage: float = 12.0
var shard_speed: float = 300.0
var shard_scene: PackedScene

var _dir: Vector2 = Vector2.RIGHT
var _age: float = 0.0
## 防重复引爆：撞玩家和抵达落点可能同一帧发生，而 queue_free 要到帧末才生效。
var _spent: bool = false

func setup(p_target: Vector2, p_speed: float, p_damage: float, p_burst_radius: float,
		p_shard_count: int, p_shard_damage: float, p_shard_speed: float,
		p_shard_scene: PackedScene) -> void:
	target = p_target
	speed = maxf(1.0, p_speed)
	damage = maxf(0.0, p_damage)
	burst_radius = maxf(1.0, p_burst_radius)
	shard_count = maxi(0, p_shard_count)
	shard_damage = maxf(0.0, p_shard_damage)
	shard_speed = maxf(1.0, p_shard_speed)
	shard_scene = p_shard_scene

func _ready() -> void:
	add_to_group("gobot_orbs")
	z_index = 16
	_dir = (target - global_position)
	_dir = _dir.normalized() if _dir.length_squared() > 0.0001 else Vector2.RIGHT
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	# 时停 / 暂停：电球停在空中，引信也不烧 —— 和 enemy_projectile 一致，
	# 否则可以靠冻结让它安全过期。
	if GameState.is_time_stopped() or get_tree().paused:
		return
	if _spent:
		return
	_age += delta
	queue_redraw()
	global_position += _dir * speed * delta
	if global_position.distance_to(target) <= ARRIVE_EPS or _age >= MAX_LIFE:
		_burst()

func _on_body_entered(body: Node) -> void:
	if _spent:
		return
	# 撞墙就地炸开（mask 里含挡弹层）。撞到玩家也炸 —— 伤害由 _burst 统一结算，
	# 不在这里额外打一次，否则贴脸会吃两份。
	if body is TileMap or body.is_in_group("player"):
		_burst()

## 炸开：范围伤害 + 一圈小电球 + 爆炸特效（纯画面）。
func _burst() -> void:
	if _spent:
		return
	_spent = true
	var here: Vector2 = global_position
	# 范围伤害：只打玩家，且只结算一次。
	var p: Node = get_tree().get_first_node_in_group("player")
	if p != null and is_instance_valid(p) and p is Node2D:
		if (p as Node2D).global_position.distance_to(here) <= burst_radius \
				and p.has_method("take_damage"):
			p.take_damage(damage)
	# 一圈小电球，均匀铺开。
	if shard_scene != null and shard_count > 0:
		for i in range(shard_count):
			var ang: float = TAU * float(i) / float(shard_count)
			var shard: Node = shard_scene.instantiate()
			get_tree().current_scene.add_child(shard)
			if shard is Node2D:
				(shard as Node2D).global_position = here
			if shard.has_method("setup"):
				shard.setup(Vector2(cos(ang), sin(ang)) * shard_speed, shard_damage, 1.4)
			if shard.has_method("set_enemy_bullet"):
				shard.set_enemy_bullet(true)
	# 爆炸特效：0 伤害，纯画面（explosion.tscn 只打敌人组，伤害已在上面结算）。
	var fx_scene: PackedScene = load("res://scenes/fx/explosion.tscn") as PackedScene
	if fx_scene != null:
		var fx: Node = fx_scene.instantiate()
		get_tree().current_scene.add_child(fx)
		if fx.has_method("setup"):
			fx.setup(burst_radius, 0.0, Color(0.4, 0.9, 1.0, 0.7))
		if fx is Node2D:
			(fx as Node2D).global_position = here
	GameState.request_camera_shake.emit(4.0, 0.18)
	SfxPlayer.play("boom")
	queue_free()

func _draw() -> void:
	# 青色电球：外晕 + 亮芯 + 一圈随时间抖动的电弧。
	var pulse: float = 0.85 + 0.15 * sin(_age * 18.0)
	draw_circle(Vector2.ZERO, RADIUS * 1.6 * pulse, Color(0.25, 0.7, 1.0, 0.25))
	draw_circle(Vector2.ZERO, RADIUS * pulse, Color(0.45, 0.9, 1.0, 0.75))
	draw_circle(Vector2.ZERO, RADIUS * 0.5 * pulse, Color(0.9, 1.0, 1.0, 0.95))
	for i in range(6):
		var a: float = TAU * float(i) / 6.0 + _age * 6.0
		var r0: float = RADIUS * 1.1
		var r1: float = RADIUS * (1.5 + 0.35 * sin(_age * 22.0 + float(i)))
		draw_line(Vector2(cos(a), sin(a)) * r0, Vector2(cos(a), sin(a)) * r1,
			Color(0.7, 0.95, 1.0, 0.7), 2.0)
