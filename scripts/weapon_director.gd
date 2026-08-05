extends Node
## Autoloaded. Owns the set of active weapons. When `add_weapon` is called,
## the weapon scene is instanced and added under the player (so it follows
## movement). This lets all weapons share the same world-space origin.
##
## Weapon storage is an ordered list of instances, NOT id-keyed. The player may
## hold several copies of the same weapon, and every 3 copies at the same level
## auto-merge into one at level+1 (see `_try_merge_all`). Each BaseWeapon keeps
## its own `level`, so there is no separate level bookkeeping here.
##
## NOTE: this autoload persists across scene reloads (death -> restart
## reuses the autoload). Its state must be cleared when the player /
## weapons are torn down, otherwise stale references to freed weapons
## crash on the next add_weapon_by_id.

var _weapons: Array[BaseWeapon] = []   # ordered, duplicates allowed
var _world_container: Node2D = null
var _merging: bool = false             # guards against tree_changed re-entry

## Hard cap on simultaneously equipped weapons. Duplicates can fill it, but
## every merge frees 2 slots, so the cap is reachable and pressable.
const MAX_WEAPONS: int = 12

## 3 identical weapons at the same level fuse into one at level+1.
const MERGE_COUNT: int = 3

signal weapon_merged(id: String, new_level: int)

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
	_prune()

## Drop refs to weapons that were freed (or queued for deletion but not yet
## collected). Validity has to be checked on the raw Variant: reading `_weapons`
## with a `for w in _weapons` always yields a BaseWeapon, but an already-freed
## object casts to null and then `is_instance_valid` on it is what we guard.
func _prune() -> void:
	var kept: Array[BaseWeapon] = []
	for w in _weapons:
		if is_instance_valid(w) and not w.is_queued_for_deletion():
			kept.append(w)
	if kept.size() != _weapons.size():
		_weapons = kept

func _reset() -> void:
	_weapons.clear()
	_world_container = null
	print("[WeaponDirector] reset on player death")

## Every weapon a drop can grant. `weight` is the drop-table weight (see
## `_roll_weighted_id`): the stronger the weapon, the rarer it is.
##
## The three FUSION ingredients (bullet_volley / chain_lightning /
## orbiting_blades) are deliberately among the COMMONEST entries, which looks
## backwards until you count: fusion needs each of them at MAX_FUSE_LEVEL, and
## every level costs MERGE_COUNT copies, so Lv3 is 9 drops of that exact id.
## Making an ingredient rare does not make fusion feel earned, it makes fusion
## unreachable. Rarity is spent on the weapons nothing else depends on.
const WEAPON_CATALOG := {
	"bullet_volley": {
		"name": "弹雨",
		"weight": 20,
		"config": "res://data/weapons/bullet_volley.tres",
		"scene": "res://scenes/weapons/bullet_volley.tscn",
		"projectile": "res://scenes/bullet.tscn",
	},
	"orbiting_blades": {
		"name": "环绕刀刃",
		"weight": 20,
		"config": "res://data/weapons/orbiting_blades.tres",
		"scene": "res://scenes/weapons/orbiting_blades.tscn",
		"blade": "res://scenes/weapons/blade.tscn",
	},
	"chain_lightning": {
		"name": "连锁闪电",
		"weight": 20,
		"config": "res://data/weapons/chain_lightning.tres",
		"scene": "res://scenes/weapons/chain_lightning.tscn",
	},
	"shotgun": {
		"name": "散弹枪",
		"weight": 20,
		"config": "res://data/weapons/shotgun.tres",
		"scene": "res://scenes/weapons/shotgun.tscn",
		"projectile": "res://scenes/bullet.tscn",
	},
	"homing_dart": {
		"name": "追踪飞镖",
		"weight": 12,
		"config": "res://data/weapons/homing_dart.tres",
		"scene": "res://scenes/weapons/homing_dart.tscn",
		"projectile": "res://scenes/bullet.tscn",
	},
	"flamethrower": {
		"name": "火焰喷射器",
		"weight": 7,
		"config": "res://data/weapons/flamethrower.tres",
		"scene": "res://scenes/weapons/flamethrower.tscn",
	},
	"laser_lance": {
		"name": "磁轨激光",
		"weight": 7,
		"config": "res://data/weapons/laser_lance.tres",
		"scene": "res://scenes/weapons/laser_lance.tscn",
	},
	"mine_layer": {
		"name": "地雷布设器",
		"weight": 4,
		"config": "res://data/weapons/mine_layer.tres",
		"scene": "res://scenes/weapons/mine_layer.tscn",
		"mine": "res://scenes/weapons/mine.tscn",
	},
}

# --- Fusion (Iter7) ---
# When 3 base weapons each have at least one copy at MAX_FUSE_LEVEL, the player
# can choose a fusion recipe. Pick 2-of-3 to get a "combo" super weapon; pick
# all 3 to get the ultimate "apocalypse" super weapon. Fusing consumes ONE
# qualifying copy of each ingredient; spare copies the player owns stay.
const BASE_WEAPONS: Array[String] = ["bullet_volley", "chain_lightning", "orbiting_blades"]
const MAX_FUSE_LEVEL: int = 3
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

## Returns Array of {id, name, recipe} for every recipe the player can fuse
## right now, given current weapons and levels. Empty if not.
func fuse_candidates() -> Array:
	for id in BASE_WEAPONS:
		if not _has_qualified(id, MAX_FUSE_LEVEL):
			return []
	var out: Array = []
	for fid in FUSION_RECIPES.keys():
		if _has_any(fid):
			continue  # already fused
		var needs: Array = (FUSION_RECIPES[fid] as Dictionary)["needs"]
		var ok: bool = true
		for need in needs:
			if not _has_qualified(need, MAX_FUSE_LEVEL):
				ok = false
				break
		if ok and ResourceLoader.exists("res://scenes/weapons/%s.tscn" % fid):
			out.append({
				"id": fid,
				"name": (FUSION_RECIPES[fid] as Dictionary)["name"],
				"recipe": needs,
			})
	return out

## Perform the fusion. Consumes one level-eligible copy of each ingredient and
## grants the super weapon. Returns the new weapon id, or "" on failure.
func fuse(recipe_id: String) -> String:
	var entry: Dictionary = FUSION_RECIPES.get(recipe_id, {})
	if entry.is_empty():
		push_error("[WeaponDirector] unknown recipe %s" % recipe_id)
		return ""
	# Eligibility: each ingredient needs at least one copy at MAX_FUSE_LEVEL.
	for need in (entry["needs"] as Array):
		if not _has_qualified(need, MAX_FUSE_LEVEL):
			return ""
	# Already fused? Fusing a recipe that already exists would silently stack
	# a second super weapon, so bail. (Still call it a success so the caller's
	# "did it fuse" check reads true.)
	if _has_any(recipe_id):
		return recipe_id
	# Resolve config + scene BEFORE destroying anything. If an asset is
	# missing we must bail with the player's arsenal still intact.
	var cfg_res: Resource = ResourceLoader.load(entry["config"])
	if not (cfg_res is WeaponConfig):
		push_error("[WeaponDirector] fusion %s missing config %s" % [recipe_id, entry["config"]])
		return ""
	var cfg: WeaponConfig = cfg_res as WeaponConfig
	var scene_res: PackedScene = _scene_for_fusion(recipe_id)
	if scene_res == null:
		push_error("[WeaponDirector] fusion %s missing scene" % recipe_id)
		return ""
	# Consume one qualifying copy of each ingredient (the highest level one).
	for need in (entry["needs"] as Array):
		_consume_one(need, MAX_FUSE_LEVEL)
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
	for w in _weapons:
		if w and w.config and w.config.id in BASE_WEAPONS:
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
	return count_of(id) > 0

## How many copies of `id` the player currently holds.
func count_of(id: String) -> int:
	var n: int = 0
	for w in _weapons:
		if w and w.config and w.config.id == id:
			n += 1
	return n

## Weapons currently equipped. Each copy counts as one slot.
func slots_used() -> int:
	return _weapons.size()

func is_full() -> bool:
	return _weapons.size() >= MAX_WEAPONS

## Highest level held across all copies of `id`, or 0 if the player owns none.
func weapon_level_of(id: String) -> int:
	var best: int = 0
	for w in _weapons:
		if w and w.config and w.config.id == id and w.level > best:
			best = w.level
	return best

## Levels of every copy of `id`, for callers that care about the distribution.
func levels_of(id: String) -> Array[int]:
	var out: Array[int] = []
	for w in _weapons:
		if w and w.config and w.config.id == id:
			out.append(w.level)
	return out

## The arsenal collapsed into one row per (id, level) pair, in mount order.
## Each entry is `{id, name, level, count, max_level}`.
##
## The (id, level) split — rather than a plain per-id count — is what makes the
## pause panel's merge progress meaningful: a merge consumes MERGE_COUNT copies
## at the *same* level, so holding a Lv1 and a Lv2 is not "one away", it is two
## separate rows that are each two away.
func inventory_groups() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# id|level -> index into `out`, so rows stay in first-mounted order.
	var seen: Dictionary = {}
	for w in _weapons:
		if w == null or w.config == null:
			continue
		var key: String = "%s|%d" % [w.config.id, w.level]
		if seen.has(key):
			var at: int = int(seen[key])
			out[at]["count"] = int(out[at]["count"]) + 1
			continue
		seen[key] = out.size()
		out.append({
			"id": w.config.id,
			"name": display_name_of(w.config.id),
			"level": w.level,
			"count": 1,
			"max_level": w.config.max_level,
		})
	return out

## Human-readable name for a weapon id, for HUD text and pickup labels. Falls
## back to the id so a missing entry is visible rather than blank.
func display_name_of(id: String) -> String:
	if FUSION_RECIPES.has(id):
		return String((FUSION_RECIPES[id] as Dictionary)["name"])
	var entry: Dictionary = WEAPON_CATALOG.get(id, {})
	if entry.has("name"):
		return String(entry["name"])
	return id

## Catalog ids the player does not own any copy of, in catalog order.
func missing_weapon_ids() -> Array[String]:
	var out: Array[String] = []
	for id in WEAPON_CATALOG.keys():
		if count_of(String(id)) == 0:
			out.append(String(id))
	return out

## Ids the player currently has equipped, fusions included. Duplicates are
## listed once per copy held. WEAPON_CATALOG only covers the base weapons, so
## callers that must cover the whole arsenal (HUD listings, bookkeeping) need
## this instead of the catalog.
func owned_weapon_ids() -> Array[String]:
	var out: Array[String] = []
	for w in _weapons:
		if w and w.config:
			out.append(w.config.id)
	return out

## Used by the weapon pickup item. Grants a weapon and returns its id. Copies
## are allowed, so this draws from all 8 base ids rather than only unowned ones —
## that is what lets duplicates accumulate toward a merge.
##
## The draw is weighted by rarity (see WEAPON_CATALOG), so a strong weapon is a
## rarer sight than a common one.
##
## When the arsenal is full, only ids that can immediately complete a merge are
## granted (that hand frees 2 slots). Rarity still applies within that filtered
## pool. Returns "" when nothing could be granted so the caller can say
## "武器槽已满" instead of silently swallowing the drop.
func grant_random_weapon() -> String:
	var pool: Array[String] = []
	if is_full():
		# Full: only a merge-completing id is worth accepting.
		for id in WEAPON_CATALOG.keys():
			if _can_complete_merge(String(id)):
				pool.append(String(id))
	else:
		for id in WEAPON_CATALOG.keys():
			pool.append(String(id))
	var id: String = _roll_weighted_id(pool)
	if id == "":
		return ""
	add_weapon_by_id(id)
	# add_weapon_by_id can still bail on a missing asset, so confirm.
	if count_of(id) == 0:
		return ""
	return id

## Weighted draw from `pool` using each id's WEAPON_CATALOG weight. Returns ""
## for an empty pool.
##
## Deliberately free of side effects: `grant_random_weapon` actually mounts a
## weapon and can trigger a merge, so it is useless for verifying the
## distribution. The self-test samples this instead, tens of thousands of times.
func _roll_weighted_id(pool: Array[String]) -> String:
	if pool.is_empty():
		return ""
	var total: int = 0
	for id in pool:
		total += weight_of(id)
	if total <= 0:
		# Every candidate weighted 0 (or a bad table). Fall back to uniform so a
		# drop is never silently swallowed by a data error.
		return pool[randi() % pool.size()]
	var roll: int = randi() % total
	for id in pool:
		roll -= weight_of(id)
		if roll < 0:
			return id
	return pool[pool.size() - 1]

## Drop-table weight for `id`. Unknown ids weigh 0 so a typo cannot quietly
## become the commonest drop in the game.
func weight_of(id: String) -> int:
	var entry: Dictionary = WEAPON_CATALOG.get(id, {})
	return int(entry.get("weight", 0))

## Level a freshly dropped copy of `id` starts at, read from its WeaponConfig.
## Rare weapons drop pre-levelled, so a single copy is already worth its slot.
## ResourceLoader caches the .tres, so this stays cheap despite the load.
##
## Ids outside WEAPON_CATALOG (fusion results, which are crafted rather than
## dropped) have no drop level and answer 1. The empty-path guard matters:
## `_can_complete_merge` runs for every add, fusion weapons included, and
## ResourceLoader.load("") is a hard error, not a null.
func drop_level_of(id: String) -> int:
	var entry: Dictionary = WEAPON_CATALOG.get(id, {})
	var path: String = String(entry.get("config", ""))
	if path == "":
		return 1
	var cfg: Resource = ResourceLoader.load(path)
	if cfg is WeaponConfig:
		return maxi(1, (cfg as WeaponConfig).drop_level)
	return 1

func add_weapon(config: WeaponConfig, scene: PackedScene) -> bool:
	if config == null or scene == null:
		return false
	# Slot cap. A full arsenal rejects a brand-new weapon, but allows a drop
	# that immediately completes a 3-way merge — that hand frees 2 slots, so the
	# net effect is -2, never a net gain.
	if is_full() and not _can_complete_merge(config.id):
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
		var lv: int = maxi(1, config.drop_level)
		(inst as BaseWeapon).setup(config, lv)
		_weapons.append(inst as BaseWeapon)
		print("[WeaponDirector] added %s (lv%d)" % [config.id, lv])
		_try_merge_all()
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
	var entry: Dictionary = WEAPON_CATALOG.get(id, {})
	if entry.is_empty():
		push_error("[WeaponDirector] unknown weapon id: %s" % id)
		return
	var cfg: Resource = ResourceLoader.load(entry.get("config", ""))
	var scene: PackedScene = ResourceLoader.load(entry.get("scene", "")) as PackedScene
	if cfg is WeaponConfig and scene:
		if id == "orbiting_blades":
			var blade_scene: PackedScene = ResourceLoader.load(entry.get("blade", "")) as PackedScene
			add_weapon_with_extras(cfg, scene, {"blade_scene": blade_scene})
		else:
			add_weapon(cfg, scene)
	else:
		push_error("[WeaponDirector] failed to load config/scene for %s" % id)

func add_weapon_with_extras(config: WeaponConfig, scene: PackedScene, extras: Dictionary) -> bool:
	if config == null or scene == null:
		return false
	if is_full() and not _can_complete_merge(config.id):
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
		var lv: int = maxi(1, config.drop_level)
		(inst as BaseWeapon).setup(config, lv)
		_weapons.append(inst as BaseWeapon)
		print("[WeaponDirector] added %s (lv%d)" % [config.id, lv])
		_try_merge_all()
		return true
	return false

## Level a single copy of `id` up by `by`. Only used by the debug/self-test
## path now; gameplay leveling happens through the 3-into-1 merge instead.
func level_up_weapon_by_id(id: String, by: int = 1) -> void:
	var target: BaseWeapon = null
	for w in _weapons:
		if w and w.config and w.config.id == id:
			target = w
			break
	if target == null:
		return
	target.level += by
	if target.config:
		target._recompute_stats()
		print("[WeaponDirector] %s -> lv%d" % [id, target.level])

# --- Auto-merge -----------------------------------------------------------

## Does the player hold at least one copy of `id` at level >= min_level?
## Fusion's eligibility is per-ingredient: it needs ONE qualifying copy of each
## base weapon (a Lv3 copy already represents 9 merged drops), then consumes
## exactly that one. So the threshold is a single copy, not MERGE_COUNT.
func _has_qualified(id: String, min_level: int) -> bool:
	for w in _weapons:
		if w and w.config and w.config.id == id and w.level >= min_level:
			return true
	return false

## Does the player hold at least one copy of `id`?
func _has_any(id: String) -> bool:
	for w in _weapons:
		if w and w.config and w.config.id == id:
			return true
	return false

## Could a single new `id` copy complete a 3-way merge right now? Used by the
## full-slot grant path: the only things worth accepting at full capacity are
## drops that immediately free slots.
##
## The comparison is against `drop_level_of(id)`, NOT a hardcoded 1: rare
## weapons drop pre-levelled, so a freshly granted magnetic laser arrives at
## Lv2 and can only pair with the Lv2 copies already held.
func _can_complete_merge(id: String) -> bool:
	var lv: int = drop_level_of(id)
	var n: int = 0
	for w in _weapons:
		if w and w.config and w.config.id == id and w.level == lv:
			n += 1
			if n >= MERGE_COUNT - 1:
				return true
	return false

## Remove one copy of `id` at >= min_level (the highest such copy). Used by
## fusion to consume exactly one ingredient, leaving spare copies alone.
func _consume_one(id: String, min_level: int) -> void:
	var victim: BaseWeapon = null
	for w in _weapons:
		if w and w.config and w.config.id == id and w.level >= min_level:
			if victim == null or w.level > victim.level:
				victim = w
	if victim == null:
		return
	_weapons.erase(victim)
	victim.queue_free()

## Merge every qualifying triple, looping until the arsenal stabilizes (the
## survivor of one merge can immediately join the next — 9 Lv1 copies cascade
## into a single Lv3). Called after every successful add. Also re-entrant-safe:
## add_child fires tree_changed -> _prune while we're mid-loop.
func _try_merge_all() -> void:
	if _merging:
		return
	_merging = true
	var guard: int = 0
	while guard < 64:
		var group: Array[BaseWeapon] = _find_merge_group()
		if group.is_empty():
			break
		_do_merge(group)
		guard += 1
	_merging = false

## Any 3 weapons with the same id and level, where that level is below the
## fusion ceiling. Returns [] when none exist.
func _find_merge_group() -> Array[BaseWeapon]:
	for w in _weapons:
		if not (w and w.config):
			continue
		if w.level >= w.config.max_level:
			continue
		var id: String = w.config.id
		var lv: int = w.level
		var matches: Array[BaseWeapon] = []
		for g in _weapons:
			if g and g.config and g.config.id == id and g.level == lv:
				matches.append(g)
				if matches.size() >= MERGE_COUNT:
					return matches
	return []

## Collapse `group` (3 copies) into one at level+1. The survivor is the
## lowest-indexed copy so the mounted icon order is stable; the other two are
## freed and removed from the list immediately (not on the frame boundary, so
## slots_used() is exact the moment the merge lands).
func _do_merge(group: Array[BaseWeapon]) -> void:
	var survivor: BaseWeapon = group[0]
	for i in range(1, group.size()):
		var victim: BaseWeapon = group[i]
		_weapons.erase(victim)
		victim.queue_free()
	survivor.level += 1
	survivor._recompute_stats()
	weapon_merged.emit(survivor.config.id, survivor.level)
	_spawn_merge_label(survivor.config.id, survivor.level)
	SfxPlayer.play("levelup")
	print("[WeaponDirector] MERGED %s x%d -> lv%d" % [survivor.config.id, MERGE_COUNT, survivor.level])

func _spawn_merge_label(id: String, new_level: int) -> void:
	var fx: Node = get_tree().get_first_node_in_group("fx_manager")
	if fx == null or not fx.has_method("_spawn_label"):
		return
	var pos: Vector2 = Vector2.ZERO
	var players: Array = get_tree().get_nodes_in_group("player")
	if not players.is_empty() and players[0] is Node2D:
		pos = (players[0] as Node2D).global_position
	fx._spawn_label(pos, "%s Lv%d！" % [display_name_of(id), new_level], Color(1.0, 0.85, 0.4), 24, 1.0)
