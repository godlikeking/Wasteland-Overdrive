extends Node
## 出界惩罚：地图边缘没有墙，代价全在这里。挂在 player.tscn 上，每帧问
## World（"world" 组）自己在图外多深，然后按爬坡曲线扣血。
##
## **只挂玩家，刻意不复用 ToxicSwamp 的"两边都挂"写法**：ToxicSwamp 同时挂在
## enemy.tscn 上，而敌人本来就生成在镜头外 —— 玩家贴边时半数生成点落在图外。
## 如果敌人也吃出界伤害，边界就会变成一台自动刷分机：站在角上等敌人自己融化。
## 出界是给玩家的规则，不是全局物理。
##
## 伤害走 Player.take_dot_damage 而不是 take_damage，理由见那个函数的文档：
## 无敌帧会把 0.25s 一跳压成 2.5 跳/秒（"高额"直接失效）、护盾会被 5 点伤害
## 换掉一整层、player_hurt 会让 Engine.time_scale 每跳掉到 0.05。
##
## 曲线：base 20 起跳，_out_time 每过 ramp 秒翻一倍，封顶 ramp_max 倍 = 80/秒。
## 100 血从跨界到死约 2.7 秒 —— 是道真墙，但擦过一个角还来得及跑回来。

class_name OutOfBounds

## 出界扣血闪色：深红，和正常受伤的亮红、毒沼的黄绿、毒池的亮绿都能分开。
const OOB_FLASH: Color = Color(1.5, 0.25, 0.25)

@export var body_path: NodePath
## 每秒基础伤害（刚跨界时的强度）。
@export var base_dps: float = 20.0
## 结算间隔。只决定颗粒度：每跳扣 dps * tick，总伤害与 tick 无关。
@export var tick: float = 0.25
## 爬坡时间常数：在外面待满 ramp 秒，dps 翻一倍。
@export var ramp: float = 3.0
## 爬坡倍数上限。
@export var ramp_max: float = 4.0

var _body: Node
var _world: Node
var _out_time: float = 0.0
var _tick_accum: float = 0.0
## 上一帧是否在图外。用来保证"回到图内"这件事只发一次信号清 HUD，
## 而不是每帧刷一条 depth = 0。
var _was_out: bool = false

func _ready() -> void:
	if body_path != NodePath():
		_body = get_node_or_null(body_path)
	# World 在 _ready 里惰性建图（见 world.gd），这一帧还问不到边界，
	# 推到下一帧再解析。
	_resolve_world()
	if _world == null:
		call_deferred("_resolve_world")

func _resolve_world() -> void:
	for w in get_tree().get_nodes_in_group("world"):
		if w != null and w.has_method("out_of_bounds_depth"):
			_world = w
			return

func _physics_process(delta: float) -> void:
	if _body == null or _world == null:
		return
	# 地图还没画出来时 map_rect 是零尺寸的，那会让"图外"读成整个世界，
	# 开局第一帧就把玩家烧死。没有地图 = 没有边界。
	if _world.has_method("map_rect") and (_world.map_rect() as Rect2).size == Vector2.ZERO:
		return
	var depth: float = _world.out_of_bounds_depth(_body.global_position)
	if depth <= 0.0:
		_out_time = 0.0
		_tick_accum = 0.0
		if _was_out:
			_was_out = false
			GameState.out_of_bounds_changed.emit(0.0, 0.0)
		return
	_was_out = true
	_out_time += delta
	var dps: float = current_dps(_out_time)
	GameState.out_of_bounds_changed.emit(depth, dps)
	_tick_accum += delta
	if _tick_accum < tick:
		return
	_tick_accum -= tick
	if _body.has_method("take_dot_damage"):
		_body.take_dot_damage(dps * tick, OOB_FLASH)

## 在图外待了 out_time 秒时的每秒伤害。纯函数，出界伤害的全部曲线都在这里，
## 所以自检可以直接断言斜率而不用真的把玩家推到虚空里跑上几秒。
func current_dps(out_time: float) -> float:
	if ramp <= 0.0:
		return base_dps * ramp_max
	return base_dps * clampf(1.0 + out_time / ramp, 1.0, ramp_max)
