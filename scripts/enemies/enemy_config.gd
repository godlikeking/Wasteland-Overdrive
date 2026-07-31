extends Resource
class_name EnemyConfig
## Data resource describing one enemy archetype. Create instances under
## res://data/enemies/ and pass them to SpawnDirector.

enum Behavior { CHASER, SHOOTER, DASHER, ELITE }

@export var id: String = "chaser"
@export var display_name: String = "拾荒者"
@export var behavior: Behavior = Behavior.CHASER

@export var scene: PackedScene          # the enemy .tscn
@export var sprite_color: Color = Color(0.85, 0.25, 0.25, 1)
@export var sprite_size: Vector2 = Vector2(20, 20)
@export var collision_radius: float = 12.0

# --- Stats ---
@export var max_hp: float = 20.0
@export var speed: float = 90.0
@export var contact_damage: float = 10.0
@export var contact_cooldown: float = 0.6
@export var xp_value: float = 1.0
@export var xp_gem_scene: PackedScene

# --- Behavior-specific ---
## DASHER: dash_interval, dash_speed_multiplier, dash_duration
@export var dash_interval: float = 2.5
@export var dash_speed_multiplier: float = 3.0
@export var dash_duration: float = 0.35

## SHOOTER: preferred distance to keep from player
@export var shoot_range: float = 220.0
@export var shoot_cooldown: float = 1.6
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 260.0
@export var projectile_damage: float = 8.0

## ELITE: extra drops / on-death shake
@export var elite_shake: float = 7.0
@export var elite_xp_multiplier: float = 4.0
