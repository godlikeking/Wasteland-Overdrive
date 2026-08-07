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

var _pending_level_ups: int = 0
var _weapon_director: Node

func _ready() -> void:
	print("[Game] _ready — validating scene wiring")
	if not _validate_children():
		push_error("[Game] scene wiring invalid — see previous errors")
		return

	GameState.reset()
	GameState.is_running = true
	# 第二关由 _advance_to_level 置 queued_level 后换场景而来：新场景的
	# reset() 会把 current_level 拨回 1，这里从传送带恢复。
	GameState.current_level = GameState.queued_level

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
	# 传送带：新场景 _ready 里 reset() 会把 current_level 拨回 1，
	# 必须靠 queued_level 记住目标关卡（见 game.gd 头部）。
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
	GameState.queued_level = 1
	get_tree().paused = false
	get_tree().reload_current_scene()

## 从头开始：清空元进度存档（废金属/累计统计/已购模块），再重开一局。
func _on_fresh_start_requested() -> void:
	if MetaProgress:
		MetaProgress.wipe()
	GameState.queued_level = 1
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_open_shop() -> void:
	if game_over_ui and game_over_ui.has_method("open_shop"):
		game_over_ui.open_shop()
	if shop_ui and shop_ui.has_method("open"):
		shop_ui.open()

func _on_shop_closed() -> void:
	if game_over_ui and game_over_ui.has_method("close_shop"):
		game_over_ui.close_shop()
