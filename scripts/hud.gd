extends CanvasLayer
## In-game HUD showing health bar, XP bar, level, timer, and combo.

@onready var health_bar: TextureProgressBar = $MarginContainer/VBoxContainer/TopBar/HealthBar
@onready var health_label: Label = $MarginContainer/VBoxContainer/TopBar/HealthBar/Label
@onready var timer_label: Label = $MarginContainer/VBoxContainer/TopBar/TimerLabel
@onready var combo_label: Label = $MarginContainer/VBoxContainer/TopBar/ComboLabel
@onready var level_label: Label = $MarginContainer/VBoxContainer/BottomBar/LevelLabel
@onready var xp_bar: TextureProgressBar = $MarginContainer/VBoxContainer/BottomBar/XPBar

func _ready() -> void:
	GameState.player_health_changed.connect(_on_health_changed)
	GameState.xp_changed.connect(_on_xp_changed)
	GameState.level_changed.connect(_on_level_changed)
	GameState.time_changed.connect(_on_time_changed)
	GameState.combo_changed.connect(_on_combo_changed)
	# Initial values
	_on_health_changed(100.0, 100.0)
	_on_xp_changed(0.0, 5.0)
	_on_level_changed(1)
	_on_combo_changed(0, 0)

func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = max(1.0, maximum)
	health_bar.value = max(0.0, current)
	health_label.text = "%d / %d" % [max(0, int(current)), int(maximum)]

func _on_xp_changed(current: float, needed: float) -> void:
	xp_bar.max_value = max(1.0, needed)
	xp_bar.value = current

func _on_level_changed(level: int) -> void:
	level_label.text = "Lv.%d" % level

func _on_time_changed(seconds: float) -> void:
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	timer_label.text = "%02d:%02d" % [m, s]

func _on_combo_changed(count: int, lvl: int) -> void:
	if lvl <= 0:
		combo_label.text = ""
		return
	var prefix: String = "连击"
	match lvl:
		2: prefix = "爆发连击"
		3: prefix = "烈焰连击"
	combo_label.text = "%s ×%d" % [prefix, count]