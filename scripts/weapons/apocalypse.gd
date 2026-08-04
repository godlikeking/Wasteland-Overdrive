extends BaseWeapon
class_name ApocalypseWeapon
## Ultimate weapon: bullet_volley + chain_lightning + orbiting_blades fused.
## Volleys a 5-way bullet spread, jumps 3-tap chain to 5 nearest enemies,
## AND spawns 8 orbiting blades every 0.7s. Every 4s a fullscreen nuke
## damages every visible enemy for 20% of base_damage.

@onready var _volley_timer: Timer = $VolleyTimer
@onready var _chain_timer: Timer = $ChainTimer
@onready var _nuke_timer: Timer = $NukeTimer
@onready var _blades_root: Node2D = $Blades
@onready var _blade_scene: PackedScene = preload("res://scenes/weapons/blade.tscn")

var _blades: Array = []   # Array[Node2D]
var _angle: float = 0.0
var _nuke_damage_pct: float = 0.20

func _ready() -> void:
	super._ready()
	_volley_timer.timeout.connect(_on_volley)
	_chain_timer.timeout.connect(_on_chain)
	_nuke_timer.timeout.connect(_on_nuke)

func _post_setup() -> void:
	if config == null:
		return
	_volley_timer.wait_time = get_fire_interval() * 0.45   # 弹雨密集
	_volley_timer.start()
	_chain_timer.wait_time = scale_cooldown(config.chain_cooldown, 0.4)
	_chain_timer.start()
	_nuke_timer.wait_time = 4.0
	_nuke_timer.start()
	_spawn_blades()

func setup_blade_scene(scene: PackedScene) -> void:
	_blade_scene = scene

func _process(delta: float) -> void:
	if not is_instance_valid(_owner) or config == null:
		return
	# Keep timers in sync with multipliers.
	if _volley_timer and abs(_volley_timer.wait_time - get_fire_interval() * 0.45) > 0.02:
		_volley_timer.wait_time = get_fire_interval() * 0.45
	# Orbit blades
	_angle += config.blade_orbit_speed * delta
	for i in range(_blades.size()):
		var b: Node2D = _blades[i]
		if not is_instance_valid(b):
			continue
		var phase: float = _angle + (TAU / float(max(1, _blades.size()))) * float(i)
		b.global_position = _owner.global_position + Vector2(cos(phase), sin(phase)) * config.blade_orbit_radius
		b.rotation = phase + PI * 0.5

func _spawn_blades() -> void:
	if _blade_scene == null or config == null:
		return
	for i in range(config.blade_count):
		var b: Node2D = _blade_scene.instantiate()
		_blades_root.add_child(b)
		_blades.append(b)

func _on_volley() -> void:
	if config == null or not is_instance_valid(_owner):
		return
	# 5-way fan. Nothing in range means we hold fire rather than spray blindly.
	var target: Node2D = _find_nearest_enemy(get_range())
	if target == null:
		return
	var base_dir: Vector2 = (target.global_position - _owner.global_position).normalized()
	var n: int = 5
	for i in range(n):
		var off: float = (float(i) - float(n - 1) / 2.0) * deg_to_rad(config.projectile_spread_deg)
		_fire_bullet(base_dir.rotated(off))

func _fire_bullet(dir: Vector2) -> void:
	if config.projectile_scene == null or not is_instance_valid(_owner):
		return
	var b: Node = config.projectile_scene.instantiate()
	get_tree().current_scene.add_child(b)
	b.global_position = _owner.global_position
	if b.has_method("setup"):
		b.setup(dir * config.projectile_speed, get_damage(), config.projectile_lifetime, get_range())
	SfxPlayer.play("fire")

func _on_chain() -> void:
	if config == null or not is_instance_valid(_owner):
		return
	var targets: Array = _find_n_nearest_enemies(config.chain_targets)
	if targets.is_empty():
		return
	var damage: float = get_damage()
	var last_pos: Vector2 = _owner.global_position
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
		damage *= config.chain_damage_falloff

func _on_nuke() -> void:
	if not is_instance_valid(_owner):
		return
	var pos: Vector2 = _owner.global_position
	var damage: float = get_damage() * _nuke_damage_pct
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D):
			continue
		var d: float = (e.global_position - pos).length()
		if d > 1200.0:   # only "visible" (within screen-edge)
			continue
		if e.has_method("take_damage"):
			e.take_damage(damage, Vector2.ZERO)
	# FX
	GameState.request_camera_shake.emit(10.0, 0.4)
	GameState.request_hit_stop.emit(0.12)
	SfxPlayer.play("levelup")
