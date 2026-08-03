extends BaseWeapon
class_name BladeBarrageWeapon
## Fusion of bullet_volley + orbiting_blades. 6 blades orbit the player and
## take turns dashing at the nearest enemy, while a wide bullet fan sprays
## outward from the player every fire cycle.

@export var blade_scene: PackedScene

@onready var _blades_root: Node2D = $Blades
@onready var _volley_timer: Timer = $VolleyTimer
@onready var _dash_timer: Timer = $DashTimer

var _blades: Array = []   # Array[Node2D]
var _angle: float = 0.0
var _next_dash_index: int = 0

func _ready() -> void:
	super._ready()
	_volley_timer.timeout.connect(_on_volley)
	_dash_timer.timeout.connect(_on_dash)
	# blade_scene may be injected BEFORE add_child via setup_blade_scene.
	if _ready_called and blade_scene != null and config != null and _blades.is_empty():
		_build_blades()

func setup_blade_scene(scene: PackedScene) -> void:
	blade_scene = scene

func _post_setup() -> void:
	if config == null:
		return
	_volley_timer.wait_time = get_fire_interval()
	_volley_timer.start()
	_dash_timer.wait_time = config.blade_dash_interval
	_dash_timer.start()
	_build_blades()

func _process(delta: float) -> void:
	if config == null or not is_instance_valid(_owner):
		return
	if _volley_timer and absf(_volley_timer.wait_time - get_fire_interval()) > 0.02:
		_volley_timer.wait_time = get_fire_interval()
		if _volley_timer.is_stopped():
			_volley_timer.start()
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

## Wide spray — the "barrage" half. Fires around the player rather than only
## at the nearest target, so it covers the gaps the blades leave.
func _on_volley() -> void:
	if config == null or config.projectile_scene == null or not is_instance_valid(_owner):
		return
	var target: Node2D = _find_nearest_enemy()
	if target == null:
		return
	var base_dir: Vector2 = (target.global_position - _owner.global_position).normalized()
	var count: int = 4 + int(GameState.extra_projectiles)
	var damage: float = get_damage() * 0.8   # blades carry the rest
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
		b.setup(dir * config.projectile_speed, damage, config.projectile_lifetime)

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
