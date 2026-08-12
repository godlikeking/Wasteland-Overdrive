extends BaseWeapon
class_name MineLayerWeapon
## Drops a proximity mine at the player's feet every `mine_interval`. Pure
## area-denial: it does nothing to whatever is chasing you right now, and
## everything to whatever follows you through the corridor you just left.
##
## Live mines are capped at `mine_max_active`. Without the cap a long run turns
## into a minefield that kills everything before it gets near the player, which
## is both trivial and unreadable.

@onready var timer: Timer = $Timer

var _mines: Array[Node2D] = []

func _ready() -> void:
	super._ready()
	if timer:
		timer.one_shot = false
		timer.timeout.connect(_on_tick)

func _post_setup() -> void:
	if timer == null:
		return
	timer.wait_time = _interval()
	timer.start()

func _process(_delta: float) -> void:
	if timer and config != null and absf(timer.wait_time - _interval()) > 0.02:
		timer.wait_time = _interval()
		if timer.is_stopped():
			timer.start()

## Laying rate follows the merge curve's fire-rate multiplier plus the player's
## fire-rate upgrades, same as the laser's cooldown does.
func _interval() -> float:
	if config == null:
		return 2.0
	return scale_cooldown(config.mine_interval, 0.2)

func _on_tick() -> void:
	_fire()

func _fire() -> void:
	if config == null or config.mine_scene == null or not is_instance_valid(_owner):
		return
	_prune()
	if _mines.size() >= maxi(1, config.mine_max_active):
		return
	var mine: Node = config.mine_scene.instantiate()
	# Slight scatter, so a stationary player lays a small field instead of
	# stacking every mine on one pixel.
	var jitter := Vector2(randf_range(-14.0, 14.0), randf_range(-14.0, 14.0))
	if mine.has_method("setup"):
		mine.setup(
			config.mine_blast_radius * float(GameState.weapon_range_mult),
			get_damage(),
			config.mine_arm_time,
			config.mine_lifetime
		)
	# 挂到 World 名下而不是场景根：World 的子节点在 z=0 上紧跟 TileMap 之后
	# 绘制，压在地图上、又压在玩家/敌人（World 的后继兄弟）之下 —— 这才是让
	# 雷"躺在地上"的正确做法。以前挂场景根 + z_index=-1，负 z 被整张地图盖掉，
	# 雷根本看不见。和 poison_pool 同一套。没有 World 就退回场景根。
	var worlds: Array = get_tree().get_nodes_in_group("world")
	if worlds.is_empty():
		get_tree().current_scene.add_child(mine)
	else:
		worlds[0].add_child(mine)
	# 落点在**挂上去之后**才设：挂到 World 名下时 global_position 才算得准，
	# 挂之前设的是无父节点的局部坐标（World 一旦不在原点就会偏）。
	if mine is Node2D:
		(mine as Node2D).global_position = _owner.global_position + jitter
		_mines.append(mine as Node2D)

## Drop refs to mines that already blew up. Checked before every lay so the cap
## counts live mines rather than everything ever laid.
func _prune() -> void:
	var alive: Array[Node2D] = []
	for m in _mines:
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			alive.append(m)
	_mines = alive

# --- Read-only accessor, used by the headless self-test ---

func live_mine_count() -> int:
	_prune()
	return _mines.size()
