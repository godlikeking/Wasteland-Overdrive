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
- **Esc**：暂停 / 继续（暂停时可查看武器等级与被动清单，见「暂停面板」）
- 武器**自动**锁定并射击最近敌人
- 击杀敌人掉落蓝色**经验宝石**，走近自动吸取
- **升级**时弹出三张**被动**升级卡（武器不再从升级卡获得），选择一张永久强化本局角色
- **接触敌人**扣血，血量归零结算重开
- **地图**：8192×8192 像素的程序化废土地形，含沙地 / 瓦砾 / 废铁 / 地坑 / **毒沼**（减速 + 持续扣血）/ **精英营地**
- **地图边缘没有墙**：走出去不会被挡住，而是开始持续高额扣血（20/秒起、每 3 秒爬一档、封顶 80/秒，满血约 **3.5 秒**死），屏幕压一层红并显示 `脱离废土！ -N/秒`（详见「地图边界」一节）
- 撞墙：玩家和敌人都被瓦砾 / 废铁 / 地坑挡住，**敌人在 0.4s 同步后会自动绕路**
- **精英营地**：地图上 12 个锈红警戒条纹地砖圈，走近会刷出精英怪；杀掉掉 **1 个道具**，营地进 45s 冷却后重刷（详见「精英营地」一节）
- **道具**：补血 / 护盾 / 炸弹 / 时间暂停 / 武器 / **磁石** 六种，走近自动吸取；磁石会把**全图**掉落物（含经验宝石）一次吸过来（详见「道具掉落」一节）
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
- [x] **程序化废土 TileMap（运行时生成 6 种子瓦片，8192×8192 地图，无边界墙）**
- [x] **武器合并**：3 把同款同级武器自动合成 1 把更高级（等级曲线 +100% 伤害 / +50% 射速，冷却型武器同步缩放）
- [x] **物理碰撞（瓦砾 / 废铁 / 地坑 写入 TileData collision_polygons）**
- [x] **毒沼：玩家和敌人减速 50% + 每 0.5s 扣 1 滴血**（走 DoT 通道，见「地图边界」一节末尾）
- [x] **敌人 NavigationAgent2D 绕墙寻路（带 warmup + 三层 fallback）**
- [x] **SystemCheck 启动诊断：autoload / 脚本 / 场景 / 资源 / 输入 / 升级库**
- [x] **真实像素素材**：玩家 / 4 敌人 / 经验宝石 / 旋转刀取自 Kenney Tiny Dungeon 16×16；12 把武器挂件 + 2 种子弹 + 6 种道具手画（同调色板，`tools/` 下可复现）
- [x] **程序化音效 SfxPlayer**：开火 / 命中 / 击杀 / 拾取 / 升级 / 道具 / 爆炸 共 7 短音（无外部 wav）
- [x] **连击系统**：连续击杀累积连击、1.5s 无击杀归零、3/8/15 三级（连击/爆发/烈焰）
- [x] **暴击系统**：基础 5% 暴击 + 连击加成（封顶 +30%），2× 伤害，暴击时飘 "暴击！"
- [x] **击杀爆裂粒子**：增强版 burst_particles（28 粒、彩尘，精英偏紫红）
- [x] **2 张新增被动升级**：暴击瞄准镜（+5%）、穿甲弹头（+0.5× 倍率）
- [x] **5 分钟 Boss 战**：废土巨兽（**25000 HP、448px 体型**、3 阶段、召唤小怪 + 弹幕，击杀 +50 废金属 + 紫红大爆裂）；**难度加了两道天花板让它真的能被活着见到**，配顶部血条 + 字号 64 倒计时横幅 + 出画时的屏幕边缘红箭头（见「BOSS 降临与难度天花板」一节）
- [x] **杀死 BOSS 即通关**：胜利也走结算界面（金色「任务胜利」），结束界面新增**从头开始**按钮（清空废金属/已购模块存档后重开，见「游戏结束与从头开始」一节）
- [x] **BOSS 远程毒物 + 近战爪击 + 直线冲刺**：抛毒团落地成毒池（持续 DoT），近身则先定住脚画预警扇形、0.45s 后挥爪（朝向在预警开始时就锁死，可以横向闪避）；中距离会蓄力后沿锁定方向直线冲刺（见「BOSS：毒物与爪击」与「BOSS 冲刺」两节）
- [x] **元进度（MetaProgress）**：永久货币、累计击杀 / Boss / 最佳时间，落盘 `user://meta_progress.json`
- [x] **5 项开局模块（模块商店）**：磁力 / 钛合金 / 瞄准镜 / 伺服 / 过载，每局开始自动应用
- [x] **装备融合（Fusion）**：3 基础武器各持有一把 Lv3 副本时可触发融合面板（可选开启）；2 件组 → 雷暴弹雨 / 刀刃弹幕 / 闪电刀阵；3 件组 → 启示录（弹雨+链+刀 + 每 4s 整屏 nuke）
- [x] **精英营地**：地图程序化生成 6 处专属地砖营地，走近刷精英、杀死进 45s 冷却重刷
- [x] **道具系统**：补血 / 护盾 / 炸弹 / 时间暂停 / 武器 / 磁石 六种掉落，武器从怪物掉落获得（含杂兵）；**护盾有 15s 时限**（层数与时间谁先到谁先结束）
- [x] **武器稀有度**：武器掉落按权重 20:12:7:4 分档，稀有武器**掉落即高等级**作为补偿（详见「武器稀有度」一节）
- [x] **12 武器槽位**：`MAX_WEAPONS = 12`，满槽拦截，挂件走左右两列布局
- [x] **5 把新基础武器**：散弹枪 / 磁轨激光 / 地雷布设器 / 火焰喷射器 / 追踪飞镖（合计 8 基础 + 4 融合 = 12 个 id）
- [x] **暂停面板（Esc）**：暂停时列出每把武器的等级 + 合并进度，以及本局选过的被动卡与堆叠层数
- [x] **地图边界代价化**：地图 128×128 格（8192px）、**删掉了边缘那圈坑墙**，出界改为持续爬坡扣血 + 屏幕红晕警告；敌人生成点也会挑一条落在图内的边（见「地图边界」一节）

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

## 暂停面板（Esc）

`scenes/ui/pause_menu.tscn` + `scripts/pause_menu.gd`，兼当本局的**装备清单**：

- **武器列**：每行一个 `(id, 等级)` 组合，形如 `弹雨 Lv2 ×2`，右侧标**合并进度** `还差 1 把升 Lv3`（满级的标「已满级」）。按 `(id, 等级)` 而不是按 id 分组是必须的——合并要 3 把**同级**，所以「Lv1 一把 + Lv2 一把」不是「差一把」，而是两行各差两把。数据来自 `WeaponDirector.inventory_groups()`。
- **被动列**：本局选过的升级卡 + 堆叠层数（`枪管增强 ×3`）。`GameState` 的那些倍率只记录**结果**、不记录是哪张卡造成的，所以另开了 `GameState.taken_upgrades`（id → 层数）这本账；写入口只有 `GameState.record_upgrade()` 一处，`level_up.gd` 选卡后调它。Dictionary 在 Godot 4 里保持插入顺序，所以列表天然按选取顺序排。

**Esc 的归属很关键**：这个键**必须**由暂停面板自己处理，不能放在 `Game` 根节点上。`Game` 是 PAUSABLE 的（World / Player / SpawnDirector 都靠继承它的 process mode 才会在暂停时停下），所以 `paused = true` 之后 `Game._unhandled_input` 就再也收不到事件了——那正是「按 Esc 暂停之后无法恢复」这个 bug 的成因。给 `Game` 加 `PROCESS_MODE_ALWAYS` 也不行：子节点会一路继承过去，暂停就彻底失效了。面板自己是 `process_mode = 3`（ALWAYS），所以永远听得见那个解除暂停的按键。

面板还要和别人的暂停共存，规则是三条自洽的判断，不需要引用任何兄弟节点：

| 按下 Esc 时 | 动作 |
|---|---|
| 面板可见 | 关闭 + 恢复 |
| 面板隐藏，且游戏**未**暂停 | 打开 + 暂停 |
| 面板隐藏，但游戏**已**暂停 | 什么都不做（升级 / 结算 / 商店面板正拿着暂停权，恢复了会把游戏从它们的弹窗底下放出去） |

```bash
godot --headless res://scenes/dev/pause_selftest.tscn   # exit 0 = 全绿
```

自测里的 Esc 用例走的是 `push_input()` 真事件，**不是**直接调 handler——直接调用在出 bug 的旧接线下也会通过，因为那个 bug 的本质是事件根本没送到。（已实测：把面板的 process mode 改回 PAUSABLE，`esc_resumes` 立刻红，`esc_opens` 仍绿，正好对应「能暂停、不能恢复」的现象。）

## 游戏结束与从头开始

一局结束有**两个入口**，都走同一个结算界面（`game_over.gd`）：

| 触发 | 标题 | 结算奖励 |
|---|---|---|
| 玩家死亡（`player_died`） | 「任务失败」（红） | `finish_run`：1 秒存活 1 废金属 + 每 10 杀 1 |
| **杀死 BOSS**（`boss_defeated`） | 「任务胜利」（金） | 同上 + BOSS 击杀 +50 |

结算界面三个按钮：

- **模块商店**：去商店花废金属买永久模块（不结束本局结算，买完回来）
- **再来一次**：重开一局，**保留**元进度存档（废金属、已购模块、累计统计）
- **从头开始**：`MetaProgress.wipe()` **清空整个元进度存档**（废金属归零、已购模块全退、累计统计清零、落盘）然后重开一局——真·开新档，不可撤销

> 实现要点：`game_over(victory)` 信号是 `GameState` 上的纯事件，`game.gd._end_run(victory)` 是唯一消费方；BOSS 在 `enemy.gd:_die()` 里同步 emit `boss_defeated`，所以"杀掉 BOSS 立刻结算"不需要轮询。实机验证过：杀 BOSS → 结算界面显示金色「任务胜利」+ 树暂停；点「从头开始」→ 存档文件从 6854 废金属/5 模块被清成全零。
> 
> `wipe()` 会真删 `user://meta_progress.json`，所以它**没有**进 headless 自检（自检会毁真实存档），只在实机验证过一次；`game_over` 信号本身在 SystemCheck 注册表里。

## 精英营地（地图特定区域）

地图生成时会在 `TilemapBuilder` 里额外挖出 `elite_camp_count`（默认 **12**）个营地：半径 3 格的圆盘，铺第 6 种瓦片 `T_CAMP`（暗混凝土 + 锈红警戒条纹）。地图从 64 格加大到 128 格后面积变成 4 倍，营地数量同步从 6 提到 12，否则跑半张图见不到一个。

营地是**确定性**的——选点复用地形自己的 `_hash2`，同一个 seed 两次生成落在同样的格子上，所以「地图特定区域」是可复现的地点，不是随机事件。选点逐个拒绝：离出生点 < `elite_camp_min_dist_tiles`(14 格)、超出 `camp_placement_limit()`、离已选营地 < `elite_camp_min_gap_tiles`(14 格)。

`camp_placement_limit()` = `map_size_tiles/2 - 1 - elite_camp_radius_tiles`，是营地中心能用的最外圈格。它**存在的理由是消掉一处公式复制**：这个式子以前在 `tilemap_builder.gd` 和 `elite_camp_selftest.gd` 里各写了一份（当时是 `half - 3 - radius`，为了避开 2 格宽的边界 pit 带），拆墙时只改一边，另一边就会拿旧几何断言、一路绿灯。现在边界没有墙了，1 格余量的作用变成"营地圆盘不能吊在图外的扣血区上"，自检 `camps_inside` 会连圆盘边缘一起验。

营地圆盘**不注册 physics / navigation**，并且会 `swamp_cells.erase` 掉压在下面的毒沼——营地必须能走进去打，不能变成一块挡路的装饰。铺设顺序在 `_paint_map()` 之后，而且现在它是**最后**一道铺设——边界 pit 带已经删掉，没有任何东西会再覆盖营地。

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

精英、Boss 与**杂兵**死亡时掉道具，数量 / 概率由 `EnemyConfig` 数据驱动：`elite_brute.tres` = 1 个（100%）、`boss.tres` = 3 个（100%）、`chaser` / `dasher` / `shooter` = 1 个（**12%**）。掉落绑定在**「是精英」而不是「是营地刷的」**，所以 ELITE WAVE 和 5% roll 出来的精英一样掉。

道具是 `scenes/pickup_item.tscn`（结构照抄 `xp_gem.tscn`：Area2D，layer 16 Pickup / mask 2），进玩家 `PickupArea` → 归巢 → 到位生效 + 飘字 + 音效。地上会上下浮动，`LIFETIME` 30s 后消失，最后 5s 闪烁预警——否则没捡的道具会慢慢铺满地图。

| 道具 | 权重 | 效果 | 落点 |
|---|---|---|---|
| 补血 `HEAL` | 24 | 回 **30%** 生命上限 | `player.heal()`，clamp 到 max_hp |
| 护盾 `SHIELD` | 22 | **15s 内**抵消 **2** 次伤害 | `GameState.shield_charges` + `shield_left`，`player.take_damage` 开头扣层 |
| 炸弹 `BOMB` | 20 | 半径 **420** 内 **120** 伤害 | `scenes/fx/explosion.tscn`，遍历 `enemies` 组做距离判定 |
| 时间暂停 `TIME_STOP` | 16 | 敌人冻结 **4s** | `GameState.start_time_stop()` |
| 武器 `WEAPON` | 36 | 给一把随机武器（可重复） | `WeaponDirector.grant_random_weapon()` |
| 磁石 `MAGNET` | 14 | **吸取全图掉落物**：经验宝石 + 所有道具（**不可叠加**） | 遍历 `MAGNET_GROUPS` 逐个调 `attract_to()` |
| **合计** | **132** | | |

权重意图：**武器仍是单项最高的权重**，因为武器只能靠掉落获得，而升一级要凑 3 把同款——掉落量不够，合并系统就等于不存在。但它要是「常态」，捡枪就不再是事件了，所以掉率压到：杂兵 12% × 武器 36/132 ≈ **每杀 31 只掉 1 把武器**，一局下来够凑出几次合并、不至于满槽刷屏。补血仍是单项最高的非武器权重——它是让一局活下去的那个效果。

> 掉率调过两轮：最初杂兵 6% × 权重 30/112 ≈ 每 62 只 1 把，一局根本攒不出 3 把同款；改成 25% × 60/142 ≈ 每 9.5 只 1 把又太密。现在的 12% / 36 是两者之间。

**磁石吸的是「全图」而不是「屏幕内」**：`_effect_magnet()` 遍历 `MAGNET_GROUPS = ["xp_gems", "pickup_items"]`，对每个成员调它自己的 `attract_to(player)`，也就是**走各自原本的归巢路径**（宝石和道具的 `pickup_scene_speed 320` / `seek_accel 900` 完全一致）。所以不是瞬间到手，而是一圈掉落物同时向内收拢；道具到达时照常触发**自己的效果**——磁石旁边躺着三个炸弹是个真连招，这是有意的。

- **磁吸道具不可叠加**：磁石本身就在 `pickup_items` 组里，`node == self` 要跳过（否则自吸→重复施放）。跳过的是**整个 MAGNET 种类**而不是单个自己——一枚磁石**不吸另一枚磁石**。因为磁石效果是"一次全场横扫"：一旦吸到另一枚磁石，那枚到达时会再横扫一次全场，等于一个磁石吸两轮，这就是"叠加"。锁着这条的是自检 `magnet_no_stack`。
- **顺手修的隐身 bug**：寿命最后 5 秒 `sprite.visible` 会按 `fmod` 闪烁，而开始 seek 后没人把它设回 `true`——闪烁期间被捡走的道具会**隐身飞过来**。以前很难注意到，磁石一次性吸走全图（必然包含将要过期的）之后会很明显，所以 `attract_to()` 里补了 `sprite.visible = true`。
- **经验宝石没有寿命**（`xp_gem.gd` 无 `_age`），后期地上可能积几十上百颗，一次吸完会在几帧内连续 `add_xp`。实测吸 24 颗直接把等级顶上去并弹出升级面板——`game.gd` 的 `_pending_level_ups` 排队机制正确吃下连续升级，不丢 XP。**磁石很容易连锁升级**，这是它的实际价值所在。

**护盾**按「次数」而不是「伤害量」抵消：一层挡一下，不管这一下打多少。抵消时照常给无敌帧 + 蓝闪，但不掉血。玩家身上挂 `ShieldRing`（`_draw` 画圆环，层数越多越亮）。

**护盾有时限（`SHIELD_SECONDS = 15`）**：层数和倒计时是**同一个效果的两个上限**，谁先到谁先结束——

- 时间到，**没用完的层数直接清零**（不是「留着以后用」）。否则一路捡护盾就等于永久无敌，`shield_charges` 只增不减。
- **期间再捡一个护盾，取「更长的那个窗口」而不是相加**：`shield_left = maxf(shield_left, SHIELD_SECONDS)`。相加会让连捡两个变成 30s，护盾就成了可囤积资源；取 max 让它始终是「刷新」语义。层数照常叠加。
- **最后一层被打掉时立刻清倒计时**，不留一个 0 层却还在跑的计时器——否则下一次捡护盾会继承上一段的残余时间。
- 倒计时在 `GameState._process` 里递减，和时停一样放在 `is_running` 判断**之前**，但 autoload 是 pausable 的，所以升级面板暂停时护盾不会偷偷过期。
- HUD 显示 `护盾 ×2 (3.0s)`；`ShieldRing` 在**最后 3 秒（`WARN_LEAD`）闪烁**预警，闪烁曲线抽成纯函数 `expiry_alpha_mult(remaining)` 以便自检直接断言，不用靠看画面。

**时间暂停只冻结敌人**：`GameState.is_time_stopped()` 为真时 `enemy.gd` / `enemy_projectile.gd` 的 `_physics_process` 开头直接 return，冻结期间染蓝灰；玩家照常移动开火。**没有碰 `Engine.time_scale`**——那会把玩家、tween、粒子一起冻住。倒计时在 `GameState._process` 里放在 `is_running` 判断**之前**递减，但 autoload 默认 pausable，所以升级面板暂停时时停不会偷跑。

**满槽时武器道具优先凑合并**：`grant_random_weapon()` 在 12 槽全满时，只接受「能立刻凑成 3 连合并」的武器（那一手净腾出 2 个槽）；凑不上就拒绝，不会静默丢掉。

**顺手修的一个老 bug**：`enemy.gd` 的 `_flash()` 原本补间回 `config.sprite_color`，但 `_apply_visuals` 给精英/BOSS 上的是 `Color(1.4,0.6,0.6)` / `Color(1.2,0.6,0.6)`——精英挨一下就永久掉红染。现在 `_apply_visuals` 缓存 `_base_tint`，`_flash()` 和时停解冻都补间回它。

贴图由 `tools/gen_pickups.py` 生成（和挂件同一套字符画 + Kenney Tiny Dungeon 调色板 + `--check` 校验），6 张 16×16，`SPRITE_SCALE 2.0` 和经验宝石一致：

```bash
python tools/gen_pickups.py          # 重新生成到 assets/sprites/pickups/ 并校验
python tools/gen_pickups.py --check  # 只校验现有文件
```

自检（6 种效果 / 护盾抵消 2 次后失效 / **护盾 15s 过期清层** / **重复捡取取更长窗口** / **最后一层用完清倒计时** / **临过期闪烁曲线** / 时停期间敌人不动且结束恢复 / 炸弹半径内外 / 满槽拒绝 / 满槽凑合并 / 磁石吸全图 / **磁石不可叠加**）：

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

## 武器稀有度（掉落权重 + 掉落等级）

武器道具给哪一把不再是均匀随机。**强力武器稀少，但掉落即高等级**——这两半必须一起看，缺任一半都会做坏。

### 掉落权重（`WEAPON_CATALOG` 里的 `weight`）

权重是「怎么获得」而不是武器自身属性，所以和 `config` / `scene` 并列放在 catalog 条目里，不进 `.tres`。

| 武器 | 权重 | 占比 | 理由 |
|---|---|---|---|
| `bullet_volley` 弹雨 | 20 | 18.2% | **融合材料，必须常见** |
| `orbiting_blades` 刀阵 | 20 | 18.2% | **融合材料，必须常见** |
| `chain_lightning` 闪电链 | 20 | 18.2% | **融合材料，必须常见** |
| `shotgun` 散弹枪 | 20 | 18.2% | 基础近战型 |
| `homing_dart` 追踪飞镖 | 12 | 10.9% | 自动瞄准，不用贴脸 |
| `flamethrower` 火焰喷射器 | 7 | 6.4% | 持续锥形覆盖 |
| `laser_lance` 磁轨激光 | 7 | 6.4% | 520 长贯穿线 |
| `mine_layer` 地雷布设器 | 4 | 3.6% | 55 伤害 × 150 半径 × 同时 6 颗 |
| **合计** | **110** | | |

抽取被提成**无副作用的纯函数** `_roll_weighted_id(pool)`，`grant_random_weapon()` 只是它的调用方。这样自检能采样两万次验分布而不会真的加武器/触发合并（`grant_random_weapon()` 有副作用，没法用来测分布）。满槽分支走同一个函数，只是 pool 先被 `_can_complete_merge` 过滤——**稀有度在满槽时依然生效**。

### 掉落等级（`WeaponConfig.drop_level`）

等级是武器自身属性，和已有的 `max_level` 是兄弟概念，所以进 `.tres`（符合项目「数据放 .tres」约定）。

| 武器 | `drop_level` | 一把掉落物的实际价值 |
|---|---|---|
| 火焰喷射器 / 磁轨激光 | 2 | 等于常见武器攒 3 把 |
| 地雷布设器 | 3 | 等于常见武器攒 9 把 |
| 其余 5 把 | 1（默认，`.tres` 不用改） | |

**没有这一半，稀有度就是纯粹的负面设计**：合并要 3 把**同款同级**，一把稀有到永远凑不满 3 把的武器会**严格劣于**常见武器——它占着一个槽却永远停在 Lv1。`drop_level` 让单把稀有武器一落地就值那个槽。稀有武器仍能正常合并（3 把 Lv2 火焰 → 1 把 Lv3），自检 `rare_merge` 锁着这条。

### 为什么融合材料必须是最常见的（改这张表前先读这段）

这是整套数值里最容易被后人改错的地方——「弹雨/刀阵/闪电链是开局武器，应该最稀有才对」是个很自然但会**直接废掉融合系统**的想法。算一遍：

1. 合并是 `MERGE_COUNT = 3` 把**同 id 同级** → 升一级。所以 Lv2 要 3 把 Lv1，**Lv3 要 9 把 Lv1**。
2. 融合要 `BASE_WEAPONS` 三种**各持有一把 Lv3**（`fuse()` 每种消耗一个副本）。
3. 于是完成一次 3 件组融合需要 **9 × 3 = 27 把特定 id 的掉落**。

27 把不是「稀有度可以调节」的量级，而是**只有当这三种各占 18% 时才够得着**的量级。任何低于 20 的权重都会把融合从「长线目标」变成「不可能」。所以：

- 三种融合材料的权重**必须并列最高**，且必须彼此相等（否则木桶效应，最稀的那种卡死全部 4 个融合物）
- 它们的 `drop_level` **必须留在 1**：掉落即 Lv2 会让「3 把同级」的分母错位——手上混着 Lv1 和 Lv2 副本时两边都凑不满，反而更难到 Lv3
- 要让某把武器变稀有，请从 `homing_dart` / `flamethrower` / `laser_lance` / `mine_layer` 里调，这四把不在任何融合配方里

### 一起改掉的 `_can_complete_merge` 硬编码

`_can_complete_merge` 原本写死 `w.level == 1`，注释是「A newly granted copy is level 1」——有了 `drop_level` 这句话就不成立了。满槽时掉一把 Lv2 激光，它会去找 Lv1 副本，找不到 → **明明能合并却被拒**（静默丢掉一把稀有武器）。现在按该 id 的掉落等级比对：`var lv: int = drop_level_of(id)`。自检 `full_slot_accepts_rare_pair` 专门锁这条修复（反证过：改回 `== 1` 立刻变红）。

`drop_level_of()` 从 catalog 的 config 路径 load 再读 `drop_level`（`ResourceLoader` 有缓存，不贵）。**融合武器不在 `WEAPON_CATALOG` 里**（它们是造出来的、不掉落），path 会是空串，而 `ResourceLoader.load("")` 是**硬报错而不是返回 null**——所以有一条显式的空路径守卫返回 1。`_can_complete_merge` 对每次 add 都跑，包括融合武器，这条守卫是必需的。

自检：

```bash
godot --headless res://scenes/dev/weapon_merge_selftest.tscn   # 含 drop_level / rare_merge / full_slot_accepts_rare_pair / drop_weights
```

`drop_weights` 采样 20000 次断言 弹雨 > 飞镖 > 地雷 的顺序、地雷占比落在 4/110 的宽容差区间（±5σ 以上，不会偶发红）、以及 catalog 里每个 id 都抽得到。



| ID | 类型 | 物理 | 效果 |
|---|---|---|---|
| 0 | 沙地 | 无 | 正常通行 |
| 1 | 瓦砾 | 阻挡 | 物理碰撞 + 视觉是废铁/碎石 |
| 2 | 废铁 | 阻挡 | 物理碰撞 + 视觉是深色金属 |
| 3 | 地坑 | 阻挡 | 物理碰撞 + 视觉是深坑 |
| 4 | 毒沼 | **不挡** | 减速 50% + 每 0.5s 扣 1 滴血（玩家+敌人，走 DoT 通道） |
| 5 | 精英营地 | **不挡** | 暗混凝土 + 锈红警戒条纹，`EliteCampDirector` 的刷怪点 |

默认 **128×128** 格地图（8192×8192 px，以原点为中心）、seed=1337，障碍合计 10%，毒沼 5%，出生点 11×11 安全区，**12** 处半径 3 格的精英营地。**地图四周没有墙**——边界的代价在「地图边界」一节。

## BOSS 降临与难度天花板

BOSS 由 `spawn_director.gd` 的 `boss_spawn_time` 决定，**当前值 300 秒**（5 分钟）。这个旋钮从 300 改成 120 过（连同注释一起改），后来又改回 300 —— 想改节奏只需要动这一个 export。

`boss_spawn_time = 300` 那会儿一直是对的，**但在此之前没人活着见过它**。原因在难度曲线本身：

```
interval = lerp(base_interval 1.2 → min_interval, t / difficulty_ramp_time)
burst    = 1 + int(t * burst_growth 0.02)     # 无上限
```

`interval` 会撞到下限停住，`burst` 却**一直线性长**。代入 t=300：旧参数下是每 0.18s 刷 7 只 ≈ **39 只/秒**，而且这个数字往后只会更大。玩家不是被 BOSS 打死的，是被通往 BOSS 的路上那道墙推死的。

修法是加**两道天花板**，而不是把曲线整体调平（调平会让前 2 分钟变得无聊）：

| 参数 | 值 | 作用 |
|---|---|---|
| `min_interval` | 0.25（原 0.18） | 刷怪间隔下限 |
| `max_burst` | 4 | 每次刷怪数上限 → 最坏 **16 只/秒**（原 39） |
| `max_live_enemies` | 110 | **同时存活**上限，刷怪前先查 `live_enemies()` |

- `max_burst` 只是把曲线削平；**`max_live_enemies` 才是真正的保证**——不管以后谁怎么调另外几个旋钮，同屏数量和帧开销都被这一条兜住。
- `burst_for(t)` 抽成**纯函数**，这样自检可以直接断言 t=600 的 burst 而不用真的跑 10 分钟。
- `live_enemies()` 会过滤 `is_queued_for_deletion()` 的敌人：刚死的敌人还会在 `enemies` 组里待一帧，不滤掉的话一次大清场会让天花板在尸体早就无所谓之后仍然堵着不刷。

### 这张表上一版是假的：16 只/秒 曾经从未生效

`min_interval` 的脚本默认值改成了 0.25，但 `scenes/game.tscn` 里那个 `SpawnDirector` 节点**带着一行 `min_interval = 0.18` 的场景覆盖**。场景覆盖赢过脚本默认值，所以真实游戏跑的一直是 4/0.18 = **22.2 只/秒**，而 README 和 commit 里都写着 16。

问题不在于改错了一个数，而在于**测试测不到它**：`boss_selftest` 是自己 `new` 一个 `SpawnDirector` 的，永远看不到场景里的覆盖值，所以整套天花板测试全绿、真实游戏超标 39%。

修法是删掉那行覆盖（让脚本成为唯一来源），再加一条读**出厂场景**的测试：

```gdscript
var st: SceneState = (load("res://scenes/game.tscn") as PackedScene).get_state()
```

`shipped_scene_ceilings` 用 `PackedScene.get_state()` 直接读节点的属性覆盖，不实例化整个世界，然后拿"覆盖值 → 没覆盖就取脚本默认值"这一对算实际峰值。它对**任何**旋钮的场景/脚本分歧都有效，不只是 `min_interval`。反证过：把 `min_interval = 0.18` 加回 game.tscn，它立刻报 `game.tscn ships 22.2/s (max_burst 4 / min_interval 0.18s), past the 20/s ceiling`。

> 一个测试里的坑：那些默认值必须从 `(load("res://scripts/spawn_director.gd") as GDScript).new()` 这样一个**临时实例**上读，不能从自检场景里那个 director 上读——自检场景自己把 `boss_spawn_time` 覆盖成了 99999，拿它当"默认值"会变成用测试脚手架去比对出厂场景。

### ⚠️ 曾经的一处失衡：BOSS 比精英波先到

`boss_spawn_time` 曾经是 120 而精英波的门是 `t >= 300.0`，意味着**打完 BOSS 才开始出精英**。后来 `boss_spawn_time` 改回 300，这条失衡自动消失了——两者现在同时到点。如果再把 BOSS 提前，记得这条会回来：要么把精英门跟着降，要么接受"BOSS 是中期考试"。

### BOSS UI（三件套，都挂在 `GameState` 的信号上）

| 信号 | 发出方 | 消费方 |
|---|---|---|
| `boss_incoming(left)` | `spawn_director._tick_boss_warning()`，**每秒一次**（不是每帧） | HUD 大横幅 |
| `boss_spawned(node)` | `_spawn_boss()`，**在 `add_child` 之后** | HUD 顶部血条 + 屏幕外箭头 |
| `boss_state_changed(ratio, phase)` | `enemy.take_damage()` 里 BOSS 分支 | 血条填充 + 阶段文字 |
| `boss_defeated()` | `enemy._die()` | 收起血条和箭头 |

- **提醒增大**：横幅字号 **64**，降临前 `boss_warn_lead = 6` 秒开始播报，文字带整秒倒计时（`BOSS 即将降临  5`）。BOSS 落点在玩家 **+600px** 方向随机（448px 身体不能落在冲刺触发带里或玩家脸上），配上提前量，它不会直接压在脸上出现。
- **血条**：屏幕顶部横贯条，`boss_spawned` 时出现，之后**只由 `boss_state_changed` 驱动**——伤害是唯一能让血条动的事件，而它本来就是逐次命中的事件，没必要每帧轮询。`boss_state_changed` 传的是**比例**而不是绝对血量，所以血量从 1000 提到 2500 时 HUD 一行都不用改。
- **屏幕外红色箭头**（`scripts/ui/boss_marker.gd`）：BOSS 出画时在屏幕边缘画红色三角指向它。世界坐标 → 屏幕坐标走 `get_viewport().get_canvas_transform() * boss.global_position`（HUD 是 CanvasLayer，它的局部坐标就是屏幕坐标）。
  - 边缘定位抽成纯静态函数 `marker_for(screen_pos, rect, margin) -> Dictionary`，用**射线 vs 盒**（把方向向量缩放到先撞上的那条半轴）而不是逐轴 clamp——逐轴 clamp 在斜角方向会把箭头贴错边。自检直接断言几何结果，不看画面。
  - `margin` 会被 clamp 到窗口半宽/半高，避免窗口比 `2*margin` 还小时缩出一个负尺寸矩形（箭头会镜像）。

验收时实测（`boss_spawn_time` 当时是 300）：`step_until _boss_spawned` 在 `time_alive = 300.0025` 命中；BOSS 掉到一半时血条 `fill = 0.55`、标题 `废土巨兽  阶段 1`；把 BOSS 挪到玩家 +(1400,-900) 后箭头落在 `(1133, 46)`（y 正好等于 `EDGE_MARGIN 46`，即贴在上边缘）、角度 −0.567 rad 指向右上，并在该位置采到实际渲染像素 `(0.99, 0.40, 0.22)`——确认是真的画出来了，而不只是算对了。

## BOSS：毒物与爪击

废土巨兽从"一个大号的追踪怪"变成了有三套攻击的战斗：**远程抛毒** + **近战爪击** + **直线冲刺**。数值全在 `data/enemies/boss.tres`，字段定义在 `scripts/enemy_config.gd`。

| 项 | 值 | 说明 |
|---|---|---|
| `max_hp` | **25000**（原 1000 → 2500 → 5000） | HUD 血条走比例，不用改 UI |
| `sprite_size` / `sprite.scale` | **448px** / **28.0×**（原 224px / 14.0×） | 源图是 16×16 |
| `collision_radius` | **224**（原 112） | 跟着体型走，否则打不到的地方看起来能打 |
| `contact_damage` | 40 | 接触伤害（高于精英 22） |

**体型加大带来的副作用必须一起处理**：直径 448px 的身体要在 64px 的障碍格之间穿行，会卡死在废墟后面。所以 BOSS 分支里 `set_collision_mask_value(1, false)`——巨兽踏碎废墟，只保留对玩家层的碰撞。巨兽卡在地形里是硬 bug，而"巨兽不被墙挡"恰好也是它该有的样子。`NavigationAgent2D` 保持不动：它绕的是自己已经能踩过去的障碍，路径次优但不会错，比重写寻路安全。

**体型翻倍后攻击范围必须跟着重标**：玩家最小中心距 = 224(身体) + 14(玩家) ≈ 238，任何小于它的攻击永远打不中。所以爪击 reach 190→**320**、冲刺触发带 220-480→**340-560**、冲刺命中半径 135→**248**——这三处是"巨兽变大"的连带成本，不是可以省的旋钮。

### 远程毒物

```
boss_poison_interval 3.0   boss_poison_count 3      boss_poison_flight 0.55
boss_poison_pool_radius 95 boss_poison_pool_life 6  boss_poison_dps 14  boss_poison_tick 0.5
```

`PoisonGlob`（`scripts/poison_glob.gd`）飞 `flight` 秒落地，生成 `PoisonPool`（`scripts/poison_pool.gd`）。

- **毒团飞行途中不伤人，也没有 Area2D**：落点才是威胁，飞行弧线是玩家的躲避线索。命中判定 100% 在毒池里，只有一个伤害来源。
- **飞行用固定时长而不是固定速度**：预警窗口必须与距离无关。固定速度会让贴身喷的毒在玩家能反应之前落地，而远处喷的又慢到没威胁。（`boss_poison_speed` 这个旋钮曾经存在过，但没有任何代码读它，已经删掉。）
- 多团时以玩家为中心张开一把扇子、中间那团仍然对准玩家，所以**站着不动永远是最差选择**。
- 阶段缩放：P2 数量 +1、间隔 ×0.8；P3 数量 +2、间隔 ×0.65。
- **不加贴图，全程序化 `_draw()`**：`tools/gen_bullets.py` 的调色板是金/红/品红，**一点绿都没有**，而 `verify()` 会拒绝调色板外的颜色。而且毒池半径随配置变化、本来就必须按半径画。和 `explosion.gd` 同一个模式。

### 近战爪击

```
boss_claw_damage 34  boss_claw_reach 320  boss_claw_arc 1.9 (≈109°)
boss_claw_windup 0.45  boss_claw_cooldown 2.6
```

| 阶段 | 发生的事 |
|---|---|
| 距离 ≤ `reach` 且冷却好了 | **锁定朝向** `_claw_facing`、生成 `ClawSlash` 预警弧、`velocity = 0`（定住脚就是那个预告） |
| 预警 0.45s 结束 | `ClawSlash` 转命中态；玩家若仍在楔形内 → `take_damage(34)` |

**朝向为什么必须在预警开始时就锁死**：这是整套设计里唯一可以被反制的点。如果命中帧重新朝玩家算一次方向，那么这个扇形攻击就永远打得中——玩家没有任何操作能躲开，"预警"变成纯装饰。锁死之后横向绕过侧面就是有效躲避，玩家学得到东西。自检 `claw_locks_facing` 正面守着这条：预警开始后把玩家挪到弧外，伤害必须是 0。反证过，把判定改成用当前方向，它立刻报 `stepping behind the locked facing still took 34.0 — the claw tracks the player and cannot be dodged`。

**爪击走正常的 `take_damage`**（不是下面那条 DoT 通道）：它是一次离散重击，无敌帧和护盾正是为这种伤害设计的。

**伤害由 BOSS 自己在命中帧结算，`ClawSlash` 纯视觉**：不像 `explosion.gd` 那样把伤害埋在特效里，单一伤害来源更好查。判定则抽成纯静态函数，照 `boss_marker.gd:marker_for` 的先例——这是自检唯一能验证 `_draw` 类逻辑的办法：

```gdscript
static func in_arc(from: Vector2, facing: Vector2, target: Vector2,
		reach: float, arc: float) -> bool
```

`claw_geometry` 断言 10 个用例：正前方命中、1.5× reach 落空、正后方落空、90° 落空、弧边界两侧（≈44° 中 / ≈46° 空）、对称的 −44°、`arc = TAU` 时背后也中、零长 facing 不炸、目标与原点重合时算命中。

### 直线冲刺

```
boss_dash_damage 45  boss_dash_windup 0.5  boss_dash_speed 950
boss_dash_duration 0.32（≈304px）  boss_dash_recover 0.35  boss_dash_cooldown 5.0
boss_dash_min_range 340  boss_dash_max_range 560  boss_dash_hit_radius 248
```

| 阶段 | 发生的事 |
|---|---|
| 距离 ∈ [220, 480] 且冷却好了 | **锁定方向** `_dash_facing`、生成 `DashTelegraph` 预告线、定住脚（步行 70 的 ~13 倍速度，这预告必须看得见） |
| 蓄力 0.5s 结束 | 沿锁定方向以 950px/s 直线冲 0.32s；玩家进入 `hit_radius`（248 = 224 身体 + 玩家 + 余量）→ 恰好结算一次 `take_damage(45)` |
| 冲完 | 硬直 0.35s（定在原地，这是反打窗口），然后回到普通寻路 |

**这个技能补的是爪击和步行之间的空档**：340 以下归爪击（reach 320），560 以上就正常追，中距离靠冲刺快速拉近——三套攻击各管一段距离，不会互相重叠触发。

**方向和爪击一样在起手时锁死**，理由也完全一样：如果冲刺每帧重新对准玩家，这条线就永远追得上人，横向让开就不再是躲避。自检 `dash_machine` 专门在冲刺中途把玩家瞬移到另一侧——如果实现偷偷跟了人，位移断言（必须是锁定的 304px 直线）立刻变红。反证过：把 `_dash_facing` 换成每帧当前方向，它报 `dashed (0.0, -19.0), expected the locked line (304.0, 0.0)`。

其他刻意设计：

- **冲刺期间跳过接触伤害（25）**：冲刺命中是位置判定，接触伤害走碰撞判定，两者会在同一帧双份结算。冲刺时单一伤害来源 = `dash_damage`，和爪击"伤害由 BOSS 自己结算"同一套哲学。
- **命中走正常的 `take_damage`**：离散重击，护盾和无敌帧按设计抵挡——无敌帧在身时冲空也正常，和爪击同一套规则。
- **位移用 `move_and_collide(velocity * delta)` 而不是 `move_and_slide`**：自检要用假 delta 驱动状态机并断言精确位移，而 `move_and_slide` 内部用的是真实物理帧 delta。代价是侧滑行为更少，但 BOSS 本来就只跟玩家对撞，撞上就是终点。
- **阶段缩放与毒物同一套**：P2 冷却 ×0.8、P3 冷却 ×0.65 + 速度 ×1.2。
- `DashTelegraph`（`scripts/dash_telegraph.gd`）纯视觉：蓄力期画沿线的半透明长条 + 三个方向箭头（随进度变亮），命中帧变亮色残影 0.15s 后自灭。伤害不在它里面。

## 地图边界：没有墙，只有代价

地图从 64 格加大到 **128 格**（8192×8192 px，以原点为中心），并且**删掉了原来那圈 2 格宽的边界坑墙**。

删墙的理由：一堵能走过去靠着的墙，会教玩家"地图边缘是个安全的放风筝位置"——贴边打怪只需要照顾 180°。墙不是边界，它是个战术道具。现在地图就是**结束了**，代价单独存在。

### 三个 API（`tilemap_builder.gd`，`world.gd` 转发）

| 方法 | 语义 |
|---|---|
| `map_rect() -> Rect2` | 地图覆盖的世界矩形。格子跑 `-size/2 .. size/2-1`，格 (x,y) 占像素 `x*TS .. x*TS+TS`，所以矩形从 `-size/2*TS` 开始 |
| `out_of_bounds_depth(pos) -> float` | 在矩形外多少**像素**；在里面返回 0 |
| `camp_placement_limit() -> int` | 营地中心能用的最外圈格（见「精英营地」一节） |

`out_of_bounds_depth` **返回距离而不是 bool**，有两个具体原因：HUD 的红晕要能随"出去多深"淡入；斜着出界时用的是到矩形的**真欧氏距离**，所以抄近路穿角不会比正面跨边便宜。

### 出界扣血（`scripts/world/out_of_bounds.gd`）

```
depth = 0  → 清警告、_out_time 归零
depth > 0  → _out_time += delta
			 dps = base 20 * clampf(1 + _out_time / ramp 3.0, 1, ramp_max 4.0)
			 每 tick 0.25s → player.take_dot_damage(dps * tick, 深红)
			 GameState.out_of_bounds_changed.emit(depth, dps)
```

20/秒起跳、每 3 秒爬一档、封顶 **80/秒**。100 血从跨界到死 **3.5 秒**（`bounds_selftest` 里按离散跳数实测的数字，不是连续积分的估算）——是道真墙，但擦过一个角还来得及跑回来。

两个刻意的设计：

- **只挂玩家，没有复用 `ToxicSwamp` 那种"玩家和敌人都挂"的写法**。`toxic_swamp.gd` 同时挂在 `enemy.tscn` 上，而敌人本来就生成在镜头外——玩家贴边时半数生成点落在图外。如果敌人也吃出界伤害，边界就会变成一台自动刷分机：站在角上等敌人自己融化。**出界是给玩家的规则，不是全局物理。**
- **地图还没生成时直接 return**。`map_rect()` 在那之前是零尺寸的，会把"图外"读成整个世界，开局第一帧就把玩家烧死。没有地图 = 没有边界。

### 为什么必须新开一条 DoT 通道（改这里前先读这段）

出界扣血、BOSS 毒池、毒沼三者都是持续伤害，而 `player.gd` 原来的 `take_damage` 有三个对 DoT 完全反作用的性质：

| `take_damage` 的性质 | 对 DoT 的后果 |
|---|---|
| `if invulnerable: return`（0.4s 无敌帧） | 0.25s 一跳被压到最多 2.5 跳/秒，"持续高额"直接失效 |
| `consume_shield()` 是"整发吸收" | 1 点毒伤换 1 层护盾，两层在一秒内蒸发——护盾比没有还糟 |
| `player_hurt` → `fx_manager` → `request_hit_stop(0.08)` → `Engine.time_scale = 0.05` | **每跳卡顿全局 0.08 秒**，站在毒池里整个游戏抽搐 |

所以 `take_dot_damage(amount, flash)` 只做三件事：扣血、闪色、发 `player_health_changed`。护盾既不抵挡也不被消耗，无敌帧不参与节流（DoT 自己的 `tick` 间隔才是节流器），也不发 `player_hurt`。

**这同时修了一个现存 bug**：`toxic_swamp.gd` 原本就走 `take_damage`，也就是说改之前的毒沼**每 0.5 秒消耗一层护盾、并且卡顿一次全局时间**。它是这条通道的第一个受益者，不是新增范围。

三条性质各有一条自检守着，且都反证过——把 `take_dot_damage` 改成转发给 `take_damage`，`poison_dot` / `poison_shield` / `dot_no_hit_stop` / `bypass` 四条一起变红。其中 `dot_no_hit_stop` 断言的是 `player_hurt` 的发出次数（5 跳必须 0 次），而不是 `Engine.time_scale`——自检场景里没有 `FxManager`，直接测 time_scale 会假绿，所以测那个**触发它的信号**，另外配一条对照（`take_damage(5.0)` 必须至少发 1 次）。

### 敌人生成点也得跟着改

`_random_offscreen_point()` 原来完全不看地图，玩家贴边时半数生成点落进图外的虚空。

**修法不是 clamp 到 `map_rect`**：把一个图外的点夹进矩形，会把它夹到玩家附近甚至**屏幕内**——敌人当脸凭空出现比敌人站在图外更糟。现在的做法是四条边随机打乱后依次试，取第一个落在图内的；四条都不行（玩家已经跑到图外很远）就退回原行为，宁可在虚空里生成，也不要因为玩家越界就整个停止出怪。

实测（`bounds_selftest`）：玩家贴一条边时 **200/200** 落在图内、**0/200** 落在屏幕内；站在角上时 **90%** 落在图内，剩下的走 fallback。角落做不到 100% 是已知且刻意的——那里两条边完全不可用、另两条只有一部分可用。

## 第二关：机器人工厂

杀掉第一关的废土巨兽后**自动进入第二关**（`game_factory.tscn`）：武器 / 等级 / 被动全保留，只有地图和刷怪节奏重置（`GameState.current_level`，`reset()` 会拨回 1）。

**房间地图**（`map_style = 1`，`factory_world.tres`）：`_paint_rooms()` 把 128×128 地图切成 8×8 网格，每格内缩出一个房间，相邻房间用 2 格宽 L 形走廊连通；墙壁 `T_METAL_WALL`（阻挡 + 不可走），地板 `T_FACTORY_FLOOR`（可走 + 有导航多边形）。出生点周围 5 格强制清空。导航多边形从"障碍格"挪到了"地板格"——之前整个项目的地图导航是反的（导航网格只覆盖了障碍物，敌人实际全走直线追击），第二关的走廊寻路必须要这条修复。

**墙壁挡子弹**：玩家弹和敌弹的 `collision_mask` 都加上了 World 层，撞到 TileMap 直接消失（不消耗穿透）。武器索敌在第二关加 **LOS 射线检测**（`_has_line_of_sight`）：隔着墙的敌人不能被锁定，第一关噪声地形不启用。

**新敌人**（贴图由 `tools/gen_enemies.py` 生成，16×16）：

| id | 行为 | 说明 |
|---|---|---|
| `machine_dog` 机器狗 | DASHER（冲刺+跳跃） | 移速 80，跳跃更频繁 |
| `robot` 机器人 | SHOOTER（远程射击） | 射程 280，伤害 10 |
| `decay_knight` 腐朽骑士 | ELITE（坚韧追击） | 120 血、接触 28、掉率 50% |
| `giant_robot` 巨型机器人 | **GOBOT（全新）** | 30000 血：激光（4s 冷却 1s 蓄力 120px 宽光束）、导弹（3s 冷却 5 发齐射）、震地（6s 冷却 AoE 150px），P2 冷却 ×0.8 / P3 ×0.65；**保留 World 碰撞**（走门不穿墙，和废土巨兽相反） |

第二关的生成池是 `machine_dog / robot / decay_knight` 三选一（无杂兵），BOSS 换成巨型机器人。杀巨型机器人 → 结算界面金色「任务胜利」。

## 全部自检

每个自测都是 headless 场景，全绿 exit 0、有失败则 exit 1，可以直接串进 CI：

```bash
godot --headless res://scenes/dev/elite_camp_selftest.tscn    # 精英营地
godot --headless res://scenes/dev/pickup_selftest.tscn        # 6 种道具 + 磁石吸全图 + 槽位上限/满槽合并
godot --headless res://scenes/dev/weapon_merge_selftest.tscn  # 3 合 1 合并 + 曲线 + 级联
godot --headless res://scenes/dev/weapon_mount_selftest.tscn  # 挂件布局（右手起两列 + 满槽 12 图标）
godot --headless res://scenes/dev/range_pierce_selftest.tscn  # 射程、穿透、追踪目标中途死亡
godot --headless res://scenes/dev/fusion_selftest.tscn        # 4 个融合配方 + 备用副本
godot --headless res://scenes/dev/pause_selftest.tscn          # ESC 暂停/恢复 + 暂停面板内容
godot --headless res://scenes/dev/boss_selftest.tscn           # BOSS 到点刷出 + 难度天花板 + 出厂场景值 + 爪击/毒池/冲刺/DoT 通道
godot --headless res://scenes/dev/bounds_selftest.tscn         # 地图尺寸 + 拆墙 + 出界爬坡扣血 + 绕过护盾/无敌帧 + 营地/生成点不落虚空
python tools/gen_enemies.py --check                            # 4 张敌人贴图（机器狗/机器人/骑士/巨型机器人）
python tools/gen_weapon_mounts.py --check                     # 12 张挂件贴图
python tools/gen_pickups.py --check                           # 6 张道具贴图
python tools/gen_bullets.py --check                           # 2 张子弹贴图
```

`SystemCheck` 也会在每次运行时把新增的脚本 / 场景 / 资源 / `GameState` 字段一并核对（包括 12 把武器的 `.tres` 与 `.tscn`、`pickup_item` / `explosion` / `shield_ring` / `elite_camp_director` / `boss_marker` / `poison_glob` / `poison_pool` / `claw_slash` / `out_of_bounds`、`shield_charges` / `shield_left` / `time_stop_left`，以及 `boss_incoming` / `boss_spawned` / `boss_state_changed` / `out_of_bounds_changed` 等信号是否真的存在），缺一个就在 Output 面板报 FAIL。dev 自检场景照惯例不入 system_check——它们自己就是检查者。

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
│   ├── ui/                     # HUD / LevelUp / GameOver / UpgradeCard / Shop / PauseMenu
│   └── weapons/                # 8 基础 + 4 融合武器 + 飞刀 + 地雷场景
├── scripts/
│   ├── globals/
│   │   ├── game_state.gd      # Autoload: 状态 + 事件总线 + 属性倍率 + 护盾/时停 + 被动账本
│   │   ├── upgrade_db.gd      # Autoload: 升级数据表（纯被动）
│   │   ├── meta_progress.gd   # Autoload: 永久货币 / 统计，落盘 user://
│   │   └── system_check.gd    # Autoload: 启动期 autoload/脚本/场景/资源自检
│   ├── player.gd
│   ├── bullet.gd
│   ├── enemy.gd
│   ├── enemy_config.gd        # EnemyConfig 资源类（含 item_drop_count + boss 爪击/毒物字段）
│   ├── enemy_projectile.gd
│   ├── spawn_director.gd      # 波次 + 敌人类型编排 + spawn_enemy_at() + 生成点挑图内的边
│   ├── poison_glob.gd         # BOSS 抛出的毒团，飞行 flight 秒后落地成池
│   ├── poison_pool.gd         # 毒池：半径内按 tick 走 take_dot_damage，全程 _draw()
│   ├── claw_slash.gd          # 爪击预警弧 + 命中扫击（in_arc 纯函数）
│   ├── dash_telegraph.gd      # 冲刺预告线 + 命中残影（纯视觉，无伤害判定）
│   ├── xp_gem.gd
│   ├── pickup_item.gd         # 6 种道具的掉落权重与效果（含磁石吸全图）
│   ├── explosion.gd           # 炸弹道具与地雷共用的范围伤害
│   ├── shield_ring.gd         # 玩家身上的护盾圆环（含临过期闪烁）
│   ├── game.gd
│   ├── hud.gd                 # 含护盾倒计时 / BOSS 顶部血条 / BOSS 大横幅 / 出界红晕与警告
│   ├── ui/
│   │   └── boss_marker.gd     # BOSS 出画时的屏幕边缘红色箭头（marker_for 纯函数）
│   ├── level_up.gd
│   ├── upgrade_card.gd
│   ├── game_over.gd
│   ├── shop.gd
│   ├── pause_menu.gd          # Esc 暂停面板：武器等级/合并进度 + 被动清单
│   ├── fx_manager.gd
│   ├── floating_label.gd
│   ├── burst_particles.gd
│   ├── shake_camera.gd
│   ├── weapon_mounts.gd       # 玩家身上的武器挂件布局与朝向
│   ├── weapon_director.gd     # Autoload: 12 武器槽 + 合并 + 融合 + 跨场景清理
│   ├── dev/                   # 自测脚本（pickup / elite_camp / mount / merge / pause / boss / bounds / ...）
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
│       ├── tilemap_builder.gd    # 运行时生成 TileSet + 铺地图 + 挖营地 + map_rect/depth
│       ├── elite_camp_director.gd # 营地刷怪 / 冷却 / 激活半径
│       ├── world.gd              # 场景入口（持有 TileMap，转发边界查询）
│       ├── toxic_swamp.gd        # 角色身上的毒沼 slow + dot 效果（DoT 通道）
│       └── out_of_bounds.gd      # 玩家身上的出界爬坡扣血（绕过护盾/无敌帧）
├── data/
│   ├── enemies/               # 5 EnemyConfig .tres（含 boss）
│   ├── weapons/               # 12 WeaponConfig .tres
│   └── world/
│       └── default_wasteland.tres  # 128x128 地图默认配置（seed=1337，12 营地）
├── tools/
│   ├── gen_weapon_mounts.py   # 生成 + 校验 12 张武器挂件贴图（Python + Pillow）
│   ├── gen_pickups.py         # 生成 + 校验 6 张道具贴图（Python + Pillow）
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
- 地图固定 8192×8192，未做"越打越大"扩展
- 融合是单向的，融合后无法拆回基础武器；一局最多融合一次（每个融合物的基础副本被消耗）
- 射程只约束子弹；旋转刀与闪电链仍各走自己的 `blade_dash_lifetime` / `chain_range` 逻辑
- `chain_lightning.gd` 与 `apocalypse.gd` 的电链未校验 `config.chain_range`（`storm_volley` / `lightning_blade` 有校验）
- 玩家精灵本身仍无朝向 / 无动画（`player.gd` 里没有 `flip_h` / `rotation`），只有武器挂件会转
- 武器挂件只有 13×8 ~ 16×10 格有效分辨率，造型全靠轮廓辨认，细节做不进去；文生图模型在这个尺度上不可用（详见「武器挂件」一节）
- `blade.gd:_return_to_orbit` 在所属武器已被 `queue_free` 后仍会尝试 reparent，冲刺中的刀会刷一条 `Can't add child` 报错（不影响功能）
- 精英营地固定 12 处、只刷 `elite_brute` 一种，没有营地专属的更强变体或多波
- 道具没有稀有度分层，权重是写死的常量，不随时间或难度变化（武器**内部**有稀有度，见「武器稀有度」）
- 融合门槛很高：每种材料要 9 把才到 Lv3，3 件组共需 27 把特定掉落，即使按最高权重 20 也是**长线目标**，一局大概率摸不到 3 件组
- 磁石只吸掉落物，不吸敌人掉落之外的东西；也没有「吸取半径永久变大」这类被动可以叠
- 时间暂停只 early-return 敌人与敌弹的 `_physics_process`，敌人身上正在跑的 tween（击退、闪白）不受影响
- 护盾时限是写死的 `SHIELD_SECONDS = 15`，没有「护盾持续时间 +X%」这类被动可以叠；HUD 只显示一位小数的倒计时，没有环形进度条
- BOSS 只有一个（`boss.tres`），`boss_spawn_time` 过后不会再刷第二只，也没有 5/10/15 分钟的多阶段 BOSS 序列
- `max_live_enemies = 110` 是全局上限而不是按屏幕/按类型的，所以后期远处的杂兵也会占用配额；`max_burst` 与 `min_interval` 的组合上限（16 只/秒）由 `shipped_scene_ceilings` 守着出厂场景值，但曲线的其它部分没有自动的 DPS 平衡校验
- BOSS 爪击/冲刺都是"锁朝向单次判定"：没有多段连抓、没有后续追击，冲刺也不可转向；出界惩罚也只对玩家生效（刻意，见「地图边界」一节）

## 扩展路线（不属于 MVP）

- 替换程序化瓦片为真实像素艺术
- BGM + 更丰富的音效层次
- Boss 房间 + 多区域随机地图
- 融合武器自身的升级曲线（目前融合物固定 1 级）
- 毒气视觉 / 闪避 / 击退
