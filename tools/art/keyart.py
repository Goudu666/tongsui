"""主视觉：标题页底图、七章章首横条、长卷首尾的小画、商店宣传图。

底片是游戏里真的画面（tools/shots/keyart.gd 摆拍：同一套底图、光与空气、人），这里只做裁切和排字，
不另画。排字也照孔版的规矩：只用纸、墨、青、梅，大字青梅两块版各错一点位，像套印。

    godot --path client --rendering-driver opengl3 --resolution 2400x1080 \\
          --script res://../tools/shots/keyart.gd -- --out=/tmp/keyart
    python3 tools/art/keyart.py /tmp/keyart [--store OUT_DIR] [--ui SHOTS_DIR]

安装包里的（client/art/keyart/）：title.jpg（2400×1080）、ch1~ch7.jpg（1200×360 横条）。
商店宣传图（--store，1920×1080 五张）不进安装包。--ui 是 tools/shots/run.sh 的截图目录（长卷那张用它）。
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
from riso import COLORS, PAPER, ROOT, font_path  # noqa: E402

OUT = os.path.join(ROOT, "client", "art", "keyart")
INK, QING, MEI = COLORS["ink"], COLORS["qing"], COLORS["mei"]
PURPLE = tuple(int(a * b / 255) for a, b in zip(QING, MEI))
# 章首横条从底片里裁哪一截：2400×1080 底片里以人为中心裁 CH_W×CH_H（再缩成 CH_SIZE），
# CH_FEET 是两个人脚底在底片里的 y、CH_X 是两个人中间的 x；脚放在横条从上往下 80% 的地方
CH_W, CH_H = 1600, 480
CH_FEET = {"ch1": 890, "ch2": 820, "ch3": 890, "ch4": 816, "ch5": 810, "ch6": 816, "ch7": 894}
CH_X = {"ch1": 1185, "ch2": 1150, "ch3": 1185, "ch4": 1170, "ch5": 1170, "ch6": 1170, "ch7": 1250}
CH_SIZE = (1200, 360)


def font(size):
    return ImageFont.truetype(font_path(), size)


def paper(w, h, seed=3):
    """米白纸：一点颗粒、一点纤维。"""
    rng = np.random.default_rng(seed)
    base = np.ones((h, w, 3), np.float32) * np.array(PAPER, np.float32)
    n = rng.normal(0, 3.2, (h, w, 1)).astype(np.float32)
    ys = np.arange(h, dtype=np.float32)[:, None, None]
    fiber = np.sin(ys * 0.35 + np.sin(np.arange(w, dtype=np.float32)[None, :, None] * 0.02) * 6.0) * 1.2
    return Image.fromarray(np.clip(base + n - fiber, 0, 255).astype(np.uint8), "RGB")


def multiply(dst: Image.Image, layer: Image.Image, color, at=(0, 0)):
    """把一张灰度版（白 = 有墨）按某色正片叠底印到 dst 上。"""
    ink = Image.new("RGB", layer.size, color)
    white = Image.new("RGB", layer.size, (255, 255, 255))
    plate = Image.composite(ink, white, layer)
    region = dst.crop((at[0], at[1], at[0] + layer.size[0], at[1] + layer.size[1]))
    from PIL import ImageChops
    dst.paste(ImageChops.multiply(region, plate), at)


def riso_text(img, text, xy, size, color=INK, anchor="la", misreg=(0, 0), second=None, alpha=255):
    """印一行字。second：再用另一块版错开 misreg 叠印一次（青 + 梅 = 深紫的边）。"""
    f = font(size)
    l, t, r, b = f.getbbox(text, anchor=anchor)
    pad = 8
    w, h = r - l + pad * 2, b - t + pad * 2
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text((pad - l, pad - t), text, font=f, fill=alpha, anchor=anchor)
    x, y = int(xy[0] + l - pad), int(xy[1] + t - pad)
    multiply(img, mask, color, (x, y))
    if second is not None:
        multiply(img, mask, second, (x + misreg[0], y + misreg[1]))
    return (r - l, b - t)


def logo(img, cx, cy, r):
    """两个圆：青在左、梅在右，叠住的地方是深紫，「同」「岁」反白在圆里。"""
    s = 4
    W = int(r * 4.4)
    H = int(r * 2.4)
    big = (W * s, H * s)
    ox, oy = cx - W // 2, cy - H // 2
    lc, rc = (W // 2 - r * 0.62, H // 2), (W // 2 + r * 0.62, H // 2)
    for c, color, mis in ((lc, QING, (0, 0)), (rc, MEI, (3, 2))):
        m = Image.new("L", big, 0)
        d = ImageDraw.Draw(m)
        d.ellipse([(c[0] - r) * s, (c[1] - r) * s, (c[0] + r) * s, (c[1] + r) * s], fill=255)
        m = m.resize((W, H), Image.LANCZOS)
        multiply(img, m, color, (ox + mis[0], oy + mis[1]))
    # 墨线圈：手画的，略错开
    m = Image.new("L", big, 0)
    d = ImageDraw.Draw(m)
    for c, dx in ((lc, -4), (rc, 5)):
        d.ellipse([(c[0] - r + dx * 0.3) * s, (c[1] - r - 2) * s, (c[0] + r + dx * 0.3) * s, (c[1] + r - 2) * s], outline=255, width=3 * s)
    multiply(img, m.resize((W, H), Image.LANCZOS), INK, (ox, oy))
    f = font(int(r * 1.0))
    d2 = ImageDraw.Draw(img)
    for c, ch in ((lc, "同"), (rc, "岁")):
        d2.text((ox + c[0] - r * 0.12 * (1 if ch == "同" else -1), oy + c[1]), ch, font=f, fill=(250, 246, 236), anchor="mm")


def crop_marks(img, box, color=INK, L=26, gap=10, w=2):
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = box
    for (x, y, sx, sy) in ((x0, y0, -1, -1), (x1, y0, 1, -1), (x0, y1, -1, 1), (x1, y1, 1, 1)):
        d.line([(x + sx * gap, y), (x + sx * (gap + L), y)], fill=color, width=w)
        d.line([(x, y + sy * gap), (x, y + sy * (gap + L))], fill=color, width=w)


def color_bar(img, x, y, sz=26):
    d = ImageDraw.Draw(img)
    for i, c in enumerate((INK, QING, MEI, PURPLE)):
        d.rectangle([x + i * (sz + 8), y, x + i * (sz + 8) + sz, y + sz], fill=c)


def inset(img, shot: Image.Image, box, shadow=True):
    """把一张画面贴到纸上：底下一道错开的青色块（和界面的 riso_box 一样），四角裁切线。"""
    x0, y0, x1, y1 = box
    if shadow:
        d = ImageDraw.Draw(img)
        d.rectangle([x0 + 10, y0 + 10, x1 + 10, y1 + 10], fill=QING)
    img.paste(shot.resize((x1 - x0, y1 - y0), Image.LANCZOS), (x0, y0))
    d = ImageDraw.Draw(img)
    d.rectangle([x0, y0, x1, y1], outline=INK, width=3)
    crop_marks(img, (x0, y0, x1, y1))


def fade_left(img: Image.Image, upto: float, color=PAPER, strength=0.94):
    """左边渐渐铺上纸色：标志和字放在纸上，画从右边透出来。"""
    w, h = img.size
    xs = np.linspace(0, 1, w, dtype=np.float32)
    a = np.clip((upto - xs) / (upto * 0.55), 0, 1) ** 1.4 * strength
    a = np.repeat(a[None, :], h, 0)
    base = np.asarray(img, np.float32)
    pc = np.asarray(paper(w, h), np.float32)
    out = base * (1 - a[..., None]) + pc * a[..., None]
    return Image.fromarray(out.astype(np.uint8), "RGB")


# ----------------------------------------------------------------------
# 安装包里的
# ----------------------------------------------------------------------

def build_game(src):
    os.makedirs(OUT, exist_ok=True)
    t = Image.open(os.path.join(src, "title.png")).convert("RGB")
    t.save(os.path.join(OUT, "title.jpg"), quality=86, optimize=True)
    for k in range(1, 8):
        n = f"ch{k}"
        im = Image.open(os.path.join(src, n + ".png")).convert("RGB")
        top = min(im.height - CH_H, CH_FEET[n] - int(CH_H * 0.8))
        x0 = max(0, min(im.width - CH_W, CH_X[n] - CH_W // 2))
        strip = im.crop((x0, top, x0 + CH_W, top + CH_H)).resize(CH_SIZE, Image.LANCZOS)
        strip.save(os.path.join(OUT, n + ".jpg"), quality=86, optimize=True)
    print("✓", OUT)


# ----------------------------------------------------------------------
# 商店宣传图：1920×1080 五张
# ----------------------------------------------------------------------
TAG = "同一栋楼，同一年出生，同一生。"


def store(src, ui, out):
    os.makedirs(out, exist_ok=True)
    W, H = 1920, 1080

    # 1 主视觉：傍晚的河边 + 标志
    t = Image.open(os.path.join(src, "title.png")).convert("RGB")
    t = t.crop((t.width - W, 0, t.width, H))  # 人在右边三分之二处，左边留给标志
    img = fade_left(t, 0.5)
    logo(img, 330, 380, 150)
    riso_text(img, TAG, (120, 620), 44, INK)
    riso_text(img, "两个人的人生模拟 · 联机 / 单机", (120, 700), 30, (90, 88, 98))
    color_bar(img, 120, 960)
    img.save(os.path.join(out, "store_1_keyart.jpg"), quality=90)

    # 2 一辈子：四个年纪四条横条
    img = paper(W, H, 5)
    riso_text(img, "从三岁到七十岁", (120, 96), 76, QING, misreg=(4, 3), second=MEI)
    riso_text(img, "七章，一章一幕。楼下那条街跟着你们一起老。", (124, 214), 34, INK)
    rows = [("ch1", "4 岁", "对门"), ("ch3", "15 岁", "过桥"), ("ch4", "24 岁", "远近"), ("ch7", "70 岁", "河边")]
    y, bw, bh0 = 266, 1200, 192
    for n, age, title in rows:
        # 从底片整宽裁一溜（大人有两百多像素高，章首横条那么近放不下）
        im = Image.open(os.path.join(src, n + ".png")).convert("RGB")
        bh = im.width * bh0 // bw
        top = min(im.height - bh, CH_FEET[n] + 20 - bh)
        band = im.crop((0, top, im.width, top + bh))
        inset(img, band, (560, y, 560 + bw, y + bh0), shadow=False)
        riso_text(img, age, (500, y + 54), 52, INK, anchor="ra")
        riso_text(img, title, (500, y + 120), 30, (110, 108, 118), anchor="ra")
        y += bh0 + 10
    img.save(os.path.join(out, "store_2_lifetime.jpg"), quality=90)

    # 3 下雨的晚上
    r = Image.open(os.path.join(src, "store_rain.png")).convert("RGB").crop((240, 0, 2160, 1080))
    img = r.copy()
    band = Image.new("L", (W, 260), 0)
    ImageDraw.Draw(band).rectangle([0, 0, W, 260], fill=150)
    band = band.filter(ImageFilter.GaussianBlur(40))
    dark = Image.new("RGB", (W, 260), (24, 26, 44))
    img.paste(Image.composite(dark, img.crop((0, 0, W, 260)), band), (0, 0))
    d = ImageDraw.Draw(img)
    d.text((120, 92), "下雨的晚上，对门的灯还亮着", font=font(64), fill=(244, 238, 225))
    d.text((124, 184), "一天五段，按一下做一回；天会黑，季节会换，灯一盏盏亮起来。", font=font(32), fill=(220, 214, 200))
    img.save(os.path.join(out, "store_3_night.jpg"), quality=90)

    # 4 人生长卷（游戏里的截图贴在纸上）
    img = paper(W, H, 7)
    riso_text(img, "两条线并成一条的地方", (120, 96), 72, QING, misreg=(4, 3), second=MEI)
    riso_text(img, "是你们走了同一条路。每道关口各选各的，一辈子画成一张长卷。", (124, 206), 34, INK)
    sp = os.path.join(ui, "46_scroll_head.png") if ui else ""
    if sp and os.path.exists(sp):
        s = Image.open(sp).convert("RGB").crop((0, 0, 1920, 1000))
        inset(img, s, (270, 290, 270 + 1380, 290 + 719))
    img.save(os.path.join(out, "store_4_scroll.jpg"), quality=90)

    # 5 老了，还是对门
    p = Image.open(os.path.join(src, "store_park.png")).convert("RGB").crop((240, 0, 2160, 1080))
    img = fade_left(p, 0.36, strength=0.82)
    riso_text(img, "老了，", (120, 300), 92, INK)
    riso_text(img, "还是对门。", (120, 420), 92, QING, misreg=(4, 3), second=MEI)
    riso_text(img, "一辈子的远近，都记在两个人身上。", (124, 580), 34, INK)
    logo(img, 1760, 120, 54)
    img.save(os.path.join(out, "store_5_old.jpg"), quality=90)
    print("✓", out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", help="keyart.gd 拍的底片目录")
    ap.add_argument("--store", help="商店宣传图输出目录（不给就不出）")
    ap.add_argument("--ui", help="tools/shots/run.sh 的截图目录（长卷那张）")
    a = ap.parse_args()
    build_game(a.src)
    if a.store:
        store(a.src, a.ui, a.store)


if __name__ == "__main__":
    main()
