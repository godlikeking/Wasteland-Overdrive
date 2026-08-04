extends Node2D
## Visual for GameState.shield_charges: a cyan ring around the player, one arc
## segment per remaining charge, brighter the more charges are stacked.
##
## Purely reactive — it owns no state, it just redraws on `shield_changed`. The
## absorb logic lives in player.take_damage / GameState.consume_shield.

## Ring radius, a little outside the 48px player sprite so it never hides it.
const RADIUS: float = 30.0
const WIDTH: float = 3.0
## Gap between arc segments, in radians, so the charge count is countable.
const SEG_GAP: float = 0.22
const SPIN_SPEED: float = 0.9   # rad/sec

var _charges: int = 0
var _spin: float = 0.0

func _ready() -> void:
	add_to_group("shield_ring")
	z_index = 5
	_charges = int(GameState.shield_charges)
	GameState.shield_changed.connect(_on_shield_changed)
	visible = _charges > 0

func _process(delta: float) -> void:
	if _charges <= 0:
		return
	# Slow spin so the ring reads as active rather than a static decal.
	_spin = fmod(_spin + SPIN_SPEED * delta, TAU)
	queue_redraw()

func _on_shield_changed(charges: int) -> void:
	var gained: bool = charges > _charges
	_charges = charges
	visible = _charges > 0
	if gained:
		_pop()
	queue_redraw()

## Brief scale pop when a charge is added, so picking up a shield registers.
func _pop() -> void:
	scale = Vector2(0.7, 0.7)
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _draw() -> void:
	if _charges <= 0:
		return
	# More charges = brighter, capped so a big stack doesn't wash out the scene.
	var alpha: float = minf(0.9, 0.4 + 0.12 * float(_charges))
	var col := Color(0.45, 0.95, 1.0, alpha)
	var seg: float = TAU / float(_charges)
	for i in range(_charges):
		var from: float = _spin + seg * float(i) + SEG_GAP * 0.5
		var to: float = _spin + seg * float(i + 1) - SEG_GAP * 0.5
		draw_arc(Vector2.ZERO, RADIUS, from, to, 24, col, WIDTH, true)
