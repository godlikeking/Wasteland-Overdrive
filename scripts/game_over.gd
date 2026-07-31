extends CanvasLayer
## Game-over screen. Shows the final time reached, run stats, and offers
## either a restart or a detour into the meta shop.

signal restart_requested
signal open_shop_requested

@onready var time_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TimeLabel
@onready var level_label: Label = $CenterContainer/Panel/MarginContainer/VBox/LevelLabel
@onready var kills_label: Label = $CenterContainer/Panel/MarginContainer/VBox/KillsLabel
@onready var currency_label: Label = $CenterContainer/Panel/MarginContainer/VBox/CurrencyLabel
@onready var total_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TotalLabel
@onready var shop_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/ShopButton
@onready var restart_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/RestartButton

var _last_reward: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	restart_btn.pressed.connect(func(): restart_requested.emit())
	shop_btn.pressed.connect(func(): open_shop_requested.emit())

func show_result() -> void:
	var seconds: float = GameState.time_alive
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	time_label.text = "存活时间: %02d:%02d" % [m, s]
	level_label.text = "达到等级: %d" % GameState.level
	kills_label.text = "击杀: %d" % MetaProgress.run_kills
	if MetaProgress:
		_last_reward = int(seconds) + (MetaProgress.run_kills / 10)
		currency_label.text = "本次收益: +%d 废金属" % _last_reward
		total_label.text = "总废金属: %d    总击杀: %d    Boss: %d" % [
			MetaProgress.currency, MetaProgress.total_kills, MetaProgress.total_boss_kills
		]
	visible = true
	get_tree().paused = true

## Called by Game when player reopens shop from the game-over screen.
func open_shop() -> void:
	# Keep the game-over panel hidden while shopping, but the game stays paused.
	visible = false

func close_shop() -> void:
	# Re-show the panel after shopping (currency may have changed).
	if MetaProgress:
		total_label.text = "总废金属: %d    总击杀: %d    Boss: %d" % [
			MetaProgress.currency, MetaProgress.total_kills, MetaProgress.total_boss_kills
		]
	visible = true
