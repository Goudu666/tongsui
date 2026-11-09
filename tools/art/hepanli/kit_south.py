"""南半边（小学 / 自行车铺 / 小花园 / 南边街坊）共用的小工具。

都按 common.py 的视角约定：顶面按平面画，朝南的正面在顶面下方露出一截，影子落右下。
"""
from __future__ import annotations

import random

from common import Ctx, ellipse_pts, rect_pts, shadow


def block(g, x, y, w, d, h, top=("ink", 0.10), face=("ink", 0.22), lw=2.4, sh=0.16, shadow_len=None):
    """一个方块（房子、台子、墙墩）：顶面 (x, y, w, d)，正面高 h 露在下面。
    阴影先画，然后挖空方块再画，所以后画的方块会盖住先画的东西。"""
    s = shadow_len if shadow_len is not None else h * 0.7
    if s > 0:
        shadow(g, [(x + w, y + d), (x + w + s, y + d + s * 0.35), (x + w + s, y + d + h + s * 0.35),
                   (x + s * 0.6, y + d + h + s * 0.35), (x, y + d + h)], sh)
    pts = rect_pts(x, y, w, d + h)
    g.clear(pts)
    if top:
        g.pen(top[0], top[1]).fill(rect_pts(x, y, w, d))
    if face and h > 0:
        g.pen(face[0], face[1]).fill(rect_pts(x, y + d, w, h))
    g.ink.rect(x, y, w, d + h, lw=lw)
    if h > 0:
        g.ink.line([(x, y + d), (x + w, y + d)], lw * 0.8)


def ground_tex(g, x, y, w, h, density=0.06, seed=1, specks=0):
    """压实的土地 / 水泥地：很淡的墨网点 + 几粒小石子。"""
    rnd = random.Random(seed)
    g.pen("ink", density).fill(rect_pts(x, y, w, h))
    for _ in range(specks):
        px, py = x + rnd.uniform(6, w - 6), y + rnd.uniform(6, h - 6)
        g.ink.dot(px, py, rnd.uniform(0.9, 1.6), density=0.55)


def grass(g, pts_box, n=30, seed=3, color="qing", density=0.8):
    """一小撮一小撮的草（两笔的小“v”）。pts_box = (x, y, w, h)。"""
    x, y, w, h = pts_box
    rnd = random.Random(seed)
    for _ in range(n):
        gx, gy = x + rnd.uniform(4, w - 4), y + rnd.uniform(6, h - 2)
        g.pen(color).line([(gx - 3, gy - 6), (gx, gy)], 1.4, amp=0, density=density)
        g.pen(color).line([(gx + 3, gy - 7), (gx, gy)], 1.4, amp=0, density=density)


def hedge(ctx: Ctx, x, y, w, d=16, h=10, seed=5, walk=True):
    """矮冬青：一条青色的“方土豆”，顶上一串小圆弧，正面一截深一点。"""
    g = ctx.g
    rnd = random.Random(seed)
    shadow(g, [(x + w, y + d), (x + w + 8, y + d + 4), (x + w + 8, y + d + h + 4), (x + 4, y + d + h + 4), (x, y + d + h)], 0.15)
    g.clear(rect_pts(x, y, w, d + h))
    g.pen("qing", 0.34).fill(rect_pts(x, y, w, d))
    g.pen("qing", 0.55).fill(rect_pts(x, y + d, w, h))
    g.pen("ink", 0.16).fill(rect_pts(x, y + d, w, h))
    g.qing.rect(x, y, w, d + h, lw=1.8, amp=1.3)
    # 叶团的小弧
    step = 11
    k = x + 4
    while k < x + w - 4:
        g.ink.arc(k + rnd.uniform(-2, 2), y + d * rnd.uniform(0.35, 0.7), 4, 3.4, 6.0, lw=1.2, density=0.7)
        k += step
    if walk:
        ctx.walk.block_rect(x, y, w, d + h)


def hedge_v(ctx: Ctx, x, y, d, w=16, h=10, seed=6):
    """南北向的冬青（俯视是一条竖带，正面只在最南头露一截）。"""
    g = ctx.g
    rnd = random.Random(seed)
    shadow(g, [(x + w, y), (x + w + 8, y + 4), (x + w + 8, y + d + h + 4), (x + 4, y + d + h + 4), (x, y + d + h)], 0.15)
    g.clear(rect_pts(x, y, w, d + h))
    g.pen("qing", 0.34).fill(rect_pts(x, y, w, d))
    g.pen("qing", 0.55).fill(rect_pts(x, y + d, w, h))
    g.pen("ink", 0.16).fill(rect_pts(x, y + d, w, h))
    g.qing.rect(x, y, w, d + h, lw=1.8, amp=1.3)
    k = y + 5
    while k < y + d - 4:
        g.ink.arc(x + w * rnd.uniform(0.35, 0.65), k, 4, 3.4, 6.0, lw=1.2, density=0.7)
        k += 11
    ctx.walk.block_rect(x, y, w, d + h)


def oval_shadow(g, x, y, rx, ry, density=0.15):
    shadow(g, ellipse_pts(x, y, rx, ry), density)
