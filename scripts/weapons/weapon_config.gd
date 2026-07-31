extends Resource
class_name WeaponConfig
## Data resource describing one weapon. Per-level upgrades multiply
## `damage` and `fire_rate` (per-second). Spawns a child scene under the
## Player and drives its behavior through the same Config.

@export var id: String = "bullet_volley"
@export var display_name: String = "弹雨"
@export var scene: PackedScene
@export var sprite_color: Color = Color(1, 0.85, 0.3, 1)

# Per-level stats — used by Weapon._ready to roll initial numbers.
@export var base_damage: float = 10.0
@export var base_fire_rate: float = 2.5
@export var max_level: int = 8

# Optional knobs (weapons read only the ones they need)
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 520.0
@export var projectile_lifetime: float = 1.2
@export var projectile_spread_deg: float = 6.0

@export var blade_count: int = 3                 # orbiting blades
@export var blade_orbit_radius: float = 90.0
@export var blade_orbit_speed: float = 3.0       # rad/sec
@export var blade_dash_interval: float = 1.6
@export var blade_dash_speed: float = 520.0
@export var blade_dash_lifetime: float = 0.6

@export var chain_targets: int = 3               # chain lightning
@export var chain_range: float = 140.0
@export var chain_cooldown: float = 1.6
@export var chain_damage_falloff: float = 0.8    # each jump
