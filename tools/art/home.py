#!/usr/bin/env python3
"""家里的东西：红砖楼三楼两户人家屋里，随年代进门的物件和按家境摆的陈设（孔版套色，和底图一个路子）。

    python3 tools/art/home.py                     →  client/art/home/atlas.png + sprites.json
    python3 tools/art/home.py --preview qing --wealth 0 --items tv,radio --decade 3 --out /tmp/h.png
                                                     底图那一段 + 这一层，不进引擎先看一眼

底图（scenes.py 的 home()）只画两家都有的：床、五斗柜、书桌、饭桌、脸盆架、窗、日历。
这一层画的是两样会变的东西（content/home.yaml + 家境），引擎（client/scripts/world/home_life.gd）按 WORLD.homes 摆：
  - 物件：收音机、电视（黑白小方盒 → 彩电 → 薄的）、游戏机、冰箱、一柜子书、电话、复读机、电脑（罩着布）、门口的牛奶箱
  - 家境陈设：清贫 —— 屋当间一道布帘子、一张折起来的行军床、木箱子当电视柜、糊好的纸盒一摞一摞
              小康 —— 一台蒙着罩布的缝纫机、矮柜、墙上一只圆钟
              殷实 —— 地上铺地板革、一张单人沙发搭着白沙发巾、玻璃门电视柜、墙上的摆钟

每个精灵按它在图上的世界坐标印（原点是 4 的倍数，和底图一样 1.25 倍）：网点、套印错位、墙脚的阴影都和底图对得上，
引擎原样贴回那个位置，不缩放不翻转。梅家是青家的镜像（点位左右对称），镜像是在印之前翻坐标，网点照旧朝一个方向。
"""
from __future__ import annotations

import argparse
import json
import math
import os
import random
import sys
from contextlib import contextmanager

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import scenes  # noqa: E402
from riso import ROOT, circle_pts, ellipse_pts, rect_pts  # noqa: E402

SCALE = scenes.ART_SCALE   # 和底图一个倍率：一个世界像素对一个世界像素，网点对得上
OUT_DIR = os.path.join(ROOT, "client", "art", "home")
ATLAS_W = 2048
SCENE = "building"
PAD = 20                   # 精灵四周多留一圈：套印错位、往右下投的影子
WEALTH = (0, 1, 2)         # 0 清贫 1 小康 2 殷实（content/families.yaml 的 wealth）
TV_KINDS = ("bw", "color", "flat")

# ----------------------------------------------------------------------
# 位置：都从青家的点位推（梅家是镜像）。和 scenes.py 的 home() 一起看
# ----------------------------------------------------------------------

SC = None
SP = {}
AXIS = 3200.0
BASE = 720.0     # 三楼地面（这张图自己的坐标）
CEIL = 320.0


def _load():
    global SC, SP, AXIS, BASE, CEIL
    if SC is not None:
        return
    SC = scenes.load_scenes()[SCENE]
    SP = SC["spots"]
    AXIS = SP["table_qing"] + SP["table_mei"]
    for k in ("bed", "corner", "desk", "table", "basin"):
        assert abs(SP[f"{k}_qing"] + SP[f"{k}_mei"] - AXIS) < 1, f"{k} 两家不对称：home.py 按镜像画梅家"
    BASE = SC["floors"][1]
    CEIL = SC["floors"][0] + 60


def slots():
    """青家的几块地方（世界 x）。T：饭桌和脸盆架之间（电视柜）；B：书桌和饭桌之间（缝纫机 / 沙发 / 布帘子）。"""
    _load()
    desk, table, basin, corner = SP["desk_qing"], SP["table_qing"], SP["basin_qing"], SP["corner_qing"]
    return {
        "T": (table + 100, basin - 66),        # 900 ~ 1004
        "B": (desk + 108, table - 96),         # 628 ~ 704
        "corner": corner,                      # 350：五斗柜 / 书柜，电脑桌摆在它跟前
        "desk": desk,                          # 520：书桌（宽 210），台面 base-96
        "fridge": (basin + 50, basin + 112),   # 1120 ~ 1182：门口
        "door": SP["door_qing"],               # 1300：楼道里青家的门
    }


CAB_TOP = {0: 672.0, 1: 648.0, 2: 656.0}   # 三种电视柜的台面（清贫是木箱子）


def tv_center(w):
    t0, t1 = slots()["T"]
    return (t0 + 36) if w == 0 else (t0 + t1) / 2


# ----------------------------------------------------------------------
# 精灵登记：名字 → 世界里的框（青家坐标）+ 画法
# ----------------------------------------------------------------------

SPRITES: dict = {}


def sprite(name, box):
    """box = (x0, y0, x1, y1) 青家坐标；印的时候四周加 PAD，对齐到 4 的倍数。"""
    def deco(fn):
        SPRITES[name] = dict(box=box, draw=fn)
        return fn
    return deco


def _snap(v, up=False):
    return float(math.ceil(v / 4.0) * 4 if up else math.floor(v / 4.0) * 4)


def frame_of(name, role):
    x0, y0, x1, y1 = SPRITES[name]["box"]
    x0, y0, x1, y1 = _snap(x0 - PAD), _snap(y0 - PAD), _snap(x1 + PAD, True), _snap(min(y1 + PAD, BASE + 8), True)
    if role == "mei":
        x0, x1 = AXIS - x1, AXIS - x0
    return x0, y0, x1 - x0, y1 - y0


@contextmanager
def mirrored(g, on):
    """梅家：整张纸的坐标左右翻（x → AXIS − x）。网点是印的时候按设备像素算的，所以不跟着翻。"""
    if not on:
        yield
        return
    ctxs = [g.plates[c][layer] for c in ("ink", "qing", "mei") for layer in ("solid", "tint")] + [g.plates["paper"]["solid"]]
    for c in ctxs:
        c.save()
        c.translate(AXIS, 0)
        c.scale(-1, 1)
    try:
        yield
    finally:
        for c in ctxs:
            c.restore()


# ----------------------------------------------------------------------
# 小零件
# ----------------------------------------------------------------------

def body(g, pts, color="ink", d=0.3, lw=2.2, amp=0.4):
    """一件实的东西：挖空（纸版记上）、铺一层网点、墨线勾边。"""
    g.clear(pts)
    if d:
        g.pen(color, d).fill(pts)
    g.ink.poly(pts, lw, amp=amp)


def box(g, x, y, w, h, color="ink", d=0.3, lw=2.2):
    body(g, rect_pts(x, y, w, h), color, d, lw)


def rbox(x, y, w, h, r):
    """圆角矩形的点。"""
    pts = []
    for cx, cy, a0 in ((x + w - r, y + r, -90), (x + w - r, y + h - r, 0), (x + r, y + h - r, 90), (x + r, y + r, 180)):
        for k in range(5):
            a = math.radians(a0 + k * 22.5)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def doily(g, x0, x1, y, drop=8, scallop=6.0, hang=(True, True), side=6):
    """钩花的白布：搭在东西顶上，前沿垂下一截，边上一个个小扇贝；hang 两头要不要从侧面垂下来。"""
    n = max(2, int((x1 - x0) / scallop))
    pts = [(x0 - 2, y - 2), (x1 + 2, y - 2)]
    if hang[1]:
        pts += [(x1 + 3, y + side), (x1, y + side + 3)]
    bottom = []
    for i in range(n, -1, -1):
        bx = x0 + (x1 - x0) * i / n
        bottom.append((bx, y + drop + (2.4 if i % 2 else 0)))
    pts += bottom
    if hang[0]:
        pts += [(x0, y + side + 3), (x0 - 3, y + side)]
    g.clear(pts)
    g.pen("ink", 0.05).fill(pts)
    g.ink.poly(pts, 1.2, amp=0.2)
    for i in range(n):
        bx = x0 + (x1 - x0) * (i + 0.5) / n
        g.ink.dot(bx, y + drop - 2, 0.9)
    for i in range(1, n, 2):
        bx = x0 + (x1 - x0) * i / n
        g.ink.circle(bx, y + drop * 0.45, 1.6, lw=0.8, amp=0)


def knob(g, x, y, r=3.0, color="ink"):
    g.clear(circle_pts(x, y, r))
    g.pen(color, 0.5).fill(circle_pts(x, y, r))
    g.ink.circle(x, y, r, lw=1.2, amp=0)


def glare(g, x0, y0, x1, y1, line=False):
    """玻璃、屏幕上的反光：左上角一小道斜的留纸色（网点挖掉，不挖墨线）。"""
    w, h = x1 - x0, y1 - y0
    k = min(w, h)
    g.clear([(x0 + k * 0.10, y0 + k * 0.42), (x0 + k * 0.16, y0 + k * 0.42), (x0 + k * 0.42, y0 + k * 0.10), (x0 + k * 0.36, y0 + k * 0.10)], colors=("ink", "qing"), layers=("tint",))
    if line:
        g.ink.line([(x0 + w * 0.62, y0 + h * 0.86), (x0 + w * 0.78, y0 + h * 0.3)], 0.9, amp=0.1, density=0.5)


def floor_shadow(g, x0, x1, d=0.22):
    """东西贴地的那一道：很扁的一抹墨网点（底图的家具也是这样落地的）。"""
    g.pen("ink", d).fill(ellipse_pts((x0 + x1) / 2 + 4, BASE - 1, (x1 - x0) / 2 + 4, 3.2, 28))


# ----------------------------------------------------------------------
# 家境陈设
# ----------------------------------------------------------------------

def _furnish():
    sl = slots()
    b0, b1 = sl["B"]
    t0, t1 = sl["T"]
    tc = (t0 + t1) / 2
    cx = sl["corner"]

    # 殷实：地上铺了地板革。剖面里看得见的是贴着地的一窄条，人字纹
    @sprite("floor_rich", (20, BASE - 11, sl["fridge"][1] + 2, BASE + 1))
    def _(g, role):
        x0, x1 = 20, sl["fridge"][1] + 2
        y0 = BASE - 10
        pts = [(x0, y0), (x1, y0), (x1 + 2, BASE + 1), (x0 - 2, BASE + 1)]
        g.clear(pts)
        g.pen("mei", 0.34).fill(pts)
        g.pen("ink", 0.14).fill(pts)
        x = x0
        k = 0
        while x < x1 - 6:
            # 人字：一格往左斜一格往右斜
            if k % 2:
                g.ink.line([(x, BASE), (x + 9, y0)], 0.9, amp=0, density=0.55)
            else:
                g.ink.line([(x, y0), (x + 9, BASE)], 0.9, amp=0, density=0.55)
            x += 11
            k += 1
        g.ink.line([(x0, y0), (x1, y0)], 1.4, amp=0.2)
        g.mei.line([(x0, y0 + 2), (x1, y0 + 2)], 0.8, amp=0.1)

    # 清贫：屋当间一道布帘子（夜里拉上，一间屋隔成两间），后头立着一张折起来的钢丝床，地上一个被卷
    @sprite("curtain", (b0 - 30, CEIL + 8, b1 + 8, BASE))
    def _(g, role):
        other = "mei" if role == "qing" else "qing"
        # 折叠床：对折起来立着，一圈铁管，里头钢丝网，底下两只小轮子
        fx0, fx1, fy0 = b0 + 30, b1 - 4, BASE - 128
        frame = rbox(fx0, fy0, fx1 - fx0, BASE - 8 - fy0, 6)
        g.clear(frame)
        g.pen("ink", 0.08).fill(frame)
        inner = rbox(fx0 + 4, fy0 + 4, fx1 - fx0 - 8, BASE - 16 - fy0, 4)
        g.pen("ink").hatch(inner, 50, 6.5, 0.7, density=0.55)
        g.pen("ink").hatch(inner, -50, 6.5, 0.7, density=0.55)
        g.ink.poly(frame, 2.8, amp=0.2)
        g.ink.line([(fx0 + 2, BASE - 68), (fx1 - 2, BASE - 68)], 2.2, amp=0.1)   # 折页那道
        for wx in (fx0 + 6, fx1 - 6):
            g.ink.line([(wx, BASE - 8), (wx, BASE - 4)], 2.0, amp=0)
            g.ink.circle(wx, BASE - 3, 3, lw=1.4, amp=0)
        # 被卷：花被子卷起来，绳子捆两道，靠床脚放着
        roll = rbox(fx0 + 4, BASE - 22, fx1 - fx0 + 6, 22, 10)
        body(g, roll, other, 0.36, 1.8)
        rnd = random.Random(17)
        for _ in range(8):
            g.pen(other).circle(rnd.uniform(fx0 + 10, fx1 + 4), rnd.uniform(BASE - 17, BASE - 6), 2.4, lw=1.0, amp=0)
        for k in (0.3, 0.72):
            sx = fx0 + 4 + (fx1 - fx0 + 6) * k
            g.ink.line([(sx, BASE - 22), (sx + 1, BASE)], 1.2, amp=0)
        # 帘子：一根铁丝两头钉在墙上，布往一边拢着，半腰一根布带子系住
        top = CEIL + 22
        g.ink.line([(b0 - 26, top), (b1 + 6, top)], 1.4, amp=0.3)
        for nx in (b0 - 26, b1 + 6):
            g.ink.dot(nx, top, 2.0)
        cx0, cx1 = b0 - 22, b0 + 36      # 上头拢起来的宽度
        tie_y, tx0, tx1 = BASE - 176, b0 - 2, b0 + 18
        bot = BASE - 20
        bx0, bx1 = b0 - 18, b0 + 34
        left = [(cx0, top + 3), (cx0 + 6, top + 60), (tx0, tie_y), (bx0 + 4, bot - 50), (bx0, bot)]
        right = [(bx1, bot), (bx1 - 4, bot - 50), (tx1, tie_y), (cx1 - 8, top + 60), (cx1, top + 3)]
        hem = [(bx0 + (bx1 - bx0) * i / 8, bot + (2.5 if i % 2 else -0.5)) for i in range(1, 8)]
        topedge = [(cx1 - (cx1 - cx0) * i / 9, top + 3 + (1.6 if i % 2 else 0)) for i in range(1, 9)]
        pts = left + hem + right + topedge
        g.clear(pts)
        g.pen("mei", 0.14).fill(pts)
        g.pen("ink", 0.05).fill(pts)
        # 碎花：一朵四个瓣，配一点青叶子
        rnd = random.Random(31)
        for _ in range(44):
            fy = rnd.uniform(top + 10, bot - 6)
            # 那一高度布有多宽
            t = (fy - top) / (tie_y - top) if fy < tie_y else (fy - tie_y) / (bot - tie_y)
            if fy < tie_y:
                lx, rx = cx0 + (tx0 - cx0) * t, cx1 + (tx1 - cx1) * t
            else:
                lx, rx = tx0 + (bx0 - tx0) * t, tx1 + (bx1 - tx1) * t
            fx = rnd.uniform(lx + 4, rx - 4)
            for a in range(4):
                g.pen("mei", 0.75).fill(circle_pts(fx + 1.8 * math.cos(a * math.pi / 2), fy + 1.8 * math.sin(a * math.pi / 2), 1.3, 6))
            g.pen("qing", 0.7).fill(circle_pts(fx + 3.2, fy + 2.6, 1.1, 6))
        # 褶子
        for k in range(1, 5):
            u = k / 5
            g.ink.line([(cx0 + (cx1 - cx0) * u, top + 6), (tx0 + (tx1 - tx0) * u, tie_y - 4)], 0.9, amp=0.5, density=0.6)
            g.ink.line([(tx0 + (tx1 - tx0) * u, tie_y + 6), (bx0 + (bx1 - bx0) * u + (k % 2) * 2, bot - 3)], 0.9, amp=0.5, density=0.6)
        g.ink.poly(pts, 1.8, amp=0.4)
        # 系带
        band = [(tx0 - 3, tie_y - 4), (tx1 + 3, tie_y - 4), (tx1 + 3, tie_y + 4), (tx0 - 3, tie_y + 4)]
        body(g, band, "qing", 0.0, 1.2)
        g.qing.fill(band)
        g.qing.line([(tx1 + 2, tie_y + 2), (tx1 + 7, tie_y + 16)], 2.2, amp=0)
        for i in range(10):
            g.ink.circle(cx0 + (cx1 - cx0) * i / 9, top, 2.0, lw=0.9, amp=0)

    # 清贫：糊好的纸盒，一摞一摞用纸绳捆着（电视柜旁一摞，饭桌底下一摞）
    @sprite("boxes", (SP["table_qing"] - 26, BASE - 64, t1, BASE))
    def _(g, role):
        def bundle(x, y, w, h, tilt=0.0):
            pts = [(x, y + tilt), (x + w, y), (x + w, y + h), (x, y + h)]
            body(g, pts, "mei", 0.22, 1.6)
            g.pen("ink", 0.1).fill(pts)
            for k in range(1, 4):
                g.ink.line([(x + 1, y + h * k / 4 + tilt * (1 - k / 4)), (x + w - 1, y + h * k / 4)], 0.8, amp=0.2, density=0.6)
            g.ink.line([(x + w * 0.5, y + tilt * 0.5 - 1), (x + w * 0.5, y + h + 1)], 1.2, amp=0.1)
            g.ink.line([(x + w * 0.5, y + tilt * 0.5 - 1), (x + w * 0.5 - 3, y - 4), (x + w * 0.5 + 3, y - 3)], 1.0, amp=0.1)
        x = t1 - 32
        bundle(x, BASE - 16, 32, 16)
        bundle(x + 2, BASE - 31, 29, 15, 1.0)
        bundle(x - 1, BASE - 46, 31, 15)
        bundle(x + 3, BASE - 60, 26, 14, 1.5)
        # 一个还没折好的，平摊在最上头
        g.ink.line([(x + 2, BASE - 62), (x + 30, BASE - 64)], 1.2, amp=0.2)
        tx = SP["table_qing"] - 20
        bundle(tx, BASE - 15, 40, 15)
        bundle(tx + 4, BASE - 29, 34, 14, 1.0)
        floor_shadow(g, x - 2, x + 34, 0.16)

    # 小康：一台缝纫机，机头蒙着罩布；底下的铁架子带脚踏板和大轮子
    @sprite("sewing", (b0, BASE - 116, b1, BASE))
    def _(g, role):
        x0, x1 = b0 + 2, b1 - 2
        top = BASE - 78
        # 铁架子：两片镂花的侧架，一块脚踏板，一个大轮子
        for sx in (x0 + 6, x1 - 6):
            g.ink.line([(sx, top + 10), (sx - 2, BASE)], 2.6, amp=0.2)
            g.ink.line([(sx - 7, BASE), (sx + 7, BASE)], 2.6, amp=0.1)
        g.ink.line([(x0 + 6, BASE - 20), (x1 - 6, BASE - 20)], 1.6, amp=0.2)
        for k in range(3):
            g.ink.arc(x0 + 6 + (x1 - x0 - 12) * (k + 0.5) / 3, BASE - 30, 7, math.pi, 2 * math.pi, 1.2, amp=0)
        wx = x1 - 22
        g.ink.circle(wx, top + 32, 14, lw=1.8, amp=0)
        for a in range(4):
            aa = a * math.pi / 4
            g.ink.line([(wx - 13 * math.cos(aa), top + 32 - 13 * math.sin(aa)), (wx + 13 * math.cos(aa), top + 32 + 13 * math.sin(aa))], 0.9, amp=0)
        tread = [(x0 + 12, BASE - 8), (x1 - 14, BASE - 12), (x1 - 12, BASE - 6), (x0 + 14, BASE - 3)]
        body(g, tread, "ink", 0.5, 1.4)
        g.ink.line([(wx, top + 32), (x0 + 30, BASE - 8)], 1.0, amp=0)
        # 台面 + 抽屉
        box(g, x0 - 3, top, x1 - x0 + 6, 9, "ink", 0.36, 2.2)
        box(g, x0 + 4, top + 9, 26, 14, "ink", 0.3, 1.6)
        g.ink.dot(x0 + 17, top + 16, 1.5)
        # 罩布：机头那一坨，罩着一块印花布，下沿一圈荷叶边
        cov = [(x0 + 10, top), (x0 + 12, top - 22), (x0 + 22, top - 34), (x1 - 22, top - 36), (x1 - 12, top - 26), (x1 - 10, top)]
        body(g, cov, "qing", 0.30, 1.8, amp=0.5)
        rnd = random.Random(7)
        for _ in range(9):
            fx, fy = rnd.uniform(x0 + 16, x1 - 16), rnd.uniform(top - 30, top - 6)
            g.pen("mei", 0.5).fill(circle_pts(fx, fy, 1.5, 8))
        for i in range(8):
            fx = x0 + 10 + (x1 - x0 - 20) * (i + 0.5) / 8
            g.ink.arc(fx, top - 1, 2.8, 0, math.pi, 1.0, amp=0)
        floor_shadow(g, x0, x1, 0.14)

    # 殷实：一张单人沙发，靠背上搭着白沙发巾，扶手上也有两小块
    @sprite("sofa", (b0, BASE - 112, b1 + 2, BASE))
    def _(g, role):
        other = "mei" if role == "qing" else "qing"
        x0, x1 = b0 + 2, b1
        seat = BASE - 40
        # 腿
        for lx in (x0 + 8, x1 - 8):
            g.ink.line([(lx, seat + 18), (lx + (2 if lx < (x0 + x1) / 2 else -2), BASE)], 3.0, amp=0)
        back = rbox(x0 + 6, BASE - 100, x1 - x0 - 12, 70, 12)
        body(g, back, other, 0.42, 2.2)
        cush = rbox(x0 + 4, seat - 8, x1 - x0 - 8, 26, 6)
        body(g, cush, other, 0.5, 2.0)
        g.ink.line([(x0 + 12, seat + 2), (x1 - 12, seat + 2)], 1.0, amp=0.3, density=0.6)
        for ax0 in (x0 - 2, x1 - 12):
            arm = rbox(ax0, BASE - 66, 14, 50, 6)
            body(g, arm, other, 0.55, 2.0)
        # 靠背上的扣子
        for k in range(3):
            g.ink.dot(x0 + 20 + k * (x1 - x0 - 40) / 2, BASE - 74, 1.6)
        # 沙发巾：靠背上一大块，扶手上两小块
        doily(g, x0 + 14, x1 - 14, BASE - 100, drop=20, scallop=5.5, hang=(False, False))
        for ax0 in (x0 - 2, x1 - 12):
            doily(g, ax0 + 1, ax0 + 13, BASE - 66, drop=8, scallop=4, hang=(False, False))
        floor_shadow(g, x0, x1, 0.18)

    # 小康：墙上一只圆钟（原来底图上的那只）
    @sprite("clock_round", (tc - 30, CEIL + 44, tc + 30, CEIL + 104))
    def _(g, role):
        scenes.clock(g, tc, CEIL + 74, 26)

    # 殷实：一台摆钟，木头壳子，底下的玻璃里看得见钟摆
    @sprite("clock_pendulum", (tc - 26, CEIL + 34, tc + 26, CEIL + 156))
    def _(g, role):
        x0, y0, w, h = tc - 22, CEIL + 44, 44, 108
        crown = [(x0 - 3, y0 + 8), (x0 + 6, y0 - 2), (x0 + w / 2, y0 - 8), (x0 + w - 6, y0 - 2), (x0 + w + 3, y0 + 8)]
        body(g, crown + [(x0 + w + 3, y0 + 10), (x0 - 3, y0 + 10)], "ink", 0.5, 1.8)
        box(g, x0, y0 + 8, w, h - 8, "ink", 0.42, 2.2)
        g.clear(circle_pts(tc, y0 + 30, 15))
        g.pen("ink", 0.06).fill(circle_pts(tc, y0 + 30, 15))
        g.ink.circle(tc, y0 + 30, 15, lw=1.8, amp=0)
        for k in range(12):
            a = k * math.tau / 12
            g.ink.dot(tc + math.cos(a) * 12, y0 + 30 + math.sin(a) * 12, 0.9)
        g.ink.line([(tc, y0 + 30), (tc + 2, y0 + 21)], 1.6, amp=0)
        g.ink.line([(tc, y0 + 30), (tc + 8, y0 + 33)], 1.6, amp=0)
        win = (x0 + 7, y0 + 52, w - 14, h - 62)
        g.clear(rect_pts(*win))
        g.pen("ink", 0.12).fill(rect_pts(*win))
        g.ink.rect(*win, lw=1.4, amp=0.2)
        g.ink.line([(tc, win[1] + 2), (tc + 3, win[1] + win[3] - 14)], 1.2, amp=0)
        g.clear(circle_pts(tc + 3, win[1] + win[3] - 10, 6.5))
        g.pen("mei", 0.55).fill(circle_pts(tc + 3, win[1] + win[3] - 10, 6.5))
        g.ink.circle(tc + 3, win[1] + win[3] - 10, 6.5, lw=1.2, amp=0)
        glare(g, *win[:2], win[0] + win[2], win[1] + win[3])
        g.ink.line([(x0 - 2, y0 + h), (x0 + w + 2, y0 + h)], 2.4, amp=0.2)

    # 书柜：五斗柜的地方换成一个玻璃门的书柜（底图的五斗柜整个盖住），顶上还是那个相框
    @sprite("bookcase", (cx - 76, BASE - 380, cx + 76, BASE + 2))
    def _(g, role):
        x0, x1 = cx - 75, cx + 75
        top = BASE - 316
        w = x1 - x0
        accent = role
        box(g, x0, top, w, BASE - top, "ink", 0.2, 2.8)
        g.ink.line([(x0 - 4, top), (x1 + 4, top)], 3.2, amp=0.2)
        mid = BASE - 110
        # 上半截：两扇玻璃门，里头三层书
        gx0, gx1, gy0, gy1 = x0 + 10, x1 - 10, top + 12, mid - 8
        g.clear(rect_pts(gx0, gy0, gx1 - gx0, gy1 - gy0))
        g.pen("ink", 0.07).fill(rect_pts(gx0, gy0, gx1 - gx0, gy1 - gy0))
        rnd = random.Random(53)
        rows = 3
        rh = (gy1 - gy0) / rows
        for r in range(rows):
            sy = gy0 + rh * (r + 1)
            x = gx0 + 3
            while x < gx1 - 6:
                bw = rnd.choice((5, 6, 7, 8, 9, 11))
                bh = rh - rnd.uniform(6, 20)
                if x + bw > gx1 - 3:
                    break
                c = rnd.choice(("ink", "qing", "mei", "ink", accent))
                lean = 0.0
                if rnd.random() < 0.07 and x + bw + 12 < gx1:
                    lean = 7.0
                pts = [(x, sy), (x + bw, sy), (x + bw + lean, sy - bh), (x + lean, sy - bh)]
                g.pen(c, rnd.uniform(0.32, 0.62)).fill(pts)
                g.ink.poly(pts, 0.9, amp=0.1)
                if bw >= 8 and rnd.random() < 0.6:
                    g.ink.line([(x + 2, sy - bh * 0.7), (x + bw - 2, sy - bh * 0.7)], 0.7, amp=0, density=0.7)
                x += bw + (lean + 2 if lean else rnd.choice((0, 0, 1)))
                if rnd.random() < 0.05:
                    x += 10
            g.ink.line([(gx0, sy), (gx1, sy)], 1.8, amp=0.1)
        g.ink.rect(gx0, gy0, gx1 - gx0, gy1 - gy0, lw=1.8, amp=0.2)
        g.ink.line([((gx0 + gx1) / 2, gy0), ((gx0 + gx1) / 2, gy1)], 1.8, amp=0.1)
        for kx in ((gx0 + gx1) / 2 - 5, (gx0 + gx1) / 2 + 5):
            g.ink.line([(kx, (gy0 + gy1) / 2 - 6), (kx, (gy0 + gy1) / 2 + 6)], 1.6, amp=0)
        # 下半截：两扇木门
        for k in range(2):
            dx = x0 + 10 + k * (w - 20) / 2
            g.ink.rect(dx + 2, mid + 2, (w - 20) / 2 - 4, BASE - mid - 18, lw=1.6, amp=0.2)
            g.ink.dot(dx + ((w - 20) / 2 - 10 if k == 0 else 8), mid + (BASE - mid) / 2 - 6, 2.4)
        g.ink.line([(x0, mid), (x1, mid)], 2.4, amp=0.1)
        g.pen("ink", 0.4).fill(rect_pts(x0 + 2, BASE - 12, w - 4, 10))
        # 顶上的相框（底图里是立在五斗柜上的那个）
        fx = cx - 62
        scenes.frame_pic(g, fx, top - 60, 64, 60, accent, "two")

    # 电视柜：清贫是一只红漆木箱子，小康是一个矮柜，殷实是带玻璃拉门的电视柜
    @sprite("cab_0", (t0 - 2, CAB_TOP[0] - 6, t0 + 74, BASE))
    def _(g, role):
        x0, x1, top = t0, t0 + 72, CAB_TOP[0]
        # 两块砖垫着
        for bx in (x0 + 6, x1 - 22):
            box(g, bx, BASE - 9, 16, 9, "mei", 0.5, 1.2)
        box(g, x0, top, x1 - x0, BASE - 9 - top, "mei", 0.45, 2.2)
        g.pen("ink", 0.12).fill(rect_pts(x0, top, x1 - x0, BASE - 9 - top))
        g.ink.line([(x0, top + 8), (x1, top + 8)], 1.4, amp=0.2)
        # 包角、锁鼻
        for ex in (x0, x1):
            s = 1 if ex == x0 else -1
            g.ink.poly([(ex, top), (ex + 8 * s, top), (ex, top + 8)], 1.0, fill=True, amp=0)
            g.ink.poly([(ex, BASE - 9), (ex + 8 * s, BASE - 9), (ex, BASE - 17)], 1.0, fill=True, amp=0)
        box(g, (x0 + x1) / 2 - 5, top + 6, 10, 12, "ink", 0.5, 1.2)
        g.ink.circle((x0 + x1) / 2, top + 15, 1.6, lw=0.8, amp=0)
        # 箱子上铺一块布，四角垂下来
        cloth = [(x0 - 3, top - 1), (x1 + 3, top - 1), (x1 + 4, top + 12), (x1 - 2, top + 9), (x0 + 2, top + 9), (x0 - 4, top + 12)]
        body(g, cloth, "qing", 0.30, 1.4)
        for i in range(9):
            g.ink.line([(x0 + 4 + i * 8, top + 1), (x0 + 6 + i * 8, top + 8)], 0.7, amp=0, density=0.6)
        floor_shadow(g, x0, x1, 0.18)

    @sprite("cab_1", (t0 - 2, CAB_TOP[1] - 6, t1 + 2, BASE))
    def _(g, role):
        x0, x1, top = t0 + 2, t1 - 2, CAB_TOP[1]
        for lx in (x0 + 5, x1 - 5):
            g.ink.line([(lx, BASE - 8), (lx, BASE)], 3.0, amp=0)
        box(g, x0, top + 4, x1 - x0, BASE - 8 - top - 4, "ink", 0.28, 2.4)
        box(g, x0 - 3, top, x1 - x0 + 6, 6, "ink", 0.4, 2.0)
        midx = (x0 + x1) / 2
        g.ink.line([(midx, top + 8), (midx, BASE - 12)], 1.4, amp=0.1)
        g.ink.rect(x0 + 6, top + 12, midx - x0 - 10, BASE - top - 28, lw=1.2, amp=0.2)
        g.ink.rect(midx + 4, top + 12, x1 - midx - 10, BASE - top - 28, lw=1.2, amp=0.2)
        knob(g, midx - 6, top + 34, 2.4)
        knob(g, midx + 6, top + 34, 2.4)
        # 台面上的一条白钩花
        doily(g, x0 + 8, x1 - 8, top - 1, drop=6, scallop=5, hang=(False, False))
        floor_shadow(g, x0, x1, 0.16)

    @sprite("cab_2", (t0 - 4, CAB_TOP[2] - 6, t1 + 4, BASE))
    def _(g, role):
        x0, x1, top = t0, t1, CAB_TOP[2]
        for lx, s in ((x0 + 6, -1), (x1 - 6, 1)):
            g.ink.line([(lx, BASE - 10), (lx + 3 * s, BASE)], 3.0, amp=0)
        box(g, x0, top + 5, x1 - x0, BASE - 10 - top - 5, "ink", 0.46, 2.4)
        box(g, x0 - 4, top, x1 - x0 + 8, 6, "ink", 0.58, 2.2)
        # 玻璃拉门：里头码着磁带、两只碗
        gx0, gx1, gy0, gy1 = x0 + 6, x1 - 6, top + 12, BASE - 18
        g.clear(rect_pts(gx0, gy0, gx1 - gx0, gy1 - gy0))
        g.pen("ink", 0.1).fill(rect_pts(gx0, gy0, gx1 - gx0, gy1 - gy0))
        for k in range(6):
            tx = gx0 + 4 + k * 7
            g.pen("ink" if k % 2 else "qing", 0.5).fill(rect_pts(tx, gy1 - 22, 5, 22))
            g.ink.rect(tx, gy1 - 22, 5, 22, lw=0.7, amp=0)
        for k in range(2):
            bx = gx1 - 30 + k * 8
            g.mei.arc(bx, gy1 - 10 - k * 6, 9, 0, math.pi, 1.2, amp=0)
            g.ink.line([(bx - 9, gy1 - 10 - k * 6), (bx + 9, gy1 - 10 - k * 6)], 0.9, amp=0)
        g.ink.rect(gx0, gy0, gx1 - gx0, gy1 - gy0, lw=1.6, amp=0.1)
        g.ink.line([((gx0 + gx1) / 2 + 4, gy0), ((gx0 + gx1) / 2 + 4, gy1)], 1.4, amp=0)
        g.ink.line([((gx0 + gx1) / 2 - 4, gy0 + 1), ((gx0 + gx1) / 2 - 4, gy1 - 1)], 1.0, amp=0, density=0.6)
        glare(g, gx0, gy0, (gx0 + gx1) / 2, gy1)
        glare(g, (gx0 + gx1) / 2, gy0, gx1, gy1)
        floor_shadow(g, x0, x1, 0.2)


# ----------------------------------------------------------------------
# 物件
# ----------------------------------------------------------------------

def _tv(g, kind, cx, top, role):
    if kind == "bw":
        # 黑白小方盒：木纹壳子，左边一块鼓着的屏，右边两只旋钮，顶上一对兔耳朵天线
        w, h = 58, 46
        x0, y0 = cx - w / 2, top - h
        for a, l in ((-0.42, 48), (0.5, 42)):
            tip = (cx + 6 + math.sin(a) * l, y0 - math.cos(a) * l)
            g.ink.line([(cx + 6, y0 + 2), tip], 1.4, amp=0)
            g.ink.dot(*tip, 1.6)
        body(g, rbox(x0, y0, w, h, 5), "ink", 0.32, 2.2)
        sx0, sy0, sx1, sy1 = x0 + 5, y0 + 6, x0 + 39, y0 + h - 7
        g.clear(rbox(sx0, sy0, sx1 - sx0, sy1 - sy0, 6))
        g.pen("ink", 0.52).fill(rbox(sx0, sy0, sx1 - sx0, sy1 - sy0, 6))
        g.ink.poly(rbox(sx0, sy0, sx1 - sx0, sy1 - sy0, 6), 1.6, amp=0.1)
        glare(g, sx0, sy0, sx1, sy1)
        knob(g, x0 + 48, y0 + 13, 4.2)
        knob(g, x0 + 48, y0 + 27, 3.4)
        for k in range(3):
            g.ink.line([(x0 + 43, y0 + 35 + k * 3), (x0 + 53, y0 + 35 + k * 3)], 0.8, amp=0)
        doily(g, x0 + 6, x0 + w - 6, y0, drop=6, scallop=5, hang=(False, False))
    elif kind == "color":
        # 彩电：大一圈，屏幕四角圆、往外鼓；右边一竖条按键和喇叭眼，两根拉杆天线
        w, h = 82, 66
        x0, y0 = cx - w / 2, top - h
        for a, l in ((-0.55, 54), (0.62, 50)):
            tip = (cx + 10 + math.sin(a) * l, y0 - math.cos(a) * l)
            g.ink.line([(cx + 10, y0 + 2), tip], 1.2, amp=0)
            g.ink.dot(*tip, 1.4)
        body(g, rbox(x0, y0, w, h, 7), "ink", 0.22, 2.4)
        g.pen("ink", 0.12).fill(rect_pts(x0 + 3, y0 + h - 8, w - 6, 6))
        sx0, sy0, sx1, sy1 = x0 + 6, y0 + 6, x0 + 60, y0 + h - 11
        scr = rbox(sx0, sy0, sx1 - sx0, sy1 - sy0, 9)
        g.clear(scr)
        g.pen("ink", 0.62).fill(scr)
        g.pen("qing", 0.22).fill(scr)
        g.ink.poly(scr, 1.8, amp=0.1)
        glare(g, sx0, sy0, sx1, sy1)
        for k in range(5):
            g.ink.rect(x0 + 66, y0 + 8 + k * 6, 10, 3.4, lw=0.8, amp=0)
        g.mei.dot(x0 + 71, y0 + 42, 1.7)
        for r in range(3):
            for c in range(3):
                g.ink.dot(x0 + 67 + c * 4, y0 + 48 + r * 4, 0.9)
        doily(g, x0 + 10, x0 + w - 10, y0, drop=7, scallop=5.5, hang=(True, True), side=10)
    else:
        # 薄的：一块黑板子立在小脚上
        w, h = 104, 60
        x0, y0 = cx - w / 2, top - h - 9
        foot = [(cx - 14, top), (cx + 14, top), (cx + 8, top - 4), (cx + 3, y0 + h), (cx - 3, y0 + h), (cx - 8, top - 4)]
        body(g, foot, "ink", 0.6, 1.4)
        body(g, rect_pts(x0, y0, w, h), "ink", 0.56, 2.0)
        g.pen("qing", 0.18).fill(rect_pts(x0 + 3, y0 + 3, w - 6, h - 6))
        g.ink.rect(x0 + 3, y0 + 3, w - 6, h - 6, lw=0.8, amp=0)
        glare(g, x0 + 3, y0 + 3, x0 + w - 3, y0 + h - 3)
        g.mei.dot(x0 + w - 6, y0 + h - 2, 1.0)


def _items():
    sl = slots()
    t0, t1 = sl["T"]
    cx = sl["corner"]
    desk = sl["desk"]
    desk_top = BASE - 96

    for w in WEALTH:
        tc = tv_center(w)
        top = CAB_TOP[w]
        for kind in TV_KINDS:
            def make(kind=kind, tc=tc, top=top):
                hw = {"bw": 56, "color": 64, "flat": 56}[kind]
                @sprite(f"tv_{kind}_{w}", (tc - hw, top - 124, tc + hw, top + 1))
                def _(g, role):
                    _tv(g, kind, tc, top, role)
            make()

        # 游戏机：小孩打游戏都坐地上。机子搁在电视柜跟前的地上，插着一盘卡；一根线顺着柜子爬上去接电视，
        # 两个手柄拖着线扔在一边
        def make_console(w=w, tc=tc, top=top):
            @sprite(f"console_{w}", (t0 - 30, top - 4, t0 + 64, BASE))
            def _(g, role):
                bx0, by = t0 + 4, BASE
                # 接电视的线：从机子后头顺着柜子侧面上去
                g.ink.line([(bx0 + 40, by - 8), (bx0 + 48, by - 12), (t0 + 52, top + 10), (tc - 18, top - 1)], 1.0, amp=0.4)
                cart = [(bx0 + 10, by - 26), (bx0 + 32, by - 26), (bx0 + 32, by - 12), (bx0 + 10, by - 12)]
                body(g, cart, "mei", 0.6, 1.4)
                g.pen("ink", 0.2).fill(rect_pts(bx0 + 14, by - 23, 14, 6))
                g.ink.rect(bx0 + 14, by - 23, 14, 6, lw=0.8, amp=0)
                shell = [(bx0, by), (bx0 + 44, by), (bx0 + 44, by - 10), (bx0 + 40, by - 14), (bx0 + 4, by - 14), (bx0, by - 10)]
                body(g, shell, "ink", 0.12, 1.8)
                g.mei.fill(rect_pts(bx0 + 2, by - 5, 40, 2.4))
                for k in range(2):
                    body(g, rect_pts(bx0 + 6 + k * 9, by - 11, 6, 3), "ink", 0.6, 0.8)
                # 两个手柄：线绕一下扔在地上
                for k, (px, tilt) in enumerate(((t0 - 22, -0.15), (t0 + 50, 0.2))):
                    py = BASE - 5
                    sx = bx0 + (6 if k == 0 else 38)
                    mid = ((sx + px) / 2, BASE - 18 - k * 4)
                    g.ink.line([(sx, by - 7), mid, (px + 9, py - 2)], 0.9, amp=0.5)
                    c, s_ = math.cos(tilt), math.sin(tilt)
                    pad = [(px + x * c - y * s_, py + x * s_ + y * c) for x, y in rbox(-1, -4, 20, 8, 3)]
                    body(g, pad, "ink", 0.22, 1.3, amp=0)
                    g.ink.dot(px + 4 * c, py + 4 * s_, 1.3)
                    g.mei.dot(px + 13 * c, py + 13 * s_, 1.3)
                    g.mei.dot(px + 16.5 * c, py + 16.5 * s_ - 1.5, 1.3)
                floor_shadow(g, bx0, bx0 + 44, 0.18)
        make_console()

    # 收音机：五斗柜（或书柜）顶上靠书桌那头，盖着一块钩花的白布
    def make_radio(name, top):
        @sprite(name, (cx + 2, top - 40, cx + 74, top + 1))
        def _(g, role):
            x0, w, h = cx + 10, 52, 30
            y0 = top - h
            box(g, x0, y0 + 3, w, h - 3, "mei", 0.38, 2.0)
            g.pen("ink", 0.2).fill(rect_pts(x0, y0 + 3, w, h - 3))
            gr = (x0 + 4, y0 + 8, 24, h - 13)
            g.clear(rect_pts(*gr))
            g.pen("ink", 0.3).hatch(rect_pts(*gr), 0, 2.4, 0.7, density=0.8)
            g.pen("ink", 0.18).fill(rect_pts(*gr))
            g.ink.rect(*gr, lw=1.0, amp=0)
            dial = (x0 + 31, y0 + 9, 17, 8)
            g.clear(rect_pts(*dial))
            g.ink.rect(*dial, lw=0.9, amp=0)
            for k in range(5):
                g.ink.line([(dial[0] + 2 + k * 3.3, dial[1] + 1), (dial[0] + 2 + k * 3.3, dial[1] + 3)], 0.6, amp=0)
            g.mei.line([(dial[0] + 9, dial[1]), (dial[0] + 9, dial[1] + 8)], 1.0, amp=0)
            knob(g, x0 + 35, y0 + 23, 3.0)
            knob(g, x0 + 44, y0 + 23, 3.0)
            for lx in (x0 + 4, x0 + w - 4):
                g.ink.line([(lx, top - 1), (lx, top)], 2.4, amp=0)
            doily(g, x0 + 2, x0 + w - 2, y0 + 3, drop=7, scallop=5, hang=(True, True), side=11)
    make_radio("radio_dresser", BASE - 300)
    make_radio("radio_case", BASE - 316)

    # 冰箱：进门那块地方。顶上也盖一块钩花布，压一个塑料花瓶
    f0, f1 = sl["fridge"]
    @sprite("fridge", (f0 - 4, BASE - 186, f1 + 4, BASE))
    def _(g, role):
        x0, x1, top = f0 + 2, f1 - 2, BASE - 150
        w = x1 - x0
        for lx in (x0 + 5, x1 - 5):
            g.ink.line([(lx, BASE - 6), (lx, BASE)], 2.6, amp=0)
        shell = rbox(x0, top, w, BASE - 6 - top, 6)
        body(g, shell, "ink", 0.07, 2.4)
        g.pen("qing", 0.06).fill(shell)
        g.ink.line([(x0 + 1, top + 44), (x1 - 1, top + 44)], 1.8, amp=0.1)
        # 把手在开门那边
        hx = x0 + 6
        for y0, y1 in ((top + 12, top + 34), (top + 54, top + 96)):
            g.ink.line([(hx, y0), (hx, y1)], 3.0, amp=0)
            g.ink.line([(hx, y0), (hx + 3, y0)], 1.4, amp=0)
            g.ink.line([(hx, y1), (hx + 3, y1)], 1.4, amp=0)
        g.ink.rect(x1 - 20, top + 54, 12, 6, lw=0.9, amp=0)
        for k in range(4):
            g.ink.line([(x0 + 10, BASE - 16 + k * 2.4), (x1 - 10, BASE - 16 + k * 2.4)], 0.7, amp=0, density=0.7)
        g.ink.line([(x0 + 3, top + 8), (x0 + 3, BASE - 12)], 0.8, amp=0, density=0.35)
        doily(g, x0 + 4, x1 - 4, top, drop=6, scallop=5, hang=(True, True), side=12)
        # 塑料花：一只小瓶，三枝
        vx = (x0 + x1) / 2 + 6
        body(g, [(vx - 5, top - 1), (vx + 5, top - 1), (vx + 4, top - 16), (vx - 4, top - 16)], "qing", 0.4, 1.2)
        for a, l, c in ((-0.5, 18, "mei"), (0.1, 24, "mei"), (0.6, 16, "qing")):
            tip = (vx + math.sin(a) * l, top - 16 - math.cos(a) * l)
            g.qing.line([(vx, top - 15), tip], 1.0, amp=0)
            g.pen(c, 0.7).fill(circle_pts(*tip, 3.2, 10))
        floor_shadow(g, x0, x1, 0.2)

    # 电脑：屋角一张电脑桌，摆在五斗柜 / 书柜跟前。显示器罩着一块布（大的那种），机箱在桌子底下
    def make_pc(kind):
        @sprite(f"pc_{kind}", (cx - 58, BASE - 132, cx + 58, BASE))
        def _(g, role):
            x0, x1 = cx - 54, cx + 54
            top = BASE - 74
            box(g, x1 - 30, BASE - 50, 22, 48, "ink", 0.12, 1.8)   # 机箱
            g.ink.line([(x1 - 26, BASE - 42), (x1 - 12, BASE - 42)], 0.8, amp=0)
            g.mei.dot(x1 - 13, BASE - 34, 1.1)
            for lx in (x0 + 4, x1 - 4):
                g.ink.line([(lx, top + 6), (lx, BASE)], 3.2, amp=0)
            box(g, x0, top, x1 - x0, 7, "ink", 0.14, 2.4)
            g.clear(rect_pts(x0 + 4, top + 7, x1 - x0 - 8, 8))
            g.pen("ink", 0.06).fill(rect_pts(x0 + 4, top + 7, x1 - x0 - 8, 8))
            g.ink.line([(x0 + 4, top + 15), (x1 - 4, top + 15)], 1.2, amp=0.1)
            box(g, x0 + 10, top + 17, x1 - x0 - 46, 5, "ink", 0.18, 1.4)   # 键盘托
            for k in range(6):
                g.ink.line([(x0 + 14 + k * 6, top + 18), (x0 + 14 + k * 6, top + 21)], 0.6, amp=0)
            mx = cx - 4
            if kind == "crt":
                mw, mh = 62, 52
                my0 = top - mh
                body(g, rbox(mx - mw / 2 + 6, my0 + 2, mw - 12, mh - 2, 4), "ink", 0.12, 1.6)   # 屁股
                body(g, rbox(mx - mw / 2, my0, mw - 14, mh, 4), "ink", 0.06, 2.0)
                body(g, [(mx - 14, top), (mx + 6, top), (mx + 2, top - 4), (mx - 10, top - 4)], "ink", 0.12, 1.2)
                scr = rbox(mx - mw / 2 + 5, my0 + 5, mw - 24, mh - 13, 4)
                g.clear(scr)
                g.pen("ink", 0.55).fill(scr)
                g.ink.poly(scr, 1.2, amp=0)
                g.mei.dot(mx + mw / 2 - 20, my0 + mh - 4, 1.0)
                # 罩布：从顶上搭下来，盖住后半截，前沿掀起来一点露着屏
                cloth = [(mx - mw / 2 - 2, my0 + 10), (mx - mw / 2 + 4, my0 - 3), (mx + mw / 2 - 2, my0 - 2), (mx + mw / 2 + 3, my0 + 34),
                         (mx + mw / 2 - 3, my0 + 31), (mx + mw / 2 - 8, my0 + 36), (mx + 6, my0 + 4), (mx - mw / 2 + 2, my0 + 6)]
                body(g, cloth, "qing", 0.34, 1.6, amp=0.4)
                g.pen("qing", 0.25).hatch(cloth, 30, 4, 0.7, density=0.6)
                g.ink.line([(mx + 4, my0 + 2), (mx + mw / 2 - 6, my0 + 30)], 0.9, amp=0.3, density=0.6)
                glare(g, mx - mw / 2 + 5, my0 + 5, mx + mw / 2 - 19, my0 + mh - 8)
            else:
                mw, mh = 62, 40
                my0 = top - mh - 12
                body(g, [(mx - 12, top), (mx + 12, top), (mx + 3, top - 3), (mx + 3, my0 + mh), (mx - 3, my0 + mh), (mx - 3, top - 3)], "ink", 0.5, 1.2)
                body(g, rect_pts(mx - mw / 2, my0, mw, mh), "ink", 0.65, 1.8)
                g.pen("qing", 0.2).fill(rect_pts(mx - mw / 2 + 3, my0 + 3, mw - 6, mh - 6))
                glare(g, mx - mw / 2 + 3, my0 + 3, mx + mw / 2 - 3, my0 + mh - 3)
            # 鼠标、音箱
            body(g, rbox(x1 - 18, top - 5, 10, 5, 2.4), "ink", 0.1, 1.0, amp=0)
            g.ink.line([(x1 - 13, top - 5), (x1 - 18, top - 9), (mx + 20, top - 6)], 0.7, amp=0.2)
            body(g, rbox(x0 + 3, top - 22, 12, 22, 2), "ink", 0.4, 1.4)
            g.ink.circle(x0 + 9, top - 9, 3, lw=0.8, amp=0)
            floor_shadow(g, x0, x1, 0.16)
    make_pc("crt")
    make_pc("lcd")

    # 复读机：书桌上靠着书，一根耳机线垂下桌沿
    @sprite("tape", (desk + 68, desk_top - 24, desk + 108, desk_top + 34))
    def _(g, role):
        x0 = desk + 73
        w, h = 30, 17
        y0 = desk_top - h
        g.ink.line([(x0 + 6, y0 + 1), (x0 + 9, y0 - 5), (x0 + 21, y0 - 5), (x0 + 24, y0 + 1)], 1.6, amp=0)   # 提手
        body(g, rbox(x0, y0, w, h, 3), "ink", 0.42, 1.6)
        g.pen("qing", 0.2).fill(rbox(x0, y0, w, h, 3))
        win = (x0 + 4, y0 + 4, 15, 9)
        g.clear(rect_pts(*win))
        g.ink.rect(*win, lw=0.9, amp=0)
        g.ink.circle(win[0] + 4.5, win[1] + 4.5, 2.2, lw=0.8, amp=0)
        g.ink.circle(win[0] + 10.5, win[1] + 4.5, 2.2, lw=0.8, amp=0)
        for k in range(3):
            g.pen("mei" if k == 1 else "ink", 0.7).fill(rect_pts(x0 + 21 + (k % 2) * 4, y0 + 4 + (k // 2) * 5, 3, 3))
        # 耳机线
        cord = [(x0 + w, y0 + 10), (x0 + w + 3, y0 + 14), (x0 + w + 4, desk_top + 2)]
        for i in range(1, 8):
            cord.append((x0 + w + 4 - i * 0.6, desk_top + 2 + i * 3.4 + math.sin(i) * 1.2))
        g.ink.line(cord, 0.8, amp=0.2)
        for ex in (-3, 3):
            g.ink.dot(x0 + w + ex, desk_top + 30, 1.8)

    # 电话：书桌靠台灯那头，红的，垫着一小块钩花
    @sprite("phone", (desk - 64, desk_top - 22, desk - 20, desk_top + 2))
    def _(g, role):
        cxp = desk - 42
        doily(g, cxp - 19, cxp + 19, desk_top - 2, drop=3, scallop=4, hang=(False, False))
        base = [(cxp - 15, desk_top - 2), (cxp + 15, desk_top - 2), (cxp + 11, desk_top - 13), (cxp - 11, desk_top - 13)]
        body(g, base, "mei", 0.6, 1.6)
        g.clear(ellipse_pts(cxp, desk_top - 7, 6, 3.4))
        g.ink.ellipse(cxp, desk_top - 7, 6, 3.4, lw=0.9, amp=0)
        hand = [(cxp - 17, desk_top - 13), (cxp - 13, desk_top - 19), (cxp + 13, desk_top - 19), (cxp + 17, desk_top - 13), (cxp + 11, desk_top - 13), (cxp + 9, desk_top - 16), (cxp - 9, desk_top - 16), (cxp - 11, desk_top - 13)]
        body(g, hand, "mei", 0.7, 1.4)
        # 卷线
        for k in range(5):
            g.ink.arc(cxp - 19 + 0.5, desk_top - 11 + k * 2.2, 2.2, -1.2, 2.0, 0.7, amp=0)

    # 牛奶箱：楼道里门旁边钉着的木头箱子，斜盖子，一把小锁
    door = sl["door"]
    @sprite("milk", (door - 76, BASE - 178, door + 78, BASE - 118))
    def _(g, role):
        # 钉在门的右手边（两家都是：门左边贴春联的地方，底图 hallway()）。梅家是镜像印的，所以青家坐标里往左挪
        x0, y0, w, h = (door + 44 if role == "qing" else door - 72), BASE - 168, 28, 40
        g.ink.dot(x0 + w / 2, y0 - 6, 1.8)
        lid = [(x0 - 2, y0 + 4), (x0 + w + 2, y0 - 2), (x0 + w + 2, y0 + 6), (x0 - 2, y0 + 10)]
        box(g, x0, y0 + 6, w, h - 6, "ink", 0.3, 2.0)
        g.pen("mei", 0.18).fill(rect_pts(x0, y0 + 6, w, h - 6))
        body(g, lid, "ink", 0.42, 1.6)
        g.ink.line([(x0 + 4, y0 + 16), (x0 + w - 4, y0 + 16)], 0.9, amp=0)
        box(g, x0 + w / 2 - 3, y0 + 20, 6, 7, "ink", 0.5, 1.0)
        g.ink.arc(x0 + w / 2, y0 + 20, 2.4, math.pi, 2 * math.pi, 0.9, amp=0)
        for k in range(3):
            g.ink.line([(x0 + 3, y0 + 30 + k * 3), (x0 + w - 3, y0 + 30 + k * 3)], 0.6, amp=0, density=0.6)


_furnish_done = False


def register():
    global _furnish_done
    if _furnish_done:
        return
    _load()
    _furnish()
    _items()
    _furnish_done = True


# ----------------------------------------------------------------------
# 印
# ----------------------------------------------------------------------

def render(name, role):
    x0, y0, w, h = frame_of(name, role)
    g = scenes.OSheet(w, h, SCALE, origin=(x0, y0), seed=7 + sum(map(ord, name)))
    with mirrored(g, role == "mei"):
        SPRITES[name]["draw"](g, role)
    al = g.alpha()
    rgb = scenes.relief(g, g.composite(True), al, SC, x0, y0, SCALE)
    # 东西往右下投一道软影子落在墙上（底图 relief 的口径，减半：屋里的家具底图也只投一点）。
    # 这一层自己带着影子，半透明叠到底图上；细线先开运算去掉，不然每根线都多一道
    R = scenes.RELIEF
    k = int(R["min_size"] * SCALE) | 1
    blk = Image.fromarray((np.clip(al, 0, 1) * 255).astype(np.uint8), "L").filter(ImageFilter.MinFilter(k)).filter(ImageFilter.MaxFilter(k))
    dx, dy = int(R["cast"][0] * SCALE * 0.5), int(R["cast"][1] * SCALE * 0.5)
    sh = Image.new("L", blk.size, 0)
    sh.paste(blk, (dx, dy))
    sh = sh.filter(ImageFilter.GaussianBlur(R["soft"] * SCALE))
    cast = np.asarray(sh, np.float32) / 255.0 * R["cast_amt"] * 0.55
    # 地面以下（剖开的楼板）不落影子
    ys = np.arange(al.shape[0], dtype=np.float32)[:, None] / SCALE + y0
    cast = cast * (ys < BASE - 1)
    # 影子的颜色：纸色乘上 relief 的冷墨，叠在纸色的墙上就和底图的影子一样
    paper = np.array((0xF4, 0xEE, 0xE1), np.float32)
    sh_rgb = paper * np.array(R["tint"], np.float32) * 0.78
    a_sp = al
    a_sh = cast * (1.0 - a_sp)
    a = a_sp + a_sh
    out = (rgb.astype(np.float32) * a_sp[..., None] + sh_rgb * a_sh[..., None]) / np.maximum(a[..., None], 1e-4)
    rgba = np.dstack([np.clip(out + 0.5, 0, 255).astype(np.uint8), np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8)])
    return rgba, (x0, y0)


def pack(images):
    order = sorted(images, key=lambda n: (-images[n].shape[0], n))
    x = y = shelf = 0
    pos = {}
    pad = 2
    for n in order:
        h, w = images[n].shape[:2]
        if x + w > ATLAS_W:
            x, y, shelf = 0, y + shelf + pad, 0
        pos[n] = (x, y)
        x += w + pad
        shelf = max(shelf, h)
    H = y + shelf
    atlas = np.zeros((H, ATLAS_W, 4), dtype=np.uint8)
    for n, (px, py) in pos.items():
        h, w = images[n].shape[:2]
        atlas[py:py + h, px:px + w] = images[n]
    return atlas, pos


def build():
    register()
    images, at = {}, {}
    for name in SPRITES:
        for role in ("qing", "mei"):
            key = f"{name}_{role}"
            images[key], at[key] = render(name, role)
    atlas, pos = pack(images)
    os.makedirs(OUT_DIR, exist_ok=True)
    if atlas.shape[0] > 2048:
        print(f"⚠ 图集高 {atlas.shape[0]}，超过 2048")
    Image.fromarray(atlas, "RGBA").save(os.path.join(OUT_DIR, "atlas.png"), optimize=True)
    meta = {"scale": SCALE, "scene": SCENE, "cab_top": {str(k): v for k, v in CAB_TOP.items()}, "sprites": {}}
    for n in sorted(images):
        h, w = images[n].shape[:2]
        meta["sprites"][n] = {"x": pos[n][0], "y": pos[n][1], "w": w, "h": h, "at": [at[n][0], at[n][1]]}
    with open(os.path.join(OUT_DIR, "sprites.json"), "w", encoding="utf-8") as fp:
        json.dump(meta, fp, ensure_ascii=False, indent=1)
    size = os.path.getsize(os.path.join(OUT_DIR, "atlas.png"))
    print(f"✓ {len(images)} 个精灵 → {os.path.relpath(OUT_DIR, ROOT)}/atlas.png（{atlas.shape[1]}×{atlas.shape[0]}，{size / 1e6:.2f} MB）")


# ----------------------------------------------------------------------
# 预览：底图那一段 + 这一层（和引擎 home_life.gd 一个挑法）
# ----------------------------------------------------------------------

def pick(wealth, items, decade, role):
    """这户人家该摆哪几张（顺序 = 从后往前）。和 client/scripts/world/home_life.gd 的 pick() 一致。"""
    out = []
    if wealth == 2:
        out.append("floor_rich")
    out.append({0: "curtain", 1: "sewing", 2: "sofa"}[wealth])
    if wealth == 1:
        out.append("clock_round")
    elif wealth == 2:
        out.append("clock_pendulum")
    if "books" in items:
        out.append("bookcase")
    if "radio" in items:
        out.append("radio_case" if "books" in items else "radio_dresser")
    out.append(f"cab_{wealth}")
    if wealth == 0:
        out.append("boxes")
    if "tv" in items:
        if decade >= 6 or (decade == 5 and wealth >= 1):   # 清贫人家一〇年代还看那台大脑袋彩电
            kind = "flat"
        elif decade <= 2:
            kind = "color" if (wealth == 2 and decade == 2) else "bw"
        else:
            kind = "bw" if (wealth == 0 and decade == 3) else "color"
        out.append(f"tv_{kind}_{wealth}")
        if "console" in items:
            out.append(f"console_{wealth}")
    if "fridge" in items:
        out.append("fridge")
    if "pc" in items:
        out.append("pc_lcd" if decade >= 5 else "pc_crt")
    if "tape" in items:
        out.append("tape")
    if "phone" in items:
        out.append("phone")
    if "milk" in items:
        out.append("milk")
    return out


def preview(role, wealth, items, decade, out, scale):
    register()
    x0 = 0 if role == "qing" else AXIS - 1400
    w = 1400
    base = scenes.render(SC, x0, w, SCALE)
    img = Image.fromarray(base, "RGBA")
    canvas = Image.new("RGBA", img.size, (0xF4, 0xEE, 0xE1, 255))
    canvas.alpha_composite(img)
    for name in pick(wealth, items, decade, role):
        rgba, (sx, sy) = render(name, role)
        sp = Image.fromarray(rgba, "RGBA")
        canvas.alpha_composite(sp, (int(round((sx - x0) * SCALE)), int(round((sy - scenes.TOP) * SCALE))))
    crop = canvas.crop((0, int((CEIL - 80 - scenes.TOP) * SCALE), canvas.width, int((BASE + 60 - scenes.TOP) * SCALE)))
    if scale != SCALE:
        crop = crop.resize((int(crop.width * scale / SCALE), int(crop.height * scale / SCALE)), Image.LANCZOS)
    crop.convert("RGB").save(out)
    print("预览：", out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", choices=("qing", "mei"))
    ap.add_argument("--wealth", type=int, default=1)
    ap.add_argument("--items", default="")
    ap.add_argument("--decade", type=int, default=3, help="0 六十年代 … 3 九十年代 4 千禧年头上 5 一〇年代 6 往后")
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--out", default="/tmp/home_preview.png")
    a = ap.parse_args()
    if a.preview:
        preview(a.preview, a.wealth, [s for s in a.items.split(",") if s], a.decade, a.out, a.scale)
        return
    build()


if __name__ == "__main__":
    main()
