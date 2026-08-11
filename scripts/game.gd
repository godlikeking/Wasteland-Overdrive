extends Node2D
## Root of the combat scene. Boots run state, wires the level-up / game-over
## flow, and handles restart. All node lookups are defensive so a missing child
## prints a clear error instead of crashing. Pausing belongs to PauseMenu — see
## the note further down for why it cannot live here.

@onready var player: Node = get_node_or_null("Player")
@onready var hud: Node = get_node_or_null("HUD")
@onready var level_up_ui: Node = get_node_or_null("LevelUp")
@onready var game_over_ui: Node = get_node_or_null("GameOver")
@onready var shop_ui: Node = get_node_or_null("Shop")
@onready var pause_menu: Node = get_node_or_null("PauseMenu")

## 本场景是第几关（1 = 废土，2 = 机器人工厂）。**场景自己声明**，而不是靠
## GameState.queued_level 传送带推断。
##
## 为什么必须这样：所有"第二关专属"行为都在读 GameState.current_level ——
## 敌弹电球贴图（enemy_projectile）、墙体挡锁敌视线（weapon）。而
## queued_level 只有走"杀第一关 BOSS → _advance_to_level"这条路才会变成 2；
## 在编辑器里直接 F6 跑 game_factory.tscn 时它还是 1，于是那些第二关特性
## 全部**静默退回第一关行为**（子弹变回红紫等离子、武器能穿墙锁敌），看起来
## 就像"改好的东西又变回来了"，而且不报任何错。场景编号是场景的固有属性，
## 让它自己说。
@export var level_index: int = 1

var _pending_level_ups: int = 0
var _weapon_director: Node

func _ready() -> void:
	print("[Game] _ready — validating scene wiring")
	if not _validate_children():
		push_error("[Game] scene wiring invalid — see previous errors")
		return

	GameState.reset()
	GameState.is_running = true
	# 关卡编号以场景自己的 level_index 为准，直接运行某一关也成立。
	# queued_level 同步跟上，让关间切换/重开读到的是同一个值。
	GameState.current_level = level_index
	GameState.queued_level = level_index
	# 关间切换可能带走一个未结束的 hit-stop：_on_hit_stop 先把
	# Engine.time_scale 压到 0.05，再 await 一个挂在 FxManager 上的计时器
	# 恢复——FxManager 随换场景被 free 后那句恢复永不执行，time_scale 就卡在
	# 0.05，整关慢动作（玩家爬行、敌人像没刷出来）。这里每关开局强制复位，
	# 顺便也兜住重启/重开时残留的卡住。
	Engine.time_scale = 1.0

	# Apply permanent meta upgrades (currency-bought) before weapons/player
	# are wired so they take effect on first stats read.
	if MetaProgress:
		MetaProgress.start_run()

	# Grant starter weapon via the autoloaded WeaponDirector.
	# We defer so the player group is fully populated by the time WD looks it up.
	call_deferred("_grant_default_weapons")

	GameState.leveled_up.connect(_on_leveled_up)
	GameState.player_died.connect(_on_player_died)
	GameState.boss_defeated.connect(_on_boss_defeated)
	level_up_ui.choice_applied.connect(_on_choice_applied)
	level_up_ui.fusion_chosen.connect(_on_fusion_chosen)
	level_up_ui.fusion_skipped.connect(_on_choice_applied)
	game_over_ui.restart_requested.connect(_on_restart_requested)
	game_over_ui.fresh_start_requested.connect(_on_fresh_start_requested)
	game_over_ui.open_shop_requested.connect(_on_open_shop)
	if shop_ui and shop_ui.has_signal("closed"):
		shop_ui.closed.connect(_on_shop_closed)

	# Emit initial UI state
	GameState.player_health_changed.emit(100.0, 100.0)
	GameState.xp_changed.emit(0.0, GameState.xp_needed_for_level(1))
	GameState.level_changed.emit(1)
	print("[Game] ready OK")

func _grant_default_weapons() -> void:
	if WeaponDirector and WeaponDirector.has_method("add_weapon_by_id"):
		WeaponDirector.add_weapon_by_id("bullet_volley")

func _validate_children() -> bool:
	var ok := true
	if player == null:
		push_error("[Game] child 'Player' missing")
		ok = false
	if hud == null:
		push_error("[Game] child 'HUD' missing")
		ok = false
	if level_up_ui == null:
		push_error("[Game] child 'LevelUp' missing")
		ok = false
	if game_over_ui == null:
		push_error("[Game] child 'GameOver' missing")
		ok = false
	if pause_menu == null:
		push_error("[Game] child 'PauseMenu' missing")
		ok = false
	return ok

# NOTE: ESC is handled by PauseMenu, not here. This node is PAUSABLE (World,
# Player and the spawn directors inherit their process mode from it and must
# stop while paused), so it stops receiving input the moment the game pauses —
# a pause toggle living here could pause but never resume. See pause_menu.gd.

func _on_leveled_up(_lvl: int) -> void:
	_pending_level_ups += 1
	if not level_up_ui.visible:
		_show_next_level_up()

func _show_next_level_up() -> void:
	if _pending_level_ups <= 0:
		return
	_pending_level_ups -= 1
	# If the player can fuse, prioritize the fusion panel.
	var candidates: Array = WeaponDirector.fuse_candidates()
	if not candidates.is_empty():
		level_up_ui.show_fusion_choices(candidates)
	else:
		level_up_ui.show_choices()

func _on_choice_applied() -> void:
	if _pending_level_ups > 0:
		call_deferred("_show_next_level_up")

func _on_fusion_chosen(recipe_id: String) -> void:
	var new_id: String = WeaponDirector.fuse(recipe_id)
	if new_id != "":
		_apply_fusion_fx(new_id)
	# Continue the level-up queue (each level-up still gets a panel,
	# but the fused-in weapon now counts as "max level" so no further
	# panel is generated until next real level up).
	if _pending_level_ups > 0:
		call_deferred("_show_next_level_up")

func _apply_fusion_fx(new_weapon_id: String) -> void:
	# Find the player and trigger a one-shot pulse.
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var pos: Vector2 = (players[0] as Node2D).global_position
	GameState.request_camera_shake.emit(12.0, 0.6)
	GameState.request_hit_stop.emit(0.18)
	# Big label
	var list: Array = get_tree().get_nodes_in_group("fx_manager")
	if not list.is_empty():
		var fx: Node = list[0]
		if fx.has_method("_spawn_label"):
			fx._spawn_label(pos, "⚡ %s 融合成功！⚡" % new_weapon_id,
				Color(1.0, 0.85, 0.3), 36, 1.4)
	SfxPlayer.play("levelup")
	print("[Game] fusion FX applied: %s" % new_weapon_id)

func _on_player_died() -> void:
	_end_run(false)

## 杀掉 BOSS：第一关的废土巨兽 → 进入第二关（机器人工厂），第二关的
## 巨型机器人 → 通关结算。
func _on_boss_defeated() -> void:
	if GameState.current_level == 1:
		_advance_to_level(2)
		return
	_end_run(true)

## 关间切换：武器 / 等级 / 被动全保留（都挂在 autoload 或 GameState 上），
## 只有地图和刷怪节奏重置。
func _advance_to_level(level: int) -> void:
	GameState.current_level = level
	# 目标关卡的场景自己会用 level_index 声明它是第几关（见头部注释），这里
	# 同步 queued_level 只是为了换场景那一帧之间两个字段不打架。
	GameState.queued_level = level
	GameState.time_alive = 0.0
	# 清掉上一关的敌人和掉落，避免它们跟着场景切换悬空。
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()
	for g in ["xp_gems", "pickup_items", "poison_pools", "poison_globs"]:
		for n in get_tree().get_nodes_in_group(g):
			if is_instance_valid(n):
				n.queue_free()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/game_factory.tscn")

## 一局结束的唯一入口，胜负都走这里。终点是结算界面（game_over_ui）。
func _end_run(victory: bool) -> void:
	GameState.is_running = false
	GameState.game_over.emit(victory)
	# Award meta currency for the run.
	if MetaProgress:
		var reward: int = MetaProgress.finish_run(GameState.time_alive)
		print("[Game] run finished (%s): %d currency awarded" %
			["victory" if victory else "defeat", reward])
	game_over_ui.show_result(victory)

func _on_restart_requested() -> void:
	_restart_from_level_one()

## 从头开始：清空元进度存档（废金属/累计统计/已购模块），再重开一局。
func _on_fresh_start_requested() -> void:
	if MetaProgress:
		MetaProgress.wipe()
	_restart_from_level_one()

## 重开一局，回到第一关。
##
## 以前这里是 `queued_level = 1` + `reload_current_scene()`，两句互相矛盾：
## 在第二关按重开会**原地重载工厂场景**，而不是回废土 —— 一局全新的、没有
## 任何武器的角色被丢在第二关地图里。现在关卡编号由场景的 level_index 决定，
## 那句 queued_level 更是彻底失效，所以按它原本的意图老实换回第一关场景。
## 第一关仍走 reload_current_scene，保住 main.tscn 那层外壳不被换掉。
func _restart_from_level_one() -> void:
	GameState.queued_level = 1
	get_tree().paused = false
	if level_index == 1:
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_open_shop() -> void:
	if game_over_ui and game_over_ui.has_method("open_shop"):
		game_over_ui.open_shop()
	if shop_ui and shop_ui.has_method("open"):
		shop_ui.open()

func _on_shop_closed() -> void:
	if game_over_ui and game_over_ui.has_method("close_shop"):
		game_over_ui.close_shop()
