extends Resource
class_name WeaponConfig
## Data resource describing one weapon. Per-level upgrades multiply
## `damage` and `fire_rate` (per-second). Spawns a child scene under the
## Player and drives its behavior through the same Config.

@export var id: String = "bullet_volley"
@export var display_name: String = "弹雨"
@export var scene: PackedScene
@export var sprite_color: Color = Color(1, 0.85, 0.3, 1)

# --- On-body mount icon (drawn on the player by WeaponMounts) ---
# Real artwork when we have it; leave null and a placeholder bar is generated
# from icon_size + sprite_color, same trick player.tscn / blade.tscn already use.
@export var icon: Texture2D
@export var icon_size: Vector2 = Vector2(18, 6)

# Per-level stats — used by Weapon._ready to roll initial numbers.
@export var base_damage: float = 10.0
@export var base_fire_rate: float = 2.5
@export var max_level: int = 8

# Optional knobs (weapons read only the ones they need)
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 520.0
@export var projectile_lifetime: float = 1.2
@export var projectile_spread_deg: float = 6.0
# Max travel distance in px. 0 = unlimited (fall back to projectile_lifetime).
# Weapons also refuse to fire when no enemy sits inside this radius.
@export var projectile_range: float = 0.0

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

# --- Iter8 base weapons ---
# Shotgun. `pellet_count` is the base spread size; GameState.extra_projectiles
# still stacks on top, same as bullet_volley.
@export var pellet_count: int = 5

# Laser lance. Hitscan, so it has no projectile: everything inside a
# laser_length x laser_width band along the aim direction is hit at once.
@export var laser_length: float = 520.0
@export var laser_width: float = 26.0
@export var laser_cooldown: float = 1.4

# Mine layer. Mines arm after `mine_arm_time` so they can't detonate in the
# player's face, and self-destruct after `mine_lifetime`.
@export var mine_scene: PackedScene
@export var mine_interval: float = 2.2
@export var mine_arm_time: float = 0.4
@export var mine_lifetime: float = 8.0
@export var mine_blast_radius: float = 150.0
## Cap on simultaneously live mines, so a long run doesn't carpet the map.
@export var mine_max_active: int = 6

# Flamethrower. A cone that damages everything inside it every `flame_tick`.
@export var flame_range: float = 160.0
@export var flame_arc_deg: float = 60.0
@export var flame_tick: float = 0.15

# Homing dart. Radians per second the dart may turn toward its target; 0 would
# leave it an ordinary straight bullet.
@export var homing_turn_rate: float = 5.0
