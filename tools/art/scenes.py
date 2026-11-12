"""侧视横版的十一张图：python3 tools/art/scenes.py [图 id ...]

每张图是一条横着的剖面或街景，人只左右走。坐标是"这张图自己的"：
  x 从 0 到 width（content/maps/<图>.yaml），y 从 TOP 到 BOTTOM，地面在 floors[i] - top（单层图都是 760）。
输出到 client/art/scenes/<图>_<k>.png：每片横着 SLICE 世界像素，ART_SCALE 倍输出，64 色调色板 PNG。
引擎（client/scripts/world/scene_art.gd）按同样的常数把它们一片片摆回去。

画的规矩：
  - 人站在地面线上，脚下往下是剖到的楼板 / 人行道 / 水，头顶留出 430 世界像素给人和牌子。
  - 出口的地方要画一扇门、一道楼梯或一个路口，引擎只在上面挂一块牌子。
  - 互动点（spots）的 x 以 content 为准，家具围着它画。
  - 年代会变的东西（告示、车、招牌上的价钱）不画进底图，留给街景层。

预览某一段（调美术时用，快）：
  python3 tools/art/scenes.py --preview street --x 0 --w 2400 --scale 0.5 --out /tmp/street.png
"""
from __future__ import annotations

import argparse
import json
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from riso import ROOT, Sheet, circle_pts, ellipse_pts, font_path, rect_pts  # noqa: E402

SLICE = 1024
TOP = -200
BOTTOM = 1000
ART_SCALE = 1.25
MARGIN = 16
GROUND = 760
MASK_STEP = 4
OUT = os.path.join(ROOT, "client", "art", "scenes")


# ----------------------------------------------------------------------
# 读内容
# ----------------------------------------------------------------------

def load_scenes():
    with open(os.path.join(ROOT, "client", "data", "content.json"), encoding="utf-8") as f:
        m = json.load(f)["map"]
    out = {}
    for s in m["scenes"]:
        top = float(s["top"])
        sid = s["id"]
        out[sid] = {
            "id": sid,
            "name": s["name"],
            "width": float(s["width"]),
            "floors": [float(y) - top for y in s["floors"]],
            "zones": {z["id"]: z for z in m["zones"] if z["scene"] == sid},
            "spots": {p["id"]: float(p["at"][0]) for p in m["spots"] if p.get("scene") == sid},
            "exits": {e["id"].split(".", 1)[1]: (float(e["at"][0]), float(e["at"][1]) - top) for e in m["exits"] if e["scene"] == sid},
        }
    return out


# ----------------------------------------------------------------------
# 灯：画到灯的时候顺手记一笔，夜里 print_light.gd 按它们烘灯光图
# ----------------------------------------------------------------------

ANCHORS: dict | None = None
SPLIT = True  ## 分层：天、远处的楼、树不画进底图（见 tools/art/layers.py）


def layer_note(key, value):
    """记下这张图给分层用的参数（地平线、远处楼脚的高度）：第一次记的算数。"""
    if ANCHORS is not None:
        ANCHORS.setdefault("layer", {}).setdefault(key, value)


def mark(kind, x, y):
    if ANCHORS is not None:
        ANCHORS.setdefault(kind, []).append([round(x), round(y)])


# ----------------------------------------------------------------------
# 快的底层笔：不抖、不吃随机种子，可以按切片跳过看不见的部分
# ----------------------------------------------------------------------

def _ctx(g, color, tint):
    return g.plates[color]["tint" if tint else "solid"]


def visible(g, x0, x1, pad=40):
    ox = g.origin[0]
    return x1 >= ox - pad and x0 <= ox + g.w + pad


def fline(g, color, pts, lw=1.4, d=1.0, tint=False):
    c = _ctx(g, color, tint)
    c.new_path()
    c.move_to(*pts[0])
    for p in pts[1:]:
        c.line_to(*p)
    c.set_line_width(lw)
    c.set_line_cap(1)
    c.set_source_rgba(0, 0, 0, d)
    c.stroke()


def fbricks(g, x, y, w, h, bw=30.0, bh=11.0, lw=0.9, d=0.32, seed=1):
    """砖缝。只画这一片看得见的那几列。"""
    if not visible(g, x, x + w):
        return
    rnd = random.Random(seed)
    c = _ctx(g, "ink", False)
    c.save()
    c.rectangle(x, y, w, h)
    c.clip()
    c.set_line_width(lw)
    c.set_source_rgba(0, 0, 0, d)
    lo = max(x, g.origin[0] - bw)
    hi = min(x + w, g.origin[0] + g.w + bw)
    row = 0
    yy = y
    while yy < y + h:
        c.move_to(lo, yy)
        c.line_to(hi, yy)
        off = (bw / 2) * (row % 2)
        k0 = math.floor((lo - x + off) / bw)
        xx = x - off + k0 * bw
        while xx < hi:
            # 缺缝按砖的位置定（每片一样），不靠调用次序
            hsh = (int(xx * 7.1) * 73856093 ^ row * 19349663 ^ seed * 83492791) & 0xFFFF
            if hsh > 5000:
                c.move_to(xx, yy)
                c.line_to(xx, yy + bh)
            xx += bw
        yy += bh
        row += 1
    c.stroke()
    c.restore()
    del rnd


def fhatch(g, color, x, y, w, h, angle=45.0, gap=9.0, lw=1.2, d=1.0, tint=False):
    """矩形里的平行排线（剖切面、阴影），只画看得见的。"""
    if not visible(g, x, x + w):
        return
    c = _ctx(g, color, tint)
    c.save()
    c.rectangle(x, y, w, h)
    c.clip()
    c.set_line_width(lw)
    c.set_source_rgba(0, 0, 0, d)
    t = math.tan(math.radians(angle))
    lo = max(x, g.origin[0] - 40) - h * abs(t) - gap
    hi = min(x + w, g.origin[0] + g.w + 40) + h * abs(t) + gap
    k = math.floor(lo / gap) * gap
    while k < hi:
        c.move_to(k, y + h)
        c.line_to(k + h * t, y)
        k += gap
    c.stroke()
    c.restore()


def ftint(g, color, pts, d):
    g.pen(color, d).fill(pts)


def knock(g, color, text, x, y, size, vertical=False, layer="solid"):
    """反白字：在一块色版上把字形挖掉（孔版里最好看的就是它）。"""
    S = g.scale
    f = ImageFont.truetype(font_path(), max(1, int(size * S)))
    if vertical:
        step = size * S * 1.08
        Wd, Hd = int(size * S * 1.4), int(step * len(text) + 4)
        img = Image.new("L", (Wd, Hd), 0)
        dr = ImageDraw.Draw(img)
        for i, ch in enumerate(text):
            dr.text((Wd / 2, step * (i + 0.5)), ch, font=f, fill=255, anchor="mm")
    else:
        bb = f.getbbox(text, anchor="mm")
        Wd, Hd = bb[2] - bb[0] + 8, bb[3] - bb[1] + 8
        img = Image.new("L", (Wd, Hd), 0)
        dr = ImageDraw.Draw(img)
        dr.text((Wd / 2, Hd / 2), text, font=f, fill=255, anchor="mm")
    m = np.asarray(img, dtype=np.float32) / 255.0
    ox = int(round((x - g.origin[0]) * S - Wd / 2))
    oy = int(round((y - g.origin[1]) * S - Hd / 2))
    x0, y0 = max(0, ox), max(0, oy)
    x1, y1 = min(g.W, ox + Wd), min(g.H, oy + Hd)
    if x1 <= x0 or y1 <= y0:
        return
    surf = g._surfaces[(color, layer)]
    surf.flush()
    buf = np.ndarray((g.H, surf.get_stride()), dtype=np.uint8, buffer=surf.get_data())
    sub = buf[y0:y1, x0:x1].astype(np.float32)
    sub *= 1.0 - m[y0 - oy : y1 - oy, x0 - ox : x1 - ox]
    buf[y0:y1, x0:x1] = sub.astype(np.uint8)
    surf.mark_dirty()


# ----------------------------------------------------------------------
# 零件
# ----------------------------------------------------------------------

def sky(g, w, seed=3, horizon=GROUND, clouds=5):
    """天：分层以后天归引擎画（shaders/sky.gdshader，跟着钟点变色、云会走），这里只记一笔地平线在哪。"""
    if SPLIT:
        layer_note("horizon", horizon)
        return
    rnd = random.Random(seed)
    # 越靠近地平线越青：六层很淡的网点叠出来，没有硬边
    for k in range(6):
        y0 = TOP - 60 + (horizon - TOP + 60) * k / 6
        g.pen("qing", 0.016 + 0.004 * k).fill(rect_pts(-50, y0, w + 100, horizon - y0))
    for i in range(clouds):
        cx = rnd.uniform(0, w)
        cy = rnd.uniform(-150, 120)
        L = rnd.uniform(160, 420)
        g.pen("qing", 0.16).fill(ellipse_pts(cx, cy, L / 2, 16))
        g.qing.line([(cx - L / 2, cy + 6), (cx + L / 2, cy + 6)], 1.8, amp=1.2)
        g.qing.line([(cx - L / 3, cy - 8), (cx + L / 4, cy - 8)], 1.4, amp=1.0)


def skyline(g, x0, x1, base, seed=1, hmin=60, hmax=220, color="qing", d=0.16, chimneys=(), towers=()):
    """远处一排楼：一层淡色的剪影，窗是更淡的点。
    分层以后远处的楼归远景层（tools/art/layers.py，按年代长高），这里只记一笔它们的楼脚在哪。"""
    if SPLIT:
        layer_note("far_base", base)
        layer_note("far_color", color)
        return
    rnd = random.Random(seed)
    x = x0
    while x < x1:
        bw = rnd.uniform(70, 170)
        bh = rnd.uniform(hmin, hmax)
        pts = rect_pts(x, base - bh, bw, bh + 4)
        g.pen(color, d).fill(pts)
        if rnd.random() < 0.3:
            g.pen(color, d).fill([(x + 10, base - bh), (x + bw / 2, base - bh - 26), (x + bw - 10, base - bh)])
        if rnd.random() < 0.6 and bh > 80:
            for wy in range(int(base - bh + 18), int(base - 14), 26):
                for wx in range(int(x + 12), int(x + bw - 12), 22):
                    if rnd.random() < 0.55:
                        g.pen(color, d * 1.8).fill(rect_pts(wx, wy, 8, 10))
                        if rnd.random() < 0.12:
                            mark("far_light", wx + 4, wy + 5)
        x += bw + rnd.uniform(-20, 24)
    for cx, ch in chimneys:
        g.pen(color, d * 1.6).fill([(cx - 14, base), (cx - 9, base - ch), (cx + 9, base - ch), (cx + 14, base)])
        for k in range(3):
            g.pen("ink", 0.06).fill(ellipse_pts(cx + 26 + k * 34, base - ch - 20 - k * 16, 22 + k * 8, 12 + k * 4))
    for cx, ch in towers:
        g.pen(color, d * 1.4).fill(rect_pts(cx - 30, base - ch, 60, ch))
        g.pen(color, d * 1.4).fill([(cx - 34, base - ch), (cx, base - ch - 36), (cx + 34, base - ch)])


def window(g, x, y, w, h, panes=2, lit=False, frame="ink", curtain=None, sill=True, glass=True, night=False):
    if lit or night:
        mark("window_light", x + w / 2, y + h / 2)
    g.clear(rect_pts(x, y, w, h))
    if glass:
        g.pen("qing", 0.22 if not lit else 0.08).fill(rect_pts(x, y, w, h))
        g.qing.line([(x + w * 0.18, y + h * 0.22), (x + w * 0.42, y + h * 0.08)], 1.6, amp=0.2)
    if lit:
        g.pen("mei", 0.16).fill(rect_pts(x, y, w, h))
    if curtain:
        g.pen(curtain, 0.45).fill([(x, y), (x + w * 0.28, y), (x + w * 0.2, y + h * 0.5), (x + w * 0.24, y + h), (x, y + h)])
        g.pen(curtain, 0.45).fill([(x + w, y), (x + w * 0.72, y), (x + w * 0.8, y + h * 0.5), (x + w * 0.76, y + h), (x + w, y + h)])
    f = g.pen(frame)
    f.rect(x, y, w, h, lw=2.6, amp=0.4)
    for i in range(1, panes):
        f.line([(x + w * i / panes, y), (x + w * i / panes, y + h)], 2.0, amp=0.2)
    f.line([(x, y + h * 0.34), (x + w, y + h * 0.34)], 1.8, amp=0.2)
    if sill:
        g.ink.line([(x - 8, y + h + 4), (x + w + 8, y + h + 4)], 3.2, amp=0.3)


def facade(g, x0, x1, top, base, color="mei", d=0.5, rows=3, win=(70, 92), gap=56, brick=True, seed=1, lit=(), cornice=True, window_from=None):
    """一栋楼的正面：色块 + 砖缝 + 一排排窗。"""
    if not visible(g, x0, x1, 400):
        # 不画也要把这些笔的种子吃掉：后面的长线才能和邻片接上
        pass
    pts = rect_pts(x0, top, x1 - x0, base - top)
    g.clear(pts)
    g.pen(color, d).fill(pts)
    if brick:
        fbricks(g, x0, top, x1 - x0, base - top, seed=seed)
    g.ink.line([(x0, top), (x0, base)], 3.0, amp=0.5)
    g.ink.line([(x1, top), (x1, base)], 3.0, amp=0.5)
    if cornice:
        g.clear(rect_pts(x0 - 10, top - 14, x1 - x0 + 20, 16))
        g.pen("ink", 0.3).fill(rect_pts(x0 - 10, top - 14, x1 - x0 + 20, 16))
        g.ink.rect(x0 - 10, top - 14, x1 - x0 + 20, 16, lw=2.4, amp=0.4)
    ww, wh = win
    rnd = random.Random(seed)
    lo = window_from if window_from is not None else base
    row_h = (lo - top - 20) / max(1, rows)
    n = max(1, int((x1 - x0 - gap) / (ww + gap)))
    span = n * ww + (n - 1) * gap
    sx = x0 + (x1 - x0 - span) / 2
    for r in range(rows):
        wy = top + 30 + r * row_h
        for i in range(n):
            wx = sx + i * (ww + gap)
            cur = None
            if rnd.random() < 0.3:
                cur = rnd.choice(["qing", "mei", "ink"])
            window(g, wx, wy, ww, min(wh, row_h - 34), lit=(r, i) in lit, curtain=cur, night=rnd.random() < 0.3)
            if rnd.random() < 0.18:
                # 窗外晾的衣裳
                rod_y = wy + 10
                g.ink.line([(wx - 10, rod_y), (wx + ww + 10, rod_y)], 1.6, amp=0.2)
                for k in range(rnd.randint(1, 3)):
                    cx = wx + 8 + k * 22
                    g.pen(rnd.choice(["qing", "mei"]), 0.5).fill(rect_pts(cx, rod_y, 16, rnd.uniform(26, 40)))
    return n


def roof_clutter(g, x0, x1, top, seed=1, pigeons=False):
    """屋顶上的零碎：女儿墙、水箱、通风帽、晾衣架、几盆花，我们那栋还有鸽子笼。不带年代（年代的东西在中景层）。"""
    rnd = random.Random(seed)
    w = x1 - x0
    # 女儿墙
    g.clear(rect_pts(x0 - 4, top - 26, w + 8, 26))
    g.pen("ink", 0.16).fill(rect_pts(x0 - 4, top - 26, w + 8, 26))
    fbricks(g, x0 - 4, top - 26, w + 8, 26, 24, 9, seed=seed)
    g.ink.rect(x0 - 4, top - 26, w + 8, 26, lw=2.4, amp=0.3)
    base = top - 26
    x = x0 + rnd.uniform(30, 80)
    racks = 0
    while x < x1 - 90:
        k = rnd.random()
        if 0.4 <= k < 0.62 and racks >= 1:
            k = 0.7
        racks += 1 if 0.4 <= k < 0.62 else 0
        if k < 0.22:
            # 水箱：架子上一只铁皮桶
            g.ink.line([(x + 6, base), (x + 6, base - 30)], 3)
            g.ink.line([(x + 74, base), (x + 74, base - 30)], 3)
            g.ink.line([(x + 6, base - 14), (x + 74, base - 30)], 1.6)
            pts = rect_pts(x, base - 82, 80, 52)
            g.clear(pts)
            g.pen("qing", 0.32).fill(pts)
            g.ink.rect(x, base - 82, 80, 52, lw=2.6)
            for j in range(1, 4):
                g.ink.line([(x, base - 82 + j * 13), (x + 80, base - 82 + j * 13)], 1.0, density=0.5)
            x += 120
        elif k < 0.4:
            # 通风帽
            g.ink.line([(x + 10, base), (x + 10, base - 40)], 6)
            g.pen("ink").fill([(x - 8, base - 40), (x + 28, base - 40), (x + 10, base - 56)])
            x += 60
        elif k < 0.62:
            # 晾衣架：两根杆、一根绳、几件衣裳
            L = rnd.uniform(110, 170)
            g.ink.line([(x, base), (x, base - 70)], 2.6)
            g.ink.line([(x + L, base), (x + L, base - 70)], 2.6)
            g.ink.line([(x, base - 66), (x + L / 2, base - 58), (x + L, base - 66)], 1.4, amp=0.3)
            cx = x + 12
            while cx < x + L - 24:
                cw, ch = rnd.uniform(16, 30), rnd.uniform(26, 44)
                pts = rect_pts(cx, base - 62, cw, ch)
                g.clear(pts)
                g.pen(rnd.choice(["qing", "mei", "mei", "ink"]), rnd.choice([0.3, 0.5, 0.7])).fill(pts)
                g.ink.rect(cx, base - 62, cw, ch, lw=1.3, amp=0.3)
                cx += cw + rnd.uniform(4, 12)
            x += L + 40
        elif k < 0.8:
            # 几盆花草
            for j in range(rnd.randint(2, 4)):
                px = x + j * 30
                pts = [(px, base), (px + 22, base), (px + 25, base - 22), (px - 3, base - 22)]
                g.clear(pts)
                g.pen("mei", 0.55).fill(pts)
                g.ink.poly(pts, w=1.6, amp=0.2)
                g.qing.line([(px + 11, base - 22), (px + 4, base - 44)], 2.2)
                g.qing.line([(px + 11, base - 22), (px + 20, base - 48)], 2.2)
                g.pen("qing", 0.5).fill(circle_pts(px + 12, base - 44, 9))
            x += 140
        else:
            x += rnd.uniform(40, 120)
    if pigeons:
        # 鸽子笼：木条钉的小房子
        cx = x0 + w * 0.68
        pts = rect_pts(cx, base - 96, 130, 96)
        g.clear(pts)
        g.pen("ink", 0.12).fill(pts)
        g.ink.rect(cx, base - 96, 130, 96, lw=2.6)
        g.pen("ink", 0.4).fill([(cx - 12, base - 96), (cx + 142, base - 96), (cx + 65, base - 128)])
        g.ink.poly([(cx - 12, base - 96), (cx + 142, base - 96), (cx + 65, base - 128)], w=2.4, amp=0.2)
        for j in range(5):
            g.ink.line([(cx + 10 + j * 26, base - 90), (cx + 10 + j * 26, base - 6)], 1.4)
        g.ink.line([(cx, base - 48), (cx + 130, base - 48)], 1.6)


def door(g, x, base, w=100, h=210, color="ink", d=0.35, open_=0.0, glass=False, plate=None, plate_color="qing"):
    """一扇门。open_ 0~1：门洞里露出多少黑。"""
    pts = rect_pts(x - w / 2, base - h, w, h)
    g.clear(pts)
    g.pen("ink", 0.55).fill(pts)
    if open_ < 1.0:
        lw = w * (1 - open_)
        leaf = rect_pts(x - w / 2, base - h, lw, h)
        g.clear(leaf)
        g.pen(color, d).fill(leaf)
        g.pen(color).rect(x - w / 2 + 8, base - h + 12, lw - 16, h * 0.4, lw=1.6, amp=0.3)
        g.pen(color).rect(x - w / 2 + 8, base - h * 0.48, lw - 16, h * 0.4, lw=1.6, amp=0.3)
        if glass:
            g.clear(rect_pts(x - w / 2 + 10, base - h + 14, lw - 20, h * 0.36))
            g.pen("qing", 0.25).fill(rect_pts(x - w / 2 + 10, base - h + 14, lw - 20, h * 0.36))
        g.ink.dot(x - w / 2 + lw - 12, base - h * 0.5, 4)
    g.ink.rect(x - w / 2, base - h, w, h, lw=3.0, amp=0.4)
    if plate:
        pw = 22 * len(plate) + 16
        g.clear(rect_pts(x - pw / 2, base - h - 40, pw, 28))
        g.pen(plate_color).fill(rect_pts(x - pw / 2, base - h - 40, pw, 28))
        knock(g, plate_color, plate, x, base - h - 26, 20)


def signboard(g, cx, cy, text, color="mei", size=40, vertical=False, pad=14, frame=True):
    n = len(text)
    if vertical:
        w, h = size * 1.5, size * 1.08 * n + pad * 2
    else:
        w, h = size * 1.05 * n + pad * 2, size * 1.55
    pts = rect_pts(cx - w / 2, cy - h / 2, w, h)
    g.clear(pts)
    g.pen(color).fill(pts)
    if frame:
        g.ink.rect(cx - w / 2, cy - h / 2, w, h, lw=2.4, amp=0.4)
    knock(g, color, text, cx, cy, size, vertical)
    return w, h


def awning(g, x0, x1, y, drop=46, color="mei", stripes=True):
    mark("stall_light", (x0 + x1) / 2, y + drop + 60)
    pts = [(x0 - 14, y), (x1 + 14, y), (x1 + 24, y + drop), (x0 - 24, y + drop)]
    g.clear(pts)
    g.pen(color, 0.55).fill(pts)
    if stripes:
        w = 34
        x = x0 - 14
        i = 0
        while x < x1 + 14:
            if i % 2 == 0:
                g.pen(color).fill([(x, y), (min(x + w, x1 + 14), y), (min(x + w, x1 + 14) + 10, y + drop), (x - 10 if x > x0 - 14 else x0 - 24, y + drop)])
            x += w
            i += 1
    g.ink.poly(pts, w=2.4, amp=0.5)
    # 布边一排小波浪
    n = int((x1 - x0 + 48) / 24)
    for k in range(n):
        ax = x0 - 24 + k * 24
        g.pen(color).arc(ax + 12, y + drop, 12, 0, math.pi, lw=2.2, amp=0.2)


def tree(g, x, base, h=420, r=130, kind="huai", seed=0, color="qing"):
    """树：墨色树干，青色网点树冠，冠子外圈一道深一点的弧。
    分层以后树单独印成精灵（tools/art/layers.py 一年四季各一张，引擎里会随风晃），底图上只留树坑。"""
    rnd = random.Random(seed or int(x * 7))
    # 树坑
    g.ink.line([(x - 40, base), (x + 40, base)], 4)
    if SPLIT:
        if ANCHORS is not None:
            ANCHORS.setdefault("trees", []).append([round(x), round(base), round(h), round(r), kind, seed])
        return
    g.ink.line([(x - 6, base), (x - 10, base - h * 0.55)], 10, amp=1.5)
    g.ink.line([(x + 6, base), (x + 2, base - h * 0.5)], 3, amp=1.0)
    if kind != "willow":
        g.ink.line([(x - 6, base - h * 0.42), (x - 60, base - h * 0.72)], 5, amp=1.4)
        g.ink.line([(x - 4, base - h * 0.5), (x + 52, base - h * 0.78)], 4, amp=1.4)
    cy = base - h + r * 0.7
    if kind == "willow":
        # 垂柳：几根弯下来的枝，枝上挂一绺一绺的柳条，没有轮廓线
        arms = []
        bx, by = x - 6, base - h * 0.55
        g.pen(color, 0.22).fill(ellipse_pts(x, by - r * 0.42, r * 1.15, r * 0.42))
        for i in range(7):
            ang = -math.pi / 2 + (i - 3) * 0.36 + rnd.uniform(-0.1, 0.1)
            L = r * rnd.uniform(0.75, 1.0)
            tx, ty = bx + math.sin(ang + math.pi / 2) * L * 1.1, by - L * 0.3 + abs(i - 3) * 22
            mid = (bx + (tx - bx) * 0.45, by - L * 0.45)
            g.ink.line([(bx, by), mid, ((mid[0] + tx) / 2, (mid[1] + ty) / 2 - 6), (tx, ty)], 3.0 if abs(i - 3) < 2 else 2.0, amp=1.0)
            arms.append((bx, by, tx, ty))
        for (bx, by, tx, ty) in arms:
            for k in range(11):
                t = 0.2 + 0.8 * k / 10
                sx = bx + (tx - bx) * t + rnd.uniform(-8, 8)
                sy = by + (ty - by) * t - (by - ty + 40) * 0.6 * 4 * t * (1 - t) * 0.5 - 4
                L = rnd.uniform(r * 0.7, r * 1.7) * (0.6 + 0.4 * t)
                sway = rnd.uniform(4, 16) * (1 if tx > bx else -1) * 0.5 + 6
                pts = [(sx + sway * (j / 6) ** 2, sy + L * j / 6) for j in range(7)]
                g.pen(color).line(pts, rnd.uniform(1.3, 2.3), amp=0.8)
                if rnd.random() < 0.5:
                    g.pen(color, 0.45).fill(ellipse_pts(sx + sway * 0.5, sy + L * 0.55, 5, L * 0.42))
    elif kind == "young":
        g.pen(color, 0.45).fill(ellipse_pts(x, cy + r * 0.3, r * 0.55, r * 0.8))
        g.pen(color).ellipse(x, cy + r * 0.3, r * 0.55, r * 0.8, lw=2.0)
        g.ink.line([(x - 10, cy + r * 1.0), (x - 40, base)], 1.8)
        g.ink.line([(x + 10, cy + r * 1.0), (x + 40, base)], 1.8)
    else:
        blobs = [(x + rnd.uniform(-r * 0.7, r * 0.7), cy + rnd.uniform(-r * 0.45, r * 0.3), r * rnd.uniform(0.45, 0.66)) for _ in range(9)]
        for bx, by, br in blobs:
            g.pen(color, 0.5).fill(circle_pts(bx, by, br))
        for bx, by, br in blobs:
            g.pen(color).arc(bx, by, br, math.pi * 0.9, math.pi * 1.9, lw=2.4)
        g.pen("ink", 0.2).fill(ellipse_pts(x + r * 0.2, cy + r * 0.32, r * 0.7, r * 0.25))
        for _ in range(14):
            lx, ly = x + rnd.uniform(-r * 0.8, r * 0.8), cy + rnd.uniform(-r * 0.5, r * 0.45)
            g.ink.arc(lx, ly, 7, 0.2, 2.6, lw=1.6)


def pole(g, x, base, h=640):
    g.ink.line([(x - 5, base), (x - 3, base - h)], 9, amp=0.6)
    g.ink.line([(x + 4, base), (x + 3, base - h)], 2, amp=0.4)
    g.ink.line([(x - 50, base - h + 30), (x + 50, base - h + 30)], 4)
    for dx in (-44, -16, 16, 44):
        g.ink.dot(x + dx, base - h + 26, 4)
    return base - h + 26


def wires(g, xs, y, sag=44, n=3):
    for a, b in zip(xs, xs[1:]):
        for k in range(n):
            yy = y + k * 8
            pts = [(a + (b - a) * t / 24, yy + sag * 4 * (t / 24) * (1 - t / 24) + k * 6) for t in range(25)]
            fline(g, "ink", pts, 1.5, 0.9)


def lamp(g, x, base, h=420, side=1):
    mark("street_lamp", x + 70 * side, base - h + 24)
    g.ink.line([(x, base), (x, base - h)], 6, amp=0.5)
    g.ink.line([(x, base - h), (x + 40 * side, base - h - 12), (x + 70 * side, base - h)], 4, amp=0.3)
    g.pen("ink").fill([(x + 54 * side, base - h), (x + 86 * side, base - h), (x + 80 * side, base - h + 14), (x + 60 * side, base - h + 14)])
    g.pen("mei", 0.12).fill([(x + 60 * side, base - h + 14), (x + 80 * side, base - h + 14), (x + 120 * side, base), (x + 20 * side, base)])
    g.ink.rect(x - 10, base - 30, 20, 30, lw=2)


def bench(g, x, base, w=150, color="qing", back=True):
    g.ink.line([(x - w / 2 + 12, base), (x - w / 2 + 14, base - 46)], 4)
    g.ink.line([(x + w / 2 - 12, base), (x + w / 2 - 14, base - 46)], 4)
    g.pen(color).fill(rect_pts(x - w / 2, base - 52, w, 10))
    g.ink.rect(x - w / 2, base - 52, w, 10, lw=2)
    if back:
        for k in range(2):
            g.pen(color).fill(rect_pts(x - w / 2 + 4, base - 92 + k * 20, w - 8, 9))
            g.ink.rect(x - w / 2 + 4, base - 92 + k * 20, w - 8, 9, lw=1.8)
        g.ink.line([(x - w / 2 + 14, base - 52), (x - w / 2 + 14, base - 96)], 3)
        g.ink.line([(x + w / 2 - 14, base - 52), (x + w / 2 - 14, base - 96)], 3)


def stool(g, x, base, color="ink", w=44, h=42):
    g.pen(color, 0.6).fill(rect_pts(x - w / 2, base - h, w, 8))
    g.ink.rect(x - w / 2, base - h, w, 8, lw=2)
    g.ink.line([(x - w / 2 + 6, base - h + 8), (x - w / 2 + 2, base)], 2.6)
    g.ink.line([(x + w / 2 - 6, base - h + 8), (x + w / 2 - 2, base)], 2.6)


def table(g, x, base, w=160, h=78, color="ink", d=0.35, cloth=None):
    g.pen(color, d).fill(rect_pts(x - w / 2, base - h, w, 12))
    g.ink.rect(x - w / 2, base - h, w, 12, lw=2.4)
    if cloth:
        g.pen(cloth, 0.4).fill([(x - w / 2 - 6, base - h), (x + w / 2 + 6, base - h), (x + w / 2 + 10, base - h + 34), (x - w / 2 - 10, base - h + 34)])
        g.pen(cloth).line([(x - w / 2 - 10, base - h + 34), (x + w / 2 + 10, base - h + 34)], 2)
    g.ink.line([(x - w / 2 + 12, base - h + 12), (x - w / 2 + 10, base)], 4)
    g.ink.line([(x + w / 2 - 12, base - h + 12), (x + w / 2 - 10, base)], 4)


def bicycle(g, x, base, facing=1, color="ink", s=1.6):
    r = 17 * s
    bx, fx = x - 28 * s * facing, x + 28 * s * facing
    for wx in (bx, fx):
        g.ink.circle(wx, base - r, r, lw=2.4)
        g.ink.dot(wx, base - r, 2.6)
    p = g.pen(color)
    seat = (x - 10 * s * facing, base - 44 * s)
    bar = (x + 18 * s * facing, base - 46 * s)
    crank = (x, base - r)
    p.line([(bx, base - r), seat, crank, (bx, base - r)], 3)
    p.line([seat, bar, crank], 3)
    p.line([bar, (fx, base - r)], 3)
    g.ink.line([(seat[0] - 8 * s, seat[1] - 3 * s), (seat[0] + 6 * s * facing, seat[1] - 3 * s)], 5)
    g.ink.line([(bar[0] - 2 * s * facing, bar[1] - 6 * s), (bar[0] + 8 * s * facing, bar[1] - 8 * s)], 3)


def ground_street(g, w, y=GROUND, road=True):
    """人行道 + 马路：路牙一道粗线，马路上淡墨网点和车道线。"""
    g.clear(rect_pts(-50, y, w + 100, BOTTOM - y + 60))
    g.pen("ink", 0.14).fill(rect_pts(-50, y, w + 100, 34))
    for x in range(0, int(w) + 60, 60):
        fline(g, "ink", [(x, y + 2), (x - 6, y + 34)], 1.2, 0.5)
    g.ink.line([(-50, y), (w + 50, y)], 4.5, amp=0.6)
    g.ink.line([(-50, y + 34), (w + 50, y + 34)], 3.0, amp=0.5)
    if road:
        g.pen("ink", 0.17).fill(rect_pts(-50, y + 40, w + 100, BOTTOM - y))
        for x in range(0, int(w) + 100, 180):
            g.clear(rect_pts(x, y + 132, 90, 8))
        fhatch(g, "ink", -50, y + 40, w + 100, BOTTOM - y, 80, 26, 0.8, 0.12)


def ground_floor(g, w, y=GROUND, color="ink", d=0.18, tiles=60):
    """屋里或院子的地：一道粗线，下面剖到的楼板。"""
    g.clear(rect_pts(-50, y, w + 100, BOTTOM - y + 60))
    g.pen(color, d).fill(rect_pts(-50, y, w + 100, 30))
    for x in range(0, int(w) + 60, tiles or 10**6):
        if tiles:
            fline(g, "ink", [(x, y + 2), (x, y + 30)], 1.1, 0.4)
    g.ink.line([(-50, y), (w + 50, y)], 4.5, amp=0.6)
    slab(g, -50, w + 50, y + 30, y + 80)
    g.pen("ink", 0.05).fill(rect_pts(-50, y + 80, w + 100, BOTTOM - y))


def slab(g, x0, x1, y0, y1):
    """剖到的楼板：墨网点 + 45° 排线 + 上下两道粗线。"""
    g.clear(rect_pts(x0, y0, x1 - x0, y1 - y0))
    g.pen("ink", 0.24).fill(rect_pts(x0, y0, x1 - x0, y1 - y0))
    fhatch(g, "ink", x0, y0, x1 - x0, y1 - y0, 45, 9, 1.2, 0.9)
    g.ink.line([(x0, y0), (x1, y0)], 3.4, amp=0.4)
    g.ink.line([(x0, y1), (x1, y1)], 3.4, amp=0.4)


def cut_wall(g, x, y0, y1, w=28, color="mei"):
    pts = rect_pts(x - w / 2, y0, w, y1 - y0)
    g.clear(pts)
    g.pen(color, 0.62).fill(pts)
    fbricks(g, x - w / 2, y0, w, y1 - y0, 16, 8, 0.7, 0.35, seed=int(x))
    g.ink.rect(x - w / 2, y0, w, y1 - y0, lw=2.6, amp=0.4)


def radiator(g, x, base, n=9, h=70):
    for i in range(n):
        g.pen("ink", 0.12).fill(rect_pts(x + i * 12, base - h, 9, h))
        g.ink.rect(x + i * 12, base - h, 9, h, lw=1.4, amp=0.2)
    g.ink.line([(x - 6, base - h + 8), (x + n * 12 + 2, base - h + 8)], 2.0)
    g.ink.line([(x - 6, base - 8), (x + n * 12 + 2, base - 8)], 2.0)


def bulb(g, x, top, L=120, lit=True):
    mark("hall_lamp", x, top + L + 22)
    g.ink.line([(x, top), (x, top + L)], 1.6, amp=0.2)
    g.pen("ink").fill(rect_pts(x - 6, top + L, 12, 10))
    g.ink.circle(x, top + L + 22, 12, lw=2)
    if lit:
        g.pen("mei", 0.18).fill(circle_pts(x, top + L + 22, 11))
        g.pen("mei", 0.06).fill([(x - 14, top + L + 30), (x + 14, top + L + 30), (x + 150, top + L + 380), (x - 150, top + L + 380)])
    g.ink.line([(x + 8, top + L + 6), (x + 22, top + L + 70)], 1.0, amp=0.2, dash=[4, 4])


def frame_pic(g, x, y, w, h, color="qing", inner="hill"):
    g.clear(rect_pts(x, y, w, h))
    g.ink.rect(x, y, w, h, lw=2.4, amp=0.3)
    g.ink.rect(x + 6, y + 6, w - 12, h - 12, lw=1.2, amp=0.2)
    if inner == "hill":
        g.pen(color, 0.4).fill([(x + 8, y + h - 8), (x + w * 0.4, y + h * 0.4), (x + w * 0.65, y + h * 0.65), (x + w * 0.8, y + h * 0.5), (x + w - 8, y + h - 8)])
    elif inner == "two":
        for k, c in enumerate(("qing", "mei")):
            cx = x + w * (0.35 + k * 0.3)
            g.pen(c, 0.5).fill(circle_pts(cx, y + h * 0.42, w * 0.1))
            g.pen(c, 0.5).fill(ellipse_pts(cx, y + h * 0.8, w * 0.16, h * 0.2))


def clock(g, x, y, r=26):
    g.clear(circle_pts(x, y, r))
    g.ink.circle(x, y, r, lw=2.6)
    g.ink.line([(x, y), (x, y - r * 0.6)], 2.4)
    g.ink.line([(x, y), (x + r * 0.45, y + r * 0.2)], 2.4)
    for k in range(12):
        a = k * math.tau / 12
        g.ink.dot(x + math.cos(a) * r * 0.8, y + math.sin(a) * r * 0.8, 1.4)


def calendar(g, x, y, color="mei"):
    g.clear(rect_pts(x, y, 56, 74))
    g.pen(color).fill(rect_pts(x, y, 56, 20))
    g.ink.rect(x, y, 56, 74, lw=2)
    for r in range(3):
        for c in range(4):
            g.ink.dot(x + 10 + c * 12, y + 32 + r * 13, 2)


def stairs_down(g, x0, x1, y0, y1, steps=8, rail=True):
    """往下去的一跑楼梯（从左上到右下）。"""
    sw = (x1 - x0) / steps
    sh = (y1 - y0) / steps
    pts = [(x0, y0)]
    for i in range(steps):
        pts += [(x0 + i * sw, y0 + (i + 1) * sh), (x0 + (i + 1) * sw, y0 + (i + 1) * sh)]
    pts += [(x1, y1 + 30), (x0, y0 + 30)]
    g.clear(pts)
    g.pen("ink", 0.16).fill(pts)
    g.ink.poly(pts, 2.4, amp=0.4)
    if rail:
        g.ink.line([(x0 + 10, y0 - 90), (x1 + 10, y1 - 90)], 3, amp=0.3)
        for i in range(0, steps + 1, 2):
            px = x0 + 10 + i * sw
            py = y0 + i * sh
            g.ink.line([(px, py + sh), (px, py - 90)], 1.6)


def ladder_up(g, x, y_bottom, y_top, w=70):
    g.ink.line([(x - w / 2, y_bottom), (x - w / 2 + 30, y_top)], 4)
    g.ink.line([(x + w / 2, y_bottom), (x + w / 2 + 30, y_top)], 4)
    n = int((y_bottom - y_top) / 34)
    for i in range(1, n):
        t = i / n
        yy = y_bottom - (y_bottom - y_top) * t
        g.ink.line([(x - w / 2 + 30 * t, yy), (x + w / 2 + 30 * t, yy)], 3)


def fence(g, x0, x1, base, h=110, gap=26, color="ink"):
    g.pen(color).line([(x0, base - h + 14), (x1, base - h + 14)], 3, amp=0.3)
    g.pen(color).line([(x0, base - 18), (x1, base - 18)], 3, amp=0.3)
    x = x0
    while x <= x1:
        g.pen(color).line([(x, base), (x, base - h)], 2.4, amp=0.2)
        g.pen(color).fill([(x - 5, base - h), (x, base - h - 12), (x + 5, base - h)])
        x += gap


def railing(g, x0, x1, base, h=110, post=130, color="ink", d=None):
    x = x0
    while x <= x1 + 1:
        g.pen(color).rect(x - 9, base - h - 6, 18, h + 6, lw=2.4, amp=0.3)
        g.pen(color, 0.4).fill(rect_pts(x - 9, base - h - 6, 18, h + 6))
        x += post
    for yy in (base - h + 8, base - h * 0.5, base - 16):
        g.pen(color).line([(x0, yy), (x1, yy)], 3.0, amp=0.4)


def water(g, x0, x1, y0, y1, seed=5):
    rnd = random.Random(seed)
    g.clear(rect_pts(x0, y0, x1 - x0, y1 - y0))
    g.pen("qing", 0.42).fill(rect_pts(x0, y0, x1 - x0, y1 - y0))
    g.pen("qing", 0.22).fill(rect_pts(x0, y0, x1 - x0, (y1 - y0) * 0.3))
    for i in range(int((x1 - x0) * (y1 - y0) / 9000)):
        x = rnd.uniform(x0, x1)
        y = rnd.uniform(y0 + 6, y1 - 6)
        L = rnd.uniform(30, 110) * (0.5 + (y - y0) / (y1 - y0))
        g.qing.line([(x, y), (x + L, y)], rnd.uniform(1.6, 3.0), amp=0.6)
    for i in range(int((x1 - x0) / 140)):
        x = rnd.uniform(x0, x1)
        y = rnd.uniform(y0 + 10, y1 - 10)
        g.clear(rect_pts(x, y, rnd.uniform(20, 60), 3), colors=["qing"])


# ----------------------------------------------------------------------
# 屋里的家具（侧面）
# ----------------------------------------------------------------------

def bed(g, x, base, w=300, facing=1, quilt="qing"):
    head = x - w / 2 if facing > 0 else x + w / 2
    foot = x + w / 2 if facing > 0 else x - w / 2
    # 床头板
    hx = head - 10 * facing
    g.ink.rect(min(hx, hx + 20 * facing), base - 170, 20, 170, lw=2.6)
    g.pen("ink", 0.4).fill(rect_pts(min(hx, hx + 20 * facing), base - 170, 20, 170))
    g.ink.line([(foot, base), (foot, base - 80)], 5)
    g.pen("ink", 0.25).fill(rect_pts(min(head, foot), base - 70, w, 26))
    g.ink.rect(min(head, foot), base - 70, w, 26, lw=2.4)
    g.ink.line([(min(head, foot) + 10, base - 44), (min(head, foot) + 10, base)], 4)
    g.ink.line([(max(head, foot) - 10, base - 44), (max(head, foot) - 10, base)], 4)
    # 被子：鼓起来的一卷，上面印花
    q = [(min(head, foot) + (60 if facing > 0 else 0), base - 70)]
    x0 = min(head, foot) + (60 if facing > 0 else 0)
    x1 = max(head, foot) - (0 if facing > 0 else 60)
    q = [(x0, base - 70), (x0 + 10, base - 104), (x0 + (x1 - x0) * 0.5, base - 116), (x1 - 6, base - 104), (x1 + 6, base - 60), (x1 + 4, base - 40), (x0, base - 66)]
    g.clear(q)
    g.pen(quilt, 0.5).fill(q)
    g.pen(quilt).poly(q, 2.4, amp=0.6)
    rnd = random.Random(int(x))
    for _ in range(9):
        fx, fy = rnd.uniform(x0 + 16, x1 - 16), rnd.uniform(base - 104, base - 76)
        g.pen(quilt).circle(fx, fy, 5, lw=1.6)
    # 枕头
    px = head + 40 * facing
    g.clear(ellipse_pts(px, base - 80, 34, 14))
    g.pen("ink", 0.08).fill(ellipse_pts(px, base - 80, 34, 14))
    g.ink.ellipse(px, base - 80, 34, 14, lw=2)


def wardrobe(g, x, base, w=150, h=290, color="ink"):
    g.clear(rect_pts(x - w / 2, base - h, w, h))
    g.pen(color, 0.3).fill(rect_pts(x - w / 2, base - h, w, h))
    g.ink.rect(x - w / 2, base - h, w, h, lw=2.8, amp=0.4)
    for k in range(4):
        yy = base - h + 20 + k * (h - 40) / 4
        g.ink.rect(x - w / 2 + 10, yy, w - 20, (h - 40) / 4 - 10, lw=1.6, amp=0.3)
        g.ink.dot(x, yy + (h - 40) / 8 - 5, 3.4)
    g.ink.line([(x - w / 2 + 10, base), (x - w / 2 + 10, base + 2)], 4)


def desk(g, x, base, w=200, lamp_side=1, books=True, color="ink"):
    g.pen(color, 0.32).fill(rect_pts(x - w / 2, base - 96, w, 14))
    g.ink.rect(x - w / 2, base - 96, w, 14, lw=2.6)
    g.pen(color, 0.2).fill(rect_pts(x + (w / 2 - 70) * lamp_side - 30, base - 82, 60, 82))
    g.ink.rect(x + (w / 2 - 70) * lamp_side - 30, base - 82, 60, 82, lw=2.2)
    g.ink.line([(x - (w / 2 - 12) * lamp_side, base - 82), (x - (w / 2 - 12) * lamp_side, base)], 4)
    lx = x - (w / 2 - 40) * lamp_side
    g.ink.line([(lx, base - 96), (lx, base - 160), (lx + 34 * lamp_side, base - 186)], 3)
    g.pen("qing").fill([(lx + 20 * lamp_side, base - 196), (lx + 56 * lamp_side, base - 180), (lx + 48 * lamp_side, base - 166), (lx + 14 * lamp_side, base - 182)])
    if books:
        bx = x + 6
        for k, (bw, bh, c) in enumerate(((14, 50, "mei"), (12, 44, "qing"), (16, 56, "ink"), (12, 40, "mei"))):
            g.pen(c, 0.5).fill(rect_pts(bx, base - 96 - bh, bw, bh))
            g.ink.rect(bx, base - 96 - bh, bw, bh, lw=1.4)
            bx += bw + 2
    # 椅子
    cx = x - 20 * lamp_side
    g.ink.line([(cx - 24, base), (cx - 24, base - 50), (cx + 24, base - 50), (cx + 24, base)], 3)
    g.ink.line([(cx + 24 * -lamp_side, base - 50), (cx + 26 * -lamp_side, base - 120)], 3.4)


def round_table(g, x, base, w=190, cloth="mei", stools="side"):
    """饭桌：暖壶、茶杯。stools="side" 两只凳子摆在两头，"under" 塞在桌子底下（屋里挤，桌边要让给别的家具）。"""
    table(g, x, base, w, 82, cloth=cloth)
    # 暖壶、茶杯
    tx = x - 40
    g.clear(rect_pts(tx - 13, base - 140, 26, 58))
    g.pen("mei" if cloth == "qing" else "qing", 0.55).fill(rect_pts(tx - 13, base - 140, 26, 58))
    g.ink.rect(tx - 13, base - 140, 26, 58, lw=2)
    g.ink.rect(tx - 8, base - 150, 16, 10, lw=1.8)
    g.ink.rect(x + 20, base - 104, 18, 22, lw=1.8)
    g.ink.rect(x + 46, base - 102, 16, 20, lw=1.8)
    if stools == "under":
        stool(g, x - w * 0.24, base)
        stool(g, x + w * 0.24, base)
    else:
        stool(g, x - w / 2 - 30, base)
        stool(g, x + w / 2 + 30, base)


def basin_stand(g, x, base, color="qing"):
    g.ink.line([(x - 30, base), (x - 20, base - 120)], 3)
    g.ink.line([(x + 30, base), (x + 20, base - 120)], 3)
    g.ink.line([(x, base), (x, base - 120)], 3)
    g.ink.line([(x - 24, base - 120), (x + 24, base - 120)], 3)
    g.ink.line([(x + 20, base - 120), (x + 20, base - 260)], 3)
    g.clear([(x - 44, base - 128), (x + 44, base - 128), (x + 32, base - 104), (x - 32, base - 104)])
    g.pen(color, 0.4).fill([(x - 44, base - 128), (x + 44, base - 128), (x + 32, base - 104), (x - 32, base - 104)])
    g.ink.poly([(x - 44, base - 128), (x + 44, base - 128), (x + 32, base - 104), (x - 32, base - 104)], 2.4)
    g.pen("mei").line([(x - 40, base - 124), (x + 40, base - 124)], 2.2)
    # 毛巾、镜子
    g.pen(color, 0.5).fill(rect_pts(x + 14, base - 250, 12, 66))
    g.clear(ellipse_pts(x - 6, base - 300, 36, 44))
    g.ink.ellipse(x - 6, base - 300, 36, 44, lw=2.6)
    g.qing.line([(x - 24, base - 312), (x - 12, base - 326)], 1.8)
    # 暖瓶
    g.ink.rect(x - 60, base - 70, 22, 70, lw=2)


# ----------------------------------------------------------------------
# 各张图
# ----------------------------------------------------------------------

def draw_building(g, sc):
    W = sc["width"]
    roof, floor3 = sc["floors"]  # 260, 720
    sp, ex = sc["spots"], sc["exits"]
    ceil = roof + 60
    sky(g, W, seed=11, horizon=roof, clouds=6)
    skyline(g, -40, W + 40, roof - 10, seed=4, hmin=50, hmax=200, d=0.12, chimneys=[(520, 300)], towers=[(2700, 170)])
    # 楼顶平台：女儿墙、鸽子棚、晾衣绳、水箱、天线
    hut_x = ex["roof_down"][0]
    # 楼梯间小屋
    g.clear(rect_pts(hut_x - 90, roof - 250, 190, 250))
    g.pen("mei", 0.5).fill(rect_pts(hut_x - 90, roof - 250, 190, 250))
    fbricks(g, hut_x - 90, roof - 250, 190, 250, seed=7)
    g.ink.rect(hut_x - 90, roof - 250, 190, 250, lw=3)
    slab(g, hut_x - 104, hut_x + 114, roof - 268, roof - 248)
    door(g, hut_x, roof, 96, 204, open_=0.55)
    # 鸽子棚
    px = sp["roof_pigeon"]
    coop = [(px - 120, roof), (px - 120, roof - 150), (px - 140, roof - 150), (px, roof - 220), (px + 140, roof - 150), (px + 120, roof - 150), (px + 120, roof)]
    g.clear(coop)
    g.pen("ink", 0.12).fill(coop)
    g.ink.poly(coop, 2.8)
    for k in range(5):
        fline(g, "ink", [(px - 110 + k * 48, roof - 140), (px - 110 + k * 48, roof - 4)], 1.4, 0.8)
    for r in range(2):
        for c in range(3):
            g.ink.rect(px - 96 + c * 66, roof - 130 + r * 56, 48, 40, lw=2)
            g.pen("ink", 0.4).fill(ellipse_pts(px - 72 + c * 66, roof - 104 + r * 56, 10, 9))
    for k, (dx, dy) in enumerate(((-40, -232), (10, -244), (70, -228))):
        g.ink.arc(px + dx, roof + dy, 10, math.pi * 1.1, math.pi * 1.9, lw=2)
    # 晾衣绳
    l0, l1 = 1430, 2120
    for lx in (l0, l1):
        g.ink.line([(lx, roof), (lx, roof - 200)], 4)
    rope = [(l0 + (l1 - l0) * t / 30, roof - 190 + 30 * 4 * (t / 30) * (1 - t / 30)) for t in range(31)]
    fline(g, "ink", rope, 1.6)
    rnd = random.Random(21)
    x = l0 + 30
    while x < l1 - 60:
        t = (x - l0) / (l1 - l0)
        yy = roof - 190 + 30 * 4 * t * (1 - t)
        w = rnd.uniform(60, 110)
        c = rnd.choice(["qing", "mei", "ink"])
        sh = [(x, yy), (x + w, yy + 2), (x + w + 4, yy + rnd.uniform(70, 120)), (x - 2, yy + rnd.uniform(70, 120))]
        g.clear(sh)
        g.pen(c, 0.35 if c != "ink" else 0.12).fill(sh)
        g.pen(c if c != "ink" else "ink").poly(sh, 2.0, amp=0.8)
        if rnd.random() < 0.5:
            for k in range(4):
                fline(g, c, [(x + 8 + k * w / 4, yy + 6), (x + 6 + k * w / 4, yy + 66)], 1.0, 0.8)
        x += w + rnd.uniform(16, 40)
    # 水箱、天线
    g.ink.rect(2330, roof - 170, 160, 120, lw=3)
    g.pen("ink", 0.2).fill(rect_pts(2330, roof - 170, 160, 120))
    for k in range(4):
        g.ink.line([(2350 + k * 40, roof - 50), (2346 + k * 40, roof)], 3)
    for ax in (620, 2860):
        g.ink.line([(ax, roof), (ax, roof - 230)], 3)
        for k in range(4):
            g.ink.line([(ax - 50 + k * 8, roof - 210 + k * 26), (ax + 50 - k * 8, roof - 210 + k * 26)], 2)
    # 凉席卷、花盆
    for fx in (1080, 1130):
        g.pen("mei", 0.55).fill(rect_pts(fx - 18, roof - 44, 36, 44))
        g.ink.rect(fx - 18, roof - 44, 36, 44, lw=2)
        g.pen("qing").line([(fx, roof - 44), (fx - 14, roof - 86)], 2.4)
        g.pen("qing").line([(fx, roof - 44), (fx + 12, roof - 80)], 2.4)
    # 女儿墙：平台外头那两截矮墙
    for x0, x1 in ((-30, 980), (2220, W + 30)):
        g.clear(rect_pts(x0, roof - 70, x1 - x0, 70))
        g.pen("mei", 0.55).fill(rect_pts(x0, roof - 70, x1 - x0, 70))
        fbricks(g, x0, roof - 70, x1 - x0, 70, seed=3)
        g.ink.rect(x0, roof - 70, x1 - x0, 70, lw=2.6)
    # 平台两头的矮栏
    for x in (990, 2210):
        g.ink.line([(x, roof), (x, roof - 100)], 3)
    # 楼顶楼板（剖切）
    slab(g, -40, W + 40, roof, ceil)
    # 三楼屋里：两家 + 楼道
    hq, hl, hm = sc["zones"]["home_qing"], sc["zones"]["hallway"], sc["zones"]["home_mei"]
    for z, accent in ((hq, "qing"), (hm, "mei")):
        x0, x1 = z["span"]
        room(g, x0, x1, ceil, floor3, accent)
    hallway(g, sc, hl["span"][0], hl["span"][1], ceil, floor3)
    home(g, sc, "qing", hq["span"], ceil, floor3)
    home(g, sc, "mei", hm["span"], ceil, floor3)
    # 外墙和分户墙（剖到的红砖）
    for x in (0, W):
        cut_wall(g, x, ceil, floor3, 36)
    # 三楼地板 + 二楼（下头淡淡的一截邻居家）
    slab(g, -40, W + 40, floor3, floor3 + 50)
    g.ink.line([(-40, floor3), (W + 40, floor3)], 5, amp=0.5)
    downstairs(g, sc, floor3 + 50)
    # 楼梯：楼道里往下一跑，往上一架铁梯
    dx = ex["hall_down"][0]
    g.clear(rect_pts(dx - 70, floor3 - 2, 230, 54))
    g.pen("ink", 0.5).fill(rect_pts(dx - 70, floor3, 230, 52))
    stairs_down(g, dx - 70, dx + 220, floor3, BOTTOM + 40, steps=9)
    ux = ex["hall_up"][0]
    g.clear(rect_pts(ux - 40, roof, 110, 60))
    g.pen("ink", 0.5).fill(rect_pts(ux - 40, roof, 110, 60))
    ladder_up(g, ux - 10, floor3, roof + 10)


def room(g, x0, x1, top, base, accent):
    """一间屋的后墙：上白下绿（墙裙），挂镜线。"""
    g.clear(rect_pts(x0, top, x1 - x0, base - top))
    wain = base - 150
    g.pen("qing", 0.30).fill(rect_pts(x0, wain, x1 - x0, base - wain))
    g.ink.line([(x0, wain), (x1, wain)], 2.6, amp=0.4)
    g.ink.line([(x0, top + 40), (x1, top + 40)], 1.6, amp=0.3)
    # 墙纸：淡淡的小花
    rnd = random.Random(int(x0) + 5)
    for yy in range(int(top + 70), int(wain - 20), 60):
        for xx in range(int(x0 + 30 + (yy // 60 % 2) * 30), int(x1 - 20), 60):
            g.pen(accent, 0.22).fill(circle_pts(xx, yy, 4))
    # 踢脚线
    g.pen("ink", 0.4).fill(rect_pts(x0, base - 14, x1 - x0, 14))
    del rnd


def home(g, sc, role, span, top, base):
    sp = sc["spots"]
    x0, x1 = span
    face = 1 if role == "qing" else -1
    s = lambda k: sp[f"{k}_{role}"] if f"{k}_{role}" in sp else sp[f"bed_{role}"] + 175 * face  # noqa: E731
    accent = role
    other = "mei" if role == "qing" else "qing"
    # 窗：书桌上头一扇，饭桌后头一扇
    for wx in (s("desk"), s("table")):
        window(g, wx - 110, top + 80, 220, 170, panes=3, curtain=accent, night=True)
    bed(g, s("bed"), base, 300, face, quilt=accent)
    wardrobe(g, s("corner"), base, 140, 300)
    # 五斗柜上立着一个相框，靠床那头；靠书桌那头空着，收音机（家里的东西那一层，tools/art/home.py）摆那儿
    cx = s("corner")
    frame_pic(g, cx - 62 if face > 0 else cx - 2, base - 300 - 60, 64, 60, accent, "two")
    desk(g, s("desk"), base, 210, face, color="ink")
    # 凳子塞在饭桌底下：桌子两边让给缝纫机 / 沙发 / 布帘子和电视柜（home.py）。墙上的钟也归那一层：清贫人家没有
    round_table(g, s("table"), base, 180, cloth=other, stools="under")
    basin_stand(g, s("basin"), base, color=accent)
    calendar(g, s("desk") + 130 * face, top + 70, accent)
    # 屋顶吊灯
    g.ink.line([(s("table"), top), (s("table"), top + 60)], 1.6)
    g.clear(ellipse_pts(s("table"), top + 70, 30, 12))
    g.pen(accent, 0.6).fill([(s("table") - 30, top + 74), (s("table") + 30, top + 74), (s("table") + 18, top + 58), (s("table") - 18, top + 58)])
    # 分户墙：门洞在楼道那一侧，墙上只留门楣
    wall_x = x1 if role == "qing" else x0
    cut_wall(g, wall_x, top, base - 260, 30)
    g.ink.line([(wall_x - 15, base - 260), (wall_x + 15, base - 260)], 3)
    g.ink.line([(wall_x - 15, base - 260), (wall_x - 15, base)], 3)
    g.ink.line([(wall_x + 15, base - 260), (wall_x + 15, base)], 3)


def hallway(g, sc, x0, x1, top, base):
    sp, ex = sc["spots"], sc["exits"]
    g.clear(rect_pts(x0, top, x1 - x0, base - top))
    g.pen("ink", 0.09).fill(rect_pts(x0, top, x1 - x0, base - top))
    wain = base - 150
    g.pen("qing", 0.34).fill(rect_pts(x0, wain, x1 - x0, base - wain))
    g.ink.line([(x0, wain), (x1, wain)], 2.6, amp=0.4)
    # 两扇门牌：301 青家、302 梅家，门扇开着靠在墙上
    for spot, plate, color, side in (("door_qing", "301", "qing", 1), ("door_mei", "302", "mei", -1)):
        dx = sp[spot]
        leaf = rect_pts(dx - 36, base - 230, 72, 230)
        g.clear(leaf)
        g.pen(color, 0.45).fill(leaf)
        g.ink.rect(dx - 36, base - 230, 72, 230, lw=2.6)
        g.ink.rect(dx - 26, base - 214, 52, 80, lw=1.6)
        g.ink.rect(dx - 26, base - 116, 52, 90, lw=1.6)
        g.clear(rect_pts(dx - 24, base - 290, 48, 26))
        g.pen(color).fill(rect_pts(dx - 24, base - 290, 48, 26))
        knock(g, color, plate, dx, base - 277, 18)
        # 春联的位置：两道淡红
        g.pen("mei", 0.3).fill(rect_pts(dx - 62, base - 240, 16, 160))
    # 电表箱、值日表
    g.clear(rect_pts(1560, top + 60, 120, 90))
    g.ink.rect(1560, top + 60, 120, 90, lw=2.4)
    for k in range(3):
        g.ink.circle(1590 + k * 30, top + 96, 10, lw=1.6)
    g.ink.line([(1620, top + 150), (1620, top + 190), (1640, top + 200)], 1.6)
    # 拉线灯、暖气、小板凳
    bulb(g, 1640, top, 90)
    radiator(g, 1330, base - 30, 7, 60)
    stool(g, sp["hall_stool"], base, "qing", 50, 46)
    # 堆东西的那一角（随年代换的东西由街景层叠在这儿，底图只画一块旧木板）
    g.ink.line([(1360, base), (1440, base - 90)], 4)
    g.pen("ink", 0.2).fill([(1350, base), (1358, base - 6), (1438, base - 94), (1446, base - 88), (1368, base)])
    # 楼梯口上头的字
    g.pen("ink", 0.7).text("↓", ex["hall_down"][0] + 60, base - 300, 28)


def downstairs(g, sc, top):
    """二楼：只露出一截，墨色很淡——楼下也住着人。"""
    W = sc["width"]
    g.clear(rect_pts(-40, top, W + 80, BOTTOM - top + 40))
    g.pen("ink", 0.10).fill(rect_pts(-40, top, W + 80, BOTTOM - top + 40))
    for x0 in (180, 860, 2240, 2820):
        g.pen("ink", 0.14).fill(rect_pts(x0, top + 70, 200, 170))
        g.ink.rect(x0, top + 70, 200, 170, lw=1.6, density=0.5)
        g.ink.line([(x0 + 100, top + 70), (x0 + 100, top + 240)], 1.2, density=0.5)
    for lx in (520, 2560):
        g.ink.line([(lx, top), (lx, top + 50)], 1.2, density=0.5)
        g.pen("mei", 0.12).fill(circle_pts(lx, top + 62, 12))
    for x in (0, W):
        cut_wall(g, x, top, BOTTOM + 40, 36)


def draw_street(g, sc):
    W = sc["width"]
    sp, ex, zs = sc["spots"], sc["exits"], sc["zones"]
    sky(g, W, seed=5, horizon=200)
    skyline(g, -40, W + 40, 60, seed=9, hmin=40, hmax=160, d=0.10)
    shop_top = GROUND - 300
    # 楼：一层门脸，上头两三层住家
    # 楼压低一截：屋顶在镜头里，后面的天、中景的屋顶、远处的城透出来
    blocks = [
        (-40, 820, 290, "mei", 0.5, 1),
        (820, 1330, 330, "ink", 0.18, 1),
        (1330, 2440, 262, "mei", 0.58, 1),
        (2440, 3070, 318, "mei", 0.42, 1),
        (3070, 3830, 350, "ink", 0.14, 1),
    ]
    for i, (x0, x1, top, col, d, rows) in enumerate(blocks):
        facade(g, x0, x1, top, shop_top, col, d, rows, (66, 86), 64, brick=col == "mei", seed=40 + i)
        roof_clutter(g, x0, x1, top - 14, seed=60 + i, pigeons=i == 2)
    # 街尾：往河那边去，楼没了，一排柳
    g.pen("qing", 0.10).fill(rect_pts(3830, 300, W - 3790, GROUND - 300))
    tree(g, 3930, GROUND, 560, 140, "willow", seed=3)
    # 一层的门脸：每一段一个店
    for zid, z in zs.items():
        x0, x1 = z["span"]
        g.clear(rect_pts(x0, shop_top, x1 - x0, GROUND - shop_top))
        g.pen("ink", 0.10).fill(rect_pts(x0, shop_top, x1 - x0, GROUND - shop_top))
        g.ink.line([(x0, shop_top), (x1, shop_top)], 4)
        g.ink.line([(x0, shop_top), (x0, GROUND)], 3)
    breakfast(g, sp, zs["breakfast"]["span"], shop_top)
    shop(g, sp, zs["shop"]["span"], shop_top)
    alley(g, sp, ex, zs["alley"]["span"], shop_top)
    bikeshop(g, sp, ex, zs["bikeshop"]["span"], shop_top)
    teahouse(g, sp, zs["teahouse"]["span"], shop_top, ex)
    # 最左头的路口：去小学
    g.clear(rect_pts(-40, shop_top - 80, 250, GROUND - shop_top + 80))
    g.pen("ink", 0.28).fill(rect_pts(-40, shop_top - 80, 250, GROUND - shop_top + 80))
    fhatch(g, "ink", -40, shop_top - 80, 250, GROUND - shop_top + 80, 30, 14, 1.0, 0.4)
    g.ink.line([(210, shop_top - 80), (210, GROUND)], 3.4)
    g.ink.line([(-40, shop_top - 80), (210, shop_top - 80)], 3.4)
    # 电线杆和电线
    poles = [300, 1100, 1960, 2800, 3620]
    tops = [pole(g, x, GROUND + 18, 700) for x in poles]
    wires(g, poles, tops[0] + 2, 50, 3)
    lamp(g, 1260, GROUND + 18, 460, 1)
    lamp(g, 3020, GROUND + 18, 460, -1)
    ground_street(g, W)
    # 马路上的井盖
    for mx in (980, 2600):
        g.ink.ellipse(mx, GROUND + 76, 46, 8, lw=2.4)


def breakfast(g, sp, span, top):
    x0, x1 = span
    awning(g, x0 + 10, x1 - 10, top + 6, 54, "mei")
    signboard(g, (x0 + x1) / 2, top - 46, "早点", "mei", 46)
    sx = sp["breakfast_stall"]
    # 灶台、鏊子、一摞笼屉、热气
    g.clear(rect_pts(sx - 110, GROUND - 100, 220, 100))
    g.pen("ink", 0.3).fill(rect_pts(sx - 110, GROUND - 100, 220, 100))
    fbricks(g, sx - 110, GROUND - 100, 220, 100, 26, 10, seed=8)
    g.ink.rect(sx - 110, GROUND - 100, 220, 100, lw=2.8)
    g.ink.ellipse(sx - 40, GROUND - 108, 64, 10, lw=3)
    g.pen("ink", 0.6).fill(ellipse_pts(sx - 40, GROUND - 108, 60, 8))
    for k in range(4):
        g.clear(rect_pts(sx + 36, GROUND - 130 - k * 26, 70, 24))
        g.pen("qing", 0.32).fill(rect_pts(sx + 36, GROUND - 130 - k * 26, 70, 24))
        g.ink.rect(sx + 36, GROUND - 130 - k * 26, 70, 24, lw=2)
    for k in range(3):
        cx = sx - 50 + k * 30
        g.ink.line([(cx, GROUND - 130), (cx - 10, GROUND - 170), (cx + 6, GROUND - 210), (cx - 4, GROUND - 250)], 1.6, amp=2.0, density=0.5)
    # 价钱牌（字留给街景层）
    g.clear(rect_pts(sx - 220, top + 90, 90, 130))
    g.ink.rect(sx - 220, top + 90, 90, 130, lw=2.4)
    for k in range(4):
        g.ink.line([(sx - 210, top + 116 + k * 26), (sx - 150, top + 116 + k * 26)], 2, density=0.5)
    # 铺子里头：门帘、案板
    g.pen("ink", 0.3).fill(rect_pts(x0 + 40, top + 80, 120, GROUND - top - 80))
    for k in range(6):
        fline(g, "qing", [(x0 + 46 + k * 20, top + 80), (x0 + 46 + k * 20, GROUND - 40)], 4, 0.8)
    # 外头的小桌、马扎
    table(g, x1 - 130, GROUND, 120, 64)
    stool(g, x1 - 200, GROUND, "mei", 34, 32)
    stool(g, x1 - 60, GROUND, "mei", 34, 32)


def shop(g, sp, span, top):
    x0, x1 = span
    signboard(g, (x0 + x1) / 2, top - 46, "小卖部", "qing", 42)
    # 玻璃柜台 + 后头货架
    for r in range(3):
        g.ink.line([(x0 + 30, top + 70 + r * 70), (x1 - 30, top + 70 + r * 70)], 2.6)
        rnd = random.Random(r + 3)
        x = x0 + 40
        while x < x1 - 60:
            w = rnd.uniform(18, 34)
            h = rnd.uniform(26, 56)
            c = rnd.choice(["mei", "qing", "ink", "mei"])
            g.pen(c, 0.5).fill(rect_pts(x, top + 70 + r * 70 - h, w, h))
            g.ink.rect(x, top + 70 + r * 70 - h, w, h, lw=1.4)
            x += w + 6
    cx0, cx1 = x0 + 40, x0 + 300
    g.clear(rect_pts(cx0, GROUND - 120, cx1 - cx0, 120))
    g.pen("qing", 0.18).fill(rect_pts(cx0, GROUND - 120, cx1 - cx0, 70))
    g.pen("ink", 0.3).fill(rect_pts(cx0, GROUND - 50, cx1 - cx0, 50))
    g.ink.rect(cx0, GROUND - 120, cx1 - cx0, 120, lw=2.8)
    g.qing.line([(cx0 + 20, GROUND - 100), (cx0 + 70, GROUND - 116)], 2)
    for k in range(5):
        g.pen(random.Random(k).choice(["mei", "qing"]), 0.6).fill(circle_pts(cx0 + 40 + k * 46, GROUND - 76, 10))
    # 冰柜
    g.clear(rect_pts(cx1 + 30, GROUND - 110, 130, 110))
    g.pen("qing", 0.4).fill(rect_pts(cx1 + 30, GROUND - 110, 130, 110))
    g.ink.rect(cx1 + 30, GROUND - 110, 130, 110, lw=2.8)
    g.ink.line([(cx1 + 30, GROUND - 90), (cx1 + 160, GROUND - 90)], 2)
    knock(g, "qing", "冰", cx1 + 95, GROUND - 50, 34)
    # 门口的长凳
    bench(g, 1220, GROUND, 150, "mei", back=False)


def alley(g, sp, ex, span, top):
    x0, x1 = span
    up = ex["upstairs"][0]
    # 小卖部和我们那栋楼中间一条窄胡同，钻过去是早市（清贫人家的孩子天不亮就往那儿去）
    mx = ex.get("to_market", (1390.0, GROUND))[0]
    lane(g, mx, top + 40, 110)
    for k in (-1, 1):
        g.ink.line([(mx + k * 26, top - 40), (mx + k * 26, top - 12)], 1.2, amp=0.1)
    g.clear(rect_pts(mx - 34, top - 12, 68, 34))
    g.pen("mei", 0.08).fill(rect_pts(mx - 34, top - 12, 68, 34))
    g.ink.rect(mx - 34, top - 12, 68, 34, lw=2.0, amp=0.4)
    g.ink.text("早市", mx, top + 5, 22)
    # 我们那栋楼的楼门：门洞里看得见楼梯
    g.clear(rect_pts(up - 120, top - 30, 240, GROUND - top + 30))
    g.pen("mei", 0.58).fill(rect_pts(up - 120, top - 30, 240, GROUND - top + 30))
    fbricks(g, up - 120, top - 30, 240, GROUND - top + 30, seed=12)
    g.clear(rect_pts(up - 70, GROUND - 250, 140, 250))
    g.pen("ink", 0.62).fill(rect_pts(up - 70, GROUND - 250, 140, 250))
    for k in range(6):
        yy = GROUND - 30 - k * 36
        g.clear(rect_pts(up - 60 + k * 14, yy, 80, 6), colors=["ink"])
    g.ink.rect(up - 70, GROUND - 250, 140, 250, lw=3.2)
    g.clear(rect_pts(up - 120, GROUND - 300, 240, 30))
    g.pen("ink", 0.3).fill(rect_pts(up - 130, GROUND - 300, 260, 30))
    g.ink.rect(up - 130, GROUND - 300, 260, 30, lw=2.6)
    g.clear(rect_pts(up + 84, GROUND - 230, 60, 30))
    g.qing.rect(up + 84, GROUND - 230, 60, 30, lw=1.6, fill=True)
    knock(g, "qing", "3号楼", up + 114, GROUND - 215, 16)
    # 告示栏（内容随年代换，留空的格子）
    # （给去早市的胡同口让地方：往右挪了一截、窄了一点）
    bx = 1516
    g.ink.line([(bx - 56, GROUND), (bx - 56, GROUND - 260)], 5)
    g.ink.line([(bx + 56, GROUND), (bx + 56, GROUND - 260)], 5)
    g.clear(rect_pts(bx - 64, GROUND - 270, 128, 130))
    g.pen("ink", 0.22).fill(rect_pts(bx - 64, GROUND - 270, 128, 130))
    g.ink.rect(bx - 64, GROUND - 270, 128, 130, lw=2.6)
    g.pen("mei").fill([(bx - 78, GROUND - 270), (bx + 78, GROUND - 270), (bx + 64, GROUND - 292), (bx - 64, GROUND - 292)])
    knock(g, "mei", "告示", bx, GROUND - 281, 18)
    for k, c in enumerate(("mei", "qing", "ink")):
        g.clear(rect_pts(bx - 54 + k * 38, GROUND - 254 + (k % 2) * 10, 32, 50))
        g.pen(c, 0.18).fill(rect_pts(bx - 54 + k * 38, GROUND - 254 + (k % 2) * 10, 32, 50))
        g.ink.rect(bx - 54 + k * 38, GROUND - 254 + (k % 2) * 10, 32, 50, lw=1.4)
    # 跳皮筋那一截：墙根两块砖
    rx = sp["alley_rope"]
    for k in (-1, 1):
        g.ink.rect(rx + k * 90 - 16, GROUND - 22, 32, 22, lw=2)
        g.pen("mei", 0.5).fill(rect_pts(rx + k * 90 - 16, GROUND - 22, 32, 22))
    # 楼门口一棵大槐树
    tree(g, 1900, GROUND, 640, 190, "huai", seed=19)
    # 下棋的石桌
    cx = sp["chess_table"]
    g.clear(rect_pts(cx - 70, GROUND - 82, 140, 16))
    g.pen("ink", 0.35).fill(rect_pts(cx - 70, GROUND - 82, 140, 16))
    g.ink.rect(cx - 70, GROUND - 82, 140, 16, lw=2.4)
    g.ink.rect(cx - 16, GROUND - 66, 32, 66, lw=2.4)
    for k in (-1, 1):
        g.ink.rect(cx + k * 110 - 20, GROUND - 40, 40, 40, lw=2.2)
        g.pen("ink", 0.2).fill(rect_pts(cx + k * 110 - 20, GROUND - 40, 40, 40))
    # 胡同口：往公园去
    gx = ex["to_park"][0]
    g.clear(rect_pts(gx - 80, top - 80, 160, GROUND - top + 80))
    g.pen("ink", 0.32).fill(rect_pts(gx - 80, top - 80, 160, GROUND - top + 80))
    fhatch(g, "ink", gx - 80, top - 80, 160, GROUND - top + 80, 30, 14, 1.0, 0.4)
    g.ink.line([(gx - 80, top - 80), (gx - 80, GROUND)], 3.4)
    g.ink.line([(gx + 80, top - 80), (gx + 80, GROUND)], 3.4)
    g.pen("ink", 0.5).fill([(gx - 100, top - 80), (gx + 100, top - 80), (gx + 90, top - 108), (gx - 90, top - 108)])
    signboard(g, gx + 140, top + 40, "河畔里", "qing", 24, vertical=True, pad=8)


def lane(g, x, top, w=150):
    """两栋楼之间的一条窄胡同口：黑洞洞的一条，上头一道过街的檐。"""
    g.clear(rect_pts(x - w / 2, top - 80, w, GROUND - top + 80))
    g.pen("ink", 0.32).fill(rect_pts(x - w / 2, top - 80, w, GROUND - top + 80))
    fhatch(g, "ink", x - w / 2, top - 80, w, GROUND - top + 80, 30, 14, 1.0, 0.4)
    g.ink.line([(x - w / 2, top - 80), (x - w / 2, GROUND)], 3.4)
    g.ink.line([(x + w / 2, top - 80), (x + w / 2, GROUND)], 3.4)
    g.pen("ink", 0.5).fill([(x - w / 2 - 20, top - 80), (x + w / 2 + 20, top - 80), (x + w / 2 + 10, top - 108), (x - w / 2 - 10, top - 108)])


def bikeshop(g, sp, ex, span, top):
    x0, x1 = span
    # 修车铺左手边一条胡同，往中学去
    lane(g, ex["to_middle"][0], top, 130)
    b0 = ex["to_middle"][0] + 80
    signboard(g, (b0 + x1) / 2, top - 46, "修车", "ink", 44)
    # 墙上挂的内胎、工具板、一把旧二胡
    for k in range(3):
        g.ink.circle(b0 + 60 + k * 70, top + 110, 30, lw=4)
        g.ink.line([(b0 + 60 + k * 70, top + 70), (b0 + 60 + k * 70, top + 80)], 2)
    g.ink.rect(b0 + 250, top + 60, 110, 110, lw=2.4)
    for r in range(3):
        for c in range(3):
            g.ink.line([(b0 + 270 + c * 30, top + 76 + r * 32), (b0 + 270 + c * 30, top + 98 + r * 32)], 3)
    hx = x1 - 50
    g.ink.line([(hx, top + 50), (hx + 10, top + 230)], 3)
    g.clear(ellipse_pts(hx + 12, top + 226, 18, 12))
    g.pen("mei", 0.6).fill(ellipse_pts(hx + 12, top + 226, 18, 12))
    g.ink.ellipse(hx + 12, top + 226, 18, 12, lw=2)
    g.ink.line([(hx - 30, top + 160), (hx + 40, top + 190)], 1.4)
    # 修着的车、等着取的车
    bicycle(g, b0 + 210, GROUND, 1, "qing")
    bicycle(g, x1 - 90, GROUND, -1, "mei")
    # 打气筒、水盆
    g.ink.line([(b0 + 300, GROUND), (b0 + 300, GROUND - 90)], 4)
    g.ink.line([(b0 + 280, GROUND - 90), (b0 + 320, GROUND - 90)], 4)
    g.ink.ellipse(b0 + 360, GROUND - 14, 34, 10, lw=2.4)
    g.pen("qing", 0.4).fill(ellipse_pts(b0 + 360, GROUND - 16, 30, 7))
    stool(g, sp["bike_bench"], GROUND, "ink", 70, 44)


def teahouse(g, sp, span, top, ex=None):
    x0, x1 = span
    signboard(g, (x0 + x1) / 2, top - 56, "河畔茶社", "mei", 44)
    # 木格子门脸：敞着，看见里头的小台子和茶座
    g.clear(rect_pts(x0 + 10, top + 6, x1 - x0 - 20, GROUND - top - 6))
    g.pen("mei", 0.12).fill(rect_pts(x0 + 10, top + 6, x1 - x0 - 20, GROUND - top - 6))
    for k in range(int((x1 - x0) / 40)):
        fline(g, "ink", [(x0 + 20 + k * 40, top + 10), (x0 + 20 + k * 40, top + 60)], 2, 0.9)
    g.ink.line([(x0 + 10, top + 62), (x1 - 10, top + 62)], 3)
    # 台子
    st = sp["tea_stage"]
    g.clear(rect_pts(st - 150, GROUND - 60, 300, 60))
    g.pen("mei", 0.5).fill(rect_pts(st - 150, GROUND - 60, 300, 60))
    g.ink.rect(st - 150, GROUND - 60, 300, 60, lw=2.8)
    g.pen("mei").fill(rect_pts(st - 140, top + 80, 280, 30))
    knock(g, "mei", "曲艺", st, top + 95, 22)
    g.pen("mei", 0.3).fill([(st - 150, top + 110), (st - 110, top + 110), (st - 130, GROUND - 60), (st - 150, GROUND - 60)])
    g.pen("mei", 0.3).fill([(st + 150, top + 110), (st + 110, top + 110), (st + 130, GROUND - 60), (st + 150, GROUND - 60)])
    table(g, st, GROUND - 60, 70, 60, cloth="mei")
    # 茶座：方桌、盖碗
    ts = sp["tea_seat"]
    for dx in (-110, 110):
        table(g, ts + dx, GROUND, 120, 76)
        g.ink.rect(ts + dx - 14, GROUND - 96, 28, 18, lw=1.8)
        g.ink.ellipse(ts + dx, GROUND - 98, 18, 5, lw=1.8)
    # 门口挂的灯笼
    for lx in (x0 + 60, x1 - 60):
        mark("stall_light", lx, top + 120)
        g.ink.line([(lx, top + 62), (lx, top + 90)], 2)
        g.clear(ellipse_pts(lx, top + 120, 26, 32))
        g.pen("mei").fill(ellipse_pts(lx, top + 120, 26, 32))
        g.ink.ellipse(lx, top + 120, 26, 32, lw=2)
        g.ink.line([(lx, top + 152), (lx, top + 180)], 2)
    # 茶社门口的公交站牌：坐车去医院（小孩病了，大人领着从这儿上车）
    hx = (ex or {}).get("to_hospital", (3150.0, GROUND))[0]
    g.ink.line([(hx, GROUND + 18), (hx, GROUND - 250)], 5, amp=0.3)
    g.clear(rect_pts(hx - 30, GROUND - 360, 60, 112))
    g.ink.rect(hx - 30, GROUND - 360, 60, 112, lw=2.4, amp=0.3)
    g.pen("qing").fill(rect_pts(hx - 30, GROUND - 360, 60, 30))
    knock(g, "qing", "公交", hx, GROUND - 345, 18)
    g.ink.text("医院", hx - 10, GROUND - 296, 15, vertical=True)
    for k in range(4):
        g.ink.line([(hx + 10, GROUND - 318 + k * 16), (hx + 22, GROUND - 318 + k * 16)], 1.6, amp=0.1)


def draw_river(g, sc):
    W = sc["width"]
    sp, ex, zs = sc["spots"], sc["exits"], sc["zones"]
    b0 = zs["bridge"]["span"][0]
    far = GROUND - 250
    sky(g, W, seed=17, horizon=far, clouds=7)
    skyline(g, -40, W + 40, far, seed=13, hmin=40, hmax=230, d=0.26, chimneys=[(900, 300), (1020, 240)], towers=[(1800, 200)])
    # 对岸的堤
    g.pen("ink", 0.2).fill(rect_pts(-40, far, W + 80, 14))
    g.ink.line([(-40, far), (W + 40, far)], 2.4, amp=0.6)
    water(g, -40, W + 40, far + 14, GROUND - 4, seed=3)
    # 远处一条小船
    bx = 1650
    hull = [(bx - 90, far + 70), (bx + 90, far + 70), (bx + 70, far + 92), (bx - 70, far + 92)]
    g.clear(hull)
    g.pen("ink", 0.4).fill(hull)
    g.ink.poly(hull, 2.4)
    g.ink.rect(bx - 30, far + 40, 60, 30, lw=2)
    # 柳树（立在步道后头）
    for i, tx in enumerate((300, 900, 1620, 2300)):
        tree(g, tx, GROUND, 600, 150, "willow", seed=31 + i)
    # 栏杆：一段一段，river_rail 那段刷着青漆
    rail0, rail1 = 220, b0 - 40
    railing(g, rail0, rail1, GROUND, 104, 130, "ink")
    rr = sp["river_rail"]
    g.pen("qing", 0.55).fill(rect_pts(rr - 130, GROUND - 104, 260, 12))
    g.pen("qing", 0.55).fill(rect_pts(rr - 130, GROUND - 58, 260, 10))
    # 钓鱼的台阶口：栏杆断开，一只小桶、一根竿
    fx = sp["river_fish"]
    g.clear(rect_pts(fx - 70, GROUND - 120, 140, 118))
    g.pen("qing", 0.42).fill(rect_pts(fx - 70, GROUND - 120, 140, 118))
    for k in range(4):
        g.clear(rect_pts(fx - 70 + k * 30, GROUND - 30 - k * 22, 140 - k * 30, 8), colors=["qing"])
        g.ink.line([(fx - 70 + k * 30, GROUND - 30 - k * 22), (fx + 70, GROUND - 30 - k * 22)], 2)
    g.ink.line([(fx + 40, GROUND - 6), (fx + 200, GROUND - 330)], 2.2)
    g.ink.line([(fx + 200, GROUND - 330), (fx + 250, GROUND - 120)], 0.9, amp=0.2)
    g.ink.rect(fx - 110, GROUND - 40, 36, 40, lw=2.2)
    g.pen("qing", 0.5).fill(rect_pts(fx - 110, GROUND - 24, 36, 24))
    # 长椅
    bench(g, sp["river_bank"], GROUND, 180, "qing")
    lamp(g, 1100, GROUND, 470, 1)
    lamp(g, 2470, GROUND, 470, -1)
    # 步道：石板
    g.clear(rect_pts(-40, GROUND, b0 + 40, BOTTOM - GROUND + 40))
    g.pen("ink", 0.16).fill(rect_pts(-40, GROUND, b0 + 40, 30))
    for x in range(0, int(b0), 90):
        fline(g, "ink", [(x, GROUND + 2), (x, GROUND + 30)], 1.2, 0.5)
    g.ink.line([(-40, GROUND), (b0, GROUND)], 4.5, amp=0.6)
    # 河堤立面：条石
    g.pen("ink", 0.2).fill(rect_pts(-40, GROUND + 30, b0 + 40, BOTTOM - GROUND))
    fbricks(g, -40, GROUND + 30, b0 + 40, BOTTOM - GROUND, 120, 40, 1.4, 0.45, seed=5)
    g.ink.line([(-40, GROUND + 30), (b0, GROUND + 30)], 3)
    # 回街上的那个台阶口
    sx = ex["to_street"][0]
    g.ink.line([(sx + 70, GROUND), (sx + 70, GROUND - 320)], 4)
    signboard(g, sx + 70, GROUND - 340, "河畔里", "qing", 22, pad=8)
    # 铁桥（桥上一溜灯）
    bridge(g, b0, W, GROUND)
    for k in range(4):
        bx = b0 + 120 + k * 260
        g.ink.line([(bx, GROUND), (bx, GROUND - 110)], 3)
        g.ink.circle(bx, GROUND - 118, 8, lw=2)
        mark("street_lamp", bx, GROUND - 118)


def bridge(g, x0, x1, deck):
    # 桥下的水（前景）
    water(g, x0, x1 + 40, deck + 30, BOTTOM + 40, seed=9)
    # 桥墩
    for px in (x0 + 40, x0 + 520):
        g.clear(rect_pts(px - 40, deck + 30, 80, BOTTOM - deck))
        g.pen("ink", 0.3).fill(rect_pts(px - 40, deck + 30, 80, BOTTOM - deck))
        fbricks(g, px - 40, deck + 30, 80, BOTTOM - deck, 40, 24, 1.2, 0.5, seed=px)
        g.ink.rect(px - 40, deck + 30, 80, BOTTOM - deck, lw=3)
    # 桥面
    g.clear(rect_pts(x0, deck, x1 - x0 + 40, 34))
    g.pen("qing", 0.62).fill(rect_pts(x0, deck, x1 - x0 + 40, 34))
    g.ink.rect(x0, deck, x1 - x0 + 40, 34, lw=3)
    for x in range(int(x0), int(x1) + 40, 40):
        g.ink.dot(x + 20, deck + 17, 3)
    # 桁架：上弦拱起，三角形的腹杆
    span = x1 - x0 + 40
    n = 8
    up = lambda t: deck - 160 - 220 * math.sin(math.pi * min(1, t))  # noqa: E731
    pts_top = [(x0 + span * i / n, up(i / n)) for i in range(n + 1)]
    for i in range(n):
        a = (x0 + span * i / n, deck)
        b = (x0 + span * (i + 1) / n, deck)
        ta, tb = pts_top[i], pts_top[i + 1]
        g.qing.line([a, tb], 7, amp=0.2)
        g.qing.line([ta, a], 6, amp=0.2)
        g.ink.line([a, tb], 2, amp=0.2)
        for k in range(1, 4):
            t = k / 4
            g.ink.dot(a[0] + (tb[0] - a[0]) * t, a[1] + (tb[1] - a[1]) * t, 2.4)
    g.qing.line(pts_top, 12, amp=0.2)
    g.ink.line(pts_top, 2.4, amp=0.2)
    g.ink.line([(x0, deck - 60), (x1 + 40, deck - 60)], 3)
    # 桥头的桥名
    signboard(g, x0 + 260, deck - 250, "铁桥", "qing", 30, pad=10)


def draw_primary(g, sc):
    W = sc["width"]
    sp, ex, zs = sc["spots"], sc["exits"], sc["zones"]
    sky(g, W, seed=23, horizon=GROUND - 120)
    skyline(g, -40, W + 40, GROUND - 260, seed=29, hmin=40, hmax=180, d=0.10)
    # 校门口：传达室、门柱、铁栅门
    gx = sp["school_gate"]
    g.clear(rect_pts(60, GROUND - 260, 200, 260))
    g.pen("mei", 0.5).fill(rect_pts(60, GROUND - 260, 200, 260))
    fbricks(g, 60, GROUND - 260, 200, 260, seed=31)
    g.ink.rect(60, GROUND - 260, 200, 260, lw=3)
    slab(g, 46, 274, GROUND - 284, GROUND - 260)
    window(g, 110, GROUND - 210, 100, 80, panes=2)
    knock_plate = "传达室"
    g.clear(rect_pts(104, GROUND - 110, 112, 28))
    g.ink.rect(104, GROUND - 110, 112, 28, lw=2)
    g.ink.text(knock_plate, 160, GROUND - 96, 20)
    for px in (gx - 150, gx + 150):
        g.clear(rect_pts(px - 34, GROUND - 330, 68, 330))
        g.pen("mei", 0.62).fill(rect_pts(px - 34, GROUND - 330, 68, 330))
        fbricks(g, px - 34, GROUND - 330, 68, 330, 22, 10, seed=int(px))
        g.ink.rect(px - 34, GROUND - 330, 68, 330, lw=3)
        g.pen("ink", 0.4).fill(rect_pts(px - 42, GROUND - 350, 84, 22))
        g.ink.rect(px - 42, GROUND - 350, 84, 22, lw=2.4)
    signboard(g, gx - 150, GROUND - 190, "河畔里小学", "ink", 22, vertical=True, pad=8)
    # 两扇铁栅门敞着，贴在门柱边
    for side in (-1, 1):
        x0 = gx + side * 116
        for k in range(6):
            xx = x0 - side * k * 10
            g.ink.line([(xx, GROUND), (xx, GROUND - 210)], 2.2)
        g.ink.line([(x0, GROUND - 200), (x0 - side * 50, GROUND - 200)], 3)
        g.ink.line([(x0, GROUND - 20), (x0 - side * 50, GROUND - 20)], 3)
    # 围墙
    g.clear(rect_pts(gx + 184, GROUND - 160, zs["school"]["span"][1] - gx - 184, 160))
    g.pen("mei", 0.5).fill(rect_pts(gx + 184, GROUND - 160, zs["school"]["span"][1] - gx - 184, 160))
    fbricks(g, gx + 184, GROUND - 160, zs["school"]["span"][1] - gx - 184, 160, seed=33)
    g.ink.rect(gx + 184, GROUND - 160, zs["school"]["span"][1] - gx - 184, 160, lw=2.6)
    g.pen("ink", 0.4).fill(rect_pts(gx + 184, GROUND - 176, zs["school"]["span"][1] - gx - 184, 16))
    # 回街上的路
    g.ink.line([(40, GROUND), (40, GROUND - 300)], 4)
    lamp(g, gx + 230, GROUND, 420, -1)
    tree(g, 690, GROUND, 520, 130, "huai", seed=41)
    # 教室：一层的平房剖开
    c0, c1 = zs["classroom"]["span"]
    ctop = GROUND - 430
    g.clear(rect_pts(c0, ctop, c1 - c0, GROUND - ctop))
    g.pen("ink", 0.05).fill(rect_pts(c0, ctop, c1 - c0, GROUND - ctop))
    wain = GROUND - 140
    g.pen("qing", 0.32).fill(rect_pts(c0, wain, c1 - c0, GROUND - wain))
    g.ink.line([(c0, wain), (c1, wain)], 2.6)
    # 屋顶：瓦
    roofp = [(c0 - 60, ctop), (c0 + 120, ctop - 120), (c1 - 120, ctop - 120), (c1 + 60, ctop)]
    g.clear(roofp)
    g.pen("ink", 0.36).fill(roofp)
    for k in range(int((c1 - c0 + 120) / 28)):
        xx = c0 - 40 + k * 28
        fline(g, "ink", [(xx, ctop - 4), (xx + 40, ctop - 116)], 1.4, 0.7)
    g.ink.poly(roofp, 3)
    slab(g, c0 - 20, c1 + 20, ctop, ctop + 26)
    # 黑板报
    bx = sp["class_board"]
    g.clear(rect_pts(bx - 160, ctop + 70, 320, 200))
    g.pen("ink", 0.78).fill(rect_pts(bx - 160, ctop + 70, 320, 200))
    g.ink.rect(bx - 166, ctop + 64, 332, 212, lw=3)
    g.clear(rect_pts(bx - 130, ctop + 90, 140, 40), colors=["ink"])
    g.pen("mei").fill(rect_pts(bx - 130, ctop + 90, 140, 40))
    knock(g, "mei", "学习园地", bx - 60, ctop + 110, 24)
    for k in range(5):
        fline(g, "ink", [(bx - 130 + (k % 2) * 160, ctop + 150 + (k // 2) * 34), (bx - 30 + (k % 2) * 160, ctop + 150 + (k // 2) * 34)], 2.4, 1.0)
        g.clear(rect_pts(bx - 130 + (k % 2) * 160, ctop + 150 + (k // 2) * 34, 100 - (k * 13) % 30, 3), colors=["ink"])
    g.pen("qing").fill(circle_pts(bx + 100, ctop + 110, 22))
    g.pen("mei", 0.6).fill(circle_pts(bx + 60, ctop + 104, 10))
    # 窗（朝操场）
    for wx in (c0 + 520, c0 + 760):
        window(g, wx - 90, ctop + 70, 180, 200, panes=3)
    # 讲台和前头的黑板（在右头墙上）
    g.clear(rect_pts(c1 - 200, ctop + 60, 170, 180))
    g.pen("qing", 0.7).fill(rect_pts(c1 - 200, ctop + 60, 170, 180))
    g.ink.rect(c1 - 206, ctop + 54, 182, 192, lw=3)
    g.ink.line([(c1 - 206, ctop + 250), (c1 - 24, ctop + 250)], 4)
    g.clear(rect_pts(c1 - 180, ctop + 90, 60, 3), colors=["qing"])
    g.clear(rect_pts(c1 - 180, ctop + 120, 110, 3), colors=["qing"])
    g.ink.rect(c1 - 150, GROUND - 100, 90, 100, lw=2.6)
    g.pen("ink", 0.3).fill(rect_pts(c1 - 150, GROUND - 100, 90, 100))
    # 课桌：一排排侧面
    for k, dx in enumerate(range(int(c0 + 380), int(c1 - 220), 130)):
        desk_school(g, dx, GROUND)
    clock(g, c0 + 640, ctop + 40, 22)
    for x in (c0, c1):
        cut_wall(g, x, ctop, GROUND, 30)
    g.clear(rect_pts(c0 - 15, GROUND - 230, 30, 230))
    g.clear(rect_pts(c1 - 15, GROUND - 230, 30, 230))
    g.ink.line([(c0 - 15, GROUND - 230), (c0 + 15, GROUND - 230)], 3)
    g.ink.line([(c1 - 15, GROUND - 230), (c1 + 15, GROUND - 230)], 3)
    # 操场：旗杆、篮球架、围栏
    y0, y1 = zs["yard"]["span"]
    fence(g, y0 + 40, W + 40, GROUND, 130, 30)
    fx = y0 + 180
    g.ink.line([(fx, GROUND), (fx, GROUND - 620)], 5)
    g.ink.circle(fx, GROUND - 626, 7, lw=2, fill=True)
    flag = [(fx + 3, GROUND - 610), (fx + 140, GROUND - 600), (fx + 136, GROUND - 530), (fx + 3, GROUND - 540)]
    g.pen("mei").fill(flag)
    g.ink.rect(fx - 40, GROUND - 30, 80, 30, lw=2.6)
    g.pen("ink", 0.2).fill(rect_pts(fx - 40, GROUND - 30, 80, 30))
    hx = y1 - 220
    g.ink.line([(hx, GROUND), (hx, GROUND - 430)], 8)
    g.ink.line([(hx, GROUND - 400), (hx - 90, GROUND - 400)], 4)
    g.clear(rect_pts(hx - 120, GROUND - 480, 34, 120))
    g.ink.rect(hx - 120, GROUND - 480, 34, 120, lw=2.6)
    g.ink.line([(hx - 120, GROUND - 400), (hx - 200, GROUND - 400)], 3)
    for k in range(5):
        g.ink.line([(hx - 196 + k * 18, GROUND - 400), (hx - 186 + k * 14, GROUND - 350)], 1.2)
    g.pen("mei").line([(hx - 200, GROUND - 400), (hx - 120, GROUND - 400)], 3)
    tree(g, y0 + 520, GROUND, 560, 160, "huai", seed=47)
    # 地：门口和操场是土，教室里是水泥
    ground_floor(g, W, GROUND, "ink", 0.14, 0)
    g.pen("mei", 0.20).fill(rect_pts(y0, GROUND, W - y0 + 40, 30))
    for k in range(int((W - y0) / 18)):
        g.ink.dot(y0 + k * 18 + (k * 7) % 11, GROUND + 8 + (k * 13) % 18, 1.6)


def desk_school(g, x, base):
    g.pen("ink", 0.3).fill(rect_pts(x - 50, base - 92, 100, 12))
    g.ink.rect(x - 50, base - 92, 100, 12, lw=2.4)
    g.ink.rect(x - 46, base - 80, 92, 30, lw=1.8)
    g.ink.line([(x - 44, base - 50), (x - 44, base)], 3)
    g.ink.line([(x + 44, base - 50), (x + 44, base)], 3)
    g.pen("mei", 0.5).fill(rect_pts(x - 20, base - 104, 30, 12))
    # 椅子在左边
    cx = x - 76
    g.ink.line([(cx - 18, base), (cx - 18, base - 52), (cx + 18, base - 52), (cx + 18, base)], 2.6)
    g.ink.line([(cx - 18, base - 52), (cx - 20, base - 120)], 3)


# --- 后面几张：同一套零件，各画各的样子 ---

def draw_middle(g, sc):
    W = sc["width"]
    sp, zs = sc["spots"], sc["zones"]
    sky(g, W, seed=37, horizon=GROUND - 120)
    skyline(g, -40, W + 40, GROUND - 300, seed=39, hmin=60, hmax=220, d=0.10)
    # 校门：门柱、电动伸缩门、门口小文具店
    f0, f1 = zs["middle_front"]["span"]
    gx = sp["middle_gate"]
    g.clear(rect_pts(30, GROUND - 260, 170, 260))
    g.pen("qing", 0.3).fill(rect_pts(30, GROUND - 260, 170, 260))
    g.ink.rect(30, GROUND - 260, 170, 260, lw=3)
    awning(g, 40, 190, GROUND - 260, 36, "qing")
    signboard(g, 115, GROUND - 300, "文具", "qing", 28)
    window(g, 60, GROUND - 200, 110, 100, panes=2)
    for px in (gx - 120, gx + 140):
        g.clear(rect_pts(px - 30, GROUND - 300, 60, 300))
        g.pen("ink", 0.26).fill(rect_pts(px - 30, GROUND - 300, 60, 300))
        g.ink.rect(px - 30, GROUND - 300, 60, 300, lw=3)
    signboard(g, gx + 10, GROUND - 330, "第二中学", "ink", 28)
    for k in range(9):
        xx = gx - 90 + k * 22
        g.ink.line([(xx, GROUND), (xx + 11, GROUND - 60), (xx + 22, GROUND)], 2)
    g.ink.line([(gx - 90, GROUND - 60), (gx + 110, GROUND - 60)], 2.4)
    # 排名榜（rank_board 在 600）
    g.clear(rect_pts(540, GROUND - 270, 120, 170))
    g.pen("mei", 0.25).fill(rect_pts(540, GROUND - 270, 120, 170))
    g.ink.rect(540, GROUND - 270, 120, 170, lw=2.6)
    g.ink.line([(550, GROUND - 100), (550, GROUND)], 4)
    g.ink.line([(650, GROUND - 100), (650, GROUND)], 4)
    for k in range(6):
        fline(g, "ink", [(556, GROUND - 240 + k * 22), (640 - (k * 9) % 30, GROUND - 240 + k * 22)], 2, 0.6)
    g.pen("mei").fill(rect_pts(540, GROUND - 290, 120, 24))
    knock(g, "mei", "光荣榜", 600, GROUND - 278, 16)
    # 教学楼：三层，剖开一楼，二三楼只看立面，楼顶小屋是广播站
    c0, c1 = zs["middle_class"]["span"]
    r0, r1 = zs["radio_room"]["span"]
    ftop = GROUND - 1000
    facade(g, c0, r1, ftop + 40, GROUND - 400, "ink", 0.14, 2, (90, 110), 70, brick=False, seed=51)
    slab(g, c0 - 20, r1 + 20, GROUND - 400, GROUND - 370)
    g.clear(rect_pts(c0, GROUND - 370, r1 - c0, 370))
    g.pen("ink", 0.05).fill(rect_pts(c0, GROUND - 370, r1 - c0, 370))
    g.pen("qing", 0.25).fill(rect_pts(c0, GROUND - 130, r1 - c0, 130))
    g.ink.line([(c0, GROUND - 130), (r1, GROUND - 130)], 2.4)
    # 黑板、课桌
    g.clear(rect_pts(c0 + 60, GROUND - 330, 330, 170))
    g.pen("qing", 0.75).fill(rect_pts(c0 + 60, GROUND - 330, 330, 170))
    g.ink.rect(c0 + 54, GROUND - 336, 342, 182, lw=3)
    for k in range(3):
        g.clear(rect_pts(c0 + 90, GROUND - 300 + k * 36, 160 + (k * 57) % 90, 3), colors=["qing"])
    for dx in range(int(c0 + 470), int(r0 - 60), 120):
        desk_school(g, dx, GROUND)
    # 走廊值日表
    g.clear(rect_pts(r0 - 10, GROUND - 330, 100, 130))
    g.ink.rect(r0 - 10, GROUND - 330, 100, 130, lw=2.4)
    for r in range(5):
        g.ink.line([(r0, GROUND - 306 + r * 22), (r0 + 80, GROUND - 306 + r * 22)], 1.4)
    # 广播站（一楼东头一间小屋，桌上一只话筒）
    mx = sp["radio_mic"]
    g.clear(rect_pts(r0, GROUND - 370, r1 - r0, 370))
    g.pen("mei", 0.14).fill(rect_pts(r0, GROUND - 370, r1 - r0, 370))
    table(g, mx, GROUND, 160, 84)
    g.ink.line([(mx, GROUND - 84), (mx, GROUND - 140)], 2.6)
    g.clear(ellipse_pts(mx, GROUND - 152, 12, 16))
    g.pen("ink", 0.7).fill(ellipse_pts(mx, GROUND - 152, 12, 16))
    g.ink.rect(mx - 50, GROUND - 120, 40, 30, lw=2)
    g.ink.dot(mx - 38, GROUND - 105, 3)
    signboard(g, mx, GROUND - 300, "广播站", "mei", 22, pad=8)
    # 楼顶的大喇叭
    g.ink.line([(r0 + 140, ftop + 26), (r0 + 140, ftop - 80)], 4)
    horn = [(r0 + 140, ftop - 70), (r0 + 220, ftop - 110), (r0 + 220, ftop - 40)]
    g.pen("ink", 0.5).fill(horn)
    g.ink.poly(horn, 2.4)
    for x in (c0, r0, r1):
        cut_wall(g, x, GROUND - 370, GROUND - 240, 28, "ink")
    # 操场：塑胶跑道是梅红的
    o0, o1 = zs["middle_field"]["span"]
    fence(g, o0, o1, GROUND, 120, 28)
    g.ink.line([(o0 + 180, GROUND), (o0 + 180, GROUND - 620)], 5)
    g.pen("mei").fill([(o0 + 183, GROUND - 610), (o0 + 320, GROUND - 600), (o0 + 316, GROUND - 530), (o0 + 183, GROUND - 540)])
    # 车棚：石棉瓦顶，一排车，最里头一辆蒙着土
    s0, s1 = zs["shed"]["span"]
    shed = [(s0, GROUND - 260), (s1 + 40, GROUND - 300), (s1 + 40, GROUND - 270), (s0, GROUND - 230)]
    g.clear(shed)
    g.pen("ink", 0.3).fill(shed)
    for k in range(int((s1 - s0) / 24)):
        fline(g, "ink", [(s0 + k * 24, GROUND - 258 - k * 0.9), (s0 + k * 24, GROUND - 228 - k * 0.9)], 1.4)
    g.ink.poly(shed, 2.6)
    for px in (s0 + 20, s1 - 20):
        g.ink.line([(px, GROUND), (px, GROUND - 240)], 5)
    for k, bx in enumerate(range(int(s0 + 70), int(s1 - 20), 74)):
        bicycle(g, bx, GROUND, 1, ["qing", "mei", "ink"][k % 3], 1.3)
    g.pen("ink", 0.18).fill(rect_pts(s1 - 80, GROUND - 70, 70, 70))
    ground_floor(g, W, GROUND, "ink", 0.14, 0)
    g.pen("mei", 0.34).fill(rect_pts(o0, GROUND, o1 - o0, 30))
    for k in range(4):
        g.clear(rect_pts(o0, GROUND + 6 + k * 6, o1 - o0, 1.4), colors=["mei"])


def draw_across(g, sc):
    W = sc["width"]
    sp, ex, zs = sc["spots"], sc["exits"], sc["zones"]
    sky(g, W, seed=43, horizon=GROUND - 300)
    skyline(g, -40, W + 40, GROUND - 380, seed=45, hmin=120, hmax=420, d=0.12)
    z = lambda k: zs[k]["span"]  # noqa: E731
    # 桥头车站：站牌、雨棚
    b0, b1 = z("bridgehead")
    shelter = [(b0 + 120, GROUND - 260), (b1 - 40, GROUND - 260), (b1 - 20, GROUND - 230), (b0 + 100, GROUND - 230)]
    g.clear(shelter)
    g.pen("qing", 0.6).fill(shelter)
    g.ink.poly(shelter, 2.6)
    for px in (b0 + 130, b1 - 50):
        g.ink.line([(px, GROUND), (px, GROUND - 232)], 4)
    bench(g, (b0 + b1) / 2 + 30, GROUND, 200, "ink", back=False)
    g.ink.line([(b0 + 80, GROUND), (b0 + 80, GROUND - 330)], 4)
    signboard(g, b0 + 80, GROUND - 360, "桥头", "qing", 26, pad=8)
    # 老厂：红砖厂房、锯齿顶、高烟囱（年代换脸由街景层盖）
    f0, f1 = z("factory")
    top = GROUND - 420
    saw = [(f0, GROUND), (f0, top)]
    n = 4
    for k in range(n):
        xa = f0 + (f1 - f0) * k / n
        xb = f0 + (f1 - f0) * (k + 1) / n
        saw += [(xa, top), (xb, top - 90), (xb, top)]
    saw += [(f1, top), (f1, GROUND)]
    g.clear(saw)
    g.pen("mei", 0.55).fill(saw)
    fbricks(g, f0, top - 90, f1 - f0, GROUND - top + 90, seed=61)
    g.ink.poly(saw, 3)
    for k in range(n):
        xb = f0 + (f1 - f0) * (k + 1) / n
        g.pen("qing", 0.4).fill([(xb - 6, top - 84), (xb - 6, top - 6), (xb - 40, top - 6)])
    for wx in range(int(f0 + 60), int(f1 - 120), 150):
        window(g, wx, top + 90, 90, 160, panes=3)
    g.clear(rect_pts(f0 + 280, GROUND - 230, 160, 230))
    g.pen("ink", 0.5).fill(rect_pts(f0 + 280, GROUND - 230, 160, 230))
    g.ink.rect(f0 + 280, GROUND - 230, 160, 230, lw=3)
    signboard(g, f0 + 360, GROUND - 270, "红星机械厂", "mei", 22, pad=8)
    cx = f1 - 70
    g.clear([(cx - 40, top), (cx - 22, -160), (cx + 22, -160), (cx + 40, top)])
    g.pen("mei", 0.6).fill([(cx - 40, top), (cx - 22, -160), (cx + 22, -160), (cx + 40, top)])
    fbricks(g, cx - 40, -160, 80, top + 160, 20, 10, seed=63)
    g.ink.poly([(cx - 40, top), (cx - 22, -160), (cx + 22, -160), (cx + 40, top)], 3)
    for k in range(3):
        g.pen("ink", 0.3).fill(rect_pts(cx - 30 + k * 2, -100 + k * 160, 60 - k * 4, 12))
    # 去新家的路口（小区在厂子这一片）
    # 去新家的路口就是厂门（后来厂子拆了盖小区），引擎在门上挂牌子
    # 少年宫：带廊子的老楼
    y0, y1 = z("youth_palace")
    facade(g, y0 + 20, y1 - 20, GROUND - 560, GROUND - 200, "mei", 0.32, 2, (70, 110), 46, brick=False, seed=65)
    g.clear(rect_pts(y0 + 20, GROUND - 200, y1 - y0 - 40, 200))
    g.pen("ink", 0.2).fill(rect_pts(y0 + 20, GROUND - 200, y1 - y0 - 40, 200))
    for k in range(7):
        ax = y0 + 70 + k * (y1 - y0 - 140) / 6
        g.clear(rect_pts(ax - 18, GROUND - 200, 36, 200))
        g.pen("mei", 0.25).fill(rect_pts(ax - 18, GROUND - 200, 36, 200))
        g.ink.rect(ax - 18, GROUND - 200, 36, 200, lw=2.4)
    roofp = [(y0, GROUND - 560), ((y0 + y1) / 2, GROUND - 660), (y1, GROUND - 560)]
    g.clear(roofp)
    g.pen("qing", 0.55).fill(roofp)
    g.ink.poly(roofp, 3)
    signboard(g, (y0 + y1) / 2, GROUND - 590, "少年宫", "qing", 26, pad=8)
    # 市重点：大门、门卫、校牌
    k0, k1 = z("key_school")
    kx = sp["key_gate"]
    facade(g, k0 + 80, k1 - 20, GROUND - 620, GROUND, "ink", 0.12, 4, (80, 90), 50, brick=False, seed=67)
    g.clear(rect_pts(kx - 160, GROUND - 300, 320, 300))
    g.pen("ink", 0.3).fill(rect_pts(kx - 160, GROUND - 300, 320, 300))
    g.ink.rect(kx - 160, GROUND - 300, 320, 300, lw=3)
    g.clear(rect_pts(kx - 110, GROUND - 240, 220, 240))
    g.pen("ink", 0.6).fill(rect_pts(kx - 110, GROUND - 240, 220, 240))
    signboard(g, kx, GROUND - 270, "实验中学", "mei", 26, pad=8)
    g.clear(rect_pts(k0 + 10, GROUND - 180, 90, 180))
    g.ink.rect(k0 + 10, GROUND - 180, 90, 180, lw=2.6)
    window(g, k0 + 24, GROUND - 160, 62, 60, panes=1)
    # 商场：大橱窗、滚梯
    m0, m1 = z("mall")
    g.clear(rect_pts(m0, GROUND - 700, m1 - m0, 700))
    g.pen("qing", 0.16).fill(rect_pts(m0, GROUND - 700, m1 - m0, 700))
    for r in range(3):
        g.ink.line([(m0, GROUND - 240 - r * 160), (m1, GROUND - 240 - r * 160)], 3)
    for k in range(int((m1 - m0) / 110) + 1):
        fline(g, "ink", [(m0 + k * 110, GROUND - 700), (m0 + k * 110, GROUND - 240)], 1.4, 0.7)
    g.ink.rect(m0, GROUND - 700, m1 - m0, 700, lw=3.4)
    signboard(g, (m0 + m1) / 2, GROUND - 650, "百货大楼", "mei", 40)
    mf = sp["mall_floor"]
    g.clear(rect_pts(mf - 180, GROUND - 230, 260, 230))
    g.pen("qing", 0.24).fill(rect_pts(mf - 180, GROUND - 230, 260, 230))
    g.ink.rect(mf - 180, GROUND - 230, 260, 230, lw=3)
    for k, c in enumerate(("mei", "qing", "mei")):
        g.pen(c, 0.5).fill(rect_pts(mf - 150 + k * 76, GROUND - 160, 46, 110))
        g.ink.circle(mf - 127 + k * 76, GROUND - 180, 16, lw=2)
    esc = [(mf + 110, GROUND), (mf + 330, GROUND - 230), (mf + 360, GROUND - 230), (mf + 140, GROUND)]
    g.pen("ink", 0.3).fill(esc)
    g.ink.poly(esc, 2.6)
    for k in range(9):
        t = k / 9
        g.ink.line([(mf + 116 + 220 * t, GROUND - 230 * t), (mf + 146 + 220 * t, GROUND - 230 * t)], 1.4)
    fd = sp["mall_food"]
    awning(g, fd - 140, fd + 140, GROUND - 260, 40, "mei")
    table(g, fd, GROUND, 140, 76)
    # 大书店：书架，地上坐着人（人由街景层画）
    s0, s1 = z("bookstore")
    facade(g, s0, s1, GROUND - 560, GROUND - 300, "ink", 0.2, 1, (90, 120), 40, brick=False, seed=69)
    g.clear(rect_pts(s0, GROUND - 300, s1 - s0, 300))
    g.pen("mei", 0.1).fill(rect_pts(s0, GROUND - 300, s1 - s0, 300))
    rnd = random.Random(71)
    for r in range(4):
        yy = GROUND - 40 - r * 60
        g.ink.line([(s0 + 20, yy), (s1 - 20, yy)], 2.6)
        x = s0 + 24
        while x < s1 - 30:
            w = rnd.uniform(8, 16)
            h = rnd.uniform(30, 52)
            g.pen(rnd.choice(["mei", "qing", "ink"]), 0.45).fill(rect_pts(x, yy - h, w, h))
            x += w + 2
    signboard(g, (s0 + s1) / 2, GROUND - 330, "书店", "mei", 30, pad=8)
    # 大学：校门的牌坊、小吃街的雨棚
    u0, u1 = z("uni")
    ux = sp["uni_gate"]
    for px in (ux - 150, ux + 150):
        g.clear(rect_pts(px - 28, GROUND - 380, 56, 380))
        g.pen("ink", 0.16).fill(rect_pts(px - 28, GROUND - 380, 56, 380))
        g.ink.rect(px - 28, GROUND - 380, 56, 380, lw=3)
    g.clear(rect_pts(ux - 200, GROUND - 440, 400, 70))
    g.pen("ink", 0.24).fill(rect_pts(ux - 200, GROUND - 440, 400, 70))
    g.ink.rect(ux - 200, GROUND - 440, 400, 70, lw=3)
    g.ink.text("大　学", ux, GROUND - 405, 30)
    for i, sx in enumerate((u0 + 30, u1 - 160)):
        awning(g, sx, sx + 130, GROUND - 230, 36, ["qing", "mei"][i])
    tree(g, u0 + 110, GROUND, 520, 120, "huai", seed=73)
    # 写字楼：一格一格的玻璃
    o0, o1 = z("office")
    g.clear(rect_pts(o0 + 20, -200, o1 - o0 - 40, GROUND + 200))
    g.pen("qing", 0.30).fill(rect_pts(o0 + 20, -200, o1 - o0 - 40, GROUND + 200))
    for yy in range(-180, int(GROUND - 120), 60):
        fline(g, "ink", [(o0 + 20, yy), (o1 - 20, yy)], 1.6, 0.8)
    for xx in range(int(o0 + 20), int(o1 - 10), 70):
        fline(g, "ink", [(xx, -200), (xx, GROUND - 160)], 1.2, 0.6)
    for k in range(12):
        xx = o0 + 20 + (k * 157) % (o1 - o0 - 110)
        yy = -160 + (k * 233) % 700
        g.pen("mei", 0.25).fill(rect_pts(xx - (xx - o0 - 20) % 70, yy - (yy + 180) % 60, 70, 60))
    g.ink.rect(o0 + 20, -200, o1 - o0 - 40, GROUND + 200, lw=3.4)
    g.clear(rect_pts(sp["office_desk"] - 140, GROUND - 160, 280, 160))
    g.pen("ink", 0.4).fill(rect_pts(sp["office_desk"] - 140, GROUND - 160, 280, 160))
    g.ink.rect(sp["office_desk"] - 140, GROUND - 160, 280, 160, lw=3)
    # 回河边：桥头
    g.ink.line([(0, GROUND - 60), (200, GROUND - 60)], 3)
    for x in range(0, 220, 40):
        g.ink.line([(x, GROUND), (x, GROUND - 60)], 2)
    for x in (b0 + 210, 2000 - 60, 2650, 4200):
        lamp(g, x, GROUND + 16, 460, 1)
    ground_street(g, W)


def draw_away(g, sc):
    W = sc["width"]
    sp, ex, zs = sc["spots"], sc["exits"], sc["zones"]
    z = lambda k: zs[k]["span"]  # noqa: E731
    sky(g, W, seed=53, horizon=GROUND - 200, clouds=8)
    # 远景：没有河，一层层新楼，冷一点（墨）
    skyline(g, -40, W + 40, GROUND - 320, seed=55, hmin=160, hmax=460, d=0.09, color="ink")
    # 车站
    s0, s1 = z("station")
    g.clear(rect_pts(s0, GROUND - 460, s1 - s0 + 20, 460))
    g.pen("ink", 0.12).fill(rect_pts(s0, GROUND - 460, s1 - s0 + 20, 460))
    g.ink.rect(s0 - 10, GROUND - 460, s1 - s0 + 30, 460, lw=3.4)
    for k in range(4):
        window(g, s0 + 40 + k * 140, GROUND - 400, 110, 180, panes=2)
    g.clear(rect_pts(s0 + 80, GROUND - 520, s1 - s0 - 160, 60))
    g.pen("qing").fill(rect_pts(s0 + 80, GROUND - 520, s1 - s0 - 160, 60))
    knock(g, "qing", "火 车 站", (s0 + s1) / 2, GROUND - 490, 34)
    clock(g, (s0 + s1) / 2, GROUND - 580, 34)
    for k in range(3):
        g.ink.rect(s0 + 60 + k * 160, GROUND - 180, 100, 180, lw=2.6)
        g.pen("ink", 0.4).fill(rect_pts(s0 + 60 + k * 160, GROUND - 180, 100, 180))
    # 学校：宿舍楼，窗户一格一格
    c0, c1 = z("campus")
    facade(g, c0 + 20, c1 - 20, GROUND - 780, GROUND, "ink", 0.10, 6, (60, 70), 36, brick=False, seed=57, lit={(1, 2), (2, 5), (4, 1), (3, 7)})
    gx = sp["away_gate"]
    g.clear(rect_pts(gx - 110, GROUND - 230, 220, 230))
    g.pen("ink", 0.5).fill(rect_pts(gx - 110, GROUND - 230, 220, 230))
    g.ink.rect(gx - 110, GROUND - 230, 220, 230, lw=3)
    g.clear(rect_pts(gx - 130, GROUND - 270, 260, 40))
    g.ink.rect(gx - 130, GROUND - 270, 260, 40, lw=2.6)
    g.ink.text("学生公寓", gx, GROUND - 250, 24)
    dx = sp["away_desk"]
    g.clear(rect_pts(dx - 120, GROUND - 210, 240, 210))
    g.pen("qing", 0.2).fill(rect_pts(dx - 120, GROUND - 210, 240, 210))
    g.ink.rect(dx - 120, GROUND - 210, 240, 210, lw=3)
    desk(g, dx, GROUND, 180, 1)
    # 夜市：一条街的灯泡、油烟
    n0, n1 = z("market")
    rope = [(n0 + (n1 - n0) * t / 40, GROUND - 400 + 50 * 4 * (t / 40) * (1 - t / 40)) for t in range(41)]
    fline(g, "ink", rope, 1.6)
    for t in range(2, 40, 3):
        bx, by = rope[t]
        g.ink.line([(bx, by), (bx, by + 18)], 1.2)
        g.pen("mei", 0.55).fill(circle_pts(bx, by + 26, 9))
        if t % 9 == 2:
            mark("stall_light", bx, by + 40)
        g.ink.circle(bx, by + 26, 9, lw=1.6)
    for i, (a, b) in enumerate(((n0 + 40, n0 + 300), (n0 + 380, n0 + 640), (n0 + 720, n1 - 40))):
        awning(g, a, b, GROUND - 250, 40, ["mei", "qing", "mei"][i])
        g.clear(rect_pts(a, GROUND - 110, b - a, 110))
        g.pen("ink", 0.3).fill(rect_pts(a, GROUND - 110, b - a, 110))
        g.ink.rect(a, GROUND - 110, b - a, 110, lw=2.6)
        for k in range(3):
            cx = a + 40 + k * 60
            g.ink.line([(cx, GROUND - 120), (cx - 10, GROUND - 170), (cx + 4, GROUND - 220)], 1.6, amp=2.0, density=0.5)
    # 上班的地方：一排一样的窗户
    w0, w1 = z("worksite")
    facade(g, w0 + 20, w1 - 20, GROUND - 640, GROUND, "ink", 0.16, 4, (70, 80), 30, brick=False, seed=59)
    wx = sp["away_work"]
    g.clear(rect_pts(wx - 90, GROUND - 220, 180, 220))
    g.pen("qing", 0.4).fill(rect_pts(wx - 90, GROUND - 220, 180, 220))
    g.ink.rect(wx - 90, GROUND - 220, 180, 220, lw=3)
    g.ink.line([(wx, GROUND - 220), (wx, GROUND)], 2.4)
    # 邮局：绿色信筒
    p0, p1 = z("post")
    facade(g, p0 + 20, p1 - 20, GROUND - 380, GROUND, "qing", 0.32, 1, (100, 120), 60, brick=False, seed=61)
    signboard(g, (p0 + p1) / 2, GROUND - 420, "邮电局", "qing", 30, pad=8)
    bx = sp["post_box"]
    g.clear(rect_pts(bx - 34, GROUND - 170, 68, 170))
    g.pen("qing").fill(rect_pts(bx - 34, GROUND - 170, 68, 170))
    g.ink.rect(bx - 34, GROUND - 170, 68, 170, lw=2.8)
    g.clear(ellipse_pts(bx, GROUND - 170, 40, 14))
    g.pen("qing").fill(ellipse_pts(bx, GROUND - 172, 40, 14))
    g.ink.ellipse(bx, GROUND - 172, 40, 14, lw=2.4)
    g.clear(rect_pts(bx - 22, GROUND - 140, 44, 8), colors=["qing"])
    g.ink.rect(bx - 22, GROUND - 140, 44, 8, lw=1.6)
    # 去出租屋的巷子
    rx = ex["to_rental"][0]
    g.clear(rect_pts(rx - 70, GROUND - 300, 140, 300))
    g.pen("ink", 0.55).fill(rect_pts(rx - 70, GROUND - 300, 140, 300))
    fhatch(g, "ink", rx - 70, GROUND - 300, 140, 300, 30, 12, 1.0, 0.5)
    g.ink.rect(rx - 70, GROUND - 300, 140, 300, lw=3)
    for x in (700, 1660, 2540, 3360):
        tree(g, x, GROUND, 420, 90, "young", seed=int(x))
    ground_street(g, W)


def draw_rental(g, sc):
    W = sc["width"]
    sp, ex, zs = sc["spots"], sc["exits"], sc["zones"]
    top = GROUND - 460
    sky(g, W, seed=61, horizon=top)
    # 屋外是另一栋楼（窗对着窗）
    facade(g, -40, W + 40, -260, top, "mei", 0.36, 2, (110, 120), 90, brick=True, seed=63, cornice=False)
    slab(g, -40, W + 40, top, top + 30)
    r0, r1 = zs["rent_room"]["span"]
    h0, h1 = zs["rent_hall"]["span"]
    g.clear(rect_pts(r0, top + 30, r1 - r0, GROUND - top - 30))
    g.pen("ink", 0.05).fill(rect_pts(r0, top + 30, r1 - r0, GROUND - top - 30))
    g.clear(rect_pts(h0, top + 30, h1 - h0, GROUND - top - 30))
    g.pen("ink", 0.14).fill(rect_pts(h0, top + 30, h1 - h0, GROUND - top - 30))
    # 墙皮掉了一块
    g.pen("ink", 0.12).fill([(r0 + 600, top + 100), (r0 + 680, top + 90), (r0 + 700, top + 150), (r0 + 640, top + 170)])
    window(g, sp["rent_desk"] - 150, top + 90, 300, 200, panes=4, curtain="qing")
    bed(g, sp["rent_bed"], GROUND, 280, 1, "qing")
    # 折叠桌、镜子
    dx = sp["rent_desk"]
    table(g, dx, GROUND, 140, 80)
    g.ink.line([(dx - 50, GROUND - 68), (dx + 50, GROUND)], 1.6)
    g.ink.line([(dx + 50, GROUND - 68), (dx - 50, GROUND)], 1.6)
    stool(g, dx + 110, GROUND, "ink")
    g.clear(rect_pts(r1 - 180, top + 110, 70, 110))
    g.ink.rect(r1 - 180, top + 110, 70, 110, lw=2.6)
    g.qing.line([(r1 - 170, top + 130), (r1 - 150, top + 116)], 1.8)
    # 墙上的挂钩，一年比一年多
    for k in range(5):
        hx = r0 + 420 + k * 34
        g.ink.line([(hx, top + 70), (hx, top + 84), (hx + 8, top + 90)], 2)
    cut_wall(g, r1, top + 30, GROUND - 240, 26, "ink")
    g.ink.line([(r1 - 13, GROUND - 240), (r1 - 13, GROUND)], 3)
    # 走廊：公用水池、四个灶眼的灶台
    bx = sp["rent_basin"]
    g.clear(rect_pts(bx - 80, GROUND - 100, 160, 100))
    g.pen("ink", 0.25).fill(rect_pts(bx - 80, GROUND - 100, 160, 100))
    g.ink.rect(bx - 80, GROUND - 100, 160, 100, lw=2.6)
    g.ink.line([(bx, GROUND - 100), (bx, GROUND - 150), (bx + 30, GROUND - 150)], 3)
    sx = sp["rent_stove"]
    g.clear(rect_pts(sx - 180, GROUND - 90, 360, 90))
    g.pen("ink", 0.3).fill(rect_pts(sx - 180, GROUND - 90, 360, 90))
    g.ink.rect(sx - 180, GROUND - 90, 360, 90, lw=2.8)
    for k in range(4):
        cx = sx - 135 + k * 90
        g.ink.ellipse(cx, GROUND - 96, 30, 6, lw=2.4)
        g.clear(rect_pts(cx - 20, GROUND - 60, 40, 22))
        g.ink.rect(cx - 20, GROUND - 60, 40, 22, lw=1.6)
        g.ink.text(str(201 + k), cx, GROUND - 49, 14)
    bulb(g, (h0 + h1) / 2, top + 30, 80)
    door(g, ex["to_away"][0] - 10, GROUND, 90, 220, open_=0.6)
    ground_floor(g, W, GROUND, "ink", 0.16)


def draw_newhome(g, sc):
    W = sc["width"]
    sp, ex, zs = sc["spots"], sc["exits"], sc["zones"]
    f0, f1 = zs["flat"]["span"]
    l0, l1 = zs["landing"]["span"]
    ga0, ga1 = zs["garden"]["span"]
    top = GROUND - 440
    sky(g, W, seed=71, horizon=GROUND - 200)
    # 远处：河、对岸那片老楼顶（从阳台看出去）
    skyline(g, -40, W + 40, GROUND - 520, seed=73, hmin=40, hmax=140, d=0.18, color="mei")
    g.pen("qing", 0.3).fill(rect_pts(-40, GROUND - 520, W + 80, 30))
    # 楼：高层，上下都是一样的人家
    facade(g, f0 - 40, l1, -200, top - 30, "ink", 0.08, 2, (130, 150), 80, brick=False, seed=75, cornice=False)
    slab(g, f0 - 40, l1 + 20, top - 30, top)
    g.clear(rect_pts(f0, top, f1 - f0, GROUND - top))
    g.pen("ink", 0.03).fill(rect_pts(f0, top, f1 - f0, GROUND - top))
    # 屋里：新床、餐桌、书桌，墙白地亮
    bed(g, sp["new_bed"], GROUND, 260, 1, "mei")
    table(g, sp["new_table"], GROUND, 170, 80, cloth="qing")
    for d in (-110, 110):
        g.ink.line([(sp["new_table"] + d - 18, GROUND), (sp["new_table"] + d - 18, GROUND - 50), (sp["new_table"] + d + 18, GROUND - 50), (sp["new_table"] + d + 18, GROUND)], 2.6)
    desk(g, sp["new_desk"], GROUND, 150, -1, books=True)
    # 一样老物件：一只旧暖壶放在桌上
    g.clear(rect_pts(sp["new_table"] - 50, GROUND - 140, 26, 58))
    g.pen("mei", 0.6).fill(rect_pts(sp["new_table"] - 50, GROUND - 140, 26, 58))
    g.ink.rect(sp["new_table"] - 50, GROUND - 140, 26, 58, lw=2)
    frame_pic(g, sp["new_table"] - 60, top + 70, 120, 90, "qing", "two")
    # 阳台：落地窗
    bx = sp["new_balcony"]
    g.clear(rect_pts(bx - 150, top + 30, 300, GROUND - top - 30))
    g.pen("qing", 0.12).fill(rect_pts(bx - 150, top + 30, 300, GROUND - top - 30))
    for k in range(4):
        g.ink.line([(bx - 150 + k * 100, top + 30), (bx - 150 + k * 100, GROUND)], 2.4)
    g.ink.rect(bx - 150, top + 30, 300, GROUND - top - 30, lw=3)
    g.ink.line([(bx - 150, GROUND - 110), (bx + 150, GROUND - 110)], 3)
    for k in range(3):
        g.pen("qing").line([(bx + 60 + k * 20, GROUND - 110), (bx + 50 + k * 26, GROUND - 160)], 2.4)
    cut_wall(g, f0, top, GROUND, 30, "ink")
    cut_wall(g, f1, top, GROUND - 240, 30, "ink")
    # 电梯间：两扇对着的防盗门、电梯门
    g.clear(rect_pts(l0, top, l1 - l0, GROUND - top))
    g.pen("ink", 0.12).fill(rect_pts(l0, top, l1 - l0, GROUND - top))
    door(g, l0 + 80, GROUND, 96, 220, "ink", 0.45)
    door(g, l1 - 80, GROUND, 96, 220, "ink", 0.45)
    ex_ = (l0 + l1) / 2
    g.clear(rect_pts(ex_ - 70, GROUND - 230, 140, 230))
    g.pen("ink", 0.22).fill(rect_pts(ex_ - 70, GROUND - 230, 140, 230))
    g.ink.rect(ex_ - 70, GROUND - 230, 140, 230, lw=3)
    g.ink.line([(ex_, GROUND - 230), (ex_, GROUND)], 2)
    g.ink.rect(ex_ + 86, GROUND - 140, 18, 34, lw=1.6)
    cut_wall(g, l1, top - 30, GROUND - 240, 30, "ink")
    # 花园：新栽的细树、步道、长椅、门岗
    for x in (ga0 + 140, ga0 + 520, ga0 + 860):
        tree(g, x, GROUND, 400, 80, "young", seed=int(x))
    bench(g, sp["garden_path"] + 120, GROUND, 160, "ink")
    gx = ex["to_across"][0]
    g.clear(rect_pts(gx - 150, GROUND - 300, 100, 300))
    g.pen("ink", 0.2).fill(rect_pts(gx - 150, GROUND - 300, 100, 300))
    g.ink.rect(gx - 150, GROUND - 300, 100, 300, lw=3)
    g.ink.line([(gx - 50, GROUND - 120), (gx + 40, GROUND - 120)], 5)
    g.pen("mei").line([(gx - 40, GROUND - 120), (gx - 10, GROUND - 120)], 5)
    ground_floor(g, W, GROUND, "ink", 0.06, 120)
    # 花园的路砖，有一块是老厂的红砖
    g.pen("ink", 0.12).fill(rect_pts(ga0, GROUND, ga1 - ga0 + 40, 30))
    for x in range(int(ga0), int(ga1) + 40, 50):
        fline(g, "ink", [(x, GROUND + 2), (x, GROUND + 30)], 1.2, 0.6)
    rb = sp["garden_path"] - 25
    g.clear(rect_pts(rb, GROUND + 2, 50, 28))
    g.pen("mei", 0.6).fill(rect_pts(rb, GROUND + 2, 50, 28))
    g.ink.rect(rb, GROUND + 2, 50, 28, lw=1.4)


def draw_park(g, sc):
    W = sc["width"]
    sp, ex, zs = sc["spots"], sc["exits"], sc["zones"]
    z = lambda k: zs[k]["span"]  # noqa: E731
    sky(g, W, seed=81, horizon=GROUND - 160)
    skyline(g, -40, W + 40, GROUND - 330, seed=83, hmin=60, hmax=240, d=0.08)
    # 湖：在步道后头一大片（远处的岸、水）
    l0, l1 = z("lake_path")
    lake = ellipse_pts((l0 + l1) / 2 + 200, GROUND - 120, (l1 - l0) / 2 + 500, 90, 80)
    g.clear(lake)
    g.pen("qing", 0.4).fill(lake)
    g.qing.poly(lake, 2.4, amp=1.0)
    rnd = random.Random(85)
    for _ in range(40):
        x = rnd.uniform(l0 - 200, l1 + 500)
        y = rnd.uniform(GROUND - 190, GROUND - 60)
        g.qing.line([(x, y), (x + rnd.uniform(30, 80), y)], 2, amp=0.4)
    for lx in (900, 1900, 2900):
        lamp(g, lx, GROUND, 400, 1)
    # 公园门口
    p0, p1 = z("park_gate")
    for px in (80, 340):
        g.clear(rect_pts(px - 26, GROUND - 330, 52, 330))
        g.pen("qing", 0.5).fill(rect_pts(px - 26, GROUND - 330, 52, 330))
        g.ink.rect(px - 26, GROUND - 330, 52, 330, lw=3)
    roofp = [(30, GROUND - 330), (210, GROUND - 400), (390, GROUND - 330)]
    g.clear(roofp)
    g.pen("qing").fill(roofp)
    g.ink.poly(roofp, 3)
    signboard(g, 210, GROUND - 300, "人民公园", "mei", 26, pad=8)
    # 去医院的路口
    hx = ex["to_hospital"][0]
    g.ink.line([(hx, GROUND), (hx, GROUND - 300)], 4)
    g.clear(rect_pts(hx - 10, GROUND - 330, 120, 36))
    g.qing.rect(hx - 10, GROUND - 330, 120, 36, fill=True)
    knock(g, "qing", "医院 →", hx + 50, GROUND - 312, 20)
    # 老树、柳树
    for i, (x, kind, h, r) in enumerate(((700, "huai", 640, 200), (1180, "willow", 600, 160), (1560, "huai", 600, 170), (2420, "huai", 620, 190))):
        tree(g, x, GROUND, h, r, kind, seed=87 + i)
    # 长椅（椅背钉小铜牌）
    for bx in (sp["lake_walk"] - 200, sp["lake_walk"] + 260):
        bench(g, bx, GROUND, 170, "qing")
        g.pen("mei").fill(rect_pts(bx - 12, GROUND - 86, 24, 8))
    # 亭子
    pv = sp["pavilion_choir"]
    for px in (pv - 200, pv - 70, pv + 70, pv + 200):
        g.clear(rect_pts(px - 12, GROUND - 330, 24, 330))
        g.pen("mei", 0.7).fill(rect_pts(px - 12, GROUND - 330, 24, 330))
        g.ink.rect(px - 12, GROUND - 330, 24, 330, lw=2.4)
    roofp = [(pv - 280, GROUND - 330), (pv - 220, GROUND - 380), (pv - 40, GROUND - 470), (pv, GROUND - 500), (pv + 40, GROUND - 470), (pv + 220, GROUND - 380), (pv + 280, GROUND - 330), (pv + 250, GROUND - 350), (pv - 250, GROUND - 350)]
    g.clear(roofp)
    g.pen("qing", 0.7).fill(roofp)
    g.ink.poly(roofp, 3)
    for k in range(9):
        fline(g, "ink", [(pv - 220 + k * 55, GROUND - 360), (pv - 120 + k * 30, GROUND - 450)], 1.4, 0.7)
    g.ink.line([(pv - 230, GROUND - 120), (pv + 230, GROUND - 120)], 3)
    g.pen("mei", 0.4).fill(rect_pts(pv - 230, GROUND - 120, 460, 12))
    # 空地：地上用水写的大字（快干了，淡淡的）
    sq = sp["square_ground"]
    g.pen("ink", 0.16).text("永", sq - 60, GROUND + 14, 38)
    g.pen("ink", 0.10).text("和", sq + 20, GROUND + 14, 38)
    g.ink.line([(sq + 120, GROUND), (sq + 200, GROUND - 160)], 3)
    g.pen("ink").fill(rect_pts(sq + 112, GROUND - 6, 18, 10))
    g.ink.ellipse(sq + 230, GROUND - 14, 26, 10, lw=2)
    ground_floor(g, W, GROUND, "ink", 0.12, 0)
    g.pen("mei", 0.14).fill(rect_pts(-40, GROUND, W + 80, 30))
    for k in range(int(W / 46)):
        g.ink.dot(k * 46 + (k * 17) % 23, GROUND + 10 + (k * 7) % 14, 1.8)


def draw_hospital(g, sc):
    W = sc["width"]
    sp, zs, ex = sc["spots"], sc["zones"], sc["exits"]
    z = lambda k: zs[k]["span"]  # noqa: E731
    top = GROUND - 460
    sky(g, W, seed=91, horizon=top)
    facade(g, -40, W + 40, -220, top - 30, "ink", 0.05, 2, (110, 120), 70, brick=False, seed=93, cornice=False)
    for cx in (520, 2240):
        g.clear(rect_pts(cx - 60, -130, 120, 140))
        g.pen("mei").fill(rect_pts(cx - 18, -110, 36, 100))
        g.pen("mei").fill(rect_pts(cx - 50, -78, 100, 36))
    slab(g, -40, W + 40, top - 30, top)
    a0, a1 = z("lobby")
    w0, w1 = z("ward_hall")
    r0, r1 = z("ward")
    for x0, x1, d in ((a0, a1, 0.06), (w0, w1, 0.12), (r0, r1, 0.04)):
        g.clear(rect_pts(x0, top, x1 - x0, GROUND - top))
        g.pen("ink", d).fill(rect_pts(x0, top, x1 - x0, GROUND - top))
        g.pen("qing", 0.22).fill(rect_pts(x0, GROUND - 120, x1 - x0, 120))
        g.ink.line([(x0, GROUND - 120), (x1, GROUND - 120)], 2.4)
    # 挂号大厅：一排窗口（往里让了让，门口是大玻璃门）
    q0 = sp.get("hosp_queue", a0 + 520)
    for k in range(3):
        wx = q0 + k * 140
        g.clear(rect_pts(wx - 60, GROUND - 270, 120, 110))
        g.pen("qing", 0.2).fill(rect_pts(wx - 60, GROUND - 270, 120, 110))
        g.ink.rect(wx - 60, GROUND - 270, 120, 110, lw=2.6)
        g.ink.arc(wx, GROUND - 160, 26, math.pi, math.tau, lw=2.4)
        g.ink.line([(wx - 80, GROUND - 160), (wx + 80, GROUND - 160)], 4)
        g.clear(rect_pts(wx - 30, GROUND - 310, 60, 26))
        g.mei.rect(wx - 30, GROUND - 310, 60, 26, fill=True)
        knock(g, "mei", str(k + 1), wx, GROUND - 297, 18)
    signboard(g, q0 + 140, top + 60, "挂号收费", "mei", 30, pad=8)
    # 大门：两扇玻璃门，门外看得见公交站牌；顶上吊一块指路牌，看完病从这儿坐车回家
    dx = ex.get("to_street", (a0 + 320, GROUND))[0]
    d0, d1 = dx - 80, dx + 80
    g.clear(rect_pts(d0, GROUND - 250, d1 - d0, 250))
    g.pen("qing", 0.14).fill(rect_pts(d0, GROUND - 250, d1 - d0, 250))
    g.pen("ink", 0.08).fill(rect_pts(d0, GROUND - 60, d1 - d0, 60))
    # 门外：站牌、一截马路牙子
    g.pen("qing", 0.45).line([(dx + 34, GROUND - 40), (dx + 34, GROUND - 190)], 3.4, amp=0.1)
    g.pen("qing", 0.55).fill(rect_pts(dx + 16, GROUND - 230, 36, 54))
    g.pen("qing", 0.35).line([(d0, GROUND - 40), (d1, GROUND - 40)], 2, amp=0.2)
    g.ink.rect(d0, GROUND - 250, d1 - d0, 250, lw=3.2, amp=0.3)
    g.ink.line([(d0, GROUND - 200), (d1, GROUND - 200)], 3)
    g.ink.line([(dx, GROUND - 200), (dx, GROUND)], 3)
    for s in (-1, 1):
        g.ink.line([(dx + s * 14, GROUND - 120), (dx + s * 14, GROUND - 80)], 4)
        g.qing.line([(dx + s * 60, GROUND - 180), (dx + s * 40, GROUND - 150)], 1.6, amp=0.1)
    # 玻璃上贴的一张纸：站名
    g.clear(rect_pts(dx - 62, GROUND - 160, 40, 56))
    g.ink.rect(dx - 62, GROUND - 160, 40, 56, lw=1.4, amp=0.4)
    g.ink.text("车站", dx - 42, GROUND - 132, 14, vertical=True)
    g.ink.line([(dx - 30, top + 14), (dx - 30, top + 60)], 1.4)
    g.ink.line([(dx + 30, top + 14), (dx + 30, top + 60)], 1.4)
    g.clear(rect_pts(dx - 90, top + 60, 180, 34))
    g.pen("qing").fill(rect_pts(dx - 90, top + 60, 180, 34))
    g.ink.rect(dx - 90, top + 60, 180, 34, lw=2.2)
    knock(g, "qing", "出口 · 公交车站", dx, top + 77, 18)
    # 走廊：两边长椅、尽头开水房冒白气
    for bx in range(int(w0 + 140), int(w1 - 200), 260):
        bench(g, bx, GROUND, 200, "qing", back=True)
    hx = w1 - 110
    g.clear(rect_pts(hx - 60, GROUND - 230, 120, 230))
    g.pen("ink", 0.35).fill(rect_pts(hx - 60, GROUND - 230, 120, 230))
    g.ink.rect(hx - 60, GROUND - 230, 120, 230, lw=3)
    g.ink.text("开水", hx, GROUND - 256, 22)
    for k in range(3):
        cx = hx - 30 + k * 30
        g.ink.line([(cx, GROUND - 240), (cx - 10, GROUND - 290), (cx + 6, GROUND - 340)], 1.6, amp=2.0, density=0.5)
    bulb(g, (w0 + w1) / 2 - 100, top, 70)
    cut_wall(g, a1, top, GROUND - 250, 28, "ink")
    cut_wall(g, w1, top, GROUND - 250, 28, "ink")
    # 病房：三张床、窗朝着河、陪床的折叠椅
    window(g, r0 + 260, top + 70, 360, 200, panes=4, curtain="qing")
    g.pen("qing", 0.3).fill(rect_pts(r0 + 262, top + 210, 356, 58))
    for k, bx in enumerate((r0 + 170, r0 + 520, r1 - 160)):
        if abs(bx - sp["ward_chair"]) < 120:
            bx = sp["ward_chair"] - 220
        g.ink.line([(bx - 130, GROUND), (bx - 130, GROUND - 120)], 4)
        g.ink.line([(bx + 130, GROUND), (bx + 130, GROUND - 90)], 4)
        g.clear(rect_pts(bx - 130, GROUND - 90, 260, 24))
        g.pen("ink", 0.12).fill(rect_pts(bx - 130, GROUND - 90, 260, 24))
        g.ink.rect(bx - 130, GROUND - 90, 260, 24, lw=2.4)
        g.pen("qing", 0.2).fill([(bx - 90, GROUND - 90), (bx + 126, GROUND - 90), (bx + 126, GROUND - 110), (bx - 90, GROUND - 116)])
        g.ink.line([(bx - 90, GROUND - 116), (bx + 126, GROUND - 110)], 2)
        g.ink.ellipse(bx - 106, GROUND - 100, 22, 10, lw=2)
        for k2 in range(5):
            fline(g, "qing", [(bx - 80 + k2 * 44, GROUND - 112), (bx - 80 + k2 * 44, GROUND - 90)], 1.4)
    cx = sp["ward_chair"]
    g.ink.line([(cx - 26, GROUND), (cx + 22, GROUND - 60)], 3)
    g.ink.line([(cx + 26, GROUND), (cx - 22, GROUND - 60)], 3)
    g.pen("mei", 0.6).fill(rect_pts(cx - 28, GROUND - 64, 56, 10))
    g.ink.rect(cx - 28, GROUND - 64, 56, 10, lw=2)
    g.ink.line([(cx - 24, GROUND - 60), (cx - 30, GROUND - 130)], 3)
    g.pen("mei", 0.6).fill(rect_pts(cx - 34, GROUND - 130, 12, 50))
    # 输液架
    g.ink.line([(cx + 90, GROUND), (cx + 90, GROUND - 260)], 2.6)
    g.ink.line([(cx + 70, GROUND - 260), (cx + 110, GROUND - 260)], 2.6)
    g.clear(rect_pts(cx + 96, GROUND - 254, 20, 40))
    g.ink.rect(cx + 96, GROUND - 254, 20, 40, lw=1.6)
    cut_wall(g, 0, top, GROUND, 30, "ink")
    cut_wall(g, W, top, GROUND, 30, "ink")
    ground_floor(g, W, GROUND, "ink", 0.08, 80)


# ----------------------------------------------------------------------
# 门外的三个世界：早市（清贫）、海边（殷实）、乡下（小康）
# 三张图一眼要分得开：早市墨版压得重、天刚亮；海边青版、海平线低、天大；乡下梅版的土和玉米、树和河沟点青。
# ----------------------------------------------------------------------

def pingfang(g, x0, x1, eave, color="ink", d=0.16, seed=1, windows=(), door=None, ridge=56, tiles="ink"):
    """一排平房的后墙和瓦顶（侧面看是一道墙、一坡瓦）。windows: [(x, w)]，door: (x, w)。"""
    pts = rect_pts(x0, eave, x1 - x0, GROUND - eave)
    g.clear(pts)
    g.pen(color, d).fill(pts)
    fbricks(g, x0, eave, x1 - x0, GROUND - eave, 28, 10, 0.8, 0.3, seed=seed)
    roof = [(x0 - 16, eave + 4), (x0 + 10, eave - ridge), (x1 - 10, eave - ridge), (x1 + 16, eave + 4)]
    g.clear(roof)
    g.pen(tiles, 0.42 if tiles == "ink" else 0.5).fill(roof)
    for k in range(int((x1 - x0) / 14)):
        xx = x0 + 4 + k * 14
        fline(g, "ink", [(xx, eave - ridge + 4), (xx - 3, eave + 2)], 1.1, 0.55)
    g.ink.poly(roof, w=2.6, amp=0.4)
    g.ink.line([(x0 + 6, eave - ridge - 4), (x1 - 6, eave - ridge - 4)], 5.0, amp=0.3)
    g.ink.line([(x0, eave), (x0, GROUND)], 2.6, amp=0.4)
    g.ink.line([(x1, eave), (x1, GROUND)], 2.6, amp=0.4)
    for wx, ww in windows:
        wy = eave + 46
        g.clear(rect_pts(wx - ww / 2, wy, ww, 70))
        g.pen("ink", 0.5).fill(rect_pts(wx - ww / 2, wy, ww, 70))
        g.ink.rect(wx - ww / 2, wy, ww, 70, lw=2.4, amp=0.3)
        for k in range(1, 3):
            fline(g, "ink", [(wx - ww / 2 + ww * k / 3, wy), (wx - ww / 2 + ww * k / 3, wy + 70)], 1.4, 0.9)
        g.ink.line([(wx - ww / 2 - 6, wy + 74), (wx + ww / 2 + 6, wy + 74)], 3, amp=0.3)
    if door:
        dx, dw = door
        g.clear(rect_pts(dx - dw / 2, GROUND - 200, dw, 200))
        g.pen("ink", 0.62).fill(rect_pts(dx - dw / 2, GROUND - 200, dw, 200))
        g.ink.rect(dx - dw / 2, GROUND - 200, dw, 200, lw=2.6, amp=0.3)


def tarp(g, x0, x1, y, depth=42, sag=16, poles=240, color="ink", d=0.44, patches=()):
    """帆布棚：前檐在 y，往后高 depth；竹竿之间布兜下来一点。patches: {段号: (色, 浓度)} 补上的塑料布。"""
    n = max(1, round((x1 - x0) / poles))
    xs = [x0 + (x1 - x0) * i / n for i in range(n + 1)]
    bottom = []
    for i in range(n):
        a, b = xs[i], xs[i + 1]
        bottom += [(a + (b - a) * t / 8, y + sag * 4 * (t / 8) * (1 - t / 8)) for t in range(8)]
    bottom.append((x1, y))
    pts = [(x0 - 10, y - depth)] + [(x1 + 10, y - depth)] + bottom[::-1]
    g.clear(pts)
    g.pen(color, d).fill(pts)
    for i in range(n):
        spec = dict(patches).get(i)
        a, b = xs[i], xs[i + 1]
        seg = [(a, y - depth)] + [(b, y - depth)] + [p for p in bottom if a <= p[0] <= b][::-1]
        if spec:
            g.pen(spec[0], spec[1]).fill(seg)
        # 布褶：几道斜的折痕
        for k in range(1, 5):
            fx = a + (b - a) * k / 5
            fline(g, "ink", [(fx - 6, y - depth + 4), (fx + 4, y + sag * 0.6)], 1.2, 0.5)
    g.ink.poly(pts, w=2.4, amp=0.5)
    for px in xs:
        # 竹竿：一道粗、一道细，几个竹节
        g.ink.line([(px, y - depth - 14), (px + 2, GROUND)], 5, amp=0.5)
        for k in range(1, 6):
            yy = y + (GROUND - y) * k / 6
            fline(g, "ink", [(px - 4, yy), (px + 6, yy)], 1.6, 0.8)
    return xs


def bulb_string(g, x0, x1, y, step=104, sag=26, lit_every=2, posts=None):
    """一串灯泡：一根电线兜着，隔一段一只裸灯泡（梅色的暖光）。"""
    posts = posts or [x0, x1]
    for a, b in zip(posts, posts[1:]):
        fline(g, "ink", [(a + (b - a) * t / 20, y + sag * 4 * (t / 20) * (1 - t / 20)) for t in range(21)], 1.4, 0.95)
    i = 0
    x = x0 + step / 2
    while x < x1:
        seg = max(0, min(len(posts) - 2, next((j for j in range(len(posts) - 1) if posts[j] <= x <= posts[j + 1]), 0)))
        a, b = posts[seg], posts[seg + 1]
        t = (x - a) / max(1.0, b - a)
        wy = y + sag * 4 * t * (1 - t)
        g.ink.line([(x, wy), (x, wy + 16)], 1.4, amp=0.1)
        g.pen("ink").fill(rect_pts(x - 4, wy + 14, 8, 8))
        g.pen("mei", 0.07).fill(circle_pts(x, wy + 31, 34))
        g.clear(circle_pts(x, wy + 31, 9))
        g.pen("mei", 0.62).fill(circle_pts(x, wy + 31, 9))
        g.ink.circle(x, wy + 31, 9, lw=1.6)
        if i % lit_every == 0:
            mark("stall_light", x, wy + 40)
        i += 1
        x += step


def produce(g, cx, base, w, kind, seed=1):
    """一堆菜码在板子上：西红柿、黄瓜、圆白菜、土豆、鸡蛋。从下往上码成小山。"""
    rnd = random.Random(seed)
    r = {"tomato": 11, "cabbage": 21, "potato": 10, "egg": 7, "melon": 24, "peach": 10}.get(kind, 10)
    if kind == "cucumber":
        for row in range(4):
            n = int(w / 26) - row
            for i in range(max(0, n)):
                x = cx - w / 2 + 16 + row * 13 + i * 26
                y = base - 6 - row * 10
                g.pen("qing", 0.75).line([(x - 9, y), (x + 9, y - 3)], 9, amp=0.3)
                g.ink.line([(x - 12, y + 1), (x - 8, y)], 2, amp=0.1)
        return
    if kind == "scallion":
        for i in range(int(w / 9)):
            x = cx - w / 2 + 6 + i * 9
            g.pen("qing", 0.7).line([(x, base - 22), (x + rnd.uniform(-8, 8), base - rnd.uniform(70, 96))], 3.2, amp=0.8)
            g.ink.line([(x, base), (x, base - 22)], 3, amp=0.2, density=0.3)
        g.pen("mei", 0.8).line([(cx - w / 2, base - 18), (cx + w / 2, base - 18)], 3, amp=0.2)
        return
    n0 = max(1, int(w / (r * 2)))
    for rows in range(min(n0, {"cabbage": 2, "melon": 2}.get(kind, 3))):
        n = n0 - rows
        for i in range(n):
            x = cx - (n - 1) * r + i * 2 * r + rnd.uniform(-1.5, 1.5)
            y = base - r - rows * r * 1.62
            if kind == "tomato":
                g.clear(circle_pts(x, y, r))
                g.pen("mei", 0.82).fill(circle_pts(x, y, r))
                g.ink.arc(x, y, r, math.pi * 0.1, math.pi * 0.9, lw=1.6)
                g.pen("qing").line([(x - 3, y - r + 2), (x + 3, y - r - 1)], 2.4, amp=0.1)
            elif kind == "peach":
                g.clear(circle_pts(x, y, r))
                g.pen("mei", 0.45).fill(circle_pts(x, y, r))
                g.ink.circle(x, y, r, lw=1.4)
            elif kind == "cabbage":
                g.clear(circle_pts(x, y, r))
                g.pen("qing", 0.42).fill(circle_pts(x, y, r))
                g.qing.arc(x, y, r, math.pi * 1.0, math.pi * 1.9, lw=2.2)
                g.qing.arc(x - 4, y + 2, r * 0.6, math.pi * 1.1, math.pi * 1.8, lw=1.6)
                g.ink.arc(x, y, r, 0.1, math.pi * 0.9, lw=1.6)
            elif kind == "melon":
                g.clear(circle_pts(x, y, r))
                g.pen("qing", 0.55).fill(circle_pts(x, y, r))
                for k in (-0.5, 0, 0.5):
                    g.ink.arc(x + k * r * 0.9, y, r * 0.9, math.pi * 1.25, math.pi * 1.75, lw=2.0)
                g.ink.circle(x, y, r, lw=1.6)
            elif kind == "egg":
                g.clear(ellipse_pts(x, y, r, r * 1.25))
                g.pen("mei", 0.08).fill(ellipse_pts(x, y, r, r * 1.25))
                g.ink.ellipse(x, y, r, r * 1.25, lw=1.2)
            else:  # potato
                g.clear(ellipse_pts(x, y, r * 1.2, r))
                g.pen("ink", 0.32).fill(ellipse_pts(x, y, r * 1.2, r))
                g.ink.ellipse(x, y, r * 1.2, r, lw=1.4)


def basket(g, cx, base, w=70, h=46, color="ink", d=0.18, load=None, seed=1):
    """竹筐：上宽下窄，编出来的斜纹；load 是筐里码的菜。"""
    pts = [(cx - w / 2, base - h), (cx + w / 2, base - h), (cx + w / 2 - 8, base), (cx - w / 2 + 8, base)]
    g.clear(pts)
    g.pen(color, d).fill(pts)
    fhatch(g, "ink", cx - w / 2, base - h, w, h, 60, 8, 1.0, 0.5)
    fhatch(g, "ink", cx - w / 2, base - h, w, h, -60, 8, 1.0, 0.35)
    g.ink.poly(pts, w=2.2, amp=0.3)
    g.ink.line([(cx - w / 2 - 3, base - h), (cx + w / 2 + 3, base - h)], 3.4, amp=0.2)
    if load:
        produce(g, cx, base - h + 4, w - 6, load, seed)


def steelyard(g, x, y, L=130, pan=True):
    """杆秤：提绳挂在 x，杆往右，秤盘往左挂下来，秤砣在杆上。"""
    g.ink.line([(x, y), (x, y + 26)], 1.4, amp=0.1)
    g.ink.line([(x - 26, y + 30), (x + L, y + 22)], 3.2, amp=0.1)
    for k in range(1, 9):
        g.ink.dot(x + k * L / 9, y + 30 - 8 * k / 9 - 1.5, 1.4)
    wx = x + L * 0.7
    g.ink.line([(wx, y + 25), (wx, y + 40)], 1.2, amp=0.1)
    g.pen("ink").fill([(wx - 7, y + 40), (wx + 7, y + 40), (wx + 10, y + 56), (wx - 10, y + 56)])
    if pan:
        px = x - 22
        for dx in (-22, 0, 22):
            g.ink.line([(px, y + 30), (px + dx, y + 84)], 1.0, amp=0.1)
        g.clear(ellipse_pts(px, y + 86, 26, 6))
        g.pen("ink", 0.3).fill(ellipse_pts(px, y + 86, 26, 6))
        g.ink.ellipse(px, y + 86, 26, 6, lw=1.6)


def plank_stall(g, x0, x1, base=GROUND, h=78, legs="crate"):
    """一块门板架在两只箱子或板凳上：早市的摊子就是这么支的。"""
    top = base - h
    g.clear(rect_pts(x0, top, x1 - x0, 12))
    g.pen("ink", 0.36).fill(rect_pts(x0, top, x1 - x0, 12))
    g.ink.rect(x0, top, x1 - x0, 12, lw=2.4, amp=0.3)
    for lx in (x0 + 14, x1 - 64):
        if legs == "crate":
            pts = rect_pts(lx, top + 12, 50, h - 12)
            g.clear(pts)
            g.pen("mei", 0.18).fill(pts)
            g.pen("ink", 0.14).fill(pts)
            g.ink.rect(lx, top + 12, 50, h - 12, lw=2.0, amp=0.3)
            g.ink.line([(lx, top + 12 + (h - 12) * 0.45), (lx + 50, top + 12 + (h - 12) * 0.45)], 1.6, amp=0.2)
        else:
            g.ink.line([(lx + 6, top + 12), (lx, base)], 3.4)
            g.ink.line([(lx + 44, top + 12), (lx + 50, base)], 3.4)
            g.ink.line([(lx + 4, top + 40), (lx + 46, top + 40)], 2)
    return top


def crate_stack(g, x, base, cols=2, rows=3, w=58, h=40, color="qing", d=0.5, seed=1):
    """塑料筐摞起来：一格一格的透气孔。"""
    rnd = random.Random(seed)
    for c in range(cols):
        for r in range(rows):
            if r == rows - 1 and rnd.random() < 0.3:
                continue
            cx = x + c * (w + 4) + (r % 2) * 3
            cy = base - (r + 1) * h
            pts = rect_pts(cx, cy, w, h)
            g.clear(pts)
            g.pen(color, d).fill(pts)
            for i in range(4):
                for j in range(2):
                    g.clear(rect_pts(cx + 6 + i * 13, cy + 8 + j * 14, 8, 8), colors=[color])
            g.ink.rect(cx, cy, w, h, lw=2.0, amp=0.2)


def cartons(g, x, base, cols, rows, w=70, h=50, seed=1, top=None):
    """纸箱码到顶：牛皮纸色（梅 + 墨叠出来的土黄），一道封箱带。"""
    rnd = random.Random(seed)
    for c in range(cols):
        n = rows if top is None else rows - (c % 2)
        for r in range(n):
            cx = x + c * w + (r % 2) * rnd.uniform(-6, 6)
            cy = base - (r + 1) * h
            pts = rect_pts(cx, cy, w - 2, h)
            g.clear(pts)
            g.pen("mei", 0.2).fill(pts)
            g.pen("ink", 0.14).fill(pts)
            g.ink.rect(cx, cy, w - 2, h, lw=1.8, amp=0.2)
            fline(g, "ink", [(cx + 4, cy + h * 0.5), (cx + w - 6, cy + h * 0.5)], 2.2, 0.5)
            if rnd.random() < 0.35:
                g.pen("qing", 0.5).fill(rect_pts(cx + w * 0.3, cy + 8, w * 0.32, h * 0.26))


def tricycle(g, x, base, facing=1, load=None, seed=1):
    """平板三轮：后头一块板子装货，前头一个轮子、车把、车座。"""
    f = facing
    rw, fw = x - 60 * f, x + 84 * f
    for wx in (rw, fw):
        g.ink.circle(wx, base - 26, 26, lw=2.6)
        g.ink.dot(wx, base - 26, 3)
        for k in range(6):
            a = k * math.pi / 3
            fline(g, "ink", [(wx, base - 26), (wx + math.cos(a) * 24, base - 26 + math.sin(a) * 24)], 0.9, 0.7)
    bed0, bed1 = x - 130 * f, x + 10 * f
    lo, hi = min(bed0, bed1), max(bed0, bed1)
    g.clear(rect_pts(lo, base - 70, hi - lo, 16))
    g.pen("ink", 0.4).fill(rect_pts(lo, base - 70, hi - lo, 16))
    g.ink.rect(lo, base - 70, hi - lo, 16, lw=2.2)
    g.ink.line([(lo, base - 70), (lo, base - 100)], 2.2)
    g.ink.line([(hi, base - 70), (hi, base - 100)], 2.2)
    seat = (x + 34 * f, base - 92)
    bar = (x + 80 * f, base - 112)
    g.ink.line([(bed1, base - 62), seat, (x + 60 * f, base - 40), (bed1, base - 62)], 2.8)
    g.ink.line([seat, bar, (fw, base - 26)], 2.8)
    g.ink.line([(seat[0] - 12, seat[1] - 4), (seat[0] + 12, seat[1] - 4)], 5)
    g.ink.line([(bar[0] - 8 * f, bar[1] - 2), (bar[0] + 10 * f, bar[1] - 8)], 3)
    if load:
        produce(g, (lo + hi) / 2, base - 70, hi - lo - 8, load, seed)


def ground_market(g, W, seed=1):
    """早市的地：踩实的水泥地，一道路沿；前头的路上一地烂菜叶、几摊水、一块压扁的纸壳。"""
    y = GROUND
    g.clear(rect_pts(-50, y, W + 100, BOTTOM - y + 60))
    g.pen("ink", 0.42).fill(rect_pts(-50, y, W + 100, 30))
    fhatch(g, "ink", -50, y, W + 100, 30, 20, 7, 0.8, 0.3)
    g.ink.line([(-50, y), (W + 50, y)], 4.5, amp=0.6)
    g.pen("ink", 0.3).fill(rect_pts(-50, y + 30, W + 100, BOTTOM - y))
    fhatch(g, "ink", -50, y + 30, W + 100, BOTTOM - y, 80, 22, 0.8, 0.22)
    g.ink.line([(-50, y + 30), (W + 50, y + 30)], 2.6, amp=0.5)
    rnd = random.Random(seed)
    # 几摊水（反着灯泡的光）
    for i in range(int(W / 520)):
        px = rnd.uniform(80, W - 80)
        py = rnd.uniform(y + 70, y + 170)
        pw = rnd.uniform(70, 150)
        g.clear(ellipse_pts(px, py, pw, 9), colors=["ink"])
        g.pen("qing", 0.22).fill(ellipse_pts(px, py, pw, 9))
        g.pen("mei", 0.25).fill(ellipse_pts(px + rnd.uniform(-20, 20), py, 10, 3))
    # 菜叶子、烂西红柿、一截葱
    for i in range(int(W / 38)):
        lx = rnd.uniform(-20, W + 20)
        ly = rnd.uniform(y + 34, y + 210)
        k = rnd.random()
        if k < 0.6:
            a = rnd.uniform(-0.6, 0.6)
            L = rnd.uniform(10, 22)
            g.pen("qing", 0.7).fill([(lx - L, ly + a * L), (lx, ly - 5), (lx + L, ly - a * L), (lx, ly + 5)])
        elif k < 0.75:
            g.pen("mei", 0.6).fill(ellipse_pts(lx, ly, 8, 4))
        elif k < 0.9:
            g.pen("qing").line([(lx, ly), (lx + rnd.uniform(18, 34), ly + rnd.uniform(-4, 4))], 2.4, amp=0.2)
        else:
            g.ink.line([(lx, ly), (lx + rnd.uniform(14, 26), ly + rnd.uniform(-3, 3))], 1.4, amp=0.3)
    # 一块压扁的纸壳
    cx = W * 0.47
    g.pen("mei", 0.2).fill([(cx, y + 110), (cx + 120, y + 100), (cx + 132, y + 140), (cx + 6, y + 150)])
    g.pen("ink", 0.16).fill([(cx, y + 110), (cx + 120, y + 100), (cx + 132, y + 140), (cx + 6, y + 150)])
    g.ink.poly([(cx, y + 110), (cx + 120, y + 100), (cx + 132, y + 140), (cx + 6, y + 150)], w=1.6, amp=0.3)


def draw_market(g, sc):
    W = sc["width"]
    sp, ex, zs = sc["spots"], sc["exits"], sc["zones"]
    z = lambda k: zs[k]["span"]  # noqa: E731
    sky(g, W, seed=101, horizon=GROUND - 330)
    skyline(g, -40, W + 40, GROUND - 330, seed=103, d=0.10, color="ink")
    m0, m1 = z("market_mouth")
    v0, v1 = z("veg_row")
    h0, h1 = z("wholesale")
    s0, s1 = z("scrap")
    # ---- 后头：一排平房（灰砖、瓦顶），批发的大棚，收废品的院墙 ----
    gx = ex["to_street"][0]
    pingfang(g, -40, gx - 70, GROUND - 300, "ink", 0.34, seed=105, windows=[])
    pingfang(g, gx + 70, m1 - 10, GROUND - 290, "ink", 0.28, seed=107, windows=[(gx + 190, 70)])
    pingfang(g, m1 - 10, 960, GROUND - 320, "ink", 0.32, seed=109, windows=[(700, 80)])
    pingfang(g, 960, 1230, GROUND - 300, "ink", 0.24, seed=111, windows=[(1100, 70)])
    pingfang(g, 1230, h0 - 10, GROUND - 330, "ink", 0.3, seed=113, windows=[(1380, 70)])
    # 进来的胡同口：从楼下那条街钻过来，黑洞洞的一条，墙上贴着一张「早市」的纸
    g.clear(rect_pts(gx - 70, GROUND - 380, 140, 380))
    g.pen("ink", 0.62).fill(rect_pts(gx - 70, GROUND - 380, 140, 380))
    fhatch(g, "ink", gx - 70, GROUND - 380, 140, 380, 30, 12, 1.0, 0.5)
    g.ink.line([(gx - 70, GROUND - 380), (gx - 70, GROUND)], 3.4)
    g.ink.line([(gx + 70, GROUND - 380), (gx + 70, GROUND)], 3.4)
    g.clear(rect_pts(gx + 80, GROUND - 250, 44, 66))
    g.pen("mei", 0.12).fill(rect_pts(gx + 80, GROUND - 250, 44, 66))
    g.ink.rect(gx + 80, GROUND - 250, 44, 66, lw=1.4, amp=0.5)
    g.ink.text("早市", gx + 102, GROUND - 217, 15, vertical=True)
    # 电线杆：天还没亮透，线上挂着那串灯泡的电
    p1x = gx + 170
    top_y = pole(g, p1x, GROUND + 18, 560)
    # 批发的大棚：钢架、波纹铁皮顶、后墙也是铁皮
    shed_top = GROUND - 470
    g.clear(rect_pts(h0, shed_top, h1 - h0, GROUND - shed_top))
    g.pen("ink", 0.36).fill(rect_pts(h0, shed_top, h1 - h0, GROUND - shed_top))
    for xx in range(int(h0) + 6, int(h1), 16):
        fline(g, "ink", [(xx, shed_top + 30), (xx, GROUND)], 1.4, 0.55)
    roof = [(h0 - 40, shed_top + 40), (h0 - 10, shed_top - 10), (h1 + 10, shed_top - 10), (h1 + 40, shed_top + 40)]
    g.clear(roof)
    g.pen("ink", 0.5).fill(roof)
    for xx in range(int(h0) - 30, int(h1) + 34, 12):
        fline(g, "ink", [(xx, shed_top - 8), (xx - 4, shed_top + 38)], 1.4, 0.9)
    g.ink.poly(roof, w=3, amp=0.3)
    for k in range(5):
        px = h0 + 20 + k * (h1 - h0 - 40) / 4
        g.clear(rect_pts(px - 9, shed_top + 40, 18, GROUND - shed_top - 40))
        g.pen("ink", 0.7).fill(rect_pts(px - 9, shed_top + 40, 18, GROUND - shed_top - 40))
        g.ink.line([(px - 9, shed_top + 70), (px + 60, shed_top + 40)], 3)
    signboard(g, (h0 + h1) / 2 - 120, shed_top + 76, "蔬菜批发", "ink", 30, pad=10)
    # 棚子底下一根日光灯
    for lx in (h0 + 230, h1 - 260):
        g.ink.line([(lx - 50, shed_top + 44), (lx - 50, shed_top + 60)], 1.4)
        g.ink.line([(lx + 50, shed_top + 44), (lx + 50, shed_top + 60)], 1.4)
        g.clear(rect_pts(lx - 60, shed_top + 60, 120, 9))
        g.pen("qing", 0.12).fill(rect_pts(lx - 60, shed_top + 60, 120, 9))
        g.ink.rect(lx - 60, shed_top + 60, 120, 9, lw=1.6)
        mark("stall_light", lx, shed_top + 90)
    # 纸箱码到顶、塑料筐
    cartons(g, h0 + 40, GROUND, 4, 6, 70, 52, seed=115)
    cartons(g, h0 + 330, GROUND, 2, 3, 66, 48, seed=117)
    hd = sp["haul_dock"]
    crate_stack(g, hd - 110, GROUND, 1, 3, seed=119)
    # 卡车：车厢的后挡板放下来，冲着 haul_dock；绿漆的老卡车，车头朝右
    t0 = hd + 30
    t1 = t0 + 250
    g.clear(rect_pts(t0, GROUND - 260, t1 - t0, 170))
    g.pen("qing", 0.42).fill(rect_pts(t0, GROUND - 260, t1 - t0, 170))
    g.pen("ink", 0.2).fill(rect_pts(t0, GROUND - 260, t1 - t0, 170))
    for k in range(1, 4):
        g.ink.line([(t0, GROUND - 260 + k * 42), (t1, GROUND - 260 + k * 42)], 1.6, amp=0.3)
    g.ink.rect(t0, GROUND - 260, t1 - t0, 170, lw=3, amp=0.3)
    # 车厢上冒出来的筐和白菜
    crate_stack(g, t0 + 20, GROUND - 260, 3, 2, 56, 36, "ink", 0.2, seed=121)
    produce(g, t0 + 214, GROUND - 260, 70, "cabbage", seed=123)
    # 放下来的后挡板
    g.clear([(t0, GROUND - 92), (t0 - 6, GROUND - 92), (t0 - 22, GROUND - 6), (t0 - 14, GROUND - 4)])
    g.pen("qing", 0.55).fill([(t0, GROUND - 92), (t0 - 8, GROUND - 92), (t0 - 22, GROUND - 6), (t0 - 14, GROUND - 4)])
    g.ink.poly([(t0, GROUND - 92), (t0 - 8, GROUND - 92), (t0 - 22, GROUND - 6), (t0 - 14, GROUND - 4)], w=2.2, amp=0.2)
    g.clear(rect_pts(t0 - 10, GROUND - 92, t1 - t0 + 140, 22))
    g.pen("ink", 0.6).fill(rect_pts(t0 - 10, GROUND - 92, t1 - t0 + 140, 22))
    cab = [(t1 + 6, GROUND - 70), (t1 + 6, GROUND - 236), (t1 + 70, GROUND - 236), (t1 + 112, GROUND - 160), (t1 + 132, GROUND - 150), (t1 + 132, GROUND - 70)]
    g.clear(cab)
    g.pen("qing", 0.45).fill(cab)
    g.pen("ink", 0.2).fill(cab)
    g.ink.poly(cab, w=3, amp=0.3)
    win = [(t1 + 22, GROUND - 222), (t1 + 64, GROUND - 222), (t1 + 98, GROUND - 162), (t1 + 22, GROUND - 162)]
    g.clear(win)
    g.pen("qing", 0.16).fill(win)
    g.ink.poly(win, w=2.2, amp=0.2)
    g.ink.line([(t1 + 20, GROUND - 150), (t1 + 20, GROUND - 80)], 1.8)
    for wx in (t0 + 56, t0 + 196, t1 + 92):
        g.clear(circle_pts(wx, GROUND - 40, 40))
        g.pen("ink", 0.8).fill(circle_pts(wx, GROUND - 40, 40))
        g.clear(circle_pts(wx, GROUND - 40, 17))
        g.pen("ink", 0.25).fill(circle_pts(wx, GROUND - 40, 17))
        g.ink.circle(wx, GROUND - 40, 17, lw=2)
    # 收废品的：院墙，墙头上冒出一座纸壳和瓶子的山；一杆大秤；铁皮棚子
    g.clear(rect_pts(h1, GROUND - 250, W - h1 + 40, 250))
    g.pen("ink", 0.32).fill(rect_pts(h1, GROUND - 250, W - h1 + 40, 250))
    fbricks(g, h1, GROUND - 250, W - h1 + 40, 250, 30, 11, 0.9, 0.34, seed=125)
    g.ink.line([(h1, GROUND - 250), (W + 40, GROUND - 250)], 3, amp=0.4)
    mound = [(s0 + 40, GROUND - 250), (s0 + 140, GROUND - 330), (s0 + 260, GROUND - 400), (s0 + 380, GROUND - 430), (s0 + 520, GROUND - 380), (s0 + 600, GROUND - 330), (s0 + 680, GROUND - 250)]
    g.clear(mound)
    g.pen("mei", 0.16).fill(mound)
    g.pen("ink", 0.16).fill(mound)
    rnd = random.Random(127)
    with g.clip(mound):
        # 压扁的纸壳一层一层
        for i in range(60):
            bx = rnd.uniform(s0 + 40, s0 + 680)
            by = rnd.uniform(GROUND - 430, GROUND - 250)
            bw = rnd.uniform(40, 90)
            a = rnd.uniform(-8, 8)
            fline(g, "ink", [(bx, by), (bx + bw, by + a)], 1.6, 0.7)
        # 一袋一袋的瓶子
        for i in range(40):
            bx = rnd.uniform(s0 + 300, s0 + 620)
            by = rnd.uniform(GROUND - 420, GROUND - 260)
            g.clear(rect_pts(bx, by, 9, 22), colors=["mei", "ink"])
            g.pen("qing", 0.35).fill(rect_pts(bx, by, 9, 22))
            fline(g, "ink", [(bx, by + 22), (bx, by), (bx + 3, by - 6), (bx + 6, by - 6), (bx + 9, by), (bx + 9, by + 22)], 1.1, 0.9)
    g.ink.poly(mound, w=2.6, amp=1.2)
    # 院墙前头：一摞摞捆好的纸壳
    for i, (bx, n) in enumerate(((s0 + 30, 4), (s0 + 150, 3), (s1 - 520, 5))):
        for r in range(n):
            pts = rect_pts(bx + (r % 2) * 6, GROUND - (r + 1) * 30, 104, 30)
            g.clear(pts)
            g.pen("mei", 0.22).fill(pts)
            g.pen("ink", 0.18).fill(pts)
            for k in range(1, 6):
                fline(g, "ink", [(bx + (r % 2) * 6, GROUND - (r + 1) * 30 + k * 5), (bx + 104 + (r % 2) * 6, GROUND - (r + 1) * 30 + k * 5)], 0.8, 0.5)
            g.ink.rect(bx + (r % 2) * 6, GROUND - (r + 1) * 30, 104, 30, lw=1.8, amp=0.3)
        g.ink.line([(bx + 34, GROUND), (bx + 34, GROUND - n * 30)], 1.4)
        g.ink.line([(bx + 74, GROUND), (bx + 74, GROUND - n * 30)], 1.4)
    # 大秤：三根木杆搭个架子，吊一杆大秤，秤钩上挂着一捆纸壳
    sx = sp["scrap_scale"]
    apex = (sx - 30, GROUND - 360)
    g.ink.line([(sx - 170, GROUND), apex], 5, amp=0.6)
    g.ink.line([(sx + 110, GROUND), apex], 5, amp=0.6)
    g.ink.line([(sx - 40, GROUND - 30), apex], 3, amp=0.4, density=0.6)
    g.ink.line([apex, (apex[0], apex[1] + 70)], 2.0, amp=0.1)
    by = apex[1] + 70
    g.ink.line([(apex[0] - 50, by + 8), (apex[0] + 190, by - 6)], 4.6, amp=0.1)
    for k in range(1, 14):
        g.ink.dot(apex[0] - 50 + k * 240 / 14, by + 8 - 14 * k / 14 - 2, 1.6)
    wx = apex[0] + 150
    g.ink.line([(wx, by - 4), (wx, by + 18)], 1.6, amp=0.1)
    g.pen("ink").fill([(wx - 12, by + 18), (wx + 12, by + 18), (wx + 16, by + 44), (wx - 16, by + 44)])
    hx = apex[0] - 40
    g.ink.line([(hx, by + 8), (hx, by + 60)], 2.0, amp=0.1)
    g.ink.arc(hx + 6, by + 64, 7, math.pi * 0.0, math.pi * 1.2, lw=2.4)
    bale = rect_pts(hx - 60, by + 74, 120, 64)
    g.clear(bale)
    g.pen("mei", 0.22).fill(bale)
    g.pen("ink", 0.18).fill(bale)
    g.ink.rect(hx - 60, by + 74, 120, 64, lw=2, amp=0.4)
    g.ink.line([(hx, by + 70), (hx - 40, by + 76), (hx - 40, by + 138)], 1.4)
    g.ink.line([(hx, by + 70), (hx + 40, by + 76), (hx + 40, by + 138)], 1.4)
    # 铁皮棚子：收购点，门口一只灯泡，一块手写的牌子
    k0, k1 = s1 - 300, s1 - 30
    g.clear(rect_pts(k0, GROUND - 280, k1 - k0, 280))
    g.pen("ink", 0.3).fill(rect_pts(k0, GROUND - 280, k1 - k0, 280))
    for xx in range(int(k0) + 6, int(k1), 14):
        fline(g, "ink", [(xx, GROUND - 280), (xx, GROUND)], 1.3, 0.6)
    g.ink.rect(k0, GROUND - 280, k1 - k0, 280, lw=3)
    rf = [(k0 - 20, GROUND - 270), (k1 + 24, GROUND - 300), (k1 + 24, GROUND - 312), (k0 - 20, GROUND - 284)]
    g.clear(rf)
    g.pen("ink", 0.55).fill(rf)
    g.ink.poly(rf, w=2.4, amp=0.3)
    g.clear(rect_pts(k0 + 60, GROUND - 190, 90, 190))
    g.pen("ink", 0.7).fill(rect_pts(k0 + 60, GROUND - 190, 90, 190))
    g.ink.rect(k0 + 60, GROUND - 190, 90, 190, lw=2.6)
    g.clear(rect_pts(k0 + 170, GROUND - 236, 86, 44))
    g.pen("mei", 0.1).fill(rect_pts(k0 + 170, GROUND - 236, 86, 44))
    g.ink.rect(k0 + 170, GROUND - 236, 86, 44, lw=1.8, amp=0.6)
    g.ink.text("收废品", k0 + 213, GROUND - 213, 22)
    bulb(g, k0 + 105, GROUND - 272, 26)
    tricycle(g, s0 + 330, GROUND, -1, None, seed=129)
    for k in range(3):
        pts = rect_pts(s0 + 206 + k * 4, GROUND - 100 - k * 26, 132, 26)
        g.clear(pts)
        g.pen("mei", 0.2).fill(pts)
        g.pen("ink", 0.2).fill(pts)
        g.ink.rect(s0 + 206 + k * 4, GROUND - 100 - k * 26, 132, 26, lw=1.6, amp=0.3)
    # ---- 菜摊：一溜帆布棚，棚檐底下一串灯泡 ----
    tarp_y = GROUND - 300
    # 棚子底下暗：天还没亮透，靠灯泡照着
    g.pen("ink", 0.24).fill(rect_pts(v0 + 20, tarp_y - 40, v1 - v0 - 50, GROUND - tarp_y + 40))
    xs = tarp(g, v0 + 20, v1 - 30, tarp_y, 46, 16, 230, "ink", 0.6, patches={1: ("qing", 0.45), 3: ("ink", 0.25)})
    bulb_string(g, v0 + 20, v1 - 30, tarp_y + 14, 92, 18, 2, posts=xs)
    # 豆浆摊在胡同口：一小块棚子、一口大锅、蜂窝煤炉子、一张折叠桌
    sx = sp["market_soy"]
    g.pen("ink", 0.2).fill(rect_pts(sx - 150, GROUND - 330, 300, 330))
    xs2 = tarp(g, sx - 150, sx + 150, GROUND - 290, 40, 12, 300, "ink", 0.55)
    bulb_string(g, sx - 150, sx + 150, GROUND - 278, 300, 10, 1, posts=xs2)
    g.clear(rect_pts(sx - 140, GROUND - 74, 64, 74))
    g.pen("ink", 0.5).fill(rect_pts(sx - 140, GROUND - 74, 64, 74))
    g.ink.rect(sx - 140, GROUND - 74, 64, 74, lw=2.4)
    for k in range(3):
        g.clear(circle_pts(sx - 124 + k * 16, GROUND - 40, 4), colors=["ink"])
    pot = [(sx - 152, GROUND - 74), (sx - 64, GROUND - 74), (sx - 70, GROUND - 140), (sx - 146, GROUND - 140)]
    g.clear(pot)
    g.pen("ink", 0.12).fill(pot)
    g.ink.poly(pot, w=2.6, amp=0.3)
    g.ink.ellipse(sx - 108, GROUND - 140, 40, 7, lw=2.4)
    for k in range(3):
        cx = sx - 128 + k * 20
        g.ink.line([(cx, GROUND - 150), (cx - 8, GROUND - 190), (cx + 6, GROUND - 230), (cx - 4, GROUND - 270)], 1.4, amp=2.0, density=0.45)
    table(g, sx + 40, GROUND, 150, 70)
    for k in range(4):
        bx = sx - 10 + k * 34
        g.clear([(bx - 13, GROUND - 92), (bx + 13, GROUND - 92), (bx + 8, GROUND - 74), (bx - 8, GROUND - 74)])
        g.ink.poly([(bx - 13, GROUND - 92), (bx + 13, GROUND - 92), (bx + 8, GROUND - 74), (bx - 8, GROUND - 74)], w=1.6, amp=0.2)
        g.qing.line([(bx - 10, GROUND - 88), (bx + 10, GROUND - 88)], 1.4, amp=0.1)
    # 一筐炸好的油条
    basket(g, sx + 140, GROUND, 60, 34)
    for k in range(5):
        g.pen("mei", 0.35).line([(sx + 118 + k * 8, GROUND - 34), (sx + 126 + k * 8, GROUND - 70)], 6, amp=0.4)
    stool(g, sx - 30, GROUND, "ink", 34, 30)
    stool(g, sx + 110, GROUND, "ink", 34, 30)
    # 菜摊一：圆白菜、土豆，竹筐摆一地
    plank_stall(g, v0 + 40, v0 + 220, GROUND, 74)
    produce(g, v0 + 130, GROUND - 74, 170, "cabbage", seed=131)
    basket(g, v0 + 60, GROUND, 66, 44, load="potato", seed=133)
    basket(g, v0 + 236, GROUND, 66, 44, load="potato", seed=135)
    # 自家的摊子（veg_stall）：门板支在两只木箱上，西红柿、黄瓜、一把葱；杆秤挂在棚檐底下
    vx = sp["veg_stall"]
    plank_stall(g, vx - 120, vx + 120, GROUND, 80)
    produce(g, vx - 56, GROUND - 80, 110, "tomato", seed=137)
    produce(g, vx + 56, GROUND - 80, 100, "cucumber", seed=139)
    produce(g, vx + 100, GROUND - 100, 0, "scallion", seed=141)
    produce(g, vx + 136, GROUND, 34, "scallion", seed=143)
    steelyard(g, vx - 40, tarp_y + 10, 120)
    # 一只装零钱的铁盒、一块写价钱的纸板（字归街景层）
    g.clear(rect_pts(vx - 20, GROUND - 98, 36, 18))
    g.pen("qing", 0.4).fill(rect_pts(vx - 20, GROUND - 98, 36, 18))
    g.ink.rect(vx - 20, GROUND - 98, 36, 18, lw=1.6)
    g.clear(rect_pts(vx - 150, GROUND - 160, 54, 40))
    g.pen("mei", 0.15).fill(rect_pts(vx - 150, GROUND - 160, 54, 40))
    g.ink.rect(vx - 150, GROUND - 160, 54, 40, lw=1.4, amp=0.6)
    g.ink.line([(vx - 123, GROUND - 160), (vx - 123, GROUND - 80)], 1.6)
    basket(g, vx - 170, GROUND, 60, 42, load="tomato", seed=145)
    stool(g, vx + 160, GROUND, "ink", 34, 30)
    # 三轮车拉来一车西瓜
    tricycle(g, 1110, GROUND, 1, "melon", seed=147)
    # 鸡蛋、豆腐、一盆鱼
    e0 = sp["market_walk"] - 20
    plank_stall(g, e0 - 40, e0 + 160, GROUND, 76, legs="trestle")
    basket(g, e0 + 10, GROUND - 76, 70, 30, d=0.1, load="egg", seed=149)
    for k in range(3):
        g.clear(rect_pts(e0 + 70 + k * 26, GROUND - 100, 24, 24))
        g.pen("ink", 0.06).fill(rect_pts(e0 + 70 + k * 26, GROUND - 100, 24, 24))
        g.ink.rect(e0 + 70 + k * 26, GROUND - 100, 24, 24, lw=1.4)
    g.pen("qing", 0.25).fill([(e0 + 64, GROUND - 104), (e0 + 150, GROUND - 104), (e0 + 156, GROUND - 92), (e0 + 60, GROUND - 92)])
    tub = [(e0 + 190, GROUND - 40), (e0 + 330, GROUND - 40), (e0 + 318, GROUND), (e0 + 202, GROUND)]
    g.clear(tub)
    g.pen("ink", 0.3).fill(tub)
    g.ink.poly(tub, w=2.4, amp=0.3)
    g.pen("qing", 0.55).fill(ellipse_pts(e0 + 260, GROUND - 40, 68, 8))
    for k in range(3):
        fx = e0 + 220 + k * 30
        g.ink.line([(fx, GROUND - 42), (fx + 18, GROUND - 40)], 4, amp=0.2)
    produce(g, e0 + 380, GROUND, 90, "peach", seed=151)
    # 前头的电线：从胡同口那根杆子扯过来
    wires(g, [p1x, v0 + 20], top_y + 2, 60, 2)
    ground_market(g, W, seed=153)


def annulus(cx, cy, R, r, a0=0.0, a1=math.tau, n=36):
    """圆环（或圆环的一段）：外圈顺着走、内圈倒着走，中间是空的。"""
    outer = [(cx + R * math.cos(a0 + (a1 - a0) * i / n), cy + R * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]
    inner = [(cx + r * math.cos(a0 + (a1 - a0) * i / n), cy + r * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]
    return outer + inner[::-1]


def lifebuoy(g, cx, cy, R=26, r=14):
    """救生圈：白底四段梅红。"""
    g.clear(annulus(cx, cy, R, r))
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        g.pen("mei", 0.9).fill(annulus(cx, cy, R, r, a - 0.42, a + 0.42, 10))
    g.ink.circle(cx, cy, R, lw=2.0)
    g.ink.circle(cx, cy, r, lw=1.6)


def parasol(g, x, base, r=110, h=236, color="mei", lean=0.0, seed=1):
    """遮阳伞：一片一片的伞面梅白相间，伞杆插进沙子，底下一块影子。"""
    ax, ay = x + lean, base - h
    rim = [(ax - r + 2 * r * i / 8, ay + 40 + 6 * math.sin(math.pi * i / 8)) for i in range(9)]
    canopy = [(ax - r, ay + 40)] + [(ax - r * math.cos(math.pi * i / 12) , ay + 40 - 44 * math.sin(math.pi * i / 12)) for i in range(13)] + [(ax + r, ay + 40)]
    g.pen("ink", 0.14).fill(ellipse_pts(x + 30, base + 4, r * 0.8, 7))
    g.ink.line([(ax, ay - 12), (x, base + 4)], 3.4, amp=0.2)
    g.clear(canopy + rim[::-1])
    for i in range(8):
        a = rim[i]
        b = rim[i + 1]
        if i % 2 == 0:
            seg = [(ax, ay - 4), (a[0], a[1]), (b[0], b[1])]
            g.pen(color, 0.85).fill(seg)
    g.ink.poly(canopy + rim[::-1], w=2.2, amp=0.3)
    for i in range(9):
        fline(g, "ink", [(ax, ay - 4), rim[i]], 1.0, 0.7)
    for i in range(8):
        a, b = rim[i], rim[i + 1]
        g.pen(color if i % 2 == 0 else "ink", 0.85 if i % 2 == 0 else 0.4).arc((a[0] + b[0]) / 2, a[1] + 2, (b[0] - a[0]) / 2, 0, math.pi, lw=1.6, amp=0.1)


def deckchair(g, x, base, facing=1, color="qing"):
    f = facing
    g.ink.line([(x - 40 * f, base), (x + 30 * f, base - 46)], 2.6)
    g.ink.line([(x + 40 * f, base), (x - 10 * f, base - 30)], 2.6)
    cloth = [(x - 36 * f, base - 18), (x + 26 * f, base - 50), (x + 40 * f, base - 92), (x + 32 * f, base - 96), (x + 16 * f, base - 56), (x - 40 * f, base - 26)]
    g.pen(color, 0.55).fill(cloth)
    g.ink.line([(x + 26 * f, base - 50), (x + 44 * f, base - 98)], 2.6)


def sea(g, x0, x1, hz, shore, seed=1):
    """海：海平线一道深青，越往近处越浅、浪越长，几点亮光；岸边一道白浪。"""
    pts = rect_pts(x0, hz, x1 - x0, shore - hz)
    g.clear(pts)
    g.pen("qing", 0.34).fill(pts)
    g.pen("qing", 0.3).fill(rect_pts(x0, hz, x1 - x0, (shore - hz) * 0.45))
    g.pen("qing", 0.4).fill(rect_pts(x0, hz, x1 - x0, 10))
    g.qing.line([(x0, hz), (x1, hz)], 2.6, amp=0.2)
    rnd = random.Random(seed)
    for i in range(int((x1 - x0) * (shore - hz) / 1600)):
        y = rnd.uniform(hz + 6, shore - 10)
        t = (y - hz) / (shore - hz)
        x = rnd.uniform(x0, x1)
        L = 10 + 90 * t * rnd.uniform(0.5, 1.2)
        fline(g, "qing", [(x, y), (x + L * 0.5, y - 1.5 * t), (x + L, y)], 1.0 + 1.6 * t, 0.9)
    for i in range(int((x1 - x0) / 60)):
        y = rnd.uniform(hz + 8, hz + (shore - hz) * 0.6)
        x = rnd.uniform(x0, x1)
        g.clear(rect_pts(x, y, rnd.uniform(8, 30), 2.4), colors=["qing"])
    # 岸边的白浪：一道挖空的花边，下面一抹湿沙
    fy = shore - 4
    g.clear(rect_pts(x0, fy - 6, x1 - x0, 12), colors=["qing"])
    k = x0
    while k < x1:
        w = rnd.uniform(26, 60)
        fline(g, "qing", [(k, fy + 6), (k + w * 0.3, fy - 2), (k + w * 0.7, fy - 3), (k + w, fy + 6)], 1.6, 0.8)
        k += w


def draw_seaside(g, sc):
    W = sc["width"]
    sp, ex, zs = sc["spots"], sc["exits"], sc["zones"]
    z = lambda k: zs[k]["span"]  # noqa: E731
    HZ = GROUND - 150   # 海平线压得低：天占一大半
    SHORE = GROUND - 34
    sky(g, W, seed=201, horizon=HZ)
    layer_note("far_base", HZ)
    a0, a1 = z("sea_street")
    b0, b1 = z("sand")
    r0, r1 = z("rocks")
    p0, p1 = z("pier")
    i0, i1 = z("inn")
    sea(g, -40, W + 40, HZ, SHORE + 30, seed=203)
    # 远处一条打鱼的小船、一只浮标
    bx = r0 + 330
    hull = [(bx - 46, HZ + 44), (bx + 52, HZ + 44), (bx + 38, HZ + 58), (bx - 36, HZ + 58)]
    g.clear(hull)
    g.pen("ink", 0.5).fill(hull)
    g.ink.line([(bx - 10, HZ + 44), (bx - 6, HZ - 6)], 2)
    g.pen("ink", 0.3).fill([(bx - 4, HZ - 2), (bx + 30, HZ + 40), (bx - 4, HZ + 40)])
    g.pen("mei", 0.8).fill(circle_pts(b0 + 520, HZ + 70, 5))
    g.ink.line([(b0 + 520, HZ + 64), (b0 + 520, HZ + 52)], 1.4)
    # 礁石：从海里拱出来，黑的，浪打在脚底下
    for (cx, w, h, sd) in ((r0 + 120, 260, 190, 1), (r0 + 360, 120, 90, 2), (r1 - 150, 300, 230, 3)):
        rnd = random.Random(205 + sd)
        n = 9
        pts = [(cx - w / 2, SHORE + 24)]
        for i in range(1, n):
            t = i / n
            pts.append((cx - w / 2 + w * t + rnd.uniform(-12, 12), SHORE + 20 - h * math.sin(math.pi * t) ** 0.7 * rnd.uniform(0.75, 1.05)))
        pts.append((cx + w / 2, SHORE + 24))
        g.clear(pts)
        g.pen("ink", 0.62).fill(pts)
        with g.clip(pts):
            fhatch(g, "ink", cx - w / 2, SHORE - h, w, h + 30, 60, 8, 1.2, 0.6)
        g.ink.poly(pts, w=3, amp=0.6)
        for i in range(4):
            fx = cx - w / 2 + 20 + i * (w - 40) / 3
            fline(g, "qing", [(fx - 18, SHORE + 18), (fx, SHORE + 12), (fx + 20, SHORE + 18)], 2, 0.9)
    # ---- 海边的街：石头栏杆、车站、卖贝壳的摊子 ----
    def balustrade(xa, xb, base, h=84):
        g.clear(rect_pts(xa, base - h, xb - xa, 14))
        g.pen("ink", 0.12).fill(rect_pts(xa, base - h, xb - xa, 14))
        g.ink.rect(xa, base - h, xb - xa, 14, lw=2.2, amp=0.3)
        x = xa
        while x <= xb:
            g.clear(rect_pts(x - 10, base - h + 14, 20, h - 14))
            g.pen("ink", 0.08).fill(rect_pts(x - 10, base - h + 14, 20, h - 14))
            g.ink.rect(x - 10, base - h + 14, 20, h - 14, lw=2.0, amp=0.2)
            x += 110
        for x in range(int(xa) + 20, int(xb), 22):
            fline(g, "ink", [(x, base - h + 18), (x, base - 6)], 1.4, 0.6)
    balustrade(-40, b0 - 20, GROUND)
    sx = ex["to_home"][0]
    # 站牌：一根杆子上一块长牌，底下一条长椅
    g.ink.line([(sx + 40, GROUND), (sx + 40, GROUND - 300)], 5)
    g.clear(rect_pts(sx + 6, GROUND - 330, 68, 120))
    g.pen("qing").fill(rect_pts(sx + 6, GROUND - 330, 68, 120))
    g.ink.rect(sx + 6, GROUND - 330, 68, 120, lw=2.4)
    knock(g, "qing", "车站", sx + 40, GROUND - 270, 26, vertical=True)
    bench(g, sx - 50, GROUND, 120, "ink", back=False)
    lamp(g, a0 + 260, GROUND, 440, 1)
    tree(g, a0 + 600, GROUND, 360, 90, "young", seed=207)
    # 卖贝壳的：一把伞、一张桌、一杆挂满贝壳串的竹竿、一摞救生圈
    shx = sp["shell_stall"]
    parasol(g, shx - 10, GROUND, 120, 250, "mei", seed=209)
    table(g, shx, GROUND, 170, 76)
    rnd = random.Random(211)
    for k in range(9):
        cx = shx - 70 + k * 17
        if k % 3 == 0:
            g.clear([(cx - 8, GROUND - 78), (cx + 8, GROUND - 78), (cx, GROUND - 104)])
            g.ink.poly([(cx - 8, GROUND - 78), (cx + 8, GROUND - 78), (cx, GROUND - 104)], w=1.4, amp=0.2)
            g.ink.line([(cx - 6, GROUND - 86), (cx + 4, GROUND - 92)], 1.0, amp=0.1)
        else:
            g.clear([(cx - 8, GROUND - 78), (cx + 8, GROUND - 78), (cx + 9, GROUND - 88), (cx, GROUND - 96), (cx - 9, GROUND - 88)])
            g.pen("mei", 0.25 if k % 2 else 0.05).fill([(cx - 8, GROUND - 78), (cx + 8, GROUND - 78), (cx + 9, GROUND - 88), (cx, GROUND - 96), (cx - 9, GROUND - 88)])
            g.ink.poly([(cx - 8, GROUND - 78), (cx + 8, GROUND - 78), (cx + 9, GROUND - 88), (cx, GROUND - 96), (cx - 9, GROUND - 88)], w=1.2, amp=0.1)
    g.ink.line([(shx + 96, GROUND), (shx + 100, GROUND - 230)], 3)
    g.ink.line([(shx + 70, GROUND - 210), (shx + 150, GROUND - 216)], 2)
    for k in range(4):
        cx = shx + 76 + k * 22
        g.ink.line([(cx, GROUND - 212), (cx + 2, GROUND - 130 + (k % 2) * 16)], 1.0, amp=0.1)
        for j in range(5):
            g.clear(circle_pts(cx + 1, GROUND - 196 + j * 14, 4.6))
            g.pen("mei" if (j + k) % 3 == 0 else "ink", 0.3 if (j + k) % 3 else 0.6).fill(circle_pts(cx + 1, GROUND - 196 + j * 14, 4.6))
            g.ink.circle(cx + 1, GROUND - 196 + j * 14, 4.6, lw=1.0)
    for k in range(3):
        lifebuoy(g, shx - 120, GROUND - 26 - k * 10, 30, 15)
    # 草帽挂在伞杆上
    g.clear(ellipse_pts(shx - 10, GROUND - 160, 30, 6))
    g.pen("mei", 0.22).fill(ellipse_pts(shx - 10, GROUND - 160, 30, 6))
    g.pen("ink", 0.12).fill(ellipse_pts(shx - 10, GROUND - 170, 14, 11))
    g.ink.ellipse(shx - 10, GROUND - 160, 30, 6, lw=1.6)
    # ---- 沙滩：一排遮阳伞、救生员的高椅子、挂着救生圈的杆子、晒着的泳衣 ----
    for k, (ux, lean) in enumerate(((b0 + 120, -6), (b0 + 300, 8), (b0 + 660, -4), (b1 - 140, 6))):
        parasol(g, ux, GROUND, 104, 226, "mei", lean, seed=213 + k)
        deckchair(g, ux + 40, GROUND, -1 if k % 2 else 1, "qing")
    sw = sp["sea_swim"]
    # 救生员的高椅子
    hx = sw - 120
    g.ink.line([(hx - 40, GROUND), (hx - 20, GROUND - 170)], 4)
    g.ink.line([(hx + 40, GROUND), (hx + 20, GROUND - 170)], 4)
    for yy in (GROUND - 60, GROUND - 120):
        t = (GROUND - yy) / 170
        g.ink.line([(hx - 40 + 20 * t, yy), (hx + 40 - 20 * t, yy)], 3)
    g.clear(rect_pts(hx - 30, GROUND - 178, 60, 10))
    g.pen("qing").fill(rect_pts(hx - 30, GROUND - 178, 60, 10))
    g.ink.rect(hx - 30, GROUND - 178, 60, 10, lw=2)
    g.ink.line([(hx + 20, GROUND - 178), (hx + 26, GROUND - 236)], 3)
    g.pen("qing").fill(rect_pts(hx + 16, GROUND - 240, 16, 50))
    # 救生圈挂在杆子上
    lx = sw + 110
    g.ink.line([(lx, GROUND), (lx, GROUND - 200)], 4)
    g.ink.line([(lx - 6, GROUND - 190), (lx + 16, GROUND - 190)], 3)
    lifebuoy(g, lx + 10, GROUND - 150, 30, 16)
    g.clear(rect_pts(lx - 30, GROUND - 236, 60, 30))
    g.pen("mei", 0.9).fill(rect_pts(lx - 30, GROUND - 236, 60, 30))
    knock(g, "mei", "救生", lx, GROUND - 221, 18)
    # 一双拖鞋
    for k in range(2):
        g.pen("qing", 0.7).fill(ellipse_pts(sw + 10 + k * 22, GROUND - 3, 10, 3))
    # 晒衣绳：两根竹竿，泳衣、毛巾
    c0, c1 = b0 + 760, b0 + 900
    for cx in (c0, c1):
        g.ink.line([(cx, GROUND), (cx, GROUND - 210)], 3)
    rope = [(c0 + (c1 - c0) * t / 12, GROUND - 200 + 14 * 4 * (t / 12) * (1 - t / 12)) for t in range(13)]
    fline(g, "ink", rope, 1.3)
    hang = (("suit", "mei", 0.7), ("towel", "qing", 0.5), ("trunk", "qing", 0.8), ("suit", "qing", 0.6), ("towel", "mei", 0.35))
    for k, (kind, col, d) in enumerate(hang):
        t = (k + 0.7) / 5.6
        hx2 = c0 + (c1 - c0) * t
        hy = GROUND - 200 + 14 * 4 * t * (1 - t)
        if kind == "suit":
            pts = [(hx2 - 9, hy), (hx2 - 5, hy + 16), (hx2 - 9, hy + 34), (hx2, hy + 42), (hx2 + 9, hy + 34), (hx2 + 5, hy + 16), (hx2 + 9, hy)]
        elif kind == "trunk":
            pts = [(hx2 - 12, hy), (hx2 + 12, hy), (hx2 + 13, hy + 22), (hx2 + 3, hy + 22), (hx2, hy + 12), (hx2 - 3, hy + 22), (hx2 - 13, hy + 22)]
        else:
            pts = rect_pts(hx2 - 11, hy, 22, 48)
        g.clear(pts)
        g.pen(col, d).fill(pts)
        g.ink.poly(pts, w=1.3, amp=0.2)
        if kind == "towel":
            for j in range(3):
                fline(g, col, [(hx2 - 11, hy + 10 + j * 12), (hx2 + 11, hy + 10 + j * 12)], 2.4, 1.0)
    # 堆沙子：一座沙堡、一只梅红的小桶、一把铲子
    sd = sp["sand_pile"]
    castle = [(sd - 70, GROUND), (sd - 60, GROUND - 30), (sd - 40, GROUND - 30), (sd - 40, GROUND - 52), (sd - 30, GROUND - 52), (sd - 30, GROUND - 46), (sd - 20, GROUND - 46), (sd - 20, GROUND - 52), (sd - 6, GROUND - 52), (sd - 6, GROUND - 74), (sd + 14, GROUND - 74), (sd + 14, GROUND - 40), (sd + 40, GROUND - 32), (sd + 66, GROUND)]
    g.clear(castle)
    g.pen("mei", 0.22).fill(castle)
    g.pen("ink", 0.1).fill(castle)
    g.ink.poly(castle, w=1.8, amp=0.4)
    g.ink.line([(sd + 4, GROUND - 74), (sd + 4, GROUND - 104)], 1.4)
    g.pen("mei").fill([(sd + 4, GROUND - 104), (sd + 24, GROUND - 98), (sd + 4, GROUND - 92)])
    pail = [(sd + 80, GROUND - 34), (sd + 112, GROUND - 34), (sd + 108, GROUND), (sd + 84, GROUND)]
    g.clear(pail)
    g.pen("mei", 0.85).fill(pail)
    g.ink.poly(pail, w=1.6, amp=0.2)
    g.ink.arc(sd + 96, GROUND - 34, 16, math.pi, math.tau, lw=1.4)
    g.ink.line([(sd - 100, GROUND), (sd - 120, GROUND - 46)], 2.6)
    g.pen("qing").fill([(sd - 104, GROUND - 2), (sd - 92, GROUND - 4), (sd - 96, GROUND + 6)])
    # ---- 栈桥：从堤上一直伸到海里去（往远处走，越走越窄） ----
    pe = sp["pier_end"]
    cx_far = pe + 30
    near0, near1 = pe - 110, pe + 110
    far0, far1 = cx_far - 7, cx_far + 7
    fy = HZ + 14
    ny = GROUND - 30
    deck = [(near0, ny), (far0, fy), (far1, fy), (near1, ny)]
    g.clear(deck)
    g.pen("ink", 0.3).fill(deck)
    for k in range(1, 8):
        t = k / 8
        fline(g, "ink", [(near0 + (near1 - near0) * t, ny), (far0 + (far1 - far0) * t, fy)], 1.0, 0.6)
    # 桥墩：桥面底下一排桩子，越远越矮
    for k in range(14):
        t = (k / 14) ** 1.6
        yy = ny + (fy - ny) * t
        for (xa, xb) in ((near0, far0), (near1, far1)):
            xx = xa + (xb - xa) * t
            fline(g, "ink", [(xx, yy), (xx, yy + 24 * (1 - t) + 3)], 2.6 * (1 - t) + 0.8, 0.9)
    g.ink.poly(deck, w=2.2, amp=0.2)
    # 栏杆和路灯：越远越小
    for (xa, xb) in ((near0, far0), (near1, far1)):
        g.ink.line([(xa, ny - 46), (xb, fy - 4)], 2.0, amp=0.2)
        for k in range(10):
            t = (k / 10) ** 1.5
            xx, yy = xa + (xb - xa) * t, ny + (fy - ny) * t
            fline(g, "ink", [(xx, yy), (xx, yy - 46 * (1 - t) - 4)], 1.8 * (1 - t) + 0.6, 0.9)
    for k, t in enumerate((0.12, 0.38, 0.62)):
        xx, yy = near1 + (far1 - near1) * t, ny + (fy - ny) * t
        hh = 150 * (1 - t) + 10
        g.ink.line([(xx, yy), (xx, yy - hh)], 3 * (1 - t) + 0.8, amp=0.1)
        g.ink.circle(xx, yy - hh - 6 * (1 - t), 7 * (1 - t) + 1.5, lw=1.6)
        if k < 2:
            mark("street_lamp", xx, yy - hh)
    # 桥头远处一座小亭子
    g.clear([(cx_far - 12, fy - 2), (cx_far - 12, fy - 16), (cx_far - 16, fy - 16), (cx_far, fy - 26), (cx_far + 16, fy - 16), (cx_far + 12, fy - 16), (cx_far + 12, fy - 2)])
    g.pen("ink", 0.5).fill([(cx_far - 16, fy - 16), (cx_far, fy - 26), (cx_far + 16, fy - 16)])
    g.ink.poly([(cx_far - 12, fy - 2), (cx_far - 12, fy - 16), (cx_far - 16, fy - 16), (cx_far, fy - 26), (cx_far + 16, fy - 16), (cx_far + 12, fy - 16), (cx_far + 12, fy - 2)], w=1.2, amp=0.1)
    mark("far_light", cx_far, fy - 10)
    # 堤上的铁栏杆，到桥头断开
    for (xa, xb) in ((p0, near0 - 30), (near1 + 30, i0 - 10)):
        g.ink.line([(xa, GROUND - 76), (xb, GROUND - 76)], 3, amp=0.3)
        g.ink.line([(xa, GROUND - 40), (xb, GROUND - 40)], 2, amp=0.3)
        x = xa
        while x <= xb + 1:
            g.ink.line([(x, GROUND), (x, GROUND - 82)], 4, amp=0.1)
            x += 70
    for px in (near0 - 30, near1 + 30):
        g.clear(rect_pts(px - 16, GROUND - 110, 32, 110))
        g.pen("ink", 0.3).fill(rect_pts(px - 16, GROUND - 110, 32, 110))
        g.ink.rect(px - 16, GROUND - 110, 32, 110, lw=2.4)
    signboard(g, near0 - 30, GROUND - 150, "栈桥", "qing", 22, vertical=True, pad=8)
    lamp(g, p0 + 60, GROUND, 440, 1)
    # ---- 招待所：带阳台的两层楼，窗口晾着毛巾；一楼剖开：饭堂、一间客房 ----
    top1 = GROUND - 250
    top2 = GROUND - 490
    g.clear(rect_pts(i0 + 10, top2, i1 - i0, GROUND - top2))
    g.pen("qing", 0.1).fill(rect_pts(i0 + 10, top2, i1 - i0, GROUND - top2))
    g.ink.rect(i0 + 10, top2, i1 - i0, GROUND - top2, lw=3, amp=0.3)
    g.clear(rect_pts(i0 - 4, top2 - 22, i1 - i0 + 28, 24))
    g.pen("ink", 0.3).fill(rect_pts(i0 - 4, top2 - 22, i1 - i0 + 28, 24))
    g.ink.rect(i0 - 4, top2 - 22, i1 - i0 + 28, 24, lw=2.4)
    signboard(g, (i0 + i1) / 2, top2 - 54, "海滨招待所", "qing", 30, pad=10)
    # 二楼：三间带阳台的屋子，门窗上头一条青色的檐
    for k in range(3):
        wx = i0 + 60 + k * 190
        lit = k == 1
        window(g, wx, top2 + 40, 70, 120, panes=2, lit=lit, curtain="qing" if k != 1 else None, sill=False, night=True)
        g.clear(rect_pts(wx + 84, top2 + 40, 56, 160))
        g.pen("ink", 0.35).fill(rect_pts(wx + 84, top2 + 40, 56, 160))
        g.ink.rect(wx + 84, top2 + 40, 56, 160, lw=2.2)
        slab_y = top2 + 200
        g.clear(rect_pts(wx - 14, slab_y, 170, 14))
        g.pen("ink", 0.3).fill(rect_pts(wx - 14, slab_y, 170, 14))
        g.ink.rect(wx - 14, slab_y, 170, 14, lw=2.2)
        g.ink.line([(wx - 14, slab_y - 56), (wx + 156, slab_y - 56)], 2.6)
        for j in range(12):
            fline(g, "ink", [(wx - 8 + j * 14, slab_y - 56), (wx - 8 + j * 14, slab_y)], 1.6, 0.9)
        # 阳台栏杆上搭着的毛巾、泳衣
        for j, (col, d) in enumerate((("mei", 0.7), ("qing", 0.55), ("mei", 0.3))[: 2 + (k % 2)]):
            tx = wx + 6 + j * 44
            pts = rect_pts(tx, slab_y - 58, 30, 50 - j * 6)
            g.clear(pts)
            g.pen(col, d).fill(pts)
            fline(g, col, [(tx, slab_y - 46), (tx + 30, slab_y - 46)], 2.4, 1.0)
            g.ink.rect(tx, slab_y - 58, 30, 50 - j * 6, lw=1.2, amp=0.2)
        g.pen("qing", 0.55).fill(rect_pts(wx - 14, top2 + 26, 170, 10))
    # 一楼剖开：前墙没了，看得见屋里
    g.clear(rect_pts(i0 + 24, top1 + 14, i1 - i0 - 28, GROUND - top1 - 14))
    g.pen("ink", 0.14).fill(rect_pts(i0 + 24, top1 + 14, i1 - i0 - 28, GROUND - top1 - 14))
    g.pen("qing", 0.24).fill(rect_pts(i0 + 24, GROUND - 100, i1 - i0 - 28, 100))
    g.ink.line([(i0 + 24, GROUND - 100), (i1, GROUND - 100)], 2)
    slab(g, i0 + 10, i1 + 10, top1, top1 + 14)
    mid = (sp["inn_table"] + sp["inn_bed"]) / 2 + 10
    cut_wall(g, mid, top1 + 14, GROUND - 230, 22, "ink")
    cut_wall(g, i0 + 17, top1, GROUND, 24, "ink")
    cut_wall(g, i1 + 6, top1, GROUND, 24, "ink")
    # 饭堂：圆桌、方凳、暖壶，墙上一台电扇
    tx = sp["inn_table"]
    round_table(g, tx, GROUND, 180, "qing")
    g.ink.circle(tx - 110, top1 + 80, 24, lw=2)
    for k in range(3):
        a = k * math.tau / 3 + 0.3
        g.ink.line([(tx - 110, top1 + 80), (tx - 110 + math.cos(a) * 20, top1 + 80 + math.sin(a) * 20)], 3)
    window(g, tx + 40, top1 + 50, 110, 80, panes=2, lit=True)
    bulb(g, tx, top1 + 14, 40)
    # 客房：一张床、蚊帐叠在床头、床头柜上一只暖壶
    bx2 = sp["inn_bed"]
    bed(g, bx2, GROUND, 230, -1, "qing")
    window(g, bx2 - 60, top1 + 50, 90, 80, panes=2, curtain="mei", night=True)
    g.ink.rect(bx2 - 170, GROUND - 60, 40, 60, lw=2)
    g.pen("qing", 0.5).fill(rect_pts(bx2 - 162, GROUND - 100, 22, 40))
    # ---- 地面：街上铺石板，沙滩，礁石，水泥堤 ----
    g.clear(rect_pts(-50, GROUND, W + 100, BOTTOM - GROUND + 60))
    # 石板街
    g.pen("ink", 0.14).fill(rect_pts(-50, GROUND, b0 + 50, 30))
    for x in range(-40, int(b0), 80):
        fline(g, "ink", [(x, GROUND + 2), (x - 4, GROUND + 30)], 1.2, 0.5)
    g.pen("ink", 0.1).fill(rect_pts(-50, GROUND + 30, b0 + 50, BOTTOM - GROUND))
    fbricks(g, -50, GROUND + 30, b0 + 50, BOTTOM - GROUND, 90, 34, 1.0, 0.3, seed=215)
    # 沙滩：梅一点、墨一点，像晒热的沙子；脚印、贝壳
    g.pen("mei", 0.16).fill(rect_pts(b0, GROUND, b1 - b0, BOTTOM - GROUND + 40))
    g.pen("ink", 0.05).fill(rect_pts(b0, GROUND, b1 - b0, BOTTOM - GROUND + 40))
    rnd = random.Random(217)
    for i in range(int((b1 - b0) / 5)):
        g.ink.dot(rnd.uniform(b0, b1), rnd.uniform(GROUND + 4, BOTTOM), rnd.uniform(0.8, 1.6))
    for i in range(14):
        fx = b0 + 40 + i * 80 + rnd.uniform(-10, 10)
        fy2 = GROUND + 60 + 40 * math.sin(i * 0.7) + (i % 2) * 18
        g.pen("ink", 0.3).fill(ellipse_pts(fx, fy2, 8, 4))
    for i in range(18):
        cx, cy = rnd.uniform(b0, b1), rnd.uniform(GROUND + 30, BOTTOM - 20)
        g.pen("mei", 0.5).fill([(cx - 6, cy), (cx + 6, cy), (cx, cy - 8)])
    # 礁石滩：黑的石头面，退了潮的水洼
    g.clear(rect_pts(r0, GROUND, r1 - r0, BOTTOM - GROUND + 40))
    g.pen("ink", 0.42).fill(rect_pts(r0, GROUND, r1 - r0, BOTTOM - GROUND + 40))
    fhatch(g, "ink", r0, GROUND, r1 - r0, BOTTOM - GROUND + 40, 55, 12, 1.0, 0.45)
    tp = sp["tide_pool"]
    for (px, py, pw, ph) in ((tp - 60, GROUND + 40, 110, 16), (tp + 120, GROUND + 90, 80, 12), (tp - 200, GROUND + 120, 70, 10), (tp + 20, GROUND + 160, 140, 18)):
        g.clear(ellipse_pts(px, py, pw, ph))
        g.pen("qing", 0.5).fill(ellipse_pts(px, py, pw, ph))
        g.ink.ellipse(px, py, pw, ph, lw=2)
        g.clear(rect_pts(px - pw * 0.5, py - ph * 0.3, pw * 0.4, 2.4), colors=["qing"])
    # 一只小螃蟹、一条海星、几缕海草
    cx = tp + 60
    g.pen("ink", 0.8).fill(ellipse_pts(cx, GROUND + 34, 9, 6))
    for s in (-1, 1):
        g.ink.line([(cx + 8 * s, GROUND + 34), (cx + 16 * s, GROUND + 28), (cx + 18 * s, GROUND + 36)], 1.4)
    for k in range(5):
        a = -math.pi / 2 + k * math.tau / 5
        g.pen("mei", 0.7).line([(tp - 140, GROUND + 70), (tp - 140 + math.cos(a) * 12, GROUND + 70 + math.sin(a) * 12)], 4, amp=0.1)
    for k in range(6):
        sx2 = r0 + 40 + k * 110
        g.qing.line([(sx2, GROUND + 2), (sx2 + 6, GROUND - 14), (sx2 - 2, GROUND - 26)], 2.2, amp=0.6)
    # 水泥堤：一块块大方砖
    g.clear(rect_pts(p0, GROUND, W - p0 + 50, BOTTOM - GROUND + 40))
    g.pen("ink", 0.2).fill(rect_pts(p0, GROUND, W - p0 + 50, 30))
    g.pen("ink", 0.12).fill(rect_pts(p0, GROUND + 30, W - p0 + 50, BOTTOM - GROUND))
    fbricks(g, p0, GROUND + 30, W - p0 + 50, BOTTOM - GROUND, 140, 46, 1.2, 0.4, seed=219)
    g.ink.line([(-50, GROUND), (W + 50, GROUND)], 4.5, amp=0.6)
    g.ink.line([(-50, GROUND + 30), (b0, GROUND + 30)], 2.6, amp=0.4)
    g.ink.line([(p0, GROUND + 30), (W + 50, GROUND + 30)], 2.6, amp=0.4)


def corn(g, x, base, h=270, seed=1, ear=True):
    """一棵玉米：墨色的秆子，青色的长叶子从秆上拱出去再耷拉下来，顶上梅色的穗，腰上一个梅色的棒子。"""
    rnd = random.Random(seed)
    top = base - h
    g.ink.line([(x, base), (x + rnd.uniform(-6, 6), top)], 3.2, amp=0.4)
    for k in range(6):
        y = base - h * (0.16 + 0.13 * k)
        s = 1 if k % 2 else -1
        L = rnd.uniform(95, 130) * (1.1 - k * 0.09)
        # 一片叶子：一道二次曲线，先往上拱、再往下耷拉，根上宽、梢上尖
        A = (x, y)
        C = (x + s * L * 0.45, y - L * rnd.uniform(0.38, 0.5))
        B = (x + s * L, y + L * rnd.uniform(0.05, 0.25))
        mid, up, dn = [], [], []
        for i in range(13):
            t = i / 12
            px = (1 - t) ** 2 * A[0] + 2 * (1 - t) * t * C[0] + t * t * B[0]
            py = (1 - t) ** 2 * A[1] + 2 * (1 - t) * t * C[1] + t * t * B[1]
            dx = 2 * (1 - t) * (C[0] - A[0]) + 2 * t * (B[0] - C[0])
            dy = 2 * (1 - t) * (C[1] - A[1]) + 2 * t * (B[1] - C[1])
            n = math.hypot(dx, dy) or 1.0
            w = 6.5 * math.sin(math.pi * min(1.0, t * 1.15 + 0.08)) * (1 - t * 0.6)
            mid.append((px, py))
            up.append((px - dy / n * w, py + dx / n * w))
            dn.append((px + dy / n * w, py - dx / n * w))
        g.pen("qing", 0.55).fill(up + dn[::-1])
        g.pen("qing").line(mid, 1.0, amp=0.1)
    for k in range(5):
        a = -math.pi / 2 + (k - 2) * 0.35
        g.pen("mei", 0.8).line([(x, top), (x + math.cos(a) * 26, top + math.sin(a) * 26 + 10)], 1.6, amp=0.2)
    if ear:
        ey = base - h * 0.5
        g.clear(ellipse_pts(x + 9, ey, 7, 22))
        g.pen("mei", 0.5).fill(ellipse_pts(x + 9, ey, 7, 22))
        g.ink.ellipse(x + 9, ey, 7, 22, lw=1.4)
        g.pen("mei", 0.8).line([(x + 9, ey - 22), (x + 14, ey - 34)], 1.6, amp=0.4)


def corn_string(g, x, y, n=7):
    """屋檐底下挂的一嘟噜玉米（晒干了留种）。"""
    g.ink.line([(x, y), (x, y + 14)], 1.4)
    for k in range(n):
        cx = x + (k - n / 2) * 7
        cy = y + 18 + k * 9
        g.clear(ellipse_pts(cx, cy + 12, 7, 15))
        g.pen("mei", 0.62).fill(ellipse_pts(cx, cy + 12, 7, 15))
        g.ink.ellipse(cx, cy + 12, 7, 15, lw=1.1)


def hen(g, x, base, facing=1, peck=False):
    f = facing
    body = ellipse_pts(x, base - 20, 17, 13)
    g.clear(body)
    g.pen("ink", 0.05).fill(body)
    g.ink.poly(body, w=1.6, amp=0.3)
    hx, hy = (x + 16 * f, base - 18) if peck else (x + 14 * f, base - 38)
    g.clear(circle_pts(hx, hy, 7))
    g.ink.circle(hx, hy, 7, lw=1.4)
    g.pen("mei").fill([(hx - 4, hy - 6), (hx + 2, hy - 12), (hx + 5, hy - 5)])
    g.pen("mei", 0.9).fill([(hx + 6 * f, hy), (hx + 12 * f, hy + 2), (hx + 6 * f, hy + 4)])
    g.ink.line([(x - 15 * f, base - 26), (x - 24 * f, base - 40)], 3, amp=0.2)
    g.ink.line([(x - 3, base - 8), (x - 4, base)], 1.4)
    g.ink.line([(x + 4, base - 8), (x + 5, base)], 1.4)


def draw_village(g, sc):
    W = sc["width"]
    sp, ex, zs = sc["spots"], sc["exits"], sc["zones"]
    z = lambda k: zs[k]["span"]  # noqa: E731
    HZ = GROUND - 190
    sky(g, W, seed=301, horizon=HZ)
    layer_note("far_base", HZ)
    v0, v1 = z("village_gate")
    y0, y1 = z("grandma_yard")
    c0, c1 = z("cornfield")
    k0, k1 = z("creek")
    t0, t1 = z("threshing")
    # ---- 远处的地：一垄一垄铺到天边，麦茬、豆子地、菜地 ----
    g.clear(rect_pts(-40, HZ, W + 80, GROUND - HZ))
    rnd = random.Random(303)
    yy = HZ
    k = 0
    while yy < GROUND:
        hh = 6 + (yy - HZ) * 0.18
        col, d = (("mei", 0.2), ("qing", 0.14), ("mei", 0.28), ("mei", 0.12), ("qing", 0.2))[k % 5]
        g.pen(col, d).fill(rect_pts(-40, yy, W + 80, hh))
        fline(g, "ink", [(-40, yy), (W + 40, yy)], 0.8, 0.35)
        yy += hh
        k += 1
    # 地里的人家：远处一溜矮房子、一个草垛
    for (fx, fw) in ((420, 90), (1720, 140), (2280, 70), (3140, 110)):
        g.pen("mei", 0.3).fill(rect_pts(fx, HZ + 4, fw, 16))
        g.pen("ink", 0.3).fill([(fx - 4, HZ + 6), (fx + fw / 2, HZ - 6), (fx + fw + 4, HZ + 6)])
    # 河沟往远处去：一道青色，越远越细
    kc = sp["creek_bank"]
    # 河沟从侧面看：地平线底下一道矮矮的、平的水，岸上一道土坎（石板搭在路上，见最后）
    cb0, cb1 = kc - 300, kc + 300
    cy0, cy1 = GROUND - 34, GROUND - 4
    g.clear(rect_pts(cb0, cy0 - 8, cb1 - cb0, cy1 - cy0 + 8))
    g.pen("mei", 0.3).fill(rect_pts(cb0, cy0 - 8, cb1 - cb0, 8))
    g.pen("qing", 0.5).fill(rect_pts(cb0, cy0, cb1 - cb0, cy1 - cy0))
    for k in range(10):
        rx = cb0 + 30 + k * 56
        ry = cy0 + 8 + (k % 3) * 7
        fline(g, "qing", [(rx, ry), (rx + 30, ry)], 1.6, 0.9)
    for k in range(6):
        g.clear(rect_pts(cb0 + 50 + k * 90, cy0 + 4 + (k % 2) * 10, 18, 2.2), colors=["qing"])
    g.ink.line([(cb0, cy0 - 8), (cb1, cy0 - 8)], 1.6, amp=0.4)
    g.qing.line([(cb0, cy0), (cb1, cy0)], 1.4, amp=0.2)
    # ---- 村口：大槐树、电线杆上一只大喇叭、一个石碾子 ----
    tree(g, v0 + 300, GROUND, 680, 210, "huai", seed=305)
    px = v0 + 540
    g.ink.line([(px - 4, GROUND), (px - 2, GROUND - 520)], 9, amp=0.6)
    g.ink.line([(px - 40, GROUND - 490), (px + 40, GROUND - 490)], 4)
    horn = [(px + 2, GROUND - 450), (px + 64, GROUND - 478), (px + 64, GROUND - 422)]
    g.clear(horn)
    g.pen("ink", 0.4).fill(horn)
    g.ink.poly(horn, w=2.4, amp=0.2)
    g.ink.ellipse(px + 64, GROUND - 450, 6, 28, lw=2.2)
    fline(g, "ink", [(px - 2, GROUND - 486), (px + 2 - 30, GROUND - 400), (px + 6, GROUND - 300)], 1.2, 0.8)
    # 坐车回去的地方：路边一块班车的牌子
    sx = ex["to_home"][0]
    g.ink.line([(sx - 40, GROUND), (sx - 40, GROUND - 250)], 4)
    g.clear(rect_pts(sx - 70, GROUND - 290, 60, 90))
    g.pen("qing").fill(rect_pts(sx - 70, GROUND - 290, 60, 90))
    g.ink.rect(sx - 70, GROUND - 290, 60, 90, lw=2.2)
    knock(g, "qing", "班车", sx - 40, GROUND - 245, 22, vertical=True)
    # 石碾子
    rx = v0 + 200
    g.clear(rect_pts(rx - 60, GROUND - 26, 120, 26))
    g.pen("ink", 0.3).fill(rect_pts(rx - 60, GROUND - 26, 120, 26))
    g.ink.rect(rx - 60, GROUND - 26, 120, 26, lw=2.2)
    g.clear(rect_pts(rx - 40, GROUND - 70, 80, 44))
    g.pen("ink", 0.4).fill(rect_pts(rx - 40, GROUND - 70, 80, 44))
    fhatch(g, "ink", rx - 40, GROUND - 70, 80, 44, 0, 9, 1.0, 0.5)
    g.ink.rect(rx - 40, GROUND - 70, 80, 44, lw=2.2)
    # ---- 姥姥家：红砖瓦房，门楼贴着褪了色的对联；前墙剖开，看得见炕 ----
    eave = GROUND - 300
    hx0, hx1 = y0 + 100, y0 + 600
    # 院子后墙
    g.clear(rect_pts(y0, GROUND - 190, y1 - y0, 190))
    g.pen("mei", 0.4).fill(rect_pts(y0, GROUND - 190, y1 - y0, 190))
    fbricks(g, y0, GROUND - 190, y1 - y0, 190, 30, 11, 0.9, 0.4, seed=307)
    g.clear(rect_pts(y0 - 6, GROUND - 204, y1 - y0 + 12, 16))
    g.pen("ink", 0.4).fill(rect_pts(y0 - 6, GROUND - 204, y1 - y0 + 12, 16))
    g.ink.rect(y0 - 6, GROUND - 204, y1 - y0 + 12, 16, lw=2.2)
    # 正房
    g.clear(rect_pts(hx0, eave, hx1 - hx0, GROUND - eave))
    g.pen("mei", 0.5).fill(rect_pts(hx0, eave, hx1 - hx0, GROUND - eave))
    fbricks(g, hx0, eave, hx1 - hx0, GROUND - eave, 30, 11, 0.9, 0.4, seed=309)
    roof = [(hx0 - 40, eave + 6), (hx0 + 30, eave - 110), (hx1 - 30, eave - 110), (hx1 + 40, eave + 6)]
    g.clear(roof)
    g.pen("ink", 0.45).fill(roof)
    with g.clip(roof):
        for xx in range(int(hx0) - 30, int(hx1) + 40, 13):
            fline(g, "ink", [(xx + 26, eave - 106), (xx, eave + 4)], 1.2, 0.8)
    g.ink.poly(roof, w=3, amp=0.4)
    g.ink.line([(hx0 + 20, eave - 116), (hx1 - 20, eave - 116)], 7, amp=0.3)
    for ex2 in (hx0 + 26, hx1 - 26):
        g.pen("ink").fill([(ex2 - 10, eave - 116), (ex2 + 10, eave - 116), (ex2, eave - 140)])
    # 剖开的那一间：炕、蚊帐、窗台、墙上的年画
    rb0, rb1 = hx0 + 14, hx0 + 270
    g.clear(rect_pts(rb0, eave + 14, rb1 - rb0, GROUND - eave - 14))
    g.pen("mei", 0.08).fill(rect_pts(rb0, eave + 14, rb1 - rb0, GROUND - eave - 14))
    g.pen("ink", 0.08).fill(rect_pts(rb0, eave + 14, rb1 - rb0, GROUND - eave - 14))
    cut_wall(g, hx0 + 7, eave, GROUND, 16, "mei")
    cut_wall(g, rb1 + 8, eave, GROUND, 16, "mei")
    kx = sp["yard_bed"]
    kang = rect_pts(rb0, GROUND - 92, rb1 - rb0, 92)
    g.clear(kang)
    g.pen("mei", 0.45).fill(kang)
    fbricks(g, rb0, GROUND - 92, rb1 - rb0, 92, 30, 11, 0.9, 0.4, seed=311)
    g.ink.rect(rb0, GROUND - 92, rb1 - rb0, 92, lw=2.6)
    g.clear(rect_pts(rb0, GROUND - 100, rb1 - rb0, 10))
    g.pen("qing", 0.45).fill(rect_pts(rb0, GROUND - 100, rb1 - rb0, 10))
    g.ink.rect(rb0, GROUND - 100, rb1 - rb0, 10, lw=1.8)
    # 叠好的被子、枕头
    quilt = [(kx + 40, GROUND - 100), (kx + 40, GROUND - 150), (kx + 120, GROUND - 150), (kx + 120, GROUND - 100)]
    g.clear(quilt)
    g.pen("mei", 0.75).fill(quilt)
    g.ink.poly(quilt, w=2, amp=0.3)
    for k in range(3):
        fline(g, "ink", [(kx + 40, GROUND - 112 - k * 12), (kx + 120, GROUND - 112 - k * 12)], 1.2, 0.6)
    g.clear(ellipse_pts(kx - 60, GROUND - 110, 30, 10))
    g.pen("qing", 0.3).fill(ellipse_pts(kx - 60, GROUND - 110, 30, 10))
    g.ink.ellipse(kx - 60, GROUND - 110, 30, 10, lw=1.6)
    # 蚊帐：从房梁上吊下来，半透的一层网
    net = [(rb0 + 10, eave + 30), (rb1 - 10, eave + 30), (rb1 - 4, GROUND - 100), (rb0 + 4, GROUND - 100)]
    g.pen("ink", 0.06).fill(net)
    g.ink.poly(net, w=1.0, amp=0.4)
    for k in range(6):
        fline(g, "ink", [(rb0 + 20 + k * 44, eave + 32), (rb0 + 16 + k * 45, GROUND - 102)], 0.7, 0.4)
    frame_pic(g, rb0 + 30, eave + 50, 60, 76, "mei", "two")
    # 堂屋：门上挂着帘子，窗户是木格子；屋檐下挂着玉米
    dx = sp["yard_table"] - 10
    g.clear(rect_pts(dx - 50, GROUND - 210, 100, 210))
    g.pen("ink", 0.6).fill(rect_pts(dx - 50, GROUND - 210, 100, 210))
    g.clear(rect_pts(dx - 44, GROUND - 204, 88, 170))
    g.pen("qing", 0.35).fill(rect_pts(dx - 44, GROUND - 204, 88, 170))
    for k in range(5):
        fline(g, "qing", [(dx - 40 + k * 20, GROUND - 204), (dx - 40 + k * 20, GROUND - 34)], 2.4, 1.0)
    g.ink.rect(dx - 50, GROUND - 210, 100, 210, lw=2.8)
    wx = hx1 - 52
    g.clear(rect_pts(wx - 45, eave + 60, 90, 110))
    g.pen("mei", 0.08).fill(rect_pts(wx - 45, eave + 60, 90, 110))
    for k in range(1, 5):
        fline(g, "ink", [(wx - 45 + k * 18, eave + 60), (wx - 45 + k * 18, eave + 170)], 1.4, 0.9)
    for k in range(1, 6):
        fline(g, "ink", [(wx - 45, eave + 60 + k * 18), (wx + 45, eave + 60 + k * 18)], 1.4, 0.9)
    g.ink.rect(wx - 45, eave + 60, 90, 110, lw=2.6)
    mark("window_light", wx, eave + 115)
    for k, cx in enumerate((rb1 + 32, rb1 + 64)):
        corn_string(g, cx, eave + 6, 6 + k % 2)
    # 蒜辫子
    gx0 = rb1 + 104
    g.ink.line([(gx0, eave + 6), (gx0, eave + 18)], 1.4)
    for k in range(7):
        cx, cy = gx0 + (3 if k % 2 else -3), eave + 24 + k * 9
        g.clear(circle_pts(cx, cy, 6.5))
        g.pen("mei", 0.12).fill(circle_pts(cx, cy, 6.5))
        g.ink.circle(cx, cy, 6.5, lw=1.1)
    # 院里一盏灯：屋檐下一只灯泡
    bulb(g, dx, eave + 8, 30)
    # 小方桌、小板凳、一把蒲扇、两只碗
    tx = sp["yard_table"]
    table(g, tx - 10, GROUND, 110, 54)
    for bx2 in (tx - 34, tx + 6):
        g.clear(ellipse_pts(bx2, GROUND - 60, 13, 6))
        g.ink.ellipse(bx2, GROUND - 60, 13, 6, lw=1.6)
        g.qing.line([(bx2 - 10, GROUND - 60), (bx2 + 10, GROUND - 60)], 1.6)
    g.pen("mei", 0.3).fill(ellipse_pts(tx + 34, GROUND - 58, 18, 6))
    g.ink.line([(tx + 50, GROUND - 58), (tx + 66, GROUND - 56)], 2)
    stool(g, tx - 90, GROUND, "ink", 34, 26)
    stool(g, tx + 70, GROUND, "ink", 34, 26)
    # 压水井：铁杆子一压，水从嘴里出来，底下一只水桶
    pw = hx1 + 50
    g.clear(rect_pts(pw - 12, GROUND - 120, 24, 120))
    g.pen("ink", 0.55).fill(rect_pts(pw - 12, GROUND - 120, 24, 120))
    g.ink.rect(pw - 12, GROUND - 120, 24, 120, lw=2.2)
    g.ink.line([(pw + 10, GROUND - 100), (pw + 34, GROUND - 92)], 6)
    g.ink.line([(pw - 6, GROUND - 124), (pw - 70, GROUND - 170)], 5)
    g.pen("qing", 0.6).line([(pw + 34, GROUND - 90), (pw + 36, GROUND - 52)], 3, amp=0.6)
    bucket = [(pw + 18, GROUND - 46), (pw + 58, GROUND - 46), (pw + 52, GROUND), (pw + 24, GROUND)]
    g.clear(bucket)
    g.pen("ink", 0.25).fill(bucket)
    g.ink.poly(bucket, w=2, amp=0.2)
    g.pen("qing", 0.5).fill(ellipse_pts(pw + 38, GROUND - 46, 20, 4))
    g.clear(rect_pts(pw - 40, GROUND - 6, 80, 6))
    g.pen("ink", 0.4).fill(rect_pts(pw - 40, GROUND - 6, 80, 6))
    # 晒着的玉米：一领苇席上摊开一片
    mx0 = hx0 - 90
    g.pen("mei", 0.25).fill([(mx0 - 60, GROUND), (mx0 - 50, GROUND - 12), (mx0 + 60, GROUND - 12), (mx0 + 70, GROUND)])
    fhatch(g, "ink", mx0 - 60, GROUND - 12, 130, 12, 30, 8, 0.8, 0.4)
    for k in range(7):
        cx = mx0 - 44 + k * 15
        g.clear(ellipse_pts(cx, GROUND - 16, 6, 4))
        g.pen("mei", 0.7).fill(ellipse_pts(cx, GROUND - 16, 6, 4))
        g.ink.ellipse(cx, GROUND - 16, 6, 4, lw=0.9)
    # 鸡窝：靠着后墙，砖垒的小房子，门口几只鸡
    cx = sp["yard_chicken"]
    coop = [(cx - 30, GROUND), (cx - 30, GROUND - 90), (cx + 64, GROUND - 106), (cx + 64, GROUND)]
    g.clear(coop)
    g.pen("mei", 0.3).fill(coop)
    g.pen("ink", 0.16).fill(coop)
    fbricks(g, cx - 30, GROUND - 106, 94, 106, 20, 9, 0.8, 0.4, seed=313)
    g.ink.poly(coop, w=2.4, amp=0.3)
    g.clear(rect_pts(cx - 4, GROUND - 44, 40, 44))
    g.pen("ink", 0.7).fill(rect_pts(cx - 4, GROUND - 44, 40, 44))
    g.ink.rect(cx - 4, GROUND - 44, 40, 44, lw=2)
    hen(g, cx - 64, GROUND, 1, True)
    hen(g, cx + 50, GROUND, -1)
    hen(g, cx + 10, GROUND - 98, 1)
    g.pen("ink", 0.3).fill(ellipse_pts(cx - 10, GROUND - 3, 24, 4))
    for k in range(10):
        g.mei.dot(cx - 70 + (k * 37) % 120, GROUND + 4 + (k * 13) % 14, 1.6)
    # 门楼：院子的大门开在右手，两扇木门敞着，对联褪成粉的
    gx = y1 - 50
    g.clear(rect_pts(gx - 60, GROUND - 250, 120, 250))
    g.pen("mei", 0.5).fill(rect_pts(gx - 60, GROUND - 250, 120, 250))
    fbricks(g, gx - 60, GROUND - 250, 120, 250, 20, 9, 0.8, 0.4, seed=315)
    groof = [(gx - 84, GROUND - 246), (gx - 60, GROUND - 290), (gx + 60, GROUND - 290), (gx + 84, GROUND - 246)]
    g.clear(groof)
    g.pen("ink", 0.5).fill(groof)
    g.ink.poly(groof, w=2.4, amp=0.3)
    g.clear(rect_pts(gx - 38, GROUND - 200, 76, 200))
    g.pen("ink", 0.62).fill(rect_pts(gx - 38, GROUND - 200, 76, 200))
    g.ink.rect(gx - 38, GROUND - 200, 76, 200, lw=2.4)
    for s in (-1, 1):
        g.clear(rect_pts(gx + s * 50 - 7, GROUND - 196, 14, 120))
        g.pen("mei", 0.55).fill(rect_pts(gx + s * 50 - 7, GROUND - 196, 14, 120))
    g.clear(rect_pts(gx - 34, GROUND - 236, 68, 22))
    g.pen("mei", 0.55).fill(rect_pts(gx - 34, GROUND - 236, 68, 22))
    # ---- 玉米地：一人多高，田埂边上留一道口子，锄头靠着，一筐掰下来的棒子 ----
    cr = sp["corn_row"]
    rnd = random.Random(319)
    x = c0 + 20
    i = 0
    while x < c1 - 10:
        if abs(x - cr) > 70:
            corn(g, x, GROUND - 16, rnd.uniform(250, 290), seed=321 + i, ear=rnd.random() < 0.6)
        x += rnd.uniform(26, 38)
        i += 1
    x = c0 + 36
    while x < c1 - 10:
        if abs(x - cr) > 50:
            corn(g, x, GROUND, rnd.uniform(240, 280), seed=421 + i, ear=rnd.random() < 0.5)
        x += rnd.uniform(34, 50)
        i += 1
    g.ink.line([(cr + 60, GROUND), (cr + 30, GROUND - 150)], 3)
    g.pen("ink").fill([(cr + 22, GROUND - 150), (cr + 50, GROUND - 156), (cr + 46, GROUND - 140)])
    basket(g, cr - 70, GROUND, 74, 46)
    for k in range(5):
        g.clear(ellipse_pts(cr - 92 + k * 11, GROUND - 52, 6, 15))
        g.pen("mei", 0.6).fill(ellipse_pts(cr - 92 + k * 11, GROUND - 52, 6, 15))
        g.ink.ellipse(cr - 92 + k * 11, GROUND - 52, 6, 15, lw=1.0)
    # 稻草人
    sr = c1 - 150
    g.ink.line([(sr, GROUND), (sr, GROUND - 300)], 4)
    g.ink.line([(sr - 60, GROUND - 230), (sr + 60, GROUND - 236)], 4)
    g.clear(circle_pts(sr, GROUND - 300, 20))
    g.pen("mei", 0.3).fill(circle_pts(sr, GROUND - 300, 20))
    g.ink.circle(sr, GROUND - 300, 20, lw=2)
    g.pen("ink", 0.5).fill([(sr - 34, GROUND - 312), (sr + 34, GROUND - 312), (sr, GROUND - 336)])
    shirt = [(sr - 50, GROUND - 232), (sr + 50, GROUND - 238), (sr + 30, GROUND - 160), (sr - 30, GROUND - 160)]
    g.clear(shirt)
    g.pen("qing", 0.5).fill(shirt)
    g.ink.poly(shirt, w=2, amp=0.5)
    # 电线杆和电线：沿着土路走
    poles = [px, y1 + 60, c1 + 40, t0 + 200]
    tops = [GROUND - 486, pole(g, poles[1], GROUND + 10, 500), pole(g, poles[2], GROUND + 10, 500), pole(g, poles[3], GROUND + 10, 500)]
    wires(g, poles, tops[1] + 2, 46, 2)
    # ---- 河沟：两岸的柳树、芦苇，沟上搭一块石板 ----
    tree(g, k0 + 60, GROUND, 560, 140, "willow", seed=323)
    tree(g, k1 - 80, GROUND, 520, 130, "willow", seed=325)
    for k in range(4):
        rx = (k0 + 140 + k * 26) if k < 2 else (k1 - 180 + k * 22)
        for j in range(6):
            g.qing.line([(rx + j * 5, GROUND), (rx + j * 5 + (j - 3) * 4, GROUND - 60 - j * 6)], 2.2, amp=0.4)
    # ---- 晒场：一大片压平的地，碌碡、麦秸垛、一张苇席 ----
    for (hx, hw, hh) in ((t1 - 160, 220, 210), (t1 + 40, 180, 170)):
        stack = [(hx - hw / 2, GROUND)] + [(hx + hw / 2 * math.cos(math.pi - math.pi * i / 12), GROUND - hh * 0.55 - hh * 0.45 * math.sin(math.pi * i / 12)) for i in range(13)] + [(hx + hw / 2, GROUND)]
        g.clear(stack)
        g.pen("mei", 0.34).fill(stack)
        g.pen("ink", 0.08).fill(stack)
        with g.clip(stack):
            fhatch(g, "ink", hx - hw / 2, GROUND - hh, hw, hh, 70, 10, 1.0, 0.5)
        g.ink.poly(stack, w=2.4, amp=0.8)
        g.ink.line([(hx, GROUND - hh), (hx + 4, GROUND - hh - 26)], 2.4)
    roller = t0 + 140
    g.clear(rect_pts(roller - 50, GROUND - 64, 100, 64))
    g.pen("ink", 0.4).fill(rect_pts(roller - 50, GROUND - 64, 100, 64))
    fhatch(g, "ink", roller - 50, GROUND - 64, 100, 64, 0, 10, 1.4, 0.6)
    g.ink.rect(roller - 50, GROUND - 64, 100, 64, lw=2.6)
    g.ink.ellipse(roller + 50, GROUND - 32, 8, 32, lw=2.4)
    g.ink.line([(roller - 50, GROUND - 32), (roller - 130, GROUND - 6)], 3)
    g.ink.line([(roller + 50, GROUND - 32), (roller - 120, GROUND - 2)], 3)
    th = sp["threshing_ground"]
    mat = [(th - 100, GROUND + 2), (th - 86, GROUND - 10), (th + 92, GROUND - 10), (th + 104, GROUND + 2)]
    g.pen("mei", 0.3).fill(mat)
    fhatch(g, "ink", th - 100, GROUND - 10, 204, 12, 20, 7, 0.8, 0.45)
    g.ink.poly(mat, w=1.6, amp=0.3)
    # 木杈子靠在草垛上
    g.ink.line([(t1 - 290, GROUND), (t1 - 230, GROUND - 230)], 3)
    for s in (-8, 0, 8):
        g.ink.line([(t1 - 230, GROUND - 230), (t1 - 226 + s, GROUND - 262)], 2)
    # ---- 地：土路（梅 + 墨，车辙），晒场压得平，河沟上一块石板 ----
    g.clear(rect_pts(-50, GROUND, W + 100, BOTTOM - GROUND + 60))
    g.pen("mei", 0.32).fill(rect_pts(-50, GROUND, W + 100, BOTTOM - GROUND + 60))
    g.pen("ink", 0.1).fill(rect_pts(-50, GROUND, W + 100, BOTTOM - GROUND + 60))
    g.pen("mei", 0.2).fill(rect_pts(-50, GROUND, W + 100, 30))
    rnd = random.Random(327)
    for i in range(int(W / 4)):
        g.ink.dot(rnd.uniform(-40, W + 40), rnd.uniform(GROUND + 4, BOTTOM), rnd.uniform(0.6, 1.5))
    for yy in (GROUND + 90, GROUND + 104, GROUND + 160, GROUND + 174):
        pts = [(x, yy + 4 * math.sin(x * 0.004 + yy)) for x in range(-40, int(W) + 60, 60)]
        fline(g, "ink", pts, 2.0, 0.35)
    # 路边的草
    for i in range(int(W / 50)):
        gx2 = rnd.uniform(-20, W + 20)
        gy = rnd.uniform(GROUND + 30, GROUND + 60)
        for j in range(4):
            g.qing.line([(gx2 + j * 4, gy), (gx2 + j * 4 + (j - 1.5) * 4, gy - rnd.uniform(10, 22))], 1.6, amp=0.2)
    # 晒场的地面：抹得平，淡一点
    g.clear(rect_pts(t0, GROUND, t1 - t0 + 50, 30), colors=["ink"])
    g.pen("mei", 0.12).fill(rect_pts(t0, GROUND, t1 - t0 + 50, 30))
    # 河沟：路在这儿被一道沟切开，水在底下，上头搭一块石板
    ch0, ch1 = kc - 150, kc + 150
    g.clear(rect_pts(ch0, GROUND + 26, ch1 - ch0, BOTTOM - GROUND + 40))
    bank = [(ch0, GROUND + 20), (ch0 + 40, GROUND + 120), (ch1 - 40, GROUND + 120), (ch1, GROUND + 20)]
    g.pen("mei", 0.3).fill(rect_pts(ch0, GROUND + 26, ch1 - ch0, BOTTOM - GROUND + 40))
    g.pen("ink", 0.2).fill(rect_pts(ch0, GROUND + 26, ch1 - ch0, BOTTOM - GROUND + 40))
    g.clear(bank)
    g.pen("qing", 0.55).fill(bank)
    for k in range(5):
        fline(g, "qing", [(ch0 + 30 + k * 50, GROUND + 50 + k * 12), (ch0 + 70 + k * 50, GROUND + 50 + k * 12)], 2.2, 0.9)
    g.clear(rect_pts(ch0 + 50, GROUND + 60, 30, 2.4), colors=["qing"])
    g.ink.poly(bank, w=2.2, amp=0.5)
    for k in range(3):
        fx = ch0 + 90 + k * 50
        g.pen("ink", 0.7).fill(ellipse_pts(fx, GROUND + 80 + (k % 2) * 16, 9, 3))
    slab_pts = rect_pts(ch0 - 30, GROUND, ch1 - ch0 + 60, 28)
    g.clear(slab_pts)
    g.pen("ink", 0.3).fill(slab_pts)
    fhatch(g, "ink", ch0 - 30, GROUND, ch1 - ch0 + 60, 28, 20, 9, 1.0, 0.5)
    g.ink.rect(ch0 - 30, GROUND, ch1 - ch0 + 60, 28, lw=2.6, amp=0.4)
    g.ink.line([(-50, GROUND), (W + 50, GROUND)], 4.0, amp=0.8)


DRAW = {
    "building": draw_building,
    "street": draw_street,
    "river": draw_river,
    "primary": draw_primary,
    "middle": draw_middle,
    "across": draw_across,
    "away": draw_away,
    "rental": draw_rental,
    "newhome": draw_newhome,
    "park": draw_park,
    "hospital": draw_hospital,
    "market": draw_market,
    "seaside": draw_seaside,
    "village": draw_village,
}


# ----------------------------------------------------------------------
# 输出
# ----------------------------------------------------------------------

class OSheet(Sheet):
    """底图的印张：凡是「先挖空再画」的东西（楼、墙、地面、家具）都是实的，挖空的同时记进纸版，
    这样合成出来天的地方是透明的，后面的天色、远景、中景能透出来。"""

    def clear(self, pts, colors=None, layers=("solid", "tint")):
        super().clear(pts, colors, layers)
        if colors is None and SPLIT:
            ctx = self.plates["paper"]["solid"]
            ctx.save()
            ctx.new_path()
            ctx.move_to(*pts[0])
            for p in pts[1:]:
                ctx.line_to(*p)
            ctx.close_path()
            ctx.set_source_rgba(0, 0, 0, 1)
            ctx.fill()
            ctx.restore()


def solid(g, pts):
    """只记进纸版（这块是实的），不印墨：网点铺的墙、水面这类没先挖空的面用。"""
    if not SPLIT:
        return
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


# 立体感（relief）：孔版是平的，但纸上的东西要「立」起来——招牌、雨棚、檐口、窗台往右下投一道软影子，
# 墙越往下越沉、墙脚贴地那一截再压一道（环境光遮蔽）。只算在实的地方（天是透明的，不印）。
# 改这几个数，十一张图一起变。光从左上来；时段的冷暖交给引擎里的 grade.gdshader。
RELIEF = {
    "cast": (8.0, 11.0),      # 影子往右下偏多少（世界像素）
    "soft": 4.0,             # 影子多软（高斯半径，世界像素）
    "min_size": 5.0,         # 比这细的线不投影（不然每根墨线都多一道，像套印没对准）
    "cast_amt": 0.42,        # 影子多深
    "wall": 0.10,            # 墙从上到下沉多少
    "ao": 0.26,              # 墙脚贴地那一截压多深
    "ao_h": 70.0,            # 压多高（世界像素）
    "tint": (0.62, 0.64, 0.80),  # 影子的颜色（冷一点的墨，不是黑）
}


def relief(g, rgb, alpha, sc, x0, y0, scale):
    """给合成好的 RGB 加立体感。x0, y0：这张纸左上角的世界坐标。"""
    from PIL import ImageFilter

    R = RELIEF
    H, W = alpha.shape
    solid = np.zeros((H, W), np.float32)
    for c in ("ink", "qing", "mei"):
        solid = np.maximum(solid, g.density(c, "solid"))
    # 开运算去掉细线：只剩成块的东西（招牌、雨棚、檐口、门、家具）
    k = int(R["min_size"] * scale) | 1
    blk = Image.fromarray((solid * 255).astype(np.uint8), "L").filter(ImageFilter.MinFilter(k)).filter(ImageFilter.MaxFilter(k))
    dx, dy = int(R["cast"][0] * scale), int(R["cast"][1] * scale)
    sh = Image.new("L", blk.size, 0)
    sh.paste(blk, (dx, dy))
    sh = sh.filter(ImageFilter.GaussianBlur(R["soft"] * scale))
    cast = np.asarray(sh, np.float32) / 255.0 * (1.0 - solid) * R["cast_amt"]
    # 墙越往下越沉；每一层地面往上一截压暗（AO）
    ys = (np.arange(H, dtype=np.float32) / scale + y0)[:, None]
    shade = np.zeros((H, 1), np.float32)
    floors = sc.get("floors", [GROUND])
    prev = TOP
    for fy in floors:
        t = np.clip((ys - prev) / max(fy - prev, 1.0), 0.0, 1.0)
        inside = (ys >= prev) & (ys < fy)
        shade = np.where(inside, R["wall"] * t ** 1.6, shade)
        ao = np.clip(1.0 - (fy - ys) / R["ao_h"], 0.0, 1.0) * inside
        shade = shade + R["ao"] * ao ** 2.2
        # 地面线往下也有一小截被墙挡着的阴
        below = np.clip(1.0 - (ys - fy) / (R["ao_h"] * 0.4), 0.0, 1.0) * (ys >= fy)
        shade = shade + R["ao"] * 0.5 * below ** 2
        prev = fy
    amt = np.clip(cast + shade, 0.0, 0.7) * alpha
    tint = np.array(R["tint"], np.float32)
    out = rgb.astype(np.float32) * (1.0 - amt[..., None] * (1.0 - tint))
    return np.clip(out + 0.5, 0, 255).astype(np.uint8)


def render(sc, x, w, scale, rgba=True):
    g = OSheet(w + 2 * MARGIN, (BOTTOM - TOP) + 2 * MARGIN, scale, origin=(x - MARGIN, TOP - MARGIN), seed=7)
    DRAW[sc["id"]](g, sc)
    m = int(MARGIN * scale)
    al = g.alpha()
    rgb = relief(g, g.composite(True), al, sc, x - MARGIN, TOP - MARGIN, scale)[m:-m, m:-m]
    if not rgba:
        return rgb
    a = np.clip(al[m:-m, m:-m] * 255.0 + 0.5, 0, 255).astype(np.uint8)
    return np.dstack([rgb, a])


def save_png(arr, path):
    """三块墨叠出来的颜色本来就少：量化成 64 色调色板 PNG（带透明）。"""
    img = Image.fromarray(arr, "RGBA" if arr.shape[2] == 4 else "RGB")
    img = img.quantize(colors=64, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    img.save(path, optimize=True)


def collect_anchors(sc):
    """用一张很小的纸把整张图跑一遍，只为了收集灯的位置（这张图自己的坐标）。"""
    global ANCHORS
    ANCHORS = {}
    DRAW[sc["id"]](Sheet(8, 8, 1.0, origin=(-9000, -9000)), sc)
    out, ANCHORS = ANCHORS, None
    res = {}
    for k, v in out.items():
        if k == "layer":
            res[k] = v
        elif k == "trees":
            res[k] = v
        else:
            res[k] = sorted({tuple(p) for p in v})
    return res


def build(ids, scale=ART_SCALE):
    os.makedirs(OUT, exist_ok=True)
    scenes = load_scenes()
    apath = os.path.join(OUT, "anchors.json")
    allanch = {}
    if os.path.exists(apath):
        with open(apath, encoding="utf-8") as f:
            allanch = json.load(f).get("scenes", {})
    for sid in ids:
        allanch[sid] = collect_anchors(scenes[sid])
    with open(apath, "w", encoding="utf-8") as f:
        json.dump({"slice": SLICE, "top": TOP, "bottom": BOTTOM, "scale": ART_SCALE, "scenes": allanch}, f, ensure_ascii=False, separators=(",", ":"))
    for sid in ids:
        sc = scenes[sid]
        # 重印前删旧切片；这回还会印出来的切片和 mask 的 .import 留着（删了 UID 会变），
        # 图变窄、切片变少，多出来的 .import 一起删。（原来边删边查「png 还在不在」，
        # listdir 先删了 png 就会把它的 .import 当成孤儿一起删掉）
        n = math.ceil(sc["width"] / SLICE)
        keep = {f"{sid}_{k}.png.import" for k in range(n)} | {f"{sid}_mask.png.import"}
        for f in sorted(os.listdir(OUT)):
            if f.startswith(sid + "_") and (f.endswith(".png") or f.endswith(".png.import")) and f not in keep:
                os.remove(os.path.join(OUT, f))
        masks = []
        for k in range(n):
            arr = render(sc, k * SLICE, SLICE, scale)
            save_png(arr, os.path.join(OUT, f"{sid}_{k}.png"))
            masks.append(arr[:, :, 3])
        # 哪儿是天：不透明度缩成 1/MASK_STEP，夜版按它在天上少印一点（scene_art.scene_mask）
        full = np.concatenate(masks, axis=1)[:, : int(round(sc["width"] * scale))]
        mw, mh = int(math.ceil(sc["width"] / MASK_STEP)), int((BOTTOM - TOP) / MASK_STEP)
        Image.fromarray(full, "L").resize((mw, mh), Image.BOX).save(os.path.join(OUT, f"{sid}_mask.png"), optimize=True)
        size = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT) if f.startswith(sid + "_") and f.endswith(".png"))
        print(f"  {sid}（{sc['name']}）{n} 片 ✓  {size / 1e6:.1f} MB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*", help="只画这几张（默认全部）")
    ap.add_argument("--preview", help="预览一张图的一段")
    ap.add_argument("--x", type=float, default=0)
    ap.add_argument("--w", type=float, default=0)
    ap.add_argument("--scale", type=float, default=0.5)
    ap.add_argument("--out", default="/tmp/scene_preview.png")
    ap.add_argument("--bg", action="store_true", help="预览时垫一块蓝底，看哪儿是透明的")
    a = ap.parse_args()
    if a.preview:
        sc = load_scenes()[a.preview]
        w = a.w or sc["width"] - a.x
        arr = render(sc, a.x, w, a.scale)
        img = Image.fromarray(arr, "RGBA")
        if a.bg:
            # 垫一块看透明的底：棋盘格 + 一点青，一眼看出哪儿是空的
            bg = Image.new("RGBA", img.size, (120, 170, 200, 255))
            bg.alpha_composite(img)
            img = bg
        img.save(a.out)
        print("预览：", a.out)
        return
    build(a.ids or list(DRAW))


if __name__ == "__main__":
    main()
