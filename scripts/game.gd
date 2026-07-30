extends Node2D
## Root of the combat scene. Boots run state, wires level-up/game-over flow,
## and handles pause/restart. All node lookups are defensive so a missing
## child prints a clear error instead of crashing.

@onready var player: Node = get_node_or_null("Player")
@onready var hud: Node = get_node_or_null("HUD")
@onready var level_up_ui: Node = get_node_or_null("LevelUp")
@onready var game_over_ui: Node = get_node_or_null("GameOver")

var _pending_level_ups: int = 0
var _wired: bool = false

func _ready() -> void:
	print("[Game] _ready — validating scene wiring")
	if not _validate_children():
		push_error("[Game] scene wiring invalid — see previous errors")
		return

	GameState.reset()
	GameState.is_running = true

	GameState.leveled_up.connect(_on_leveled_up)
	GameState.player_died.connect(_on_player_died)
	level_up_ui.choice_applied.connect(_on_choice_applied)
	game_over_ui.restart_requested.connect(_on_restart_requested)
	_wired = true

	# Emit initial UI state
	GameState.player_health_changed.emit(100.0, 100.0)
	GameState.xp_changed.emit(0.0, GameState.xp_needed_for_level(1))
	GameState.level_changed.emit(1)
	print("[Game] ready OK")

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
	level_up_ui.show_choices()

func _on_choice_applied() -> void:
	if _pending_level_ups > 0:
		call_deferred("_show_next_level_up")

func _on_player_died() -> void:
	GameState.is_running = false
	game_over_ui.show_result()

func _on_restart_requested() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
