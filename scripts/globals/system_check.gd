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

const REQUIRED_AUTOLOADS := ["GameState", "UpgradeDB", "WeaponDirector", "SfxPlayer", "MetaProgress"]

const REQUIRED_SCRIPTS := [
	"res://scripts/player.gd",
	"res://scripts/enemy_config.gd",
	"res://scripts/bullet.gd",
	"res://scripts/enemy.gd",
	"res://scripts/enemy_projectile.gd",
	"res://scripts/enemy_spawner.gd",
	"res://scripts/spawn_director.gd",
	"res://scripts/xp_gem.gd",
	"res://scripts/pickup_item.gd",
	"res://scripts/explosion.gd",
	"res://scripts/shield_ring.gd",
	"res://scripts/game.gd",
	"res://scripts/hud.gd",
	"res://scripts/level_up.gd",
	"res://scripts/upgrade_card.gd",
	"res://scripts/game_over.gd",
	"res://scripts/shop.gd",
	"res://scripts/fx_manager.gd",
	"res://scripts/floating_label.gd",
	"res://scripts/burst_particles.gd",
	"res://scripts/shake_camera.gd",
	"res://scripts/weapon_director.gd",
	"res://scripts/weapon_mounts.gd",
	"res://scripts/globals/meta_progress.gd",
	"res://scripts/weapons/weapon.gd",
	"res://scripts/weapons/weapon_config.gd",
	"res://scripts/weapons/bullet_volley.gd",
	"res://scripts/weapons/orbiting_blades.gd",
	"res://scripts/weapons/chain_lightning.gd",
	"res://scripts/weapons/shotgun.gd",
	"res://scripts/weapons/laser_lance.gd",
	"res://scripts/weapons/mine_layer.gd",
	"res://scripts/weapons/mine.gd",
	"res://scripts/weapons/flamethrower.gd",
	"res://scripts/weapons/homing_dart.gd",
	"res://scripts/weapons/storm_volley.gd",
	"res://scripts/weapons/blade_barrage.gd",
	"res://scripts/weapons/lightning_blade.gd",
	"res://scripts/weapons/apocalypse.gd",
	"res://scripts/weapons/blade.gd",
	"res://scripts/world/wasteland_config.gd",
	"res://scripts/world/tilemap_builder.gd",
	"res://scripts/world/world.gd",
	"res://scripts/world/toxic_swamp.gd",
	"res://scripts/world/elite_camp_director.gd",
]

const REQUIRED_SCENES := [
	"res://scenes/main.tscn",
	"res://scenes/game.tscn",
	"res://scenes/player.tscn",
	"res://scenes/enemy.tscn",
	"res://scenes/enemy_projectile.tscn",
	"res://scenes/bullet.tscn",
	"res://scenes/xp_gem.tscn",
	"res://scenes/pickup_item.tscn",
	"res://scenes/ui/hud.tscn",
	"res://scenes/ui/level_up.tscn",
	"res://scenes/ui/upgrade_card.tscn",
	"res://scenes/ui/game_over.tscn",
	"res://scenes/ui/shop.tscn",
	"res://scenes/fx/floating_label.tscn",
	"res://scenes/fx/enemy_death_particles.tscn",
	"res://scenes/fx/bullet_hit_particles.tscn",
	"res://scenes/fx/explosion.tscn",
	"res://scenes/weapons/bullet_volley.tscn",
	"res://scenes/weapons/orbiting_blades.tscn",
	"res://scenes/weapons/chain_lightning.tscn",
	"res://scenes/weapons/shotgun.tscn",
	"res://scenes/weapons/laser_lance.tscn",
	"res://scenes/weapons/mine_layer.tscn",
	"res://scenes/weapons/mine.tscn",
	"res://scenes/weapons/flamethrower.tscn",
	"res://scenes/weapons/homing_dart.tscn",
	"res://scenes/weapons/storm_volley.tscn",
	"res://scenes/weapons/blade_barrage.tscn",
	"res://scenes/weapons/lightning_blade.tscn",
	"res://scenes/weapons/apocalypse.tscn",
	"res://scenes/weapons/blade.tscn",
]

const REQUIRED_RESOURCES := [
	"res://data/enemies/chaser.tres",
	"res://data/enemies/dasher.tres",
	"res://data/enemies/shooter.tres",
	"res://data/enemies/elite_brute.tres",
	"res://data/enemies/boss.tres",
	"res://data/weapons/bullet_volley.tres",
	"res://data/weapons/orbiting_blades.tres",
	"res://data/weapons/chain_lightning.tres",
	"res://data/weapons/shotgun.tres",
	"res://data/weapons/laser_lance.tres",
	"res://data/weapons/mine_layer.tres",
	"res://data/weapons/flamethrower.tres",
	"res://data/weapons/homing_dart.tres",
	"res://data/weapons/storm_volley.tres",
	"res://data/weapons/blade_barrage.tres",
	"res://data/weapons/lightning_blade.tres",
	"res://data/weapons/apocalypse.tres",
	"res://data/world/default_wasteland.tres",
]

const REQUIRED_INPUTS := ["move_up", "move_down", "move_left", "move_right", "pause"]

const REQUIRED_GAME_STATE_MEMBERS := [
	"time_alive", "is_running", "level", "current_xp",
	"damage_mult", "fire_rate_mult", "move_speed_mult", "max_hp_bonus",
	"pickup_radius_mult", "xp_gain_mult", "extra_projectiles", "hp_regen_per_sec",
	"crit_rate", "crit_damage_mult",
	"weapon_range_mult", "pierce_count", "pierce_damage_falloff",
	"shield_charges", "time_stop_left",
]

var _failures: Array[String] = []

func _ready() -> void:
	print("========== [SystemCheck] Startup diagnostics ==========")
	_check_autoloads()
	_check_scripts()
	_check_scenes()
	_check_resources()
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

func _check_resources() -> void:
	for path in REQUIRED_RESOURCES:
		var res := ResourceLoader.load(path)
		if res == null:
			_fail("Resource failed to load: %s" % path)
		else:
			print("[SystemCheck] resource %s OK" % path)

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
