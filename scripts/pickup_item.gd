extends Area2D
class_name PickupItem
## Item dropped by elites. Homes to the player once their PickupArea touches it,
## then applies its effect. Structure mirrors xp_gem.gd (same layer/mask, same
## seek-then-grant flow) so the two pickups behave identically to the player.
##
## Six kinds, all resolved through `_apply_effect`:
##   HEAL       回血 30% 上限
##   WEAPON     给一把随机武器（按稀有度加权；满槽只收能立刻合并的）
##   BOMB       半径 420 内全体伤害
##   TIME_STOP  敌人冻结 4s
##   SHIELD     抵消接下来 2 次伤害
##   MAGNET     把全图掉落物（宝石 + 道具）吸向玩家

enum Kind { HEAL, WEAPON, BOMB, TIME_STOP, SHIELD, MAGNET }

## Roll weights for the normal item pool. **HEAL 补血不在这个池里** —— 它只从
## 精英怪极低概率掉落（见 enemy.gd 的 ELITE_HEAL_CHANCE），普通怪/其余敌人
## 永远不掉血。其余种类照常加权：weapon 最重（3-1 合并是武器唯一的升级路径），
## trash 掉落 12% 时 36/132 是武器，约 30 杀一把。
const DROP_WEIGHTS: Dictionary = {
	Kind.SHIELD: 22,
	Kind.BOMB: 20,
	Kind.TIME_STOP: 16,
	Kind.WEAPON: 36,
	Kind.MAGNET: 14,
}

const HEAL_PCT: float = 0.30
const BOMB_RADIUS: float = 420.0
const BOMB_DAMAGE: float = 120.0
const TIME_STOP_SECONDS: float = 4.0
const SHIELD_CHARGES: int = 2
## The shield expires whether or not its charges were spent. Long enough to
## cover a wave you walked into, short enough that you can't save it for the
## boss — a shield you can bank forever is just extra permanent health.
const SHIELD_SECONDS: float = 15.0

const SPRITE_DIR: String = "res://assets/sprites/pickups/"
const SPRITE_SCALE: float = 2.0
## 武器掉落物用武器自己的挂件图标（mount_*.png，约 22-32px 宽的横条）。比通用
## 道具图标的 2.0 小一档，否则一条长枪躺在地上会盖住半个屏幕。
const WEAPON_ICON_SCALE: float = 1.5
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
## WEAPON 掉落物具体是哪把武器。**落地时就决定**，这样地上画的就是那把武器的
## 图标，而不是一个看不出内容的通用武器图标。空字符串 = 没指定（自检里直接
## setup(Kind.WEAPON) 的旧路径），捡起来时退回随机掷骰。
var weapon_id: String = ""
## 这次掉落是否来自精英/BOSS。磁轨激光和火焰喷射器只在精英掉落里出现。
var elite_drop: bool = false
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

func setup(p_kind: int, p_elite_drop: bool = false) -> void:
	kind = p_kind
	elite_drop = p_elite_drop
	# 武器掉落：现在就决定是哪一把，图标才能画成那把武器。
	if kind == Kind.WEAPON and weapon_id == "":
		weapon_id = WeaponDirector.roll_weapon_id(elite_drop)
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
		attract_to(parent as Node2D)

## Start homing toward `player` without waiting for a PickupArea overlap. The
## MAGNET pickup vacuums the whole map through this, so items far outside the
## pickup radius still come in along their normal seek path — and still apply
## their own effect on arrival.
func attract_to(player: Node2D) -> void:
	if _seeking or player == null or not is_instance_valid(player):
		return
	_target = player
	_seeking = true
	# The expiry blink leaves `sprite.visible` wherever the last fmod landed, and
	# once seeking starts nothing drives it again — so an item grabbed during the
	# blink window would fly in invisible. A magnet sweeps up everything at once,
	# near-expiry items included, which makes that very easy to hit.
	if sprite:
		sprite.visible = true

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
			if GameState.add_shield(SHIELD_CHARGES, SHIELD_SECONDS):
				_label("护盾 +%d (%ds)" % [SHIELD_CHARGES, int(SHIELD_SECONDS)], Color(0.5, 1.0, 1.0))
			else:
				# 护盾不可叠加：已有护盾时再捡被拒绝。
				_label("护盾已激活", Color(0.6, 0.95, 1.0))
		Kind.MAGNET:
			_effect_magnet(player)

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
	# 装上落地时就决定好的那把（图标画的就是它）。weapon_id 为空时退回随机掷骰。
	var granted: String = WeaponDirector.grant_weapon_id(weapon_id, elite_drop) \
		if weapon_id != "" else WeaponDirector.grant_random_weapon(elite_drop)
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

## Groups vacuumed by MAGNET. Both scripts expose `attract_to`, which is the
## only thing this effect needs from them.
const MAGNET_GROUPS: Array[String] = ["xp_gems", "pickup_items"]

## Vacuum every drop on the map toward the player. Gems and items both come in
## along their own normal seek path, so each still applies its own effect on
## arrival — a magnet lying next to three bombs really is a combo, on purpose.
##
## 磁吸道具**不可叠加**：一枚磁石不吸另一枚磁石。磁石效果是瞬时瞬发的，
## 一旦吸到另一枚磁石，那枚到达时会再跑一遍全场横扫——一枚磁石等于吸两轮，
## 这就是"叠加"。所以这里跳过整个 MAGNET 种类（不只是跳过自己），杜绝连锁。
func _effect_magnet(player: Node2D) -> void:
	var n: int = 0
	for group in MAGNET_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			# 两类都跳过：a) 自己（正在收集、即将 free）；b) 任何磁石（不可叠加）。
			if node == self or node.is_queued_for_deletion():
				continue
			if node is PickupItem and (node as PickupItem).kind == Kind.MAGNET:
				continue
			if node.has_method("attract_to"):
				node.attract_to(player)
				n += 1
	if n > 0:
		_label("磁石回收 ×%d" % n, Color(0.85, 0.6, 1.0))
	else:
		# Nothing on the ground — say so rather than flashing a silent "×0".
		_label("场上无掉落", Color(0.7, 0.7, 0.7))

func _label(text: String, color: Color) -> void:
	var fx: Node = get_tree().get_first_node_in_group("fx_manager")
	if fx and fx.has_method("_spawn_label"):
		fx._spawn_label(global_position, text, color, 22, 0.9)

# --- Presentation ---

func _apply_sprite() -> void:
	if sprite == null:
		return
	# 武器掉落物：画**那把武器自己的图标**（和玩家身上挂件同一张 mount_*.png），
	# 这样地上一眼能看出捡的是什么。拿不到图标（未知 id / 资源缺失）时退回下面
	# 的通用 weapon.png。
	if kind == Kind.WEAPON and weapon_id != "":
		var wtex: Texture2D = WeaponDirector.icon_of(weapon_id)
		if wtex != null:
			sprite.texture = wtex
			# 武器图标是横向长条（枪口朝 +X），比 16x16 的道具图标窄。放大到和
			# 其它掉落物差不多的视觉体量，并居中（掉落物不像挂件那样绕枪柄转）。
			sprite.scale = Vector2(WEAPON_ICON_SCALE, WEAPON_ICON_SCALE)
			sprite.offset = Vector2.ZERO
			sprite.modulate = Color(1, 1, 1)
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
		Kind.MAGNET: return "magnet.png"
	return "heal.png"

func _fallback_color() -> Color:
	match kind:
		Kind.HEAL: return Color(0.9, 0.3, 0.35)
		Kind.WEAPON: return Color(1.0, 0.8, 0.35)
		Kind.BOMB: return Color(0.95, 0.55, 0.2)
		Kind.TIME_STOP: return Color(0.5, 0.85, 1.0)
		Kind.SHIELD: return Color(0.4, 1.0, 0.95)
		Kind.MAGNET: return Color(0.85, 0.6, 1.0)
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
