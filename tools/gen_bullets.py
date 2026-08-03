"""生成 2 张子弹贴图（assets/sprites/bullets/{bullet,enemy_bullet}.png）。

用法（仓库根目录执行，需要 Pillow）：
    python tools/gen_bullets.py            # 写入素材目录并校验
    python tools/gen_bullets.py --check    # 只校验现有文件，不写盘

为什么手画：Kenney Tiny Dungeon 是地牢包，132 张瓦片里没有任何抛射物
（同批下载的 modern-city 只有道路设施，pixel-platformer 是 18×18）。

和 gen_weapon_mounts.py 的关键差异是 BLOCK = 1。挂件是从 16×8 瓦片裁片
2× 放大来的，所以那边一个字符占 2×2。子弹对标 Kenney 瓦片的**原生**
16×16 分辨率，一个字符就是一个像素。

朝向必须烘进 PNG：bullet.gd:setup 和 enemy_projectile.gd:setup 都做
rotation = velocity.angle()，rotation = 0 表示朝 +X。所以字符画一律
**尾焰在左、尖头在右**，并且左右撑满画布（bbox 横向必须是 0..宽度），
否则留白会让子弹看起来比实际短、朝向也读不出来。

上下**不要求**撑满：那条约束只属于挂件（weapon_mounts._make_icon 拿
offset.x = 宽度/2 当枢轴），子弹的 Sprite2D 是居中的，上下留白无害。
反过来还有好处——bullet.tscn 里 CollisionShape2D 半径只有 5.0（10px
直径），而 16×16 × BULLET_SPRITE_SCALE 2.0 = 32px 视觉。把造型画薄
（约 14×7）视觉就降到 28×14 上下，和判定框接近多了，不用动任何常量。

玩家弹和敌弹靠**造型 + 配色**区分，不靠 modulate：细长金黄曳光弹 vs
短粗红紫等离子球。enemy_projectile.gd 里原本那句
modulate = Color(1.0, 0.5, 0.5, 1) 已经删掉，否则会把品红高光压死。
"""
import argparse
import os
import sys

from PIL import Image

# Kenney Tiny Dungeon 调色板中子弹用到的颜色。校验会拒绝这以外的任何颜色。
PALETTE = {
	"0": (0x3F, 0x26, 0x31, 255),  # 轮廓
	"w": (0xBD, 0x6C, 0x4A, 255),  # 暗金
	"W": (0xEA, 0xA5, 0x6C, 255),  # 中金
	"k": (0xF7, 0xC2, 0x82, 255),  # 亮金核（对齐 bullet.tscn 里 Trail 的 (1,.85,.3)）
	"r": (0x76, 0x3B, 0x36, 255),  # 暗红
	"5": (0xE8, 0x45, 0x37, 255),  # 红
	"7": (0xD1, 0x76, 0xD0, 255),  # 品红高光
	".": (0, 0, 0, 0),
}

BLOCK = 1  # 每个字符 = 1 像素（子弹是 Kenney 瓦片原生分辨率，不放大）

# 文件名 -> (字符画, 宽, 高)。字符画的行列数必须正好等于尺寸。
ART = {
	# 玩家：细长金黄曳光弹，尾焰在左、尖头在右
	"bullet": ("""
................
................
................
.....000000000..
...00wwWWWkkk00.
0wwWWWWkkkkkkkk0
...00wwWWWkkk00.
.....000000000..
................
................
................
................
................
................
................
................
""", 16, 16),
	# 敌人：短粗红紫等离子球，尾迹在左、尖刺在右
	"enemy_bullet": ("""
................
................
................
......00000.....
....005555500...
..0055777775500.
0r55777777777750
..0055777775500.
....005555500...
......00000.....
................
................
................
................
................
................
""", 16, 16),
}

OUT_DIR = os.path.join("assets", "sprites", "bullets")


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
	"""校验一颗子弹是否满足全部格式约束，返回问题列表（空 = 通过）。"""
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

	# 横向必须撑满：rotation = velocity.angle() 要求朝向和长度都读得出来
	bbox = im.getbbox()
	if bbox is None:
		bad.append("整张全透明")
	elif bbox[0] != 0 or bbox[2] != w:
		bad.append("bbox %s 横向没撑满 0..%d" % (bbox, w))
	return bad


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--check", action="store_true", help="只校验现有文件，不写盘")
	ap.add_argument("--out", default=OUT_DIR, help="输出目录（默认素材目录）")
	args = ap.parse_args()

	if not args.check:
		os.makedirs(args.out, exist_ok=True)

	failed = 0
	for name, (art, w, h) in sorted(ART.items()):
		path = os.path.join(args.out, "%s.png" % name)
		if not args.check:
			paint(art, w, h).save(path)
		elif not os.path.exists(path):
			print("FAIL %s.png 不存在" % name)
			failed += 1
			continue
		bad = verify(path, w, h)
		if bad:
			failed += 1
			print("FAIL %s.png" % name)
			for b in bad:
				print("       %s" % b)
		else:
			print("  OK %s.png %dx%d bbox=%s" % (name, w, h, Image.open(path).getbbox()))

	print("%d/%d 通过" % (len(ART) - failed, len(ART)))
	return 1 if failed else 0


if __name__ == "__main__":
	sys.exit(main())
