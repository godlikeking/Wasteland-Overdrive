extends BaseWeapon
class_name ChainLightningWeapon
## Every `chain_cooldown`, deal damage to the K nearest enemies, then
## hop to their nearest neighbor up to K-1 times. Each hop uses a
## falloff multiplier.

@onready var timer: Timer = $Timer

var _last_targets: Array = []

func _ready() -> void:
	super._ready()
	timer.one_shot = false
	timer.timeout.connect(_on_tick)

func _post_setup() -> void:
	if timer == null:
		return
	timer.wait_time = config.chain_cooldown
	timer.start()

func _process(_delta: float) -> void:
	if timer and config and abs(timer.wait_time - config.chain_cooldown) > 0.02:
		timer.wait_time = config.chain_cooldown
		if timer.is_stopped():
			timer.start()

func _on_tick() -> void:
	_fire()

func _fire() -> void:
	if config == null:
		return
	var targets: Array = _find_n_nearest_enemies(config.chain_targets)
	if targets.is_empty():
		return
	var damage: float = get_damage()
	var last_pos: Vector2 = _owner.global_position if is_instance_valid(_owner) else Vector2.ZERO
	# Collect world-space path of the chain for the visual line.
	var chain_pts: PackedVector2Array = PackedVector2Array()
	chain_pts.append(last_pos)
	for i in range(targets.size()):
		var t: Node2D = targets[i]
		if not is_instance_valid(t):
			continue
		if t.has_method("take_damage"):
			var mult: float = GameState.roll_crit()
			var final_dmg: float = damage * mult
			t.take_damage(final_dmg, (t.global_position - last_pos).normalized())
			GameState.bullet_hit.emit(t.global_position, mult > 1.001, final_dmg)
		last_pos = t.global_position
		chain_pts.append(last_pos)
		damage *= config.chain_damage_falloff
	SfxPlayer.play("fire")
	_spawn_chain_line(chain_pts)

## Build a transient jagged polyline that flashes for ~0.2s.
func _spawn_chain_line(points: PackedVector2Array) -> void:
	if points.size() < 2:
		return
	var line: Line2D = Line2D.new()
	line.top_level = true
	line.width = 4.0
	line.default_color = Color(0.6, 0.8, 1.0, 0.95)
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	# Slightly jitter each segment for a "lightning" feel.
	var jagged: PackedVector2Array = PackedVector2Array()
	for i in range(points.size()):
		jagged.append(points[i])
		if i < points.size() - 1:
			var a: Vector2 = points[i]
			var b: Vector2 = points[i + 1]
			var mid: Vector2 = (a + b) * 0.5
			var perp: Vector2 = Vector2(-(b - a).y, (b - a).x).normalized()
			mid += perp * randf_range(-8.0, 8.0)
			jagged.append(mid)
	line.points = jagged
	get_tree().current_scene.add_child(line)
	# Fade out then free.
	var tw: Tween = line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.18)
	tw.tween_callback(line.queue_free)
