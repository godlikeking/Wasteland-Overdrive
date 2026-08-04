extends Area2D
class_name PickupItem
## Item dropped by elites. Homes to the player once their PickupArea touches it,
## then applies its effect. Structure mirrors xp_gem.gd (same layer/mask, same
## seek-then-grant flow) so the two pickups behave identically to the player.
##
## Five kinds, all resolved through `_apply_effect`:
##   HEAL       回血 30% 上限
##   WEAPON     给一把没有的武器（满槽/全持有则升一把）
##   BOMB       半径 420 内全体伤害
##   TIME_STOP  敌人冻结 4s
##   SHIELD     抵消接下来 2 次伤害

enum Kind { HEAL, WEAPON, BOMB, TIME_STOP, SHIELD }

## Roll weights. Heal is the most common because it is the effect that keeps a
## run alive. The weapon drop is weighted high so trash drops (~25% per kill)
## can accumulate 3 copies of the same weapon within a run — that is the only
## way a weapon levels, via the 3-into-1 merge.
const DROP_WEIGHTS: Dictionary = {
	Kind.HEAL: 24,
	Kind.SHIELD: 22,
	Kind.BOMB: 20,
	Kind.TIME_STOP: 16,
	Kind.WEAPON: 60,
}

const HEAL_PCT: float = 0.30
const BOMB_RADIUS: float = 420.0
const BOMB_DAMAGE: float = 120.0
const TIME_STOP_SECONDS: float = 4.0
const SHIELD_CHARGES: int = 2

const SPRITE_DIR: String = "res://assets/sprites/pickups/"
const SPRITE_SCALE: float = 2.0
## Idle bob, so an item lying in the grass is visible without being loud.
const BOB_HEIGHT: float = 4.0
const BOB_TIME: float = 0.7
## Items expire so the map doesn't slowly fill with uncollected drops.
const LIFETIME: float = 30.0
## Last seconds of the lifetime are spent blinking as a warning.
const BLINK_LEAD: float = 5.0

@export var pickup_scene_speed: float = 320.0
@export var seek_accel: float = 900.0
@export var explosion_scene: PackedScene

@onready var sprite: Sprite2D = $Sprite2D

var kind: int = Kind.HEAL
var _seeking: bool = false
var _target: Node2D
var _velocity: Vector2 = Vector2.ZERO
var _age: float = 0.0

## Weighted random kind. Static so callers (enemy._die) don't need an instance.
static func roll_kind() -> int:
	var total: int = 0
	for w in DROP_WEIGHTS.values():
		total += int(w)
	var roll: int = randi() % maxi(1, total)
	for k in DROP_WEIGHTS.keys():
		roll -= int(DROP_WEIGHTS[k])
		if roll < 0:
			return int(k)
	return Kind.HEAL

func setup(p_kind: int) -> void:
	kind = p_kind
	if is_node_ready():
		_apply_sprite()

func _ready() -> void:
	add_to_group("pickup_items")
	_apply_sprite()
	area_entered.connect(_on_area_entered)
	_start_bob()

func _physics_process(delta: float) -> void:
	_age += delta
	if not _seeking:
		# Blink out the last few seconds, then vanish.
		if _age >= LIFETIME:
			queue_free()
			return
		var left: float = LIFETIME - _age
		if left <= BLINK_LEAD:
			sprite.visible = fmod(left, 0.3) > 0.12
		return
	if _target == null or not is_instance_valid(_target):
		_seeking = false
		return
	var to_target: Vector2 = (_target.global_position - global_position).normalized()
	_velocity = _velocity.move_toward(to_target * pickup_scene_speed, seek_accel * delta)
	global_position += _velocity * delta
	if global_position.distance_to(_target.global_position) < 10.0:
		_collect(_target)

func _on_area_entered(area: Area2D) -> void:
	if _seeking:
		return
	var parent: Node = area.get_parent()
	if parent and parent.is_in_group("player"):
		_target = parent as Node2D
		_seeking = true

func _collect(player: Node2D) -> void:
	_apply_effect(player)
	SfxPlayer.play("pickup")
	queue_free()

func _apply_effect(player: Node2D) -> void:
	match kind:
		Kind.HEAL:
			_effect_heal(player)
		Kind.WEAPON:
			_effect_weapon()
		Kind.BOMB:
			_effect_bomb()
		Kind.TIME_STOP:
			GameState.start_time_stop(TIME_STOP_SECONDS)
			_label("时间暂停 %.0fs" % TIME_STOP_SECONDS, Color(0.6, 0.9, 1.0))
		Kind.SHIELD:
			GameState.add_shield(SHIELD_CHARGES)
			_label("护盾 +%d" % SHIELD_CHARGES, Color(0.5, 1.0, 1.0))

func _effect_heal(player: Node2D) -> void:
	if not player.has_method("heal"):
		return
	var amount: float = float(player.max_hp) * HEAL_PCT
	var gained: float = player.heal(amount)
	if gained > 0.0:
		_label("+%d HP" % int(round(gained)), Color(0.5, 1.0, 0.5))
	else:
		# Already at full health — say so rather than flashing a silent "+0".
		_label("生命已满", Color(0.7, 0.7, 0.7))

func _effect_weapon() -> void:
	var granted: String = WeaponDirector.grant_random_weapon()
	if granted == "":
		# Slots full and nothing here can complete a merge — the director already
		# tried; refuse rather than silently wasting the drop.
		_label("武器槽已满", Color(0.8, 0.8, 0.6))
		return
	_label("获得 %s" % WeaponDirector.display_name_of(granted), Color(1.0, 0.85, 0.4))
	# A merge that the grant triggered is announced by WeaponDirector itself.

func _effect_bomb() -> void:
	if explosion_scene == null:
		explosion_scene = load("res://scenes/fx/explosion.tscn") as PackedScene
	if explosion_scene == null:
		return
	var boom: Node = explosion_scene.instantiate()
	if boom is Node2D:
		(boom as Node2D).global_position = global_position
	if boom.has_method("setup"):
		boom.setup(BOMB_RADIUS, BOMB_DAMAGE)
	# Parented to the scene, not to us: we free ourselves on the same frame.
	get_tree().current_scene.add_child(boom)
	_label("轰！", Color(1.0, 0.6, 0.2))

func _label(text: String, color: Color) -> void:
	var fx: Node = get_tree().get_first_node_in_group("fx_manager")
	if fx and fx.has_method("_spawn_label"):
		fx._spawn_label(global_position, text, color, 22, 0.9)

# --- Presentation ---

func _apply_sprite() -> void:
	if sprite == null:
		return
	# Guarded with `exists` because a bare `load()` on a missing path spams the
	# error log every single drop, which would drown a headless self-test run.
	var path: String = SPRITE_DIR + _sprite_name()
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	if tex:
		sprite.texture = tex
		sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
		sprite.modulate = Color(1, 1, 1)
	else:
		# No art yet: fall back to a flat colour square so the item is still
		# visible and testable.
		sprite.modulate = _fallback_color()

func _sprite_name() -> String:
	match kind:
		Kind.HEAL: return "heal.png"
		Kind.WEAPON: return "weapon.png"
		Kind.BOMB: return "bomb.png"
		Kind.TIME_STOP: return "time_stop.png"
		Kind.SHIELD: return "shield.png"
	return "heal.png"

func _fallback_color() -> Color:
	match kind:
		Kind.HEAL: return Color(0.9, 0.3, 0.35)
		Kind.WEAPON: return Color(1.0, 0.8, 0.35)
		Kind.BOMB: return Color(0.95, 0.55, 0.2)
		Kind.TIME_STOP: return Color(0.5, 0.85, 1.0)
		Kind.SHIELD: return Color(0.4, 1.0, 0.95)
	return Color(1, 1, 1)

func _start_bob() -> void:
	if sprite == null:
		return
	var base_y: float = sprite.position.y
	var tw: Tween = create_tween().set_loops()
	tw.tween_property(sprite, "position:y", base_y - BOB_HEIGHT, BOB_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(sprite, "position:y", base_y, BOB_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
