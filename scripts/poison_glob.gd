extends Node2D
class_name PoisonGlob
## BOSS 抛出的一团毒液。飞 `flight` 秒抵达落点，然后变成一片 PoisonPool。
##
## **飞行途中不造成任何伤害，也没有碰撞体。** 这是设计选择而不是省事：
## 威胁在落点，不在弹道。玩家要能看着毒团的落地标记横向跑开，如果飞行段也
## 伤人，那条躲避线索就变成了假的。所有伤害都由落地后的 PoisonPool 结算。
##
## 和 PoisonPool 一样纯 _draw()：见那边关于调色板没有绿色的说明。

var origin: Vector2 = Vector2.ZERO
var target: Vector2 = Vector2.ZERO
var flight: float = 0.55
var pool_radius: float = 95.0
var pool_dps: float = 14.0
var pool_tick: float = 0.5
var pool_life: float = 6.0
## 抛物线的视觉抬高量。毒团是"抛"出去的，直线飞会读成子弹。
var arc_height: float = 90.0

var _age: float = 0.0

func setup(p_origin: Vector2, p_target: Vector2, p_flight: float,
		p_pool_radius: float, p_pool_dps: float, p_pool_tick: float,
		p_pool_life: float) -> void:
	origin = p_origin
	target = p_target
	flight = maxf(0.05, p_flight)
	pool_radius = maxf(1.0, p_pool_radius)
	pool_dps = maxf(0.0, p_pool_dps)
	pool_tick = maxf(0.05, p_pool_tick)
	pool_life = maxf(0.1, p_pool_life)

func _ready() -> void:
	add_to_group("poison_globs")
	z_index = 15
	global_position = origin

func _physics_process(delta: float) -> void:
	_age += delta
	var t: float = clampf(_age / flight, 0.0, 1.0)
	global_position = origin.lerp(target, t)
	queue_redraw()
	if t >= 1.0:
		_land()

func _land() -> void:
	var pool := PoisonPool.new()
	pool.setup(pool_radius, pool_dps, pool_tick, pool_life)
	# 挂到当前场景而不是自己名下 —— 自己下一帧就 queue_free 了。
	get_tree().current_scene.add_child(pool)
	pool.global_position = target
	SfxPlayer.play("hit")
	queue_free()

## 抛物线的视觉偏移（不进入碰撞/判定，纯画面）。
func _hop_offset(t: float) -> Vector2:
	return Vector2(0.0, -arc_height * sin(PI * t))

func _draw() -> void:
	var t: float = clampf(_age / flight, 0.0, 1.0)
	var off: Vector2 = _hop_offset(t)
	# 落地标记先画：这才是玩家需要读的信息，毒团本身只是它的倒计时。
	# 画在 target 的**局部坐标**上（本节点在 origin→target 之间移动，用
	# Vector2.ZERO 会让标记跟着毒团跑，那就不是落点标记了）。
	# 圈随 t 收紧到实际池子半径，"多久之后这里变毒池"一眼可见。
	var mark: Vector2 = target - global_position
	var mark_r: float = pool_radius * lerpf(1.35, 1.0, t)
	draw_arc(mark, mark_r, 0.0, TAU, 40,
		Color(0.5, 1.0, 0.45, 0.35 + 0.35 * t), 3.0, true)
	# 毒团本体。
	draw_circle(off, 13.0, Color(0.3, 0.8, 0.35, 0.9))
	draw_circle(off, 7.0, Color(0.65, 1.0, 0.5, 0.95))
