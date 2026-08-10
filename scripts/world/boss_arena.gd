extends Node
## 第二关 BOSS 竞技场控制器：玩家进入且 BOSS 激活后封门，BOSS 死亡后开门。
##
## 竞技场几何（房间矩形 + 门洞格子）由 TilemapBuilder 在生成地图时挖好，
## 这里只负责"何时封门 / 何时开门"，封门开门都走 World 的转发方法。
## 触发语义：BOSS 刷新（boss_spawned）后竞技场才算"激活"，玩家进门前门始终
## 开着、BOSS 被 enemy.gd 的 arena_rect 牵制在房里；玩家一脚踏进竞技场 → 封门，
## 直到 BOSS 被打败（boss_defeated）才开门。第二关打败 BOSS 即通关结算，所以
## 这个"封到打赢"对玩家来说近似是永久的。

class_name BossArena

var _world: Node = null
var _sealed: bool = false
var _boss_active: bool = false

func _ready() -> void:
	add_to_group("boss_arena")
	GameState.boss_spawned.connect(_on_boss_spawned)
	GameState.boss_defeated.connect(_on_boss_defeated)

func _process(_delta: float) -> void:
	if _sealed or not _boss_active:
		return
	if _world == null:
		_world = get_tree().get_first_node_in_group("world")
	if _world == null or not _world.has_method("boss_arena_contains") \
			or not _world.has_method("seal_boss_door"):
		return
	var p: Node = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	if _world.boss_arena_contains(p.global_position):
		_sealed = true
		_world.seal_boss_door()
		_flash_seal_banner(p.global_position)

func _on_boss_spawned(_boss: Node2D) -> void:
	_boss_active = true

func _on_boss_defeated() -> void:
	if _world != null and _world.has_method("open_boss_door"):
		_world.open_boss_door()
	_sealed = false
	_boss_active = false

func _flash_seal_banner(pos: Vector2) -> void:
	var list: Array = get_tree().get_nodes_in_group("fx_manager")
	if list.is_empty():
		return
	var fx: Node = list[0]
	if fx and fx.has_method("_spawn_label"):
		fx._spawn_label(pos, "⚡ 入口已封！击败 BOSS 才能离开 ⚡",
			Color(0.4, 0.9, 1.0), 26, 1.6)
