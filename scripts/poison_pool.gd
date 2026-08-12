extends Node2D
class_name PoisonPool
## 一片持续伤害的毒液。BOSS 的毒团落地后生成，`life` 秒后自行消失。
##
## 伤害走 Player.take_dot_damage 而不是 take_damage —— 完整推导见那个函数的
## 文档注释，一句话版本：take_damage 会被无敌帧节流成 2.5 跳/秒、会让每一跳
## 都吃掉一整层护盾、还会通过 player_hurt → FxManager 把全局时间缩放到 0.05
## 让整个游戏抽搐。DoT 自己的 tick 间隔就是它的节流器。
##
## 完全程序化绘制，不用贴图：tools/gen_bullets.py 的调色板里一点绿都没有，
## 而毒池半径本来就随配置变化，必须按半径画。和 explosion.gd 同一个模式。

## 毒池闪色，和毒沼的黄绿、正常受伤的红都区分得开。
const POOL_FLASH: Color = Color(0.55, 1.6, 0.6)
## 出现/消失的淡入淡出时长，用来让"还有多久没了"读得出来。
const FADE: float = 0.5

var radius: float = 95.0
var dps: float = 14.0
var tick: float = 0.5
var life: float = 6.0

var _age: float = 0.0
var _tick_accum: float = 0.0
## 每片毒液的形状扰动种子，免得几团叠在一起像同一个圆规画的。
var _wobble: float = 0.0

func setup(p_radius: float, p_dps: float, p_tick: float, p_life: float) -> void:
	radius = maxf(1.0, p_radius)
	dps = maxf(0.0, p_dps)
	tick = maxf(0.05, p_tick)
	life = maxf(0.1, p_life)

func _ready() -> void:
	add_to_group("poison_pools")
	# 画在 TileMap 之上、玩家和敌人之下：毒池是地面地形，不能挡住角色。
	# z_index = 0 与 TileMap 同层，靠"World 先画 TileMap 再画毒池"的子节点
	# 顺序压在图上；以前用 -5，被整片地图盖掉（毒雾落地就看不见）。
	z_index = 0
	_wobble = randf() * TAU

func _physics_process(delta: float) -> void:
	# 时停：毒池停止跳伤害，存留时间也一起冻住。
	#
	# 两头都要冻**才**自洽：只冻伤害的话，玩家可以站在毒池里靠时停把它耗光
	# （时停变成"免费清毒池"）；只冻寿命的话，时停期间照样掉血，玩家会觉得
	# 时停对敌人留下的东西无效。和敌弹/毒团同一条规则。
	if GameState.is_time_stopped() or get_tree().paused:
		return
	_age += delta
	if _age >= life:
		queue_free()
		return
	queue_redraw()
	_tick_accum += delta
	if _tick_accum >= tick:
		_tick_accum -= tick
		_apply_tick()

## 对半径内的玩家结算一跳。伤害按 dps * tick 换算，所以调 tick 只改手感的
## 颗粒度、不改总伤害 —— 这是让 dps 成为唯一强度旋钮的关键。
func _apply_tick() -> void:
	if dps <= 0.0:
		return
	for p in get_tree().get_nodes_in_group("player"):
		if not (p is Node2D) or not p.has_method("take_dot_damage"):
			continue
		var body := p as Node2D
		if body.global_position.distance_to(global_position) > radius:
			continue
		body.take_dot_damage(dps * tick, POOL_FLASH)

## 当前不透明度：淡入 → 满值 → 淡出。快消失的池子必须看起来快消失了，
## 否则玩家学不会"这块地什么时候能踩"。
func alpha_mult() -> float:
	if _age < FADE:
		return clampf(_age / FADE, 0.0, 1.0)
	var left: float = life - _age
	if left < FADE:
		return clampf(left / FADE, 0.0, 1.0)
	return 1.0

func _draw() -> void:
	var a: float = alpha_mult()
	# 主体：半透明毒液。
	draw_circle(Vector2.ZERO, radius, Color(0.25, 0.75, 0.3, 0.34 * a))
	# 内圈更浓，读作"这里最脏"。
	draw_circle(Vector2.ZERO, radius * 0.6, Color(0.35, 0.9, 0.4, 0.22 * a))
	# 轮廓：不规则边缘，让它看起来是液体而不是技能圈。
	var pts: PackedVector2Array = PackedVector2Array()
	var n: int = 28
	for i in range(n + 1):
		var ang: float = TAU * float(i) / float(n)
		var r: float = radius * (0.93 + 0.07 * sin(ang * 3.0 + _wobble))
		pts.append(Vector2(cos(ang), sin(ang)) * r)
	draw_polyline(pts, Color(0.5, 1.0, 0.45, 0.7 * a), 3.0, true)
	# 几个气泡，用 _age 驱动，静止的毒池会被误读成装饰。
	for i in range(5):
		var ba: float = _wobble + TAU * float(i) / 5.0 + _age * 0.8
		var bd: float = radius * (0.3 + 0.35 * absf(sin(_age * 1.3 + float(i))))
		draw_circle(Vector2(cos(ba), sin(ba)) * bd, radius * 0.07,
			Color(0.6, 1.0, 0.5, 0.5 * a))
