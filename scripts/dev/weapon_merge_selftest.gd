extends Node2D
## Dev-only self test for the 3-into-1 weapon merge (Iter7 merge). Not referenced
## by the game; run it headless:
##
##   godot --headless res://scenes/dev/weapon_merge_selftest.tscn
##
## Exits with code 0 on success, 1 if any assertion failed.
##
## Grants weapons through the real WeaponDirector (via add_weapon_by_id) so the
## test covers the exact path gameplay uses: the auto-merge after each add, the
## cascade of 9 copies collapsing into a Lv3, the max_level ceiling, and the
## full-slot grant path.

@onready var _player: Node2D = $Player

var _failures: int = 0

func _ready() -> void:
	await get_tree().process_frame
	print("=== weapon merge selftest ===")
	await _test_three_merge_to_one()
	await _test_curve_locked()
	await _test_cooldown_weapon_scales()
	await _test_cascade_nine_to_lv3()
	await _test_two_do_not_merge()
	await _test_mixed_levels_do_not_merge()
	await _test_max_level_ceiling()
	await _test_full_slot_refuses()
	await _test_full_slot_accepts_completing_merge()
	print("=== weapon merge selftest failures: %d ===" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

# --- core merge -----------------------------------------------------------

func _test_three_merge_to_one() -> void:
	var t: String = "three_to_one"
	await _clear()
	for i in range(3):
		WeaponDirector.add_weapon_by_id("bullet_volley")
	await _advance(0.1)
	if WeaponDirector.slots_used() != 1:
		_fail(t, "%d slots after 3 copies, want 1" % WeaponDirector.slots_used())
		return
	if WeaponDirector.count_of("bullet_volley") != 1:
		_fail(t, "expected 1 bullet_volley, got %d" % WeaponDirector.count_of("bullet_volley"))
		return
	if WeaponDirector.weapon_level_of("bullet_volley") != 2:
		_fail(t, "level %d, want 2" % WeaponDirector.weapon_level_of("bullet_volley"))
		return
	_ok(t, "3 copies -> 1 Lv2, 3 slots -> 1")

func _test_curve_locked() -> void:
	var t: String = "curve"
	await _clear()
	# 3 copies merge to Lv2: _damage must be 2.0x base, _fire_rate 1.5x base.
	for i in range(3):
		WeaponDirector.add_weapon_by_id("bullet_volley")
	await _advance(0.1)
	var w: BaseWeapon = _find("bullet_volley")
	if w == null:
		_fail(t, "no bullet_volley after merge")
		return
	var cfg: WeaponConfig = w.config
	if cfg == null:
		_fail(t, "config null after merge")
		return
	if absf(w._damage - cfg.base_damage * 2.0) > 0.01:
		_fail(t, "Lv2 _damage=%.2f, want %.2f (2.0x base)" % [w._damage, cfg.base_damage * 2.0])
		return
	if absf(w._fire_rate - cfg.base_fire_rate * 1.5) > 0.01:
		_fail(t, "Lv2 _fire_rate=%.2f, want %.2f (1.5x base)" % [w._fire_rate, cfg.base_fire_rate * 1.5])
		return
	_ok(t, "Lv2 = 2.0x damage x 1.5x rate — the merge curve is locked")

func _test_cooldown_weapon_scales() -> void:
	# Cooldown-driven weapons (chain lightning) must ALSO speed up by the merge
	# curve's rate multiplier, or a merge is worth 2.0x there instead of 3.0x.
	var t: String = "cooldown_scale"
	await _clear()
	WeaponDirector.add_weapon_by_id("chain_lightning")
	await _advance(0.1)
	var base: BaseWeapon = _find("chain_lightning")
	if base == null:
		_fail(t, "no chain_lightning")
		return
	var interval_lv1: float = base._interval()
	await _clear()
	for i in range(3):
		WeaponDirector.add_weapon_by_id("chain_lightning")
	await _advance(0.1)
	var merged: BaseWeapon = _find("chain_lightning")
	if merged == null:
		_fail(t, "no chain_lightning after merge")
		return
	var want: float = interval_lv1 / 1.5
	if absf(merged._interval() - want) > 0.01:
		_fail(t, "Lv2 interval=%.3f, want %.3f (1.5x faster)" % [merged._interval(), want])
		return
	_ok(t, "Lv2 chain interval %.3f -> %.3f, scaled by the rate multiplier" % [interval_lv1, merged._interval()])

func _test_cascade_nine_to_lv3() -> void:
	var t: String = "cascade"
	await _clear()
	for i in range(9):
		WeaponDirector.add_weapon_by_id("shotgun")
	await _advance(0.1)
	if WeaponDirector.slots_used() != 1:
		_fail(t, "%d slots after 9 copies, want 1" % WeaponDirector.slots_used())
		return
	if WeaponDirector.weapon_level_of("shotgun") != 3:
		_fail(t, "level %d, want 3 (9 Lv1 should cascade to 1 Lv3)" % WeaponDirector.weapon_level_of("shotgun"))
		return
	_ok(t, "9 copies cascade into a single Lv3")

func _test_two_do_not_merge() -> void:
	var t: String = "two_no_merge"
	await _clear()
	WeaponDirector.add_weapon_by_id("laser_lance")
	WeaponDirector.add_weapon_by_id("laser_lance")
	await _advance(0.1)
	if WeaponDirector.slots_used() != 2:
		_fail(t, "%d slots after 2 copies, want 2" % WeaponDirector.slots_used())
		return
	if WeaponDirector.weapon_level_of("laser_lance") != 1:
		_fail(t, "level %d, want 1 (a pair must not merge)" % WeaponDirector.weapon_level_of("laser_lance"))
		return
	_ok(t, "2 copies stay at 2 slots Lv1")

func _test_mixed_levels_do_not_merge() -> void:
	# 2x Lv1 + 1x Lv2 is NOT a mergeable triple — the levels must match.
	var t: String = "mixed_levels"
	await _clear()
	WeaponDirector.add_weapon_by_id("mine_layer")
	WeaponDirector.add_weapon_by_id("mine_layer")
	WeaponDirector.add_weapon_by_id("mine_layer")
	await _advance(0.1)
	# Now we have 1x Lv2. Add one more Lv1 -> 1x Lv2 + 1x Lv1 (no triple).
	WeaponDirector.add_weapon_by_id("mine_layer")
	await _advance(0.1)
	if WeaponDirector.slots_used() != 2:
		_fail(t, "%d slots for 1x Lv2 + 1x Lv1, want 2" % WeaponDirector.slots_used())
		return
	if WeaponDirector.weapon_level_of("mine_layer") != 2:
		_fail(t, "max level %d, want 2" % WeaponDirector.weapon_level_of("mine_layer"))
		return
	_ok(t, "2x Lv1 + 1x Lv2 do not form a triple")

func _test_max_level_ceiling() -> void:
	# At max_level, three copies must co-exist rather than merge forever.
	var t: String = "max_level"
	await _clear()
	WeaponDirector.add_weapon_by_id("shotgun")
	await _advance(0.1)
	var w: BaseWeapon = _find("shotgun")
	if w == null:
		_fail(t, "no shotgun")
		return
	var cap: int = w.config.max_level
	w.level = cap
	w._recompute_stats()
	WeaponDirector.add_weapon_by_id("shotgun")
	WeaponDirector.add_weapon_by_id("shotgun")
	await _advance(0.1)
	if WeaponDirector.slots_used() != 3:
		_fail(t, "%d slots at max level, want 3 (no merge above the cap)" % WeaponDirector.slots_used())
		return
	_ok(t, "3 max-level copies coexist (no merge past level %d)" % cap)

# --- full-slot drop path --------------------------------------------------

func _test_full_slot_refuses() -> void:
	var t: String = "full_refuses"
	await _clear()
	# Fill 12 slots with 12 DISTINCT weapons (8 base + 4 fusions): every count is
	# 1, so no drop can complete a merge and the grant must be refused.
	for id in WeaponDirector.WEAPON_CATALOG.keys():
		WeaponDirector.add_weapon_by_id(String(id))
	for fid in WeaponDirector.FUSION_RECIPES.keys():
		_force_add_fusion(String(fid))
	await _advance(0.1)
	if not WeaponDirector.is_full():
		_fail(t, "setup did not fill the arsenal (%d slots)" % WeaponDirector.slots_used())
		return
	var before: int = WeaponDirector.slots_used()
	var granted: String = WeaponDirector.grant_random_weapon()
	if granted != "":
		_fail(t, "full arsenal granted %s (no pair to complete) — slots %d" % [granted, WeaponDirector.slots_used()])
		return
	if WeaponDirector.slots_used() != before:
		_fail(t, "refused grant changed the slot count to %d" % WeaponDirector.slots_used())
		return
	_ok(t, "full arsenal with no mergeable pair refuses the drop")

func _test_full_slot_accepts_completing_merge() -> void:
	var t: String = "full_accepts"
	await _clear()
	# Fill 12 slots with 2 copies of bullet_volley + 10 other distinct weapons.
	# bullet_volley has a mergeable pair, so the grant can complete a merge.
	WeaponDirector.add_weapon_by_id("bullet_volley")
	WeaponDirector.add_weapon_by_id("bullet_volley")
	var others: Array = ["chain_lightning", "shotgun", "laser_lance", "mine_layer",
		"flamethrower", "homing_dart", "orbiting_blades"]  # 7 more, distinct
	for id in others:
		WeaponDirector.add_weapon_by_id(String(id))
	for fid in WeaponDirector.FUSION_RECIPES.keys():
		_force_add_fusion(String(fid))
	await _advance(0.1)
	if not WeaponDirector.is_full():
		_fail(t, "setup did not fill the arsenal (%d slots)" % WeaponDirector.slots_used())
		return
	if not WeaponDirector._can_complete_merge("bullet_volley"):
		_fail(t, "_can_complete_merge(bullet_volley) should be true with 2 copies")
		return
	var before: int = WeaponDirector.slots_used()
	WeaponDirector.add_weapon_by_id("bullet_volley")
	await _advance(0.1)
	# 12 full, add 1 -> 13, merge 3->1 removes 2 -> 11. Net -1, so the arsenal
	# actually shrank: the drop was accepted precisely because it freed slots.
	if WeaponDirector.slots_used() != before - 1:
		_fail(t, "merge on a full arsenal: %d -> %d, want %d" % [before, WeaponDirector.slots_used(), before - 1])
		return
	if WeaponDirector.weapon_level_of("bullet_volley") != 2:
		_fail(t, "bullet_volley level %d, want 2" % WeaponDirector.weapon_level_of("bullet_volley"))
		return
	_ok(t, "a merge-completing drop on a full arsenal shrank it to %d slots" % WeaponDirector.slots_used())

## Equip a fusion weapon without running fuse(), so the full-slot setups can
## reach 12 distinct ids. Recipes carry a config path but no scene path — the
## scene always lives at scenes/weapons/<id>.tscn.
func _force_add_fusion(id: String) -> void:
	var entry: Dictionary = WeaponDirector.FUSION_RECIPES.get(id, {})
	if entry.is_empty():
		return
	var cfg: Resource = load(String(entry.get("config", "")))
	var scene: PackedScene = load("res://scenes/weapons/%s.tscn" % id) as PackedScene
	if cfg is WeaponConfig and scene:
		WeaponDirector.add_weapon(cfg as WeaponConfig, scene)

# --- helpers --------------------------------------------------------------

func _find(weapon_id: String) -> BaseWeapon:
	for c in _player.get_children():
		if c is BaseWeapon:
			var w: BaseWeapon = c as BaseWeapon
			if w.config and w.config.id == weapon_id:
				return w
	return null

func _clear() -> void:
	WeaponDirector._reset()
	for c in _player.get_children():
		if c is BaseWeapon:
			c.queue_free()
	await _advance(0.1)

func _advance(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

func _ok(test_name: String, msg: String) -> void:
	print("  OK   %-22s %s" % [test_name, msg])

func _fail(test_name: String, msg: String) -> void:
	_failures += 1
	printerr("  FAIL %-22s %s" % [test_name, msg])