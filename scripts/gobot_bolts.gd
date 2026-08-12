extends Node2D
class_name GobotBolts
## 巨型机器人「多道长条闪电」的判定几何 + 视觉。
##
## 和 claw_slash.gd / dash_telegraph.gd 同一个模板：`_draw()` 的东西自检验证
## 不了，所以把能算的部分挤成纯函数（`in_beam` / `bolt_angles`），其余都是画面。
## **伤害不由本节点结算**，由 BOSS 在命中帧自己打 —— 单一伤害来源，不像
## explosion.gd 那样把伤害埋进特效里（那会让"特效没生成"静默地等于"攻击没发生"）。

## 长条矩形命中判定：target 是否落在以 from 为起点、facing 为轴、length 为长、
## width 为总宽的长条里。
##
## 纯函数、无副作用。激光和多道闪电**共用**这一条 —— 这段数学原来内联在
## `_gobot_laser_strike` 里，一行测试都没有。
## - 身后（投影为负）不算命中：光束只朝前打。
## - 投影用 <= length、垂距用 <= width/2：边界上算命中，和"范围以内"的直觉一致。
## - facing 长度为 0 时返回 false 而不是崩：拿不到朝向应该是"打空"，
##   不是让整个 _physics_process 报错（和 ClawSlash.in_arc 同一个先例）。
static func in_beam(from: Vector2, facing: Vector2, target: Vector2,
		length: float, width: float) -> bool:
	if facing.length_squared() < 0.0000001:
		return false
	var dir: Vector2 = facing.normalized()
	var to_target: Vector2 = target - from
	var proj: float = to_target.dot(dir)
	if proj < 0.0 or proj > length:
		return false
	var perp: float = absf(dir.rotated(PI * 0.5).dot(to_target))
	return perp <= width * 0.5

## N 道闪电各自的朝向角，以 base 为中轴、spread 为总张角均匀铺开。
##
## 纯函数：命中判定要按这些角度逐条做 in_beam，视觉也要按同样的角度画线 ——
## 两边必须用同一个来源，否则"看到的"和"打到的"会错开。
## count <= 1 时退化成正中一条（spread 无意义）。
static func bolt_angles(base: float, count: int, spread: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n: int = maxi(1, count)
	if n == 1:
		out.append(base)
		return out
	for i in range(n):
		out.append(base + lerpf(-spread * 0.5, spread * 0.5, float(i) / float(n - 1)))
	return out

# --- 视觉 ---

## 预警阶段：细锯齿线，读作"这几条马上要过电"。
const WINDUP_COLOR: Color = Color(0.45, 0.8, 1.0, 0.5)
## 命中阶段：亮青白，一闪而过。
const STRIKE_COLOR: Color = Color(0.85, 0.98, 1.0, 0.9)
## 命中特效的存留时长。
const STRIKE_TIME: float = 0.16
## 锯齿抖动幅度（像素），和 chain_lightning 的手法一致。
const JAG: float = 10.0
## 每道线的锯齿段数。
const SEGMENTS: int = 8

var angles: PackedFloat32Array = PackedFloat32Array()
var length: float = 900.0
var width: float = 44.0
var windup: float = 0.9

var _striking: bool = false
var _age: float = 0.0
## 锯齿点在生成时定死，不每帧重抖 —— 预警线必须稳定可读，玩家要靠它判断站位。
var _jags: Array[PackedVector2Array] = []

func setup(p_angles: PackedFloat32Array, p_length: float, p_width: float,
		p_windup: float) -> void:
	angles = p_angles
	length = maxf(16.0, p_length)
	width = maxf(2.0, p_width)
	windup = maxf(0.01, p_windup)
	_build_jags()

func _ready() -> void:
	add_to_group("gobot_bolts")
	z_index = 18

func _build_jags() -> void:
	_jags.clear()
	for a in angles:
		var dir: Vector2 = Vector2(cos(a), sin(a))
		var perp: Vector2 = dir.rotated(PI * 0.5)
		var pts := PackedVector2Array()
		pts.append(Vector2.ZERO)
		for s in range(1, SEGMENTS):
			var t: float = float(s) / float(SEGMENTS)
			pts.append(dir * (length * t) + perp * randf_range(-JAG, JAG))
		pts.append(dir * length)
		_jags.append(pts)

## BOSS 在预警结束时调用，把节点从"预警"切到"命中闪光"，STRIKE_TIME 后自灭。
func strike() -> void:
	_striking = true
	_age = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	# 主人被时停冻住时，预警也跟着停住。
	#
	# 不这么做的话：冻结期间 BOSS 的蓄力计时不走（enemy.gd 早退），但这里的
	# _age 照走，预警会长完、并在 windup+0.5 时把自己清掉；解冻后 BOSS 接着
	# 蓄力完成直接命中 —— 一次完全看不见的攻击。
	# 冻结判定问主人而不是问 GameState：BOSS 的冻结窗口是减半的，而本节点
	# （DashTelegraph）还被突袭者/机器狗用着，走的是全额窗口。
	var host: Node = get_parent()
	if host != null and host.has_method("is_frozen") and host.is_frozen():
		return
	_age += delta
	queue_redraw()
	if _striking and _age >= STRIKE_TIME:
		queue_free()
	# 预警期超时未被 strike()（BOSS 死了 / 被冻住）就自己清掉，免得留一组
	# 永远不会落下的预警线。和 ClawSlash 同一个理由。
	elif not _striking and _age >= windup + 0.5:
		queue_free()

func _draw() -> void:
	if _jags.is_empty():
		return
	if _striking:
		var fade: float = 1.0 - clampf(_age / STRIKE_TIME, 0.0, 1.0)
		for pts in _jags:
			var col: Color = STRIKE_COLOR
			col.a *= fade
			# 粗底色 + 细亮芯，读作"高压电弧"而不是一条线。
			draw_polyline(pts, Color(0.3, 0.7, 1.0, 0.55 * fade), width * 0.5)
			draw_polyline(pts, col, 4.0)
		return
	# 预警：线从根部向外长出来，长满就是落下的瞬间。
	var t: float = clampf(_age / windup, 0.0, 1.0)
	for pts in _jags:
		var grown := PackedVector2Array()
		var take: int = maxi(2, int(ceilf(float(pts.size()) * t)))
		for i in range(mini(take, pts.size())):
			grown.append(pts[i])
		if grown.size() >= 2:
			draw_polyline(grown, WINDUP_COLOR, 2.5)
