extends CanvasLayer
## In-game HUD showing health bar, XP bar, level, timer, combo, and the item
## status row (shield charges + countdown, time-stop countdown, weapon slots),
## plus the boss furniture: a full-width health bar, a large centre banner for
## the arrival countdown, and the off-screen arrow (see ui/boss_marker.gd).
##
## Everything is signal-driven; `_process` is reserved for values GameState has
## no signal for. Adding a poll here means the value should have gained a signal.

@onready var health_bar: TextureProgressBar = $MarginContainer/VBoxContainer/TopBar/HealthBar
@onready var health_label: Label = $MarginContainer/VBoxContainer/TopBar/HealthBar/Label
@onready var timer_label: Label = $MarginContainer/VBoxContainer/TopBar/TimerLabel
@onready var combo_label: Label = $MarginContainer/VBoxContainer/TopBar/ComboLabel
@onready var shield_label: Label = $MarginContainer/VBoxContainer/StatusBar/ShieldLabel
@onready var time_stop_label: Label = $MarginContainer/VBoxContainer/StatusBar/TimeStopLabel
@onready var weapon_slot_label: Label = $MarginContainer/VBoxContainer/StatusBar/WeaponSlotLabel
@onready var level_label: Label = $MarginContainer/VBoxContainer/BottomBar/LevelLabel
@onready var xp_bar: TextureProgressBar = $MarginContainer/VBoxContainer/BottomBar/XPBar
@onready var boss_bar: VBoxContainer = $MarginContainer/VBoxContainer/BossBar
@onready var boss_name_label: Label = $MarginContainer/VBoxContainer/BossBar/BossNameLabel
@onready var boss_health_bar: TextureProgressBar = $MarginContainer/VBoxContainer/BossBar/BossHealthBar
@onready var boss_banner: Label = $BossBanner

## Last slot count we drew. WeaponDirector has no "arsenal changed" signal (and
## weapons come and go through several paths: level-up cards, pickups, fusion),
## so the count is polled — but only redrawn when it actually moves.
var _shown_slots: int = -1

## Charges and remaining seconds arrive on two separate signals but share one
## label, so both are cached and the label is rebuilt from the pair. Two labels
## would let a stale count linger next to an expired timer.
var _shield_charges: int = 0
var _shield_left: float = 0.0

## Tween driving the banner's fade, killed before each restart so a phase change
## landing mid-fade can't leave two tweens fighting over the same alpha.
var _banner_tw: Tween

func _ready() -> void:
	GameState.player_health_changed.connect(_on_health_changed)
	GameState.xp_changed.connect(_on_xp_changed)
	GameState.level_changed.connect(_on_level_changed)
	GameState.time_changed.connect(_on_time_changed)
	GameState.combo_changed.connect(_on_combo_changed)
	GameState.shield_changed.connect(_on_shield_changed)
	GameState.shield_time_changed.connect(_on_shield_time_changed)
	GameState.time_stop_changed.connect(_on_time_stop_changed)
	GameState.boss_spawned.connect(_on_boss_spawned)
	GameState.boss_state_changed.connect(_on_boss_state_changed)
	GameState.boss_defeated.connect(_on_boss_defeated)
	GameState.boss_incoming.connect(_on_boss_incoming)
	# Initial values
	_on_health_changed(100.0, 100.0)
	_on_xp_changed(0.0, 5.0)
	_on_level_changed(1)
	_on_combo_changed(0, 0)
	_shield_charges = GameState.shield_charges
	_shield_left = GameState.shield_left
	_refresh_shield_label()
	_on_time_stop_changed(GameState.time_stop_left)
	# The bar only belongs on screen while a boss is alive, and the banner has to
	# start invisible: the scene sets both, but a reloaded HUD would otherwise
	# inherit whatever the last run left behind.
	boss_bar.visible = false
	boss_banner.text = ""
	boss_banner.modulate.a = 0.0

func _process(_delta: float) -> void:
	var slots: int = WeaponDirector.slots_used()
	if slots == _shown_slots:
		return
	_shown_slots = slots
	weapon_slot_label.text = "武器 %d／%d" % [slots, WeaponDirector.MAX_WEAPONS]

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

func _on_shield_changed(charges: int) -> void:
	_shield_charges = charges
	_refresh_shield_label()

func _on_shield_time_changed(remaining: float) -> void:
	_shield_left = remaining
	_refresh_shield_label()

## Shield readout: count plus the seconds left, because the shield now expires
## and a bare "护盾 ×2" would say nothing about whether it's about to vanish.
func _refresh_shield_label() -> void:
	if _shield_charges <= 0:
		shield_label.text = ""
		return
	if _shield_left <= 0.0:
		# No timer known (e.g. granted before the time signal landed): show the
		# count alone rather than a misleading "0.0s".
		shield_label.text = "护盾 ×%d" % _shield_charges
		return
	shield_label.text = "护盾 ×%d (%.1fs)" % [_shield_charges, _shield_left]

func _on_time_stop_changed(remaining: float) -> void:
	# Blank rather than "0.0s" so the row collapses when nothing is active,
	# instead of leaving a dead readout on screen for the whole run.
	time_stop_label.text = "" if remaining <= 0.0 else "时停 %.1fs" % remaining

# --- Boss ---------------------------------------------------------------

func _on_boss_spawned(_boss: Node2D) -> void:
	boss_bar.visible = true
	boss_health_bar.value = 1.0
	boss_name_label.text = "废土巨兽  阶段 1"
	_flash_banner("废土巨兽降临！", Color(1, 0.25, 0.2), 2.0)

func _on_boss_state_changed(hp_frac: float, phase: int) -> void:
	# Damage arrives before the spawn signal in no scenario, but a boss surviving
	# a scene reload would leave the bar hidden — cheap to make it self-healing.
	boss_bar.visible = true
	boss_health_bar.value = clampf(hp_frac, 0.0, 1.0)
	boss_name_label.text = "废土巨兽  阶段 %d" % phase

func _on_boss_defeated() -> void:
	boss_bar.visible = false
	_flash_banner("巨兽已倒下", Color(1, 0.85, 0.3), 1.6)

## Countdown banner in the seconds before the boss lands. Fires once per whole
## second (the director throttles it), so each tick replaces the previous text.
func _on_boss_incoming(seconds: float) -> void:
	if seconds <= 0.0:
		return   # 0 means "it is here"; the spawn banner covers that.
	_flash_banner("BOSS 即将降临  %d" % int(ceilf(seconds)), Color(1, 0.6, 0.15), 0.9)

## Fade the big centre banner in and back out over `hold` seconds.
##
## Only `modulate.a` is animated. A scale punch would need a pivot, and the
## banner is anchored to the whole viewport, so its pivot — and therefore the
## punch — would change with the window size.
func _flash_banner(text: String, color: Color, hold: float) -> void:
	if _banner_tw and _banner_tw.is_valid():
		_banner_tw.kill()
	boss_banner.text = text
	boss_banner.add_theme_color_override("font_color", color)
	boss_banner.modulate.a = 0.0
	_banner_tw = create_tween()
	_banner_tw.tween_property(boss_banner, "modulate:a", 1.0, 0.18)
	_banner_tw.tween_interval(maxf(0.1, hold - 0.5))
	_banner_tw.tween_property(boss_banner, "modulate:a", 0.0, 0.32)
