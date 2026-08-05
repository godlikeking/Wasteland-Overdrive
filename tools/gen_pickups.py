"""生成 6 张道具贴图（assets/sprites/pickups/*.png）。

用法（仓库根目录执行，需要 Pillow）：
    python tools/gen_pickups.py            # 写入素材目录并校验
    python tools/gen_pickups.py --check    # 只校验现有文件，不写盘

画法和 gen_weapon_mounts.py 一致：手写半分辨率字符画，一个字符一格，
落盘时做 2x 最近邻放大，保持和 Kenney Tiny Dungeon 素材同样的像素颗粒度。

和挂件的唯一区别是**不要求 bbox 撑满画布**：挂件的枢轴按整张图宽度算，
留白会把握把推离挂点；道具是居中 Sprite2D，四周留一圈透明反而更好看。
"""
import argparse
import os
import sys

from PIL import Image

# Kenney Tiny Dungeon 调色板中道具用到的颜色。校验会拒绝这以外的任何颜色。
PALETTE = {
	"0": (0x3F, 0x26, 0x31, 255),  # 轮廓
	"1": (0xC0, 0xCB, 0xDC, 255),  # 亮钢 / 白
	"2": (0x8B, 0x9B, 0xB4, 255),  # 暗钢
	"3": (0xBD, 0x6C, 0x4A, 255),  # 深木
	"4": (0xEA, 0xA5, 0x6C, 255),  # 浅木
	"5": (0xE8, 0x45, 0x37, 255),  # 红
	"6": (0x75, 0xE3, 0xFF, 255),  # 青
	"8": (0xF9, 0xC0, 0x4C, 255),  # 金
	"9": (0x99, 0x24, 0x1C, 255),  # 暗红
	"a": (0x4D, 0x9B, 0xE6, 255),  # 蓝
	"c": (0x30, 0x36, 0x4A, 255),  # 深黑蓝（炸弹弹体）
	".": (0, 0, 0, 0),
}

BLOCK = 2  # 每个字符放大成 BLOCK x BLOCK 像素块
SIZE = 16  # 所有道具都是 16x16，和 xp_gem 一样 scale 2.0 使用

# 道具文件名 -> 字符画。行列数必须都正好是 SIZE // BLOCK。
ART = {
	# 补血：红心，右下方用暗红压一层体积
	"heal": """
.00..00.
05500550
05555550
05555990
00559990
.055990.
..0990..
...00...
""",
	# 武器：木箱 + 金色封条
	"weapon": """
00000000
03444430
04888840
04888840
04344340
04433440
03444430
00000000
""",
	# 炸弹：黑色弹体 + 金色引信火花
	"bomb": """
.....080
....080.
..0000..
.0c22c0.
0cc22cc0
0cccccc0
.0cccc0.
..0000..
""",
	# 时间暂停：沙漏，青色的沙
	"time_stop": """
00000000
.066660.
..0660..
...00...
...00...
..0660..
.066660.
00000000
""",
	# 护盾：蓝盾 + 白十字
	"shield": """
00000000
0aa11aa0
0aa11aa0
01111110
0aa11aa0
.0a11a0.
..0aa0..
...00...
""",
	# 磁石：马蹄形磁铁，开口朝下，两极是亮钢；右臂用暗红压体积（和补血一致的打光方向）
	"magnet": """
.000000.
05555550
05999950
050..090
050..090
050..090
010..010
000..000
""",
}

OUT_DIR = os.path.join("assets", "sprites", "pickups")


def paint(art):
	"""字符画 -> RGBA 图像。行列数不匹配直接炸，别让错图静默落盘。"""
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
	"""校验一张道具图是否满足全部格式约束，返回问题列表（空 = 通过）。"""
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

	# 全透明图 = 画错了；居中留白是允许的，所以不要求 bbox 撑满
	if im.getbbox() is None:
		bad.append("整张图全透明")
	return bad


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--check", action="store_true", help="只校验现有文件，不写盘")
	ap.add_argument("--out", default=OUT_DIR, help="输出目录（默认素材目录）")
	args = ap.parse_args()

	if not args.check:
		os.makedirs(args.out, exist_ok=True)

	failed = 0
	for name, art in sorted(ART.items()):
		path = os.path.join(args.out, "%s.png" % name)
		if not args.check:
			paint(art).save(path)
		elif not os.path.exists(path):
			print("FAIL %s.png 不存在" % name)
			failed += 1
			continue
		bad = verify(path)
		if bad:
			failed += 1
			print("FAIL %s.png" % name)
			for b in bad:
				print("       %s" % b)
		else:
			print("  OK %s.png %dx%d" % (name, SIZE, SIZE))

	print("%d/%d 通过" % (len(ART) - failed, len(ART)))
	return 1 if failed else 0


if __name__ == "__main__":
	sys.exit(main())
