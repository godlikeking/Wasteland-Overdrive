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
	for i in range(targets.size()):
		var t: Node2D = targets[i]
		if not is_instance_valid(t):
			continue
		if t.has_method("take_damage"):
			t.take_damage(damage, (t.global_position - last_pos).normalized())
		GameState.bullet_hit.emit(t.global_position)
		last_pos = t.global_position
		damage *= config.chain_damage_falloff
