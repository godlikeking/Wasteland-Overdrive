extends Area2D
class_name GobotMine
## 巨型机器人扔出的地雷。布防延迟 → 闪烁 → 踩上去或到期炸开，**伤玩家**。
##
## 为什么不复用玩家的 mine.gd：那颗雷在 PlayerBullet 层上打敌人组，而且把伤害
## 交给 explosion.tscn 结算 —— explosion 只打敌人。这颗要反过来伤玩家，所以
## 自己结算伤害，爆炸特效只当画面（和 enemy.gd 的 `_gobot_stomp_land`、
## gobot_orb.gd 同一手法）。
##
## 布防延迟的意义和玩家地雷相反但同样必要：雷是扔在玩家脚边的，没有延迟就等于
## 一颗无法反应的即时伤害，那不叫地雷叫射线。

## 布防后的闪烁周期，让"已布防"和"还在落地"区分得开。
const BLINK_TIME: float = 0.45
## 到期前最后几秒快闪示警。
const PANIC_LEAD: float = 1.5
const PANIC_BLINK_TIME: float = 0.13
## 视觉半径。
const RADIUS: float = 14.0

var blast_radius: float = 140.0
var damage: float = 50.0
var arm_time: float = 0.8
var life: float = 9.0

var _age: float = 0.0
var _armed: bool = false
## 防重复引爆：接触和到期可能同一帧发生，queue_free 要到帧末才生效。
var _spent: bool = false
var _lit: bool = true

func setup(p_radius: float, p_damage: float, p_arm_time: float, p_life: float) -> void:
	blast_radius = maxf(1.0, p_radius)
	damage = maxf(0.0, p_damage)
	arm_time = maxf(0.0, p_arm_time)
	life = maxf(0.1, p_life)

func _ready() -> void:
	add_to_group("gobot_mines")
	# 躺在地上，但**不能用负 z**：TileMap 在 z=0，z=-1 会被整张地图盖掉，
	# 结果是雷完全看不见、只看到最后那朵爆炸 —— 这个坑毒池踩过一次
	# （以前用 -5），poison_pool.gd 那条注释就是它的墓志铭。
	# z=0 + 挂在 World 名下（见 enemy._add_to_world_or_scene）才对：World 先画
	# TileMap，雷作为它的后继子节点紧随其后压在图上，又在玩家/敌人
	# （World 的后继兄弟）之下。
	z_index = 0
	body_entered.connect(_on_touch)

func _physics_process(delta: float) -> void:
	# 时停冻结引信：否则可以靠冻结让一片雷安全过期。
	if GameState.is_time_stopped() or get_tree().paused:
		return
	if _spent:
		return
	_age += delta
	if not _armed and _age >= arm_time:
		_armed = true
	_update_blink()
	queue_redraw()
	if _age >= life:
		_detonate()
		return
	# 接触只报告"进入"的 body，已经站在未布防的雷上的玩家永远不会触发它。
	# 布防后重扫一次 —— 和玩家地雷同一个坑。
	if _armed:
		for b in get_overlapping_bodies():
			if b != null and b.is_in_group("player"):
				_detonate()
				return

func _on_touch(body: Node) -> void:
	if _spent or not _armed:
		return
	if body != null and body.is_in_group("player"):
		_detonate()

func _detonate() -> void:
	if _spent:
		return
	_spent = true
	var here: Vector2 = global_position
	# 范围伤害：只打玩家。
	var p: Node = get_tree().get_first_node_in_group("player")
	if p != null and is_instance_valid(p) and p is Node2D:
		if (p as Node2D).global_position.distance_to(here) <= blast_radius \
				and p.has_method("take_damage"):
			p.take_damage(damage)
	# 爆炸特效：0 伤害，纯画面。
	var fx_scene: PackedScene = load("res://scenes/fx/explosion.tscn") as PackedScene
	if fx_scene != null:
		var fx: Node = fx_scene.instantiate()
		get_tree().current_scene.add_child(fx)
		if fx.has_method("setup"):
			fx.setup(blast_radius, 0.0, Color(1.0, 0.5, 0.25, 0.7))
		if fx is Node2D:
			(fx as Node2D).global_position = here
	GameState.request_camera_shake.emit(3.5, 0.16)
	SfxPlayer.play("boom")
	queue_free()

func _update_blink() -> void:
	if not _armed:
		_lit = true
		return
	var left: float = life - _age
	var period: float = PANIC_BLINK_TIME if left <= PANIC_LEAD else BLINK_TIME
	_lit = fmod(_age, period) > period * 0.45

func _draw() -> void:
	# 未布防：暗灰壳。布防后：壳 + 一颗一闪一闪的红灯。
	var shell: Color = Color(0.22, 0.23, 0.26) if _armed else Color(0.3, 0.31, 0.34)
	draw_circle(Vector2.ZERO, RADIUS, shell)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 20, Color(0.45, 0.47, 0.52), 2.0)
	# 四根小脚，读作"雷"而不是"石头"。
	for i in range(4):
		var a: float = TAU * float(i) / 4.0 + PI * 0.25
		var d: Vector2 = Vector2(cos(a), sin(a))
		draw_line(d * RADIUS * 0.8, d * RADIUS * 1.35, Color(0.38, 0.4, 0.44), 2.0)
	if _armed and _lit:
		draw_circle(Vector2.ZERO, RADIUS * 0.42, Color(1.0, 0.3, 0.25, 0.95))
		draw_circle(Vector2.ZERO, RADIUS * 0.75, Color(1.0, 0.35, 0.25, 0.22))
