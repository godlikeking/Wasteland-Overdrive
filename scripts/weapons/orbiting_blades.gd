extends BaseWeapon
class_name OrbitingBladesWeapon
## Spawns N short blades that orbit the player. Every dash_interval one
## blade detaches and homes in on the nearest enemy as a short-lived
## hitbox. The rest continue orbiting.

@export var blade_scene: PackedScene

@onready var _blades_root: Node2D = $Blades
@onready var _timer: Timer = $DashTimer

var _blades: Array = []   # Array[Node2D]
var _angle: float = 0.0
var _next_dash_index: int = 0

func setup(config: WeaponConfig, level: int = 1) -> void:
	# Delegate to base so config/level are stored and _post_setup() is called.
	super.setup(config, level)

func setup_blade_scene(scene: PackedScene) -> void:
	blade_scene = scene

func _ready() -> void:
	super._ready()
	_timer.timeout.connect(_on_dash)
	# Build initial blades in case blade_scene is injected BEFORE add_child
	# (via setup_blade_scene in WeaponDirector).
	if _ready_called and blade_scene != null and config != null and _blades.is_empty():
		_build_blades()

func _post_setup() -> void:
	if _timer == null:
		return
	_timer.wait_time = config.blade_dash_interval
	_timer.start()
	_build_blades()

func _process(delta: float) -> void:
	if not is_instance_valid(_owner):
		return
	_angle += config.blade_orbit_speed * delta
	for i in range(_blades.size()):
		var b: Node2D = _blades[i]
		if not is_instance_valid(b):
			continue
		var phase: float = _angle + (TAU / float(_blades.size())) * float(i)
		b.global_position = _owner.global_position + Vector2(cos(phase), sin(phase)) * config.blade_orbit_radius
		b.rotation = phase + PI * 0.5

func _build_blades() -> void:
	if blade_scene == null or _blades_root == null or config == null:
		return
	for i in range(config.blade_count):
		var blade: Node2D = blade_scene.instantiate()
		_blades_root.add_child(blade)
		_blades.append(blade)

func _on_dash() -> void:
	if _blades.is_empty():
		return
	# Find a blade that isn't currently a projectile.
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
	if target == null:
		return
	blade.set_meta("dashing", true)
	# Re-parent to world for the dash.
	var world := get_tree().current_scene
	if world:
		world.add_child(blade)
		blade.global_position = _owner.global_position
	var dir: Vector2 = (target.global_position - blade.global_position).normalized()
	var speed: float = config.blade_dash_speed
	var dmg: float = get_damage()
	# Animate and check for hits via Area2D on the blade scene.
	if blade.has_method("launch_dash"):
		blade.launch_dash(dir * speed, dmg, config.blade_dash_lifetime, self)
	# After lifetime the dash handler re-parents back to us.
