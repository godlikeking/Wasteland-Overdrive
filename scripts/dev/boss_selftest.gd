extends Node2D
## Headless self-test for the boss encounter and the difficulty ceilings.
##   godot --headless res://scenes/dev/boss_selftest.tscn
## Exits 0 when green, 1 when any check fails.
##
## The boss lands at 5 minutes, which no headless test can afford to wait for, so
## `GameState.time_alive` is set by hand — the director reads it fresh every
## frame, and `is_running` is left false so nothing else moves the clock. That
## also makes the countdown assertions exact instead of timing-dependent.
##
## Covers: the spawn ceilings that made t=300 unreachable, the boss arriving on
## schedule, the countdown firing once per second, the health/phase and death
## signals the HUD bar hangs off, the off-screen arrow geometry, the claw wedge
## and its locked facing, the dash's locked line and single hit, the poison
## pool's DoT channel, and the values the SHIPPED game.tscn hands the director.

const BOSS_MARKER: GDScript = preload("res://scripts/ui/boss_marker.gd")

var _failures: int = 0

@onready var player: CharacterBody2D = $Player
@onready var director: Node2D = $SpawnDirector

func _ready() -> void:
	await get_tree().process_frame
	print("=== boss selftest ===")
	# Enemies walk at the player and a dead player would reset the run mid-test.
	player.max_hp = 100000.0
	player.hp = player.max_hp
	await _test_burst_cap()
	await _test_spawn_rate_ceiling()
	await _test_shipped_scene_ceilings()
	await _test_live_enemy_cap()
	await _test_boss_warning()
	await _test_boss_spawn()
	await _test_claw_geometry()
	await _test_claw_locks_facing()
	await _test_dash_machine()
	await _test_boss_health_signals()
	await _test_poison_pool_dot()
	await _test_poison_bypasses_shield()
	await _test_dot_no_hit_stop()
	await _test_marker_geometry()
	print("=== boss selftest failures: %d ===" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

# --- Difficulty ceilings ------------------------------------------------

## `burst_for` is the reason the 5-minute boss was unreachable: uncapped, it
## reached 7 spawns per tick at t=300. Pure, so the whole curve is checked here
## without playing five minutes of game.
func _test_burst_cap() -> void:
	var cap: int = director.max_burst
	if director.burst_for(0.0) != 1:
		_fail("burst", "t=0 should start at 1 spawn, got %d" % director.burst_for(0.0))
	else:
		_ok("burst", "starts at 1 spawn per tick")
	# The uncapped formula at t=300; the cap must actually bite there.
	var uncapped: int = 1 + int(300.0 * director.burst_growth)
	if uncapped <= cap:
		_fail("burst", "test is vacuous: uncapped t=300 burst (%d) is already <= cap (%d)" % [uncapped, cap])
	elif director.burst_for(300.0) != cap:
		_fail("burst", "t=300 burst %d, expected the cap %d" % [director.burst_for(300.0), cap])
	else:
		_ok("burst", "t=300 clamped to %d (uncapped would be %d)" % [cap, uncapped])
	# And it must never climb again, however long the run gets.
	var over: Array[float] = [600.0, 1800.0, 36000.0]
	var bad: Array[String] = []
	for t in over:
		if director.burst_for(t) > cap:
			bad.append("t=%.0f->%d" % [t, director.burst_for(t)])
	if bad.is_empty():
		_ok("burst", "stays at the cap out to t=36000")
	else:
		_fail("burst", "burst grew past the cap: %s" % ", ".join(bad))
	# Monotonic on the way up, or the ramp has a hole in it.
	var prev: int = 0
	for i in range(0, 400, 10):
		var b: int = director.burst_for(float(i))
		if b < prev:
			_fail("burst", "burst decreased at t=%d (%d -> %d)" % [i, prev, b])
			return
		prev = b
	_ok("burst", "never decreases as the run goes on")

## The number that actually decides whether the late game is playable: burst
## divided by interval. This is the assertion that would have caught the original
## bug, since neither knob looks wrong on its own.
func _test_spawn_rate_ceiling() -> void:
	var worst: float = float(director.max_burst) / maxf(0.01, director.min_interval)
	# 20/s is already frantic; the broken curve sat at ~39/s.
	if worst > 20.0:
		_fail("rate", "peak spawn rate %.1f/s (burst %d / interval %.2fs) is past the 20/s ceiling" % [
			worst, director.max_burst, director.min_interval])
	else:
		_ok("rate", "peak spawn rate is %.1f/s (burst %d every %.2fs)" % [
			worst, director.max_burst, director.min_interval])

## The same ceiling, but read off the SHIPPED scene instead of a script-built
## director. Every other test here builds the director from the script, so a
## property override in game.tscn is invisible to them — and one was: the scene
## carried `min_interval = 0.18` while the script said 0.25, so the real game ran
## at 22/s while this whole file went green at 16/s.
##
## `PackedScene.get_state()` reads the overrides without instantiating the world,
## so this stays a cheap assertion rather than a second full game boot. It guards
## ANY scene-vs-script divergence on these knobs, not just the one that bit.
func _test_shipped_scene_ceilings() -> void:
	var packed: PackedScene = load("res://scenes/game.tscn") as PackedScene
	if packed == null:
		_fail("shipped", "could not load res://scenes/game.tscn")
		return
	var st: SceneState = packed.get_state()
	var idx: int = -1
	for i in range(st.get_node_count()):
		if String(st.get_node_name(i)) == "SpawnDirector":
			idx = i
			break
	if idx < 0:
		_fail("shipped", "game.tscn has no SpawnDirector node — the shipped cadence is unguarded")
		return
	var overrides: Dictionary = {}
	for p in range(st.get_node_property_count(idx)):
		overrides[String(st.get_node_property_name(idx, p))] = st.get_node_property_value(idx, p)
	# Script default unless the scene overrides it: that pair IS the effective value.
	#
	# Defaults come from a THROWAWAY instance of the script, not from `director` —
	# this scene overrides boss_spawn_time to 99999 and the cap tests rewrite
	# min_interval, so reading the live node would compare game.tscn against the
	# test harness instead of against the script.
	var defaults: Node = (load("res://scripts/spawn_director.gd") as GDScript).new()
	var burst: int = int(overrides.get("max_burst", defaults.max_burst))
	var interval: float = float(overrides.get("min_interval", defaults.min_interval))
	var boss_t: float = float(overrides.get("boss_spawn_time", defaults.boss_spawn_time))
	defaults.free()
	var worst: float = float(burst) / maxf(0.01, interval)
	if worst > 20.0:
		_fail("shipped", "game.tscn ships %.1f/s (max_burst %d / min_interval %.2fs), past the 20/s ceiling" % [
			worst, burst, interval])
	else:
		_ok("shipped", "game.tscn ships %.1f/s (max_burst %d every %.2fs)" % [worst, burst, interval])
	# And the shipped boss time has to be a real number the run can reach.
	if boss_t <= 0.0 or boss_t > 600.0:
		_fail("shipped", "game.tscn ships boss_spawn_time %.0fs, outside a reachable 0-600s" % boss_t)
	else:
		_ok("shipped", "game.tscn ships boss_spawn_time %.0fs" % boss_t)

## The population ceiling, exercised through the real cadence rather than the
## formula: the guard sits in `_process`, so only running it proves it is wired.
func _test_live_enemy_cap() -> void:
	await _clear_enemies()
	var cap: int = 8
	director.max_live_enemies = cap
	director.base_interval = 0.05
	director.min_interval = 0.05
	GameState.time_alive = 300.0   # deep into the ramp: maximum burst
	var peak: int = 0
	var t: float = 0.0
	while t < 2.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		peak = maxi(peak, director.live_enemies())
	# A burst is decided before it is spawned, so the population can overshoot by
	# at most one burst minus the one that fit under the cap.
	var allowed: int = cap + director.max_burst - 1
	if peak > allowed:
		_fail("live_cap", "%d enemies alive, ceiling is %d (+%d burst overshoot)" % [peak, cap, director.max_burst - 1])
	elif peak < cap:
		_fail("live_cap", "only %d enemies ever spawned — the cadence never reached the %d ceiling, so the guard is untested" % [peak, cap])
	else:
		_ok("live_cap", "population held at %d with a ceiling of %d" % [peak, cap])
	director.base_interval = 9999.0
	GameState.time_alive = 0.0
	await _clear_enemies()

# --- Boss ---------------------------------------------------------------

## The countdown has to speak once per remaining second — not once per frame (60
## banners a second) and not outside the warning window.
func _test_boss_warning() -> void:
	director.boss_spawn_time = 100.0
	director.boss_warn_lead = 6.0
	director._boss_spawned = false
	director._boss_warn_shown = -1
	var seen: Array[float] = []
	var on_incoming: Callable = func(s: float) -> void: seen.append(s)
	GameState.boss_incoming.connect(on_incoming)

	# Outside the window: silence, however many frames pass.
	GameState.time_alive = 90.0   # 10s out, lead is 6s
	await _frames(5)
	if not seen.is_empty():
		_fail("boss_warn", "announced %ds before the window opened" % seen.size())
		GameState.boss_incoming.disconnect(on_incoming)
		return
	_ok("boss_warn", "silent while the boss is further out than the %.0fs lead" % director.boss_warn_lead)

	# Inside the window, several frames on the SAME whole second: exactly one.
	GameState.time_alive = 94.5   # 5.5s left -> ceil 6
	await _frames(6)
	if seen.size() != 1:
		_fail("boss_warn", "%d announcements for one second of countdown" % seen.size())
	else:
		_ok("boss_warn", "one announcement per second, not one per frame")

	# Crossing into the next whole second speaks again.
	GameState.time_alive = 95.2   # 4.8s left -> ceil 5
	await _frames(3)
	if seen.size() != 2:
		_fail("boss_warn", "crossing a second boundary gave %d total announcements, expected 2" % seen.size())
	else:
		_ok("boss_warn", "each second boundary announces once more")
	GameState.boss_incoming.disconnect(on_incoming)
	GameState.time_alive = 0.0

## The original bug report: the boss never showed up. It always did spawn once
## the clock got there — this pins the schedule so a future tuning pass to the
## ceilings can't quietly break the arrival.
func _test_boss_spawn() -> void:
	await _clear_enemies()
	director.boss_spawn_time = 60.0
	director._boss_spawned = false
	director._boss_warn_shown = -1
	var got: Array[Node2D] = []
	var on_spawn: Callable = func(b: Node2D) -> void: got.append(b)
	GameState.boss_spawned.connect(on_spawn)

	# One second short: still nothing, so the assertion below can't pass by
	# accident on an already-spawned boss.
	GameState.time_alive = 59.0
	await _frames(3)
	if not got.is_empty():
		_fail("boss_spawn", "boss arrived early (t=%.0f, scheduled %.0f)" % [GameState.time_alive, director.boss_spawn_time])
		GameState.boss_spawned.disconnect(on_spawn)
		return
	_ok("boss_spawn", "no boss before the scheduled time")

	GameState.time_alive = 60.1
	await _frames(3)
	GameState.boss_spawned.disconnect(on_spawn)
	if got.size() != 1:
		_fail("boss_spawn", "boss_spawned fired %d times, expected once" % got.size())
		return
	var boss: Node2D = got[0]
	if boss == null or not is_instance_valid(boss):
		_fail("boss_spawn", "boss_spawned carried a dead node")
		return
	if not boss.is_inside_tree():
		_fail("boss_spawn", "boss_spawned fired before the node was in the tree — the HUD bar and the arrow would both attach to nothing")
		return
	_ok("boss_spawn", "boss spawned once, in the tree, and the signal carries it")
	if _find_boss() == null:
		_fail("boss_spawn", "the spawned boss is not a BOSS-behaviour enemy")
	else:
		_ok("boss_spawn", "spawned enemy has BOSS behaviour")

	# Once per run: the clock ticking past the time again must not spawn a second.
	# Counted in an Array because a lambda captures an int BY VALUE — an
	# `again += 1` on a local int would increment a copy and always read 0.
	var again: Array[Node2D] = []
	var on_again: Callable = func(b: Node2D) -> void: again.append(b)
	GameState.boss_spawned.connect(on_again)
	GameState.time_alive = 400.0
	await _frames(5)
	GameState.boss_spawned.disconnect(on_again)
	GameState.time_alive = 0.0
	if not again.is_empty():
		_fail("boss_spawn", "%d more bosses spawned later in the run" % again.size())
	else:
		_ok("boss_spawn", "only one boss per run")

## The HUD bar is driven entirely by these two signals, so a boss that takes
## damage without emitting them is a bar frozen at full health.
func _test_boss_health_signals() -> void:
	var boss: Node2D = _find_boss()
	if boss == null:
		_fail("boss_hp", "no boss on the field to damage")
		return
	var fracs: Array[float] = []
	var phases: Array[int] = []
	var on_state: Callable = func(f: float, p: int) -> void:
		fracs.append(f)
		phases.append(p)
	GameState.boss_state_changed.connect(on_state)

	var max_hp: float = float(boss.config.max_hp)
	boss.take_damage(max_hp * 0.25)
	await _frames(2)
	if fracs.is_empty():
		_fail("boss_hp", "damage emitted no boss_state_changed — the bar would never move")
		GameState.boss_state_changed.disconnect(on_state)
		return
	if absf(fracs[0] - 0.75) > 0.02:
		_fail("boss_hp", "reported %.3f of max hp after a 25%% hit" % fracs[0])
	else:
		_ok("boss_hp", "damage reports the hp fraction (%.2f)" % fracs[0])

	# Down into phase 2: the bar's phase label comes off the same signal.
	boss.take_damage(max_hp * 0.3)
	await _frames(4)
	var last_phase: int = phases[phases.size() - 1]
	if last_phase < 2:
		_fail("boss_hp", "still phase %d at %.0f%% hp (phase 2 starts at %.0f%%)" % [
			last_phase, fracs[fracs.size() - 1] * 100.0, boss.config.boss_phase2_hp_frac * 100.0])
	else:
		_ok("boss_hp", "phase change is reported (now phase %d)" % last_phase)
	# Monotonically down: an increasing fraction means the bar would jump back up.
	var rose: bool = false
	for i in range(1, fracs.size()):
		if fracs[i] > fracs[i - 1] + 0.001:
			rose = true
	if rose:
		_fail("boss_hp", "reported fraction went back up: %s" % str(fracs))
	else:
		_ok("boss_hp", "reported fraction only ever falls (%d samples)" % fracs.size())
	GameState.boss_state_changed.disconnect(on_state)

	# Death has to tear the bar and the arrow down, or both outlive the boss.
	# Array accumulator again: an int captured by a lambda is a copy.
	var dead: Array[int] = []
	var on_dead: Callable = func() -> void: dead.append(1)
	GameState.boss_defeated.connect(on_dead)
	boss.take_damage(max_hp)
	await _frames(3)
	GameState.boss_defeated.disconnect(on_dead)
	if dead.size() != 1:
		_fail("boss_hp", "boss_defeated fired %d times on death, expected once" % dead.size())
	else:
		_ok("boss_hp", "death emits boss_defeated once")
	await _clear_enemies()

# --- Claw ---------------------------------------------------------------

## `ClawSlash.in_arc` is the entire claw hit test; the node around it only draws.
## Checked as a pure function because a `_draw` result cannot be read back
## headlessly — same reason `marker_for` is factored out.
func _test_claw_geometry() -> void:
	var from := Vector2.ZERO
	var facing := Vector2.RIGHT
	var reach: float = 100.0
	var arc: float = PI / 2.0        # ±45°
	var bad: Array[String] = []

	# Straight ahead, well inside: the plain hit.
	if not ClawSlash.in_arc(from, facing, Vector2(50, 0), reach, arc):
		bad.append("dead ahead at half reach missed")
	# Past the reach: the claw has a length, or it is a screen-wide attack.
	if ClawSlash.in_arc(from, facing, Vector2(150, 0), reach, arc):
		bad.append("target 1.5x past reach was hit")
	# Behind: the wedge has a direction, or facing means nothing.
	if ClawSlash.in_arc(from, facing, Vector2(-50, 0), reach, arc):
		bad.append("target directly behind was hit")
	# Straight to the side is 90°, outside a ±45° wedge.
	if ClawSlash.in_arc(from, facing, Vector2(0, 50), reach, arc):
		bad.append("target at 90° was inside a ±45° wedge")
	# Both sides of the arc edge: the boundary has to be where the arc says.
	if not ClawSlash.in_arc(from, facing, Vector2(50, 48), reach, arc):
		bad.append("target at ~44° (just inside the edge) missed")
	if ClawSlash.in_arc(from, facing, Vector2(50, 52), reach, arc):
		bad.append("target at ~46° (just outside the edge) was hit")
	# Symmetric: a wedge that only reaches one way would be a directional bug
	# invisible in play (the boss turns to face you anyway).
	if not ClawSlash.in_arc(from, facing, Vector2(50, -48), reach, arc):
		bad.append("the wedge is not symmetric about the facing axis")
	# A full-circle arc hits anything within reach; this is the path a config of
	# arc = TAU takes, and it must not fold back to "nothing".
	if not ClawSlash.in_arc(from, facing, Vector2(-50, 0), reach, TAU):
		bad.append("arc = TAU did not hit a target behind")
	# Degenerate inputs must answer, not crash or return NaN-driven nonsense.
	if ClawSlash.in_arc(from, Vector2.ZERO, Vector2(10, 0), reach, arc):
		bad.append("a zero-length facing still hit something")
	if not ClawSlash.in_arc(from, facing, from, reach, arc):
		bad.append("a target exactly on the origin missed")

	if bad.is_empty():
		_ok("claw_geometry", "the wedge respects reach, direction, arc edges and degenerate input")
	else:
		_fail("claw_geometry", "; ".join(bad))

## The claw locks its facing when the wind-up STARTS. That lock is the whole
## counterplay: stepping sideways during the 0.45s tell is how the attack is
## dodged. If the facing tracked the player per frame the claw would be an
## unavoidable tax, and `in_arc` would be untestable in isolation.
##
## Driven by calling `_boss_claw` directly rather than by awaiting frames: no
## physics runs between the wind-up and the strike, so contact damage and the
## swamp cannot pollute the hp reading.
func _test_claw_locks_facing() -> void:
	var boss: Node2D = _find_boss()
	if boss == null:
		_fail("claw_lock", "no boss on the field to swing")
		return
	var cfg: EnemyConfig = boss.config as EnemyConfig
	boss.global_position = Vector2.ZERO
	boss._player = player

	# 1) Standing still in front: the claw connects, or the rest is vacuous.
	_ready_player_for_hit()
	player.global_position = Vector2(cfg.boss_claw_reach * 0.5, 0.0)
	boss._claw_accum = cfg.boss_claw_cooldown
	boss._boss_claw(0.0)                       # starts the wind-up, locks facing
	if boss._claw_wind_left <= 0.0:
		_fail("claw_lock", "a player inside reach did not start a wind-up")
		return
	var before: float = player.hp
	boss._boss_claw(cfg.boss_claw_windup)      # wind-up elapses -> strike
	var dealt: float = before - player.hp
	if absf(dealt - cfg.boss_claw_damage) > 0.01:
		_fail("claw_lock", "a standing target took %.1f, expected the claw's %.1f" % [dealt, cfg.boss_claw_damage])
		return
	_ok("claw_lock", "the claw connects for %.0f on a target that stands still" % cfg.boss_claw_damage)

	# 2) Same wind-up, but the player steps to the far side: the LOCKED facing
	# must miss. Position is changed after the wind-up begins, which is exactly
	# what a player does during the tell.
	_ready_player_for_hit()
	player.global_position = Vector2(cfg.boss_claw_reach * 0.5, 0.0)
	boss._claw_accum = cfg.boss_claw_cooldown
	boss._boss_claw(0.0)
	player.global_position = Vector2(-cfg.boss_claw_reach * 0.5, 0.0)   # behind
	var before2: float = player.hp
	boss._boss_claw(cfg.boss_claw_windup)
	if player.hp < before2 - 0.01:
		_fail("claw_lock", "stepping behind the locked facing still took %.1f — the claw tracks the player and cannot be dodged" % (before2 - player.hp))
	else:
		_ok("claw_lock", "stepping out of the locked wedge during the wind-up dodges the claw")

	# 3) A target beyond reach never even starts a wind-up, so the boss does not
	# root itself across the arena for an attack that cannot land.
	_ready_player_for_hit()
	player.global_position = Vector2(cfg.boss_claw_reach * 3.0, 0.0)
	boss._claw_accum = cfg.boss_claw_cooldown
	boss._claw_wind_left = 0.0
	boss._boss_claw(0.0)
	if boss._claw_wind_left > 0.0:
		_fail("claw_lock", "the boss wound up at 3x the claw reach")
	else:
		_ok("claw_lock", "no wind-up against a target beyond reach")
	boss._claw_wind_left = 0.0
	player.global_position = Vector2.ZERO

# --- Dash ----------------------------------------------------------------

## The dash fills the mid range (220-480px): outside the claw's wedge but too
## close to just walk. Like the claw, the DIRECTION locks when the wind-up
## starts — a straight-line charge only connects if the player stands in the
## line, so stepping sideways is the whole dodge.
##
## Unlike the claw test, THIS one moves the boss through physics
## (`move_and_collide`), so two things are different:
## - The boss's own `_physics_process` is disabled: it would run `_behavior_boss`
##   on real frames (navigation, summons, poison) and pollute the reading.
## - Every player teleport that precedes boss motion is followed by a couple of
##   real physics frames. Teleports alone never reach the physics server, and a
##   dash into a stale "ghost" body reads as a bogus collision — that is exactly
##   the 209px/25px drift this test caught on its first run.
## Fake deltas still drive the machine, so the player's InvulnTimer cannot tick
## and every hp delta stays exact.
func _test_dash_machine() -> void:
	var boss: Node2D = _find_boss()
	if boss == null:
		_fail("dash", "no boss on the field to dash")
		return
	var cfg: EnemyConfig = boss.config as EnemyConfig
	boss.set_physics_process(false)
	boss.global_position = Vector2.ZERO
	boss._player = player
	# Fresh machine: the claw test left teleports and zeroed timers behind.
	boss._dash_accum = 0.0
	boss._dash_wind_left = 0.0
	boss._dash_run_left = 0.0
	boss._dash_recover_left = 0.0
	# Clear the origin first: the claw test's last act parked the player ON the
	# boss. Sync the server before anything moves.
	player.global_position = Vector2(400.0, 0.0)
	await _physics_frames(2)

	# 1) Wind-up: mid range + cooldown ready -> telegraph spawns, direction
	#    locks, and the boss does NOT move (rooting IS the tell).
	_ready_player_for_hit()
	player.global_position = Vector2(400.0, 0.0)
	await _physics_frames(2)
	boss._dash_accum = cfg.boss_dash_cooldown
	boss._boss_dash(0.0)
	if boss._dash_wind_left <= 0.0:
		_fail("dash", "a player at 300px did not start a wind-up")
		return
	if boss._dash_facing.distance_to(Vector2.RIGHT) > 0.01:
		_fail("dash", "locked facing is %s, expected (1, 0)" % str(boss._dash_facing))
		return
	if boss._dash_fx == null:
		_fail("dash", "no dash telegraph spawned")
		return
	var pos0: Vector2 = boss.global_position
	boss._boss_dash(cfg.boss_dash_windup * 0.5)
	if boss.global_position != pos0:
		_fail("dash", "the boss moved during the wind-up")
		return
	_ok("dash", "wind-up roots the boss, locks the direction, spawns the telegraph")

	# 2) The dash is a STRAIGHT LINE along the locked facing. Player steps off
	#    the line by 220px (perpendicular): the boss covers the full distance
	#    without deviating and without landing a hit. The player also moves to
	#    the far side MID-dash — if the charge re-aimed per frame it would end
	#    somewhere else entirely and this assertion would fail.
	_ready_player_for_hit()
	player.global_position = Vector2(0.0, 400.0)
	await _physics_frames(2)
	var before: float = player.hp
	boss._boss_dash(cfg.boss_dash_windup)        # wind-up elapses -> dash starts
	if boss._dash_run_left <= 0.0:
		_fail("dash", "the dash did not start when the wind-up elapsed")
		return
	var start: Vector2 = boss.global_position
	var t: float = cfg.boss_dash_duration
	var step: float = 0.05
	while t > 0.0001:
		var d: float = minf(step, t)
		boss._boss_dash(d)
		t -= d
		if absf(t - cfg.boss_dash_duration * 0.5) < step * 0.5:
			player.global_position = Vector2(0.0, -500.0)   # dart across mid-dash
	var disp: Vector2 = boss.global_position - start
	var expect: Vector2 = Vector2.RIGHT * (cfg.boss_dash_speed * cfg.boss_dash_duration)
	if disp.distance_to(expect) > 1.0:
		_fail("dash", "dashed %s, expected the locked line %s (%.0fpx)" % [str(disp), str(expect), expect.length()])
		return
	if absf(player.hp - before) > 0.01:
		_fail("dash", "a player 220px off the line took %.1f damage" % (before - player.hp))
		return
	if boss._dash_run_left > 0.0 or boss._dash_recover_left <= 0.0:
		_fail("dash", "the dash did not end in recovery")
		return
	_ok("dash", "%.0fpx straight along the locked line, 0 damage to an off-line player" % expect.length())

	# 3) A player standing IN the line gets exactly one hit, and only from the
	#    dash's own damage — not from contact. The wind-up starts with the player
	#    in range, then the player steps INTO the line before it elapses.
	_ready_player_for_hit()
	boss.global_position = Vector2.ZERO   # #2 left the boss at the end of its dash
	player.global_position = Vector2(400.0, 0.0)
	await _physics_frames(2)
	boss._dash_accum = cfg.boss_dash_cooldown
	boss._dash_wind_left = 0.0
	boss._dash_recover_left = 0.0
	boss._boss_dash(0.0)                            # wind-up, facing locked (1,0)
	player.global_position = Vector2(100.0, 0.0)    # step into the line
	await _physics_frames(2)
	var before3: float = player.hp
	boss._boss_dash(cfg.boss_dash_windup)           # wind-up elapses -> dash
	t = cfg.boss_dash_duration
	while t > 0.0001:
		var d3: float = minf(step, t)
		boss._boss_dash(d3)
		t -= d3
	var dealt3: float = before3 - player.hp
	if absf(dealt3 - cfg.boss_dash_damage) > 0.01:
		_fail("dash", "an on-line player took %.1f, expected exactly the dash's %.1f" % [dealt3, cfg.boss_dash_damage])
		return
	if not boss._dash_hit_done:
		_fail("dash", "the dash hit landed but _dash_hit_done was not set")
		return
	_ok("dash", "one hit of %.0f on a player standing in the line" % cfg.boss_dash_damage)

	# 4) Recovery is a root: the boss stays planted while it counts down, then
	#    the machine returns to cooldown.
	if boss._dash_recover_left <= 0.0:
		_fail("dash", "no recovery after the dash ended")
		return
	var pos4: Vector2 = boss.global_position
	var rec: float = boss._dash_recover_left
	boss._boss_dash(rec * 0.5)
	if boss.global_position != pos4:
		_fail("dash", "the boss moved during recovery")
		return
	_ok("dash", "recovery roots the boss for %.2fs" % rec)

	# 5) Cooldown and range gates: too soon, too close (< min), too far (> max)
	#    — none of them may start a wind-up.
	boss.global_position = Vector2.ZERO   # distances are measured from the boss
	boss._dash_accum = 0.0
	boss._dash_wind_left = 0.0
	boss._dash_run_left = 0.0
	boss._dash_recover_left = 0.0         # #4 left 0.175s of recovery
	boss._boss_dash(0.0)
	if boss._dash_wind_left > 0.0:
		_fail("dash", "wound up with the cooldown not ready")
		return
	player.global_position = Vector2(50.0, 0.0)
	boss._dash_accum = cfg.boss_dash_cooldown
	boss._boss_dash(0.0)
	if boss._dash_wind_left > 0.0:
		_fail("dash", "wound up at %dpx, inside the claw's range" % int(cfg.boss_dash_min_range))
		return
	player.global_position = Vector2(700.0, 0.0)
	boss._dash_accum = cfg.boss_dash_cooldown
	boss._boss_dash(0.0)
	if boss._dash_wind_left > 0.0:
		_fail("dash", "wound up at 600px, beyond the max range")
		return
	player.global_position = Vector2(400.0, 0.0)
	boss._dash_accum = cfg.boss_dash_cooldown
	boss._boss_dash(0.0)
	if boss._dash_wind_left <= 0.0:
		_fail("dash", "a player at 300px with the cooldown ready did not wind up")
		return
	_ok("dash", "cooldown and the %d-%dpx range gate the wind-up" % [int(cfg.boss_dash_min_range), int(cfg.boss_dash_max_range)])

	boss._dash_wind_left = 0.0
	boss._dash_run_left = 0.0
	boss._dash_recover_left = 0.0
	boss.set_physics_process(true)
	player.global_position = Vector2.ZERO

# --- Poison -------------------------------------------------------------

## The pool is the only thing in the poison attack that deals damage (the glob in
## flight deliberately does not), and it deals it per tick as `dps * tick` so the
## tick length is granularity, never strength. Ticks are driven by calling
## `_apply_tick` directly: no frames pass, so the swamp component and any enemy
## contact cannot show up in the hp delta.
func _test_poison_pool_dot() -> void:
	await _park_player()
	var pool: PoisonPool = PoisonPool.new()
	pool.setup(100.0, 20.0, 0.5, 6.0)
	add_child(pool)
	pool.global_position = Vector2.ZERO

	# Inside: 4 ticks of 20 dps * 0.5s = 40.
	var before: float = player.hp
	for i in range(4):
		pool._apply_tick()
	var dealt: float = before - player.hp
	if absf(dealt - 40.0) > 0.01:
		_fail("poison_dot", "4 ticks of 20dps x 0.5s dealt %.1f, expected 40" % dealt)
	else:
		_ok("poison_dot", "ticks deal dps x tick (%.0f over 4 ticks)" % dealt)

	# Outside the radius: nothing at all. A pool that leaks damage past its own
	# outline is unreadable — the drawn circle is the player's only information.
	player.global_position = Vector2(140.0, 0.0)    # radius is 100
	var before2: float = player.hp
	for i in range(4):
		pool._apply_tick()
	if player.hp < before2 - 0.01:
		_fail("poison_dot", "a player 40px outside the pool still took %.1f" % (before2 - player.hp))
	else:
		_ok("poison_dot", "no damage outside the drawn radius")

	# The fade curve is what tells the player when the ground is walkable again.
	var bad: Array[String] = []
	pool._age = 0.0
	if pool.alpha_mult() > 0.01:
		bad.append("a brand-new pool starts fully visible instead of fading in")
	pool._age = pool.life * 0.5
	if pool.alpha_mult() < 0.99:
		bad.append("a mid-life pool is not at full opacity")
	pool._age = pool.life
	if pool.alpha_mult() > 0.01:
		bad.append("an expiring pool is still opaque")
	if bad.is_empty():
		_ok("poison_dot", "opacity fades in, holds, and fades out")
	else:
		_fail("poison_dot", "; ".join(bad))
	pool.queue_free()
	player.global_position = Vector2.ZERO
	await _frames(1)

## The DoT channel's defining property. `take_damage` absorbs a whole hit per
## shield charge, so routing a 10-damage poison tick through it would trade one
## charge for 10 damage and evaporate a two-charge shield in one second — a
## shield that makes poison WORSE than no shield. DoT is a separate channel:
## the shield neither blocks it nor is spent by it.
##
## The i-frame half matters just as much: `take_damage` early-returns for 0.4s
## after a hit, which would throttle a 0.25s DoT tick down to 2.5 ticks/sec and
## quietly halve every "high damage" number in the design.
func _test_poison_bypasses_shield() -> void:
	await _park_player()
	GameState.shield_charges = 0
	GameState.shield_left = 0.0
	GameState.add_shield(2, 10.0)
	player.invulnerable = true                    # i-frames wide open too
	var charges_before: int = GameState.shield_charges
	var hp_before: float = player.hp

	var pool: PoisonPool = PoisonPool.new()
	pool.setup(100.0, 20.0, 0.5, 6.0)
	add_child(pool)
	pool.global_position = Vector2.ZERO
	for i in range(3):
		pool._apply_tick()
	var dealt: float = hp_before - player.hp

	if absf(dealt - 30.0) > 0.01:
		_fail("poison_shield", "3 ticks behind a 2-charge shield and full i-frames dealt %.1f, expected 30" % dealt)
	else:
		_ok("poison_shield", "poison ignores the shield and the i-frames (%.0f dealt)" % dealt)
	if GameState.shield_charges != charges_before:
		_fail("poison_shield", "poison spent %d shield charge(s) — a DoT would strip the whole shield in a second" % (charges_before - GameState.shield_charges))
	else:
		_ok("poison_shield", "the shield still has %d charge(s) after 3 poison ticks" % GameState.shield_charges)

	pool.queue_free()
	player.invulnerable = false
	GameState.shield_charges = 0
	GameState.shield_left = 0.0
	GameState.shield_changed.emit(0)
	await _frames(1)

## DoT must not emit `player_hurt`. FxManager answers that signal with
## `request_hit_stop(0.08)`, which sets `Engine.time_scale = 0.05` — so a DoT
## firing it every tick would make the whole game stutter for as long as the
## player stands in the pool.
##
## `player_hurt` is asserted rather than `Engine.time_scale` directly: this scene
## has no FxManager, so time_scale would sit at 1.0 no matter how badly the
## channel misbehaved. The signal is the actual contract; the stutter is only
## its most visible consequence.
func _test_dot_no_hit_stop() -> void:
	await _park_player()
	var hurts: Array[Vector2] = []
	var on_hurt: Callable = func(p: Vector2) -> void: hurts.append(p)
	GameState.player_hurt.connect(on_hurt)

	var pool: PoisonPool = PoisonPool.new()
	pool.setup(100.0, 20.0, 0.5, 6.0)
	add_child(pool)
	pool.global_position = Vector2.ZERO
	for i in range(5):
		pool._apply_tick()
	if not hurts.is_empty():
		_fail("dot_no_hit_stop", "5 poison ticks emitted player_hurt %d times — every one is a 0.08s global hit-stop" % hurts.size())
	else:
		_ok("dot_no_hit_stop", "5 poison ticks emitted no player_hurt")

	# Control: a normal hit MUST still emit it, or the assertion above would pass
	# just as happily on a player that never reports damage at all.
	player.invulnerable = false
	player.take_damage(5.0)
	if hurts.is_empty():
		_fail("dot_no_hit_stop", "take_damage emitted no player_hurt either — the test above proves nothing")
	else:
		_ok("dot_no_hit_stop", "take_damage still emits player_hurt (the hit-stop path is intact)")
	GameState.player_hurt.disconnect(on_hurt)
	pool.queue_free()
	player.invulnerable = false
	await _frames(1)

# --- Off-screen marker --------------------------------------------------

## `marker_for` is the whole arrow: everything else is drawing. Checked as a pure
## function because a Control's `_draw` output cannot be read back headlessly.
func _test_marker_geometry() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var margin: float = 40.0
	var center: Vector2 = rect.get_center()

	# On screen: nothing to point at.
	var on: Dictionary = BOSS_MARKER.marker_for(center, rect, margin)
	if bool(on["offscreen"]):
		_fail("marker", "the screen centre was reported off-screen")
	else:
		_ok("marker", "a target at the centre is not off-screen")

	# The margin is the boundary, and it must be the boundary of the INSET rect —
	# an arrow drawn on the true edge would be half outside the window.
	var just_in: Dictionary = BOSS_MARKER.marker_for(Vector2(rect.end.x - margin - 5.0, center.y), rect, margin)
	var just_out: Dictionary = BOSS_MARKER.marker_for(Vector2(rect.end.x - margin + 5.0, center.y), rect, margin)
	if bool(just_in["offscreen"]) or not bool(just_out["offscreen"]):
		_fail("marker", "the %.0fpx margin is not where the arrow starts (in=%s out=%s)" % [
			margin, str(just_in["offscreen"]), str(just_out["offscreen"])])
	else:
		_ok("marker", "the arrow appears exactly once the target passes the %.0fpx inset" % margin)

	# Cardinal directions: the arrow sits on the inset edge and points outward.
	var cases: Array = [
		["right", Vector2(9000, center.y), 0.0],
		["left", Vector2(-9000, center.y), PI],
		["up", Vector2(center.x, -9000), -PI / 2.0],
		["down", Vector2(center.x, 9000), PI / 2.0],
	]
	var bad: Array[String] = []
	for c in cases:
		var name: String = c[0]
		var m: Dictionary = BOSS_MARKER.marker_for(c[1], rect, margin)
		if not bool(m["offscreen"]):
			bad.append("%s not off-screen" % name)
			continue
		var ang: float = float(m["angle"])
		if absf(angle_difference(ang, float(c[2]))) > 0.01:
			bad.append("%s points at %.2frad, expected %.2frad" % [name, ang, float(c[2])])
		var pos: Vector2 = m["pos"]
		if not _on_inset_edge(pos, rect, margin):
			bad.append("%s sits at %s, off the inset edge" % [name, str(pos)])
	if bad.is_empty():
		_ok("marker", "all 4 cardinal targets put the arrow on the inset edge pointing outward")
	else:
		_fail("marker", "; ".join(bad))

	# The case a naive per-side clamp gets wrong: a diagonal target. The arrow
	# must stay on the ray to the boss, or it points at empty ground.
	var diag_bad: Array[String] = []
	for a in [0.3, 1.1, 2.4, -0.7, -2.9]:
		var target: Vector2 = center + Vector2(6000, 0).rotated(a)
		var m: Dictionary = BOSS_MARKER.marker_for(target, rect, margin)
		var pos: Vector2 = m["pos"]
		var to_arrow: Vector2 = pos - center
		if absf(angle_difference(to_arrow.angle(), a)) > 0.02:
			diag_bad.append("target at %.2frad -> arrow at %.2frad" % [a, to_arrow.angle()])
		elif absf(angle_difference(float(m["angle"]), a)) > 0.02:
			diag_bad.append("target at %.2frad -> arrow points %.2frad" % [a, float(m["angle"])])
		elif not _on_inset_edge(pos, rect, margin):
			diag_bad.append("target at %.2frad -> %s is off the inset edge" % [a, str(pos)])
	if diag_bad.is_empty():
		_ok("marker", "diagonal targets keep the arrow on the ray to the boss")
	else:
		_fail("marker", "; ".join(diag_bad))

	# A window narrower than twice the margin must not produce a mirrored rect
	# (negative size), which would send the arrow to the opposite edge.
	var tiny := Rect2(Vector2.ZERO, Vector2(50, 50))
	var t_m: Dictionary = BOSS_MARKER.marker_for(Vector2(9000, 25), tiny, 200.0)
	var t_pos: Vector2 = t_m["pos"]
	if not bool(t_m["offscreen"]):
		_fail("marker", "a target 9000px away was on-screen in a 50px window")
	elif t_pos.x < tiny.position.x - 0.01 or t_pos.x > tiny.end.x + 0.01:
		_fail("marker", "margin larger than the window pushed the arrow to %s, outside %s" % [str(t_pos), str(tiny)])
	else:
		_ok("marker", "a margin larger than the window degenerates safely, not mirrored")

	# Degenerate input: a target exactly on the centre of a zero-size rect has no
	# direction. It must pick one instead of returning NaN.
	var zero: Dictionary = BOSS_MARKER.marker_for(Vector2.ZERO, Rect2(Vector2.ZERO, Vector2.ZERO), 10.0)
	var z_pos: Vector2 = zero["pos"]
	if is_nan(z_pos.x) or is_nan(z_pos.y) or is_nan(float(zero["angle"])):
		_fail("marker", "a zero-length direction produced NaN")
	else:
		_ok("marker", "a zero-length direction falls back to a real angle")

# --- Helpers ------------------------------------------------------------

## True when `pos` lies on the boundary of `rect` deflated by `margin`. The arrow
## must be ON that boundary, not merely inside it.
func _on_inset_edge(pos: Vector2, rect: Rect2, margin: float) -> bool:
	var inner := Rect2(rect.position + Vector2(margin, margin), rect.size - Vector2(margin, margin) * 2.0)
	var eps: float = 0.5
	var on_x: bool = absf(pos.x - inner.position.x) < eps or absf(pos.x - inner.end.x) < eps
	var on_y: bool = absf(pos.y - inner.position.y) < eps or absf(pos.y - inner.end.y) < eps
	if not (on_x or on_y):
		return false
	# And within the span of the other axis, so a corner-adjacent point that has
	# drifted off the rectangle entirely still fails.
	return pos.x >= inner.position.x - eps and pos.x <= inner.end.x + eps \
		and pos.y >= inner.position.y - eps and pos.y <= inner.end.y + eps

## Put the player back in a state where the next hit is guaranteed to land: no
## leftover i-frames, alive, and full. Without this a previous test's 0.4s
## invulnerability would silently swallow the hit the next test is measuring.
func _ready_player_for_hit() -> void:
	player.invulnerable = false
	player.alive = true
	player.hp = player.max_hp

## Empty field, player at the origin, clean slate. The origin is the one spot the
## generator guarantees is plain sand and inside the map (`spawn_clear_radius` /
## `spawn_no_swamp_radius`), so neither the swamp component nor the out-of-bounds
## component can add damage to a reading. Enemies are cleared for the same reason:
## contact damage looks exactly like poison damage in an hp delta.
func _park_player() -> void:
	await _clear_enemies()
	player.global_position = Vector2.ZERO
	_ready_player_for_hit()
	await _frames(1)

## The BOSS-behaviour enemy on the field, if any. Elites share the scene and the
## script, so the behaviour flag is the only way to tell them apart.
func _find_boss() -> Node2D:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or e.is_queued_for_deletion():
			continue
		var cfg: EnemyConfig = e.config as EnemyConfig
		if cfg != null and cfg.behavior == EnemyConfig.Behavior.BOSS:
			return e as Node2D
	return null

## Empty the field. Tests count the population, so leftovers from an earlier test
## would read as spawns from this one.
func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await _frames(2)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

## Real PHYSICS frames. Used by the dash test to let the physics server catch up
## with synchronous teleports; process frames would not do that (the server only
## syncs bodies during the physics step).
func _physics_frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame

func _ok(tag: String, msg: String) -> void:
	print("  [ok] %s: %s" % [tag, msg])

func _fail(tag: String, msg: String) -> void:
	_failures += 1
	printerr("  [FAIL] %s: %s" % [tag, msg])
