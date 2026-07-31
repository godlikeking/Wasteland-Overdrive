extends Camera2D
## Camera with a screen-shake helper. Called via `shake(strength, duration)`.
## Shake uses a decaying offset so it always returns to center.

var _shake_strength: float = 0.0
var _shake_time_left: float = 0.0
var _shake_duration: float = 0.0
var _base_offset: Vector2

func _ready() -> void:
	add_to_group("shake_camera")
	_base_offset = offset

func _process(delta: float) -> void:
	if _shake_time_left > 0.0:
		_shake_time_left -= delta
		# Decay curve — full strength at start, zero at end.
		var t: float = clamp(_shake_time_left / _shake_duration, 0.0, 1.0)
		var s: float = _shake_strength * t
		offset = _base_offset + Vector2(
			randf_range(-s, s),
			randf_range(-s, s)
		)
		if _shake_time_left <= 0.0:
			offset = _base_offset

func shake(strength: float, duration: float = 0.25) -> void:
	# If a stronger shake is already active, keep it.
	if strength * duration > _shake_strength * _shake_time_left:
		_shake_strength = strength
		_shake_duration = max(0.01, duration)
		_shake_time_left = _shake_duration
