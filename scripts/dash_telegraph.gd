extends Node2D
class_name DashTelegraph
## BOSS 直线冲刺的视觉预告。和 claw_slash.gd 同一个模板：`_draw()` 的东西
## 自检验证不了，所以判定（命中半径、冲刺位移）全部留在 enemy.gd 里，本节点
## 纯画面 —— 伤害**不**由它结算，单一伤害来源是 BOSS 的 `_boss_dash`。
##
## 蓄力期画一条沿冲刺方向的半透明长条 + 箭头（随进度变亮），strike() 后
## 变成一道亮色残影闪一下，然后自灭。贴在巨兽名下跟着身体走，被击退时
## 预告线不该留在原地（和 ClawSlash 同一个理由）。

## 蓄力期颜色：读作"这里马上要被碾过去"。
const WINDUP_COLOR: Color = Color(1.0, 0.4, 0.3, 0.4)
## 命中帧颜色：亮橙白，一闪而过。
const STRIKE_COLOR: Color = Color(1.0, 0.9, 0.7, 0.8)
## 命中特效的存留时长。
const STRIKE_TIME: float = 0.15

## 冲刺方向（单位向量）。
var facing: Vector2 = Vector2.RIGHT
## 冲刺线长度（= dash_speed × dash_duration 的预期位移）。
var dash_length: float = 300.0
## 预警总时长，用来把预告条从短画到长，作为进度条。
var windup: float = 0.5

var _striking: bool = false
var _age: float = 0.0

func setup(p_facing: Vector2, p_length: float, p_windup: float) -> void:
	facing = p_facing if p_facing.length_squared() > 0.0 else Vector2.RIGHT
	dash_length = maxf(16.0, p_length)
	windup = maxf(0.01, p_windup)

func _ready() -> void:
	add_to_group("dash_telegraphs")
	z_index = 18

## BOSS 在蓄力结束时调用，把节点从"预告"切到"命中残影"，STRIKE_TIME 后自灭。
func strike() -> void:
	_striking = true
	_age = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _striking and _age >= STRIKE_TIME:
		queue_free()
	# 蓄力期超时未被 strike()（BOSS 死了 / 被冻住）就自己清掉，
	# 免得留一条永远不会启动的冲刺线。
	elif not _striking and _age >= windup + 0.5:
		queue_free()

func _draw() -> void:
	var dir: Vector2 = facing.normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	if _striking:
		var fade: float = 1.0 - clampf(_age / STRIKE_TIME, 0.0, 1.0)
		var col: Color = STRIKE_COLOR
		col.a *= fade
		# 残影：整条冲刺线两笔宽 + 沿线的速度感箭头。
		_draw_strip(dir, perp, dash_length, 14.0, col)
		return
	# 蓄力：条从短变长 + 箭头从淡变亮，张满就是起冲的瞬间。
	var t: float = clampf(_age / windup, 0.0, 1.0)
	var length_now: float = dash_length * (0.3 + 0.7 * t)
	_draw_strip(dir, perp, length_now, 10.0, WINDUP_COLOR)
	_draw_arrows(dir, perp, length_now, WINDUP_COLOR)

## 一条从原点出发沿 dir 的长矩形。
func _draw_strip(dir: Vector2, perp: Vector2, length: float, half_w: float, col: Color) -> void:
	var end: Vector2 = dir * length
	var pts: PackedVector2Array = PackedVector2Array([
		perp * half_w,
		perp * half_w + end,
		-perp * half_w + end,
		-perp * half_w,
	])
	draw_colored_polygon(pts, col)

## 沿线等距的三个 V 形箭头，读作"朝这个方向冲"。
func _draw_arrows(dir: Vector2, perp: Vector2, length: float, col: Color) -> void:
	var n: int = 3
	var tip: float = 26.0
	var half_w: float = 14.0
	for i in range(1, n + 1):
		var at: Vector2 = dir * (length * float(i) / float(n + 1))
		var back: Vector2 = at - dir * tip
		var pts: PackedVector2Array = PackedVector2Array([
			at,
			back + perp * half_w,
			back - perp * half_w,
		])
		draw_colored_polygon(pts, col)
