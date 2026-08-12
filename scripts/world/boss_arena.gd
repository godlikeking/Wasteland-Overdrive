extends Node
## 第二关 BOSS 竞技场控制器：玩家踏进房间 → BOSS 即刻降临 + 封门，BOSS 死亡
## 后开门。
##
## 竞技场几何（房间矩形 + 门洞格子）由 TilemapBuilder 在生成地图时挖好，这里只
## 负责"何时刷 BOSS / 何时封门 / 何时开门"，封门开门都走 World 的转发方法。
##
## 触发语义：**进门即开打**。以前是等 SpawnDirector 的 3 分钟计时把 BOSS 刷出来
## 之后才算激活，房间在那之前是空的；现在玩家一脚踏进竞技场就同时做两件事 ——
## 让刷怪总管立刻放 BOSS（`spawn_boss_now`，一局只放一次），并封死门洞。
## 直到 BOSS 被打败（boss_defeated）才开门；第二关打败 BOSS 即通关结算，所以
## 这个"封到打赢"对玩家来说近似是永久的。

class_name BossArena

var _world: Node = null
var _sealed: bool = false

func _ready() -> void:
	add_to_group("boss_arena")
	GameState.boss_defeated.connect(_on_boss_defeated)

func _process(_delta: float) -> void:
	if _sealed:
		return
	if _world == null:
		_world = get_tree().get_first_node_in_group("world")
	if _world == null or not _world.has_method("boss_arena_contains") \
			or not _world.has_method("seal_boss_door"):
		return
	if not _world.has_method("has_boss_arena") or not _world.has_boss_arena():
		return
	var p: Node = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	if not _world.boss_arena_contains(p.global_position):
		return
	# 进门：先放 BOSS 再封门。顺序无关紧要（BOSS 落点在房间中央、玩家已经在
	# 房里），但先刷后封读起来更像"门在你身后关上"。
	_sealed = true
	_summon_boss()
	_world.seal_boss_door()
	_flash_seal_banner(p.global_position)

## 让刷怪总管立刻放 BOSS。重复调用由 SpawnDirector 自己挡（`_boss_spawned`），
## 所以就算这里被多触发一次也不会刷出第二只。
func _summon_boss() -> void:
	var sd: Node = get_tree().get_first_node_in_group("boss_spawner")
	if sd != null and sd.has_method("spawn_boss_now"):
		sd.spawn_boss_now()

func _on_boss_defeated() -> void:
	if _world != null and _world.has_method("open_boss_door"):
		_world.open_boss_door()
	_sealed = false

func _flash_seal_banner(pos: Vector2) -> void:
	var list: Array = get_tree().get_nodes_in_group("fx_manager")
	if list.is_empty():
		return
	var fx: Node = list[0]
	if fx and fx.has_method("_spawn_label"):
		fx._spawn_label(pos, "⚡ 入口已封！击败 BOSS 才能离开 ⚡",
			Color(0.4, 0.9, 1.0), 26, 1.6)
