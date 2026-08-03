extends BaseWeapon
class_name LightningBladeWeapon
## Fusion of chain_lightning + orbiting_blades. 4 electrified blades orbit and
## dash; every chain_cooldown a lightning chain hops through the 3 nearest
## enemies. No projectiles — this build is all melee + zap.

@export var blade_scene: PackedScene

@onready var _blades_root: Node2D = $Blades
@onready var _chain_timer: Timer = $ChainTimer
@onready var _dash_timer: Timer = $DashTimer

var _blades: Array = []   # Array[Node2D]
var _angle: float = 0.0
var _next_dash_index: int = 0

func _ready() -> void:
	super._ready()
	_chain_timer.timeout.connect(_on_chain)
	_dash_timer.timeout.connect(_on_dash)
	if _ready_called and blade_scene != null and config != null and _blades.is_empty():
		_build_blades()

func setup_blade_scene(scene: PackedScene) -> void:
	blade_scene = scene

func _post_setup() -> void:
	if config == null:
		return
	_chain_timer.wait_time = maxf(0.2, config.chain_cooldown)
	_chain_timer.start()
	_dash_timer.wait_time = config.blade_dash_interval
	_dash_timer.start()
	_build_blades()

func _process(delta: float) -> void:
	if config == null or not is_instance_valid(_owner):
		return
	_angle += config.blade_orbit_speed * delta
	for i in range(_blades.size()):
		var b: Node2D = _blades[i]
		if not is_instance_valid(b):
			continue
		var phase: float = _angle + (TAU / float(maxi(1, _blades.size()))) * float(i)
		b.global_position = _owner.global_position + Vector2(cos(phase), sin(phase)) * config.blade_orbit_radius
		b.rotation = phase + PI * 0.5

func _build_blades() -> void:
	if blade_scene == null or _blades_root == null or config == null:
		return
	if not _blades.is_empty():
		return
	for i in range(config.blade_count):
		var blade: Node2D = blade_scene.instantiate()
		_blades_root.add_child(blade)
		_blades.append(blade)

func _on_chain() -> void:
	if config == null or not is_instance_valid(_owner):
		return
	var targets: Array = _find_n_nearest_enemies(config.chain_targets)
	if targets.is_empty():
		return
	var damage: float = get_damage()
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
	SfxPlayer.play("fire")
	_spawn_chain_line(chain_pts)

## Transient jagged polyline that flashes for ~0.2s, in world space.
func _spawn_chain_line(points: PackedVector2Array) -> void:
	if points.size() < 2:
		return
	var line: Line2D = Line2D.new()
	line.top_level = true
	line.width = 4.0
	line.default_color = Color(0.6, 0.85, 1.0, 0.95)
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

func _on_dash() -> void:
	if _blades.is_empty():
		return
	var attempts: int = 0
	while attempts < _blades.size():
		var b: Node2D = _blades[_next_dash_index]
		_next_dash_index = (_next_dash_index + 1) % _blades.size()
		attempts += 1
		if is_instance_valid(b) and not b.has_meta("dashing"):
			_launch_blade(b)
			return

func _launch_blade(blade: Node2D) -> void:
	var target: Node2D = _find_nearest_enemy()
	if target == null or not is_instance_valid(_owner):
		return
	blade.set_meta("dashing", true)
	var world: Node = get_tree().current_scene
	if world:
		world.add_child(blade)
		blade.global_position = _owner.global_position
	var dir: Vector2 = (target.global_position - blade.global_position).normalized()
	if blade.has_method("launch_dash"):
		blade.launch_dash(dir * config.blade_dash_speed, get_damage(), config.blade_dash_lifetime, self)
