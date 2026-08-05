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

## Item drops (Iter8). How many PickupItems this archetype leaves behind when it
## dies, and the probability (0..1) that it drops at all. `item_drop_count` is a
## COUNT not a chance, so ordinary trash mobs use a small chance (e.g. 0.06) with
## count 1, while elites/bosses drop guaranteed with chance 1.0. The scene ref is
## injected at runtime by SpawnDirector (same as xp_gem_scene) so the .tres files
## stay scene-free.
@export var item_drop_count: int = 0
@export var item_drop_chance: float = 1.0
@export var item_drop_scene: PackedScene

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

## BOSS 近战爪击。一次离散重击，走 Player.take_damage（无敌帧和护盾本来就是
## 为这种攻击设计的），不走 DoT 通道。
## reach/arc 决定楔形判定，windup 是预警时长 —— 朝向在预警开始时就锁死，
## 所以横向拉开才是反制手段；把 windup 调到 0 等于取消这个攻击的可躲性。
@export var boss_claw_damage: float = 34.0
@export var boss_claw_reach: float = 190.0
@export var boss_claw_arc: float = 1.9            # 弧宽（弧度），≈109°
@export var boss_claw_windup: float = 0.45        # 预警时长，期间巨兽定住脚
@export var boss_claw_cooldown: float = 2.6

## BOSS 远程毒物。抛出 boss_poison_count 团毒液，飞行 flight 秒后落地成池；
## 毒团飞行途中不伤人（落点才是威胁，这也是玩家的躲避线索），全部伤害由
## 毒池按 tick 走 Player.take_dot_damage 结算。
##
## 飞行用**固定时长**而不是固定速度：预警窗口必须与距离无关，否则贴身喷的毒
## 会在玩家能反应之前就落地，而远处喷的又慢到没有威胁。这也是这里没有
## `boss_poison_speed` 的原因 —— 那个旋钮曾经存在过，但没有任何代码读它。
@export var boss_poison_interval: float = 3.0
@export var boss_poison_count: int = 3
@export var boss_poison_flight: float = 0.55
@export var boss_poison_pool_radius: float = 95.0
@export var boss_poison_pool_life: float = 6.0
@export var boss_poison_dps: float = 14.0
@export var boss_poison_tick: float = 0.5
