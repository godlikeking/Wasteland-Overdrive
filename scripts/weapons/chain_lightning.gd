extends BaseWeapon
class_name ChainLightningWeapon
## Every `chain_cooldown`, deal damage to up to N enemies within
## `chain_attack_range` (scales with level), then hop to their nearest
## neighbor within `chain_range` (also scales with level). Each hop uses a
## falloff multiplier.
##
## 升级提升：伤害（全武器通用曲线 +100%/级）、射速（+50%/级）、
## 攻击距离（+30/级）、弹射距离（+20/级）。

@onready var timer: Timer = $Timer

var _last_targets: Array = []

func _ready() -> void:
	super._ready()
	timer.one_shot = false
	timer.timeout.connect(_on_tick)

func _post_setup() -> void:
	if timer == null:
		return
	timer.wait_time = _interval()
	timer.start()

func _process(_delta: float) -> void:
	if timer and config and abs(timer.wait_time - _interval()) > 0.02:
		timer.wait_time = _interval()
		if timer.is_stopped():
			timer.start()

## Chain cadence also scales with the merge curve's fire-rate multiplier, not
## just the player's fire-rate upgrades — see BaseWeapon.scale_cooldown.
func _interval() -> float:
	if config == null:
		return 1.0
	return scale_cooldown(config.chain_cooldown, 0.1)

## 攻击距离（锁定第一个目标）：随等级 +30/级。
func _effective_attack_range() -> float:
	if config == null:
		return 350.0
	return config.chain_attack_range + 30.0 * float(level - 1)

## 弹射距离（每跳之间）：随等级 +20/级。
func _effective_chain_range() -> float:
	if config == null:
		return 140.0
	return config.chain_range + 20.0 * float(level - 1)

func _on_tick() -> void:
	_fire()

func _fire() -> void:
	if config == null:
		return
	var atk_range: float = _effective_attack_range()
	var hop_range: float = _effective_chain_range()
	var owner_pos: Vector2 = _owner.global_position if is_instance_valid(_owner) else Vector2.ZERO

	# 1) 从攻击范围内取最近的 chain_targets 个敌人。
	var candidates: Array = _find_n_nearest_enemies(999, atk_range)
	if candidates.is_empty():
		return
	var targets: Array = candidates.slice(0, min(config.chain_targets, candidates.size()))

	var damage: float = get_damage()
	var last_pos: Vector2 = owner_pos
	var chain_pts: PackedVector2Array = PackedVector2Array()
	chain_pts.append(last_pos)
	for i in range(targets.size()):
		var t: Node2D = targets[i] as Node2D
		if not is_instance_valid(t):
			continue
		# 2) 每跳受弹射距离约束：首跳从武器到目标，后续从上一目标到当前目标。
		if i > 0 and last_pos.distance_to(t.global_position) > hop_range:
			continue
		if t.has_method("take_damage"):
			var mult: float = GameState.roll_crit()
			var final_dmg: float = damage * mult
			t.take_damage(final_dmg, (t.global_position - last_pos).normalized())
			GameState.bullet_hit.emit(t.global_position, mult > 1.001, final_dmg)
		last_pos = t.global_position
		chain_pts.append(last_pos)
		damage *= config.chain_damage_falloff
	if chain_pts.size() < 2:
		return
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
