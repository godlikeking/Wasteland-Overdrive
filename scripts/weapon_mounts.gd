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

## Every mount sits on the player's LEFT or RIGHT side — never on the front or
## back — so the silhouette reads as "guns strapped to both hips" at any arsenal
## size. Slots are handed out RIGHT column first, then left, alternating, so the
## starter weapon (the first one granted) lands on the player's right hand and
## the columns stay balanced as the arsenal grows.
##
## The player sprite is 48x48 (16px art at 3x) with a 14px collision radius, so
## SIDE_X sits right at the body edge.
const SIDE_X: float = 20.0
## Vertical spacing between icons within one column, at full icon scale. The art
## is 16px tall (apocalypse 20px), so 18 leaves a small gap instead of letting
## neighbours swallow each other. Scaled by the crowding shrink in `slots_for`,
## since shrunken icons need proportionally less room.
const SIDE_STEP: float = 18.0
## More than this many weapons and the icons shrink; 12 full-size guns on a 48px
## sprite read as one unrecognisable mass.
const CROWDED_THRESHOLD: int = 6
const CROWDED_ICON_SCALE: float = 0.75
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
	# weapon doesn't visibly snap the ones already mounted back to zero. Keyed by
	# instance id (not config id) so several copies of the same weapon each keep
	# their own angle instead of collapsing into one.
	var kept: Dictionary = {}
	for i in range(_weapons.size()):
		var w: BaseWeapon = _weapons[i]
		if not (is_instance_valid(w) and w.config):
			continue
		if i < _icons.size() and is_instance_valid(_icons[i]):
			kept[w.get_instance_id()] = {"rot": _icons[i].rotation, "aim": _aims[i]}
	for icon in _icons:
		if is_instance_valid(icon):
			icon.queue_free()
	_icons.clear()
	_aims.clear()
	_weapons = found

	var slots: Array = slots_for(found.size())
	var icon_scale: float = _icon_scale_for(found.size())
	for i in range(found.size()):
		var w: BaseWeapon = found[i]
		var icon: Sprite2D = _make_icon(w.config)
		icon.position = slots[i]
		icon.scale = Vector2(icon_scale, icon_scale)
		add_child(icon)
		_icons.append(icon)
		if kept.has(w.get_instance_id()):
			var prev: Dictionary = kept[w.get_instance_id()] as Dictionary
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

## Mount offsets for `n` weapons: two vertical columns hugging the player's
## right and left sides. Slots alternate RIGHT, left, RIGHT, left... so weapon 0
## (the starter) sits in the right hand and the columns stay within one of each
## other as the arsenal grows. Each column is centred vertically on the body, so
## the guns spread symmetrically above and below the waist instead of growing
## downward off the sprite.
func slots_for(n: int) -> Array:
	if n <= 0:
		return []
	var right_n: int = ceili(float(n) * 0.5)
	var left_n: int = n - right_n
	# Icons that shrink need proportionally less room, and a 6-per-side column at
	# the full-scale step would hang well off the sprite.
	var step: float = SIDE_STEP * _icon_scale_for(n)
	# Distance from the column centre to its first icon.
	var right_half: float = float(right_n - 1) * 0.5 * step
	var left_half: float = float(left_n - 1) * 0.5 * step
	var slots: Array = []
	for i in range(n):
		# Even indices go right, odd go left; the rank within the column is the
		# number of earlier icons that landed on the same side.
		var rank: int = i / 2
		if i % 2 == 0:
			slots.append(Vector2(SIDE_X, -right_half + step * float(rank)))
		else:
			slots.append(Vector2(-SIDE_X, -left_half + step * float(rank)))
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
	# Duplicates are legal now (the player can hold several copies of one
	# weapon), so this lists each id once per copy held.
	var out: Array[String] = []
	for w in _weapons:
		if is_instance_valid(w) and w.config:
			out.append(w.config.id)
	return out
