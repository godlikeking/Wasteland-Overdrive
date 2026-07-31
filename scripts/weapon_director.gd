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
		var w: BaseWeapon = _weapons[id] as BaseWeapon
		if w == null or not is_instance_valid(w):
			_weapons.erase(id)
			_weapon_levels.erase(id)

func _reset() -> void:
	_weapons.clear()
	_weapon_levels.clear()
	_world_container = null
	print("[WeaponDirector] reset on player death")

const WEAPON_CATALOG := {
	"bullet_volley": {
		"config": "res://data/weapons/bullet_volley.tres",
		"scene": "res://scenes/weapons/bullet_volley.tscn",
		"projectile": "res://scenes/bullet.tscn",
	},
	"orbiting_blades": {
		"config": "res://data/weapons/orbiting_blades.tres",
		"scene": "res://scenes/weapons/orbiting_blades.tscn",
		"blade": "res://scenes/weapons/blade.tscn",
	},
	"chain_lightning": {
		"config": "res://data/weapons/chain_lightning.tres",
		"scene": "res://scenes/weapons/chain_lightning.tscn",
	},
}

func _resolve_world_container() -> Node2D:
	if _world_container and is_instance_valid(_world_container):
		return _world_container
	var players: Array = get_tree().get_nodes_in_group("player")
	if not players.is_empty() and players[0] is Node2D:
		_world_container = players[0] as Node2D
	return _world_container

func has_weapon(id: String) -> bool:
	return _weapons.has(id)

func add_weapon(config: WeaponConfig, scene: PackedScene) -> void:
	if config == null or scene == null:
		return
	if _weapons.has(config.id):
		level_up_weapon_by_id(config.id)
		return
	# Inject runtime scene refs that come from this game's data folder
	# rather than being baked into the WeaponConfig .tres.
	_inject_runtime_refs(config.id, config)
	var parent: Node2D = _resolve_world_container()
	if parent == null:
		push_error("[WeaponDirector] no player found to parent weapons under")
		return
	var inst: Node = scene.instantiate()
	parent.add_child(inst)
	if inst is BaseWeapon:
		(inst as BaseWeapon).setup(config, _weapon_levels.get(config.id, 1))
		_weapons[config.id] = inst
		_weapon_levels[config.id] = 1
		print("[WeaponDirector] added %s (lv1)" % config.id)

func _inject_runtime_refs(weapon_id: String, config: WeaponConfig) -> void:
	var entry: Dictionary = WEAPON_CATALOG.get(weapon_id, {})
	if entry.is_empty():
		return
	if weapon_id == "bullet_volley" and config.projectile_scene == null:
		var p: PackedScene = ResourceLoader.load(entry.get("projectile", "")) as PackedScene
		if p:
			config.projectile_scene = p

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

func add_weapon_with_extras(config: WeaponConfig, scene: PackedScene, extras: Dictionary) -> void:
	if config == null or scene == null:
		return
	if _weapons.has(config.id):
		level_up_weapon_by_id(config.id)
		return
	_inject_runtime_refs(config.id, config)
	var parent: Node2D = _resolve_world_container()
	if parent == null:
		push_error("[WeaponDirector] no player found to parent weapons under")
		return
	var inst: Node = scene.instantiate()
	# Pass extras to the weapon via a typed extras call (subclasses know
	# their own property types and can assign them safely).
	for k in extras.keys():
		var v: Variant = extras[k]
		if k == "blade_scene" and v is PackedScene:
			inst.setup_blade_scene(v as PackedScene)
	parent.add_child(inst)
	if inst is BaseWeapon:
		(inst as BaseWeapon).setup(config, _weapon_levels.get(config.id, 1))
		_weapons[config.id] = inst
		_weapon_levels[config.id] = 1
		print("[WeaponDirector] added %s (lv1)" % config.id)

func level_up_weapon_by_id(id: String, by: int = 1) -> void:
	if not _weapons.has(id):
		return
	# Stale ref guard: in case the weapon node was freed between add and now
	# (e.g. scene reload while autoload persisted). Drop and bail.
	var stored: BaseWeapon = _weapons[id] as BaseWeapon
	if stored == null or not is_instance_valid(stored):
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
