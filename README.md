# Wasteland Roguelite (SecondGame)

一个用 **Godot 4.6 + GDScript** 开发的 2D 俯视角科幻废土肉鸽射击 MVP，玩法参考《吸血鬼幸存者》（Vampire Survivors）。当前版本是**最小可玩原型**，专注核心循环，暂无美术资源，所有可视对象为占位色块。

## 启动自检 (SystemCheck)

工程自带一个 autoload `SystemCheck`，每次运行会在编辑器 **Output** 面板打印诊断：

```
========== [SystemCheck] Startup diagnostics ==========
[SystemCheck] autoload 'GameState' OK
[SystemCheck] script res://scripts/player.gd OK
[SystemCheck] scene res://scenes/game.tscn OK
[SystemCheck] input 'move_up' OK
[SystemCheck] UpgradeDB.roll(3) returned 3 upgrades OK
[SystemCheck] OK — all checks passed.
=======================================================
```

- **全部 OK** → 环境正常，进入游戏。
- **看到 `[SystemCheck] FAIL: ...`** → 按照错误内容修复；每行 FAIL 说明是哪个脚本/场景/autoload/输入映射出问题。
- 场景加载器 `Game` 节点也会打印 `[Game] ready OK` 或列出缺失的子节点。

如果 F5 报错，请把 Output 面板里以 `[SystemCheck]` 或 `[Game]` 或 `SCRIPT ERROR:` 开头的红字贴出来。

## 玩法

- **WASD / 方向键**：移动
- **Esc**：暂停 / 继续
- 武器**自动**锁定并射击最近敌人
- 击杀敌人掉落蓝色**经验宝石**，走近自动吸取
- **升级**时弹出三张升级卡（被动强化 / 解锁新武器 / 武器升级），选择一张永久强化本局角色
- **接触敌人**扣血，血量归零结算重开
- **地图**：4096×4096 像素的程序化废土地形，含沙地 / 瓦砾 / 废铁 / 地坑 / **毒沼**（减速 + 持续扣血）
- 撞墙：玩家和敌人都被瓦砾 / 废铁 / 地坑挡住，**敌人在 0.4s 同步后会自动绕路**

## 已实现

- [x] 玩家移动与相机跟随
- [x] 自动开火（射速、伤害、多弹）
- [x] 敌人生成器（波次/密度随时间上升）
- [x] 敌人追踪 AI + 接触伤害
- [x] 经验宝石掉落与吸附
- [x] 等级系统 + 三选一被动升级
- [x] HUD（血量、经验、等级、计时）
- [x] 死亡结算 & 重开（含 WeaponDirector autoload 状态清理）
- [x] 手感抛光：屏幕震动 / 击中 hit-stop / 击杀与命中粒子 / 子弹拖尾 / 拾取与升级弹字
- [x] 多敌人（拾荒者 / 突袭者 / 哨兵 / 机械重装）+ SpawnDirector 波次编排
- [x] 数据驱动敌人（EnemyConfig Resource）+ 哨兵敌人射击子弹
- [x] 多武器系统：弹雨 / 旋转刀阵 / 闪电链 + 武器解锁与升级三选一卡
- [x] WeaponDirector autoload 管理武器槽与等级
- [x] **程序化废土 TileMap（运行时生成 5 种子瓦片，4096×4096 地图）**
- [x] **物理碰撞（瓦砾 / 废铁 / 地坑 写入 TileData collision_polygons）**
- [x] **毒沼：玩家和敌人减速 50% + 每 0.5s 扣 1 滴血**
- [x] **敌人 NavigationAgent2D 绕墙寻路（带 warmup + 三层 fallback）**
- [x] **SystemCheck 启动诊断：autoload / 脚本 / 场景 / 资源 / 输入 / 升级库**
- [x] **真实像素素材 (Kenney Tiny Dungeon 16×16)**：玩家 / 4 敌人 / 子弹 / 经验宝石 / 旋转刀
- [x] **程序化音效 SfxPlayer**：开火 / 命中 / 击杀 / 拾取 / 升级 共 5 短音（无外部 wav）
- [x] **连击系统**：连续击杀累积连击、1.5s 无击杀归零、3/8/15 三级（连击/爆发/烈焰）
- [x] **暴击系统**：基础 5% 暴击 + 连击加成（封顶 +30%），2× 伤害，暴击时飘 "暴击！"
- [x] **击杀爆裂粒子**：增强版 burst_particles（28 粒、彩尘，精英偏紫红）
- [x] **2 张新增被动升级**：暴击瞄准镜（+5%）、穿甲弹头（+0.5× 倍率）
- [x] **5 分钟 Boss 战**：废土巨兽（1000 HP、3 阶段、召唤小怪 + 弹幕，击杀 +50 废金属 + 紫红大爆裂）
- [x] **元进度（MetaProgress）**：永久货币、累计击杀 / Boss / 最佳时间，落盘 `user://meta_progress.json`
- [x] **5 项开局模块（模块商店）**：磁力 / 钛合金 / 瞄准镜 / 伺服 / 过载，每局开始自动应用
- [x] **装备融合（Fusion）**：3 基础武器全部 5 级时可触发融合面板；2 件组 → 雷暴弹雨 / 刀刃弹幕 / 闪电刀阵；3 件组 → 启示录（弹雨+链+刀 + 每 4s 整屏 nuke）

## 已内建的 10 项被动升级

| ID | 名称 | 效果 |
|---|---|---|
| `damage_up` | 枪管增强 | 伤害 +15% |
| `fire_rate_up` | 过载电容 | 射速 +15% |
| `move_speed_up` | 机动伺服 | 移速 +10% |
| `max_hp_up` | 钛合金外骨骼 | 生命上限 +25 |
| `pickup_radius_up` | 磁力回收 | 拾取半径 +30% |
| `xp_gain_up` | 神经加速 | 经验获取 +15% |
| `extra_projectile` | 分歧弹道 | 子弹数 +1 |
| `regen_up` | 纳米修复 | 每秒回血 +0.5 |
| `crit_rate_up` | 暴击瞄准镜 | 暴击率 +5% |
| `crit_damage_up` | 穿甲弹头 | 暴击伤害倍率 +0.5× |

## 融合配方（`WeaponDirector.FUSION_RECIPES`）

三把基础武器（弹雨 / 闪电链 / 旋转刀）全部升到 5 级后，下一次升级弹出融合面板。
融合会消耗配方里列出的基础武器，换成一把超级武器。

| 融合物 | 配方 | 行为 |
|---|---|---|
| 雷暴弹雨 `storm_volley` | 弹雨 + 闪电链 | 3 路弹扇（吃 `extra_projectile`）+ 0.4s 一次的 2 段电链（60% 伤害） |
| 刀刃弹幕 `blade_barrage` | 弹雨 + 旋转刀 | 6 把环绕刀轮流冲刺 + 4 路宽弹扇（80% 伤害） |
| 闪电刀阵 `lightning_blade` | 闪电链 + 旋转刀 | 4 把环绕刀轮流冲刺 + 0.8s 一次的 3 段电链，纯近战无弹道 |
| 启示录 `apocalypse` | 弹雨 + 闪电链 + 旋转刀 | 5 路弹扇 + 电链 + 8 把环绕刀，且每 4s 一次整屏 nuke（20% 伤害） |

融合前会先解析 `.tres` 与 `.tscn`，任一缺失就直接放弃并**保留**原有武器；
`fuse_candidates()` 也会跳过资源缺失的配方，不会把死选项摆到面板上。

自检（4 个配方 + 缺资源回归）：

```bash
godot --headless res://scenes/dev/fusion_selftest.tscn   # exit 0 = 全绿
```

## 瓦片类型（`data/world/default_wasteland.tres`）

| ID | 类型 | 物理 | 效果 |
|---|---|---|---|
| 0 | 沙地 | 无 | 正常通行 |
| 1 | 瓦砾 | 阻挡 | 物理碰撞 + 视觉是废铁/碎石 |
| 2 | 废铁 | 阻挡 | 物理碰撞 + 视觉是深色金属 |
| 3 | 地坑 | 阻挡 | 物理碰撞 + 视觉是深坑 |
| 4 | 毒沼 | **不挡** | 减速 50% + 每 0.5s 扣 1 滴血（玩家+敌人） |

默认 64×64 格地图、seed=1337，障碍合计 10%，毒沼 5%，出生点 11×11 安全区。

## 项目结构

```
SecondGame/
├── project.godot              # 项目入口，输入映射、autoload、主题
├── icon.svg                    # 项目图标
├── assets/ui/default_theme.tres  # 中文字体回退主题
├── scenes/
│   ├── main.tscn              # 主场景（包裹 game.tscn）
│   ├── game.tscn              # 战斗场景（玩家 + 生成器 + UI + World）
│   ├── player.tscn            # 玩家 + Camera + ToxicSwamp
│   ├── enemy.tscn             # 敌人 + NavigationAgent2D + ToxicSwamp
│   ├── bullet.tscn            # 直线飞行子弹
│   ├── enemy_projectile.tscn  # 敌人发射的子弹
│   ├── xp_gem.tscn            # 经验宝石
│   ├── fx/                    # 浮字 + 粒子
│   ├── ui/                    # HUD / LevelUp / GameOver / UpgradeCard
│   └── weapons/               # 3 武器 + 飞刀场景
├── scripts/
│   ├── globals/
│   │   ├── game_state.gd      # Autoload: 状态 + 事件总线 + 属性倍率
│   │   ├── upgrade_db.gd      # Autoload: 升级数据表（被动 + 武器解锁 + 武器升级）
│   │   └── system_check.gd    # Autoload: 启动期 autoload/脚本/场景/资源自检
│   ├── player.gd
│   ├── bullet.gd
│   ├── enemy.gd
│   ├── enemy_config.gd        # EnemyConfig 资源类
│   ├── enemy_projectile.gd
│   ├── spawn_director.gd      # 波次 + 敌人类型编排
│   ├── xp_gem.gd
│   ├── game.gd
│   ├── hud.gd
│   ├── level_up.gd
│   ├── upgrade_card.gd
│   ├── game_over.gd
│   ├── fx_manager.gd
│   ├── floating_label.gd
│   ├── burst_particles.gd
│   ├── shake_camera.gd
│   ├── weapon_director.gd     # Autoload: 武器槽 + 跨场景清理
│   ├── weapons/
│   │   ├── weapon.gd          # BaseWeapon 基类
│   │   ├── weapon_config.gd   # WeaponConfig 资源类
│   │   ├── bullet_volley.gd
│   │   ├── orbiting_blades.gd
│   │   ├── chain_lightning.gd
│   │   └── blade.gd
│   └── world/                 # Iter4: 程序化废土地形
│       ├── wasteland_config.gd   # 资源：地图尺寸/种子/密度
│       ├── tilemap_builder.gd    # 运行时生成 TileSet + 铺地图
│       ├── world.gd              # 场景入口（持有 TileMap）
│       └── toxic_swamp.gd        # 角色身上的毒沼 slow + dot 效果
├── data/
│   ├── enemies/               # 4 EnemyConfig .tres
│   ├── weapons/               # 3 WeaponConfig .tres
│   └── world/
│       └── default_wasteland.tres  # 64x64 地图默认配置（seed=1337）
└── README.md
```

## 物理层约定

| 层 | 用途 |
|---|---|
| 1 World | 瓦砾 / 废铁 / 地坑（瓦片 collision_polygon 自动注册） |
| 2 Player | 玩家 body + 拾取 area |
| 3 PlayerBullet | 玩家子弹 |
| 4 Enemy | 敌人 body |
| 5 Pickup | 经验宝石 |

- 玩家 body: layer=2, mask=1（被瓦片挡路）
- 玩家 PickupArea: layer=2, mask=16（检测宝石）
- 子弹: layer=4, mask=8（打敌人）
- 敌人: layer=8, mask=3（碰玩家 + 被瓦片挡路）
- 经验宝石: layer=16, mask=2（被玩家 PickupArea 吸引）
- 毒沼: **不参与物理碰撞**，由 `ToxicSwamp` 节点每帧检查 `_builder.is_swamp(pos)` 触发减速/扣血

## 运行

1. 安装 [Godot 4.2+](https://godotengine.org/download)（GL 兼容模式）
2. 在 Godot 编辑器 `Import` 本目录（选择 `project.godot`）
3. 首次导入完成后按 **F5** 或点击右上角运行
4. 主场景已配置为 `res://scenes/main.tscn`

## 已知限制 / 后续可扩展

- 瓦片仍是程序化生成（64×64 手绘），只有角色 / 子弹 / 宝石换成了 Kenney 像素图
- 音效是程序合成的 5 个短音，没有 BGM
- 毒沼只有减速/扣血，无视觉毒气动画
- 敌人寻路未启用 avoidance（避免 60+ 实体时性能塌方）
- 地图固定 4096×4096，未做"越打越大"扩展
- 融合是单向的，融合后无法拆回基础武器；一局最多融合一次（基础武器被消耗）

## 扩展路线（不属于 MVP）

- 替换程序化瓦片为真实像素艺术
- BGM + 更丰富的音效层次
- Boss 房间 + 多区域随机地图
- 融合武器自身的升级曲线（目前融合物固定 1 级）
- 毒气视觉 / 闪避 / 击退
