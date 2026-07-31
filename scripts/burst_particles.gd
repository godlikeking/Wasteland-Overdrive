extends CPUParticles2D
## Simple particle burst that auto-destroys after emission finishes.
## Supports optional color override and a "kill" mode (more particles,
## bigger, with a brief starburst) for enemy deaths.

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

## Override particle color and bump size/count for "kill" feedback.
func configure_kill(c: Color = Color(0.95, 0.4, 0.35, 1)) -> void:
	color = c
	amount = 28
	scale_amount_min = 3.0
	scale_amount_max = 5.5
	initial_velocity_min = 130.0
	initial_velocity_max = 280.0
	lifetime = 0.55
	gravity = Vector2(0, 60)
