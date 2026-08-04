extends Node
## Autoloaded. Owns the set of active weapons. When `add_weapon` is called,
## the weapon scene is instanced and added under the player (so it follows
## movement). This lets all weapons share the same world-space origin.
##
## NOTE: this autoload persists across scene reloads (death -> restart
## reuses the autoload). Its state must be cleared when the player /
## weapons are torn down, otherwise stale references to freed weapons
## crash on the next add_weapon_by_id.

var _weapons: Dictionary = {}      # config_id -> BaseWeapon
var _weapon_levels: Dictionary = {}  # config_id -> int
var _world_container: Node2D = null

## Hard cap on simultaneously equipped weapons. The catalog holds exactly 12
## reachable ids (8 base + 4 fusions), so a player who never fuses can fill
## every slot, and fusing frees slots as it consumes its ingredients.
const MAX_WEAPONS: int = 12

func _ready() -> void:
	# Reset state when the tree becomes empty (after a death and before
	# the next scene finishes loading). This drops freed refs.
	get_tree().node_removed.connect(_on_node_removed)
	get_tree().tree_changed.connect(_on_tree_changed)

func _on_node_removed(node: Node) -> void:
	# Player got freed on death/restart. Drop our weapon refs.
	if node.is_in_group("player"):
		_reset()

func _on_tree_changed() -> void:
	# Belt + suspenders: prune any entries whose target was freed.
	for id in _weapons.keys():
		if _live_weapon(id) == null:
			_weapons.erase(id)
			_weapon_levels.erase(id)

## Fetch a still-alive weapon, or null. Validity has to be checked on the raw
## Variant: `as BaseWeapon` on an already-freed object throws "Trying to cast a
## freed object" right there, before any is_instance_valid() guard downstream
## ever gets a look in.
func _live_weapon(id: String) -> BaseWeapon:
	if not _weapons.has(id):
		return null
	var raw: Variant = _weapons[id]
	if not is_instance_valid(raw):
		return null
	return raw as BaseWeapon

func _reset() -> void:
	_weapons.clear()
	_weapon_levels.clear()
	_world_container = null
	print("[WeaponDirector] reset on player death")

const WEAPON_CATALOG := {
	"bullet_volley": {
		"name": "弹雨",
		"config": "res://data/weapons/bullet_volley.tres",
		"scene": "res://scenes/weapons/bullet_volley.tscn",
		"projectile": "res://scenes/bullet.tscn",
	},
	"orbiting_blades": {
		"name": "环绕刀刃",
		"config": "res://data/weapons/orbiting_blades.tres",
		"scene": "res://scenes/weapons/orbiting_blades.tscn",
		"blade": "res://scenes/weapons/blade.tscn",
	},
	"chain_lightning": {
		"name": "连锁闪电",
		"config": "res://data/weapons/chain_lightning.tres",
		"scene": "res://scenes/weapons/chain_lightning.tscn",
	},
	"shotgun": {
		"name": "散弹枪",
		"config": "res://data/weapons/shotgun.tres",
		"scene": "res://scenes/weapons/shotgun.tscn",
		"projectile": "res://scenes/bullet.tscn",
	},
	"laser_lance": {
		"name": "磁轨激光",
		"config": "res://data/weapons/laser_lance.tres",
		"scene": "res://scenes/weapons/laser_lance.tscn",
	},
	"mine_layer": {
		"name": "地雷布设器",
		"config": "res://data/weapons/mine_layer.tres",
		"scene": "res://scenes/weapons/mine_layer.tscn",
		"mine": "res://scenes/weapons/mine.tscn",
	},
	"flamethrower": {
		"name": "火焰喷射器",
		"config": "res://data/weapons/flamethrower.tres",
		"scene": "res://scenes/weapons/flamethrower.tscn",
	},
	"homing_dart": {
		"name": "追踪飞镖",
		"config": "res://data/weapons/homing_dart.tres",
		"scene": "res://scenes/weapons/homing_dart.tscn",
		"projectile": "res://scenes/bullet.tscn",
	},
}

# --- Fusion (Iter7) ---
# When 3 base weapons are all at MAX_FUSE_LEVEL, the player can choose
# a fusion recipe. Pick 2-of-3 to get a "combo" super weapon; pick all 3
# to get the ultimate "apocalypse" super weapon.
const BASE_WEAPONS: Array[String] = ["bullet_volley", "chain_lightning", "orbiting_blades"]
const MAX_FUSE_LEVEL: int = 5
signal fused(new_id: String, recipe: Array)

const FUSION_RECIPES := {
	"storm_volley":   {"needs": ["bullet_volley", "chain_lightning"],
					   "name": "雷暴弹雨", "config": "res://data/weapons/storm_volley.tres"},
	"blade_barrage":  {"needs": ["bullet_volley", "orbiting_blades"],
					   "name": "刀刃弹幕", "config": "res://data/weapons/blade_barrage.tres"},
	"lightning_blade":{"needs": ["chain_lightning", "orbiting_blades"],
					   "name": "闪电刀阵", "config": "res://data/weapons/lightning_blade.tres"},
	"apocalypse":     {"needs": ["bullet_volley", "chain_lightning", "orbiting_blades"],
					   "name": "启示录",   "config": "res://data/weapons/apocalypse.tres"},
}

## Returns Array of {id, name, recipe, level} for every recipe the player
## can fuse right now, given current weapons and levels. Empty if not.
func fuse_candidates() -> Array:
	var lvls: Dictionary = {}
	for id in BASE_WEAPONS:
		if not _weapons.has(id):
			return []
		lvls[id] = int(_weapon_levels.get(id, 0))
		if lvls[id] < MAX_FUSE_LEVEL:
			return []
	# All 3 base weapons at MAX_FUSE_LEVEL — eligible.
	var owned: Array[String] = []
	for id in BASE_WEAPONS:
		owned.append(id)
	var out: Array = []
	for fid in FUSION_RECIPES.keys():
		if _weapons.has(fid):
			continue  # already fused
		var needs: Array = (FUSION_RECIPES[fid] as Dictionary)["needs"]
		var ok: bool = true
		for need in needs:
			if not owned.has(need):
				ok = false
				break
		if ok and ResourceLoader.exists("res://scenes/weapons/%s.tscn" % fid):
			out.append({
				"id": fid,
				"name": (FUSION_RECIPES[fid] as Dictionary)["name"],
				"recipe": needs,
			})
	return out

## Perform the fusion. Unlocks the super weapon and frees the 2/3 base
## weapons listed in its recipe. Returns the new weapon id, or "" on
## failure.
func fuse(recipe_id: String) -> String:
	var entry: Dictionary = FUSION_RECIPES.get(recipe_id, {})
	if entry.is_empty():
		push_error("[WeaponDirector] unknown recipe %s" % recipe_id)
		return ""
	# Eligibility: base weapons still at MAX_FUSE_LEVEL.
	for need in (entry["needs"] as Array):
		if not _weapons.has(need):
			return ""
		if int(_weapon_levels.get(need, 0)) < MAX_FUSE_LEVEL:
			return ""
	# Already fused?
	if _weapons.has(recipe_id):
		return recipe_id
	# Resolve config + scene BEFORE destroying anything. If an asset is
	# missing we must bail with the player's arsenal still intact.
	# Scene path follows the convention res://scenes/weapons/<id>.tscn
	var cfg_res: Resource = ResourceLoader.load(entry["config"])
	if not (cfg_res is WeaponConfig):
		push_error("[WeaponDirector] fusion %s missing config %s" % [recipe_id, entry["config"]])
		return ""
	var cfg: WeaponConfig = cfg_res as WeaponConfig
	var scene_res: PackedScene = _scene_for_fusion(recipe_id)
	if scene_res == null:
		push_error("[WeaponDirector] fusion %s missing scene" % recipe_id)
		return ""
	# Now it is safe: remove the 2/3 base weapons from the player.
	for need in (entry["needs"] as Array):
		var w: BaseWeapon = _live_weapon(need)
		if w:
			w.queue_free()
		_weapons.erase(need)
		_weapon_levels.erase(need)
	# Fusion weapons also need runtime refs (projectile_scene / blade_scene)
	# injected so subclasses can find them. Use the add_weapon_with_extras
	# path so the blade scene is wired via setup_blade_scene.
	var blade_ps: PackedScene = ResourceLoader.load("res://scenes/weapons/blade.tscn") as PackedScene
	if blade_ps:
		add_weapon_with_extras(cfg, scene_res, {"blade_scene": blade_ps})
	else:
		add_weapon(cfg, scene_res)
	fused.emit(recipe_id, (entry["needs"] as Array))
	print("[WeaponDirector] FUSED -> %s" % recipe_id)
	return recipe_id

func _scene_for_fusion(recipe_id: String) -> PackedScene:
	var path: String = "res://scenes/weapons/%s.tscn" % recipe_id
	var res: PackedScene = ResourceLoader.load(path) as PackedScene
	return res

## Test helper / debug: force all 3 base weapons to MAX_FUSE_LEVEL.
func _debug_max_base_weapons() -> void:
	for id in BASE_WEAPONS:
		if _weapons.has(id):
			_weapon_levels[id] = MAX_FUSE_LEVEL
			var w: BaseWeapon = _live_weapon(id)
			if w:
				w.level = MAX_FUSE_LEVEL
				w._recompute_stats()

func _resolve_world_container() -> Node2D:
	if _world_container and is_instance_valid(_world_container):
		return _world_container
	var players: Array = get_tree().get_nodes_in_group("player")
	if not players.is_empty() and players[0] is Node2D:
		_world_container = players[0] as Node2D
	return _world_container

func has_weapon(id: String) -> bool:
	return _weapons.has(id)

## Weapons currently equipped. Used by the HUD and the full-slot guards.
func slots_used() -> int:
	return _weapons.size()

func is_full() -> bool:
	return _weapons.size() >= MAX_WEAPONS

## Current level of an owned weapon, or 0 if it isn't equipped. Lets callers
## observe a level-up without reaching into `_weapon_levels`.
func weapon_level_of(id: String) -> int:
	if not _weapons.has(id):
		return 0
	return int(_weapon_levels.get(id, 1))

## Human-readable name for a weapon id, for HUD text and pickup labels. Falls
## back to the id so a missing entry is visible rather than blank.
func display_name_of(id: String) -> String:
	if FUSION_RECIPES.has(id):
		return String((FUSION_RECIPES[id] as Dictionary)["name"])
	var entry: Dictionary = WEAPON_CATALOG.get(id, {})
	if entry.has("name"):
		return String(entry["name"])
	return id

## Every catalog id the player does not own yet, in catalog order.
func missing_weapon_ids() -> Array[String]:
	var out: Array[String] = []
	for id in WEAPON_CATALOG.keys():
		if not _weapons.has(id):
			out.append(String(id))
	return out

## Ids the player currently has equipped, fusions included. WEAPON_CATALOG only
## covers the base weapons, so callers that must cover the whole arsenal (HUD
## listings, level-up bookkeeping) need this instead.
func owned_weapon_ids() -> Array[String]:
	var out: Array[String] = []
	for id in _weapons.keys():
		out.append(String(id))
	return out

## Used by the weapon pickup item. Grants one random unowned weapon and returns
## its id. Returns "" when nothing could be granted (all slots full, or the
## player already owns every catalog weapon) so the caller can say so instead of
## silently swallowing the drop.
func grant_random_weapon() -> String:
	if is_full():
		return ""
	var pool: Array[String] = missing_weapon_ids()
	if pool.is_empty():
		return ""
	var id: String = pool[randi() % pool.size()]
	add_weapon_by_id(id)
	# add_weapon_by_id can still bail on a missing asset, so confirm.
	if not _weapons.has(id):
		return ""
	return id

## Fallback for the weapon pickup when every slot is taken: level up a random
## weapon the player already owns. Returns its id, or "" if they own nothing.
func level_up_random_weapon() -> String:
	var ids: Array = _weapons.keys()
	if ids.is_empty():
		return ""
	var id: String = String(ids[randi() % ids.size()])
	level_up_weapon_by_id(id)
	return id

func add_weapon(config: WeaponConfig, scene: PackedScene) -> bool:
	if config == null or scene == null:
		return false
	if _weapons.has(config.id):
		level_up_weapon_by_id(config.id)
		return true
	# Slot cap. Checked after the "already owned" branch so a level-up is never
	# blocked by a full arsenal — only brand-new weapons are.
	if is_full():
		print("[WeaponDirector] slots full (%d), rejected %s" % [MAX_WEAPONS, config.id])
		return false
	# Inject runtime scene refs that come from this game's data folder
	# rather than being baked into the WeaponConfig .tres.
	_inject_runtime_refs(config.id, config)
	var parent: Node2D = _resolve_world_container()
	if parent == null:
		push_error("[WeaponDirector] no player found to parent weapons under")
		return false
	var inst: Node = scene.instantiate()
	parent.add_child(inst)
	if inst is BaseWeapon:
		(inst as BaseWeapon).setup(config, _weapon_levels.get(config.id, 1))
		_weapons[config.id] = inst
		_weapon_levels[config.id] = 1
		print("[WeaponDirector] added %s (lv1)" % config.id)
		return true
	return false

## Weapons that fire the shared bullet.tscn projectile. Their .tres leaves
## projectile_scene null so the data folder stays free of scene refs.
const BULLET_USERS: Array[String] = [
	"bullet_volley", "storm_volley", "blade_barrage", "apocalypse",
	"shotgun", "homing_dart",
]

## Weapons that place mine.tscn. Same reasoning as BULLET_USERS: the scene ref
## is resolved here so mine_layer.tres stays pure data.
const MINE_USERS: Array[String] = ["mine_layer"]

func _inject_runtime_refs(weapon_id: String, config: WeaponConfig) -> void:
	if weapon_id in BULLET_USERS and config.projectile_scene == null:
		var p: PackedScene = ResourceLoader.load("res://scenes/bullet.tscn") as PackedScene
		if p:
			config.projectile_scene = p
	if weapon_id in MINE_USERS and config.mine_scene == null:
		var m: PackedScene = ResourceLoader.load("res://scenes/weapons/mine.tscn") as PackedScene
		if m:
			config.mine_scene = m

func add_weapon_by_id(id: String) -> void:
	if has_weapon(id):
		level_up_weapon_by_id(id)
		return
	var entry: Dictionary = WEAPON_CATALOG.get(id, {})
	if entry.is_empty():
		push_error("[WeaponDirector] unknown weapon id: %s" % id)
		return
	var cfg: Resource = ResourceLoader.load(entry.get("config", ""))
	var scene: PackedScene = ResourceLoader.load(entry.get("scene", "")) as PackedScene
	if cfg is WeaponConfig and scene:
		# OrbitingBladesWeapon also needs the blade scene.
		if id == "orbiting_blades":
			var blade_scene: PackedScene = ResourceLoader.load(entry.get("blade", "")) as PackedScene
			if blade_scene:
				# Stash the blade scene on the parent-of-scene via a property on
				# the OrbitingBladesWeapon. We set it post-instantiation below.
				pass
			add_weapon_with_extras(cfg, scene, {"blade_scene": blade_scene})
		else:
			add_weapon(cfg, scene)
	else:
		push_error("[WeaponDirector] failed to load config/scene for %s" % id)

func add_weapon_with_extras(config: WeaponConfig, scene: PackedScene, extras: Dictionary) -> bool:
	if config == null or scene == null:
		return false
	if _weapons.has(config.id):
		level_up_weapon_by_id(config.id)
		return true
	if is_full():
		print("[WeaponDirector] slots full (%d), rejected %s" % [MAX_WEAPONS, config.id])
		return false
	_inject_runtime_refs(config.id, config)
	var parent: Node2D = _resolve_world_container()
	if parent == null:
		push_error("[WeaponDirector] no player found to parent weapons under")
		return false
	var inst: Node = scene.instantiate()
	# Pass extras to the weapon via a typed extras call (subclasses know
	# their own property types and can assign them safely).
	for k in extras.keys():
		var v: Variant = extras[k]
		if k == "blade_scene" and v is PackedScene and inst.has_method("setup_blade_scene"):
			inst.setup_blade_scene(v as PackedScene)
	parent.add_child(inst)
	if inst is BaseWeapon:
		(inst as BaseWeapon).setup(config, _weapon_levels.get(config.id, 1))
		_weapons[config.id] = inst
		_weapon_levels[config.id] = 1
		print("[WeaponDirector] added %s (lv1)" % config.id)
		return true
	return false

func level_up_weapon_by_id(id: String, by: int = 1) -> void:
	if not _weapons.has(id):
		return
	# Stale ref guard: in case the weapon node was freed between add and now
	# (e.g. scene reload while autoload persisted). Drop and bail.
	var stored: BaseWeapon = _live_weapon(id)
	if stored == null:
		_weapons.erase(id)
		_weapon_levels.erase(id)
		return
	var new_level: int = int(_weapon_levels.get(id, 1)) + by
	_weapon_levels[id] = new_level
	var w: BaseWeapon = stored
	if w and w.config:
		w.level = new_level
		w._recompute_stats()
		print("[WeaponDirector] %s -> lv%d" % [id, new_level])

func all_unlocked_ids() -> Array:
	return _weapons.keys()
