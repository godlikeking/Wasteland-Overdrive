extends Node2D
## Visual for GameState.shield_charges: a cyan ring around the player, one arc
## segment per remaining charge, brighter the more charges are stacked.
##
## Purely reactive — it owns no shield state of its own, only a cached copy of
## the countdown to drive the expiry flash. The absorb logic lives in
## player.take_damage / GameState.consume_shield.

## Ring radius, a little outside the 48px player sprite so it never hides it.
const RADIUS: float = 30.0
const WIDTH: float = 3.0
## Gap between arc segments, in radians, so the charge count is countable.
const SEG_GAP: float = 0.22
const SPIN_SPEED: float = 0.9   # rad/sec
## Seconds before expiry at which the ring starts flashing. The shield now runs
## out on its own, so "it's about to go" has to be readable without looking away
## from the fight at the HUD countdown.
const WARN_LEAD: float = 4.0
## Flashes per second at the very end of the warning window. The rate ramps up
## as the timer drains, which reads as urgency rather than as decoration.
const WARN_HZ_MAX: float = 5.0

var _charges: int = 0
var _spin: float = 0.0
## Mirror of GameState.shield_left, used only to drive the expiry flash.
var _left: float = 0.0

func _ready() -> void:
	add_to_group("shield_ring")
	z_index = 5
	_charges = int(GameState.shield_charges)
	_left = GameState.shield_left
	GameState.shield_changed.connect(_on_shield_changed)
	GameState.shield_time_changed.connect(_on_shield_time_changed)
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

func _on_shield_time_changed(remaining: float) -> void:
	_left = remaining
	# No redraw here: _process already redraws every frame while charges exist,
	# and this fires every frame too — queueing twice would just be waste.

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
	alpha *= expiry_alpha_mult(_left)
	var col := Color(0.45, 0.95, 1.0, alpha)
	var seg: float = TAU / float(_charges)
	for i in range(_charges):
		var from: float = _spin + seg * float(i) + SEG_GAP * 0.5
		var to: float = _spin + seg * float(i + 1) - SEG_GAP * 0.5
		draw_arc(Vector2.ZERO, RADIUS, from, to, 24, col, WIDTH, true)

## Alpha multiplier for a shield with `remaining` seconds left: 1.0 until the
## warning window, then a flash that speeds up as it drains. Split out as a pure
## function of the remaining time so the flash can be asserted headlessly —
## `_draw` output can't be.
##
## `remaining <= 0` means "no timer known" (the ring is also used before the
## first time signal arrives), so it stays fully lit rather than blinking.
static func expiry_alpha_mult(remaining: float) -> float:
	if remaining <= 0.0 or remaining > WARN_LEAD:
		return 1.0
	var urgency: float = 1.0 - remaining / WARN_LEAD   # 0 at the start, 1 at zero
	var hz: float = lerpf(1.5, WARN_HZ_MAX, urgency)
	# Phase off `remaining` rather than an accumulator: the flash is then a pure
	# function of the timer, so it can't drift out of sync with the countdown.
	var wave: float = absf(sin(remaining * hz * PI))
	return lerpf(0.35, 1.0, wave)
