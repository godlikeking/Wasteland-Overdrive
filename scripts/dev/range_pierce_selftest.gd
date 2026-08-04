extends Node2D
## Dev-only self test for projectile range + pierce. Not referenced by the game;
## run it headless:
##
##   godot --headless res://scenes/dev/range_pierce_selftest.tscn
##
## Exits with code 0 on success, 1 if any assertion failed.
##
## Fake enemies are built here rather than instancing scenes/enemy.tscn so the
## test stays independent of navigation, configs and spawn logic. What matters
## is the collision setup: enemies are bodies on the Enemy layer (so a bullet's
## body_entered fires) and enemy projectiles are Areas on that same layer.

const BULLET_SCENE: String = "res://scenes/bullet.tscn"
const ENEMY_LAYER: int = 8      # project.godot layer 4 "Enemy"

@onready var _player: Node2D = $Player

var _failures: int = 0

## Minimal stand-in for Enemy: records the damage it was dealt.
class FakeEnemy extends StaticBody2D:
	var hits: Array[float] = []

	func _init(radius: float = 16.0) -> void:
		collision_layer = ENEMY_LAYER
		collision_mask = 0
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = radius
		shape.shape = circle
		add_child(shape)

	func _ready() -> void:
		add_to_group("enemies")

	func take_damage(amount: float, _hit_dir: Vector2 = Vector2.ZERO) -> void:
		hits.append(amount)

## Stand-in for enemy_projectile.tscn: an Area2D that also sits on the Enemy
## layer but is NOT a valid damage target.
class FakeEnemyBullet extends Area2D:
	func _init(radius: float = 16.0) -> void:
		collision_layer = ENEMY_LAYER
		collision_mask = 0
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = radius
		shape.shape = circle
		add_child(shape)

	func _ready() -> void:
		add_to_group("enemies")   # enemy bullets are in the group too

func _ready() -> void:
	await get_tree().process_frame
	print("=== range/pierce selftest ===")
	await _test_range_despawn()
	await _test_range_not_clipped_by_lifetime()
	await _test_no_pierce_stops_at_first()
	await _test_pierce_with_falloff()
	await _test_same_enemy_hit_once()
	await _test_enemy_bullet_does_not_eat_pierce()
	await _test_targeting_range_cutoff()
	await _test_weapon_holds_fire_out_of_range()
	await _test_homing_survives_target_death()
	print("=== range/pierce selftest failures: %d ===" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

# --- range ---------------------------------------------------------------

## A bullet with max_distance must survive short of it and die past it.
func _test_range_despawn() -> void:
	var t: String = "range_despawn"
	GameState.pierce_count = 0
	var speed: float = 500.0
	var b: Node2D = _spawn_bullet(Vector2.ZERO, Vector2.RIGHT * speed, 10.0, 5.0, 200.0)
	# 200px at 500px/s = 0.4s. Check well before and well after.
	await _wait(0.25)
	if not is_instance_valid(b):
		_fail(t, "bullet died before reaching its 200px range")
		return
	await _wait(0.35)
	if is_instance_valid(b):
		_fail(t, "bullet outlived its 200px range (travelled %.0fpx)" % b._travelled)
		b.queue_free()
		return
	_ok(t, "despawned between 200px and 300px of travel")

## The lifetime passed in must not clip a longer range — setup() stretches it.
func _test_range_not_clipped_by_lifetime() -> void:
	var t: String = "range_beats_lifetime"
	GameState.pierce_count = 0
	var speed: float = 500.0
	# 600px needs 1.2s, but we hand it a 0.3s lifetime on purpose.
	var b: Node2D = _spawn_bullet(Vector2.ZERO, Vector2.RIGHT * speed, 10.0, 0.3, 600.0)
	await _wait(0.6)
	if not is_instance_valid(b):
		_fail(t, "a 0.3s lifetime clipped a 600px range")
		return
	var travelled: float = b._travelled
	b.queue_free()
	if travelled < 250.0:
		_fail(t, "only travelled %.0fpx in 0.6s" % travelled)
		return
	_ok(t, "still alive at %.0fpx despite a 0.3s lifetime" % travelled)

# --- pierce --------------------------------------------------------------

## pierce_count = 0 → the bullet stops on the first enemy.
func _test_no_pierce_stops_at_first() -> void:
	var t: String = "no_pierce"
	GameState.pierce_count = 0
	var enemies: Array = _line_of_enemies(3, 60.0)
	var b: Node2D = _spawn_bullet(Vector2.ZERO, Vector2.RIGHT * 400.0, 10.0, 5.0, 0.0)
	await _wait(0.8)
	var hit_counts: Array = []
	for e in enemies:
		hit_counts.append((e as FakeEnemy).hits.size())
	if is_instance_valid(b):
		b.queue_free()
	if hit_counts != [1, 0, 0]:
		_fail(t, "expected hits [1,0,0], got %s" % [hit_counts])
	else:
		_ok(t, "stopped on the first enemy")
	_clear_enemies()

## pierce_count = 2 → three enemies hit, damage decaying by 0.8 each time.
func _test_pierce_with_falloff() -> void:
	var t: String = "pierce_falloff"
	GameState.pierce_count = 2
	var enemies: Array = _line_of_enemies(4, 60.0)
	var base: float = 100.0
	# Force crit off so the damage sequence is deterministic.
	var saved_crit: float = GameState.crit_rate
	GameState.crit_rate = 0.0
	var b: Node2D = _spawn_bullet(Vector2.ZERO, Vector2.RIGHT * 400.0, base, 5.0, 0.0)
	await _wait(1.0)
	GameState.crit_rate = saved_crit
	if is_instance_valid(b):
		b.queue_free()
	var got: Array = []
	for e in enemies:
		for h in (e as FakeEnemy).hits:
			got.append(snappedf(h, 0.01))
	var want: Array = [100.0, 80.0, 64.0]
	if got != want:
		_fail(t, "expected damage %s, got %s" % [want, got])
	elif (enemies[3] as FakeEnemy).hits.size() != 0:
		_fail(t, "4th enemy was hit despite only 2 pierces")
	else:
		_ok(t, "hit 3 enemies for %s, stopped before the 4th" % [got])
	_clear_enemies()

## One enemy must only ever be damaged once by the same bullet, even if
## body_entered fires again. Enemies have no i-frames to fall back on.
func _test_same_enemy_hit_once() -> void:
	var t: String = "hit_dedupe"
	GameState.pierce_count = 5
	var e := FakeEnemy.new(16.0)
	add_child(e)
	e.global_position = Vector2(100, 0)
	await get_tree().process_frame
	var b: Node2D = _spawn_bullet(Vector2.ZERO, Vector2.RIGHT * 200.0, 10.0, 5.0, 0.0)
	await get_tree().physics_frame
	# Replay the signal by hand — same node, same bullet.
	if is_instance_valid(b):
		b._try_hit(e)
		b._try_hit(e)
		b._try_hit(e)
	await _wait(0.6)
	var n: int = e.hits.size()
	var pierce_left: int = b.pierce_left if is_instance_valid(b) else -1
	if is_instance_valid(b):
		b.queue_free()
	if n != 1:
		_fail(t, "one enemy took %d hits from a single bullet" % n)
	elif pierce_left != 4:
		_fail(t, "repeat hits spent extra pierces (pierce_left=%d, want 4)" % pierce_left)
	else:
		_ok(t, "repeat contacts ignored, 1 pierce spent")
	_clear_enemies()

## Enemy projectiles ride the Enemy collision layer, so area_entered fires for
## them. They must not consume a pierce.
func _test_enemy_bullet_does_not_eat_pierce() -> void:
	var t: String = "enemy_fire_no_pierce"
	GameState.pierce_count = 2
	var eb := FakeEnemyBullet.new(20.0)
	add_child(eb)
	eb.global_position = Vector2(100, 0)
	await get_tree().process_frame
	var b: Node2D = _spawn_bullet(Vector2.ZERO, Vector2.RIGHT * 300.0, 10.0, 5.0, 0.0)
	await _wait(0.7)
	if not is_instance_valid(b):
		_fail(t, "bullet was destroyed by an enemy projectile")
		_clear_enemies()
		return
	var pierce_left: int = b.pierce_left
	b.queue_free()
	if pierce_left != 2:
		_fail(t, "flying through enemy fire spent a pierce (pierce_left=%d, want 2)" % pierce_left)
	else:
		_ok(t, "enemy projectile ignored, pierces intact")
	_clear_enemies()

# --- targeting -----------------------------------------------------------

## _find_nearest_enemy(max_range) must ignore anything past the cutoff.
func _test_targeting_range_cutoff() -> void:
	var t: String = "targeting_cutoff"
	var far := FakeEnemy.new()
	add_child(far)
	far.global_position = _player.global_position + Vector2(400, 0)
	await get_tree().process_frame
	var w: BaseWeapon = _make_weapon("bullet_volley")
	if w == null:
		_fail(t, "could not build bullet_volley")
		_clear_enemies()
		return
	var out_of_range: Node2D = w._find_nearest_enemy(300.0)
	var in_range: Node2D = w._find_nearest_enemy(500.0)
	var unlimited: Node2D = w._find_nearest_enemy()
	w.queue_free()
	if out_of_range != null:
		_fail(t, "a 400px enemy was returned for a 300px range")
	elif in_range != far:
		_fail(t, "a 400px enemy was missed at a 500px range")
	elif unlimited != far:
		_fail(t, "the no-arg call stopped finding distant enemies")
	else:
		_ok(t, "300px misses / 500px hits / no-arg unlimited")
	_clear_enemies()

## The starter weapon must hold fire when nothing is inside its range, and
## its range must come from the config scaled by weapon_range_mult.
func _test_weapon_holds_fire_out_of_range() -> void:
	var t: String = "hold_fire"
	var w: BaseWeapon = _make_weapon("bullet_volley")
	if w == null:
		_fail(t, "could not build bullet_volley")
		return
	if not is_equal_approx(w.get_range(), 420.0):
		_fail(t, "expected 420px base range, got %.1f" % w.get_range())
	GameState.weapon_range_mult = 1.25
	if not is_equal_approx(w.get_range(), 525.0):
		_fail(t, "range upgrade not applied: got %.1f, want 525" % w.get_range())
	GameState.weapon_range_mult = 1.0

	# Enemy well beyond 420px — firing must produce no bullets.
	var far := FakeEnemy.new()
	add_child(far)
	far.global_position = _player.global_position + Vector2(900, 0)
	await get_tree().process_frame
	var before: int = _count_bullets()
	w._fire()
	await get_tree().process_frame
	var after: int = _count_bullets()
	if after != before:
		_fail(t, "fired at an enemy 900px away (range 420)")
	else:
		# Now move it inside range and confirm it does fire.
		far.global_position = _player.global_position + Vector2(200, 0)
		await get_tree().process_frame
		w._fire()
		await get_tree().process_frame
		if _count_bullets() <= before:
			_fail(t, "held fire at an enemy 200px away (range 420)")
		else:
			_ok(t, "silent at 900px, fires at 200px")
	w.queue_free()
	_clear_enemies()
	_clear_bullets()

# --- homing --------------------------------------------------------------

## A homing dart whose target dies mid-flight must notice and re-acquire.
## `_is_valid_target` used to declare a statically typed `Node2D` parameter, and
## Godot 4 rejects a freed reference at a typed Object parameter *before* the body
## runs — so the guard meant to detect a dead target was itself the thing that
## broke on one, spamming "previously freed ... is not a subclass of the expected
## argument class" every physics frame for the rest of the dart's flight.
func _test_homing_survives_target_death() -> void:
	var t: String = "homing_target_freed"
	GameState.pierce_count = 0
	_clear_enemies()
	_clear_bullets()
	var near := FakeEnemy.new(14.0)
	add_child(near)
	near.global_position = Vector2(160, 0)
	var far := FakeEnemy.new(14.0)
	add_child(far)
	far.global_position = Vector2(700, -260)
	# Generous range so the dart cannot despawn out from under the assertions.
	var b: Node2D = _spawn_bullet(Vector2.ZERO, Vector2.RIGHT * 300.0, 10.0, 5.0, 4000.0)
	b.set_homing(5.0)
	await _wait(0.05)
	if b._homing_target != near:
		_fail(t, "dart locked onto %s, expected the nearer enemy" % [b._homing_target])
		_clear_enemies()
		_clear_bullets()
		return

	# free(), not queue_free(): the reported error needs a genuinely freed object,
	# not one that is merely queued and still passes is_instance_valid.
	near.free()
	# Two physics frames is well under RETARGET_INTERVAL (0.12s), so the timer
	# cannot be what moves the dart off its dead target — only the validity guard.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_instance_valid(b):
		_fail(t, "dart despawned when its target was freed")
		_clear_enemies()
		return
	if b._homing_target != far:
		_fail(t, "dart held a freed target instead of re-acquiring (target=%s)" % [b._homing_target])
		_clear_enemies()
		_clear_bullets()
		return
	# The precise regression: a failed typed-argument check returns null, so
	# comparing against false distinguishes "returned false" from "never ran".
	var verdict: Variant = b._is_valid_target(near)
	if verdict != false:
		_fail(t, "_is_valid_target(freed) returned %s, want false" % [verdict])
		_clear_enemies()
		_clear_bullets()
		return
	_ok(t, "re-acquired within one frame of its target being freed")
	_clear_enemies()
	_clear_bullets()

# --- helpers -------------------------------------------------------------

func _spawn_bullet(pos: Vector2, vel: Vector2, dmg: float, life: float, range_px: float) -> Node2D:
	var ps: PackedScene = ResourceLoader.load(BULLET_SCENE) as PackedScene
	var b: Node2D = ps.instantiate() as Node2D
	add_child(b)
	b.global_position = pos
	b.setup(vel, dmg, life, range_px)
	return b

## N enemies in a row along +X starting at `spacing`.
func _line_of_enemies(n: int, spacing: float) -> Array:
	var out: Array = []
	for i in range(n):
		var e := FakeEnemy.new(14.0)
		add_child(e)
		e.global_position = Vector2(spacing * float(i + 1), 0)
		out.append(e)
	return out

func _make_weapon(weapon_id: String) -> BaseWeapon:
	var entry: Dictionary = WeaponDirector.WEAPON_CATALOG.get(weapon_id, {})
	if entry.is_empty():
		return null
	var cfg: Resource = ResourceLoader.load(entry.get("config", ""))
	var scene: PackedScene = ResourceLoader.load(entry.get("scene", "")) as PackedScene
	if not (cfg is WeaponConfig) or scene == null:
		return null
	var w: BaseWeapon = scene.instantiate() as BaseWeapon
	_player.add_child(w)
	# Same runtime ref injection the director does, so projectile_scene is set.
	WeaponDirector._inject_runtime_refs((cfg as WeaponConfig).id, cfg as WeaponConfig)
	w.setup(cfg as WeaponConfig, 1)
	return w

func _count_bullets() -> int:
	var n: int = 0
	for c in get_children():
		if c is Area2D and c.has_method("setup") and "pierce_left" in c:
			n += 1
	for c in get_tree().current_scene.get_children():
		if c is Area2D and c.has_method("setup") and "pierce_left" in c:
			n += 1
	return n

func _clear_bullets() -> void:
	for c in get_tree().current_scene.get_children():
		if c is Area2D and "pierce_left" in c:
			c.queue_free()

func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _ok(test_name: String, msg: String) -> void:
	print("  OK   %-22s %s" % [test_name, msg])

func _fail(test_name: String, msg: String) -> void:
	_failures += 1
	printerr("  FAIL %-22s %s" % [test_name, msg])
