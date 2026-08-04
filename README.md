# Wasteland Roguelite (SecondGame)

一个用 **Godot 4.6 + GDScript** 开发的 2D 俯视角科幻废土肉鸽射击 MVP，玩法参考《吸血鬼幸存者》（Vampire Survivors）。角色 / 敌人 / 宝石用 Kenney Tiny Dungeon 像素图，武器挂件 / 子弹 / 道具是同调色板手画的（`tools/` 下可复现），地形仍是运行时程序化生成的瓦片。

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
- **升级**时弹出三张**被动**升级卡（武器不再从升级卡获得），选择一张永久强化本局角色
- **接触敌人**扣血，血量归零结算重开
- **地图**：4096×4096 像素的程序化废土地形，含沙地 / 瓦砾 / 废铁 / 地坑 / **毒沼**（减速 + 持续扣血）/ **精英营地**
- 撞墙：玩家和敌人都被瓦砾 / 废铁 / 地坑挡住，**敌人在 0.4s 同步后会自动绕路**
- **精英营地**：地图上 6 个锈红警戒条纹地砖圈，走近会刷出精英怪；杀掉掉 **1 个道具**，营地进 45s 冷却后重刷（详见「精英营地」一节）
- **道具**：补血 / 护盾 / 炸弹 / 时间暂停 / 武器 五种，走近自动吸取（详见「道具掉落」一节）
- **武器来源**：怪物掉落（含杂兵），可同时持有多把相同武器，**3 把同款同级武器自动合成 1 把更高级**（详见「武器合并」一节）
- 最多同时装备 **12 把武器**，挂件全部画在玩家左右两侧

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
- [x] 多武器系统：弹雨 / 旋转刀阵 / 闪电链 + 武器从怪物掉落（可重复持有）
- [x] WeaponDirector autoload 管理武器槽与等级
- [x] **程序化废土 TileMap（运行时生成 5 种子瓦片，4096×4096 地图）**
- [x] **武器合并**：3 把同款同级武器自动合成 1 把更高级（等级曲线 +100% 伤害 / +50% 射速，冷却型武器同步缩放）
- [x] **物理碰撞（瓦砾 / 废铁 / 地坑 写入 TileData collision_polygons）**
- [x] **毒沼：玩家和敌人减速 50% + 每 0.5s 扣 1 滴血**
- [x] **敌人 NavigationAgent2D 绕墙寻路（带 warmup + 三层 fallback）**
- [x] **SystemCheck 启动诊断：autoload / 脚本 / 场景 / 资源 / 输入 / 升级库**
- [x] **真实像素素材**：玩家 / 4 敌人 / 经验宝石 / 旋转刀取自 Kenney Tiny Dungeon 16×16；12 把武器挂件 + 2 种子弹 + 5 种道具手画（同调色板，`tools/` 下可复现）
- [x] **程序化音效 SfxPlayer**：开火 / 命中 / 击杀 / 拾取 / 升级 / 道具 / 爆炸 共 7 短音（无外部 wav）
- [x] **连击系统**：连续击杀累积连击、1.5s 无击杀归零、3/8/15 三级（连击/爆发/烈焰）
- [x] **暴击系统**：基础 5% 暴击 + 连击加成（封顶 +30%），2× 伤害，暴击时飘 "暴击！"
- [x] **击杀爆裂粒子**：增强版 burst_particles（28 粒、彩尘，精英偏紫红）
- [x] **2 张新增被动升级**：暴击瞄准镜（+5%）、穿甲弹头（+0.5× 倍率）
- [x] **5 分钟 Boss 战**：废土巨兽（1000 HP、3 阶段、召唤小怪 + 弹幕，击杀 +50 废金属 + 紫红大爆裂）
- [x] **元进度（MetaProgress）**：永久货币、累计击杀 / Boss / 最佳时间，落盘 `user://meta_progress.json`
- [x] **5 项开局模块（模块商店）**：磁力 / 钛合金 / 瞄准镜 / 伺服 / 过载，每局开始自动应用
- [x] **装备融合（Fusion）**：3 基础武器各持有一把 Lv3 副本时可触发融合面板（可选开启）；2 件组 → 雷暴弹雨 / 刀刃弹幕 / 闪电刀阵；3 件组 → 启示录（弹雨+链+刀 + 每 4s 整屏 nuke）
- [x] **精英营地**：地图程序化生成 6 处专属地砖营地，走近刷精英、杀死进 45s 冷却重刷
- [x] **道具系统**：补血 / 护盾 / 炸弹 / 时间暂停 / 武器 五种掉落，武器从怪物掉落获得（含杂兵）
- [x] **12 武器槽位**：`MAX_WEAPONS = 12`，满槽拦截，挂件走左右两列布局
- [x] **5 把新基础武器**：散弹枪 / 磁轨激光 / 地雷布设器 / 火焰喷射器 / 追踪飞镖（合计 8 基础 + 4 融合 = 12 个 id）

## 已内建的 12 项被动升级

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
| `pierce_up` | 贯穿弹芯 | 子弹穿透 +1（每次穿透伤害 ×0.8） |
| `range_up` | 磁轨加速管 | 子弹射程 +25% |

## 射程与穿透

子弹型武器都有射程上限（`WeaponConfig.projectile_range`，单位 px），由 `.tres` 数据驱动：

| 武器 | 射程 | 速度 | 到达时间 |
|---|---|---|---|
| `bullet_volley` 弹雨 | 420 | 520 | 0.81s |
| `blade_barrage` 刀刃弹幕 | 480 | 520 | 0.92s |
| `storm_volley` 雷暴弹雨 | 520 | 580 | 0.90s |
| `apocalypse` 启示录 | 620 | 620 | 1.00s |

- **射程内无敌人则不开火**，不再朝空处乱喷。寻敌走 `BaseWeapon._find_nearest_enemy(get_range())`，`get_range()` 会把 `GameState.weapon_range_mult` 乘进去。
- **射程优先于 lifetime**：`bullet.setup()` 里按 `max_distance / speed + 0.1` 反推 lifetime 下界，否则叠了「磁轨加速管」后 `projectile_lifetime` 会抢先掐断子弹，射程升级白买。
- **穿透**：`GameState.pierce_count` 决定一颗子弹能额外打穿几个敌人，第 n 次命中的伤害为 `damage × 0.8^(n-1)`。同一敌人对同一颗子弹只结算一次（敌人没有无敌帧，重复进出碰撞圈会重复扣血 + 刷连击）。
- 敌方弹幕（`enemy_projectile.tscn`）与敌人共用 layer 8，穿透扣减放在 `is_in_group("enemies")` 判断内部，所以飞过敌方弹幕不会白掉穿透次数。
- 旋转刀的冲刺与闪电链**不受射程约束**，它们各有 `blade_dash_lifetime` / `chain_range` 管着。
- **追踪飞镖的目标可能中途死掉**：`bullet.gd` 的 `_is_valid_target()` 参数刻意**不加静态类型**（`Variant`）。Godot 4 在**进入函数体之前**就会对静态类型的 Object 参数做检查并拒绝已释放的引用，所以把它标成 `Node2D` 会让「检查目标是否还活着」这件事本身在目标已释放时报错（`previously freed ... is not a subclass of the expected argument class`），而报错会中断整个 `_steer()`，飞镖就再也不会重新索敌、每个物理帧刷一条错误。同款 `Variant` 写法见 `elite_camp_director._is_alive()`。

自检（exit 0 = 全绿）：

```bash
godot --headless res://scenes/dev/range_pierce_selftest.tscn
godot --headless res://scenes/dev/fusion_selftest.tscn
```

## 武器挂件（显示在玩家身上）

`scenes/player.tscn` 下的 `WeaponMounts` 节点（`scripts/weapon_mounts.gd`）会为**每一把当前持有的武器**在玩家身上画一个小挂件。

**挂点布局**：一把武器都不摆在玩家正前 / 正后，**全部沿身体左右两侧排成两列竖线**（玩家视觉 48×48、碰撞半径 14，挂点贴在身体边缘）。槽位按 **右、左、右、左……** 交替发放，所以：

- **第 1 把（开局武器 `bullet_volley`）落在玩家右手边** `x=+20`
- 两列数量永远相差不超过 1（奇数时右列多一把）
- 每列纵向居中于身体，武器往腰上下均匀铺开，不会单向往下长出精灵

| 持有数 | 右列 / 左列 | 挂点（玩家局部坐标 px） |
|---|---|---|
| 1 | 1 / 0 | `(20, 0)` |
| 2 | 1 / 1 | `(20, 0)` `(-20, 0)` |
| 3 | 2 / 1 | `(20, ∓9)` `(-20, 0)` |
| 6 | 3 / 3 | `(±20, -18)` `(±20, 0)` `(±20, 18)` |
| 12 | 6 / 6 | `x=±20`，每列 6 个、纵向步长 13.5（含缩放） |

两列全是算出来的（`slots_for(n)`，没有手调表）：`SIDE_X=20` 固定横向贴边，`SIDE_STEP=18` 纵向等距。步长会**按图标缩放同比收缩**——挂件贴图高 16px（apocalypse 20px），满 18 的步长才留得出缝；而 n > 6 时图标 `scale = 0.75`，需要的间距同比变小，步长也跟着收到 13.5，否则左右各 6 个的列会甩出精灵老远。

`weapon_mount_selftest` 实测锁住的性质（不是把布局公式抄一遍，而是直接断言需求）：每个图标 `|x|` 必须等于 20（全在两侧）、第 1 个图标必须在 `+x`（右手）、两列数量差 ≤ 1、任意一对图标的距离不小于**较短那个**图标的高度（否则短的会被长的整根吞掉）。覆盖 n=1/2/3、n=6（满缩放下最挤）和 n=12（每侧 6 个）。

**朝向**：每个挂件独立转向自己武器的目标，走 `BaseWeapon.get_aim_direction()`（复用 `_find_nearest_enemy(get_range())`，所以子弹武器受射程约束，刀阵/闪电链不限距离）。目标扫描 **每 0.06s 一次**（敌人组可能 60+，每帧全扫是白烧 CPU），每帧用 `lerp_angle` 以 10 rad/s 平滑转。丢失目标时保持上一次方向并**把没转完的角度转完**，不冻在半路也不弹回 0。

**武器列表来源**是 Player 的 `BaseWeapon` 子节点，不经过 `WeaponDirector`。因为武器一律 `add_child` 到玩家身上，读节点树就让融合消耗基础武器、死亡重开、director 剪枝这三条路径全部自动同步，不需要额外信号。

**贴图**：12 把武器全部用上了真实像素图，手画的枪械/冷兵器，用 Kenney Tiny Dungeon 的调色板（和玩家 / 敌人 / 子弹风格统一）。`WeaponConfig.icon: Texture2D` 指向 `assets/sprites/weapons/mount_*.png`；`icon` 为 null 时才回退成按 `icon_size` + `sprite_color` 生成的渐变占位条（握把亮、枪口暗）。

**枢轴**用的是贴图自己的尺寸（`icon.get_size()`），不是 `icon_size`——后者只描述占位条。`offset.x = 宽度/2`，图形从挂点往前延伸，所以转起来是"枪管甩向目标"而不是绕中心打转。换任意尺寸的图都不用改 `.tres`。

**朝向已烘进 PNG**：一律握把在左端、前端在右端，对应 `rotation = 0`（+X）。代码里没有朝向修正常数、也没有额外的枢轴节点。左右还必须**撑满画布**——枢轴按整张图宽度算，留白会把握把推离挂点。

挂件由 `tools/gen_weapon_mounts.py` 生成，源数据是脚本里的半分辨率字符画（一个字符一格，落盘时 2× 最近邻放大，和其他 Kenney 素材同样的像素颗粒度）：

```bash
python tools/gen_weapon_mounts.py          # 重新生成到 assets/sprites/weapons/ 并校验
python tools/gen_weapon_mounts.py --check  # 只校验现有文件
```

脚本自带格式校验，不满足就报错退出：RGBA / alpha 只有 0|255 / 颜色全在调色板内 / 每 2×2 一个同色块 / bbox 撑满画布 / 尺寸逐张匹配。

| 武器 | 挂件贴图 | 尺寸 | 造型 |
|---|---|---|---|
| `bullet_volley` 弹雨 | `mount_bullet_volley.png` | 26×16 | 紧凑手枪，木握把 |
| `chain_lightning` 闪电链 | `mount_chain_lightning.png` | 26×16 | 电枪，枪口两个青色线圈环 |
| `orbiting_blades` 刀阵 | `mount_orbiting_blades.png` | 32×16 | 横置战斧，右端宽斧刃 |
| `storm_volley` 雷暴弹雨 | `mount_storm_volley.png` | 32×16 | 电磁步枪，导轨发紫 |
| `blade_barrage` 刀刃弹幕 | `mount_blade_barrage.png` | 32×16 | 三片飞刃并排 |
| `lightning_blade` 闪电刀阵 | `mount_lightning_blade.png` | 32×16 | 等离子长刀，青色刀身 |
| `apocalypse` 启示录 | `mount_apocalypse.png` | 32×20 | 末日重炮，炮口红色能量裂纹 |
| `shotgun` 散弹枪 | `mount_shotgun.png` | 26×16 | 短粗双管，右端喇叭口 |
| `laser_lance` 磁轨激光 | `mount_laser_lance.png` | 32×16 | 细长镜筒，右端青色聚焦透镜 |
| `mine_layer` 地雷布设器 | `mount_mine_layer.png` | 32×16 | 短管 + 右端浑圆雷体 |
| `flamethrower` 火焰喷射器 | `mount_flamethrower.png` | 32×16 | 粗管 + 右端橙红火苗 |
| `homing_dart` 追踪飞镖 | `mount_homing_dart.png` | 32×16 | 发射器 + 右端紫色制导弹头 |

换图只需两步，零代码改动：PNG 丢进 `assets/sprites/weapons/`，在对应 `data/weapons/*.tres` 里设 `icon`。

> 试过用文生图模型（Seedream）生成这套挂件，不可用：挂件有效分辨率只有 13×8 ~ 16×10 格，模型既守不住"前端朝右"（多次把枪口画在左边，而朝向是功能性约束），也画不出原素材那种描边密度（原图 51% 是描边色 `#3F2631`，降采样后的 AI 图几乎为 0），内部细节还会糊成一团。这个尺度只能手画。

自检：

```bash
godot --headless res://scenes/dev/weapon_mount_selftest.tscn
```

## 子弹贴图

玩家弹 `assets/sprites/bullets/bullet.png` 和敌弹 `enemy_bullet.png` 都是 16×16 RGBA，手画，由 `tools/gen_bullets.py` 生成。Kenney Tiny Dungeon 是地牢包，132 张瓦片里没有任何抛射物，所以这两张不是 Kenney 素材。

```bash
python tools/gen_bullets.py          # 重新生成到 assets/sprites/bullets/ 并校验
python tools/gen_bullets.py --check  # 只校验现有文件
```

**朝向是功能性约束**：`bullet.gd` 和 `enemy_projectile.gd` 的 `setup()` 都做 `rotation = velocity.angle()`，`rotation = 0` 表示朝 +X。所以字符画一律**尾焰在左、尖头在右**，且左右必须撑满画布——留白会让子弹看起来比实际短，朝向也读不出来。上下**不要求**撑满：那条约束只属于挂件（`weapon_mounts._make_icon` 拿 `offset.x = 宽度/2` 当枢轴），子弹的 `Sprite2D` 是居中的。

反过来上下留白还有好处：`bullet.tscn` 里 `CollisionShape2D` 半径只有 5.0（10px 直径），而 16×16 × `BULLET_SPRITE_SCALE` 2.0 = 32px 视觉。把造型画薄（有效 16×5 / 16×7）视觉降到 32×10 / 32×14，和判定框接近多了，**不用改任何常量或 .tscn**。

和挂件工具的关键差异是 `BLOCK = 1`：挂件是从 16×8 瓦片裁片 2× 放大来的，一个字符占 2×2；子弹对标 Kenney 瓦片的**原生** 16×16 分辨率，一个字符就是一个像素。

**玩家弹 / 敌弹靠造型 + 配色区分，不靠 `modulate`**：细长金黄曳光弹（`#F7C282` 亮核）vs 短粗红紫等离子球（`#D176D0` 品红高光）。原来 `enemy_projectile.gd` 里那句 `modulate = Color(1.0, 0.5, 0.5, 1)` 已经删掉——那时两张 PNG 逐像素相同，染色是唯一的区分手段；现在颜色烘进贴图，再叠一层红会把品红高光压死。

子弹**没有拖尾**：`bullet.tscn` 里原本挂了个 `Line2D` 拖尾（`top_level = true`，每帧 `add_point` 保留 8 点），已经整节点连配套的 Gradient / Curve 一起移除，`bullet.gd` 里的 `trail_length` 和逐帧点管理也删了。

校验断言和挂件同款，跑不过就非零退出：RGBA / alpha 只有 0|255 / 颜色全在调色板内 / 尺寸精确 16×16 / bbox 横向撑满 / 行列数与声明尺寸逐张匹配。

## 融合配方（`WeaponDirector.FUSION_RECIPES`）

三把基础武器（弹雨 / 闪电链 / 旋转刀）各持有**一把 Lv3 副本**后，下一次升级弹出融合面板（可选开启，不强制）。
融合会消耗配方里每种基础武器**一个**副本（等级最高的那个），换成一把超级武器；多余的同款副本保留。

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

## 武器合并（3 把同款同级 → 1 把更高级）

武器不再来自升级卡，而是**怪物掉落**（含杂兵，见「道具掉落」），所以玩家可以同时持有多把相同武器。凑齐 **3 把同款同级**的武器会自动合成 1 把**更高一级**的武器，落地立刻生效（不用手动操作）。

| 等级 | 伤害 | 射速 | 相对 Lv1 输出 | 等价 Lv1 把数 | 需要的掉落数 |
|---|---|---|---|---|---|
| 1 | 1.0× | 1.0× | 1.0× | 1 | 1 |
| 2 | 2.0× | 1.5× | **3.0×** | 3 | 3 |
| 3 | 3.0× | 2.0× | 6.0× | 6 | 9 |
| 4 | 4.0× | 2.5× | 10.0× | 10 | 27 |

- **第一次合并零亏**：Lv2 的 3.0× 输出正好等于 3 把 Lv1 各打各的，还净赚 2 个槽位。之后是「用 DPS 换槽位效率 + 换融合门槛」的有意递减收益。
- **冷却型武器**（闪电链 / 磁轨激光 / 火焰喷射器 / 地雷布设器 / 雷暴弹雨 / 闪电刀阵 / 启示录）的等级射速同样走 `scale_cooldown()`，保证合并对它们也是 3.0×，而不是只放大伤害。
- **级联**：9 把 Lv1 会先合成 3 把 Lv2，再合成 1 把 Lv3，最终只占 1 个槽位。
- **上限**：`WeaponConfig.max_level`（默认 8）是合并天花板，3 把满级副本不再合并、可共存。
- **满槽掉落**：优先凑能立刻完成合并的掉落（因为那一手净腾出 2 个槽）；凑不上就拒绝，不浪费。

```bash
godot --headless res://scenes/dev/weapon_merge_selftest.tscn   # exit 0 = 全绿
```

## 精英营地（地图特定区域）

地图生成时会在 `TilemapBuilder` 里额外挖出 `elite_camp_count`（默认 **6**）个营地：半径 3 格的圆盘，铺第 6 种瓦片 `T_CAMP`（暗混凝土 + 锈红警戒条纹）。

营地是**确定性**的——选点复用地形自己的 `_hash2`，同一个 seed 两次生成落在同样的格子上，所以「地图特定区域」是可复现的地点，不是随机事件。选点逐个拒绝：离出生点 < `elite_camp_min_dist_tiles`(14 格)、进边界 pit 带、离已选营地 < `elite_camp_min_gap_tiles`(14 格)。

营地圆盘**不注册 physics / navigation**，并且会 `swamp_cells.erase` 掉压在下面的毒沼——营地必须能走进去打，不能变成一块挡路的装饰。铺设顺序插在 `_paint_map()` 之后、`_paint_borders()` 之前，所以营地覆盖地形障碍，但边界 pit 带仍然优先。

`scripts/world/elite_camp_director.gd`（挂在 `game.tscn` 的 `Game` 下）负责刷怪：

| 参数 | 默认 | 说明 |
|---|---|---|
| `activation_radius` | 700 px | 玩家进入这个距离才刷。比 1280×720 视口在 zoom 1.2 下的半对角（≈610px）稍大，所以精英是在画面外站起来的，不会当面弹出来 |
| `respawn_cooldown` | 45 s | 精英死后重新武装的冷却 |
| `arm_delay` | 20 s | 开局静默期，避免 1 级玩家撞上 220hp 精英 |
| `elite_id` | `elite_brute` | 刷哪种敌人 |
| `CHECK_INTERVAL` | 0.25 s | 距离扫描节流（冷却仍每帧递减） |

- **每个营地同时最多 1 只精英**。刷怪走 `SpawnDirector.spawn_enemy_at(id, pos)`（靠 `enemy_spawner` 组找），营地中心走 `world` 组的 `camp_centers()`——都是项目「靠组不靠 NodePath」的约定。
- 存活判定单独维护一个 `busy` 标志，**不能只看 `elite != null`**：Godot 4 里被释放的对象在 Variant 里和 null 相等，光看引用分不出「从没刷过」和「刚被打死」，营地会在下一次扫描里立刻重刷。同理 `_is_alive()` 还要排掉 `is_queued_for_deletion()`，否则击杀当帧营地还占着。
- 刷怪时飘「精英出没」+ 震屏 + 音效。
- `SpawnDirector` 原有的 5% 精英 roll 和 300s 后的 ELITE WAVE **保留不动**：那两条是按时间来的，营地是按地点来的，叠加生效。

自检（营地数量 / 同 seed 确定性 / 最小间距 / 圆盘可走无碰撞无毒沼 / 进半径刷怪 / 每营地至多 1 只 / 死后冷却）：

```bash
godot --headless res://scenes/dev/elite_camp_selftest.tscn   # exit 0 = 全绿
```

## 道具掉落

精英、Boss 与**杂兵**死亡时掉道具，数量 / 概率由 `EnemyConfig` 数据驱动：`elite_brute.tres` = 1 个（100%）、`boss.tres` = 3 个（100%）、`chaser` / `dasher` / `shooter` = 1 个（**25%**）。掉落绑定在**「是精英」而不是「是营地刷的」**，所以 ELITE WAVE 和 5% roll 出来的精英一样掉。

道具是 `scenes/pickup_item.tscn`（结构照抄 `xp_gem.tscn`：Area2D，layer 16 Pickup / mask 2），进玩家 `PickupArea` → 归巢 → 到位生效 + 飘字 + 音效。地上会上下浮动，`LIFETIME` 30s 后消失，最后 5s 闪烁预警——否则没捡的道具会慢慢铺满地图。

| 道具 | 权重 | 效果 | 落点 |
|---|---|---|---|
| 补血 `HEAL` | 24 | 回 **30%** 生命上限 | `player.heal()`，clamp 到 max_hp |
| 护盾 `SHIELD` | 22 | 抵消接下来 **2** 次伤害 | `GameState.shield_charges`，`player.take_damage` 开头扣层 |
| 炸弹 `BOMB` | 20 | 半径 **420** 内 **120** 伤害 | `scenes/fx/explosion.tscn`，遍历 `enemies` 组做距离判定 |
| 时间暂停 `TIME_STOP` | 16 | 敌人冻结 **4s** | `GameState.start_time_stop()` |
| 武器 `WEAPON` | 60 | 给一把随机武器（可重复） | `WeaponDirector.grant_random_weapon()` |

权重意图：**武器权重（60）压过其余四种之和的一半**，因为武器现在只能靠掉落获得，而升一级要凑 3 把同款——掉落量不够，合并系统就等于不存在。杂兵 25% × 武器 60/142 ≈ **每杀 9.5 只掉 1 把武器**，一局下来才够凑出几次合并。（改之前是杂兵 6% × 权重 30/112 ≈ 每 62 只 1 把，实测一局根本攒不出 3 把同款。）补血仍是单项最高的非武器权重——它是让一局活下去的那个效果。

**护盾**按「次数」而不是「伤害量」抵消：一层挡一下，不管这一下打多少。抵消时照常给无敌帧 + 蓝闪，但不掉血。玩家身上挂 `ShieldRing`（`_draw` 画圆环，层数越多越亮）。

**时间暂停只冻结敌人**：`GameState.is_time_stopped()` 为真时 `enemy.gd` / `enemy_projectile.gd` 的 `_physics_process` 开头直接 return，冻结期间染蓝灰；玩家照常移动开火。**没有碰 `Engine.time_scale`**——那会把玩家、tween、粒子一起冻住。倒计时在 `GameState._process` 里放在 `is_running` 判断**之前**递减，但 autoload 默认 pausable，所以升级面板暂停时时停不会偷跑。

**满槽时武器道具优先凑合并**：`grant_random_weapon()` 在 12 槽全满时，只接受「能立刻凑成 3 连合并」的武器（那一手净腾出 2 个槽）；凑不上就拒绝，不会静默丢掉。

**顺手修的一个老 bug**：`enemy.gd` 的 `_flash()` 原本补间回 `config.sprite_color`，但 `_apply_visuals` 给精英/BOSS 上的是 `Color(1.4,0.6,0.6)` / `Color(1.2,0.6,0.6)`——精英挨一下就永久掉红染。现在 `_apply_visuals` 缓存 `_base_tint`，`_flash()` 和时停解冻都补间回它。

贴图由 `tools/gen_pickups.py` 生成（和挂件同一套字符画 + Kenney Tiny Dungeon 调色板 + `--check` 校验），5 张 16×16，`SPRITE_SCALE 2.0` 和经验宝石一致：

```bash
python tools/gen_pickups.py          # 重新生成到 assets/sprites/pickups/ 并校验
python tools/gen_pickups.py --check  # 只校验现有文件
```

自检（5 种效果 / 护盾抵消 2 次后失效 / 时停期间敌人不动且结束恢复 / 炸弹半径内外 / 满槽拒绝 / 满槽凑合并）：

```bash
godot --headless res://scenes/dev/pickup_selftest.tscn   # exit 0 = 全绿
```

## 武器槽位（12）

`WeaponDirector.MAX_WEAPONS = 12`。武器以**实例列表**存储（`_weapons: Array[BaseWeapon]`），允许重复持有同一把武器；`BaseWeapon.level` 是每实例的，3 把同款同级自动合并。

- 满槽拦截放在 `add_weapon` / `add_weapon_with_extras` 顶部——这两个是 `_weapons` 的唯一写入口，返回值从 `void` 改成 `bool` 便于自测断言。**满槽时若有 id 能立刻凑成 3 连合并仍放行**（那一手净减 2 槽）。
- 新增 `slots_used()` / `is_full()` / `count_of(id)` / `owned_weapon_ids()`。`count_of()` 返回该 id 的副本数；`weapon_level_of(id)` 返回该 id 所有副本里的最高等级。
- **`fuse()` 净减槽位**：它先 `_consume_one()` 掉配方里每种基础武器**一个**副本再 add 融合物，所以 2 件组 -1 槽、3 件组 -2 槽，且多余的同款副本保留。
- **合并净减槽位**：3 把同款同级 → 1 把更高级，净 -2 槽。加上可重复持有，**12 个槽位在正常玩法里真的能填满**。

HUD 底部状态行会显示 `护盾 ×N` / `时停 N.Ns` / `武器 N／12`。前两个听 `GameState.shield_changed` / `time_stop_changed`；槽位是**轮询**的——`WeaponDirector` 没有「军火库变了」的信号，而武器可以从掉落、合并、融合三条路进出，所以 `_process` 里比对上一次画的数字，只在真的变了时重绘。为 0 时两个状态标签留空而不是显示 `0`，让整行在没有效果时塌掉。

## 基础武器（8 把）

前 3 把是原有的，后 5 把是为了把 12 个槽位填满而加的，全部复用现有设施（`BaseWeapon` 基类 + `WeaponConfig` 数据 + 挂件图标）。**`BASE_WEAPONS`（融合配方的输入）保持原来 3 把不动**，不破坏现有融合。

| 武器 | 伤害 | 射速 | 关键数据 | 行为 |
|---|---|---|---|---|
| `bullet_volley` 弹雨 | 10 | 2.5 | 射程 420 | 朝最近敌人打单发，吃 `extra_projectiles` |
| `orbiting_blades` 刀阵 | 14 | 1.0 | 环绕半径 90、3 把刀 | 绕身旋转 + 周期冲刺 |
| `chain_lightning` 闪电链 | 18 | 0.7 | 链距 140、3 段 | 每 1.6s 放一次连锁电击 |
| `shotgun` 散弹枪 | 7 | 1.1 | 射程 260、弹丸 5 | 近距扇形喷 5 发，每发独立 roll 暴击；也吃 `extra_projectiles` |
| `laser_lance` 磁轨激光 | 26 | 0.7 | 长 520 / 宽 26 | 瞬发（hitscan）矩形光束，贯穿路径上全部敌人 + `Line2D` 淡出 |
| `mine_layer` 地雷布设器 | 55 | 0.5 | 爆半径 150、同时 6 颗 | 周期在脚下放雷，0.4s 布防、接触或 8s 后引爆，**复用炸弹道具的 explosion** |
| `flamethrower` 火焰喷射器 | 4 | 6.7 | 射程 160、锥角 60° | 锥形区域跟 `get_aim_direction()` 转，每 0.15s 结算一次重叠敌人 |
| `homing_dart` 追踪飞镖 | 12 | 1.6 | 射程 520、转向 5 rad/s | `bullet.set_homing()`：有制导且目标有效时每帧把速度转向最近敌人 |

每把都配了 `WeaponConfig` 数据 + 挂件图标（`UpgradeDB` 不再负责武器解锁/升级，武器只从掉落获得）。`shotgun` / `homing_dart` 复用 `bullet.tscn`，`mine_layer` 用 `mine.tscn`——两者的场景引用都在 `WeaponDirector` 的 `BULLET_USERS` / `MINE_USERS` 里注入，`.tres` 留 null，`data/` 目录里不出现场景引用。



| ID | 类型 | 物理 | 效果 |
|---|---|---|---|
| 0 | 沙地 | 无 | 正常通行 |
| 1 | 瓦砾 | 阻挡 | 物理碰撞 + 视觉是废铁/碎石 |
| 2 | 废铁 | 阻挡 | 物理碰撞 + 视觉是深色金属 |
| 3 | 地坑 | 阻挡 | 物理碰撞 + 视觉是深坑 |
| 4 | 毒沼 | **不挡** | 减速 50% + 每 0.5s 扣 1 滴血（玩家+敌人） |
| 5 | 精英营地 | **不挡** | 暗混凝土 + 锈红警戒条纹，`EliteCampDirector` 的刷怪点 |

默认 64×64 格地图、seed=1337，障碍合计 10%，毒沼 5%，出生点 11×11 安全区，6 处半径 3 格的精英营地。

## 全部自检

每个自测都是 headless 场景，全绿 exit 0、有失败则 exit 1，可以直接串进 CI：

```bash
godot --headless res://scenes/dev/elite_camp_selftest.tscn    # 精英营地
godot --headless res://scenes/dev/pickup_selftest.tscn        # 5 种道具 + 槽位上限/满槽合并
godot --headless res://scenes/dev/weapon_merge_selftest.tscn  # 3 合 1 合并 + 曲线 + 级联
godot --headless res://scenes/dev/weapon_mount_selftest.tscn  # 挂件布局（右手起两列 + 满槽 12 图标）
godot --headless res://scenes/dev/range_pierce_selftest.tscn  # 射程、穿透、追踪目标中途死亡
godot --headless res://scenes/dev/fusion_selftest.tscn        # 4 个融合配方 + 备用副本
python tools/gen_weapon_mounts.py --check                     # 12 张挂件贴图
python tools/gen_pickups.py --check                           # 5 张道具贴图
python tools/gen_bullets.py --check                           # 2 张子弹贴图
```

`SystemCheck` 也会在每次运行时把新增的脚本 / 场景 / 资源 / `GameState` 字段一并核对（包括 12 把武器的 `.tres` 与 `.tscn`、`pickup_item` / `explosion` / `shield_ring` / `elite_camp_director`、`shield_charges` / `time_stop_left`），缺一个就在 Output 面板报 FAIL。

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
│   ├── xp_gem.tscn             # 经验宝石
│   ├── pickup_item.tscn        # 道具（补血/护盾/炸弹/时停/武器 共用一个场景）
│   ├── dev/                   # headless 自测场景
│   ├── fx/                     # 浮字 + 粒子 + explosion
│   ├── ui/                     # HUD / LevelUp / GameOver / UpgradeCard / Shop
│   └── weapons/                # 8 基础 + 4 融合武器 + 飞刀 + 地雷场景
├── scripts/
│   ├── globals/
│   │   ├── game_state.gd      # Autoload: 状态 + 事件总线 + 属性倍率 + 护盾/时停
│   │   ├── upgrade_db.gd      # Autoload: 升级数据表（纯被动）
│   │   ├── meta_progress.gd   # Autoload: 永久货币 / 统计，落盘 user://
│   │   └── system_check.gd    # Autoload: 启动期 autoload/脚本/场景/资源自检
│   ├── player.gd
│   ├── bullet.gd
│   ├── enemy.gd
│   ├── enemy_config.gd        # EnemyConfig 资源类（含 item_drop_count）
│   ├── enemy_projectile.gd
│   ├── spawn_director.gd      # 波次 + 敌人类型编排 + spawn_enemy_at()
│   ├── xp_gem.gd
│   ├── pickup_item.gd         # 5 种道具的掉落权重与效果
│   ├── explosion.gd           # 炸弹道具与地雷共用的范围伤害
│   ├── shield_ring.gd         # 玩家身上的护盾圆环
│   ├── game.gd
│   ├── hud.gd
│   ├── level_up.gd
│   ├── upgrade_card.gd
│   ├── game_over.gd
│   ├── shop.gd
│   ├── fx_manager.gd
│   ├── floating_label.gd
│   ├── burst_particles.gd
│   ├── shake_camera.gd
│   ├── weapon_mounts.gd       # 玩家身上的武器挂件布局与朝向
│   ├── weapon_director.gd     # Autoload: 12 武器槽 + 合并 + 融合 + 跨场景清理
│   ├── dev/                   # 自测脚本（pickup / elite_camp / mount / merge / ...）
│   ├── weapons/
│   │   ├── weapon.gd          # BaseWeapon 基类
│   │   ├── weapon_config.gd   # WeaponConfig 资源类
│   │   ├── bullet_volley.gd
│   │   ├── orbiting_blades.gd
│   │   ├── chain_lightning.gd
│   │   ├── shotgun.gd
│   │   ├── laser_lance.gd
│   │   ├── mine_layer.gd
│   │   ├── mine.gd
│   │   ├── flamethrower.gd
│   │   ├── homing_dart.gd
│   │   ├── storm_volley.gd
│   │   ├── blade_barrage.gd
│   │   ├── lightning_blade.gd
│   │   ├── apocalypse.gd
│   │   └── blade.gd
│   └── world/                 # Iter4: 程序化废土地形
│       ├── wasteland_config.gd   # 资源：地图尺寸/种子/密度/精英营地
│       ├── tilemap_builder.gd    # 运行时生成 TileSet + 铺地图 + 挖营地
│       ├── elite_camp_director.gd # 营地刷怪 / 冷却 / 激活半径
│       ├── world.gd              # 场景入口（持有 TileMap）
│       └── toxic_swamp.gd        # 角色身上的毒沼 slow + dot 效果
├── data/
│   ├── enemies/               # 5 EnemyConfig .tres（含 boss）
│   ├── weapons/               # 12 WeaponConfig .tres
│   └── world/
│       └── default_wasteland.tres  # 64x64 地图默认配置（seed=1337）
├── tools/
│   ├── gen_weapon_mounts.py   # 生成 + 校验 12 张武器挂件贴图（Python + Pillow）
│   ├── gen_pickups.py         # 生成 + 校验 5 张道具贴图（Python + Pillow）
│   └── gen_bullets.py         # 生成 + 校验 2 张子弹贴图（Python + Pillow）
└── README.md
```

## 物理层约定

| 层 | 用途 |
|---|---|
| 1 World | 瓦砾 / 废铁 / 地坑（瓦片 collision_polygon 自动注册） |
| 2 Player | 玩家 body + 拾取 area |
| 3 PlayerBullet | 玩家子弹 |
| 4 Enemy | 敌人 body |
| 5 Pickup | 经验宝石 + 道具 |

- 玩家 body: layer=2, mask=1（被瓦片挡路）
- 玩家 PickupArea: layer=2, mask=16（检测宝石与道具）
- 子弹: layer=4, mask=8（打敌人）
- 敌人: layer=8, mask=3（碰玩家 + 被瓦片挡路）
- 经验宝石 / 道具: layer=16, mask=2（被玩家 PickupArea 吸引）
- 地雷: layer=4, mask=8（当玩家侧的伤害源，踩中即爆）
- 毒沼: **不参与物理碰撞**，由 `ToxicSwamp` 节点每帧检查 `_builder.is_swamp(pos)` 触发减速/扣血
- 精英营地: **不参与物理碰撞**，只是一种可通行瓦片 + `EliteCampDirector` 的距离判定

## 运行

1. 安装 [Godot 4.2+](https://godotengine.org/download)（GL 兼容模式）
2. 在 Godot 编辑器 `Import` 本目录（选择 `project.godot`）
3. 首次导入完成后按 **F5** 或点击右上角运行
4. 主场景已配置为 `res://scenes/main.tscn`

## 已知限制 / 后续可扩展

- 瓦片仍是程序化生成（64×64 手绘），角色 / 宝石用 Kenney 像素图，武器挂件与子弹是手画的
- 音效是程序合成的 5 个短音，没有 BGM
- 毒沼只有减速/扣血，无视觉毒气动画
- 敌人寻路未启用 avoidance（避免 60+ 实体时性能塌方）
- 地图固定 4096×4096，未做"越打越大"扩展
- 融合是单向的，融合后无法拆回基础武器；一局最多融合一次（每个融合物的基础副本被消耗）
- 射程只约束子弹；旋转刀与闪电链仍各走自己的 `blade_dash_lifetime` / `chain_range` 逻辑
- `chain_lightning.gd` 与 `apocalypse.gd` 的电链未校验 `config.chain_range`（`storm_volley` / `lightning_blade` 有校验）
- 玩家精灵本身仍无朝向 / 无动画（`player.gd` 里没有 `flip_h` / `rotation`），只有武器挂件会转
- 武器挂件只有 13×8 ~ 16×10 格有效分辨率，造型全靠轮廓辨认，细节做不进去；文生图模型在这个尺度上不可用（详见「武器挂件」一节）
- `blade.gd:_return_to_orbit` 在所属武器已被 `queue_free` 后仍会尝试 reparent，冲刺中的刀会刷一条 `Can't add child` 报错（不影响功能）
- 精英营地固定 6 处、只刷 `elite_brute` 一种，没有营地专属的更强变体或多波
- 道具没有稀有度分层，权重是写死的常量，不随时间或难度变化
- 时间暂停只 early-return 敌人与敌弹的 `_physics_process`，敌人身上正在跑的 tween（击退、闪白）不受影响

## 扩展路线（不属于 MVP）

- 替换程序化瓦片为真实像素艺术
- BGM + 更丰富的音效层次
- Boss 房间 + 多区域随机地图
- 融合武器自身的升级曲线（目前融合物固定 1 级）
- 毒气视觉 / 闪避 / 击退
