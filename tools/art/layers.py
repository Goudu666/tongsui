#!/usr/bin/env python3
"""分层：底图后面的远景、中景，和一年四季的树。python3 tools/art/layers.py [far mid trees]

  远景 client/art/layers/far_<年代>.png   远处的城：楼的剪影，烟囱、塔吊、高楼随年代换（五个年代 = 五个人生阶段）
  中景 client/art/layers/mid_<年代>.png   隔一两条街的屋顶：水箱、天线、太阳能热水器、空调外机、晾的衣裳
       每张还有一张同名的 _lit.png（灰度）：夜里哪些窗亮，引擎按它点灯、让灯一闪一闪
  树   client/art/layers/tree_<种>_<季>.png 槐树 / 柳树 / 小树 × 春夏秋冬，脚底在图的底边正中

远景、中景横着能无缝接（宽 STRIP），引擎按视差慢慢挪、平铺；底边就是楼脚。
颜色只用纸、墨、青、梅四样：远的淡、近的浓，天色由引擎（shaders/sky.gdshader）画。
"""
from __future__ import annotations

import argparse
import math
import os
import random
import sys

import cairo
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from riso import ROOT, Sheet, circle_pts, ellipse_pts, rect_pts  # noqa: E402

OUT = os.path.join(ROOT, "client", "art", "layers")
STRIP = 2048
ERAS = ("child", "teen", "young", "middle", "old")
SEASONS = ("spring", "summer", "autumn", "winter")


# ----------------------------------------------------------------------
# 小工具
# ----------------------------------------------------------------------

def paper(g, pts):
    """记进纸版：这块是实的（挡住后面的）。"""
    ctx = g.plates["paper"]["solid"]
    ctx.save()
    ctx.new_path()
    ctx.move_to(*pts[0])
    for p in pts[1:]:
        ctx.line_to(*p)
    ctx.close_path()
    ctx.set_source_rgba(0, 0, 0, 1)
    ctx.fill()
    ctx.restore()


def block(g, pts, color, d, line=None):
    """一块实的面：挖空、纸、上色，要的话描一圈。"""
    g.clear(pts)
    paper(g, pts)
    g.pen(color, d).fill(pts)
    if line:
        g.pen(line[0], line[1] if len(line) > 1 else None).poly(pts, w=line[2] if len(line) > 2 else 1.6, amp=0.3)


def union(g, color, d, polys):
    """几块面合成一块再铺：重叠的地方不加深。"""
    ctx = g.plates[color]["tint" if d is not None else "solid"]
    ctx.save()
    ctx.set_fill_rule(cairo.FILL_RULE_WINDING)
    ctx.new_path()
    for pts in polys:
        ctx.move_to(*pts[0])
        for p in pts[1:]:
            ctx.line_to(*p)
        ctx.close_path()
    ctx.set_source_rgba(0, 0, 0, 1.0 if d is None else d)
    ctx.fill()
    ctx.restore()


class Lit:
    """夜里亮的窗：一张灰度图，和印张一样大。"""

    def __init__(self, w, h, scale):
        self.scale = scale
        self.a = np.zeros((int(h * scale), int(w * scale)), dtype=np.float32)

    def rect(self, x, y, w, h, v=1.0):
        s = self.scale
        H, W = self.a.shape
        for off in (-STRIP, 0, STRIP):
            x0, x1 = int((x + off) * s), int((x + off + w) * s + 0.999)
            y0, y1 = int(y * s), int((y + h) * s + 0.999)
            x0, x1 = max(0, x0), min(W, x1)
            y0, y1 = max(0, y0), min(H, y1)
            if x1 > x0 and y1 > y0:
                self.a[y0:y1, x0:x1] = np.maximum(self.a[y0:y1, x0:x1], v)

    def save(self, path):
        Image.fromarray((np.clip(self.a, 0, 1) * 255).astype(np.uint8), "L").save(path, optimize=True)


def wrap(fn, *args, **kw):
    """横着无缝：同一样东西在左右各再画一遍。"""
    for off in (-STRIP, 0, STRIP):
        fn(off, *args, **kw)


def save_rgba(g: Sheet, path, colors=64):
    rgb = g.composite(True, True)
    a = np.clip(g.alpha() * 255.0 + 0.5, 0, 255).astype(np.uint8)
    img = Image.fromarray(np.dstack([rgb, a]), "RGBA")
    img.quantize(colors=colors, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).save(path, optimize=True)


# ----------------------------------------------------------------------
# 远景：远处的城
# ----------------------------------------------------------------------

FAR_H = 620  # 远景条有多高（世界像素）；底边是楼脚


def far_specs(era: int, seed=5):
    """先把这条天际线上有什么定下来（定了再画三遍，左右接得上）。"""
    rnd = random.Random(seed + era * 101)
    items = []
    # 底下一层矮楼：每个年代都有，越往后越密、越高一点
    x = 0.0
    while x < STRIP:
        w = rnd.uniform(60, 150)
        h = rnd.uniform(50, 150) + era * 14
        items.append(("low", x, w, h, rnd.random()))
        x += w + rnd.uniform(-14, 18)
    # 高楼：九十年代几乎没有，后来一年比一年多
    n_tall = [1, 6, 12, 17, 17][era]
    for _ in range(n_tall):
        w = rnd.uniform(56, 110)
        h = rnd.uniform(200, 300) + era * rnd.uniform(25, 55)
        items.append(("tall", rnd.uniform(0, STRIP), w, min(h, FAR_H - 40), rnd.random()))
    # 烟囱和冒烟：小时候到处是，后来一根一根拆掉
    for _ in range([4, 2, 1, 0, 0][era]):
        items.append(("chimney", rnd.uniform(0, STRIP), 26, rnd.uniform(240, 340), rnd.random()))
    if era <= 1:
        items.append(("gas", rnd.uniform(0, STRIP), 150, 120, 0))   # 储气罐
        items.append(("water", rnd.uniform(0, STRIP), 60, 210, 0))  # 水塔
    # 塔吊：盖楼最凶的那几年
    for _ in range([1, 4, 3, 1, 0][era]):
        items.append(("crane", rnd.uniform(0, STRIP), 0, rnd.uniform(300, 420), rnd.random()))
    if era >= 2:
        items.append(("mast", rnd.uniform(0, STRIP), 0, rnd.uniform(470, 540), 0))  # 一根细长的广播塔，不是哪座真塔
    items.sort(key=lambda it: (0 if it[0] in ("tall", "crane", "mast", "chimney") else 1, it[3] if it[0] == "low" else -it[3]))
    return items


def draw_far(era: int, scale=1.0):
    g = Sheet(STRIP, FAR_H, scale, seed=40 + era)
    lit = Lit(STRIP, FAR_H, scale)
    base = FAR_H
    col, d = "qing", 0.2 + era * 0.01
    specs = far_specs(era)

    def item(off, kind, x, w, h, r):
        x += off
        if kind == "low":
            pts = rect_pts(x, base - h, w, h + 2)
            block(g, pts, col, d * 0.85)
            if r < 0.35:
                block(g, [(x + 8, base - h), (x + w / 2, base - h - 22), (x + w - 8, base - h)], col, d * 0.85)
            for wy in range(int(base - h + 14), int(base - 10), 22):
                for wx in range(int(x + 9), int(x + w - 12), 18):
                    hsh = (wx * 73856093 ^ wy * 19349663 ^ era * 977) & 0xFFFF
                    if hsh % 10 < 5:
                        g.pen(col, d * 1.9).fill(rect_pts(wx, wy, 7, 9))
                        if hsh % 10 < 2:
                            lit.rect(wx - off, wy, 7, 9, 0.6 + 0.4 * (hsh % 7) / 6)
            if era == 0 and r > 0.7:
                # 楼顶的电视天线
                g.pen("ink", 0.25).line([(x + w * 0.6, base - h), (x + w * 0.6, base - h - 30)], 1.4, amp=0)
                g.pen("ink", 0.25).line([(x + w * 0.6 - 12, base - h - 24), (x + w * 0.6 + 12, base - h - 24)], 1.4, amp=0)
        elif kind == "tall":
            pts = rect_pts(x, base - h, w, h + 2)
            block(g, pts, col, d * 1.15)
            crown = int(r * 4)
            if crown == 0:
                block(g, [(x + 4, base - h), (x + w / 2, base - h - 34), (x + w - 4, base - h)], col, d * 1.15)
            elif crown == 1:
                block(g, rect_pts(x + w * 0.25, base - h - 26, w * 0.5, 26), col, d * 1.15)
            elif crown == 2 and era >= 2:
                g.pen(col, d * 2.0).line([(x + w / 2, base - h), (x + w / 2, base - h - 60)], 2.0, amp=0)
            # 玻璃幕墙：几道竖线；老一点的高楼是一格一格的窗
            if era >= 2 and r > 0.4:
                for k in range(1, 5):
                    g.pen(col, d * 2.0).fill(rect_pts(x + w * k / 5 - 1, base - h + 8, 2, h - 10))
                for wy in range(int(base - h + 20), int(base - 12), 30):
                    if ((int(x) * 31 + wy * 17) & 7) < 3:
                        lit.rect(x - off + 4, wy, w - 8, 3, 0.5)
            else:
                for wy in range(int(base - h + 14), int(base - 10), 20):
                    for wx in range(int(x + 8), int(x + w - 10), 14):
                        hsh = (wx * 92837111 ^ wy * 689287499 ^ era) & 0xFFFF
                        if hsh % 10 < 6:
                            g.pen(col, d * 2.0).fill(rect_pts(wx, wy, 6, 8))
                            if hsh % 10 < 2:
                                lit.rect(wx - off, wy, 6, 8, 0.55 + 0.45 * (hsh % 5) / 4)
            # 楼顶的红灯（航空障碍灯）
            lit.rect(x - off + w / 2 - 2, base - h - 6, 4, 4, 1.0)
        elif kind == "chimney":
            block(g, [(x - 14, base), (x - 9, base - h), (x + 9, base - h), (x + 14, base)], col, d * 1.6)
            for k in (0.25, 0.32):
                g.clear(rect_pts(x - 11, base - h * (1 - k), 22, 6), colors=[col])
            for k in range(4):
                g.pen("ink", 0.07 + 0.01 * k).fill(ellipse_pts(x + 24 + k * 36, base - h - 18 - k * 15, 20 + k * 10, 11 + k * 4))
            lit.rect(x - off - 2, base - h - 4, 4, 4, 1.0)
        elif kind == "gas":
            pts = ellipse_pts(x, base - h / 2, w / 2, h / 2) if False else rect_pts(x - w / 2, base - h, w, h)
            block(g, [(x - w / 2, base), (x - w / 2, base - h * 0.75), (x - w * 0.35, base - h), (x + w * 0.35, base - h), (x + w / 2, base - h * 0.75), (x + w / 2, base)], col, d * 1.2)
            for k in range(1, 4):
                g.pen(col, d * 2.2).fill(rect_pts(x - w / 2, base - h * k / 4, w, 2))
        elif kind == "water":
            block(g, rect_pts(x - 8, base - h * 0.7, 16, h * 0.7), col, d * 1.3)
            block(g, [(x - w / 2, base - h * 0.7), (x - w / 2 + 6, base - h), (x + w / 2 - 6, base - h), (x + w / 2, base - h * 0.7)], col, d * 1.5)
        elif kind == "crane":
            c = g.pen("ink", 0.22)
            c.line([(x, base), (x, base - h)], 3.0, amp=0)
            c.line([(x - 70, base - h + 10), (x + 190, base - h + 10)], 2.4, amp=0)
            c.line([(x, base - h - 30), (x - 70, base - h + 10)], 1.2, amp=0)
            c.line([(x, base - h - 30), (x + 190, base - h + 10)], 1.2, amp=0)
            hx = x + 60 + r * 110
            c.line([(hx, base - h + 10), (hx, base - h + 90 + r * 60)], 1.0, amp=0)
            g.pen("ink", 0.3).fill(rect_pts(x - 64, base - h + 10, 22, 14))
            lit.rect(x - off - 2, base - h - 32, 4, 4, 1.0)
        elif kind == "mast":
            c = g.pen(col, d * 2.2)
            c.line([(x, base), (x, base - h)], 3.0, amp=0)
            block(g, ellipse_pts(x, base - h * 0.72, 22, 9), col, d * 2.0)
            lit.rect(x - off - 2, base - h - 2, 4, 4, 1.0)
            lit.rect(x - off - 10, base - h * 0.72 - 2, 20, 3, 0.8)

    for it in specs:
        wrap(item, *it)
    # 最底下一抹地气：远处的树和低矮的房子连成一片
    for off in (-STRIP, 0, STRIP):
        rnd = random.Random(7 + era)
        xx = 0.0
        while xx < STRIP:
            rr = rnd.uniform(16, 34)
            block(g, circle_pts(xx + off, base - rr * 0.3, rr), "qing", 0.26)
            xx += rr * 1.3
    return g, lit


# ----------------------------------------------------------------------
# 门外的远景：海边、乡下各一条，不随年代变（那是一年夏天去过的地方，不是天天看着长高的城）
# 引擎：scene_art.gd 的 LAYOUT 里 far_kind 指到 far_<kind>.png
# ----------------------------------------------------------------------

PLACE_H = 300
PLACES = ("sea", "village")


def draw_place(kind: str, scale=1.0):
    g = Sheet(STRIP, PLACE_H, scale, seed=150 + PLACES.index(kind))
    lit = Lit(STRIP, PLACE_H, scale)
    base = PLACE_H
    rnd = random.Random(17 + PLACES.index(kind))
    if kind == "sea":
        # 岬角：从海里慢慢拱起来、到头一道陡崖，崖顶一座白灯塔
        def cape(off):
            x0, x1 = 120 + off, 980 + off
            pts = [(x0, base)]
            for i in range(1, 30):
                t = i / 30
                h = 170 * (min(1.0, t * 5.0) ** 0.6) * (1 - t) ** 0.55 + 8 * math.sin(t * 23)
                pts.append((x0 + (x1 - x0) * t, base - h))
            pts.append((x1, base))
            block(g, pts, "qing", 0.36)
            g.pen("qing", 0.55).line(pts[:-1], 1.6, amp=0.4)
            # 崖面：几道竖的排线；坡上一层黑松
            for k in range(8):
                xx = x0 + 6 + k * 9
                g.pen("ink", 0.25).line([(xx, base - 10), (xx + 6, base - 120 + k * 8)], 1.2, amp=0.3)
            for k in range(26):
                t = 0.18 + 0.6 * k / 26
                tx = x0 + (x1 - x0) * t
                h = 170 * (min(1.0, t * 5.0) ** 0.6) * (1 - t) ** 0.55 + 8 * math.sin(t * 23)
                block(g, circle_pts(tx, base - h + 6, 9 + (k * 7) % 6), "qing", 0.6)
            t = 0.2
            lx = x0 + (x1 - x0) * t
            ly = base - (170 * (min(1.0, t * 5.0) ** 0.6) * (1 - t) ** 0.55 + 8 * math.sin(t * 23)) + 8
            block(g, [(lx - 10, ly), (lx - 7, ly - 46), (lx + 7, ly - 46), (lx + 10, ly)], "ink", 0.04, ("ink", None, 1.4))
            block(g, rect_pts(lx - 9, ly - 58, 18, 12), "mei", 0.5, ("ink", None, 1.2))
            block(g, [(lx - 11, ly - 58), (lx, ly - 70), (lx + 11, ly - 58)], "ink", 0.6)
            for k in range(2):
                g.pen("mei", 0.6).fill(rect_pts(lx - 10, ly - 32 + k * 14, 20, 4))
            lit.rect(lx - off - 9, ly - 58, 18, 12, 1.0)
        wrap(cape)

        # 远处一个小岛
        def island(off):
            x0 = 1560 + off
            pts = [(x0, base)] + [(x0 + 200 * i / 12, base - 34 * math.sin(math.pi * i / 12) ** 0.7) for i in range(1, 12)] + [(x0 + 200, base)]
            block(g, pts, "qing", 0.2)
        wrap(island)

        # 货轮：长长一条船身，船尾一座白楼，甲板上码着集装箱，烟囱冒一点烟
        def ship(off):
            sx = 1120 + off
            hull = [(sx - 10, base - 36), (sx + 300, base - 36), (sx + 284, base - 8), (sx + 10, base - 8)]
            block(g, hull, "ink", 0.55)
            block(g, rect_pts(sx - 6, base - 20, 300, 6), "mei", 0.5)
            cols = (("qing", 0.45), ("mei", 0.45), ("ink", 0.3), ("qing", 0.3), ("mei", 0.3), ("ink", 0.45))
            for c in range(9):
                for r in range(2 + (c % 3 == 1)):
                    col, d = cols[(c * 2 + r) % len(cols)]
                    block(g, rect_pts(sx + 70 + c * 22, base - 50 - r * 13, 21, 13), col, d)
            block(g, rect_pts(sx + 6, base - 92, 52, 56), "ink", 0.06, ("ink", None, 1.2))
            for r in range(3):
                g.pen("ink", 0.5).fill(rect_pts(sx + 12, base - 84 + r * 15, 40, 4))
                lit.rect(sx - off + 12, base - 84 + r * 15, 40, 4, 0.8)
            block(g, rect_pts(sx + 22, base - 116, 16, 24), "ink", 0.5)
            for k in range(4):
                g.pen("ink", 0.06 + 0.01 * k).fill(ellipse_pts(sx - 6 - k * 26, base - 128 - k * 10, 14 + k * 8, 7 + k * 3))
            lit.rect(sx - off + 296, base - 44, 4, 4, 1.0)
            # 船底下一道白浪
            g.pen("qing", 0.4).line([(sx - 20, base - 6), (sx + 310, base - 6)], 1.4, amp=0.3)
        wrap(ship)
        # 海平线上远远的几条渔船
        for k in range(5):
            bx = 1500 + k * 90 + rnd.uniform(-20, 20)
            g.pen("ink", 0.35).fill(rect_pts(bx, base - 8, 26, 5))
            g.pen("ink", 0.35).line([(bx + 10, base - 8), (bx + 10, base - 22)], 1.0, amp=0)
    else:
        # 杨树行：一排排又高又瘦的杨树，沿着地头、路边
        rows = ((0.5, 0.22, 100, 150, 22), (0.75, 0.32, 130, 190, 30))
        for depth, d, hmin, hmax, gap in rows:
            def trees(off, depth=depth, d=d, hmin=hmin, hmax=hmax, gap=gap):
                r2 = random.Random(int(depth * 100))
                x = 0.0
                while x < STRIP:
                    if r2.random() < 0.12:
                        x += r2.uniform(120, 300)  # 地头断开一截
                        continue
                    h = r2.uniform(hmin, hmax) * depth / 0.75
                    w = h * r2.uniform(0.18, 0.26)
                    block(g, ellipse_pts(x + off, base - h * 0.55, w, h * 0.5), "qing", d)
                    g.pen("ink", d).line([(x + off, base), (x + off, base - h * 0.3)], 1.4, amp=0)
                    x += gap * r2.uniform(0.7, 1.4)
            wrap(trees)

        # 水塔：一根柱子顶着一只大罐子
        def tower(off):
            tx = 640 + off
            block(g, [(tx - 16, base), (tx - 10, base - 170), (tx + 10, base - 170), (tx + 16, base)], "ink", 0.22)
            block(g, [(tx - 40, base - 168), (tx - 46, base - 214), (tx - 30, base - 236), (tx + 30, base - 236), (tx + 46, base - 214), (tx + 40, base - 168)], "ink", 0.26, ("ink", 0.5, 1.4))
            g.pen("ink", 0.4).line([(tx - 44, base - 190), (tx + 44, base - 190)], 1.2, amp=0)
            lit.rect(tx - off - 2, base - 240, 4, 4, 1.0)
        wrap(tower)

        # 远处的村子：几排红砖房、一根烟囱
        def hamlet(off, x0, n):
            for k in range(n):
                hx = x0 + k * 46 + off
                block(g, rect_pts(hx, base - 30, 40, 30), "mei", 0.32)
                block(g, [(hx - 4, base - 30), (hx + 20, base - 44), (hx + 44, base - 30)], "ink", 0.3)
                if k % 2 == 0:
                    lit.rect(hx - off + 12, base - 22, 8, 8, 0.8)
        wrap(hamlet, 220, 5)
        wrap(hamlet, 1260, 7)

        # 高压线铁塔
        def pylon(off):
            px = 1700 + off
            c = g.pen("ink", 0.3)
            c.line([(px - 30, base), (px - 6, base - 200)], 1.6, amp=0)
            c.line([(px + 30, base), (px + 6, base - 200)], 1.6, amp=0)
            for k in range(5):
                y = base - k * 40
                w = 30 - k * 5
                c.line([(px - w, y), (px + w - 5, y - 40)], 0.9, amp=0)
                c.line([(px + w, y), (px - w + 5, y - 40)], 0.9, amp=0)
            c.line([(px - 46, base - 160), (px + 46, base - 160)], 1.6, amp=0)
            c.line([(px - 36, base - 190), (px + 36, base - 190)], 1.6, amp=0)
        wrap(pylon)
        # 底下一抹庄稼
        for off in (-STRIP, 0, STRIP):
            r3 = random.Random(29)
            xx = 0.0
            while xx < STRIP:
                rr = r3.uniform(12, 26)
                block(g, ellipse_pts(xx + off, base - rr * 0.2, rr * 1.8, rr * 0.5), "qing", 0.3)
                xx += rr * 2.6
    return g, lit


# ----------------------------------------------------------------------
# 中景：隔一两条街的屋顶
# ----------------------------------------------------------------------

MID_H = 640


def mid_specs(era: int, seed=11):
    rnd = random.Random(seed + era * 37)
    items = []
    x = 0.0
    while x < STRIP:
        w = rnd.uniform(210, 380)
        floors = rnd.randint(4, 7)
        tower = era >= 2 and rnd.random() < [0, 0, 0.15, 0.28, 0.3][era]
        if tower:
            floors = rnd.randint(14, 20)
            w = rnd.uniform(160, 220)
        items.append(dict(x=x, w=w, floors=floors, tower=tower, r=rnd.random(), r2=rnd.random(), color=rnd.choice(["mei", "mei", "ink", "qing"])))
        x += w + rnd.uniform(30, 120)
    return items


def draw_mid(era: int, scale=1.0):
    g = Sheet(STRIP, MID_H, scale, seed=70 + era)
    lit = Lit(STRIP, MID_H, scale)
    base = MID_H
    FL = 32  # 一层多高（中景比近景小一号）

    def building(off, it):
        x = it["x"] + off
        w, n = it["w"], it["floors"]
        h = min(n * FL + 20, MID_H - 40)
        col = it["color"]
        d = {"mei": 0.36, "ink": 0.2, "qing": 0.28}[col]
        if it["tower"]:
            col, d = "qing", 0.3
        pts = rect_pts(x, base - h, w, h + 2)
        block(g, pts, col, d, ("ink", 0.55, 1.6))
        # 窗：一排排，窗格墨网点；有的人家亮着
        rows = int((h - 24) / FL)
        cols = max(2, int((w - 30) / 34))
        gap = (w - 30) / cols
        for ry in range(rows):
            wy = base - h + 16 + ry * FL
            for cx in range(cols):
                wx = x + 15 + cx * gap + gap * 0.2
                ww = gap * 0.55
                hsh = (int(it["x"] * 3) * 7919 ^ ry * 104729 ^ cx * 1299709 ^ era * 31) & 0xFFFF
                g.clear(rect_pts(wx, wy, ww, FL * 0.55))
                paper(g, rect_pts(wx, wy, ww, FL * 0.55))
                g.pen("ink", 0.5 if hsh % 5 else 0.3).fill(rect_pts(wx, wy, ww, FL * 0.55))
                if hsh % 9 < 3:
                    lit.rect(wx - off, wy, ww, FL * 0.55, 0.65 + 0.35 * (hsh % 4) / 3)
                # 空调外机（2000 年以后）
                if era >= 1 and hsh % 7 == 0 and not it["tower"]:
                    block(g, rect_pts(wx + ww + 2, wy + FL * 0.3, 12, 9), "ink", 0.12, ("ink", 0.6, 1.0))
        # 楼顶的东西：这一层最有年代感
        top = base - h
        r, r2 = it["r"], it["r2"]
        g.ink.line([(x - 6, top), (x + w + 6, top)], 2.6, amp=0.2)
        if not it["tower"]:
            if era == 0:
                # 九十年代：鱼骨天线、晾衣绳、鸽子笼
                for k in range(1 + int(r * 3)):
                    ax = x + 30 + k * (w - 60) / 3
                    g.ink.line([(ax, top), (ax, top - 46)], 1.6, amp=0)
                    for j in range(4):
                        g.ink.line([(ax - 14 + j * 2, top - 40 + j * 8), (ax + 14 - j * 2, top - 40 + j * 8)], 1.1, amp=0)
            if era in (1, 2, 3):
                # 太阳能热水器：一排斜管子 + 一根横水箱（2000 年以后家家楼顶都有）
                for k in range(1 + int(r * 2)):
                    sx = x + 24 + k * 90 + r2 * 20
                    if sx + 70 > x + w:
                        break
                    block(g, [(sx, top), (sx + 8, top - 34), (sx + 66, top - 34), (sx + 70, top)], "ink", 0.18)
                    for j in range(7):
                        g.ink.line([(sx + 4 + j * 9, top), (sx + 10 + j * 8, top - 34)], 1.0, amp=0, density=0.7)
                    block(g, rect_pts(sx + 4, top - 46, 64, 12), "qing", 0.35, ("ink", None, 1.4))
            if era >= 3 and r > 0.5:
                # 后来的楼顶种了菜和花
                for k in range(int(w / 40)):
                    block(g, circle_pts(x + 20 + k * 40, top - 8, 12), "qing", 0.45)
            if r2 > 0.55:
                # 水箱
                tx = x + w * (0.6 + 0.2 * r)
                block(g, rect_pts(tx - 24, top - 52, 48, 36), "ink", 0.22, ("ink", None, 1.6))
                g.ink.line([(tx - 18, top - 16), (tx - 18, top)], 2, amp=0)
                g.ink.line([(tx + 18, top - 16), (tx + 18, top)], 2, amp=0)
            if r < 0.4:
                # 晾的衣裳
                g.ink.line([(x + 20, top - 34), (x + 130, top - 30)], 1.0, amp=0.3)
                for k in range(4):
                    cc = "mei" if (k + era) % 2 else "qing"
                    block(g, rect_pts(x + 28 + k * 24, top - 32, 16, 20 + (k % 2) * 8), cc, 0.5)
        else:
            lit.rect(x - off + w / 2 - 2, top - 6, 4, 4, 1.0)

    def trees(off):
        rnd = random.Random(3 + era)
        xx = 0.0
        while xx < STRIP:
            rr = rnd.uniform(28, 56)
            block(g, circle_pts(xx + off, base - rr * 0.5, rr), "qing", 0.42)
            g.pen("qing").arc(xx + off, base - rr * 0.5, rr, math.pi * 1.05, math.pi * 1.8, lw=1.8)
            xx += rr * rnd.uniform(1.6, 3.4)

    for it in mid_specs(era):
        wrap(building, it)
    wrap(trees)
    return g, lit


# ----------------------------------------------------------------------
# 树：一种树一年四季
# ----------------------------------------------------------------------

TREES = {
    # 种：(画布宽, 高, 树高, 冠半径)；脚底在画布底边正中，引擎按 anchors 里的 h 缩放
    "huai": (620, 700, 620, 175),
    "willow": (640, 680, 580, 155),
    "young": (300, 380, 320, 84),
}


def branches(rnd, x, y, ang, L, w, depth, out):
    """往上长的枝杈：每一节分两三根，越往上越细。ang 是和竖直向上的夹角（度）。"""
    a = math.radians(ang)
    x2, y2 = x + math.sin(a) * L, y - math.cos(a) * L
    mid = ((x + x2) / 2 + rnd.uniform(-L * 0.06, L * 0.06), (y + y2) / 2)
    out.append(((x, y), mid, (x2, y2), w))
    if depth <= 0:
        return
    for k in range(2 if depth > 2 else rnd.choice((2, 3))):
        na = ang + rnd.uniform(14, 34) * (1 if k % 2 else -1) + rnd.uniform(-8, 8)
        branches(rnd, x2, y2, na, L * rnd.uniform(0.62, 0.8), w * 0.66, depth - 1, out)


def draw_tree(kind: str, season: str, scale=1.25):
    Wd, Hd, h, r = TREES[kind]
    g = Sheet(Wd, Hd, scale, seed=hash((kind, season)) & 0xFFFF)
    rnd = random.Random({"huai": 19, "willow": 3, "young": 7}[kind])
    x, base = Wd / 2, Hd - 4
    col = "qing"
    # 枝杈（四季一样，冬天才全看得见）
    segs = []
    # 主干长到冠子底下，往上的枝杈正好够到冠子边
    trunk = h - r * 1.75
    tw = {"willow": 16, "young": 7, "huai": 19}[kind]
    top = (x + rnd.uniform(-6, 6), base - trunk)
    segs.append(((x, base), ((x + top[0]) / 2 + 3, (base + top[1]) / 2), top, tw))
    for k, ang in enumerate((-48, -16, 14, 44) if kind != "young" else (-30, 4, 32)):
        branches(rnd, top[0], top[1], ang + rnd.uniform(-6, 6), r * (0.62 if kind != "willow" else 0.7), tw * 0.62, 2, segs)
    crown_c = (x, base - h + r * 0.85)
    leafy = season != "winter"

    def draw_branches():
        for (p0, pm, p1, w) in segs:
            g.ink.line([p0, pm, p1], max(1.2, w), amp=0.8)

    def snow():
        # 雪：顺着枝杈上沿挖出一道纸白
        for (p0, pm, p1, w) in segs:
            if w < 2.0:
                continue
            up = [(p[0], p[1] - max(1.0, w * 0.3)) for p in (p0, pm, p1)]
            pts = up + [(p[0], p[1] - max(4.5, w * 0.95)) for p in (p1, pm, p0)]
            g.clear(pts)
            paper(g, pts)

    if kind == "young":
        # 小树：绑着两根撑杆
        g.ink.line([(x - 8, base - h * 0.5), (x - 44, base)], 2.0)
        g.ink.line([(x + 8, base - h * 0.5), (x + 44, base)], 2.0)

    if kind in ("huai", "young"):
        draw_branches()
        if leafy:
            n = 16 if kind == "huai" else 8
            blobs = []
            for i in range(n):
                ang = i / n * math.tau + rnd.uniform(-0.3, 0.3)
                rr = r * rnd.uniform(0.36, 0.52)
                bx = crown_c[0] + math.cos(ang) * r * rnd.uniform(0.55, 0.85)
                by = crown_c[1] + math.sin(ang) * r * rnd.uniform(0.38, 0.6) - r * 0.08
                blobs.append((bx, by, rr))
            for i in range(4):
                blobs.append((crown_c[0] + rnd.uniform(-r * 0.4, r * 0.4), crown_c[1] + rnd.uniform(-r * 0.3, r * 0.2), r * rnd.uniform(0.5, 0.65)))
            fill = {"spring": (col, 0.3), "summer": (col, 0.5), "autumn": ("mei", 0.3)}[season]
            # 一整片冠子一次铺（圆和圆重叠的地方不会更浓）
            union(g, fill[0], fill[1], [circle_pts(bx, by, br) for bx, by, br in blobs])
            for bx, by, br in blobs:
                paper(g, circle_pts(bx, by, br))
            # 冠子里一层更浓的「暗部」，偏下偏后
            union(g, fill[0], fill[1] * 0.6, [circle_pts(bx + br * 0.15, by + br * 0.25, br * 0.6) for bx, by, br in blobs[::2]])
            if season == "autumn":
                # 秋天：梅色里夹着没黄透的青，叶子稀了，枝杈透出来
                union(g, "qing", 0.12, [circle_pts(bx + br * 0.2, by + br * 0.15, br * 0.55) for bx, by, br in blobs[1::3]])
            # 冠子底下一道阴影、上沿一道深色的弧
            g.pen("ink", 0.18).fill(ellipse_pts(crown_c[0] + r * 0.12, crown_c[1] + r * 0.4, r * 0.75, r * 0.22))
            edge = ("qing", None) if season != "autumn" else ("mei", 0.7)
            for bx, by, br in blobs[:n]:
                if by < crown_c[1] + r * 0.1:
                    g.pen(*edge).arc(bx, by, br, math.pi * 1.1, math.pi * 1.7, lw=2.2)
            for _ in range(22 if kind == "huai" else 8):
                lx, ly = crown_c[0] + rnd.uniform(-r * 0.85, r * 0.85), crown_c[1] + rnd.uniform(-r * 0.55, r * 0.5)
                g.ink.arc(lx, ly, 6, 0.2, 2.6, lw=1.4)
            if season == "spring":
                # 槐花：一串串白里透粉的小点
                for _ in range(60 if kind == "huai" else 18):
                    lx, ly = crown_c[0] + rnd.uniform(-r * 0.9, r * 0.9), crown_c[1] + rnd.uniform(-r * 0.6, r * 0.55)
                    pts = circle_pts(lx, ly, rnd.uniform(3, 5.5), 10)
                    g.clear(pts)
                    paper(g, pts)
                    g.pen("mei", 0.22).fill(pts)
            # 冠子里隐约露出几根枝
            for (p0, pm, p1, w) in segs[1:]:
                if w > 8:
                    g.pen("ink", 0.5).line([p0, pm], w * 0.7, amp=0.8)
            g.ink.line([segs[0][0], segs[0][1], segs[0][2]], segs[0][3], amp=0.8)
        else:
            snow()
    else:  # willow
        draw_branches()
        # 柳条：从枝梢垂下来
        tips = [s for s in segs if s[3] < 12]
        n_str = {"spring": 8, "summer": 9, "autumn": 6, "winter": 5}[season]
        if season != "winter":
            dome = ellipse_pts(x, base - h + r * 0.75, r * 1.25, r * 0.6)
            g.pen(col if season != "autumn" else "mei", 0.2).fill(dome)
        for (p0, pm, p1, w) in tips:
            for k in range(n_str):
                t = rnd.uniform(0.2, 1.0)
                sx = p0[0] + (p1[0] - p0[0]) * t
                sy = p0[1] + (p1[1] - p0[1]) * t
                L = rnd.uniform(r * 0.8, r * 2.0) * (0.75 + 0.25 * t)
                L = min(L, base - sy - 30)
                sway = rnd.uniform(-10, 18)
                pts = [(sx + sway * (j / 6) ** 2, sy + L * j / 6) for j in range(7)]
                if season == "winter":
                    g.pen("ink", 0.55).line(pts, 1.0, amp=0.6)
                    continue
                c = {"spring": (col, 0.42), "summer": (col, 0.58), "autumn": ("mei", 0.3) if k % 2 else (col, 0.32)}[season]
                g.pen(c[0], c[1]).line(pts, rnd.uniform(1.4, 2.4), amp=0.7)
                if rnd.random() < (0.7 if season != "autumn" else 0.4):
                    lp = ellipse_pts(sx + sway * 0.5, sy + L * 0.55, 5.5, L * 0.4)
                    g.pen(c[0], 0.34 if season == "summer" else 0.24).fill(lp)
                    paper(g, lp)
        if season == "winter":
            snow()
    # 树坑那一道（底图上也有，叠上不碍事）
    g.ink.line([(x - 40, base), (x + 40, base)], 4)
    return g


# ----------------------------------------------------------------------
# 前景：贴着镜头的一溜东西（比人走得快，像是镜头前面隔着它们看过去）
# ----------------------------------------------------------------------

FORE_H = 240
FORE_KINDS = ("street", "river", "green", "school", "market", "sea", "field")


def draw_fore(kind: str, scale=1.0):
    g = Sheet(STRIP, FORE_H, scale, seed=90 + FORE_KINDS.index(kind))
    base = FORE_H
    rnd = random.Random(31 + FORE_KINDS.index(kind))
    dark = ("ink", 0.78)
    items = []
    x = rnd.uniform(60, 200)
    while x < STRIP - 60:
        items.append((x, rnd.random(), rnd.random()))
        x += rnd.uniform(340, 760)

    def sil(pts, spec=dark):
        block(g, pts, spec[0], spec[1])

    def grass(off, x, w, h, color="ink", d=0.8):
        pts = [(x + off, base)]
        n = int(w / 7)
        for i in range(n + 1):
            tx = x + off + i * w / n
            pts.append((tx + rnd.uniform(-3, 3), base - h * rnd.uniform(0.45, 1.0)))
            pts.append((tx + w / n * 0.5, base - h * rnd.uniform(0.05, 0.3)))
        pts.append((x + off + w, base))
        sil(pts, (color, d))

    def bush(off, x, w, h, color="qing", d=0.62):
        circles = []
        k = max(3, int(w / 40))
        for i in range(k):
            cx = x + off + (i + 0.5) * w / k
            rr = h * rnd.uniform(0.45, 0.7)
            circles.append(circle_pts(cx, base - rr * 0.7, rr))
        union(g, color, d, circles)
        for c in circles:
            g.clear(c, colors=["mei"])
            paper(g, c)
        union(g, "ink", 0.35, [circle_pts(sum(p[0] for p in c) / len(c) + 6, base - 6, 30) for c in circles])

    def item(off, x, r, r2):
        if kind == "street":
            if r < 0.3:
                # 路边一溜矮栏杆
                cx = x + off
                for k in range(5):
                    g.ink.line([(cx + k * 40, base), (cx + k * 40, base - 80)], 6)
                g.ink.line([(cx - 10, base - 70), (cx + 170, base - 70)], 5)
                g.pen("mei", 0.7).line([(cx - 10, base - 40), (cx + 170, base - 40)], 5)
            elif r < 0.55:
                # 消防栓
                cx = x + off
                sil(rect_pts(cx - 22, base - 86, 44, 86), ("mei", 0.85))
                sil([(cx - 28, base - 86), (cx + 28, base - 86), (cx + 18, base - 108), (cx - 18, base - 108)], ("mei", 0.85))
                sil(rect_pts(cx - 38, base - 70, 76, 14), ("ink", 0.8))
                g.ink.poly(rect_pts(cx - 22, base - 86, 44, 86), w=3)
            elif r < 0.8:
                # 一小丛冬青
                bush(off, x, rnd.uniform(160, 260), rnd.uniform(60, 90), "qing", 0.7)
            else:
                # 路边的石墩
                cx = x + off
                sil([(cx - 30, base), (cx - 26, base - 84), (cx + 26, base - 84), (cx + 30, base)], ("ink", 0.62))
                g.ink.line([(cx - 28, base - 84), (cx + 28, base - 84)], 4)
        elif kind == "river":
            if r < 0.6:
                # 芦苇：一丛细长的叶子、几根穗
                cx = x + off
                for k in range(14):
                    a = rnd.uniform(-0.35, 0.35)
                    L = rnd.uniform(80, 150)
                    p1 = (cx + k * 7 + math.sin(a) * L, base - math.cos(a) * L)
                    g.pen("ink", 0.85).line([(cx + k * 7, base), ((cx + k * 7 + p1[0]) / 2 + a * 20, (base + p1[1]) / 2), p1], 3.4)
                for k in range(4):
                    px = cx + 20 + k * 22
                    py = base - rnd.uniform(140, 170)
                    g.pen("ink", 0.8).line([(px, base), (px + 6, py)], 2)
                    sil(ellipse_pts(px + 8, py - 18, 7, 22), ("mei", 0.55))
            else:
                # 近处一截石栏杆
                cx = x + off
                sil(rect_pts(cx, base - 110, 46, 110), ("ink", 0.7))
                sil(rect_pts(cx - 8, base - 126, 62, 20), ("ink", 0.85))
                sil(rect_pts(cx + 46, base - 90, 260, 20), ("ink", 0.7))
                g.ink.poly(rect_pts(cx, base - 110, 46, 110), w=3)
        elif kind == "green":
            if r < 0.5:
                bush(off, x, rnd.uniform(200, 340), rnd.uniform(64, 100), "qing", 0.62)
                if r2 < 0.5:
                    for k in range(7):
                        fx, fy = x + off + rnd.uniform(20, 200), base - rnd.uniform(60, 120)
                        pts = circle_pts(fx, fy, 8, 10)
                        g.clear(pts)
                        paper(g, pts)
                        g.pen("mei", 0.75).fill(pts)
            else:
                grass(off, x, rnd.uniform(140, 260), rnd.uniform(50, 100))
        elif kind == "school":
            if r < 0.45:
                # 近处的铁栅栏：几根尖头的竖杆
                cx = x + off
                for k in range(6):
                    px = cx + k * 34
                    g.ink.line([(px, base), (px, base - 100)], 7)
                    sil([(px - 8, base - 100), (px + 8, base - 100), (px, base - 120)], ("ink", 0.95))
                g.ink.line([(cx - 10, base - 80), (cx + 180, base - 80)], 6)
                g.ink.line([(cx - 10, base - 40), (cx + 180, base - 40)], 6)
            else:
                bush(off, x, rnd.uniform(180, 280), rnd.uniform(60, 90), "qing", 0.66)
        elif kind == "market":
            cx = x + off
            if r < 0.4:
                # 近处一只竹筐，冒出几片菜叶
                sil([(cx, base), (cx - 10, base - 90), (cx + 130, base - 90), (cx + 120, base)], ("ink", 0.72))
                for k in range(5):
                    sil(ellipse_pts(cx + 14 + k * 26, base - 98, 18, 14), ("qing", 0.7))
                g.ink.line([(cx - 14, base - 90), (cx + 134, base - 90)], 6)
            else:
                # 摞起来的塑料筐
                for k in range(2):
                    sil(rect_pts(cx + k * 6, base - 64 - k * 64, 120, 62), ("qing", 0.62))
                    for j in range(5):
                        g.clear(rect_pts(cx + k * 6 + 10 + j * 22, base - 50 - k * 64, 12, 12), colors=["qing"])
        elif kind == "sea":
            cx = x + off
            if r < 0.55:
                # 沙丘上一丛海草
                for k in range(16):
                    a = rnd.uniform(-0.6, 0.6)
                    L = rnd.uniform(60, 130)
                    g.pen("ink", 0.85).line([(cx + k * 6, base), (cx + k * 6 + math.sin(a) * L * 0.5 + a * 20, base - L * 0.6), (cx + k * 6 + math.sin(a) * L, base - math.cos(a) * L)], 3.0)
                sil([(cx - 40, base), (cx + 60, base - 40), (cx + 160, base)], ("mei", 0.4))
            elif r < 0.8:
                # 一截木桩，拴着一根缆绳
                sil(rect_pts(cx, base - 140, 34, 140), ("ink", 0.75))
                sil(ellipse_pts(cx + 17, base - 140, 17, 6), ("ink", 0.9))
                g.ink.line([(cx + 30, base - 100), (cx + 120, base - 60), (cx + 220, base - 20)], 4)
            else:
                # 一只倒扣在沙滩上的小舢板
                sil([(cx, base), (cx + 30, base - 50), (cx + 240, base - 56), (cx + 280, base)], ("qing", 0.7))
                g.ink.line([(cx + 30, base - 50), (cx + 240, base - 56)], 4)
        elif kind == "field":
            cx = x + off
            if r < 0.5:
                # 地头的玉米：几片长叶子从镜头底下扫上来
                for k in range(6):
                    s = -1 if k % 2 else 1
                    L = rnd.uniform(120, 200)
                    sx = cx + k * 18
                    tip = (sx + s * L * 0.8, base - rnd.uniform(90, 180))
                    sil([(sx, base), (sx + s * L * 0.3, base - L * 0.55), tip, (sx + s * L * 0.35, base - L * 0.4), (sx + 12, base)], ("qing", 0.6))
                g.ink.line([(cx + 40, base), (cx + 46, base - 230)], 6)
            else:
                # 狗尾巴草
                for k in range(9):
                    px = cx + k * 16
                    py = base - rnd.uniform(90, 150)
                    g.pen("ink", 0.85).line([(px, base), (px + 6, py + 10), (px + 16, py)], 2.4)
                    sil(ellipse_pts(px + 18, py - 4, 8, 16), ("qing", 0.55))
                grass(off, x - 20, 200, 60, "ink", 0.8)

    for it in items:
        wrap(item, *it)
    return g


# ----------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("what", nargs="*", default=["far", "mid", "places", "trees", "fore"])
    ap.add_argument("--preview", help="拼一张预览图")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    prev = []
    if "far" in a.what:
        for i, era in enumerate(ERAS):
            g, lit = draw_far(i)
            save_rgba(g, os.path.join(OUT, f"far_{era}.png"))
            lit.save(os.path.join(OUT, f"far_{era}_lit.png"))
            prev.append(g.composite())
            print("✓ far", era)
    if "mid" in a.what:
        for i, era in enumerate(ERAS):
            g, lit = draw_mid(i)
            save_rgba(g, os.path.join(OUT, f"mid_{era}.png"))
            lit.save(os.path.join(OUT, f"mid_{era}_lit.png"))
            prev.append(g.composite())
            print("✓ mid", era)
    if "places" in a.what:
        for kind in PLACES:
            g, lit = draw_place(kind)
            save_rgba(g, os.path.join(OUT, f"far_{kind}.png"))
            lit.save(os.path.join(OUT, f"far_{kind}_lit.png"))
            prev.append(g.composite())
            print("✓ far", kind)
    if "trees" in a.what:
        for kind in TREES:
            row = []
            for season in SEASONS:
                g = draw_tree(kind, season)
                save_rgba(g, os.path.join(OUT, f"tree_{kind}_{season}.png"), colors=48)
                row.append(g.composite())
            if a.preview:
                prev.append(np.concatenate(row, axis=1))
            print("✓ tree", kind)
    if "fore" in a.what:
        for kind in FORE_KINDS:
            g = draw_fore(kind)
            save_rgba(g, os.path.join(OUT, f"fore_{kind}.png"), colors=48)
            prev.append(g.composite())
            print("✓ fore", kind)
    if a.preview and prev:
        W = max(p.shape[1] for p in prev)
        rows = [np.pad(p, ((0, 8), (0, W - p.shape[1]), (0, 0)), constant_values=255) for p in prev]
        Image.fromarray(np.concatenate(rows, axis=0)).save(a.preview)
        print("预览：", a.preview)


if __name__ == "__main__":
    main()
