extends Node2D
## Headless self-test for the pickup-item system (Iter8).
##   godot --headless res://scenes/dev/pickup_selftest.tscn
## Exits 0 when green, 1 when any check fails.
##
## Covers all five item kinds, plus the two behaviours that are easy to get
## wrong: the shield running out of charges, and time-stop freezing enemies
## without freezing the player.

const PICKUP_SCENE: PackedScene = preload("res://scenes/pickup_item.tscn")

var _failures: int = 0

@onready var player: CharacterBody2D = $Player
@onready var spawner: Node2D = $SpawnDirector

func _ready() -> void:
	await get_tree().process_frame
	print("=== pickup selftest ===")
	await _test_roll_weights()
	await _test_collect_by_touch()
	await _test_heal()
	await _test_shield()
	await _test_time_stop()
	await _test_bomb()
	await _test_weapon()
	print("=== pickup selftest failures: %d ===" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

# --- Kind roll ---

func _test_roll_weights() -> void:
	# Every kind must be reachable, or a drop table entry is silently dead.
	var seen: Dictionary = {}
	for i in range(4000):
		seen[PickupItem.roll_kind()] = true
	var missing: Array[String] = []
	for k in PickupItem.Kind.values():
		if not seen.has(k):
			missing.append(str(k))
	if missing.is_empty():
		_ok("roll", "all %d kinds reachable" % PickupItem.Kind.size())
	else:
		_fail("roll", "kinds never rolled: %s" % ", ".join(missing))

# --- Collection path ---

func _test_collect_by_touch() -> void:
	# The real path: drop an item on the player and let the Area2D overlap
	# start the homing, instead of poking _collect() by hand.
	var item: PickupItem = _drop(PickupItem.Kind.HEAL, player.global_position + Vector2(40, 0))
	await _advance(1.0)
	if is_instance_valid(item) and not item.is_queued_for_deletion():
		_fail("touch", "item within reach was never collected")
	else:
		_ok("touch", "item homes in and is collected on contact")

# --- Effects ---

func _test_heal() -> void:
	player.hp = 40.0
	var before: float = player.hp
	_apply(PickupItem.Kind.HEAL)
	var want: float = before + player.max_hp * PickupItem.HEAL_PCT
	if absf(player.hp - want) > 0.5:
		_fail("heal", "hp %.1f -> %.1f, expected %.1f" % [before, player.hp, want])
	else:
		_ok("heal", "restored %.0f%% of max hp" % (PickupItem.HEAL_PCT * 100.0))
	# And it must clamp instead of overhealing.
	player.hp = player.max_hp - 1.0
	_apply(PickupItem.Kind.HEAL)
	if player.hp > player.max_hp + 0.01:
		_fail("heal", "overhealed past max (%.1f > %.1f)" % [player.hp, player.max_hp])
	else:
		_ok("heal", "clamps at max hp")

func _test_shield() -> void:
	GameState.shield_charges = 0
	player.hp = player.max_hp
	_apply(PickupItem.Kind.SHIELD)
	if GameState.shield_charges != PickupItem.SHIELD_CHARGES:
		_fail("shield", "expected %d charges, got %d" % [PickupItem.SHIELD_CHARGES, GameState.shield_charges])
		return
	_ok("shield", "granted %d charges" % GameState.shield_charges)
	# Each hit must eat exactly one charge and cost no health. take_damage
	# grants invulnerability frames, so the timer has to be cleared between
	# hits or only the first one lands.
	var hp_before: float = player.hp
	for i in range(PickupItem.SHIELD_CHARGES):
		_hit(10.0)
	if GameState.shield_charges != 0 or absf(player.hp - hp_before) > 0.01:
		_fail("shield", "after %d hits: charges=%d hp=%.1f (wanted 0 / %.1f)" % [
			PickupItem.SHIELD_CHARGES, GameState.shield_charges, player.hp, hp_before])
	else:
		_ok("shield", "absorbed exactly %d hits with no health loss" % PickupItem.SHIELD_CHARGES)
	# One more hit, with no charges left, must actually hurt.
	_hit(10.0)
	if player.hp >= hp_before:
		_fail("shield", "hit past the last charge did no damage")
	else:
		_ok("shield", "damage resumes once the charges run out")

func _test_time_stop() -> void:
	GameState.time_stop_left = 0.0
	var enemy: Node2D = spawner.spawn_enemy_at("chaser", player.global_position + Vector2(300, 0)) as Node2D
	if enemy == null:
		_fail("time_stop", "could not spawn a chaser")
		return
	# Let it get moving first, so "did not move" can't just mean "not started".
	await _advance(0.5)
	var moved_free: float = await _distance_moved_by(enemy, 0.4)
	if moved_free <= 1.0:
		_fail("time_stop", "chaser did not move even before the freeze (%.2fpx)" % moved_free)
		enemy.queue_free()
		return

	_apply(PickupItem.Kind.TIME_STOP)
	if not GameState.is_time_stopped():
		_fail("time_stop", "pickup did not start the freeze")
		enemy.queue_free()
		return
	var moved_frozen: float = await _distance_moved_by(enemy, 0.4)
	if moved_frozen > 1.0:
		_fail("time_stop", "frozen chaser still moved %.2fpx" % moved_frozen)
	else:
		_ok("time_stop", "enemy frozen in place (%.2fpx)" % moved_frozen)

	# The player must keep acting — that is the whole point of freezing only
	# the enemies instead of touching Engine.time_scale. Driven through the
	# real input action, because player._physics_process rebuilds `velocity`
	# from Input every frame and would overwrite a hand-set value.
	var p_from: Vector2 = player.global_position
	Input.action_press("move_right")
	await _advance(0.3)
	Input.action_release("move_right")
	if player.global_position.distance_to(p_from) < 1.0:
		_fail("time_stop", "player was frozen too")
	else:
		_ok("time_stop", "player keeps moving during the freeze")

	# And it has to expire on its own.
	GameState.time_stop_left = 0.15
	await _advance(0.4)
	if GameState.is_time_stopped():
		_fail("time_stop", "freeze never expired")
	else:
		var moved_thawed: float = await _distance_moved_by(enemy, 0.4)
		if moved_thawed <= 1.0:
			_fail("time_stop", "enemy stayed frozen after the freeze expired")
		else:
			_ok("time_stop", "enemy resumes chasing after the freeze (%.1fpx)" % moved_thawed)
	enemy.queue_free()
	await _advance(0.1)

func _test_bomb() -> void:
	var enemies: Array[Node2D] = []
	for i in range(3):
		var e: Node2D = spawner.spawn_enemy_at("chaser", player.global_position + Vector2(80.0 + 60.0 * float(i), 0)) as Node2D
		if e:
			enemies.append(e)
	# Plus one well outside the blast, to prove the radius is respected.
	var far: Node2D = spawner.spawn_enemy_at("chaser", player.global_position + Vector2(PickupItem.BOMB_RADIUS + 400.0, 0)) as Node2D
	await _advance(0.1)
	if enemies.size() < 3 or far == null:
		_fail("bomb", "could not stage the enemies")
		return
	var hp_before: Array[float] = []
	for e in enemies:
		hp_before.append(float(e.hp))
	var far_hp: float = float(far.hp)

	_apply(PickupItem.Kind.BOMB)
	await _advance(0.1)

	var hurt: int = 0
	for i in range(enemies.size()):
		var e: Node2D = enemies[i]
		# Killed outright counts as hurt; a chaser has less hp than the blast.
		if not is_instance_valid(e) or e.is_queued_for_deletion() or float(e.hp) < hp_before[i]:
			hurt += 1
	if hurt != enemies.size():
		_fail("bomb", "only %d/%d enemies in range took damage" % [hurt, enemies.size()])
	else:
		_ok("bomb", "all %d enemies in range took damage" % hurt)
	if is_instance_valid(far) and not far.is_queued_for_deletion() and absf(float(far.hp) - far_hp) < 0.01:
		_ok("bomb", "enemy outside the radius was untouched")
	else:
		_fail("bomb", "enemy outside the %.0fpx radius was hit" % PickupItem.BOMB_RADIUS)
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	if is_instance_valid(far):
		far.queue_free()
	await _advance(0.1)

func _test_weapon() -> void:
	WeaponDirector._reset()
	await _advance(0.1)
	# Empty arsenal: the drop must hand out a brand-new weapon.
	var before: int = WeaponDirector.slots_used()
	_apply(PickupItem.Kind.WEAPON)
	await _advance(0.1)
	if WeaponDirector.slots_used() != before + 1:
		_fail("weapon", "slots %d -> %d, expected +1" % [before, WeaponDirector.slots_used()])
	else:
		_ok("weapon", "granted a new weapon (%d slots used)" % WeaponDirector.slots_used())

	# Fill every slot, then check the drop turns into a level-up instead of
	# being silently thrown away.
	for id in WeaponDirector.missing_weapon_ids():
		WeaponDirector.add_weapon_by_id(id)
	await _advance(0.2)
	var base_count: int = WeaponDirector.WEAPON_CATALOG.size()
	if WeaponDirector.slots_used() != base_count:
		_fail("weapon", "catalog gave %d/%d base weapons" % [WeaponDirector.slots_used(), base_count])
		return
	_ok("weapon", "catalog grants all %d base weapons" % base_count)

	# The remaining 4 ids are fusions. Normally they arrive through fuse(),
	# which CONSUMES its ingredients and therefore lowers the slot count — so
	# reaching 12 at once means adding them directly. This is the cap test, not
	# a fusion test; fusion has its own selftest.
	for fid in WeaponDirector.FUSION_RECIPES.keys():
		_force_add(String(fid))
	await _advance(0.2)
	if not WeaponDirector.is_full():
		_fail("weapon", "only %d/%d slots filled" % [WeaponDirector.slots_used(), WeaponDirector.MAX_WEAPONS])
		return
	_ok("weapon", "base + fusion ids fill all %d slots" % WeaponDirector.MAX_WEAPONS)

	# The 13th must bounce. Built in code because there is no 13th id to load.
	var dummy: WeaponConfig = WeaponConfig.new()
	dummy.id = "selftest_dummy"
	var any_scene: PackedScene = load("res://scenes/weapons/bullet_volley.tscn") as PackedScene
	if WeaponDirector.add_weapon(dummy, any_scene):
		_fail("weapon", "a 13th weapon got past the cap")
	elif WeaponDirector.slots_used() != WeaponDirector.MAX_WEAPONS:
		_fail("weapon", "rejected add still changed the count to %d" % WeaponDirector.slots_used())
	else:
		_ok("weapon", "the 13th weapon is rejected")

	# Every owned id, not just the catalog ones: the level-up picks at random and
	# 4 of the 12 slots hold fusion weapons the catalog does not list.
	var levels_before: Dictionary = {}
	for id in WeaponDirector.owned_weapon_ids():
		levels_before[id] = WeaponDirector.weapon_level_of(id)
	_apply(PickupItem.Kind.WEAPON)
	await _advance(0.1)
	if WeaponDirector.slots_used() != WeaponDirector.MAX_WEAPONS:
		_fail("weapon", "full arsenal grew to %d slots" % WeaponDirector.slots_used())
		return
	var leveled: bool = false
	for id in levels_before.keys():
		if WeaponDirector.weapon_level_of(String(id)) > int(levels_before[id]):
			leveled = true
			break
	if leveled:
		_ok("weapon", "drop on a full arsenal levels a weapon up instead")
	else:
		_fail("weapon", "drop on a full arsenal did nothing at all")

## Equip a fusion weapon without running fuse(), so the slot cap can be tested
## at its actual limit. Fusion recipes carry a config path but no scene path —
## the scene always lives at scenes/weapons/<id>.tscn.
func _force_add(id: String) -> void:
	var entry: Dictionary = WeaponDirector.FUSION_RECIPES.get(id, {})
	if entry.is_empty():
		return
	var cfg: Resource = load(String(entry.get("config", "")))
	var scene: PackedScene = load("res://scenes/weapons/%s.tscn" % id) as PackedScene
	if cfg is WeaponConfig and scene:
		WeaponDirector.add_weapon(cfg as WeaponConfig, scene)

# --- Helpers ---

## Instantiate a pickup of `kind` at `pos` and put it in the scene.
func _drop(kind: int, pos: Vector2) -> PickupItem:
	var item: PickupItem = PICKUP_SCENE.instantiate()
	item.global_position = pos
	item.setup(kind)
	get_tree().current_scene.add_child(item)
	return item

## Apply an item's effect the way collection does, without waiting for the
## homing to play out. Every effect test goes through this.
func _apply(kind: int) -> void:
	var item: PickupItem = _drop(kind, player.global_position)
	item._collect(player)

## Damage the player, bypassing the invulnerability window left over from the
## previous hit — otherwise a loop of hits only ever lands the first one.
func _hit(amount: float) -> void:
	player.invulnerable = false
	player.take_damage(amount)

func _distance_moved_by(node: Node2D, seconds: float) -> float:
	var from: Vector2 = node.global_position
	await _advance(seconds)
	if not is_instance_valid(node):
		return 0.0
	return node.global_position.distance_to(from)

func _advance(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

func _ok(tag: String, msg: String) -> void:
	print("  [ok] %s: %s" % [tag, msg])

func _fail(tag: String, msg: String) -> void:
	_failures += 1
	printerr("  [FAIL] %s: %s" % [tag, msg])
