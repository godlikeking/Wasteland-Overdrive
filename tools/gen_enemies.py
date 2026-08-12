"""生成 3 张敌人贴图（assets/sprites/enemies/{machine_dog,robot,decay_knight}.png）。

用法（仓库根目录执行，需要 Pillow）：
    python tools/gen_enemies.py            # 写入素材目录并校验
    python tools/gen_enemies.py --check    # 只校验现有文件，不写盘

和 gen_bullets.py 同一个模式：BLOCK = 1（原生 16×16 分辨率，一个字符一个像素）。
朝向必须烘进 PNG：enemy.gd 不旋转，全部朝 +X（右）。所以字符画一律**面朝右**。

giant_robot.png 已**退出本脚本管理**：它换成了 160×160 的外部美术素材，不再由
字符画生成。原来那份 16×16 字符画留在生成表里会是个陷阱 —— 只要有人不带
--check 跑一次本脚本，就会把 160×160 的成品覆盖成 16×16 的占位图，而且一声
不响。所以从 ART 里删掉了它，改在 EXTERNAL 里留一条尺寸校验：enemy.gd 是按
sprite_size ÷ 贴图原生尺寸算放大倍数的，原生尺寸一变，上屏大小就跟着静默变
（16px 那版曾经把它渲染成 4480px）。
"""
import argparse
import os
import sys

from PIL import Image

# 取 gen_pickups.py 的调色板作为基础（钢色/蓝/金/紫都在），再加子弹的红/品红。
PALETTE = {
    "0": (0x3F, 0x26, 0x31, 255),  # 轮廓
    "1": (0xC0, 0xCB, 0xDC, 255),  # 亮钢 / 白
    "2": (0x8B, 0x9B, 0xB4, 255),  # 暗钢
    "3": (0xBD, 0x6C, 0x4A, 255),  # 深木
    "4": (0xEA, 0xA5, 0x6C, 255),  # 浅木 / 铜
    "5": (0xE8, 0x45, 0x37, 255),  # 红
    "6": (0x75, 0xE3, 0xFF, 255),  # 青
    "7": (0xD1, 0x76, 0xD0, 255),  # 品红
    "8": (0xF9, 0xC0, 0x4C, 255),  # 金
    "9": (0x99, 0x24, 0x1C, 255),  # 暗红
    "a": (0x4D, 0x9B, 0xE6, 255),  # 蓝
    "b": (0x76, 0x3B, 0x36, 255),  # 暗红（子弹调色板）
    "c": (0x30, 0x36, 0x4A, 255),  # 深黑蓝
    "d": (0x9B, 0x4C, 0xA3, 255),  # 紫（精英）
    "e": (0x6B, 0x2C, 0x73, 255),  # 深紫（精英暗面）
    ".": (0, 0, 0, 0),
}

BLOCK = 1    # 每个字符 = 1 像素（原生 16×16）
SIZE = 16    # 所有敌人都是 16×16，_apply_visuals 按 behavior 决定 scale

ART = {
    # 机器狗：金属灰机身 + 橙红眼睛 + 尖耳朵，面朝右（+X）
    "machine_dog": """
................
.00..000000.....
.080880000......
005cccc0..0.....
055ccccc0000....
055ccccc0000....
005cccc0.0......
.0000000000.....
..0ccccc0.......
..0cccccc0......
..0ccccc0.......
..0ccccc0.......
..0cccccc0......
...0ccccc0......
....00000.......
................
""",
    # 机器人：蓝灰机兵 + 红色单眼 + 方形肩甲，面朝右
    "robot": """
................
..00000000000...
.0aaaaaaaaaa0...
.0aaaaaaaaaa0...
.0a0000000aa0...
.0a0ccccc0aa0...
.0a0c555c0aa0...
.0a0ccccc0aa0...
.0a0000000aa0...
.0aaaaaaaaaa0...
.0cc000000cc0...
.0cc0aaaa0cc0...
.0cc0aaaa0cc0...
.0cc000000cc0...
.0cccccccccc0...
.0000000000000..
""",
    # 腐朽骑士：紫黑铠甲 + 暗金锈蚀 + 单眼红光，面朝右
    "decay_knight": """
................
..00000000000...
.0ddddddddd0....
.0ddddddddd0....
.0dd000dddd0....
.0d0d77d0dd0....
.0d0dddd0dd0....
.0dd000dddd0....
.0dddeeeedd0....
.0ddeeeeedd0....
.0dde228edd0....
.0ddee2eedd0....
.0dddeeeedd0....
.0ddddddddd0....
.0ddddddddd0....
.0000000000000..
""",
    # 巨型机器人（BOSS）已退出本脚本管理 —— 见模块开头。原来那份 16×16 字符画
    # 已删除，避免它把 160×160 的外部素材覆盖掉；旧图仍在 git 历史里可查。
}

## 不由本脚本生成、但仍要盯住尺寸的外部素材：文件名 -> 期望尺寸。
EXTERNAL = {
    "giant_robot": (160, 160),
}

OUT_DIR = os.path.join("assets", "sprites", "enemies")


def paint(art):
    """字符画 -> RGBA 图像。"""
    rows = [r for r in art.splitlines() if r]
    side = SIZE // BLOCK
    if len(rows) != side:
        raise ValueError("行数 %d != %d" % (len(rows), side))
    im = Image.new("RGBA", (SIZE, SIZE))
    px = im.load()
    for y, row in enumerate(rows):
        if len(row) != side:
            raise ValueError("第 %d 行列数 %d != %d" % (y, len(row), side))
        for x, ch in enumerate(row):
            if ch not in PALETTE:
                raise ValueError("第 %d 行第 %d 列的 '%s' 不在调色板里" % (y, x, ch))
            for dy in range(BLOCK):
                for dx in range(BLOCK):
                    px[x * BLOCK + dx, y * BLOCK + dy] = PALETTE[ch]
    return im


def verify(path):
    """校验一张敌人图是否满足全部格式约束，返回问题列表（空 = 通过）。"""
    bad = []
    im = Image.open(path)
    if im.mode != "RGBA":
        bad.append("mode=%s 不是 RGBA" % im.mode)
        return bad
    if im.size != (SIZE, SIZE):
        bad.append("尺寸 %dx%d != %dx%d" % (im.size[0], im.size[1], SIZE, SIZE))
        return bad
    px = im.load()

    allowed = set(PALETTE.values())
    alphas, colors = set(), set()
    for y in range(im.height):
        for x in range(im.width):
            c = px[x, y]
            alphas.add(c[3])
            if c[3] == 255:
                colors.add(c)
    if not alphas <= {0, 255}:
        bad.append("alpha 不是二值：%s" % sorted(alphas))
    off = colors - allowed
    if off:
        bad.append("越界颜色：%s" % sorted(off))

    # 每 BLOCK x BLOCK 必须是同色块
    for y in range(0, im.height, BLOCK):
        for x in range(0, im.width, BLOCK):
            blk = {px[x + dx, y + dy] for dy in range(BLOCK) for dx in range(BLOCK)}
            if len(blk) != 1:
                bad.append("(%d,%d) 处的 %dx%d 块不同色" % (x, y, BLOCK, BLOCK))
                break
        else:
            continue
        break

    if im.getbbox() is None:
        bad.append("全透明 — 图是空的")
    return bad


def verify_external(path, want_size):
    """外部素材只校验"能用"的底线：存在、RGBA、尺寸没变。

    刻意**不**查调色板和同色块 —— 那两条是给字符画生成物定的规矩，手绘素材
    本来就不该守。尺寸必须查：enemy.gd 按 sprite_size ÷ 原生尺寸算放大倍数。
    """
    bad = []
    if not os.path.exists(path):
        return ["文件不存在"]
    im = Image.open(path)
    if im.mode != "RGBA":
        bad.append("mode=%s 不是 RGBA" % im.mode)
    if im.size != want_size:
        bad.append("尺寸 %dx%d != %dx%d（会静默改变 BOSS 上屏大小）"
                   % (im.size[0], im.size[1], want_size[0], want_size[1]))
    if im.getbbox() is None:
        bad.append("全透明 — 图是空的")
    return bad


def main():
    ap = argparse.ArgumentParser(description="生成 3 张敌人贴图（另校验 1 张外部素材）")
    ap.add_argument("--check", action="store_true", help="只校验不写盘")
    args = ap.parse_args()

    root = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
    out_dir = os.path.join(root, OUT_DIR)
    os.makedirs(out_dir, exist_ok=True)

    ok = 0
    for name, art in ART.items():
        path = os.path.join(out_dir, "%s.png" % name)
        if not args.check:
            im = paint(art)
            im.save(path)
            print("  OK %s.png %dx%d" % (name, im.width, im.height))
        else:
            print("  CHECK %s.png" % name, end="")

        problems = verify(path) if os.path.exists(path) else ["文件不存在"]
        if problems:
            print("  FAIL %s.png: %s" % (name, "; ".join(problems)))
        else:
            ok += 1
            if args.check:
                print(" OK")

    # 外部素材：只校验，永不写盘（写盘就等于覆盖掉美术给的成品）。
    for name, want_size in EXTERNAL.items():
        path = os.path.join(out_dir, "%s.png" % name)
        print("  EXTERNAL %s.png" % name, end="")
        problems = verify_external(path, want_size)
        if problems:
            print("  FAIL %s.png: %s" % (name, "; ".join(problems)))
        else:
            ok += 1
            print(" OK %dx%d（不由本脚本生成）" % want_size)

    total = len(ART) + len(EXTERNAL)
    print("%d/%d 通过" % (ok, total))
    sys.exit(0 if ok == total else 1)


if __name__ == "__main__":
    main()