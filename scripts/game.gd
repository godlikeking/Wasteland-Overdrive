extends Node2D
## Root of the combat scene. Boots run state, wires level-up/game-over flow,
## and handles pause/restart. All node lookups are defensive so a missing
## child prints a clear error instead of crashing.

@onready var player: Node = get_node_or_null("Player")
@onready var hud: Node = get_node_or_null("HUD")
@onready var level_up_ui: Node = get_node_or_null("LevelUp")
@onready var game_over_ui: Node = get_node_or_null("GameOver")
@onready var shop_ui: Node = get_node_or_null("Shop")

var _pending_level_ups: int = 0
var _wired: bool = false
var _weapon_director: Node

func _ready() -> void:
	print("[Game] _ready — validating scene wiring")
	if not _validate_children():
		push_error("[Game] scene wiring invalid — see previous errors")
		return

	GameState.reset()
	GameState.is_running = true

	# Apply permanent meta upgrades (currency-bought) before weapons/player
	# are wired so they take effect on first stats read.
	if MetaProgress:
		MetaProgress.start_run()

	# Grant starter weapon via the autoloaded WeaponDirector.
	# We defer so the player group is fully populated by the time WD looks it up.
	call_deferred("_grant_default_weapons")

	GameState.leveled_up.connect(_on_leveled_up)
	GameState.player_died.connect(_on_player_died)
	level_up_ui.choice_applied.connect(_on_choice_applied)
	level_up_ui.fusion_chosen.connect(_on_fusion_chosen)
	level_up_ui.fusion_skipped.connect(_on_choice_applied)
	game_over_ui.restart_requested.connect(_on_restart_requested)
	game_over_ui.open_shop_requested.connect(_on_open_shop)
	if shop_ui and shop_ui.has_signal("closed"):
		shop_ui.closed.connect(_on_shop_closed)
	_wired = true

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
	return ok

func _unhandled_input(event: InputEvent) -> void:
	if not _wired:
		return
	if event.is_action_pressed("pause"):
		if level_up_ui.visible or game_over_ui.visible:
			return
		get_tree().paused = not get_tree().paused

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
	GameState.is_running = false
	# Award meta currency for the run.
	if MetaProgress:
		var reward: int = MetaProgress.finish_run(GameState.time_alive)
		print("[Game] run finished: %d currency awarded" % reward)
	game_over_ui.show_result()

func _on_restart_requested() -> void:
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
