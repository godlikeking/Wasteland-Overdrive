extends Node2D
## Wave / archetype scheduler. Picks an EnemyConfig based on elapsed time
## (GameState.time_alive) and spawns it just outside the camera view.
##
## Archetype cadence (seconds alive):
##   0:00 -> only chasers
##   1:00 -> introduce dasher (20% chance at any non-elite spawn)
##   2:00 -> introduce shooter (30% chance) + BOSS lands (`boss_spawn_time`)
##   3:30 -> mixed: chaser/dasher/shooter at 50/20/30
##   5:00 -> every 30s, an elite spawns in addition to the normal cadenced
##
## NOTE: `boss_spawn_time` is 120s while the elite cadence is gated at t >= 300,
## so the boss now lands three minutes BEFORE the first elite wave. That ordering
## is a deliberate tuning choice ("boss as midterm"), not an oversight — if it
## ever needs fixing, lower the 300.0 gate in `_process`, not the boss time.
##
## Difficulty: spawn interval shrinks from `base_interval` to `min_interval`
## over `difficulty_ramp_time`, mirroring the original EnemySpawner. Two ceilings
## keep the late game finishable rather than merely survivable: `max_burst` on
## the per-tick count and `max_live_enemies` on the population. Both were added
## because the uncapped curve reached ~39 spawns/second by t=300, so nobody ever
## lived to see the boss the code was already spawning correctly.
##
## `min_interval` must NOT be overridden in game.tscn: the scene used to ship
## 0.18 while this script said 0.25, so the real peak was 22/s while every test
## (which builds a director from the script) saw 16/s and passed. The shipped
## values are now asserted by boss_selftest's `shipped_scene_ceilings`.

@export var enemy_scene: PackedScene
@export var xp_gem_scene: PackedScene
@export var enemy_projectile_scene: PackedScene
## Dropped by elites/boss on death; injected into their EnemyConfigs.
@export var pickup_item_scene: PackedScene
@export var camera: Camera2D
@export var player_path: NodePath
@export var configs_path: NodePath  # Node that has enemy configs as children
@export var base_interval: float = 1.2
@export var min_interval: float = 0.25
@export var difficulty_ramp_time: float = 240.0
@export var spawn_padding: float = 80.0
@export var burst_growth: float = 0.02
## Hard ceiling on the per-tick burst. Without it `1 + int(t * burst_growth)`
## keeps growing forever against a `min_interval` that has already bottomed out:
## at t=300 that was 7 spawns every 0.18s, ~39 enemies/second, which is why the
## 5-minute boss was unreachable in practice. See `burst_for`.
@export var max_burst: int = 4
## Hard ceiling on enemies alive at once. The burst cap smooths the curve; this
## is the actual guarantee — it bounds both the difficulty and the frame cost no
## matter how the other knobs are tuned later.
@export var max_live_enemies: int = 110
@export var start_wave_shake: float = 5.0
@export var elite_interval: float = 30.0
@export var boss_spawn_time: float = 300.0   # 5 分钟触发 Boss
## Seconds of warning before the boss lands, so it doesn't appear on top of you.
@export var boss_warn_lead: float = 6.0

var _spawn_accum: float = 0.0
var _elite_accum: float = 0.0
var _player: Node2D
var _configs_root: Node
var _configs: Array = []  # Array[EnemyConfig]
var _boss_spawned: bool = false
## Whole seconds of boss countdown last broadcast, so `boss_incoming` fires once
## per second instead of once per frame.
var _boss_warn_shown: int = -1

func _ready() -> void:
	if player_path != NodePath():
		_player = get_node_or_null(player_path)
	if configs_path != NodePath():
		_configs_root = get_node_or_null(configs_path)
	_cache_configs()
	GameState.leveled_up.connect(_on_leveled_up)
	add_to_group("boss_spawner")
	# Generic spawn service, used by EliteCampDirector. Separate from
	# "boss_spawner" so the boss callback contract stays untouched.
	add_to_group("enemy_spawner")
	print("[SpawnDirector] ready with %d configs" % _configs.size())

func _cache_configs() -> void:
	_configs.clear()
	# Always load from resource paths — keeps the type system happy and
	# avoids a Node-vs-Resource mismatch on the children of configs_root.
	for path in [
		"res://data/enemies/chaser.tres",
		"res://data/enemies/dasher.tres",
		"res://data/enemies/shooter.tres",
		"res://data/enemies/elite_brute.tres",
		"res://data/enemies/boss.tres",
	]:
		var res: Resource = ResourceLoader.load(path)
		if res is EnemyConfig:
			_configs.append(res as EnemyConfig)
	_inject_runtime_refs(_configs)

func _inject_runtime_refs(list: Array) -> void:
	for c in list:
		if not (c is EnemyConfig):
			continue
		var ec: EnemyConfig = c as EnemyConfig
		if ec.scene == null:
			ec.scene = enemy_scene
		if ec.xp_gem_scene == null:
			ec.xp_gem_scene = xp_gem_scene
		# SHOOTER 和 BOSS 都开枪。BOSS 一度漏在这个条件外面，于是 P2/P3 的
		# _boss_volley 每次都在 _fire_projectile 的 `projectile_scene == null`
		# 早退里静默失败 —— 弹幕从来没打出来过，而且没有任何报错。
		if ec.projectile_scene == null and (
				ec.behavior == EnemyConfig.Behavior.SHOOTER
				or ec.behavior == EnemyConfig.Behavior.BOSS):
			ec.projectile_scene = enemy_projectile_scene
		# Only archetypes that actually drop items need the scene, so a missing
		# export can't silently break trash mobs.
		if ec.item_drop_count > 0 and ec.item_drop_scene == null:
			ec.item_drop_scene = pickup_item_scene

func _process(delta: float) -> void:
	if _configs.is_empty():
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return

	# --- Difficulty interval ---
	var t: float = GameState.time_alive
	var progress: float = clamp(t / difficulty_ramp_time, 0.0, 1.0)
	var interval: float = lerp(base_interval, min_interval, progress)

	# --- Regular cadence ---
	_spawn_accum += delta
	if _spawn_accum >= interval:
		_spawn_accum = 0.0
		if live_enemies() < max_live_enemies:
			for i in range(burst_for(t)):
				_spawn_one(_pick_archetype(false))

	# --- Elite cadence ---
	_elite_accum += delta
	if _elite_accum >= elite_interval and t >= 300.0:
		_elite_accum = 0.0
		_spawn_one(_pick_archetype(true), true)
		GameState.request_camera_shake.emit(start_wave_shake, 0.35)
		GameState.request_hit_stop.emit(0.06)
		# Big floating label
		var player_pos: Vector2 = _player.global_position
		_spawn_label(player_pos, "ELITE WAVE", Color(1, 0.4, 0.4), 30, 1.4)

	# --- Boss check (5 min, once per run) ---
	if not _boss_spawned:
		if t >= boss_spawn_time:
			_boss_spawned = true
			GameState.boss_incoming.emit(0.0)
			var boss_cfg: EnemyConfig = _find_config("boss")
			if boss_cfg:
				_spawn_boss(boss_cfg)
		else:
			_tick_boss_warning(boss_spawn_time - t)

## Per-tick spawn count at `t` seconds alive, capped by `max_burst`. Pure so the
## cap can be asserted at times the game would take five minutes to reach.
func burst_for(t: float) -> int:
	return clampi(1 + int(t * burst_growth), 1, maxi(1, max_burst))

## Enemies currently alive. Queued-for-deletion ones still answer the group
## query for a frame, so they are filtered out — otherwise a big clear would
## keep the ceiling closed long after the corpses stopped mattering.
func live_enemies() -> int:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != null and not e.is_queued_for_deletion():
			n += 1
	return n

## Announce the boss once per remaining second inside the warning window. The
## HUD banner owns the presentation; this only decides when to speak.
func _tick_boss_warning(left: float) -> void:
	if left > boss_warn_lead:
		return
	var whole: int = int(ceilf(left))
	if whole == _boss_warn_shown:
		return
	_boss_warn_shown = whole
	GameState.boss_incoming.emit(left)

func _pick_archetype(force_elite: bool) -> EnemyConfig:
	if force_elite:
		return _find_config("elite_brute")
	var t: float = GameState.time_alive
	var roll: float = randf()
	if t < 60.0:
		return _find_config("chaser")
	# t in [60, 120)
	if t < 120.0:
		# chaser 80% / dasher 20%
		return _find_config("dasher") if roll < 0.2 else _find_config("chaser")
	# t in [120, 210)
	if t < 210.0:
		# chaser 60% / dasher 15% / shooter 25%
		if roll < 0.6: return _find_config("chaser")
		if roll < 0.75: return _find_config("dasher")
		return _find_config("shooter")
	# t >= 210
	# chaser 45% / dasher 20% / shooter 30% / elite 5%
	var elite_r: float = 0.05
	if roll < elite_r: return _find_config("elite_brute")
	if roll < elite_r + 0.45: return _find_config("chaser")
	if roll < elite_r + 0.65: return _find_config("dasher")
	return _find_config("shooter")

func _find_config(id: String) -> EnemyConfig:
	for c in _configs:
		if c is EnemyConfig and (c as EnemyConfig).id == id:
			return c as EnemyConfig
	# Hard fallback.
	return _configs[0] if not _configs.is_empty() else null

func _spawn_one(cfg: EnemyConfig, announce: bool = false) -> void:
	if cfg == null or cfg.scene == null:
		return
	var enemy: Node = cfg.scene.instantiate()
	if enemy is Node2D:
		(enemy as Node2D).global_position = _random_offscreen_point()
	# Pass config via a typed method to avoid `set()` Variant assignment
	# tripping the @export strong-typed setter.
	if enemy.has_method("setup_config"):
		enemy.setup_config(cfg)
	get_tree().current_scene.add_child(enemy)
	if announce:
		print("[SpawnDirector] spawned %s" % cfg.id)

func _spawn_boss(cfg: EnemyConfig) -> void:
	if cfg == null or cfg.scene == null:
		return
	var enemy: Node = cfg.scene.instantiate()
	# Boss appears near player, but in line of sight.
	var dir: Vector2 = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	var pos: Vector2 = _player.global_position + dir * 360.0
	if enemy is Node2D:
		(enemy as Node2D).global_position = pos
	if enemy.has_method("setup_config"):
		enemy.setup_config(cfg)
	get_tree().current_scene.add_child(enemy)
	# Warning + SFX. The HUD banner and the off-screen marker both hang off this
	# signal, so it has to fire after the node is in the tree.
	if enemy is Node2D:
		GameState.boss_spawned.emit(enemy as Node2D)
	_spawn_label(_player.global_position, "废土巨兽降临！", Color(1.0, 0.4, 0.2), 28, 1.4)
	GameState.request_camera_shake.emit(10.0, 0.6)
	GameState.request_hit_stop.emit(0.12)
	SfxPlayer.play("levelup")   # 警报感用琶音
	print("[SpawnDirector] BOSS spawned at %s" % str(pos))

## Generic "spawn one enemy of this archetype right here" service, used by
## EliteCampDirector. Returns the instance so the caller can track whether it
## is still alive; null if the archetype or its scene is missing.
func spawn_enemy_at(id: String, pos: Vector2) -> Node:
	var cfg: EnemyConfig = _find_config(id)
	if cfg == null or cfg.id != id or cfg.scene == null:
		push_warning("[SpawnDirector] cannot spawn unknown archetype '%s'" % id)
		return null
	var enemy: Node = cfg.scene.instantiate()
	if enemy is Node2D:
		(enemy as Node2D).global_position = pos
	if enemy.has_method("setup_config"):
		enemy.setup_config(cfg)
	get_tree().current_scene.add_child(enemy)
	return enemy

## Used by Boss._boss_summon_minions to spawn N chasers around the boss.
func spawn_minion_around(center: Vector2, minion_id: String, n: int) -> void:
	var cfg: EnemyConfig = _find_config(minion_id)
	if cfg == null or cfg.scene == null:
		return
	for i in range(n):
		var enemy: Node = cfg.scene.instantiate()
		var ang: float = TAU * float(i) / float(max(1, n)) + randf() * 0.4
		var radius: float = 80.0 + randf() * 30.0
		if enemy is Node2D:
			(enemy as Node2D).global_position = center + Vector2(cos(ang), sin(ang)) * radius
		if enemy.has_method("setup_config"):
			enemy.setup_config(cfg)
		get_tree().current_scene.add_child(enemy)

func _random_offscreen_point() -> Vector2:
	var vp: Vector2 = get_viewport_rect().size
	var cam_pos: Vector2 = _player.global_position
	var zoom: Vector2 = Vector2.ONE
	if camera and is_instance_valid(camera):
		cam_pos = camera.global_position
		zoom = camera.zoom
	else:
		var cam: Node = _player.get_node_or_null("Camera2D")
		if cam and cam is Camera2D:
			zoom = (cam as Camera2D).zoom
	var half: Vector2 = (vp / zoom) * 0.5 + Vector2(spawn_padding, spawn_padding)
	var side: int = randi() % 4
	# 四条边打乱后依次试，取第一个落在地图内的。
	#
	# **刻意不 clamp 到 map_rect**：把一个图外的点夹进矩形会把它夹到玩家附近
	# 甚至屏幕内 —— 敌人当脸凭空出现比敌人站在图外更糟。换边是唯一能同时
	# 保住"在镜头外"和"在地图内"这两个性质的做法。
	#
	# 四条边都不行（玩家已经跑到图外很远）就退回原行为：宁可在虚空里生成，
	# 也不要因为玩家越界就整个停止出怪。
	var sides: Array[int] = [0, 1, 2, 3]
	sides.shuffle()
	var world: Node = _map_world()
	if world != null:
		for s in sides:
			var p: Vector2 = _side_point(cam_pos, half, s)
			if world.out_of_bounds_depth(p) <= 0.0:
				return p
	return _side_point(cam_pos, half, side)

## 地图边界的持有者，没有就返回 null。自检里构造的 SpawnDirector 没有 World，
## 必须干净地退化成"不做边界过滤"而不是报错。
func _map_world() -> Node:
	for w in get_tree().get_nodes_in_group("world"):
		if w != null and w.has_method("out_of_bounds_depth"):
			return w
	return null

func _side_point(cam_pos: Vector2, half: Vector2, side: int) -> Vector2:
	match side:
		0: return cam_pos + Vector2(randf_range(-half.x, half.x), -half.y)
		1: return cam_pos + Vector2(randf_range(-half.x, half.x), half.y)
		2: return cam_pos + Vector2(-half.x, randf_range(-half.y, half.y))
		_: return cam_pos + Vector2(half.x, randf_range(-half.y, half.y))

func _spawn_label(pos: Vector2, text: String, color: Color, font_size: int, life: float) -> void:
	var list: Array = get_tree().get_nodes_in_group("fx_manager")
	if list.is_empty():
		return
	var fx: Node = list[0]
	if fx and fx.has_method("_spawn_label"):
		fx._spawn_label(pos, text, color, font_size, life)

func _on_leveled_up(_lvl: int) -> void:
	GameState.request_camera_shake.emit(2.0, 0.15)
