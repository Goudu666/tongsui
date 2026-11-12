#!/usr/bin/env python3
"""《同岁》横版街坊：每张图上的街坊各干各的营生，路上还有来来往往的人。和主角同一副骨架（actors.py）、同一台孔版机。

    python3 tools/art/folks.py               →  client/art/folks/<图>.png、walkers.png、index.json
    python3 tools/art/folks.py --preview X   →  所有图集拼一张，调手感用

谁在哪张图、哪个年纪在、几点在、搭腔说什么，写在 content/maps/<图>.yaml 的 npcs（npm run content → client/data/folks.json）；
这里只管长相和动作：FOLKS 按街坊 id 写一个人的样子和他的营生。
  <图>.png：一个街坊一行，列 0~3 干活的一圈（营生），列 4~7 歇着（站或坐着喘气、眨眼）
  walkers.png：一种路人一行，8 帧走路（一整步）
每格 200×220 世界像素，脚底 (100, 206)，1.25 倍输出；人朝右，朝左由引擎翻转。
街坊用浅一档的网点和墨，不用主角那种青、梅实地：一眼分得出谁是玩家。
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import actor_acts as A  # noqa: E402
from actors import CELL_H, CELL_W, FOOT, ROOT, Painter, Sheet, build, chaikin, draw_person, ell, pose_stand, pose_walk, save_rgba_small  # noqa: E402

SCALE = 1.25
OUT_DIR = os.path.join(ROOT, "client", "art", "folks")
FOLKS_JSON = os.path.join(ROOT, "client", "data", "folks.json")


# ----------------------------------------------------------------------
# 长相
# ----------------------------------------------------------------------

def look(male, stage, shirt, pants=("ink", 0.6, "flat"), coat=None, cardigan=None, long_coat=False, hat=None, apron=None,
         glasses=None, cane=False, belly=0.0, hair=None, prop="ink", lean=None, shoes=("ink", None)):
    b = build("qing" if male else "mei", stage)
    b.update(role=prop, male=male, tuft=False, shine=False, shirt=shirt, pants=pants, coat=coat, cardigan=cardigan, long_coat=long_coat,
             skirt=False, stripes=False, stripe=False, bag=False, collar=("paper",), cane=cane, belly=belly, shoes=shoes)
    if glasses is not None:
        b["glasses"] = glasses
    if hair:
        b["hair"] = hair
    if lean is not None:
        b["lean"] = lean
    b["hat"] = hat
    b["apron"] = apron
    return b


def dress(p, layer, J):
    """帽子、围裙：套在骨架上（hook 的 body / front 层）。"""
    b = J["b"]
    hx, hy, r = J["head"]
    if layer == "front" and b.get("hat"):
        kind, spec = b["hat"]
        if kind == "cap":  # 前进帽 / 工作帽：一顶扣在头上，帽檐朝前
            p.shape(chaikin([(hx - r * 1.08, hy - r * 0.3), (hx - r * 0.9, hy - r * 1.05), (hx + r * 0.2, hy - r * 1.22), (hx + r * 0.95, hy - r * 0.7),
                             (hx + r * 1.0, hy - r * 0.42)], 1), spec, line=1.6)
            p.shape([(hx + r * 0.6, hy - r * 0.52), (hx + r * 1.55, hy - r * 0.42), (hx + r * 1.5, hy - r * 0.3), (hx + r * 0.6, hy - r * 0.36)], spec, line=1.4)
        elif kind == "helmet":  # 安全帽
            p.shape(ell(hx, hy - r * 0.45, r * 1.12, r * 0.78, 24)[12:] + [(hx + r * 1.4, hy - r * 0.42), (hx - r * 1.2, hy - r * 0.42)], spec, line=1.6)
        elif kind == "nurse":  # 护士帽：一小块白
            p.shape([(hx - r * 0.7, hy - r * 0.95), (hx + r * 0.5, hy - r * 1.1), (hx + r * 0.55, hy - r * 1.45), (hx - r * 0.65, hy - r * 1.35)], ("paper",), line=1.4)
            p.line([(hx - r * 0.1, hy - r * 1.32), (hx - r * 0.1, hy - r * 1.12)], 1.6, "mei", None)
    if layer == "body" and b.get("apron"):
        sh, hip = J["shoulder"], J["hip"]
        w = b["waist"]
        top = (sh[0] + w * 0.38, sh[1] + 10)
        pts = [(top[0] - 3, top[1]), (top[0] + 5, top[1] + 2), (hip[0] + w * 0.62, hip[1] + b["thigh"] * 0.55), (hip[0] + w * 0.05, hip[1] + b["thigh"] * 0.6)]
        p.shape(pts, b["apron"], line=1.5)


def _hooked(fn, b, k):
    """一套动作加上帽子围裙：把两个 hook 串起来。"""
    d = fn(b, k)
    inner = d.get("hook")

    def hook(p, layer, J):
        if inner:
            inner(p, layer, J)
        dress(p, layer, J)
    d["hook"] = hook
    return d


# ----------------------------------------------------------------------
# 街坊才有的营生
# ----------------------------------------------------------------------

def act_fan(b, k):
    """坐着摇蒲扇。"""
    s = math.sin(k * math.tau)
    nr = (0.5, -0.12 + 0.12 * s)

    def hook(p, layer, J):
        if layer == "front":
            h = J["hand_near"]
            a = math.radians(-60 + 30 * s)
            c = (h[0] + 12 * math.cos(a), h[1] + 12 * math.sin(a))
            p.line([h, c], 1.6)
            p.shape(ell(c[0] + 6 * math.cos(a), c[1] + 6 * math.sin(a), 9, 11, 16), ("ink", 0.25), line=1.4)
    return dict(pose=A.pose(b, A.sit_legs(b), A.arms(nr, (0.45, 0.6)), lean=2, tilt=-2), sit=True, expr="bliss" if k < 0.5 else None, hook=hook)


def act_knit(b, k):
    """坐着织毛衣：两根针一戳一戳，线团在脚边。"""
    s = math.sin(k * math.tau * 2)
    nr, fr = (0.55, 0.45 - 0.04 * s), (0.5, 0.48 + 0.04 * s)

    def hook(p, layer, J):
        if layer == "front":
            h1, h2 = J["hand_near"], J.get("hand_far", J["hand_near"])
            p.line([(h1[0] - 2, h1[1] + 2), (h1[0] + 12, h1[1] - 10)], 1.4)
            p.line([(h2[0] - 2, h2[1] + 2), (h2[0] + 14, h2[1] - 6)], 1.4)
            p.shape(chaikin([(h2[0] - 2, h2[1] + 3), (h1[0] + 6, h1[1] + 2), (h1[0] + 4, h1[1] + 12), (h2[0] - 4, h2[1] + 10)], 1), (b["role"], 0.5), line=1.3)
            p.shape(ell(38, -7, 7, 7, 14), (b["role"], 0.45), line=1.3)
    return dict(pose=A.pose(b, A.sit_legs(b), A.arms(nr, fr), lean=6, tilt=14), sit=True, expr="focus" if k != 0.75 else "bliss", hook=hook)


def act_call(b, k):
    """吆喝：手拢在嘴边，仰着脸喊一嗓子。"""
    loud = k in (0.25, 0.5)

    def hook(p, layer, J):
        if layer == "front" and loud:
            hx, hy, r = J["head"]
            for i in range(3):
                a = math.radians(-30 + i * 25)
                p.line([(hx + r * 1.6 + 6 * math.cos(a), hy + 6 * math.sin(a)), (hx + r * 1.6 + 13 * math.cos(a), hy + 13 * math.sin(a))], 1.4)
    return dict(pose=A.pose(b, A.stand_legs(b), A.arms((0.42, -0.22) if loud else (0.3, 0.5), (0.08, 0.9)), lean=-2 if loud else 2, tilt=-12 if loud else 0),
                expr="open" if loud else None, hook=hook)


def act_snip(b, k):
    """剃头的：剪子一开一合。"""
    s = math.sin(k * math.tau * 2)

    def hook(p, layer, J):
        if layer == "front":
            h = J["hand_near"]
            o = 0.35 + 0.25 * s
            for sgn in (1, -1):
                a = -0.3 + sgn * o
                p.line([h, (h[0] + 14 * math.cos(a), h[1] + 14 * math.sin(a))], 1.6)
            p.line([(h[0] - 4, h[1] + 3), h], 2.0, "mei", None)
    return dict(pose=A.pose(b, A.stand_legs(b), A.arms((0.72, -0.05 + 0.03 * s), (0.6, 0.1)), lean=6, tilt=10), expr="focus", hook=hook)


def act_camera(b, k):
    """拍照的：相机端到眼前，咔嚓一下闪一闪。"""

    def hook(p, layer, J):
        if layer == "front":
            h = J["hand_near"]
            p.shape([(h[0] - 10, h[1] - 9), (h[0] + 6, h[1] - 9), (h[0] + 6, h[1] + 3), (h[0] - 10, h[1] + 3)], ("ink", 0.7, "flat"), line=1.5)
            p.shape(ell(h[0] + 8, h[1] - 3, 4, 5, 12), ("paper",), line=1.3)
            if k == 0.5:
                A.sparkle(p, h[0] + 16, h[1] - 14, 7)
    return dict(pose=A.pose(b, A.stand_legs(b, (10, 12), (-6, 4)), A.arms((0.4, -0.12), (0.34, -0.08)), lean=4, tilt=0), expr="focus" if k != 0.5 else "happy", hook=hook)


def act_flyer(b, k):
    """发传单：一张一张往外递，点个头。"""
    out = k in (0.25, 0.5)

    def hook(p, layer, J):
        if layer == "front":
            h = J["hand_near"]
            p.shape([(h[0] - 1, h[1] - 9), (h[0] + 11, h[1] - 10), (h[0] + 12, h[1] + 4), (h[0], h[1] + 5)], ("paper",), line=1.3)
            p.line([(h[0] + 2, h[1] - 4), (h[0] + 9, h[1] - 5)], 1.2, "mei", None)
            f = J.get("hand_far")
            if f:
                p.shape([(f[0] - 4, f[1] - 10), (f[0] + 8, f[1] - 10), (f[0] + 8, f[1] + 6), (f[0] - 4, f[1] + 6)], ("mei", 0.45), line=1.3)
    return dict(pose=A.pose(b, A.stand_legs(b), A.arms((0.78, 0.18) if out else (0.5, 0.4), (0.45, 0.42)), lean=10 if out else 2, tilt=12 if out else 0),
                expr="happy", hook=hook)


def act_conduct(b, k):
    """指挥：指挥棒一上一下打拍子。"""
    up = {0.0: -0.7, 0.25: -0.2, 0.5: 0.15, 0.75: -0.35}[k]

    def hook(p, layer, J):
        if layer == "front":
            h = J["hand_near"]
            p.line([h, (h[0] + 12, h[1] - 12)], 1.4)
    return dict(pose=A.pose(b, A.stand_legs(b), A.arms((0.62, up), (0.55, -0.35 - up * 0.4)), lean=-2, tilt=-6, no_cane=True),
                expr="sing" if k in (0.0, 0.25) else "bliss", hook=hook)


def act_stamp(b, k):
    """柜台后头盖戳：抬手、啪、再抬。"""
    y = {0.0: 0.3, 0.25: 0.12, 0.5: 0.5, 0.75: 0.4}[k]

    def hook(p, layer, J):
        if layer == "front":
            h = J["hand_near"]
            p.shape([(h[0] - 3, h[1] - 6), (h[0] + 3, h[1] - 6), (h[0] + 4, h[1] + 4), (h[0] - 4, h[1] + 4)], ("ink", 0.6), line=1.3)
            if k == 0.5:
                p.shape([(h[0] - 6, h[1] + 5), (h[0] + 6, h[1] + 5), (h[0] + 6, h[1] + 7), (h[0] - 6, h[1] + 7)], ("mei", None), line=0.8)
    return dict(pose=A.pose(b, A.sit_legs(b), A.arms((0.72, y), (0.55, 0.48)), lean=6, tilt=10), sit=True, expr="focus", hook=hook)


def act_sweep(b, k):
    """扫地：大扫帚左右一划。"""
    s = math.sin(k * math.tau)

    def hook(p, layer, J):
        if layer == "front":
            h = J["hand_near"]
            tip = (56 + 18 * s, -2)
            p.line([(h[0] - 12, h[1] - 14), tip], 2.2)
            p.shape([(tip[0] - 10, tip[1] - 9), (tip[0] + 6, tip[1] - 10), (tip[0] + 12, tip[1] + 1), (tip[0] - 14, tip[1] + 1)], ("ink", 0.5), line=1.3)
    return dict(pose=A.pose(b, A.stand_legs(b, (10, 12), (-6, 6)), A.arms((0.55, 0.42), (0.35, 0.3)), lean=12, tilt=10, no_cane=True), expr=None, hook=hook)


def act_dog(b, k):
    """遛狗：牵着绳子站着，小狗在前头嗅来嗅去、摇尾巴。"""
    s = math.sin(k * math.tau)

    def hook(p, layer, J):
        if layer != "front":
            return
        h = J["hand_near"]
        dx, dy = 66 + 6 * s, 0
        # 小狗：一个圆身子、一个脑袋、四条小腿、一根翘着的尾巴
        p.line([(dx - 12, -15), (dx - 20, -24 - 4 * math.sin(k * math.tau * 2))], 2.2)
        for x in (-9, -4, 6, 10):
            p.line([(dx + x, -10), (dx + x + (1.5 if x > 0 else -1.5) * s, -1)], 2.4)
        p.shape(ell(dx, -15, 14, 7.5, 18), ("paper",), line=1.6)
        p.blot(ell(dx - 4, -17, 5, 3.5, 10), "ink", 0.5)
        hd = (dx + 14, -22 + 3 * (k == 0.5))
        p.shape(ell(hd[0], hd[1], 6.5, 5.5, 14), ("paper",), line=1.5)
        p.shape([(hd[0] - 3, hd[1] - 4), (hd[0] - 6, hd[1] + 3), (hd[0] - 1, hd[1] + 1)], ("ink", 0.7), line=1.0)
        p.dot(hd[0] + 3, hd[1] - 1, 1.1)
        p.line([h, ((h[0] + dx) / 2, h[1] * 0.4 - 6), (dx + 6, -18)], 0.9, "mei", None)
    return dict(pose=A.pose(b, A.stand_legs(b), A.arms((0.5, 0.5), (0.08, 0.9)), lean=3, tilt=8, no_cane=True), expr="happy" if k != 0.75 else "blink", hook=hook)


def act_stroller(b, k):
    """推婴儿车：两手扶着把，车一前一后地晃，嘴里哼着。"""
    s = math.sin(k * math.tau)

    def hook(p, layer, J):
        if layer != "front":
            return
        h = J["hand_near"]
        x0 = h[0] + 6
        p.line([h, (x0 + 4, -40)], 2.0)
        body = [(x0 + 2, -44), (x0 + 50, -44), (x0 + 52, -26), (x0 + 6, -24)]
        p.shape(body, ("qing", 0.4), line=1.6)
        p.shape(chaikin([(x0 + 26, -44), (x0 + 30, -66), (x0 + 52, -62), (x0 + 52, -44)], 1), ("paper",), line=1.5)
        for wx in (x0 + 12, x0 + 44):
            p.shape(ell(wx, -8, 7, 7, 14), ("paper",), line=1.6)
    return dict(pose=A.pose(b, A.stand_legs(b, (8 + 4 * s, 8), (-6 + 4 * s, 4)), A.arms((0.62, 0.32), (0.55, 0.3)), lean=8 + 2 * s, tilt=10, no_cane=True),
                expr="bliss" if k < 0.5 else "happy", hook=hook)


def act_steam(b, k):
    """烤山芋：守着炉子，吆喝一声，炉口冒热气。"""
    d = act_call(b, k)
    inner = d["hook"]

    def hook(p, layer, J):
        inner(p, layer, J)
        if layer == "back":
            x = 48
            p.shape([(x - 18, -62), (x + 18, -62), (x + 16, -2), (x - 16, -2)], ("ink", 0.55), line=1.8)
            p.shape(ell(x, -62, 18, 4, 16), ("ink", 0.8, "flat"), line=1.5)
            p.line([(x - 18, -40), (x + 18, -40)], 1.4, "mei", None)
            A.steam(p, x, -68, k, 3, 30)
    d["hook"] = hook
    return d


# ----------------------------------------------------------------------
# 歇着：站着或坐着，喘气，最后一帧眨眼
# ----------------------------------------------------------------------

def idle(b, k, sit=False):
    br = math.sin(k * math.tau)
    if sit:
        return dict(pose=A.pose(b, A.sit_legs(b, br * 0.4), A.arms((0.45, 0.6), (0.38, 0.62)), lean=3 + br * 0.6), sit=True,
                    expr="blink" if k == 0.75 else None)
    d = dict(pose=pose_stand(b, br), expr="blink" if k == 0.75 else None)
    return d


# ----------------------------------------------------------------------
# 每位街坊：长相 + 营生 + 歇着坐不坐 + 干活时头顶冒什么
# ----------------------------------------------------------------------

M, F = True, False
CAP = ("cap", ("ink", 0.62, "flat"))
CAP_Q = ("cap", ("qing", 0.5))
WHITE = ("paper",)
APRON = ("ink", 0.18)

FOLKS = {
    # 楼下
    "shop_ayi": (look(F, "middle", ("paper",), cardigan=("mei", 0.4), prop="mei"), act_knit, True, ["dots", "heart"]),
    "shop_clerk": (look(M, "young", ("qing", 0.4), coat=("ink", 0.45), prop="qing"), A.act_talk, False, ["talk", "note"]),
    "grinder": (look(M, "middle", ("ink", 0.3), coat=("ink", 0.55), hat=CAP, apron=APRON), act_call, False, ["talk"]),
    "barber": (look(M, "middle", WHITE, long_coat=True, coat=WHITE, glasses=True), act_snip, False, ["dots", "note"]),
    # 河对岸
    "piano_teacher": (look(F, "young", WHITE, long_coat=True, coat=("mei", 0.35), prop="mei"), A.act_talk, False, ["note"]),
    "bath_uncle": (look(M, "middle", WHITE, belly=0.25, apron=("ink", 0.4)), A.act_carry, False, ["sweat"]),
    "site_worker": (look(M, "young", ("ink", 0.45), hat=("helmet", ("qing", 0.55))), A.act_carry, False, ["sweat"]),
    "greeter": (look(F, "young", ("mei", 0.45), prop="mei"), act_flyer, False, ["talk", "heart"]),
    "clerk": (look(F, "young", WHITE, cardigan=("qing", 0.35), glasses=True, prop="qing"), A.act_read, True, ["dots"]),
    "guard_office": (look(M, "middle", ("ink", 0.3), coat=("ink", 0.7, "flat"), hat=CAP), A.act_gaze, False, ["dots"]),
    # 外地
    "dorm_ayi": (look(F, "middle", WHITE, cardigan=("qing", 0.35), prop="qing"), act_knit, True, ["dots", "zzz"]),
    "stall_owner": (look(M, "young", ("ink", 0.3), apron=APRON, prop="mei"), A.act_cook, False, ["steam", "talk"]),
    "coworker": (look(M, "young", WHITE, coat=("ink", 0.55, "flat"), glasses=True), A.act_type, True, ["dots", "sweat"]),
    "postal": (look(F, "young", WHITE, coat=("qing", 0.5), prop="qing"), act_stamp, True, ["dots"]),
    # 楼里
    "er_nainai": (look(F, "old", ("mei", 0.3), cardigan=("mei", 0.4), prop="mei"), act_fan, True, ["dots", "heart"]),
    "coal": (look(M, "middle", ("ink", 0.5), coat=("ink", 0.6, "flat"), hat=CAP), A.act_carry, False, ["sweat"]),
    "junk": (look(M, "middle", ("ink", 0.3), coat=("qing", 0.35), hat=CAP_Q), act_call, False, ["talk"]),
    "silou": (look(M, "young", WHITE, coat=("ink", 0.4)), A.act_read, False, ["dots"]),
    # 医院
    "nurse": (look(F, "young", WHITE, long_coat=True, coat=WHITE, hat=("nurse", None), prop="mei"), A.act_read, False, ["dots"]),
    "porter": (look(M, "middle", WHITE, coat=("qing", 0.4)), A.act_carry, False, ["sweat"]),
    "queue_old": (look(M, "old", ("ink", 0.3), coat=("ink", 0.5), cane=True, hat=CAP), A.act_gaze, False, ["dots", "zzz"]),
    # 中学
    "shed_ayi": (look(F, "middle", ("qing", 0.3), apron=("ink", 0.25), prop="qing"), act_knit, True, ["dots"]),
    "stationery": (look(M, "middle", WHITE, cardigan=("ink", 0.4), glasses=True), A.act_read, True, ["dots"]),
    "dean": (look(M, "middle", WHITE, coat=("ink", 0.72, "flat"), glasses=True, lean=1.0), A.act_gaze, False, ["bang", "dots"]),
    # 新楼
    "property": (look(M, "young", ("qing", 0.55), hat=CAP_Q, prop="qing"), act_sweep, False, ["dots"]),
    "next_door": (look(F, "middle", ("mei", 0.35), cardigan=("ink", 0.3), prop="mei"), A.act_talk, False, ["talk"]),
    "dog_walker": (look(F, "middle", WHITE, coat=("qing", 0.4)), act_dog, False, ["heart", "note"]),
    # 公园
    "conductor": (look(M, "old", WHITE, coat=("ink", 0.55, "flat"), hair="grey"), act_conduct, False, ["note"]),
    "writer": (look(M, "old", ("ink", 0.2), hat=CAP), A.act_brush, False, ["dots"]),
    "stroller": (look(F, "old", ("mei", 0.3), cardigan=("ink", 0.35), prop="mei"), act_stroller, False, ["heart", "note"]),
    "kite_old": (look(M, "old", ("qing", 0.3), coat=("ink", 0.4), hat=CAP), A.act_kite, False, ["note"]),
    # 小学
    "guard": (look(M, "old", ("ink", 0.3), coat=("ink", 0.6, "flat"), hat=CAP), A.act_read, True, ["dots", "zzz"]),
    "teacher": (look(F, "young", WHITE, cardigan=("mei", 0.4), glasses=True, prop="mei"), A.act_chalk, False, ["dots"]),
    "grandparents": (look(F, "old", ("mei", 0.25), cardigan=("ink", 0.35)), A.act_gaze, False, ["dots"]),
    # 出租屋
    "landlord": (look(F, "middle", ("mei", 0.3), belly=0.15, prop="mei"), act_fan, True, ["dots"]),
    "neighbor_rent": (look(M, "young", WHITE, coat=("ink", 0.35)), A.act_eat, True, ["steam"]),
    # 海河边
    "yam": (look(M, "middle", ("ink", 0.4), coat=("ink", 0.55), hat=CAP, apron=APRON), act_steam, False, ["talk", "steam"]),
    "photog": (look(M, "young", WHITE, coat=("qing", 0.45)), act_camera, False, ["spark"]),
    "runner": (look(F, "middle", ("mei", 0.4), pants=("ink", 0.7, "flat"), prop="mei"), A.act_exercise, False, ["sweat"]),
    # 早市（清贫人家的世界）：天不亮就出摊，穿得厚、旧，围裙、套袖
    "soy_seller": (look(F, "middle", ("ink", 0.3), cardigan=("ink", 0.4), apron=WHITE, prop="ink"), A.act_cook, False, ["steam", "talk"]),
    "veg_seller": (look(M, "middle", ("ink", 0.35), coat=("ink", 0.5), hat=CAP, apron=APRON), act_call, False, ["talk"]),
    "wholesale_boss": (look(M, "middle", ("ink", 0.3), coat=("ink", 0.62, "flat"), belly=0.3), A.act_talk, False, ["talk", "dots"]),
    "scrap_buyer": (look(M, "middle", ("ink", 0.4), coat=("qing", 0.3), hat=CAP), A.act_carry, False, ["sweat"]),
    # 海边（殷实人家的夏天）：短袖、凉帽，晒黑了的救生员
    "shell_seller": (look(F, "middle", ("mei", 0.3), hat=("cap", ("paper",)), apron=("qing", 0.3), prop="mei"), A.act_talk, False, ["talk", "note"]),
    "lifeguard": (look(M, "young", ("mei", 0.6), pants=("qing", 0.6, "flat"), hat=CAP_Q), A.act_gaze, False, ["bang", "dots"]),
    "angler": (look(M, "old", WHITE, coat=("qing", 0.3), hat=("cap", ("paper",))), A.act_fish, False, ["dots", "zzz"]),
    "inn_clerk": (look(F, "young", WHITE, cardigan=("qing", 0.4), prop="qing"), A.act_read, False, ["dots"]),
    # 乡下（小康人家回姥姥家）：大襟褂子、蒲扇、晒黑的表哥
    "grandma_v": (look(F, "old", ("ink", 0.3), cardigan=("ink", 0.45), hair="grey", prop="mei"), act_fan, True, ["heart", "dots"]),
    "gate_old": (look(M, "old", WHITE, coat=("ink", 0.4), hat=CAP), act_fan, True, ["dots", "zzz"]),
    "cousin": (look(M, "teen", ("paper",), pants=("ink", 0.6, "flat"), prop="qing"), A.act_talk, False, ["talk", "note"]),
}

## 路人：一种一行，只会走。年纪、衣裳各不相同，引擎随机挑
WALKERS = [
    ("bag_man", look(M, "young", ("ink", 0.3), coat=("ink", 0.5))),
    ("basket_aunt", look(F, "middle", ("mei", 0.3), cardigan=("ink", 0.3))),
    ("cane_old", look(M, "old", ("ink", 0.25), coat=("qing", 0.35), cane=True, hat=CAP)),
    ("kid", look(M, "child", ("qing", 0.4), pants=("ink", 0.5, "flat"))),
    ("student", look(F, "teen", WHITE, coat=("qing", 0.4), pants=("ink", 0.6, "flat"))),
    ("coat_woman", look(F, "young", WHITE, long_coat=True, coat=("ink", 0.4))),
]


def _basket(p, layer, J):
    if layer == "front" and J["b"].get("basket"):
        h = J["hand_near"]
        p.shape([(h[0] - 9, h[1] + 3), (h[0] + 9, h[1] + 3), (h[0] + 7, h[1] + 16), (h[0] - 7, h[1] + 16)], ("ink", 0.3), line=1.4)
        p.line([(h[0] - 8, h[1] + 3), (h[0], h[1] - 4), (h[0] + 8, h[1] + 3)], 1.2)


WALKERS[1][1]["basket"] = True


def scene_sheet(ids):
    sh = Sheet(CELL_W * 8, CELL_H * len(ids), scale=SCALE, seed=71 + len(ids))
    p = Painter(sh)
    for row, nid in enumerate(ids):
        b, fn, sit, _ = FOLKS[nid]
        for i in range(4):
            draw_person(p, b, x0=i * CELL_W + FOOT[0], y0=row * CELL_H + FOOT[1], **_hooked(fn, b, i / 4.0))
            d = idle(b, i / 4.0, sit)
            d["hook"] = lambda pp, layer, J: dress(pp, layer, J)
            draw_person(p, b, x0=(4 + i) * CELL_W + FOOT[0], y0=row * CELL_H + FOOT[1], **d)
    return sh


def walker_sheet():
    sh = Sheet(CELL_W * 8, CELL_H * len(WALKERS), scale=SCALE, seed=97)
    p = Painter(sh)
    for row, (_name, b) in enumerate(WALKERS):
        for i in range(8):
            def hook(pp, layer, J):
                dress(pp, layer, J)
                _basket(pp, layer, J)
            pose = pose_walk(b, i / 8.0)
            if b.get("basket"):
                pose["arms"] = [dict(a, side=a["side"]) if a["side"] == "far" else dict(side="near", shoulder=0, elbow=0, hand_rel=(0.3, 0.62)) for a in pose["arms"]]
            draw_person(p, b, pose, i * CELL_W + FOOT[0], row * CELL_H + FOOT[1], hook=hook)
    return sh


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", default="")
    ap.add_argument("--only", default="", help="只出这几张图（逗号分隔），加 walkers 出路人")
    a = ap.parse_args()
    folks = json.load(open(FOLKS_JSON, encoding="utf-8"))
    os.makedirs(OUT_DIR, exist_ok=True)
    only = set(a.only.split(",")) if a.only else None
    index = {"scale": SCALE, "cell": [CELL_W, CELL_H], "foot": list(FOOT), "scenes": {}, "folks": {},
             "walkers": [w[0] for w in WALKERS]}
    previews = []
    missing = [n["id"] for lst in folks.values() for n in lst if n["id"] not in FOLKS]
    if missing:
        sys.exit("folks.py 里还没给这几位画长相：" + ", ".join(missing))
    for scene, lst in sorted(folks.items()):
        ids = [n["id"] for n in lst]
        index["scenes"][scene] = ids
        for row, nid in enumerate(ids):
            _b, _fn, sit, bubbles = FOLKS[nid]
            index["folks"][nid] = {"scene": scene, "row": row, "sit": sit, "bubbles": bubbles}
        if only and scene not in only:
            continue
        sh = scene_sheet(ids)
        if a.preview:
            previews.append(sh.composite())
        else:
            path = os.path.join(OUT_DIR, f"{scene}.png")
            save_rgba_small(sh, path)
            print("✓", os.path.relpath(path, ROOT))
    if not only or "walkers" in only:
        sh = walker_sheet()
        if a.preview:
            previews.append(sh.composite())
        else:
            path = os.path.join(OUT_DIR, "walkers.png")
            save_rgba_small(sh, path)
            print("✓", os.path.relpath(path, ROOT))
    if a.preview:
        import numpy as np
        from PIL import Image
        Image.fromarray(np.concatenate(previews, axis=0)).save(a.preview)
        print("✓", a.preview)
        return
    with open(os.path.join(OUT_DIR, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("✓", os.path.relpath(os.path.join(OUT_DIR, "index.json"), ROOT))


if __name__ == "__main__":
    main()
