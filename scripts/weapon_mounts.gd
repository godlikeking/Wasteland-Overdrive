extends Node2D
## Draws one small icon per weapon the player currently holds, mounted at a
## fixed offset on the body. Each icon pivots in place toward whatever its own
## weapon is aiming at.
##
## The weapon list is read straight off our parent's children, because
## WeaponDirector always add_child()s weapons onto the player itself (see
## weapon_director.gd add_weapon / add_weapon_with_extras). Reading the tree
## rather than the director means fusion consuming base weapons, death/restart
## teardown and the director's own stale-ref pruning all flow through here for
## free, with no extra signals to keep in sync.

## Mount offsets in player-local px, chosen per weapon count so a lone fused
## weapon sits centred on the shoulder instead of lopsided on one hip.
## The player sprite is 48x48 (16px art at 3x) with a 14px collision radius,
## so these sit right at the body edge.
const MOUNT_LAYOUTS := {
	1: [Vector2(0, -18)],
	2: [Vector2(-16, 6), Vector2(16, 6)],
	3: [Vector2(-16, 8), Vector2(16, 8), Vector2(0, -18)],
	4: [Vector2(-17, 8), Vector2(17, 8), Vector2(-13, -15), Vector2(13, -15)],
	5: [Vector2(-17, 9), Vector2(17, 9), Vector2(-15, -8), Vector2(15, -8), Vector2(0, -22)],
	6: [
		Vector2(-18, 11), Vector2(18, 11),
		Vector2(-20, -2), Vector2(20, -2),
		Vector2(-12, -18), Vector2(12, -18),
	],
}
## Beyond the hand-tuned table (7–12 weapons) mounts go on two concentric rings.
## One ring can't hold 12 icons without them merging into a blob, and simply
## growing a single radius would float the guns off the 48x48 body.
const INNER_RADIUS: float = 20.0
const OUTER_RADIUS: float = 34.0
## Most icons the inner ring will take. Above that the split is even (half in,
## half out) so neither ring gets crowded while the other sits nearly empty.
const INNER_CAP: int = 6
## More than this many weapons and the icons shrink; 12 full-size guns on a 48px
## sprite read as one unrecognisable mass.
const CROWDED_THRESHOLD: int = 6
const CROWDED_ICON_SCALE: float = 0.75
const FALLBACK_RADIUS: float = 20.0   # even ring, if we ever exceed the table
const AIM_REFRESH: float = 0.06       # sec between target scans
const TURN_SPEED: float = 10.0        # rad/sec, how fast an icon swings around
const DEFAULT_ICON_SIZE: Vector2 = Vector2(18, 6)

var _weapons: Array[BaseWeapon] = []
var _icons: Array[Sprite2D] = []
var _aims: Array[Vector2] = []        # last non-zero aim, parallel to _icons
var _dirty: bool = true
var _aim_accum: float = 0.0

func _ready() -> void:
	z_index = 1
	var p: Node = get_parent()
	if p:
		p.child_entered_tree.connect(_mark_dirty)
		p.child_exiting_tree.connect(_mark_dirty)

func _mark_dirty(_node: Node) -> void:
	# Rebuild on the next frame rather than right now: child_exiting_tree fires
	# *before* the node leaves, so get_children() would still hand it back.
	_dirty = true

func _process(delta: float) -> void:
	if _dirty:
		_dirty = false
		_rebuild()
	if _icons.is_empty():
		return
	# Scanning the enemies group can mean 60+ distance checks per weapon, so
	# retarget on a timer and only interpolate every frame.
	_aim_accum += delta
	var refresh: bool = _aim_accum >= AIM_REFRESH
	if refresh:
		_aim_accum = 0.0
	var t: float = minf(1.0, TURN_SPEED * delta)
	for i in range(_icons.size()):
		var icon: Sprite2D = _icons[i]
		if not is_instance_valid(icon):
			continue
		if refresh:
			var w: BaseWeapon = _weapons[i]
			if is_instance_valid(w):
				var aim: Vector2 = w.get_aim_direction()
				if aim != Vector2.ZERO:
					_aims[i] = aim
		if _aims[i] == Vector2.ZERO:
			continue   # never had a target — leave the icon at its rest angle
		icon.rotation = lerp_angle(icon.rotation, _aims[i].angle(), t)

func _rebuild() -> void:
	var found: Array[BaseWeapon] = []
	var p: Node = get_parent()
	if p:
		for c in p.get_children():
			if c is BaseWeapon and not c.is_queued_for_deletion():
				found.append(c as BaseWeapon)
	if _same_weapons(found):
		return
	# Carry each surviving weapon's angle across the rebuild, so gaining a new
	# weapon doesn't visibly snap the ones already mounted back to zero.
	var kept: Dictionary = {}
	for i in range(_weapons.size()):
		var w: BaseWeapon = _weapons[i]
		if not (is_instance_valid(w) and w.config):
			continue
		if i < _icons.size() and is_instance_valid(_icons[i]):
			kept[w.config.id] = {"rot": _icons[i].rotation, "aim": _aims[i]}
	for icon in _icons:
		if is_instance_valid(icon):
			icon.queue_free()
	_icons.clear()
	_aims.clear()
	_weapons = found

	var slots: Array = _slots_for(found.size())
	var icon_scale: float = _icon_scale_for(found.size())
	for i in range(found.size()):
		var w: BaseWeapon = found[i]
		var icon: Sprite2D = _make_icon(w.config)
		icon.position = slots[i]
		icon.scale = Vector2(icon_scale, icon_scale)
		add_child(icon)
		_icons.append(icon)
		var wid: String = w.config.id if w.config else ""
		if kept.has(wid):
			var prev: Dictionary = kept[wid] as Dictionary
			icon.rotation = float(prev["rot"])
			_aims.append(prev["aim"] as Vector2)
		else:
			_aims.append(Vector2.ZERO)

## Compare by reference, element-wise. Avoids leaning on Array == semantics and
## keeps a no-op rebuild (any unrelated child added to the player) truly free.
func _same_weapons(found: Array[BaseWeapon]) -> bool:
	if found.size() != _weapons.size():
		return false
	for i in range(found.size()):
		if found[i] != _weapons[i]:
			return false
	return true

## Mount offsets for `n` weapons: the hand-tuned table up to 6, then a
## two-ring layout. The outer ring is rotated by half a step so its icons sit in
## the gaps between the inner ones instead of directly on top of them.
func _slots_for(n: int) -> Array:
	if MOUNT_LAYOUTS.has(n):
		return MOUNT_LAYOUTS[n]
	if n <= 0:
		return []
	var inner_n: int = mini(INNER_CAP, ceili(float(n) * 0.5))
	var outer_n: int = n - inner_n
	if outer_n <= 0:
		# Only reachable if the table ever loses an entry it used to have.
		var out: Array = []
		for i in range(n):
			var a: float = -PI * 0.5 + TAU / float(n) * float(i)
			out.append(Vector2(cos(a), sin(a)) * FALLBACK_RADIUS)
		return out
	var slots: Array = []
	var inner_step: float = TAU / float(inner_n)
	for i in range(inner_n):
		var a: float = -PI * 0.5 + inner_step * float(i)
		slots.append(Vector2(cos(a), sin(a)) * INNER_RADIUS)
	var outer_step: float = TAU / float(outer_n)
	for i in range(outer_n):
		var a: float = -PI * 0.5 + outer_step * (float(i) + 0.5)
		slots.append(Vector2(cos(a), sin(a)) * OUTER_RADIUS)
	return slots

## Icon scale for `n` weapons. Shrinks once the body gets crowded.
func _icon_scale_for(n: int) -> float:
	return CROWDED_ICON_SCALE if n > CROWDED_THRESHOLD else 1.0

func _make_icon(cfg: WeaponConfig) -> Sprite2D:
	var s := Sprite2D.new()
	var size: Vector2 = cfg.icon_size if cfg else DEFAULT_ICON_SIZE
	if size.x <= 0.0 or size.y <= 0.0:
		size = DEFAULT_ICON_SIZE
	if cfg and cfg.icon:
		s.texture = cfg.icon
		# Real artwork carries its own dimensions, so pivot off those rather than
		# icon_size (which only ever described the generated placeholder bar).
		# Lets us drop in art of any size without touching the .tres.
		size = cfg.icon.get_size()
	else:
		s.texture = _placeholder(size, cfg.sprite_color if cfg else Color(1, 1, 1, 1))
	# Draw forward from the pivot instead of centred on it, so rotating the icon
	# swings a barrel out toward the target rather than spinning about its middle.
	# The art is authored pointing along +X (grip at the left edge), matching
	# rotation 0, so the grip lands on the mount point.
	s.offset = Vector2(size.x * 0.5, 0.0)
	return s

## Placeholder bar until real artwork lands: bright at the grip, dark at the
## muzzle, so even a plain rotated rectangle reads as "pointy end forward".
## Same GradientTexture2D stand-in that player.tscn / blade.tscn already use.
func _placeholder(size: Vector2, tint: Color) -> Texture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([
		tint,
		Color(tint.r * 0.35, tint.g * 0.35, tint.b * 0.35, tint.a),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = maxi(2, int(size.x))
	tex.height = maxi(2, int(size.y))
	tex.fill_from = Vector2(0.0, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex

# --- Read-only accessors, used by the headless self-test ---

func icon_count() -> int:
	return _icons.size()

func icons() -> Array[Sprite2D]:
	return _icons.duplicate()

func mounted_ids() -> Array[String]:
	var out: Array[String] = []
	for w in _weapons:
		if is_instance_valid(w) and w.config:
			out.append(w.config.id)
	return out
