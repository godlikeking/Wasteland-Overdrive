extends Resource
class_name EnemyConfig
## Data resource describing one enemy archetype. Create instances under
## res://data/enemies/ and pass them to SpawnDirector.

enum Behavior { CHASER, SHOOTER, DASHER, ELITE, BOSS }

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

## BOSS: 3-phase giant with high HP
@export var boss_summon_interval: float = 4.0    # 召唤小怪间隔
@export var boss_summon_count: int = 2           # 每次召唤小怪数
@export var boss_minion_id: String = "chaser"    # 召唤的小怪 id
@export var boss_bullet_count: int = 3           # 弹幕路数
@export var boss_bullet_interval: float = 1.2    # 弹幕间隔
@export var boss_bullet_speed: float = 200.0     # 弹幕速度
@export var boss_phase2_hp_frac: float = 0.6     # 进入 P2 阈值
@export var boss_phase3_hp_frac: float = 0.3     # 进入 P3 阈值
@export var boss_xp_multiplier: float = 20.0     # Boss 击杀经验倍率
@export var boss_shake_on_death: float = 14.0
