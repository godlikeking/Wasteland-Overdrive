extends Node2D
class_name ClawSlash
## BOSS 近战爪击的判定几何 + 视觉。
##
## 判定全在 `in_arc()` 这个静态纯函数里，其余都是画面。这么切分是因为
## `_draw()` 的东西自检验证不了 —— 和 ui/boss_marker.gd 的 `marker_for()`
## 同一个先例：把能算的部分挤成纯函数，才有东西可断言。
##
## 伤害**不**由本节点结算，由 BOSS 在命中帧调 in_arc 后自己打。单一伤害来源，
## 不像 explosion.gd 那样把伤害埋进特效里（那会让"特效没生成"静默地等于
## "攻击没发生"）。

## 楔形判定：target 是否落在以 from 为顶点、facing 为中轴、reach 为长、
## arc 为总弧宽的扇形里。
##
## 纯函数、无副作用，爪击的全部命中逻辑就这一条。
## - reach 用 <= ：恰好在边界上算命中，和"半径以内"的直觉一致。
## - facing 长度为 0 时返回 false 而不是崩：调用方拿不到朝向时应该是"打空"，
##   不是让整个 _physics_process 报错。
## - arc >= TAU 时退化成纯距离判定（全向），这是有意义的极端配置。
static func in_arc(from: Vector2, facing: Vector2, target: Vector2,
		reach: float, arc: float) -> bool:
	if facing.length_squared() < 0.0000001:
		return false
	var to_target: Vector2 = target - from
	var dist: float = to_target.length()
	if dist > reach:
		return false
	# 顶点上的目标：没有方向可比，但它确实在爪子里。
	if dist < 0.0001:
		return true
	if arc >= TAU:
		return true
	# 半角比较用 angle_to 的绝对值，避免自己处理 ±PI 环绕。
	return absf(facing.angle_to(to_target)) <= arc * 0.5

# --- 视觉 ---

## 预警阶段：细轮廓，读作"这里马上要被扫"。
const WINDUP_COLOR: Color = Color(1.0, 0.45, 0.35, 0.55)
## 命中阶段：亮色实心，一闪而过。
const STRIKE_COLOR: Color = Color(1.0, 0.85, 0.6, 0.75)
## 命中特效的存留时长。
const STRIKE_TIME: float = 0.18

var reach: float = 190.0
var arc: float = 1.9
var facing: Vector2 = Vector2.RIGHT
## 预警总时长，用来把轮廓从空画到满，作为进度条。
var windup: float = 0.45

var _striking: bool = false
var _age: float = 0.0

func setup(p_facing: Vector2, p_reach: float, p_arc: float, p_windup: float) -> void:
	facing = p_facing if p_facing.length_squared() > 0.0 else Vector2.RIGHT
	reach = maxf(1.0, p_reach)
	arc = clampf(p_arc, 0.05, TAU)
	windup = maxf(0.01, p_windup)

func _ready() -> void:
	add_to_group("claw_slashes")
	z_index = 18

## BOSS 在预警结束时调用，把节点从"预警"切到"命中闪光"，STRIKE_TIME 后自灭。
func strike() -> void:
	_striking = true
	_age = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _striking and _age >= STRIKE_TIME:
		queue_free()
	# 预警期超时未被 strike()（BOSS 死了 / 被冻住）就自己清掉，
	# 免得留一个永远不会落下的爪印。
	elif not _striking and _age >= windup + 0.5:
		queue_free()

func _draw() -> void:
	var base: float = facing.angle()
	var a0: float = base - arc * 0.5
	var a1: float = base + arc * 0.5
	if _striking:
		var fade: float = 1.0 - clampf(_age / STRIKE_TIME, 0.0, 1.0)
		var fill: Color = STRIKE_COLOR
		fill.a *= fade
		_draw_wedge(a0, a1, reach, fill)
		var edge: Color = Color(1.0, 1.0, 0.9, fade)
		draw_arc(Vector2.ZERO, reach, a0, a1, 32, edge, 5.0, true)
		return
	# 预警：轮廓从中轴向两侧张开，张满就是落下的瞬间。
	var t: float = clampf(_age / windup, 0.0, 1.0)
	var w0: float = lerpf(base, a0, t)
	var w1: float = lerpf(base, a1, t)
	draw_arc(Vector2.ZERO, reach, w0, w1, 32, WINDUP_COLOR, 3.0, true)
	draw_line(Vector2.ZERO, Vector2(cos(w0), sin(w0)) * reach, WINDUP_COLOR, 2.0)
	draw_line(Vector2.ZERO, Vector2(cos(w1), sin(w1)) * reach, WINDUP_COLOR, 2.0)

func _draw_wedge(a0: float, a1: float, r: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(Vector2.ZERO)
	var steps: int = 20
	for i in range(steps + 1):
		var ang: float = lerpf(a0, a1, float(i) / float(steps))
		pts.append(Vector2(cos(ang), sin(ang)) * r)
	draw_colored_polygon(pts, col)
