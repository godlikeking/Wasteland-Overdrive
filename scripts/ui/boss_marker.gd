extends Control
## Red arrow pinned to the screen edge pointing at the boss while it is off
## camera, plus the distance to it. The boss is the one enemy you have to go and
## find — everything else walks to you — so without this it can sit off-screen
## summoning minions while the player wanders.
##
## Lives on the HUD CanvasLayer, so its local coordinates ARE screen
## coordinates: the layer is not moved by the camera. World positions are
## converted with the viewport's canvas transform.

## Arrow size in px (tip-to-back), and how far inside the screen edge it sits.
const ARROW_SIZE: float = 22.0
const EDGE_MARGIN: float = 46.0
## Pulse, so the arrow reads as an alert rather than as part of the frame.
const PULSE_HZ: float = 2.2

var _boss: Node2D
var _pulse: float = 0.0

func _ready() -> void:
	# Purely decorative overlay: never eat a click meant for the game below.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameState.boss_spawned.connect(_on_boss_spawned)
	GameState.boss_defeated.connect(_on_boss_defeated)
	visible = false

func _process(delta: float) -> void:
	# The boss dies by queue_free, and a run can end with it still alive, so the
	# ref is re-validated every frame rather than trusted until boss_defeated.
	if _boss != null and not is_instance_valid(_boss):
		_boss = null
		visible = false
		return
	if _boss == null:
		return
	_pulse = fmod(_pulse + delta, 1000.0)
	queue_redraw()

func _on_boss_spawned(boss: Node2D) -> void:
	_boss = boss
	visible = true
	queue_redraw()

func _on_boss_defeated() -> void:
	_boss = null
	visible = false
	queue_redraw()

## Where to draw an edge marker for a target at `screen_pos`, given the screen
## `rect` and how far inside the edge the marker should sit.
##
## Returns `{offscreen: bool, pos: Vector2, angle: float}`. When the target is
## on screen there is nothing to point at and `pos` is just the target. When it
## is off screen, `pos` is the point where the ray from the screen centre to the
## target crosses the inset rectangle, and `angle` points outward along that ray.
##
## Static and pure because this is the only part of the arrow that can be wrong
## in a way worth testing — `_draw` output cannot be asserted headlessly, but
## "does the arrow sit on the edge and point at the target" can.
static func marker_for(screen_pos: Vector2, rect: Rect2, margin: float) -> Dictionary:
	var m: float = maxf(0.0, margin)
	# Clamp the inset so a window smaller than 2*margin degenerates to its
	# centre instead of producing a negative-size rect (and a mirrored arrow).
	var inset: Vector2 = Vector2(
		minf(m, rect.size.x * 0.5),
		minf(m, rect.size.y * 0.5))
	var inner := Rect2(rect.position + inset, rect.size - inset * 2.0)
	if inner.has_point(screen_pos):
		return {"offscreen": false, "pos": screen_pos, "angle": 0.0}
	var center: Vector2 = rect.get_center()
	var dir: Vector2 = screen_pos - center
	if dir.length_squared() < 0.000001:
		dir = Vector2.RIGHT
	# Ray-vs-box: scale the direction until it hits whichever half-extent it
	# reaches first. Cheaper and branch-free compared with clipping per side.
	var half: Vector2 = inner.size * 0.5
	var sx: float = INF if absf(dir.x) < 0.000001 else half.x / absf(dir.x)
	var sy: float = INF if absf(dir.y) < 0.000001 else half.y / absf(dir.y)
	var s: float = minf(sx, sy)
	return {
		"offscreen": true,
		"pos": center + dir * s,
		"angle": dir.angle(),
	}

func _draw() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	var xform: Transform2D = get_viewport().get_canvas_transform()
	var screen_pos: Vector2 = xform * _boss.global_position
	var rect := Rect2(Vector2.ZERO, get_viewport_rect().size)
	var m: Dictionary = marker_for(screen_pos, rect, EDGE_MARGIN)
	if not bool(m.get("offscreen", false)):
		return   # Visible on screen: the HUD bar already tells the story.
	var pos: Vector2 = m["pos"]
	var angle: float = m["angle"]
	var alpha: float = lerpf(0.55, 1.0, absf(sin(_pulse * PULSE_HZ * PI)))
	var col := Color(1.0, 0.2, 0.18, alpha)
	# Arrow points along `angle`, i.e. outward at the boss.
	var tip: Vector2 = pos + Vector2(ARROW_SIZE, 0).rotated(angle)
	var back_a: Vector2 = pos + Vector2(-ARROW_SIZE * 0.55, ARROW_SIZE * 0.72).rotated(angle)
	var back_b: Vector2 = pos + Vector2(-ARROW_SIZE * 0.55, -ARROW_SIZE * 0.72).rotated(angle)
	draw_colored_polygon(PackedVector2Array([tip, back_a, back_b]), col)
	# Dark outline: the arrow has to stay readable over a bright explosion.
	draw_polyline(PackedVector2Array([tip, back_a, back_b, tip]),
		Color(0, 0, 0, alpha * 0.8), 2.0)
	_draw_distance(pos, angle, alpha)

## Distance readout tucked just inside the arrow, so "which way" also answers
## "how far" — 2000px away and 300px away call for very different decisions.
func _draw_distance(pos: Vector2, angle: float, alpha: float) -> void:
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not is_instance_valid(player):
		return
	var dist: int = int(player.global_position.distance_to(_boss.global_position))
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var text: String = "%dm" % (dist / 10)
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	# Inward from the arrow, so the text never lands outside the viewport.
	var at: Vector2 = pos - Vector2(ARROW_SIZE + size.x * 0.5 + 6.0, 0).rotated(angle)
	draw_string(font, at - Vector2(size.x * 0.5, -size.y * 0.3), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.6, 0.55, alpha))
