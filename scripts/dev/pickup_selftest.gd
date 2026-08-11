extends Node2D
## Headless self-test for the pickup-item system (Iter8).
##   godot --headless res://scenes/dev/pickup_selftest.tscn
## Exits 0 when green, 1 when any check fails.
##
## Covers all six item kinds, plus the behaviours that are easy to get wrong:
## the shield running out of charges AND out of time, the shield refusing to
## stack, HEAL staying out of the normal roll pool (elite-only), time-stop
## freezing enemies without freezing the player, and the magnet vacuuming the
## map without vacuuming itself.

const PICKUP_SCENE: PackedScene = preload("res://scenes/pickup_item.tscn")
const GEM_SCENE: PackedScene = preload("res://scenes/xp_gem.tscn")
## Preloaded for its static `expiry_alpha_mult` — the flash is asserted as a pure
## function because `_draw` output cannot be read back headlessly.
const SHIELD_RING: GDScript = preload("res://scripts/shield_ring.gd")

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
	await _test_shield_no_stack()
	await _test_shield_expiry()
	await _test_shield_ring_flash()
	await _test_time_stop()
	await _test_bomb()
	await _test_weapon()
	await _test_magnet()
	await _test_magnet_no_stack()
	await _clear_arsenal()
	_test_elite_only_weapons()
	await _test_weapon_drop_shows_its_own_icon()
	print("=== pickup selftest failures: %d ===" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

## 清空武器库。前面的 _test_weapon 会把 12 个槽全部填满，而满槽时候选池只留
## "能立刻凑成合并的 id" —— 不清空的话下面两条掉落池断言量的其实是满槽逻辑，
## 而不是掉落池本身。
func _clear_arsenal() -> void:
	WeaponDirector._reset()
	for c in player.get_children():
		if c is BaseWeapon:
			c.queue_free()
	await _advance(0.1)

## 磁轨激光 / 火焰喷射器**只从精英档（精英 + BOSS）掉落**。
## 杂兵的掉落池里必须一次都不出现，否则"稀有武器"就退化成普通掉落。
func _test_elite_only_weapons() -> void:
	var elite_only: Array[String] = ["laser_lance", "flamethrower"]
	for id in elite_only:
		if not WeaponDirector.is_elite_only(id):
			_fail("elite_weapon", "%s is not marked elite_only" % id)
			return
	# 杂兵池：采样足够多次，这两把一次都不该出现。
	var trash_hits: Dictionary = {}
	for i in range(4000):
		var id: String = WeaponDirector.roll_weapon_id(false)
		trash_hits[id] = int(trash_hits.get(id, 0)) + 1
	var leaked: Array[String] = []
	for id in elite_only:
		if int(trash_hits.get(id, 0)) > 0:
			leaked.append("%s x%d" % [id, int(trash_hits[id])])
	if leaked.is_empty():
		_ok("elite_weapon", "trash drops never roll 磁轨激光/火焰喷射器 (4000 draws)")
	else:
		_fail("elite_weapon", "trash pool leaked elite-only weapons: %s" % ", ".join(leaked))
	# 杂兵池不能被掏空：其余武器还得照常出。
	if trash_hits.size() < 3:
		_fail("elite_weapon", "trash pool collapsed to %d distinct ids" % trash_hits.size())
	else:
		_ok("elite_weapon", "trash pool still offers %d other weapons" % trash_hits.size())
	# 精英池：两把都必须可达。
	var elite_hits: Dictionary = {}
	for i in range(6000):
		var id: String = WeaponDirector.roll_weapon_id(true)
		elite_hits[id] = int(elite_hits.get(id, 0)) + 1
	var missing: Array[String] = []
	for id in elite_only:
		if int(elite_hits.get(id, 0)) == 0:
			missing.append(id)
	if missing.is_empty():
		_ok("elite_weapon", "elite drops can roll both elite-only weapons")
	else:
		_fail("elite_weapon", "elite pool never rolled: %s" % ", ".join(missing))

## 武器掉落物在地上画的是**那把武器自己的图标**，而不是通用武器图标；
## 并且捡起来拿到的就是图标上那把（落地时就定下来了）。
func _test_weapon_drop_shows_its_own_icon() -> void:
	var item: PickupItem = PICKUP_SCENE.instantiate() as PickupItem
	add_child(item)
	item.global_position = Vector2(4000, 4000)   # 远离玩家，别被吸走
	item.weapon_id = "laser_lance"
	item.setup(PickupItem.Kind.WEAPON, true)
	await get_tree().process_frame
	var want: Texture2D = WeaponDirector.icon_of("laser_lance")
	if want == null:
		_fail("weapon_icon", "laser_lance has no icon in its WeaponConfig")
		item.queue_free()
		return
	if item.sprite.texture != want:
		_fail("weapon_icon", "drop shows '%s', expected the laser_lance icon '%s'" % [
			item.sprite.texture.resource_path if item.sprite.texture else "<none>",
			want.resource_path])
	else:
		_ok("weapon_icon", "a laser_lance drop shows the laser_lance icon on the ground")
	item.queue_free()
	await get_tree().process_frame
	# 落地即定：setup 后 weapon_id 必须已经有值（否则图标无从可画）。
	var rolled: PickupItem = PICKUP_SCENE.instantiate() as PickupItem
	add_child(rolled)
	rolled.global_position = Vector2(4200, 4200)
	rolled.setup(PickupItem.Kind.WEAPON, false)
	await get_tree().process_frame
	if rolled.weapon_id == "":
		_fail("weapon_icon", "a weapon drop left weapon_id empty — it would fall back to the generic icon")
	elif WeaponDirector.is_elite_only(rolled.weapon_id):
		_fail("weapon_icon", "a trash weapon drop picked the elite-only %s" % rolled.weapon_id)
	else:
		_ok("weapon_icon", "a weapon drop decides its weapon (%s) at drop time" % rolled.weapon_id)
	rolled.queue_free()
	await get_tree().process_frame

# --- Kind roll ---

func _test_roll_weights() -> void:
	# Every kind in the pool must be reachable, or a drop table entry is
	# silently dead. HEAL 刻意不在池里（只由精英怪极低概率掉落），所以这里
	# 断言的是"池内种类全可达 + HEAL 永不从池里滚出来"。
	var seen: Dictionary = {}
	for i in range(4000):
		seen[PickupItem.roll_kind()] = true
	var missing: Array[String] = []
	for k in PickupItem.DROP_WEIGHTS.keys():
		if not seen.has(k):
			missing.append(str(k))
	if missing.is_empty():
		_ok("roll", "all %d pooled kinds reachable" % PickupItem.DROP_WEIGHTS.size())
	else:
		_fail("roll", "kinds never rolled: %s" % ", ".join(missing))
	if seen.has(PickupItem.Kind.HEAL):
		_fail("roll", "HEAL rolled from the normal pool — it must be elite-only")
	else:
		_ok("roll", "HEAL never rolls from the normal pool (elite-only)")

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

## 护盾**不可叠加**：已有护盾时再捡不加层，add_shield 返回 false，层数不变。
## 这条是防"囤护盾等于永久无敌"的回归闸门。
func _test_shield_no_stack() -> void:
	_clear_shield()
	var first: bool = GameState.add_shield(PickupItem.SHIELD_CHARGES, PickupItem.SHIELD_SECONDS)
	var after_first: int = GameState.shield_charges
	if not first or after_first != PickupItem.SHIELD_CHARGES:
		_fail("shield_stack", "first shield did not apply (ok=%s charges=%d)" % [first, after_first])
		return
	# 第二次必须被拒绝，且层数不涨。
	var second: bool = GameState.add_shield(PickupItem.SHIELD_CHARGES, PickupItem.SHIELD_SECONDS)
	if second:
		_fail("shield_stack", "add_shield() returned true while a shield was active")
	elif GameState.shield_charges != after_first:
		_fail("shield_stack", "charges stacked %d -> %d" % [after_first, GameState.shield_charges])
	else:
		_ok("shield_stack", "second pickup refused, charges stay at %d" % GameState.shield_charges)
	# 用光之后必须能重新获得（不可叠加 ≠ 一局只能一次）。
	for i in range(PickupItem.SHIELD_CHARGES):
		_hit(10.0)
	if GameState.shield_charges != 0:
		_fail("shield_stack", "charges not drained: %d" % GameState.shield_charges)
		return
	if GameState.add_shield(PickupItem.SHIELD_CHARGES, PickupItem.SHIELD_SECONDS):
		_ok("shield_stack", "a fresh shield is grantable once the old one is spent")
	else:
		_fail("shield_stack", "could not re-shield after the charges were spent")
	_clear_shield()

func _test_shield_expiry() -> void:
	# The shield is a window to fight in, not a bank. Four separate rules, each
	# of which has its own way of silently reverting to "permanent shield".
	_clear_shield()

	# 1. The pickup must hand over the constant, not some default. A missing
	#    `seconds` argument used to mint an unlimited shield.
	_apply(PickupItem.Kind.SHIELD)
	if absf(GameState.shield_left - PickupItem.SHIELD_SECONDS) > 0.2:
		_fail("shield_time", "pickup granted %.1fs, expected %.1fs" % [
			GameState.shield_left, PickupItem.SHIELD_SECONDS])
	else:
		_ok("shield_time", "pickup grants a %.0fs window" % PickupItem.SHIELD_SECONDS)

	# 2. Unspent charges are lost when the window closes, and the hit after that
	#    has to actually land. Both signals must fire, because the HUD and the
	#    ring would otherwise keep advertising a shield that absorbs nothing.
	_clear_shield()
	var charge_sig: Array[int] = []
	var time_sig: Array[float] = []
	var on_charges: Callable = func(c: int) -> void: charge_sig.append(c)
	var on_time: Callable = func(t: float) -> void: time_sig.append(t)
	GameState.shield_changed.connect(on_charges)
	GameState.shield_time_changed.connect(on_time)
	GameState.add_shield(2, 0.3)
	await _advance(0.6)
	GameState.shield_changed.disconnect(on_charges)
	GameState.shield_time_changed.disconnect(on_time)
	if GameState.shield_charges != 0 or GameState.shield_left > 0.0:
		_fail("shield_time", "after expiry: charges=%d left=%.2f (wanted 0 / 0)" % [
			GameState.shield_charges, GameState.shield_left])
	elif not charge_sig.has(0):
		_fail("shield_time", "expiry never emitted shield_changed(0): %s" % str(charge_sig))
	elif not time_sig.has(0.0):
		_fail("shield_time", "expiry never emitted shield_time_changed(0)")
	else:
		_ok("shield_time", "unspent charges are dropped when the window closes, both signals fire")
	var hp_before: float = player.hp
	_hit(10.0)
	if player.hp >= hp_before:
		_fail("shield_time", "a hit after expiry was still absorbed")
	else:
		_ok("shield_time", "damage resumes once the window closes")

	# 3. 护盾不可叠加，所以"第二次捡"既不加层也不刷新时长 —— 被整发拒绝。
	#    （旧规则是"叠层 + 取更长窗口"，护盾改成不可叠加后那条已作废；
	#    真正的叠加闸门在 _test_shield_no_stack。）
	_clear_shield()
	GameState.add_shield(1, 5.0)
	var left_after_first: float = GameState.shield_left
	GameState.add_shield(1, 20.0)
	if GameState.shield_charges != 1:
		_fail("shield_time", "a second pickup changed charges to %d" % GameState.shield_charges)
	elif absf(GameState.shield_left - left_after_first) > 0.2:
		_fail("shield_time", "a second pickup moved the window %.2fs -> %.2fs" % [
			left_after_first, GameState.shield_left])
	else:
		_ok("shield_time", "a second pickup neither stacks charges nor extends the window")

	# 4. Spending the last charge ends the effect, so the countdown has to stop
	#    with it — otherwise the HUD ticks down a shield that is already gone.
	_clear_shield()
	GameState.add_shield(2, 10.0)
	GameState.consume_shield()
	if GameState.shield_left <= 0.0:
		_fail("shield_time", "the timer was cleared while a charge remained")
		return
	GameState.consume_shield()
	if GameState.shield_left > 0.0:
		_fail("shield_time", "the timer kept running after the last charge (%.2fs)" % GameState.shield_left)
	else:
		_ok("shield_time", "spending the last charge clears the countdown")
	_clear_shield()

## The ring's expiry flash. Asserted through the pure function rather than the
## drawn output: what matters is that it stays lit outside the warning window,
## dips inside it, and never blinks when no timer is known.
func _test_shield_ring_flash() -> void:
	var lead: float = float(SHIELD_RING.get("WARN_LEAD"))
	if absf(SHIELD_RING.expiry_alpha_mult(lead + 2.0) - 1.0) > 0.001:
		_fail("shield_ring", "ring dimmed while %.1fs remained (outside the %.1fs window)" % [lead + 2.0, lead])
	else:
		_ok("shield_ring", "ring is fully lit outside the %.0fs warning window" % lead)
	# No timer known (the ring also runs before the first time signal arrives):
	# it must stay solid instead of blinking for the whole run.
	if absf(SHIELD_RING.expiry_alpha_mult(0.0) - 1.0) > 0.001:
		_fail("shield_ring", "ring blinked with no timer known")
	else:
		_ok("shield_ring", "no timer known means no blink")
	# Inside the window it has to actually swing, and stay a legal alpha scale.
	var lo: float = 2.0
	var hi: float = 0.0
	for i in range(200):
		var t: float = lead * float(i) / 199.0
		var a: float = SHIELD_RING.expiry_alpha_mult(t)
		lo = minf(lo, a)
		hi = maxf(hi, a)
	if lo < 0.0 or hi > 1.0:
		_fail("shield_ring", "alpha multiplier left 0..1 (%.2f..%.2f)" % [lo, hi])
	elif hi - lo < 0.3:
		_fail("shield_ring", "flash barely moves (%.2f..%.2f) — the warning is invisible" % [lo, hi])
	else:
		_ok("shield_ring", "flash swings %.2f..%.2f inside the warning window" % [lo, hi])

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

	# Fill every slot with 12 DISTINCT weapons (8 base + 4 fusions): every count
	# is 1, so no drop can complete a merge, and a further drop must be refused —
	# not silently thrown away or turned into a level-up.
	WeaponDirector._reset()
	for c in player.get_children():
		if c is BaseWeapon:
			c.queue_free()
	await _advance(0.2)
	for id in WeaponDirector.WEAPON_CATALOG.keys():
		WeaponDirector.add_weapon_by_id(String(id))
	for fid in WeaponDirector.FUSION_RECIPES.keys():
		_force_add(String(fid))
	await _advance(0.2)
	if not WeaponDirector.is_full():
		_fail("weapon", "setup did not fill the arsenal (%d/%d slots)" % [
			WeaponDirector.slots_used(), WeaponDirector.MAX_WEAPONS])
		return
	_ok("weapon", "12 distinct weapons fill every slot without merging")

	var before_full: int = WeaponDirector.slots_used()
	_apply(PickupItem.Kind.WEAPON)
	await _advance(0.1)
	if WeaponDirector.slots_used() != before_full:
		_fail("weapon", "full arsenal with no mergeable pair changed the count to %d" % WeaponDirector.slots_used())
	else:
		_ok("weapon", "drop on a full non-mergeable arsenal is refused (slots stay %d)" % WeaponDirector.slots_used())

func _test_magnet() -> void:
	# Everything is staged FAR outside the pickup radius, and the test first
	# proves the drops sit still on their own — otherwise "they all came in"
	# would only be measuring the normal overlap pickup, not the magnet.
	await _clear_drops()
	var far: float = 1200.0
	var gems: Array[Node2D] = []
	for i in range(3):
		gems.append(_drop_gem(player.global_position + Vector2(far + 120.0 * float(i), 0)))
	var items: Array[PickupItem] = [
		_drop(PickupItem.Kind.HEAL, player.global_position + Vector2(-far, 0)),
		_drop(PickupItem.Kind.SHIELD, player.global_position + Vector2(0, -far)),
	]
	await _advance(0.5)
	var moved: int = 0
	for g in gems:
		if not is_instance_valid(g) or g.global_position.distance_to(player.global_position) < far - 50.0:
			moved += 1
	for it in items:
		if not is_instance_valid(it) or it.global_position.distance_to(player.global_position) < far - 50.0:
			moved += 1
	if moved > 0:
		_fail("magnet", "%d drops homed in with no magnet — staging is inside the pickup radius" % moved)
		return
	_ok("magnet", "5 drops sit still ~%.0fpx away while no magnet exists" % far)

	# HEAL at full hp would apply invisibly, so half the player first; the shield
	# charge count is the second observable arrival.
	player.hp = player.max_hp * 0.5
	GameState.shield_charges = 0
	var hp_before: float = player.hp
	_apply(PickupItem.Kind.MAGNET)
	await _advance(0.2)
	var seeking: int = 0
	for g in gems:
		if is_instance_valid(g) and g._seeking:
			seeking += 1
	for it in items:
		if is_instance_valid(it) and it._seeking:
			seeking += 1
	if seeking != 5:
		_fail("magnet", "only %d/5 drops started homing after the magnet" % seeking)
		return
	_ok("magnet", "all 5 drops (3 gems + 2 items) start homing")

	# They must actually arrive AND fire their own effects. A magnet that pulls
	# items in without triggering them would be a downgrade, not a pickup.
	# 1200px at 320px/s is ~3.8s; 6s leaves room for the acceleration ramp.
	await _advance(6.0)
	var left: int = 0
	for g in gems:
		if is_instance_valid(g) and not g.is_queued_for_deletion():
			left += 1
	for it in items:
		if is_instance_valid(it) and not it.is_queued_for_deletion():
			left += 1
	if left > 0:
		_fail("magnet", "%d/5 drops never reached the player" % left)
	else:
		_ok("magnet", "all 5 drops arrive and are consumed")
	if player.hp <= hp_before:
		_fail("magnet", "the vacuumed heal never applied (hp stayed %.1f)" % player.hp)
	elif GameState.shield_charges != PickupItem.SHIELD_CHARGES:
		_fail("magnet", "the vacuumed shield never applied (%d charges)" % GameState.shield_charges)
	else:
		_ok("magnet", "vacuumed items still apply their own effect on arrival")

func _test_magnet_no_stack() -> void:
	# A magnet is itself in `pickup_items`, so the sweep walks over its own node.
	# Without the self-skip it would call attract_to on itself while mid-collect
	# and fly off toward the player as a live pickup. `_seeking` on the magnet is
	# the direct evidence, so that is what gets asserted.
	await _clear_drops()
	var lone: PickupItem = _drop(PickupItem.Kind.MAGNET, player.global_position + Vector2(900, 0))
	await _advance(0.2)
	lone._effect_magnet(player)
	if lone._seeking:
		_fail("magnet_stack", "the magnet attracted itself")
	else:
		_ok("magnet_stack", "a lone magnet does not attract itself")

	# 磁吸道具不可叠加：跳过的不只是 SELF，而是整个 MAGNET 种类 —— 否则一枚
	# 磁石吸来另一枚，那枚到达时再横扫一次全场，一个磁石等于吸两轮。第二枚
	# 磁石必须**不被**吸走。
	var other: PickupItem = _drop(PickupItem.Kind.MAGNET, player.global_position + Vector2(-900, 0))
	await _advance(0.2)
	lone._effect_magnet(player)
	if other._seeking:
		_fail("magnet_stack", "a second magnet was vacuumed — magnets chain and stack")
	elif lone._seeking:
		_fail("magnet_stack", "the magnet attracted itself once another magnet existed")
	else:
		_ok("magnet_stack", "a second magnet is left on the ground (no stacking)")
	await _clear_drops()

# --- Helpers ---

## Instantiate an XP gem at `pos`. Gems are half of what the magnet exists for,
## so the test stages the real node rather than a stand-in.
func _drop_gem(pos: Vector2) -> Node2D:
	var gem: Node2D = GEM_SCENE.instantiate()
	gem.global_position = pos
	get_tree().current_scene.add_child(gem)
	return gem

## Clear every gem and item off the map. The magnet tests count what a sweep
## touches, so leftovers from an earlier test would show up as phantom pulls.
func _clear_drops() -> void:
	for group in PickupItem.MAGNET_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			node.queue_free()
	await _advance(0.2)

## Equip a fusion weapon without running fuse(), so the full-slot setup can
## reach 12 distinct ids. Recipes carry a config path but no scene path — the
## scene always lives at scenes/weapons/<id>.tscn.
func _force_add(id: String) -> void:
	var entry: Dictionary = WeaponDirector.FUSION_RECIPES.get(id, {})
	if entry.is_empty():
		return
	var cfg: Resource = load(String(entry.get("config", "")))
	var scene: PackedScene = load("res://scenes/weapons/%s.tscn" % id) as PackedScene
	if cfg is WeaponConfig and scene:
		WeaponDirector.add_weapon(cfg as WeaponConfig, scene)

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

## Wipe both halves of the shield state. Zeroing only the charges would leave a
## countdown running into the next test and expire it mid-assertion.
func _clear_shield() -> void:
	GameState.shield_charges = 0
	GameState.shield_left = 0.0
	player.hp = player.max_hp

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
