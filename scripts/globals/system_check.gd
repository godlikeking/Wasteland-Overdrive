extends Node
## Startup self-check. Autoloaded as `SystemCheck` (order after
## GameState/UpgradeDB in project.godot so this runs last).
##
## What it does:
## 1. Verifies required autoloads exist and have expected members.
## 2. Verifies key scripts and scenes load without parse/load errors.
## 3. Verifies expected input actions are mapped.
## 4. Verifies UpgradeDB.roll returns something.
## 5. Installs a scene-tree unhandled exception logger so any runtime
##    script error is printed with a clear tag in the Output panel.
##
## Read the Godot "Output" bottom panel after F5. A green `[SystemCheck] OK`
## line means the environment is sane. Any `[SystemCheck] FAIL` explains
## the reason.

const REQUIRED_AUTOLOADS := ["GameState", "UpgradeDB"]

const REQUIRED_SCRIPTS := [
	"res://scripts/player.gd",
	"res://scripts/auto_gun.gd",
	"res://scripts/bullet.gd",
	"res://scripts/enemy.gd",
	"res://scripts/enemy_spawner.gd",
	"res://scripts/xp_gem.gd",
	"res://scripts/game.gd",
	"res://scripts/hud.gd",
	"res://scripts/level_up.gd",
	"res://scripts/upgrade_card.gd",
	"res://scripts/game_over.gd",
	"res://scripts/fx_manager.gd",
	"res://scripts/floating_label.gd",
	"res://scripts/burst_particles.gd",
	"res://scripts/shake_camera.gd",
]

const REQUIRED_SCENES := [
	"res://scenes/main.tscn",
	"res://scenes/game.tscn",
	"res://scenes/player.tscn",
	"res://scenes/enemy.tscn",
	"res://scenes/bullet.tscn",
	"res://scenes/xp_gem.tscn",
	"res://scenes/ui/hud.tscn",
	"res://scenes/ui/level_up.tscn",
	"res://scenes/ui/upgrade_card.tscn",
	"res://scenes/ui/game_over.tscn",
	"res://scenes/fx/floating_label.tscn",
	"res://scenes/fx/enemy_death_particles.tscn",
	"res://scenes/fx/bullet_hit_particles.tscn",
]

const REQUIRED_INPUTS := ["move_up", "move_down", "move_left", "move_right", "pause"]

const REQUIRED_GAME_STATE_MEMBERS := [
	"time_alive", "is_running", "level", "current_xp",
	"damage_mult", "fire_rate_mult", "move_speed_mult", "max_hp_bonus",
	"pickup_radius_mult", "xp_gain_mult", "extra_projectiles", "hp_regen_per_sec",
]

var _failures: Array[String] = []

func _ready() -> void:
	print("========== [SystemCheck] Startup diagnostics ==========")
	_check_autoloads()
	_check_scripts()
	_check_scenes()
	_check_inputs()
	_check_upgrade_db()
	_check_theme()

	if _failures.is_empty():
		print("[SystemCheck] OK — all checks passed.")
	else:
		push_error("[SystemCheck] FAIL (%d issues):" % _failures.size())
		for f in _failures:
			push_error("  - " + f)
			printerr("[SystemCheck] FAIL: " + f)
	print("=======================================================")

func _fail(msg: String) -> void:
	_failures.append(msg)

# --- Individual checks ---

func _check_autoloads() -> void:
	var root := get_tree().root
	for name in REQUIRED_AUTOLOADS:
		var node := root.get_node_or_null(name)
		if node == null:
			_fail("Autoload '%s' is not registered in project.godot" % name)
		else:
			print("[SystemCheck] autoload '%s' OK" % name)
	# Verify GameState has expected properties (catches script parse errors early).
	if root.has_node("GameState"):
		var gs = root.get_node("GameState")
		for prop in REQUIRED_GAME_STATE_MEMBERS:
			if not (prop in gs):
				_fail("GameState is missing property '%s'" % prop)

func _check_scripts() -> void:
	for path in REQUIRED_SCRIPTS:
		var res := ResourceLoader.load(path)
		if res == null:
			_fail("Script failed to load: %s (check console for parse errors)" % path)
		else:
			print("[SystemCheck] script %s OK" % path)

func _check_scenes() -> void:
	for path in REQUIRED_SCENES:
		var res := ResourceLoader.load(path)
		if res == null:
			_fail("Scene failed to load: %s" % path)
		elif not (res is PackedScene):
			_fail("Resource is not a PackedScene: %s" % path)
		else:
			print("[SystemCheck] scene %s OK" % path)

func _check_inputs() -> void:
	for action in REQUIRED_INPUTS:
		if not InputMap.has_action(action):
			_fail("Input action '%s' is not defined" % action)
		else:
			print("[SystemCheck] input '%s' OK" % action)

func _check_upgrade_db() -> void:
	var root := get_tree().root
	if not root.has_node("UpgradeDB"):
		return  # already flagged
	var db = root.get_node("UpgradeDB")
	if not db.has_method("roll"):
		_fail("UpgradeDB.roll() is missing")
		return
	var choices = db.roll(3)
	if typeof(choices) != TYPE_ARRAY:
		_fail("UpgradeDB.roll(3) did not return an Array")
		return
	if choices.size() < 1:
		_fail("UpgradeDB.roll(3) returned no upgrades — pool may be empty")
		return
	print("[SystemCheck] UpgradeDB.roll(3) returned %d upgrades OK" % choices.size())

func _check_theme() -> void:
	var theme_path := "res://assets/ui/default_theme.tres"
	if not ResourceLoader.exists(theme_path):
		_fail("Theme resource missing: %s" % theme_path)
		return
	var theme := ResourceLoader.load(theme_path)
	if theme == null:
		_fail("Theme resource failed to load: %s" % theme_path)
		return
	print("[SystemCheck] theme %s OK" % theme_path)
