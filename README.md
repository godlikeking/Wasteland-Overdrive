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
- **升级**时弹出三张升级卡，选择一张永久强化本局角色
- **接触敌人**扣血，血量归零结算重开

## 已实现

- [x] 玩家移动与相机跟随
- [x] 自动开火（射速、伤害、多弹）
- [x] 敌人生成器（波次/密度随时间上升）
- [x] 敌人追踪 AI + 接触伤害
- [x] 经验宝石掉落与吸附
- [x] 等级系统 + 三选一被动升级
- [x] HUD（血量、经验、等级、计时）
- [x] 死亡结算 & 重开

## 已内建的 8 项被动升级

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

## 项目结构

```
SecondGame/
├── project.godot              # 项目入口，输入映射、autoload、主题
├── icon.svg                    # 项目图标
├── assets/ui/default_theme.tres  # 中文字体回退主题
├── scenes/
│   ├── main.tscn              # 主场景（包裹 game.tscn）
│   ├── game.tscn              # 战斗场景（玩家 + 生成器 + UI）
│   ├── player.tscn            # 玩家 + Camera + AutoGun + PickupArea
│   ├── enemy.tscn             # 追踪型敌人
│   ├── bullet.tscn            # 直线飞行子弹
│   ├── xp_gem.tscn            # 经验宝石
│   └── ui/
│       ├── hud.tscn
│       ├── level_up.tscn
│       ├── upgrade_card.tscn
│       └── game_over.tscn
└── scripts/
    ├── globals/
    │   ├── game_state.gd      # Autoload: 状态 + 事件总线 + 属性倍率
    │   └── upgrade_db.gd      # Autoload: 升级数据表
    ├── player.gd
    ├── auto_gun.gd
    ├── bullet.gd
    ├── enemy.gd
    ├── enemy_spawner.gd
    ├── xp_gem.gd
    ├── game.gd
    ├── hud.gd
    ├── level_up.gd
    ├── upgrade_card.gd
    └── game_over.gd
```

## 物理层约定

| 层 | 用途 |
|---|---|
| 1 World | 保留（当前无实体墙） |
| 2 Player | 玩家 body + 拾取 area |
| 3 PlayerBullet | 玩家子弹 |
| 4 Enemy | 敌人 body |
| 5 Pickup | 经验宝石 |

- 玩家 body: layer=2, mask=1（暂无墙）
- 玩家 PickupArea: layer=2, mask=16（检测宝石）
- 子弹: layer=4, mask=8（打敌人）
- 敌人: layer=8, mask=3（碰玩家 + 世界）
- 经验宝石: layer=16, mask=2（被玩家 PickupArea 吸引）

## 运行

1. 安装 [Godot 4.2+](https://godotengine.org/download)（GL 兼容模式）
2. 在 Godot 编辑器 `Import` 本目录（选择 `project.godot`）
3. 首次导入完成后按 **F5** 或点击右上角运行
4. 主场景已配置为 `res://scenes/main.tscn`

## 已知限制 / 后续可扩展

- 无实际美术：所有对象为纯色占位（`PlaceholderTexture2D`）
- 无音效
- 单一敌人类型，无远程敌人 / 精英 / Boss
- 单一武器（AutoGun），无武器切换 / 融合
- 无地图边界，无 Tilemap 地形
- 无存档 / 元进度系统
- 生成密度只随时间线性上升，未做波次编排

## 扩展路线（不属于 MVP）

- CC0 像素素材接入（Kenney、itch.io）
- Tilemap 废土地形 + 障碍物
- 多种武器 + 融合升级
- 远程敌人、精英、Boss
- 元进度存档（跨局解锁）
- 音效 / 屏幕震动 / 击杀特效
