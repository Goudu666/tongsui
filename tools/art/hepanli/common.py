"""河畔里地图的公共约定：布局、可走区域、锚点、常用道具。

视角：俯视略带斜角（像手绘街区地图）。我们从南边的上方看下去：
  - 物体的"顶面"按平面图画，朝南的"正面"在顶面下方露出一截（高度 × 0.5）。
  - 光从左上来，影子落在右下：墨 0.14~0.2 网点。
  - 红砖楼是剖面：楼顶揭开一半，能看见三楼两家人的屋里。

分层：
  ctx.g  地面层（不透明，角色在它上面走）
  ctx.o  上层（树冠、电线、晾的床单、桥的钢架……引擎里用"正片叠底"盖在角色上面）
  ctx.walk  可走区域
  ctx.anchors  给引擎的锚点（环境动画、鸽子、风筝、热气……）
"""
from __future__ import annotations

import json
import math
import os
import random

from PIL import Image, ImageDraw

from riso import ROOT, Sheet, circle_pts, ellipse_pts, rect_pts  # noqa: F401

CONTENT = json.load(open(os.path.join(ROOT, "client", "data", "content.json"), encoding="utf-8"))
MAP = CONTENT["map"]
W, H = MAP["size"]
ZONES = {z["id"]: z for z in MAP["zones"]}
SPOTS = {s["id"]: s for s in MAP["spots"]}


def zrect(zid):
    """zone 的 (x, y, w, h)。"""
    return tuple(ZONES[zid]["rect"])


def spot(sid):
    return tuple(SPOTS[sid]["at"])


# ----------------------------------------------------------------------
# 可走区域：5 像素一格的位图，按顺序 add / block
# ----------------------------------------------------------------------

class WalkMask:
    CELL = 5

    def __init__(self):
        self.img = Image.new("L", (W // self.CELL, H // self.CELL), 0)
        self.d = ImageDraw.Draw(self.img)

    def _p(self, pts):
        return [(x / self.CELL, y / self.CELL) for x, y in pts]

    def add_rect(self, x, y, w, h):
        self.d.rectangle([x / self.CELL, y / self.CELL, (x + w) / self.CELL - 1, (y + h) / self.CELL - 1], fill=255)

    def block_rect(self, x, y, w, h):
        self.d.rectangle([x / self.CELL, y / self.CELL, (x + w) / self.CELL - 1, (y + h) / self.CELL - 1], fill=0)

    def add_poly(self, pts):
        self.d.polygon(self._p(pts), fill=255)

    def block_poly(self, pts):
        self.d.polygon(self._p(pts), fill=0)

    def block_circle(self, cx, cy, r):
        self.d.ellipse([(cx - r) / self.CELL, (cy - r) / self.CELL, (cx + r) / self.CELL, (cy + r) / self.CELL], fill=0)

    def add_circle(self, cx, cy, r):
        self.d.ellipse([(cx - r) / self.CELL, (cy - r) / self.CELL, (cx + r) / self.CELL, (cy + r) / self.CELL], fill=255)

    def ok(self, x, y):
        return self.img.getpixel((int(x // self.CELL), int(y // self.CELL))) > 127


class Ctx:
    def __init__(self, g: Sheet, o: Sheet, walk: WalkMask, anchors: dict):
        self.g, self.o, self.walk, self.anchors = g, o, walk, anchors
        self.rnd = random.Random(2026)

    def anchor(self, kind, x, y, **extra):
        """记一个锚点给引擎，比如 anchor("steam", 1600, 420)。"""
        self.anchors.setdefault(kind, []).append({"x": round(x, 1), "y": round(y, 1), **extra})


# ----------------------------------------------------------------------
# 常用道具（大家共用，保证风格一致）
# ----------------------------------------------------------------------

def shadow(g: Sheet, pts, density=0.16):
    g.pen("ink", density).fill(pts)


def tree(ctx: Ctx, x, y, r=70, kind="huai", seed=0):
    """一棵树：地面层画树干和落在地上的影子，上层画树冠（角色从树下走过）。
    kind: huai 国槐（团团的）/ willow 垂柳（垂下来的线）"""
    g, o = ctx.g, ctx.o
    rnd = random.Random(seed or int(x * 7 + y * 13))
    # 地上的影子（树冠投影，往右下偏）
    shadow(g, ellipse_pts(x + r * 0.35, y + r * 0.25, r * 0.95, r * 0.55), 0.13)
    # 树干 + 树池
    g.ink.rect(x - 22, y - 8, 44, 30, lw=2.0)
    g.ink.line([(x - 5, y + 6), (x - 4, y - 40)], 6)
    g.ink.line([(x + 5, y + 6), (x + 4, y - 40)], 2.5)
    # 树冠（上层）
    cy = y - r * 0.9
    if kind == "willow":
        o.pen("qing", 0.38).fill(ellipse_pts(x, cy, r * 0.9, r * 0.55))
        o.qing.ellipse(x, cy, r * 0.9, r * 0.55, lw=2.2)
        for i in range(26):
            a = rnd.uniform(-math.pi, 0)
            sx = x + math.cos(a) * r * 0.8 * rnd.uniform(0.3, 1.0)
            sy = cy + math.sin(a) * r * 0.4
            L = rnd.uniform(r * 0.6, r * 1.3)
            o.qing.line([(sx, sy), (sx + rnd.uniform(-8, 8), sy + L * 0.5), (sx + rnd.uniform(-14, 14), sy + L)], 1.8, amp=1.5)
    else:
        blobs = [(x + rnd.uniform(-r * 0.45, r * 0.45), cy + rnd.uniform(-r * 0.3, r * 0.35), r * rnd.uniform(0.45, 0.62)) for _ in range(6)]
        for bx, by, br in blobs:
            o.pen("qing", 0.55).fill(circle_pts(bx, by, br))
        for bx, by, br in blobs:
            o.qing.arc(bx, by, br, math.pi * 0.85, math.pi * 1.95, lw=2.4)
        # 一点点墨色暗部，叠出深青
        o.pen("ink", 0.22).fill(ellipse_pts(x + r * 0.25, cy + r * 0.3, r * 0.5, r * 0.28))
        for _ in range(10):
            lx, ly = x + rnd.uniform(-r * 0.6, r * 0.6), cy + rnd.uniform(-r * 0.5, r * 0.5)
            o.ink.arc(lx, ly, 6, 0.2, 2.6, lw=1.6)
    ctx.walk.block_circle(x, y + 4, 20)


def bicycle(g: Sheet, x, y, facing=1, color="ink", scale=1.0):
    """一辆二八自行车（侧面），x, y 是两轮之间着地的中点。"""
    s = scale
    r = 17 * s
    bx, fx = x - 28 * s * facing, x + 28 * s * facing
    shadow(g, ellipse_pts(x + 6, y + 4, 52 * s, 8 * s), 0.14)
    for wx in (bx, fx):
        g.ink.circle(wx, y - r, r, lw=2.2)
        g.ink.dot(wx, y - r, 2.2)
    pen = g.pen(color)
    seat = (x - 10 * s * facing, y - 44 * s)
    bar = (x + 18 * s * facing, y - 46 * s)
    crank = (x, y - r)
    pen.line([(bx, y - r), seat, crank, (bx, y - r)], 2.6)
    pen.line([seat, bar, crank], 2.6)
    pen.line([bar, (fx, y - r)], 2.6)
    g.ink.line([(seat[0] - 8 * s, seat[1] - 3 * s), (seat[0] + 6 * s * facing, seat[1] - 3 * s)], 4)
    g.ink.line([(bar[0] - 2 * s * facing, bar[1] - 6 * s), (bar[0] + 8 * s * facing, bar[1] - 8 * s)], 2.6)
    # 车筐
    g.ink.rect(fx - 6 * s if facing > 0 else fx - 10 * s, y - 60 * s, 16 * s, 10 * s, lw=1.6)


def stool(g: Sheet, x, y, color="ink", r=11):
    """小马扎/小板凳（俯视略斜）。"""
    g.pen(color, 0.5).fill(ellipse_pts(x, y, r, r * 0.6))
    g.ink.ellipse(x, y, r, r * 0.6, lw=2)
    g.ink.line([(x - r * 0.7, y + 2), (x - r * 0.8, y + r * 0.9)], 2)
    g.ink.line([(x + r * 0.7, y + 2), (x + r * 0.8, y + r * 0.9)], 2)


def pole(ctx: Ctx, x, y, h=150):
    """水泥电线杆：地面层画杆子底座和影子，上层画杆身与横担。返回横担两端（给电线用）。"""
    g, o = ctx.g, ctx.o
    shadow(ctx.g, [(x, y), (x + h * 0.55, y + h * 0.18), (x + h * 0.55 + 6, y + h * 0.18 + 5), (x + 6, y + 5)], 0.12)
    g.ink.circle(x, y, 7, lw=2, fill=True)
    o.ink.line([(x, y), (x, y - h)], 5)
    o.ink.line([(x - 26, y - h + 14), (x + 26, y - h + 14)], 3)
    ctx.walk.block_circle(x, y, 8)
    return (x - 24, y - h + 14), (x + 24, y - h + 14)


def wire(o: Sheet, a, b, sag=24, lw=1.4):
    """两点之间下垂的电线。"""
    pts = []
    for i in range(21):
        t = i / 20
        pts.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t + sag * 4 * t * (1 - t)))
    o.ink.line(pts, lw, amp=0.2)


def sign(g: Sheet, x, y, text, color="mei", size=26, vertical=False, pad=10):
    """招牌：一块实地色牌子 + 挖白的字（孔版里最好看的就是反白字）。"""
    n = len(text)
    if vertical:
        w, h = size * 1.5, size * 1.08 * n + pad * 2
    else:
        w, h = size * 1.05 * n + pad * 2, size * 1.5
    pts = rect_pts(x - w / 2, y - h / 2, w, h)
    g.clear(pts)
    g.pen(color).fill(pts)
    g.ink.rect(x - w / 2, y - h / 2, w, h, lw=2.0)
    # 反白字：在色版上挖掉字形
    _knockout_text(g, color, text, x, y, size, vertical)


def label(g: Sheet, x, y, text, size=24, color="ink"):
    """地图上的地名：小字，两侧一点短横，像旧地图的注记。"""
    g.pen(color).text(text, x, y, size)
    w = size * 1.02 * len(text) / 2 + 10
    g.pen(color).line([(x - w - 18, y), (x - w, y)], 1.6, amp=0)
    g.pen(color).line([(x + w, y), (x + w + 18, y)], 1.6, amp=0)


def _knockout_text(g: Sheet, color, text, x, y, size, vertical, layer="solid"):
    import numpy as np
    from PIL import ImageFont

    from riso import font_path

    S = g.scale
    f = ImageFont.truetype(font_path(), int(size * S))
    if vertical:
        step = size * S * 1.08
        Wd, Hd = int(size * S * 1.4), int(step * len(text) + 4)
        img = Image.new("L", (Wd, Hd), 0)
        d = ImageDraw.Draw(img)
        for i, ch in enumerate(text):
            d.text((Wd / 2, step * (i + 0.5)), ch, font=f, fill=255, anchor="mm")
    else:
        bb = f.getbbox(text, anchor="mm")
        Wd, Hd = bb[2] - bb[0] + 8, bb[3] - bb[1] + 8
        img = Image.new("L", (Wd, Hd), 0)
        d = ImageDraw.Draw(img)
        d.text((Wd / 2, Hd / 2), text, font=f, fill=255, anchor="mm")
    surf = g._surfaces[(color, layer)]
    surf.flush()
    buf = np.ndarray((g.H, surf.get_stride()), dtype=np.uint8, buffer=surf.get_data())
    ox = int(round((x - g.origin[0]) * S - Wd / 2))
    oy = int(round((y - g.origin[1]) * S - Hd / 2))
    a = np.asarray(img, dtype=np.float32) / 255.0
    x0, y0 = max(0, ox), max(0, oy)
    x1, y1 = min(g.W, ox + Wd), min(g.H, oy + Hd)
    if x1 <= x0 or y1 <= y0:
        return
    sub = buf[y0:y1, x0:x1].astype(np.float32) * (1.0 - a[y0 - oy : y1 - oy, x0 - ox : x1 - ox])
    buf[y0:y1, x0:x1] = sub.astype(np.uint8)
    surf.mark_dirty()
