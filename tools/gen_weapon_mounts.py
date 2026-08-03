"""生成 7 张武器挂件贴图（assets/sprites/weapons/mount_*.png）。

用法（仓库根目录执行，需要 Pillow）：
    python tools/gen_weapon_mounts.py            # 写入素材目录并校验
    python tools/gen_weapon_mounts.py --check    # 只校验现有文件，不写盘

画法：手写半分辨率字符画，一个字符一格，落盘时做 2x 最近邻放大。
半分辨率是刻意的——挂件在游戏里只有十几像素高，Kenney Tiny Dungeon 那套
原始素材也是 2x 放大来的，保持同样的像素颗粒度才不会和其他素材打架。

朝向必须烘进 PNG：weapon_mounts._make_icon 用 offset.x = 宽度/2 当枢轴，
rotation = 0 表示朝 +X。所以字符画一律**握把在左端、前端在右端**，
并且左右必须撑满画布，否则留白会把握把推离挂点。

FORMAT 里的尺寸就是契约，改数值等于改素材尺寸，Godot 侧的 .import 也要跟着重来。
"""
import argparse
import os
import sys

from PIL import Image

# Kenney Tiny Dungeon 调色板中挂件用到的颜色。校验会拒绝这以外的任何颜色。
PALETTE = {
    "0": (0x3F, 0x26, 0x31, 255),  # 轮廓
    "1": (0xC0, 0xCB, 0xDC, 255),  # 亮钢
    "2": (0x8B, 0x9B, 0xB4, 255),  # 暗钢
    "3": (0xBD, 0x6C, 0x4A, 255),  # 深木
    "4": (0xEA, 0xA5, 0x6C, 255),  # 浅木
    "5": (0xE8, 0x45, 0x37, 255),  # 红
    "6": (0x75, 0xE3, 0xFF, 255),  # 青
    "7": (0xD1, 0x76, 0xD0, 255),  # 紫
    ".": (0, 0, 0, 0),
}

BLOCK = 2  # 每个字符放大成 BLOCK x BLOCK 像素块

# 武器 id -> (字符画, 宽, 高)。字符画的行列数必须正好是尺寸的一半。
ART = {
    # 弹雨：紧凑手枪，枪管朝右，木握把在左
    "bullet_volley": ("""
....00000....
0003333100000
0334441111110
0334441222220
0334441111110
0003331000000
...00300.....
....000......
""", 26, 16),
    # 闪电链：电枪，右端两个青色线圈环
    "chain_lightning": ("""
....00000....
0003333066060
0334441661610
0334442661610
0334441661610
0003331066060
...00300.....
....000......
""", 26, 16),
    # 刀阵：横置战斧，右端宽斧刃
    "orbiting_blades": ("""
..........000000
0003333001111110
0334442011222110
0334441222222210
0334442011222110
0003333001111110
...00300..000000
....000.........
""", 32, 16),
    # 雷暴弹雨：电磁步枪，导轨发紫
    "storm_volley": ("""
....000000000000
0003333777777770
0334441111111110
0334442222222210
0334441111111110
0003333777777770
...00300........
....000.........
""", 32, 16),
    # 刀刃弹幕：三片飞刃并排
    "blade_barrage": ("""
......0011111100
0003330011222100
0334440011111100
0334441122222210
0334440011111100
0003330011222100
...0030011111100
....000.00000000
""", 32, 16),
    # 闪电刀阵：等离子长刀，青色刀身
    "lightning_blade": ("""
.........0000000
0003333006666660
0334440066666660
0334444666666660
0334440066666660
0003333006666660
...00300.0000000
....000.........
""", 32, 16),
    # 启示录：末日重炮，炮口红色能量裂纹
    "apocalypse": ("""
.......000000000
0000003311111150
0333333311111550
0334444422222550
0334444422222550
0333333311111550
0000003311111150
...0033000000000
...00300........
....000.........
""", 32, 20),
}

OUT_DIR = os.path.join("assets", "sprites", "weapons")


def paint(art, w, h):
	"""字符画 -> RGBA 图像。行列数不匹配直接炸，别让错图静默落盘。"""
	rows = [r for r in art.splitlines() if r]
	if len(rows) != h // BLOCK:
		raise ValueError("行数 %d != %d" % (len(rows), h // BLOCK))
	im = Image.new("RGBA", (w, h))
	px = im.load()
	for y, row in enumerate(rows):
		if len(row) != w // BLOCK:
			raise ValueError("第 %d 行列数 %d != %d" % (y, len(row), w // BLOCK))
		for x, ch in enumerate(row):
			if ch not in PALETTE:
				raise ValueError("第 %d 行第 %d 列的 '%s' 不在调色板里" % (y, x, ch))
			for dy in range(BLOCK):
				for dx in range(BLOCK):
					px[x * BLOCK + dx, y * BLOCK + dy] = PALETTE[ch]
	return im


def verify(path, w, h):
	"""校验一张挂件是否满足全部格式约束，返回问题列表（空 = 通过）。"""
	bad = []
	im = Image.open(path)
	if im.mode != "RGBA":
		bad.append("mode=%s 不是 RGBA" % im.mode)
		return bad
	if im.size != (w, h):
		bad.append("尺寸 %dx%d != %dx%d" % (im.size[0], im.size[1], w, h))
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

	# 每 BLOCK x BLOCK 必须是同色块，否则等于偷偷提高了分辨率
	for y in range(0, im.height, BLOCK):
		for x in range(0, im.width, BLOCK):
			blk = {px[x + dx, y + dy] for dy in range(BLOCK) for dx in range(BLOCK)}
			if len(blk) != 1:
				bad.append("(%d,%d) 处的 %dx%d 块不同色" % (x, y, BLOCK, BLOCK))
				break
		else:
			continue
		break

	# bbox 必须撑满画布：_make_icon 的枢轴按整张图宽度算，留白会错位
	if im.getbbox() != (0, 0, w, h):
		bad.append("bbox %s 没撑满 %dx%d" % (im.getbbox(), w, h))
	return bad


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--check", action="store_true", help="只校验现有文件，不写盘")
	ap.add_argument("--out", default=OUT_DIR, help="输出目录（默认素材目录）")
	args = ap.parse_args()

	if not args.check:
		os.makedirs(args.out, exist_ok=True)

	failed = 0
	for wid, (art, w, h) in sorted(ART.items()):
		path = os.path.join(args.out, "mount_%s.png" % wid)
		if not args.check:
			paint(art, w, h).save(path)
		elif not os.path.exists(path):
			print("FAIL mount_%s.png 不存在" % wid)
			failed += 1
			continue
		bad = verify(path, w, h)
		if bad:
			failed += 1
			print("FAIL mount_%s.png" % wid)
			for b in bad:
				print("       %s" % b)
		else:
			print("  OK mount_%s.png %dx%d" % (wid, w, h))

	print("%d/%d 通过" % (len(ART) - failed, len(ART)))
	return 1 if failed else 0


if __name__ == "__main__":
	sys.exit(main())
