extends BaseWeapon
class_name StormVolleyWeapon
## Fusion of bullet_volley + chain_lightning. Fires a 3-way bullet fan on
## the normal fire cycle, and on a much shorter chain cooldown zaps the 2
## nearest enemies. Bullets and zaps both roll crit through GameState.

@onready var _volley_timer: Timer = $VolleyTimer
@onready var _chain_timer: Timer = $ChainTimer

func _ready() -> void:
	super._ready()
	_volley_timer.timeout.connect(_on_volley)
	_chain_timer.timeout.connect(_on_chain)

func _post_setup() -> void:
	if config == null:
		return
	_volley_timer.wait_time = get_fire_interval()
	_volley_timer.start()
	_chain_timer.wait_time = maxf(0.2, config.chain_cooldown)
	_chain_timer.start()

func _process(_delta: float) -> void:
	if config == null:
		return
	# Keep the volley cadence in sync with dynamic multipliers.
	if _volley_timer and absf(_volley_timer.wait_time - get_fire_interval()) > 0.02:
		_volley_timer.wait_time = get_fire_interval()
		if _volley_timer.is_stopped():
			_volley_timer.start()

func _on_volley() -> void:
	if config == null or config.projectile_scene == null or not is_instance_valid(_owner):
		return
	var target: Node2D = _find_nearest_enemy(get_range())
	if target == null:
		return
	var base_dir: Vector2 = (target.global_position - _owner.global_position).normalized()
	# 3-way fan, plus whatever extra_projectiles the player has picked up.
	var count: int = 3 + int(GameState.extra_projectiles)
	var damage: float = get_damage()
	for i in range(count):
		var offset_index: float = float(i) - float(count - 1) / 2.0
		var angle: float = deg_to_rad(config.projectile_spread_deg) * offset_index
		_spawn_bullet(base_dir.rotated(angle), damage)
	SfxPlayer.play("fire")

func _spawn_bullet(dir: Vector2, damage: float) -> void:
	var b: Node = config.projectile_scene.instantiate()
	get_tree().current_scene.add_child(b)
	if b is Node2D:
		(b as Node2D).global_position = _owner.global_position
	if b.has_method("setup"):
		b.setup(dir * config.projectile_speed, damage, config.projectile_lifetime, get_range())

func _on_chain() -> void:
	if config == null or not is_instance_valid(_owner):
		return
	var targets: Array = _find_n_nearest_enemies(config.chain_targets)
	if targets.is_empty():
		return
	# Chain rides at 60% of the weapon damage — the volley is the main output.
	var damage: float = get_damage() * 0.6
	var last_pos: Vector2 = _owner.global_position
	var chain_pts: PackedVector2Array = PackedVector2Array()
	chain_pts.append(last_pos)
	for t in targets:
		if not is_instance_valid(t) or not (t is Node2D):
			continue
		var enemy: Node2D = t as Node2D
		if enemy.global_position.distance_to(last_pos) > config.chain_range:
			continue
		if enemy.has_method("take_damage"):
			var mult: float = GameState.roll_crit()
			var final_dmg: float = damage * mult
			enemy.take_damage(final_dmg, (enemy.global_position - last_pos).normalized())
			GameState.bullet_hit.emit(enemy.global_position, mult > 1.001, final_dmg)
		last_pos = enemy.global_position
		chain_pts.append(last_pos)
		damage *= config.chain_damage_falloff
	_spawn_chain_line(chain_pts)

## Transient jagged polyline that flashes for ~0.2s, in world space.
func _spawn_chain_line(points: PackedVector2Array) -> void:
	if points.size() < 2:
		return
	var line: Line2D = Line2D.new()
	line.top_level = true
	line.width = 3.0
	line.default_color = Color(0.75, 0.75, 1.0, 0.95)
	line.joint_mode = Line2D.LINE_JOINT_ROUND
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
	var tw: Tween = line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.18)
	tw.tween_callback(line.queue_free)
