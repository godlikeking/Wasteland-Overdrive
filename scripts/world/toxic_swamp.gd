extends Node
## Sticks to a CharacterBody2D and applies toxic-swamp effects when the
## owner steps onto a swamp tile. Owner must expose `set_swamp_slow(factor)`
## and a way to take damage (Player.take_damage / Enemy.take_damage).

class_name ToxicSwamp

@export var body_path: NodePath
@export var builder_path: NodePath
@export var use_signal: bool = true   # listen to GameState for shared tuning

var _body: Node
var _builder: Node
var _in_swamp: bool = false
var _tick_accum: float = 0.0
var _factor: float = 1.0   # applied to owner via set_swamp_slow()

func _ready() -> void:
	if body_path != NodePath():
		_body = get_node_or_null(body_path)
	_resolve_builder()
	# World is constructed lazily in _ready (see World.gd). Wait one frame so
	# the dynamic TilemapBuilder exists, then attach.
	if _builder == null:
		call_deferred("_resolve_builder")

func _resolve_builder() -> void:
	if builder_path != NodePath():
		_builder = get_node_or_null(builder_path)
	if _builder == null:
		var list: Array = get_tree().get_nodes_in_group("world")
		for w in list:
			if w and w.has_method("get_builder"):
				var b: Node = w.get_builder()
				if b:
					_builder = b
					return

func set_builder(p_builder: Node) -> void:
	_builder = p_builder

func _physics_process(delta: float) -> void:
	if _body == null or _builder == null:
		return
	if not _builder.has_method("is_swamp"):
		return
	var pos: Vector2 = _body.global_position
	var here: bool = _builder.is_swamp(pos)
	if here != _in_swamp:
		_in_swamp = here
		_apply_factor()
	_tick_accum += delta
	if _in_swamp:
		var interval: float = _swamp_tick_interval()
		if interval <= 0.0:
			interval = 0.5
		if _tick_accum >= interval:
			_tick_accum = 0.0
			_apply_swamp_damage()

func _apply_factor() -> void:
	var target: float = 0.5 if _in_swamp else 1.0
	if _body.has_method("set_swamp_slow"):
		_body.set_swamp_slow(target)
	_factor = target

func _apply_swamp_damage() -> void:
	var amount: float = _swamp_damage()
	if amount <= 0.0:
		return
	if _body.has_method("take_damage"):
		# Player.take_damage(amount) -> GameState.player_hurt signal -> red flash
		# Enemy.take_damage(amount, hit_dir) -> we pass zero dir.
		if _body.is_in_group("player"):
			_body.take_damage(amount)
		elif _body.has_method("take_damage"):
			# Use 2-arg form on enemies.
			_body.take_damage(amount, Vector2.ZERO)

func _swamp_damage() -> float:
	# Read fresh from config if available, else default 1.
	var cfg = _builder.config if _builder and "config" in _builder else null
	if cfg and "swamp_damage_per_tick" in cfg:
		return cfg.swamp_damage_per_tick
	return 1.0

func _swamp_tick_interval() -> float:
	var cfg = _builder.config if _builder and "config" in _builder else null
	if cfg and "swamp_tick_interval" in cfg:
		return cfg.swamp_tick_interval
	return 0.5
