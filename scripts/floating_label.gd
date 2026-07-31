extends Node2D
## Short-lived floating label that rises upward and fades out.

@onready var label: Label = $Label

var _life: float = 0.7
var _elapsed: float = 0.0
var _rise_speed: float = 40.0

func setup(text: String, color: Color, font_size: int = 20, life: float = 0.7) -> void:
	_life = max(0.1, life)
	# Defer, since label may not be ready when instantiated + added same frame.
	call_deferred("_apply", text, color, font_size)

func _apply(text: String, color: Color, font_size: int) -> void:
	if label == null:
		return
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	# Random horizontal jitter so multiple labels don't overlap perfectly.
	position.x += randf_range(-8.0, 8.0)

func _process(delta: float) -> void:
	_elapsed += delta
	position.y -= _rise_speed * delta
	if label:
		var alpha: float = clamp(1.0 - _elapsed / _life, 0.0, 1.0)
		label.modulate.a = alpha
	if _elapsed >= _life:
		queue_free()
