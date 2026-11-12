#!/usr/bin/env python3
"""像素版的家里的东西：沿用 home.py 的画法和点位，只换「怎么落成像素」（见 pxlib）。

每张精灵按它在楼里那张图上的世界坐标印（左上角落在 3×3 的格子上，格子原点是 pxlib.GRID0），
引擎原样贴回 at，缩放 1（贴图 1 像素 = 1 世界像素），和底图的点一个一个对得上。
梅家是青家的镜像：坐标在印之前翻（home.mirrored），框往外扩到格子上。

精灵自己带两样底图上没有的东西：
  · 往右下投的硬影子（和底图 compose 的 relief 一个口径：2 个点，压 28% 的影子色），半透明叠在墙上；
  · 东西贴地那一抹影子（墨的浅色、不在纸版里的地方），也是半透明的影子色。

    python3 tools/art/pixel/pxhome.py                              →  client/art/home/atlas.png + sprites.json
    python3 tools/art/pixel/pxhome.py --preview qing --wealth 2 --items tv,radio,books --decade 3 --out /tmp/h.png
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)
import scenes  # noqa: E402
import pxlib  # noqa: E402
import pxsprite  # noqa: E402

pxlib.enable()
import home  # noqa: E402

PX = pxlib.PX
PAD = 12                 # 精灵四周多留一圈（世界像素）：投影 2 个点
M = 9                    # 画的时候再多画一截，裁掉（线头、抗锯齿不被纸边切）
OUT_DIR = home.OUT_DIR
ATLAS_W = 2048
SHADE = pxlib.C["shade"]
CAST = (2, 2)            # 投影偏多少个点（和 pxlib.compose 的 relief 一样）
CAST_A = 0.28
FLOOR_A = 0.42           # 贴地那一抹影子最深多少


# ----------------------------------------------------------------------
# 换几样小零件的画法（只在印精灵时；home.py 里的精灵按名字找这些函数，换了就跟着换）
# ----------------------------------------------------------------------

def doily(g, x0, x1, y, drop=8, scallop=6.0, hang=(True, True), side=6):
    """钩花白布的像素画法：下沿一个点一个点地起伏（锯齿花边），里头一排小眼，不再画一圈圈小圆。"""
    top = y - 2
    if drop < 5:   # 垫在电话底下那种：一条，不起牙
        pts = [(x0 - 2, top), (x1 + 2, top), (x1 + 2, y + drop), (x0 - 2, y + drop)]
        g.clear(pts)
        g.pen("paper").fill(pts)
        g.ink.poly(pts, 1.0, amp=0)
        return
    bot = y + drop
    pts = [(x0 - 2, top), (x1 + 2, top)]
    if hang[1]:
        pts += [(x1 + 3, y + side + 3)]
    # 下沿：每 2 个点一个牙（起伏一个点）
    n = max(2, int(round((x1 - x0) / (2 * PX))))
    edge = []
    for i in range(n, -1, -1):
        bx = x0 + (x1 - x0) * i / n
        edge.append((bx + PX * 0.5, bot + (PX if i % 2 else 0)))
        if i > 0:
            edge.append((bx - (x1 - x0) / n + PX * 0.5, bot + (PX if i % 2 else 0)))
    pts += edge
    if hang[0]:
        pts += [(x0 - 3, y + side + 3)]
    g.clear(pts)
    g.pen("paper").fill(pts)
    g.ink.poly(pts, 1.6, amp=0)
    for i in range(1, n, 2):
        bx = x0 + (x1 - x0) * (i + 0.5) / n
        g.ink.dot(bx, bot - PX, 0.9)


def draw_phone(g, role):
    """电话（像素版）：梅色的座机，一块圆的白拨盘，听筒架在上头，卷线垂在左边。"""
    B = home.BASE
    desk = home.slots()["desk"]
    top = B - 96
    cx = desk - 42
    doily(g, cx - 18, cx + 18, top - 1, drop=3)
    base = [(cx - 14, top - 2), (cx + 14, top - 2), (cx + 10, top - 12), (cx - 10, top - 12)]
    g.clear(base)
    g.pen("mei", 0.8).fill(base)
    g.ink.poly(base, 1.6, amp=0)
    g.clear(home.rect_pts(cx - 4, top - 10, 9, 6))
    g.pen("paper").fill(home.rect_pts(cx - 4, top - 10, 9, 6))
    g.ink.dot(cx + 0.5, top - 7, 1.4)
    hand = [(cx - 17, top - 12), (cx - 14, top - 19), (cx + 14, top - 19), (cx + 17, top - 12)]
    g.clear(hand)
    g.pen("mei", 1.0).fill(hand)
    g.ink.poly(hand, 1.6, amp=0)
    g.ink.line([(cx - 17, top - 11), (cx - 19, top - 7), (cx - 17, top - 4)], 0.9, amp=0)


def draw_sewing(g, role):
    """缝纫机（像素版）：罩布、台面和抽屉照旧；底下的铁架子只留两条腿、一道横撑、一个大轮子、一块脚踏板。"""
    B = home.BASE
    b0, b1 = home.slots()["B"]
    x0, x1 = b0 + 2, b1 - 2
    top = B - 78
    for sx in (x0 + 6, x1 - 6):
        g.ink.line([(sx, top + 9), (sx, B - 3)], 2.6, amp=0)
        g.ink.line([(sx - 6, B - 2), (sx + 6, B - 2)], 2.6, amp=0)
    g.ink.line([(x0 + 6, B - 30), (x1 - 6, B - 30)], 2.0, amp=0)
    wx, wy = x1 - 22, top + 34
    g.clear(home.circle_pts(wx, wy, 13))
    g.pen("ink", 0.12).fill(home.circle_pts(wx, wy, 13))
    g.ink.circle(wx, wy, 13, lw=2.0, amp=0)
    for a in range(4):
        aa = a * math.pi / 4
        g.ink.line([(wx - 11 * math.cos(aa), wy - 11 * math.sin(aa)), (wx + 11 * math.cos(aa), wy + 11 * math.sin(aa))], 0.9, amp=0)
    g.ink.dot(wx, wy, 2.0)
    tread = home.rect_pts(x0 + 12, B - 11, x1 - x0 - 26, 6)
    g.clear(tread)
    g.pen("ink", 0.5).fill(tread)
    g.ink.poly(tread, 1.6, amp=0)
    g.ink.line([(wx, wy), (x0 + 22, B - 10)], 0.9, amp=0)
    home.box(g, x0 - 3, top, x1 - x0 + 6, 9, "ink", 0.36, 2.2)
    home.box(g, x0 + 4, top + 9, 24, 12, "ink", 0.3, 1.6)
    g.ink.dot(x0 + 16, top + 15, 1.5)
    cov = [(x0 + 10, top), (x0 + 12, top - 22), (x0 + 22, top - 34), (x1 - 22, top - 36), (x1 - 12, top - 26), (x1 - 10, top)]
    home.body(g, cov, "qing", 0.30, 1.8, amp=0.5)
    rnd = home.random.Random(7)
    for _ in range(9):
        fx, fy = rnd.uniform(x0 + 16, x1 - 16), rnd.uniform(top - 30, top - 6)
        g.pen("mei", 0.8).dot(fx, fy, 1.2)
    # 荷叶边：下沿一排浅色的牙
    for i in range(0, int(x1 - x0 - 20), 6):
        g.pen("paper").fill(home.rect_pts(x0 + 11 + i, top - 4, 3, 3))
    home.floor_shadow(g, x0, x1, 0.14)


def install():
    """印精灵之前换上：钩花布；电话、缝纫机两样太碎，换成像素的画法（位置、大小照旧）。"""
    home.doily = doily
    home.register()
    home.SPRITES["phone"]["draw"] = draw_phone
    home.SPRITES["sewing"]["draw"] = draw_sewing


def gsnap_x(v, up=False):
    return int(math.ceil(v / PX) * PX if up else math.floor(v / PX) * PX)


def gsnap_y(v, up=False):
    y0 = pxlib.GRID0[1]
    return int((math.ceil((v - y0) / PX) if up else math.floor((v - y0) / PX)) * PX + y0)


def frame_of(name, role):
    """世界里的框 (x0, y0, w, h)：四角都落在格子上。"""
    bx0, by0, bx1, by1 = home.SPRITES[name]["box"]
    bx0, bx1 = bx0 - PAD, bx1 + PAD
    by0, by1 = by0 - PAD, min(by1 + PAD, home.BASE + 6)
    if role == "mei":
        bx0, bx1 = home.AXIS - bx1, home.AXIS - bx0
    x0, x1 = gsnap_x(bx0), gsnap_x(bx1, True)
    y0, y1 = gsnap_y(by0), gsnap_y(by1, True)
    return x0, y0, x1 - x0, y1 - y0


def _shift(a, dx, dy):
    return pxlib._shift(a, dx, dy)


def render(name, role):
    """印一张：回来 (每个点一个像素的 RGBA, (x0, y0) 世界坐标)。"""
    x0, y0, w, h = frame_of(name, role)
    g = scenes.OSheet(w + 2 * M, h + 2 * M, 1.0, origin=(x0 - M, y0 - M), seed=7 + sum(map(ord, name)))
    with pxsprite.crisp(g), home.mirrored(g, role == "mei"):
        home.SPRITES[name]["draw"](g, role)
    gx, gy = x0 // PX, (y0 - int(pxlib.GRID0[1])) // PX
    d, pa, marks = pxlib.plates(g, (M, M + h, M, M + w))
    col, alpha, line = pxlib.compose(d, pa, marks, PX, gx=gx, gy=gy)
    col, alpha, line = pxsprite.clean(col, alpha, line, pxsprite.pooled(d, pa))
    rgba = pxsprite.finish(col, alpha, line, gx=gx, gy=gy)
    return add_shadows(rgba, d, pa, y0), (x0, y0)


def add_shadows(rgba, d, pa, y0):
    """精灵外面（透明的地方）补两样影子：投到墙上的硬影子、贴地的一抹。都是半透明的影子色。"""
    H, W = rgba.shape[:2]
    solid = rgba[..., 3] > 0
    # 只拿成块的东西投影（细线、天线不投）
    blk = pxlib._dilate(pxlib._erode(solid, 1), 1)
    cast = _shift(blk, *CAST) & ~solid
    # 贴地的影子：墨的浅色版里有、纸版里没有的地方（home.floor_shadow 那一抹）
    tint = pxlib.pool(d["ink"][1], PX, "mean")
    paper = pxlib.pool(pa, PX, "max")
    flo = np.clip(tint * 2.2, 0, FLOOR_A) * (paper < 0.5)
    flo = np.where(flo > 0.12, FLOOR_A * 0.75, 0.0)
    a = np.maximum(cast * CAST_A, flo)
    # 地面以下（剖开的楼板）不落影子
    ys = y0 + (np.arange(H) + 1) * PX
    a = a * (ys <= home.BASE)[:, None]
    a = a * ~solid
    out = rgba.copy()
    on = a > 0
    out[on, :3] = SHADE.astype(np.uint8)
    out[on, 3] = np.round(a[on] * 255).astype(np.uint8)
    return out


def pack(images):
    """按高度排架子；每张的位置和大小都是 3 的倍数（贴图里一个点 = 3×3），中间空 3 像素。"""
    order = sorted(images, key=lambda n: (-images[n].shape[0], n))
    x = y = shelf = 0
    pos = {}
    pad = PX
    for n in order:
        h, w = images[n].shape[0] * PX, images[n].shape[1] * PX
        if x + w > ATLAS_W:
            x, y, shelf = 0, y + shelf + pad, 0
        pos[n] = (x, y)
        x += w + pad
        shelf = max(shelf, h)
    H = y + shelf
    atlas = np.zeros((H, ATLAS_W, 4), dtype=np.uint8)
    for n, (px, py) in pos.items():
        big = pxlib.up(images[n], PX)
        h, w = big.shape[:2]
        atlas[py:py + h, px:px + w] = big
    return atlas, pos


def build():
    install()
    home.register()
    images, at = {}, {}
    for name in home.SPRITES:
        for role in ("qing", "mei"):
            key = f"{name}_{role}"
            images[key], at[key] = render(name, role)
    atlas, pos = pack(images)
    os.makedirs(OUT_DIR, exist_ok=True)
    if atlas.shape[0] > 2048:
        print(f"⚠ 图集高 {atlas.shape[0]}，超过 2048")
    Image.fromarray(atlas, "RGBA").save(os.path.join(OUT_DIR, "atlas.png"), optimize=True)
    meta = {"scale": 1.0, "px": PX, "scene": home.SCENE, "cab_top": {str(k): v for k, v in home.CAB_TOP.items()}, "sprites": {}}
    for n in sorted(images):
        h, w = images[n].shape[0] * PX, images[n].shape[1] * PX
        meta["sprites"][n] = {"x": pos[n][0], "y": pos[n][1], "w": w, "h": h, "at": [at[n][0], at[n][1]]}
    with open(os.path.join(OUT_DIR, "sprites.json"), "w", encoding="utf-8") as fp:
        json.dump(meta, fp, ensure_ascii=False, indent=1)
    size = os.path.getsize(os.path.join(OUT_DIR, "atlas.png"))
    print(f"✓ {len(images)} 个精灵 → {os.path.relpath(OUT_DIR, home.ROOT)}/atlas.png（{atlas.shape[1]}×{atlas.shape[0]}，{size / 1e6:.2f} MB）")


# ----------------------------------------------------------------------
# 预览：像素底图那一段 + 这一层（和引擎 home_life.gd 一个挑法、一个贴法）
# ----------------------------------------------------------------------

def background(x0, x1):
    import pxscene
    scenes.ANCHORS = None
    arr, bx = pxscene.render(home.SC, x0, x1)
    return pxlib.up(arr, PX), bx


def over(dst, src, ox, oy):
    """src（RGBA uint8）按 alpha 叠到 dst（float RGB）上，ox, oy 是 dst 里的像素位置。"""
    H, W = dst.shape[:2]
    sx0, sy0 = max(0, -ox), max(0, -oy)
    x0, y0 = max(0, ox), max(0, oy)
    x1, y1 = min(W, ox + src.shape[1]), min(H, oy + src.shape[0])
    if x1 <= x0 or y1 <= y0:
        return
    src = src[sy0:sy0 + y1 - y0, sx0:sx0 + x1 - x0]
    a = src[..., 3:4].astype(np.float32) / 255.0
    sub = dst[y0:y1, x0:x1]
    sub[...] = sub * (1 - a) + src[..., :3].astype(np.float32) * a


def preview(role, wealth, items, decade, out, zoom=1, x0=None, w=1400, atlas=False):
    install()
    home.register()
    if x0 is None:
        x0 = 0 if role == "qing" else int(home.AXIS) - w
    x0 = gsnap_x(x0)
    bg, bx = background(x0, x0 + w)
    sky = np.array((150, 170, 200), np.float32)
    al = bg[..., 3:4] / 255.0
    canvas = bg[..., :3].astype(np.float32) * al + sky * (1 - al)
    meta = None
    if atlas:
        with open(os.path.join(OUT_DIR, "sprites.json"), encoding="utf-8") as f:
            meta = json.load(f)
        at_img = np.asarray(Image.open(os.path.join(OUT_DIR, "atlas.png")).convert("RGBA"))
    for name in home.pick(wealth, items, decade, role):
        if meta is not None:
            sp = meta["sprites"][f"{name}_{role}"]
            big = at_img[sp["y"]:sp["y"] + sp["h"], sp["x"]:sp["x"] + sp["w"]]
            sx, sy = sp["at"]
        else:
            rgba, (sx, sy) = render(name, role)
            big = pxlib.up(rgba, PX)
        over(canvas, big, int(sx - bx), int(sy - scenes.TOP))
    top = int(home.CEIL - 80 - scenes.TOP)
    bot = int(home.BASE + 40 - scenes.TOP)
    img = Image.fromarray(np.clip(canvas[top:bot], 0, 255).astype(np.uint8), "RGB")
    if zoom != 1:
        img = img.resize((int(img.width * zoom), int(img.height * zoom)), Image.NEAREST)
    img.save(out)
    print("预览：", out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", choices=("qing", "mei"))
    ap.add_argument("--wealth", type=int, default=1)
    ap.add_argument("--items", default="")
    ap.add_argument("--decade", type=int, default=3)
    ap.add_argument("--x", type=int)
    ap.add_argument("--w", type=int, default=1400)
    ap.add_argument("--zoom", type=float, default=1.0)
    ap.add_argument("--atlas", action="store_true", help="从出好的 atlas.png + sprites.json 里取（验引擎的贴法）")
    ap.add_argument("--out", default="/tmp/pxhome.png")
    a = ap.parse_args()
    if a.preview:
        preview(a.preview, a.wealth, [s for s in a.items.split(",") if s], a.decade, a.out, a.zoom, a.x, a.w, a.atlas)
        return
    build()


if __name__ == "__main__":
    main()
