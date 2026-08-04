extends Node2D
## Guards the elite camps that TilemapBuilder carved into the map.
##
## Each camp holds at most one elite at a time. A camp spawns its elite the
## first time the player walks within `activation_radius`, and re-arms
## `respawn_cooldown` seconds after that elite dies — so a camp is a repeatable
## objective the player can farm for item drops, not a one-shot event.
##
## This is additive to SpawnDirector's own elite cadence (the 5% archetype roll
## and the 30s ELITE WAVE); those are time-based, these are place-based.
##
## Camps are read from the TilemapBuilder via the "world" group and enemies are
## spawned through SpawnDirector via the "enemy_spawner" group, matching the
## project's find-by-group convention instead of hardcoded NodePaths.

## Spawn once the player is this close. Sized a little larger than the 1280x720
## viewport half-diagonal at zoom 1.2 (~610px) so the elite is already on its
## feet by the time the camp scrolls into view, rather than popping in.
@export var activation_radius: float = 700.0
@export var respawn_cooldown: float = 45.0
@export var elite_id: String = "elite_brute"
## Camps stay dormant this long into a run, so the opening minute is not
## ruined by wandering into a 220hp elite at level 1.
@export var arm_delay: float = 20.0

const CHECK_INTERVAL: float = 0.25   # sec between proximity scans

var _player: Node2D
var _spawner: Node
## One entry per camp: {pos: Vector2, cooldown: float, elite: Node}
var _camps: Array[Dictionary] = []
var _check_accum: float = 0.0
var _resolved: bool = false

func _ready() -> void:
	add_to_group("elite_camp_director")
	# The world builds its TileMap in _ready too, and node order is not
	# something we want to depend on, so resolve on the next frame.
	call_deferred("_resolve_camps")

func _resolve_camps() -> void:
	_resolved = true
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("camp_centers"):
		push_warning("[EliteCampDirector] no world with camp_centers(); camps disabled")
		return
	var centers: Array[Vector2] = world.camp_centers()
	_camps.clear()
	for pos in centers:
		# Start on a fresh cooldown so `arm_delay` also covers the case where
		# the player happens to spawn near a camp.
		_camps.append({"pos": pos, "cooldown": arm_delay, "elite": null, "busy": false})
	print("[EliteCampDirector] tracking %d elite camps" % _camps.size())

func _process(delta: float) -> void:
	if _camps.is_empty():
		return
	# Cooldowns tick every frame; the proximity scan is throttled because it
	# is O(camps) distance checks and 0.25s of latency is imperceptible for a
	# 700px trigger.
	for camp in _camps:
		if camp["cooldown"] > 0.0:
			camp["cooldown"] = maxf(0.0, camp["cooldown"] - delta)
	_check_accum += delta
	if _check_accum < CHECK_INTERVAL:
		return
	_check_accum = 0.0

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return
	var player_pos: Vector2 = _player.global_position

	for camp in _camps:
		# `busy` is tracked separately from the `elite` ref on purpose: a freed
		# object compares EQUAL to null in Godot 4, so `elite != null` cannot
		# tell "this camp never spawned" from "its elite just died" — the camp
		# would silently look idle and respawn on the very next scan.
		if camp["busy"]:
			if _is_alive(camp["elite"]):
				continue
			camp["busy"] = false
			camp["elite"] = null
			camp["cooldown"] = respawn_cooldown
			continue
		if camp["cooldown"] > 0.0:
			continue
		if player_pos.distance_to(camp["pos"] as Vector2) > activation_radius:
			continue
		_spawn_camp_elite(camp)

## An enemy counts as dead the moment it is queued for deletion — `queue_free`
## only lands at the end of the frame, and `is_instance_valid` stays true until
## then, which would otherwise keep the camp "busy" for a frame after the kill.
## Same idiom as WeaponMounts' `not c.is_queued_for_deletion()` filter.
func _is_alive(node: Variant) -> bool:
	if not is_instance_valid(node):
		return false
	var n: Node = node as Node
	return n != null and not n.is_queued_for_deletion()

func _spawn_camp_elite(camp: Dictionary) -> void:
	if _spawner == null or not is_instance_valid(_spawner):
		_spawner = get_tree().get_first_node_in_group("enemy_spawner")
	if _spawner == null or not _spawner.has_method("spawn_enemy_at"):
		return
	var pos: Vector2 = camp["pos"] as Vector2
	var elite: Node = _spawner.spawn_enemy_at(elite_id, pos)
	if elite == null:
		# Archetype missing — put the camp on a long cooldown instead of
		# retrying every 0.25s forever.
		camp["cooldown"] = respawn_cooldown
		return
	camp["elite"] = elite
	camp["busy"] = true
	_spawn_label(pos, "精英出没", Color(1.0, 0.4, 0.4), 28, 1.2)
	GameState.request_camera_shake.emit(4.0, 0.3)
	SfxPlayer.play("levelup")

func _spawn_label(pos: Vector2, text: String, color: Color, font_size: int, life: float) -> void:
	var fx: Node = get_tree().get_first_node_in_group("fx_manager")
	if fx and fx.has_method("_spawn_label"):
		fx._spawn_label(pos, text, color, font_size, life)

# --- Read-only accessors, used by the headless self-test ---

func camp_count() -> int:
	return _camps.size()

func camp_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for camp in _camps:
		out.append(camp["pos"] as Vector2)
	return out

func live_elite_count() -> int:
	var n: int = 0
	for camp in _camps:
		if _is_alive(camp["elite"]):
			n += 1
	return n

func cooldown_of(index: int) -> float:
	if index < 0 or index >= _camps.size():
		return -1.0
	return float(_camps[index]["cooldown"])

## Test hook: drop the arming delay so a self-test doesn't have to wait 20s.
func force_arm() -> void:
	for camp in _camps:
		if not camp["busy"]:
			camp["cooldown"] = 0.0

## Test hook: human-readable dump of every camp's state.
func debug_dump() -> String:
	var parts: PackedStringArray = []
	for i in range(_camps.size()):
		var c: Dictionary = _camps[i]
		parts.append("#%d cd=%.2f busy=%s alive=%s" % [
			i, c["cooldown"], c["busy"], _is_alive(c["elite"])])
	return ", ".join(parts)
