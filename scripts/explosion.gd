extends Node2D
## One-shot radial blast: damages every enemy inside `radius`, draws an
## expanding shockwave ring, then frees itself.
##
## Shared by the bomb pickup item and the mine weapon, which is why the damage
## and radius are set through `setup()` instead of being baked in — the pickup
## wants a big screen-clearing hit, the mine a smaller one.

## Ring animation length. The damage is dealt immediately on spawn; this is
## purely how long the visual takes.
const FLASH_TIME: float = 0.35

var radius: float = 420.0
var damage: float = 60.0
## Damage falls off to this fraction at the very edge of the blast, so standing
## on the rim is meaningfully better than standing on top of it.
var edge_damage_pct: float = 0.45

var _age: float = 0.0
var _color: Color = Color(1.0, 0.72, 0.28)

func setup(p_radius: float, p_damage: float, p_color: Color = Color(1.0, 0.72, 0.28)) -> void:
	radius = maxf(1.0, p_radius)
	damage = maxf(0.0, p_damage)
	_color = p_color

func _ready() -> void:
	add_to_group("explosions")
	z_index = 20
	_detonate()

func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _age >= FLASH_TIME:
		queue_free()

func _detonate() -> void:
	var hit: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D) or not e.has_method("take_damage"):
			continue
		var enemy := e as Node2D
		var d: float = enemy.global_position.distance_to(global_position)
		if d > radius:
			continue
		# Linear falloff from full damage at the centre to edge_damage_pct at
		# the rim.
		var t: float = clampf(d / radius, 0.0, 1.0)
		var dmg: float = damage * lerpf(1.0, edge_damage_pct, t)
		var dir: Vector2 = (enemy.global_position - global_position).normalized()
		enemy.take_damage(dmg, dir)
		hit += 1
	# Shake scales with the blast so a 150px mine doesn't rattle the screen as
	# hard as the 420px bomb pickup.
	GameState.request_camera_shake.emit(clampf(radius / 60.0, 2.0, 9.0), 0.35)
	if hit > 0:
		GameState.request_hit_stop.emit(0.08)
	SfxPlayer.play("boom")

func _draw() -> void:
	var t: float = clampf(_age / FLASH_TIME, 0.0, 1.0)
	# Ring races outward while fading; a soft filled core sells the flash.
	var r: float = radius * ease(t, 0.4)
	var fade: float = 1.0 - t
	var ring: Color = _color
	ring.a = fade
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, ring, 6.0, true)
	var core: Color = _color
	core.a = fade * 0.28
	draw_circle(Vector2.ZERO, r * 0.85, core)
