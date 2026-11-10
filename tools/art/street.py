#!/usr/bin/env python3
"""河畔里的活物：街坊、摊子、车、随年代更替的街景（孔版套色，和地图、主角一个路子）。

    python3 tools/art/street.py            →  client/art/street/atlas.png + sprites.json
    python3 tools/art/street.py --sheet x.png   另存一张带名字的总览图（检查用）

每个精灵是一小张印张：可以有几帧（横排），脚底锚点 foot 用世界像素写在 sprites.json 里。
引擎（client/scripts/world/street_life.gd）按 content/street.yaml 把它们摆到街上，按年代换。
底图里不会变的东西（茶社、桥、河）在 tools/art/hepanli/ 里画；这里只画会来、会走、会老的。
"""
from __future__ import annotations

import json
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "hepanli"))

from actors import SKIN, arc_pts, chaikin, ell, part, place, rotate, rrect, solid, tint, tube  # noqa: E402
from common import _knockout_text as _ko_abs  # noqa: E402
from riso import ROOT, Sheet, circle_pts, ellipse_pts, font_path, rect_pts  # noqa: E402
from street_fig import INK, WHITE_HAIR, fig, rider  # noqa: E402

SCALE = 2.0
OUT_DIR = os.path.join(ROOT, "client", "art", "street")
ATLAS_W = 2048

SPRITES: dict = {}


def sprite(name, w=96, h=128, foot=(48, 120), frames=1):
    def deco(fn):
        SPRITES[name] = dict(w=w, h=h, foot=foot, frames=frames, draw=fn)
        return fn
    return deco


def _abs(s, x, y):
    """当前坐标系（place 平移过的）里的一点 → 印张的世界坐标。写字的函数不认 cairo 的变换，要自己换算。"""
    dx, dy = s.plates["ink"]["solid"].user_to_device(x, y)
    return dx / s.scale + s.origin[0], dy / s.scale + s.origin[1]


def _knockout_text(s, color, text, x, y, size, vertical=False):
    ax, ay = _abs(s, x, y)
    _ko_abs(s, color, text, ax, ay, size, vertical)


def ground_shadow(s, rx=20, ry=7, dx=4, dy=2, d=0.17):
    s.pen("ink", d).fill(ellipse_pts(dx, dy, rx, ry, 28))


def person(name, spec, alt=None, w=96, h=116, foot=(48, 108), shadow=(20, 7), drop=0):
    """一个街坊：两帧（平常 / 换个动作），引擎慢慢来回切。
    drop：背对我们坐着的人看不见腿，整个人往下挪这么多，让屁股落在脚底锚点上（坐在条凳、石墩上）。"""
    @sprite(name, w, h, foot, 2 if alt else 1)
    def _draw(s, i):
        if shadow:
            ground_shadow(s, *shadow)
        d = dict(spec)
        if i == 1 and alt:
            d.update(alt)
        with place(s, 0, drop):
            fig(s, d)
    return _draw


# ======================================================================
# 街坊
# ======================================================================

# 周家 · 早点铺
person("zhou_shen",
       dict(build="middle", hair="short", hat="cook", top=tint("mei", 0.35), sleeve_len=0.55, apron=SKIN,
            arms=("hold", "front"), props=(("spatula", "r"),), eyes="happy"),
       dict(arms=("hold", "up"), mouth="open", eyes="open"))
person("zhou_son",
       dict(build="middle", hair="crew", top=tint("qing", 0.75), sleeve_len=0.55, apron=SKIN, collar="tee",
            arms=("hold", "front"), props=(("spatula", "r"),)),
       dict(arms=("hold", "up"), mouth="open"))

# 茶社里说书的
person("gu_ye",
       dict(build="old", gown=True, top=tint("ink", 0.2), collar="stand", hair="bald", hair_color=WHITE_HAIR, glasses=True,
            brows=True, arms=("down", "front"), props=(("fan", "r"),), shoes=INK),
       dict(arms=("out", "front"), mouth="open"))
person("pang",
       dict(build="fat", gown=True, top=tint("qing", 0.55), collar="stand", hair="crew", arms=("behind", "behind"), eyes="happy"),
       dict(mouth="open", eyes="open", arms=("behind", "hip")))
person("gu_xiao",
       dict(build="young", gown=True, top=tint("mei", 0.42), collar="stand", hair="short", arms=("down", "front"),
            props=(("fan_closed", "r"),)),
       dict(arms=("out", "up"), mouth="open", eyes="happy"))

# 茶社里的茶客（背对我们，冲着台上）
person("guest_a",
       dict(build="old", view="back", pose="sit", hair="short", hair_color=WHITE_HAIR, hat="cap", hat_color=tint("ink", 0.45),
            top=tint("ink", 0.42)),
       dict(arms=("up", "down")), shadow=None, drop=19, h=96, foot=(48, 92))
person("guest_b",
       dict(build="granny", view="back", pose="sit", hair="perm", hair_color=WHITE_HAIR, top=tint("mei", 0.5)),
       dict(arms=("down", "up")), shadow=None, drop=17, h=96, foot=(48, 92))

# 海河边
person("fisher",
       dict(build="old", pose="sit", hat="straw", hair="short", hair_color=WHITE_HAIR, top=SKIN, sleeve_len=0.0, collar="tee",
            pants=tint("ink", 0.36), pants_len=0.62, arms=("down", "front"), props=(("rod", "r"),), beard="mustache"),
       dict(eyes="closed"), w=120, foot=(44, 108))
person("diver",
       dict(build="fat", bare=True, pants=solid("qing"), pants_len=0.36, hem=0.0, shoes=SKIN, hair="none", hat="swim",
            hat_color=solid("mei"), arms=("hip", "hip"), eyes="happy", brows=True),
       dict(arms=("high", "high"), mouth="open"))


# 自行车铺
person("bike_ye",
       dict(build="old", pose="sit", hat="cap", hat_color=tint("ink", 0.5), hair="short", hair_color=WHITE_HAIR, beard="mustache",
            top=tint("qing", 0.6), buttons=True, pants=tint("ink", 0.4), arms=("down", "front"), props=(("wrench", "r"),)),
       dict(arms=("hold", "front"), eyes="happy"))
person("bike_tu",
       dict(build="middle", pose="sit", hair="crew", top=solid("qing"), stripe=("ink", 0.12), collar="tee", pants=tint("ink", 0.4),
            arms=("down", "front"), props=(("wrench", "r"),)),
       dict(arms=("hold", "front")))

# 小花园
person("bird_ye",
       dict(build="old", hair="bald", hair_color=WHITE_HAIR, top=SKIN, buttons=True, collar="stand", pants=tint("ink", 0.42),
            arms=("behind", "down"), props=(("cage", "r"),), brows=True),
       dict(eyes="happy", mouth="open"))
person("chess_n",
       dict(build="old", pose="sit", hair="short", hair_color=WHITE_HAIR, glasses=True, top=tint("ink", 0.28), sleeve_len=0.4,
            collar="v", arms=("hip", "front"), props=(("pufan", "r"),)),
       dict(arms=("out", "front"), mouth="open"), shadow=(18, 5))
person("chess_s",
       dict(build="fat", view="back", pose="sit", hair="crew", top=SKIN, sleeve_len=0.0),
       dict(arms=("up", "down")), shadow=None, drop=19, h=96, foot=(48, 92))

# 校门口卖糖堆儿的
person("candy",
       dict(build="granny", hair="bun", top=tint("mei", 0.5), buttons=True, collar="stand", pants=tint("ink", 0.4),
            arms=("down", "front"), props=(("tanghulu", "r"),)),
       dict(mouth="open", eyes="happy"), w=110, h=140, foot=(46, 132))

# 河边跳舞的
person("dama",
       dict(build="granny", hair="perm", top=solid("mei"), collar="tee", pants=tint("ink", 0.34), arms=("up", "out"), eyes="happy"),
       dict(arms=("out", "up"), mouth="open"))


# ======================================================================
# 道具
# ======================================================================

@sprite("stage_table", w=84, h=64, foot=(42, 58))
def _stage_table(s, i):
    """茶社台上的桌子：梅色桌围子，桌上醒木、折扇、白手绢。"""
    w, d, h = 64, 20, 26
    x, y = -w / 2, -(d + h)
    s.pen("ink", 0.17).fill([(x + w, y + 6), (x + w + 10, y + 12), (x + w + 10, y + d + h + 5), (x + 8, y + d + h + 5), (x, y + d + h)])
    part(s, rect_pts(x, y, w, d + h), solid("mei"), 2.4)
    s.clear(rect_pts(x, y, w, d))
    s.pen("paper").fill(rect_pts(x, y, w, d))
    s.pen("ink", 0.1).fill(rect_pts(x, y, w, d))
    s.ink.rect(x, y, w, d, lw=2.2)
    _knockout_text(s, "mei", "河畔", 0, y + d + h / 2 - 1, 15)
    s.clear(rect_pts(x + 3, y + d + h - 5, w - 6, 1.4), colors=("mei",))
    part(s, rrect(x + 10, y + 7, 9, 6, 1), INK, 1.0, amp=0)                     # 醒木
    s.ink.line([(x + 26, y + 13), (x + 44, y + 7)], w=3.2, amp=0)               # 折扇
    part(s, chaikin([(x + 48, y + 6), (x + 59, y + 5), (x + 60, y + 14), (x + 49, y + 15)], 1), SKIN, 1.2)  # 手绢


def _board(s, w=84, h=50, legs=16):
    """公告栏的架子：两条腿、一块板、一道小雨檐。原点在两腿之间的地面。返回板面矩形。"""
    x, y = -w / 2, -(h + legs)
    s.pen("ink", 0.16).fill([(x + 6, 0), (x + w + 4, 0), (x + w + 20, 6), (x + 22, 6)])
    for lx in (x + 8, x + w - 8):
        s.ink.line([(lx, y + h), (lx, 0)], w=3.4, amp=0.2)
    part(s, rect_pts(x, y, w, h), SKIN, 2.6)
    roof = [(x - 5, y), (x + w + 5, y), (x + w + 2, y - 7), (x - 2, y - 7)]
    part(s, roof, tint("ink", 0.5), 2.0)
    return x, y, w, h


def _text(s, color, text, x, y, size, density=1.0):
    ax, ay = _abs(s, x, y)
    s.pen(color).text(text, ax, ay, size, density=density)


def _scribble(s, x, y, w, rows, gap=6.0, seed=1, density=0.55):
    rnd = random.Random(seed)
    for r in range(rows):
        L = w * rnd.uniform(0.6, 1.0)
        s.ink.line([(x, y + r * gap), (x + L, y + r * gap)], w=1.0, amp=0.5, density=density)


@sprite("notice_child", w=110, h=84, foot=(55, 76))
def _notice_child(s, i):
    """九十年代：黑板报。粉笔字「欢迎新邻居」，角上一朵粉笔花。"""
    x, y, w, h = _board(s)
    s.ink.fill(rect_pts(x + 4, y + 4, w - 8, h - 8))
    _knockout_text(s, "ink", "黑板报", x + 26, y + 13, 9)
    _knockout_text(s, "ink", "欢迎新邻居", 0, y + 28, 11)
    for k in range(3):
        s.clear(rect_pts(x + 12, y + 37 + k * 3.5, w - 30 - k * 9, 1.0), colors=("ink",))
    cx, cy = x + w - 16, y + 14
    for a in range(5):
        aa = a * math.tau / 5
        s.clear(circle_pts(cx + 4.6 * math.cos(aa), cy + 4.6 * math.sin(aa), 2.4, 8), colors=("ink",))
        s.pen("mei").dot(cx + 4.6 * math.cos(aa), cy + 4.6 * math.sin(aa), 2.0)
    s.clear(circle_pts(cx, cy, 1.8, 8), colors=("ink",))


@sprite("notice_teen", w=110, h=84, foot=(55, 76))
def _notice_teen(s, i):
    """千禧年：迎奥运的宣传画，旁边贴着寻猫启事。"""
    x, y, w, h = _board(s)
    s.mei.fill(rect_pts(x + 4, y + 4, 46, 15))
    _knockout_text(s, "mei", "迎奥运", x + 27, y + 11.5, 11)
    for k in range(5):   # 五个环
        s.pen(("qing", "ink", "mei", "ink", "qing")[k]).circle(x + 12 + k * 7.5, y + 28 + (k % 2) * 4, 4.4, lw=1.3, amp=0)
    _text(s, "ink", "讲文明", x + 27, y + 43, 8.5, 0.9)
    px, py = x + 54, y + 6
    part(s, rotate(rect_pts(px, py, 26, 36), 3, (px, py)), SKIN, 1.2, amp=0.3)
    _text(s, "ink", "寻猫", px + 13, py + 7, 8.5)
    s.ink.ellipse(px + 13, py + 19, 6, 4.4, lw=1.2)      # 画得不太像的一只猫
    for sd in (-1, 1):
        s.ink.poly([(px + 13 + sd * 5.5, py + 16), (px + 13 + sd * 5, py + 11.5), (px + 13 + sd * 2, py + 15)], w=1.0, amp=0)
    _scribble(s, px + 4, py + 28, 18, 2, 4, seed=3)


@sprite("notice_young", w=110, h=84, foot=(55, 76))
def _notice_young(s, i):
    """一〇年代：拆迁摸底的通知，一个圈起来的「拆」；有人在旁边贴了张「不搬」。"""
    x, y, w, h = _board(s)
    part(s, rect_pts(x + 5, y + 5, 46, h - 10), SKIN, 1.2, amp=0.3)
    _text(s, "ink", "通知", x + 28, y + 12, 9)
    _scribble(s, x + 10, y + 21, 36, 4, 5, seed=5)
    s.mei.circle(x + 62, y + 23, 15, lw=2.6, amp=0.8)
    _text(s, "mei", "拆", x + 62, y + 23, 19)
    note = rotate(rect_pts(x + 50, y + 33, 28, 13), -8, (x + 64, y + 39))
    part(s, note, tint("qing", 0.3), 1.2, amp=0.3)
    with place(s, x + 64, y + 39.5, rot=-8):
        _text(s, "ink", "不搬", 0, 0, 9)


@sprite("notice_middle", w=110, h=84, foot=(55, 76))
def _notice_middle(s, i):
    """后来：喜报——列入历史风貌建筑；旁边是加装电梯的公示。"""
    x, y, w, h = _board(s)
    s.mei.fill(rect_pts(x + 4, y + 4, w - 8, 13))
    _knockout_text(s, "mei", "喜报", 0, y + 10.5, 10)
    plaque = rect_pts(x + 8, y + 22, 40, 21)
    part(s, plaque, solid("qing"), 1.4, amp=0.2)
    _knockout_text(s, "qing", "历史风貌", x + 28, y + 28.5, 7.5)
    _knockout_text(s, "qing", "建筑", x + 28, y + 37.5, 7.5)
    part(s, rect_pts(x + 54, y + 21, 24, 24), SKIN, 1.1, amp=0.3)
    _text(s, "ink", "电梯", x + 66, y + 26.5, 7.5)
    s.ink.rect(x + 61, y + 31, 10, 12, lw=1.0, amp=0)
    s.ink.line([(x + 66, y + 31), (x + 66, y + 43)], w=0.8, amp=0)


@sprite("notice_old", w=110, h=84, foot=(55, 76))
def _notice_old(s, i):
    """很多年以后：河畔里一百年，征集老照片。"""
    x, y, w, h = _board(s)
    _text(s, "mei", "河畔里", x + 27, y + 14, 12)
    _text(s, "ink", "一百年", x + 27, y + 28, 10)
    _scribble(s, x + 8, y + 37, 38, 2, 4.5, seed=9)
    for k, (px, py, rot) in enumerate(((x + 52, y + 8, -5), (x + 60, y + 24, 6))):
        ph = rotate(rect_pts(px, py, 22, 17), rot, (px + 11, py + 8))
        part(s, ph, SKIN, 1.2, amp=0.2)
        with place(s, px + 11, py + 8, rot=rot):
            s.pen("ink", 0.3).fill(rect_pts(-9, -6.5, 18, 11))
            for sd, col in ((-1, "qing"), (1, "mei")):   # 照片上两个小人
                s.pen(col).dot(sd * 3, 1.5, 2.2)
                s.ink.dot(sd * 3, -2, 1.5)


@sprite("locker", w=104, h=80, foot=(52, 74))
def _locker(s, i):
    """快递柜：盖住了当年的煤球垛。"""
    w, d, h = 88, 12, 52
    x, y = -w / 2, -(d + h)
    s.pen("ink", 0.17).fill([(x + w, y + 6), (x + w + 12, y + 12), (x + w + 12, y + d + h + 5), (x + 8, y + d + h + 5), (x, y + d + h)])
    part(s, rect_pts(x, y, w, d + h), solid("qing"), 2.4)
    s.pen("ink", 0.2).fill(rect_pts(x, y, w, d))
    s.ink.line([(x, y + d), (x + w, y + d)], w=1.6, amp=0.2)
    cols, rows = 6, 4
    cw, ch = (w - 8) / cols, (h - 8) / rows
    for c in range(cols):
        for r in range(rows):
            cx, cy = x + 4 + c * cw, y + d + 4 + r * ch
            if c == 2 and r in (1, 2):
                continue
            s.clear(rect_pts(cx + 0.8, cy + 0.8, cw - 1.6, ch - 1.6), colors=("qing",))
            s.pen("paper").fill(rect_pts(cx + 0.8, cy + 0.8, cw - 1.6, ch - 1.6))
            s.pen("qing", 0.25).fill(rect_pts(cx + 0.8, cy + 0.8, cw - 1.6, ch - 1.6))
            s.ink.dot(cx + cw - 3, cy + ch / 2, 0.7)
    sx, sy = x + 4 + 2 * cw, y + d + 4 + ch
    s.ink.fill(rect_pts(sx + 1.5, sy + 1.5, cw - 3, ch * 2 - 3))       # 屏幕
    s.clear(rect_pts(sx + 3.5, sy + 4, cw - 7, 3), colors=("ink",))


@sprite("phone_booth", w=64, h=110, foot=(28, 102))
def _phone_booth(s, i):
    """IC 卡电话亭：一根杆子顶着半个蛋壳。"""
    s.pen("ink", 0.16).fill(ellipse_pts(8, 2, 20, 6, 24))
    s.ink.line([(0, 0), (0, -62)], w=4.0, amp=0.2)
    part(s, rrect(-7, -4, 14, 5, 1.5), tint("ink", 0.4), 1.6)
    hood = chaikin([(-19, -40), (-21, -74), (-8, -92), (12, -92), (23, -74), (21, -40)], 2)
    part(s, hood, solid("mei"), 2.4)
    inner = chaikin([(-13, -40), (-14, -70), (-5, -82), (9, -82), (17, -70), (15, -40)], 2)
    s.clear(inner)
    s.pen("paper").fill(inner)
    s.pen("ink", 0.12).fill(inner)
    s.ink.poly(inner, w=1.6, amp=0.2)
    part(s, rrect(-7, -70, 16, 24, 2), tint("ink", 0.5), 1.5)             # 话机
    s.clear(rect_pts(-4, -67, 10, 5), colors=("ink",))
    for r in range(3):
        for c in range(3):
            s.clear(circle_pts(-3 + c * 4, -58 + r * 4, 1.0, 6), colors=("ink",))
    s.ink.line([(-10, -66), (-10, -50)], w=3.4, amp=0)                    # 听筒
    s.ink.line([(-10, -50), (-13, -42), (-6, -44)], w=0.9, amp=0.6)
    _knockout_text(s, "mei", "电话", 1, -86, 7)


def _bike(s, x, color, facing=1, basket=True):
    """一辆共享单车（侧面）：实心的专色车架、小轮子、车筐。x 是两轮中点，地面 y=0。"""
    r = 13
    bx, fx = x - 21 * facing, x + 21 * facing
    for wx in (bx, fx):
        part(s, circle_pts(wx, -r, r, 22), SKIN, 2.0, amp=0.2, occlude=False)
        s.ink.dot(wx, -r, 1.8)
    seat = (x - 8 * facing, -36)
    bar = (x + 15 * facing, -38)
    crank = (x, -r)
    for seg in ([(bx, -r), seat, crank, (bx, -r)], [seat, bar, crank], [bar, (fx, -r)]):
        tube(s, seg, 2.8, solid(color), 1.1, amp=0)
    s.ink.line([(seat[0] - 6, seat[1] - 2), (seat[0] + 5 * facing, seat[1] - 2)], w=3.6, amp=0)
    s.ink.line([(bar[0] - 2 * facing, bar[1] - 5), (bar[0] + 6 * facing, bar[1] - 7)], w=2.4, amp=0)
    if basket:
        part(s, rect_pts(fx - 5 if facing > 0 else fx - 8, -48, 13, 9), solid(color), 1.3, amp=0)


@sprite("shared_bikes", w=250, h=64, foot=(120, 58))
def _shared_bikes(s, i):
    """一排共享单车：青的、梅的，歪歪扭扭挤在修车铺门口。"""
    s.pen("ink", 0.15).fill(ellipse_pts(4, 2, 108, 6, 40))
    for k, col in enumerate(("qing", "mei", "qing", "qing", "mei")):
        with place(s, -86 + k * 43, 0, rot=(-3, 2, 0, 4, 14)[k]):
            _bike(s, 0, col)


@sprite("river_warn", w=52, h=100, foot=(26, 92))
def _river_warn(s, i):
    """桥头后来立的牌子：水深危险。"""
    s.pen("ink", 0.16).fill(ellipse_pts(6, 1, 14, 4, 16))
    s.ink.line([(0, 0), (0, -52)], w=3.0, amp=0.2)
    part(s, circle_pts(0, -66, 16, 28), SKIN, 2.2, amp=0.3)
    s.mei.circle(0, -66, 12.5, lw=3.0, amp=0)
    # 一个扎猛子的小人
    s.ink.line([(-5, -71), (3, -63)], w=2.6, amp=0)
    s.ink.dot(5, -60.5, 2.2)
    s.ink.line([(-5, -71), (-9, -66)], w=1.8, amp=0)
    s.mei.line([(-9, -57), (9, -75)], w=3.0, amp=0)
    part(s, rrect(-19, -48, 38, 12, 1.5), SKIN, 1.5)
    _text(s, "mei", "水深危险", 0, -42, 7.5)


# ----------------------------------------------------------------------
# 对岸：厂子和后来的楼（不是不透明的精灵，只有墨，叠在底图那排楼的剪影上）
# ----------------------------------------------------------------------

@sprite("far_factory", w=216, h=108, foot=(0, 104))
def _far_factory(s, i):
    """对岸的老厂：锯齿顶的车间、水塔、两根大烟囱，烟囱上一圈一圈的箍。"""
    # 锯齿顶车间（压在岸线上）
    x = 6
    while x < 118:
        tooth = [(x, 0), (x, -22), (x + 20, -34), (x + 20, 0)]
        part(s, tooth, tint("ink", 0.38), 1.6, amp=0.3)
        s.clear(rect_pts(x + 3, -19, 14, 2.4), colors=("ink",))
        x += 20
    part(s, rect_pts(6, -12, 112, 12), tint("ink", 0.5), 1.6, amp=0.3)
    # 厂门口一条梅色的横幅
    part(s, rect_pts(40, -11, 44, 7), solid("mei"), 1.0, amp=0)
    for k in range(5):
        s.clear(rect_pts(45 + k * 8, -8.6, 4.5, 2.2), colors=("mei",))
    # 水塔
    part(s, rect_pts(136, -40, 4, 40), INK, 0.1, amp=0)
    part(s, rect_pts(150, -40, 4, 40), INK, 0.1, amp=0)
    s.ink.line([(138, -30), (152, -10)], w=1.0, amp=0)
    s.ink.line([(152, -30), (138, -10)], w=1.0, amp=0)
    part(s, rrect(128, -62, 34, 22, 4), tint("ink", 0.45), 1.6)
    part(s, [(128, -62), (145, -72), (162, -62)], tint("ink", 0.6), 1.4)
    # 烟囱：底粗顶细，三道箍，顶上一截梅色（航标）
    for cx, top, wb in ((60, -98, 9), (100, -84, 8)):
        body = [(cx - wb, -30), (cx + wb, -30), (cx + wb * 0.56, top), (cx - wb * 0.56, top)]
        part(s, body, tint("ink", 0.3), 1.8, amp=0.3)
        with s.clip(body):
            s.pen("ink", 0.25).fill(rect_pts(cx + 1, top, wb, -top))
            s.mei.fill(rect_pts(cx - wb, top, 2 * wb, 9))
            for k in range(1, 4):
                yy = top + (-30 - top) * k / 4
                s.ink.line([(cx - wb, yy), (cx + wb, yy)], w=1.0, amp=0)
        s.ink.line([(cx - wb * 0.56, top + 9), (cx + wb * 0.56, top + 9)], w=1.0, amp=0)
    # 厂里的塔吊
    s.ink.line([(190, 0), (190, -70)], w=2.2, amp=0)
    s.ink.line([(172, -64), (212, -70)], w=1.8, amp=0)
    s.ink.line([(190, -78), (176, -64)], w=1.0, amp=0)
    s.ink.line([(190, -78), (208, -69.5)], w=1.0, amp=0)
    s.ink.line([(204, -68), (204, -52)], w=0.9, amp=0)


@sprite("far_towers", w=216, h=108, foot=(0, 104))
def _far_towers(s, i):
    """后来对岸的高楼：老厂的地卖了，起了一排玻璃幕墙的楼，青的。"""
    rnd = random.Random(12)
    for x, w, top in ((4, 26, -96), (34, 20, -70), (60, 24, -84), (90, 30, -100), (126, 18, -62), (148, 16, -88), (168, 22, -78), (192, 24, -102)):
        body = rect_pts(x, top, w, -top)
        part(s, body, tint("qing", 0.42), 1.6, amp=0.3)
        with s.clip(body):
            s.pen("ink", 0.14).fill(rect_pts(x + w * 0.55, top, w, -top))
            yy = top + 7
            while yy < 0:
                s.ink.line([(x, yy), (x + w, yy)], w=0.7, amp=0, density=0.5)
                yy += 7
            for _ in range(int(w * -top / 90)):
                s.clear(rect_pts(x + rnd.randint(0, int(w / 5) - 1) * 5 + 1, top + rnd.randint(1, int(-top / 7) - 1) * 7 + 1.5, 3.4, 4.2), colors=("qing", "ink"))
        s.ink.line([(x + w / 2, top), (x + w / 2, top - 8)], w=1.0, amp=0)
    # 还在盖的那栋：楼顶一台塔吊
    s.ink.line([(105, -100), (105, -106)], w=1.6, amp=0)
    s.ink.line([(92, -104), (132, -106)], w=1.4, amp=0)
    s.ink.line([(126, -105.6), (126, -96)], w=0.8, amp=0)


# ======================================================================
# 车
# ======================================================================

def _wheel(s, x, r=12):
    part(s, circle_pts(x, -r, r, 24), INK, 0.1, amp=0)
    s.clear(circle_pts(x, -r, r * 0.46, 14), colors=("ink",))
    s.pen("paper").fill(circle_pts(x, -r, r * 0.46, 14))
    s.ink.dot(x, -r, 1.6)


@sprite("dafa", w=196, h=104, foot=(98, 94))
def _dafa(s, i):
    """黄大发：九十年代满街跑的小面包出租车（朝右）。纸上没有黄，车身留白压一层很淡的墨，腰上一圈梅色的格子。"""
    s.pen("ink", 0.2).fill(ellipse_pts(4, 1, 84, 8, 40))
    body = chaikin([(-80, -10), (-80, -66), (-72, -76), (50, -76), (72, -48), (82, -42), (82, -10)], 2)
    part(s, body, tint("ink", 0.07), 2.8)
    with s.clip(body):
        k = -84
        j = 0
        while k < 84:                       # 腰线：出租车的格子
            if j % 2 == 0:
                s.mei.fill(rect_pts(k, -38, 7, 6))
            k += 7
            j += 1
        s.ink.line([(-84, -38), (84, -38)], w=1.0, amp=0)
        s.ink.line([(-84, -32), (84, -32)], w=1.0, amp=0)
        s.pen("ink", 0.3).fill(rect_pts(-84, -16, 170, 8))
    for x0, x1 in ((-70, -42), (-36, -8), (0, 34)):
        win = rrect(x0, -70, x1 - x0, 24, 3)
        part(s, win, tint("qing", 0.4), 1.8, amp=0.2)
    ws = [(40, -70), (50, -70), (66, -47), (40, -47)]
    part(s, chaikin(ws, 1), tint("qing", 0.4), 1.8, amp=0.2)
    # 司机
    s.ink.dot(48, -57, 5.2)
    s.ink.line([(-2, -74), (-2, -16)], w=1.2, amp=0)
    s.ink.line([(37, -74), (37, -16)], w=1.2, amp=0)
    s.ink.line([(-30, -28), (-24, -28)], w=2.0, amp=0)
    part(s, rrect(74, -36, 8, 8, 2), SKIN, 1.4)                    # 大灯
    part(s, rrect(-82, -34, 5, 10, 1.5), solid("mei"), 1.2)        # 尾灯
    part(s, rrect(-10, -86, 30, 10, 2), SKIN, 1.6)                 # 顶灯
    _text(s, "mei", "出租", 5, -81, 8)
    _wheel(s, -50)
    _wheel(s, 50)


@sprite("xiali", w=204, h=92, foot=(102, 82))
def _xiali(s, i):
    """红夏利：千禧年前后的出租车（朝右）。"""
    s.pen("ink", 0.2).fill(ellipse_pts(4, 1, 90, 8, 40))
    body = chaikin([(-88, -10), (-88, -34), (-64, -40), (-46, -62), (20, -62), (42, -40), (78, -36), (88, -28), (88, -10)], 2)
    part(s, body, solid("mei"), 2.8)
    with s.clip(body):
        s.pen("ink", 0.3).fill(rect_pts(-90, -17, 180, 9))
        s.clear(rect_pts(-90, -30, 180, 2.2), colors=("mei",))
    for pts in ([(-58, -40), (-43, -58), (-16, -58), (-16, -40)], [(-11, -58), (17, -58), (35, -40), (-11, -40)]):
        w = chaikin(pts, 1)
        s.clear(w)
        s.pen("paper").fill(w)
        s.pen("qing", 0.4).fill(w)
        s.ink.poly(w, w=1.8, amp=0.2)
    s.ink.dot(8, -49, 5.0)
    s.ink.line([(-13, -60), (-13, -14)], w=1.2, amp=0)
    s.ink.line([(38, -38), (38, -14)], w=1.2, amp=0)
    part(s, rrect(80, -34, 8, 7, 2), SKIN, 1.4)
    part(s, rrect(-12, -72, 26, 10, 2), SKIN, 1.6)
    _text(s, "mei", "TAXI", 1, -67, 7.5)
    _wheel(s, -52, 11.5)
    _wheel(s, 52, 11.5)


def _cycle(s, color="ink", phase=0, r=17):
    """一辆二八（朝右），返回 (车座, 车把, 近脚蹬, 远脚蹬)。"""
    bx, fx = -28, 28
    for wx in (bx, fx):
        part(s, circle_pts(wx, -r, r, 26), SKIN, 2.2, amp=0.2, occlude=False)
        s.ink.dot(wx, -r, 2.0)
        for a in range(4):
            aa = a * math.pi / 4 + phase * 0.4
            s.ink.line([(wx - (r - 2) * math.cos(aa), -r - (r - 2) * math.sin(aa)), (wx + (r - 2) * math.cos(aa), -r + (r - 2) * math.sin(aa))], w=0.6, amp=0, density=0.6)
    seat, bar, crank = (-10, -45), (18, -47), (0, -r)
    for seg in ([(bx, -r), seat, crank, (bx, -r)], [seat, bar, crank], [bar, (fx, -r)]):
        if color != "ink":
            tube(s, seg, 2.6, solid(color), 1.0, amp=0)
        else:
            s.ink.line(seg, w=2.6, amp=0)
    s.ink.line([(seat[0] - 8, seat[1] - 3), (seat[0] + 6, seat[1] - 3)], w=4, amp=0)
    s.ink.line([(bar[0] - 2, bar[1] - 6), (bar[0] + 8, bar[1] - 8)], w=2.6, amp=0)
    a = phase * math.pi / 2
    near = (crank[0] + 8 * math.cos(a), crank[1] + 8 * math.sin(a))
    far = (crank[0] - 8 * math.cos(a), crank[1] - 8 * math.sin(a))
    s.ink.line([far, near], w=1.6, amp=0)
    return (seat[0], seat[1] - 5), (bar[0] + 5, bar[1] - 8), near, far


def cyclist(name, color, **kw):
    box = kw.pop("rack", None)

    @sprite(name, w=116, h=112, foot=(58, 104), frames=2)
    def _draw(s, i):
        s.pen("ink", 0.17).fill(ellipse_pts(4, 1, 48, 6, 30))
        seat, bar, near, far = _cycle(s, color, i)
        if box == "lunch":      # 后衣架上夹着的铝饭盒
            part(s, rrect(-40, -50, 20, 10, 2), tint("ink", 0.12), 1.4)
            s.ink.line([(-40, -45), (-20, -45)], w=0.8, amp=0)
        rider(s, seat, bar, near, far, **kw)


# 下班的工人：劳动布工作服、前进帽，后衣架上夹着饭盒
cyclist("rider_worker", "ink", top=tint("qing", 0.6), hat="cap", hat_color=tint("ink", 0.5), rack="lunch")
cyclist("rider_lady", "ink", top=tint("mei", 0.55), pants=tint("ink", 0.3))
cyclist("rider_share", "qing", top=SKIN, pants=tint("ink", 0.36))


@sprite("waimai", w=124, h=108, foot=(62, 100))
def _waimai(s, i):
    """送外卖的电动车（朝右）：头盔、后座一个大箱子。"""
    s.pen("ink", 0.18).fill(ellipse_pts(2, 1, 50, 6, 30))
    for wx in (-30, 32):
        _wheel(s, wx, 10)
    deck = chaikin([(-40, -16), (-38, -30), (-8, -32), (-2, -14), (20, -14), (26, -40), (34, -40), (36, -12), (-36, -10)], 2)
    part(s, deck, tint("ink", 0.5), 2.4)
    s.ink.line([(28, -40), (22, -56)], w=3.0, amp=0)
    s.ink.line([(16, -57), (28, -55)], w=3.0, amp=0)
    part(s, rrect(30, -36, 7, 7, 2), SKIN, 1.3)
    rider(s, (-14, -36), (22, -56), (6, -15), (2, -15), top=solid("qing"), hat="helmet", hat_color=solid("qing"), box=solid("qing"))


# ======================================================================
# 出图
# ======================================================================

def render(name):
    sp = SPRITES[name]
    s = Sheet(sp["w"] * sp["frames"], sp["h"], scale=SCALE, seed=11)
    for i in range(sp["frames"]):
        s._seed = 1000 + sum(map(ord, name))     # 每帧同一套抖动：换帧时线条不"沸腾"
        frame = rect_pts(i * sp["w"], 0, sp["w"], sp["h"])
        with s.clip(frame):
            with place(s, i * sp["w"] + sp["foot"][0], sp["foot"][1]):
                sp["draw"](s, i)
    rgb = s.composite(True, True)
    a = np.clip(s.alpha() * 255.0 + 0.5, 0, 255).astype(np.uint8)
    return np.dstack([rgb, a])


def pack(images):
    """按高度排架子，塞进一张不超过 2048 宽的图集。"""
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
    atlas[..., :3] = (0xF4, 0xEE, 0xE1)
    for n, (px, py) in pos.items():
        h, w = images[n].shape[:2]
        atlas[py:py + h, px:px + w] = images[n]
    return atlas, pos


def contact_sheet(images, path):
    """带名字的总览图。"""
    names = list(images)
    f = ImageFont.truetype(font_path(), 22)
    cols = 5
    cw = max(im.shape[1] for im in images.values()) + 20
    ch = max(im.shape[0] for im in images.values()) + 44
    rows = math.ceil(len(names) / cols)
    out = Image.new("RGB", (cols * cw, rows * ch), (0xF4, 0xEE, 0xE1))
    d = ImageDraw.Draw(out)
    for k, n in enumerate(names):
        im = Image.fromarray(images[n], "RGBA")
        ox, oy = (k % cols) * cw + 10, (k // cols) * ch + 34
        out.paste(im, (ox, oy), im)
        d.text((ox, oy - 28), n, font=f, fill=(0x2B, 0x2A, 0x33))
    out.save(path)


def main(argv):
    only = [a for a in argv if a in SPRITES]
    names = only or list(SPRITES)
    images = {n: render(n) for n in names}
    if "--sheet" in argv:
        path = argv[argv.index("--sheet") + 1]
        contact_sheet(images, path)
        print("总览：", path)
        if only:
            return
    atlas, pos = pack(images)
    os.makedirs(OUT_DIR, exist_ok=True)
    if atlas.shape[0] > 2048:
        print(f"⚠ 图集高 {atlas.shape[0]}，超过 2048：低端机可能加载不了，拆成两张或删几个精灵")
    Image.fromarray(atlas, "RGBA").save(os.path.join(OUT_DIR, "atlas.png"), optimize=True)
    meta = {"scale": SCALE, "sprites": {}}
    for n in names:
        sp = SPRITES[n]
        meta["sprites"][n] = {"x": pos[n][0], "y": pos[n][1], "w": sp["w"], "h": sp["h"], "frames": sp["frames"], "foot": list(sp["foot"])}
    with open(os.path.join(OUT_DIR, "sprites.json"), "w", encoding="utf-8") as fp:
        json.dump(meta, fp, ensure_ascii=False, indent=1)
    size = os.path.getsize(os.path.join(OUT_DIR, "atlas.png"))
    print(f"✓ {len(names)} 个精灵 → {os.path.relpath(OUT_DIR, ROOT)}/atlas.png（{atlas.shape[1]}×{atlas.shape[0]}，{size / 1e6:.1f} MB）")


if __name__ == "__main__":
    main(sys.argv[1:])
