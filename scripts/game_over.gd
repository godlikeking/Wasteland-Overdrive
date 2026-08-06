extends CanvasLayer
## Game-over screen. Shows the final time reached, run stats, and offers
## either a restart, a "fresh start" (wipe the meta save), or a detour into
## the meta shop.

signal restart_requested
signal fresh_start_requested
signal open_shop_requested

@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBox/Title
@onready var time_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TimeLabel
@onready var level_label: Label = $CenterContainer/Panel/MarginContainer/VBox/LevelLabel
@onready var kills_label: Label = $CenterContainer/Panel/MarginContainer/VBox/KillsLabel
@onready var currency_label: Label = $CenterContainer/Panel/MarginContainer/VBox/CurrencyLabel
@onready var total_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TotalLabel
@onready var shop_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/ShopButton
@onready var restart_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/RestartButton
@onready var fresh_start_btn: Button = $CenterContainer/Panel/MarginContainer/VBox/FreshStartButton

var _last_reward: int = 0
var _victory: bool = false

const VICTORY_TITLE: String = "任务胜利"
const DEFEAT_TITLE: String = "任务失败"
const VICTORY_COLOR: Color = Color(1.0, 0.84, 0.33)
const DEFEAT_COLOR: Color = Color(0.95, 0.5, 0.5)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	restart_btn.pressed.connect(func(): restart_requested.emit())
	fresh_start_btn.pressed.connect(func(): fresh_start_requested.emit())
	shop_btn.pressed.connect(func(): open_shop_requested.emit())

func show_result(victory := false) -> void:
	_victory = victory
	var seconds: float = GameState.time_alive
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	# 标题按胜负动态设置：.tscn 里硬编码的是"任务失败"，胜利覆盖成金色"任务胜利"。
	title_label.text = VICTORY_TITLE if _victory else DEFEAT_TITLE
	title_label.add_theme_color_override("font_color",
		VICTORY_COLOR if _victory else DEFEAT_COLOR)
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
