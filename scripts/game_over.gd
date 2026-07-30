extends CanvasLayer
## Game-over screen. Shows the final time reached and offers a restart.

signal restart_requested

@onready var time_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TimeLabel
@onready var level_label: Label = $CenterContainer/Panel/MarginContainer/VBox/LevelLabel
@onready var restart_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/RestartButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	restart_btn.pressed.connect(func(): restart_requested.emit())

func show_result() -> void:
	var seconds: float = GameState.time_alive
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	time_label.text = "存活时间: %02d:%02d" % [m, s]
	level_label.text = "达到等级: %d" % GameState.level
	visible = true
	get_tree().paused = true
