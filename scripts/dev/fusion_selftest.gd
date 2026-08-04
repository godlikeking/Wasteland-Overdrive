extends Node2D
## Dev-only self test for the Iter7 fusion system. Not referenced by the game;
## run it headless to verify every fusion recipe resolves, instantiates and
## starts its timers:
##
##   godot --headless res://scenes/dev/fusion_selftest.tscn
##
## Exits with code 0 on success, 1 if any recipe failed.

@onready var _player: Node2D = $Player

var _failures: int = 0

func _ready() -> void:
	# Let the player register in the "player" group so WeaponDirector can
	# resolve a parent for the weapon nodes.
	await get_tree().process_frame
	print("=== fusion selftest ===")
	for recipe_id in WeaponDirector.FUSION_RECIPES.keys():
		await _test_recipe(recipe_id)
	await _test_missing_asset_is_non_destructive()
	await _test_spare_copy_survives_fusion()
	print("=== fusion selftest failures: %d ===" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

## Regression: a recipe whose scene/config is missing must bail out WITHOUT
## consuming the base weapons, or the player ends up with no weapons at all.
## Only runs for recipes whose assets are genuinely absent — move a
## scenes/weapons/<id>.tscn aside to exercise this path.
func _test_missing_asset_is_non_destructive() -> void:
	var broken: Array = []
	for rid in WeaponDirector.FUSION_RECIPES.keys():
		var entry: Dictionary = WeaponDirector.FUSION_RECIPES[rid]
		if not ResourceLoader.exists("res://scenes/weapons/%s.tscn" % rid) 				or not ResourceLoader.exists(entry["config"]):
			broken.append(rid)
	if broken.is_empty():
		print("  -- missing-asset check skipped (all 4 recipes have assets)")
		return
	for rid in broken:
		for id in WeaponDirector.BASE_WEAPONS:
			WeaponDirector.add_weapon_by_id(id)
		WeaponDirector._debug_max_base_weapons()
		# A recipe with missing assets must not even be offered.
		for c in WeaponDirector.fuse_candidates():
			if c["id"] == rid:
				_fail(rid, "missing-asset recipe was offered to the player")
		# And forcing it must leave the arsenal intact.
		var got: String = WeaponDirector.fuse(rid)
		if got != "":
			_fail(rid, "fuse() returned '%s' despite missing assets" % got)
		for id in WeaponDirector.BASE_WEAPONS:
			if not WeaponDirector.has_weapon(id):
				_fail(rid, "base weapon '%s' was destroyed by a failed fusion" % id)
		print("  OK %-16s arsenal intact after failed fusion" % rid)
		await _teardown()

func _test_recipe(recipe_id: String) -> void:
	var needs: Array = (WeaponDirector.FUSION_RECIPES[recipe_id] as Dictionary)["needs"]
	# Fresh arsenal: grant + max all 3 base weapons.
	for id in WeaponDirector.BASE_WEAPONS:
		WeaponDirector.add_weapon_by_id(id)
	WeaponDirector._debug_max_base_weapons()

	var candidates: Array = WeaponDirector.fuse_candidates()
	var listed: bool = false
	for c in candidates:
		if c["id"] == recipe_id:
			listed = true
	if not listed:
		_fail(recipe_id, "not offered by fuse_candidates()")
		await _teardown()
		return

	var new_id: String = WeaponDirector.fuse(recipe_id)
	if new_id != recipe_id:
		_fail(recipe_id, "fuse() returned '%s'" % new_id)
		await _teardown()
		return

	# Base weapons in the recipe must be gone; the fused one must exist.
	for need in needs:
		if WeaponDirector.has_weapon(need):
			_fail(recipe_id, "base weapon '%s' survived the fusion" % need)
	if not WeaponDirector.has_weapon(new_id):
		_fail(recipe_id, "fused weapon not registered")
		await _teardown()
		return

	# Give _post_setup a frame, then inspect the live node.
	await get_tree().process_frame
	var node: Node = _find_weapon_node(new_id)
	if node == null:
		_fail(recipe_id, "no weapon node under player")
		await _teardown()
		return
	_check_timers(recipe_id, node)
	_check_blades(recipe_id, node)
	print("  OK %-16s node=%s" % [recipe_id, node.name])
	await _teardown()

## Every Timer child must be running, otherwise the weapon never fires.
func _check_timers(recipe_id: String, node: Node) -> void:
	var found: int = 0
	for child in node.get_children():
		if child is Timer:
			found += 1
			if (child as Timer).is_stopped():
				_fail(recipe_id, "timer '%s' is stopped after setup" % child.name)
	if found == 0:
		_fail(recipe_id, "weapon has no Timer children")

## Weapons whose config asks for orbiting blades must have spawned them.
func _check_blades(recipe_id: String, node: Node) -> void:
	var blades_root: Node = node.get_node_or_null("Blades")
	if blades_root == null:
		return   # bullet-only weapon, nothing to check
	var cfg: WeaponConfig = (node as BaseWeapon).config
	if cfg == null:
		_fail(recipe_id, "config is null after setup")
		return
	var n: int = blades_root.get_child_count()
	if n != cfg.blade_count:
		_fail(recipe_id, "expected %d blades, got %d" % [cfg.blade_count, n])

func _find_weapon_node(weapon_id: String) -> Node:
	for child in _player.get_children():
		if child is BaseWeapon:
			var w: BaseWeapon = child as BaseWeapon
			if w.config != null and w.config.id == weapon_id:
				return w
	return null

## Fusion must consume exactly ONE qualifying copy of each ingredient, leaving
## any spare copies the player owns untouched.
func _test_spare_copy_survives_fusion() -> void:
	var t: String = "spare_copy"
	await _teardown()
	# Two copies of each base weapon: fusion consumes one of each, one remains.
	for id in WeaponDirector.BASE_WEAPONS:
		WeaponDirector.add_weapon_by_id(id)
		WeaponDirector.add_weapon_by_id(id)
	WeaponDirector._debug_max_base_weapons()
	var got: String = WeaponDirector.fuse("apocalypse")
	if got != "apocalypse":
		_fail(t, "fuse() returned '%s'" % got)
		await _teardown()
		return
	for id in WeaponDirector.BASE_WEAPONS:
		if WeaponDirector.count_of(id) != 1:
			_fail(t, "base weapon '%s' count %d after fusion, want 1 (spare must survive)" % [
				id, WeaponDirector.count_of(id)])
			return
	if not WeaponDirector.has_weapon("apocalypse"):
		_fail(t, "fused weapon not registered")
		await _teardown()
		return
	_ok(t, "fusion consumed one copy of each ingredient, spares survived")
	await _teardown()

## Drop every weapon so the next recipe starts from a clean arsenal.
func _teardown() -> void:
	for child in _player.get_children():
		if child is BaseWeapon:
			child.queue_free()
	# Orbiting blades that were mid-dash live under the current scene.
	for b in get_tree().get_nodes_in_group("blades"):
		b.queue_free()
	WeaponDirector._reset()
	await get_tree().process_frame

func _fail(recipe_id: String, msg: String) -> void:
	_failures += 1
	printerr("  FAIL %s: %s" % [recipe_id, msg])

func _ok(recipe_id: String, msg: String) -> void:
	print("  OK %-16s %s" % [recipe_id, msg])
