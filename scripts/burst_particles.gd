extends CPUParticles2D
## Simple particle burst that auto-destroys after emission finishes.

func _ready() -> void:
	emitting = true
	# Convert lifetime + explosiveness into a self-destroy timer.
	var life: float = lifetime + 0.1
	get_tree().create_timer(life, true, false, false).timeout.connect(queue_free)

func set_hit_direction(dir: Vector2) -> void:
	# Optional API used by fx_manager to bias direction of explosion.
	if dir.length_squared() > 0.01:
		direction = dir.normalized()
		spread = 55.0
	else:
		direction = Vector2.RIGHT
		spread = 180.0
