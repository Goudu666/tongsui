#!/usr/bin/env python3
"""《同岁》角色精灵表：侧视横版，骨骼摆姿势，孔版套色印出来。

    python3 tools/art/actors.py            →  client/art/actors/{qing,mei}_{child,teen,young,middle,old}.png
    python3 tools/art/actors.py --preview  →  /tmp/actors_preview.png（十张表拼一张，调手感用）

每张 8 列 × 3 行，每格 CELL_W×CELL_H 世界像素（SCALE 倍输出），脚底中点在每格的 FOOT。人一律朝右，朝左由引擎翻转。
  行 0：走路一整步 8 帧（近腿相位 0, 1/8 … 7/8；远腿差半步）
  行 1：列 0–3 站着喘气（列 3 眨眼）；列 4–7 在忙（两手在身前做事）
  行 2：列 0–1 坐着；列 2–3 躺着睡（被子盖着）；列 4–7 挥手
人身上有一副骨架：髋、膝、踝、脚尖；肩、肘、手。走路的关键帧取的是真人步态的大致曲线
（脚跟着地时大腿前摆、蹬地时膝盖弯得最深），髋的高度由「哪只脚最低」反算，所以身体的起伏是自己出来的。

画法：每个部件先描一圈墨（宽一点）、再把里面挖空、铺纸版、上色。从后往前画，前面的自然压住后面的。
远侧的胳膊腿用同一种颜色的网点（浅一档），一眼看出前后。
"""
from __future__ import annotations

import argparse
import math
import os
import sys

import cairo

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from riso import COLORS, ROOT, Sheet  # noqa: E402

CELL_W, CELL_H = 200, 220
COLS, ROWS = 8, 3
FOOT = (100, 206)
SCALE = 2.0
OUT_DIR = os.path.join(ROOT, "client", "art", "actors")
ROLES = ("qing", "mei")
STAGES = ("child", "teen", "young", "middle", "old")
OUTLINE = 2.3  # 墨线（世界像素）
INKS = tuple(COLORS)


# ----------------------------------------------------------------------
# 体型和衣着
# ----------------------------------------------------------------------

def build(role: str, stage: str) -> dict:
    """一个人在某个年纪的样子：身高、各段长度、穿什么。颜色写成 (版, 网点浓度或 None=实地)。"""
    q = role == "qing"
    me = role
    H = {"child": 112, "teen": 152, "young": 172, "middle": 170, "old": 160}[stage] - (0 if q else 6)
    head = {"child": 19.5, "teen": 17.0, "young": 16.5, "middle": 16.8, "old": 16.3}[stage]
    leg = {"child": 0.37, "teen": 0.47, "young": 0.48, "middle": 0.47, "old": 0.45}[stage] * H
    neck = {"child": 3.0, "teen": 6.0, "young": 7.0, "middle": 6.0, "old": 4.5}[stage]
    torso = H - leg - neck - head * 2 + 2
    w = {"child": 25, "teen": 25, "young": 27, "middle": 31, "old": 29}[stage] - (0 if q else 2)
    b = dict(role=role, stage=stage, H=H, head=head, leg=leg, thigh=leg * 0.5, shin=leg * 0.43, ankle=leg * 0.07,
             neck=neck, torso=torso, waist=w, chest=w + (2 if stage != "child" else 0),
             upper=H * 0.17 if stage != "child" else H * 0.16, fore=H * 0.155 if stage != "child" else H * 0.15,
             limb=(10.5 if stage == "child" else 11.5), shin_w=9.5 if stage == "child" else 10.0,
             foot=13.0 if stage == "child" else 18.0,
             lean=6.0 if stage == "old" else 1.5, walk_lean=4.0, swing=1.0, stride=1.0,
             hair="ink", skin=("paper",))
    paper_tint = ("ink", 0.0)
    if stage == "child":
        b.update(shirt=(me, None), pants=("ink", 0.62, "flat") if q else (me, 0.45), shoes=(me if not q else "ink", None),
                 skirt=not q, collar=("paper",), stripes=q, stride=0.95, swing=1.2)
    elif stage == "teen":
        # 校服：一身运动服，袖子和裤腿一道白杠
        b.update(shirt=(me, None), pants=(me, None), shoes=("paper",), stripe=True, collar=("paper",), bag=True)
    elif stage == "young":
        if q:
            b.update(shirt=(me, None), coat=None, pants=("ink", 0.75, "flat"), shoes=("ink", None), collar=("paper",))
        else:
            b.update(shirt=("paper",), coat=(me, None), pants=("ink", 0.7, "flat"), shoes=("ink", None), long_coat=True)
    elif stage == "middle":
        if q:
            b.update(shirt=("paper",), coat=(me, None), pants=("ink", 0.8, "flat"), shoes=("ink", None), bag=False, stride=0.95)
        else:
            b.update(shirt=(me, None), cardigan=("mei", 0.5), pants=("ink", 0.72, "flat"), shoes=("ink", None), stride=0.95)
        b["hair"] = "ink"
    else:  # old
        b.update(shirt=(me, 0.55), coat=(me, None) if q else None, cardigan=None if q else (me, None),
                 pants=("ink", 0.58, "flat"), shoes=("ink", None), stride=0.72, swing=0.55, cane=q, hair="grey")
    b["paper_tint"] = paper_tint
    return b


# ----------------------------------------------------------------------
# 几何
# ----------------------------------------------------------------------

def polar(p, ang, length):
    """从 p 出发，与竖直向下夹角 ang 度（正 = 往前，+x）走 length。"""
    a = math.radians(ang)
    return (p[0] + length * math.sin(a), p[1] + length * math.cos(a))


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def arc_pts(cx, cy, rx, ry, a0, a1, n=None):
    n = n or max(6, int(abs(a1 - a0) / 7))
    return [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n)))
            for i in range(n + 1)]


def ell(cx, cy, rx, ry, n=40):
    return [(cx + rx * math.cos(i * math.tau / n), cy + ry * math.sin(i * math.tau / n)) for i in range(n)]


def chaikin(pts, it=2):
    for _ in range(it):
        out = []
        n = len(pts)
        for i in range(n):
            p, q = pts[i], pts[(i + 1) % n]
            out += [lerp(p, q, 0.25), lerp(p, q, 0.75)]
        pts = out
    return pts


def rot(pts, deg, c):
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(c[0] + (x - c[0]) * ca - (y - c[1]) * sa, c[1] + (x - c[0]) * sa + (y - c[1]) * ca) for x, y in pts]


def periodic(keys, t):
    """关键帧 [(相位, 值)]（相位 0~1，首尾相接），Catmull-Rom 插值。"""
    t %= 1.0
    ks = sorted(keys)
    n = len(ks)
    for i in range(n):
        t0, v0 = ks[i]
        t1, v1 = ks[(i + 1) % n]
        span = (t1 - t0) % 1.0 or 1.0
        if (t - t0) % 1.0 <= span:
            u = ((t - t0) % 1.0) / span
            vm = ks[(i - 1) % n][1]
            vp = ks[(i + 2) % n][1]
            return 0.5 * ((2 * v0) + (-vm + v1) * u + (2 * vm - 5 * v0 + 4 * v1 - vp) * u * u + (-vm + 3 * v0 - 3 * v1 + vp) * u ** 3)
    return ks[0][1]


# 一条腿一步的关键帧（相位 0 = 这只脚的脚跟着地）
THIGH = [(0.0, 24), (0.15, 17), (0.5, -13), (0.62, -9), (0.8, 18), (0.92, 25)]
KNEE = [(0.0, 3), (0.12, 15), (0.4, 4), (0.6, 36), (0.72, 58), (0.88, 18)]
FOOT_PITCH = [(0.0, -14), (0.1, 0), (0.42, 0), (0.6, 32), (0.74, 14), (0.9, -6)]


# ----------------------------------------------------------------------
# 印张上的部件：先墨圈，再挖空，再铺纸、上色
# ----------------------------------------------------------------------

class Painter:
    def __init__(self, sheet: Sheet):
        self.s = sheet
        self.ox = 0.0
        self.oy = 0.0

    def _ctx(self, color, layer):
        return self.s.plates[color][layer]

    def _path(self, ctx, pts, closed=True):
        ctx.new_path()
        ctx.move_to(pts[0][0] + self.ox, pts[0][1] + self.oy)
        for x, y in pts[1:]:
            ctx.line_to(x + self.ox, y + self.oy)
        if closed:
            ctx.close_path()

    def _fill(self, color, density, pts, closed=True, stroke_w=None, op=cairo.OPERATOR_OVER):
        layer = "solid" if density is None else "tint"
        ctx = self._ctx(color, layer)
        ctx.save()
        ctx.set_operator(op)
        ctx.set_source_rgba(0, 0, 0, 1.0 if density is None else density)
        self._path(ctx, pts, closed)
        if stroke_w is None:
            ctx.fill()
        else:
            ctx.set_line_width(stroke_w)
            ctx.set_line_cap(cairo.LINE_CAP_ROUND)
            ctx.set_line_join(cairo.LINE_JOIN_ROUND)
            ctx.stroke()
        ctx.restore()

    def _clear(self, pts, closed=True, stroke_w=None):
        for c in INKS:
            for layer in ("solid", "tint"):
                ctx = self._ctx(c, layer)
                ctx.save()
                ctx.set_operator(cairo.OPERATOR_CLEAR)
                self._path(ctx, pts, closed)
                if stroke_w is None:
                    ctx.fill()
                else:
                    ctx.set_line_width(stroke_w)
                    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
                    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
                    ctx.stroke()
                ctx.restore()

    def _paint(self, spec, pts, closed=True, stroke_w=None):
        if spec is None:
            return
        if spec[0] == "paper":
            return
        color, density = spec[0], spec[1] if len(spec) > 1 else None
        if density is not None and density <= 0:
            return
        if len(spec) > 2 and spec[2] == "flat":
            # 平涂：实地版上一层半透明（不出网点），裤子、头发这种大块深色用
            ctx = self._ctx(color, "solid")
            ctx.save()
            ctx.set_source_rgba(0, 0, 0, density)
            self._path(ctx, pts, closed)
            if stroke_w is None:
                ctx.fill()
            else:
                ctx.set_line_width(stroke_w)
                ctx.set_line_cap(cairo.LINE_CAP_ROUND)
                ctx.set_line_join(cairo.LINE_JOIN_ROUND)
                ctx.stroke()
            ctx.restore()
            return
        self._fill(color, density, pts, closed, stroke_w)

    def shape(self, pts, spec, line=OUTLINE, line_color="ink"):
        """一块面：墨圈 + 挖空 + 纸 + 色。"""
        if line > 0:
            self._fill(line_color, None, pts, True, stroke_w=line * 2)
        self._clear(pts)
        self._fill("paper", None, pts, True, stroke_w=line * 2 if line > 0 else None)
        self._fill("paper", None, pts)
        self._paint(spec, pts)

    def limb(self, pts, width, spec, line=OUTLINE):
        """一根胳膊或腿：一条圆头粗线，关节处自然连上，没有接缝。"""
        self._fill("ink", None, pts, False, stroke_w=width + line * 2)
        self._clear(pts, False, stroke_w=width)
        self._fill("paper", None, pts, False, stroke_w=width + line * 2)
        self._paint(spec, pts, False, stroke_w=width)

    def line(self, pts, w=OUTLINE, color="ink", density=None, closed=False):
        self._fill(color, density, pts, closed, stroke_w=w)

    def dot(self, x, y, r, color="ink", density=None):
        self._fill(color, density, ell(x, y, r, r, 16))

    def blot(self, pts, color, density=None, flat=False):
        """只上色、不挖空不描边（花纹、高光、腮红）。"""
        if flat:
            self._paint((color, density, "flat"), pts)
        else:
            self._fill(color, density, pts)


# ----------------------------------------------------------------------
# 一个姿势
# ----------------------------------------------------------------------

def far_spec(spec):
    """远侧的胳膊腿：同色浅一档（实地变网点、网点再淡一点），像隔着一层空气。"""
    if spec is None or spec[0] == "paper":
        return ("ink", 0.12)
    c, d = spec[0], spec[1] if len(spec) > 1 else None
    if len(spec) > 2:
        return (c, min(0.95, d + 0.12), "flat")
    return (c, 0.62 if d is None else max(0.2, d * 0.7))


def leg_points(hip, thigh_deg, knee_deg, pitch_deg, b):
    knee = polar(hip, thigh_deg, b["thigh"])
    ankle = polar(knee, thigh_deg - knee_deg, b["shin"])
    heel = (ankle[0] - b["foot"] * 0.22, ankle[1] + b["ankle"])
    # 脚：脚后跟到脚尖，按 pitch 绕脚踝转
    toe = (ankle[0] + b["foot"] * 0.85, ankle[1] + b["ankle"])
    heel, toe = rot([heel, toe], pitch_deg, ankle)
    return knee, ankle, heel, toe


def pose_walk(b, phase):
    """走路这一帧：两条腿、两只胳膊的角度和髋的位置。"""
    st, sw = b["stride"], b["swing"]
    legs = []
    for side, ph in (("near", phase), ("far", phase + 0.5)):
        legs.append(dict(side=side, thigh=periodic(THIGH, ph) * st, knee=periodic(KNEE, ph) * (0.6 + 0.4 * st),
                         pitch=periodic(FOOT_PITCH, ph) * st))
    arms = []
    for side, leg in (("near", legs[1]), ("far", legs[0])):  # 手和对侧的腿一起往前
        a = leg["thigh"] * 0.95 * sw
        arms.append(dict(side=side, shoulder=a, elbow=12 + max(0.0, a) * 0.9))
    return dict(legs=legs, arms=arms, lean=b["lean"] + b["walk_lean"], bob=0.0, tilt=0.0)


def pose_stand(b, breathe=0.0):
    legs = [dict(side="near", thigh=3, knee=4, pitch=0), dict(side="far", thigh=-4, knee=3, pitch=0)]
    arms = [dict(side="near", shoulder=4 + breathe, elbow=10), dict(side="far", shoulder=-3 - breathe, elbow=8)]
    return dict(legs=legs, arms=arms, lean=b["lean"], bob=breathe * 0.6, tilt=0.0)


def place_hip(b, pose):
    """髋放多高：两只脚里最低的那一点正好踩在地上（y=0）。"""
    hip0 = (0.0, 0.0)
    low = -1e9
    for leg in pose["legs"]:
        knee, ankle, heel, toe = leg_points(hip0, leg["thigh"], leg["knee"], leg["pitch"], b)
        low = max(low, heel[1], toe[1], ankle[1] + b["ankle"] * 0.8)
    return (0.0, -low)


def draw_person(p: Painter, b, pose, x0, y0, blink=False, busy=None, wave=None, sit=False):
    """把一个姿势画到 (x0, y0) 为脚底的位置。"""
    p.ox, p.oy = x0, y0
    if sit:
        hip = (-4.0, -44.0)
    else:
        hip = place_hip(b, pose)
        hip = (hip[0], hip[1] - pose.get("bob", 0.0))
    lean = pose["lean"]
    # 躯干：髋到肩，往前倾 lean 度
    shoulder = polar(hip, 180 - lean, b["torso"])
    neck_top = polar(shoulder, 180 - lean * 0.6, b["neck"])
    head_c = (neck_top[0] + 2.0 + lean * 0.25, neck_top[1] - b["head"] * 0.92)
    w, cw = b["waist"], b["chest"]

    # ---- 远侧：胳膊、腿 ----
    def leg_poly(leg):
        return leg_points(hip, leg["thigh"], leg["knee"], leg["pitch"], b)

    def draw_leg(leg, far):
        knee, ankle, heel, toe = leg_poly(leg)
        pants = far_spec(b["pants"]) if far else b["pants"]
        p.limb([hip, knee, ankle], b["limb"] if not sit else b["limb"], pants)
        if b.get("stripe"):
            p.line([lerp(hip, knee, 0.1), knee, lerp(knee, ankle, 0.85)], 2.2, "ink", 0.0)
            _stripe(p, [lerp(hip, knee, 0.15), knee, lerp(knee, ankle, 0.8)], far)
        shoe = far_spec(b["shoes"]) if far and b["shoes"][0] != "paper" else b["shoes"]
        # 鞋：一块圆头的面
        ang = math.degrees(math.atan2(toe[1] - heel[1], toe[0] - heel[0]))
        sole = 6.5 if b["stage"] != "child" else 5.5
        pts = arc_pts(toe[0] - sole * 0.7, toe[1] - sole * 0.75, sole, sole * 0.95, -80 + ang, 90 + ang, 8) + \
            arc_pts(heel[0] + sole * 0.4, heel[1] - sole * 0.7, sole * 0.75, sole * 0.75, 90 + ang, 230 + ang, 6) + \
            [polar(ankle, 180 + ang * 0.5, sole * 0.6)]
        p.shape(pts, shoe)

    def draw_arm(arm, far):
        sh = (shoulder[0] + (-3 if far else 1), shoulder[1] + 4)
        elbow = polar(sh, arm["shoulder"], b["upper"])
        hand = polar(elbow, arm["shoulder"] + arm["elbow"], b["fore"])
        if "hand_to" in arm:
            hand = arm["hand_to"]
            # 按手的位置反算肘：两段长不变，肘往下弯
            elbow = _ik(sh, hand, b["upper"], b["fore"], bend=arm.get("bend", 1))
        sleeve = b.get("coat") or b.get("cardigan") or b["shirt"]
        spec = far_spec(sleeve) if far else sleeve
        p.limb([sh, elbow, hand], b["limb"] - 1.0, spec)
        if b.get("stripe"):
            _stripe(p, [lerp(sh, elbow, 0.2), elbow, lerp(elbow, hand, 0.7)], far)
        p.shape(ell(hand[0], hand[1], 4.6, 4.6, 14), ("paper",) if not far else ("ink", 0.1, "flat"), line=1.8)
        return hand

    far_leg = [l for l in pose["legs"] if l["side"] == "far"][0]
    near_leg = [l for l in pose["legs"] if l["side"] == "near"][0]
    far_arm = [a for a in pose["arms"] if a["side"] == "far"][0]
    near_arm = [a for a in pose["arms"] if a["side"] == "near"][0]

    if b.get("bag") and b["stage"] == "teen":
        # 书包：背在身后，远侧
        bx, by = polar(hip, 180 - lean, b["torso"] * 0.55)
        p.shape(chaikin([(bx - w * 0.5 - 15, by - 18), (bx - w * 0.5 + 2, by - 22), (bx - w * 0.5 + 2, by + 22), (bx - w * 0.5 - 14, by + 18)], 2),
                ("ink", 0.55))
    draw_arm(far_arm, True)
    if b.get("cane"):
        pass
    draw_leg(far_leg, True)
    draw_leg(near_leg, False)

    # ---- 躯干 ----
    up = (math.sin(math.radians(lean)), -math.cos(math.radians(lean)))  # 沿躯干往上
    rt = (-up[1], up[0])  # 往前

    def at(t, side):  # 躯干上 t（0 髋 ~ 1 肩）处、side（-1 后 ~ 1 前）处的点
        width = w + (cw - w) * t
        c = (hip[0] + up[0] * b["torso"] * t, hip[1] + up[1] * b["torso"] * t)
        return (c[0] + rt[0] * side * width / 2, c[1] + rt[1] * side * width / 2)

    hem = -0.1
    body = [at(hem, -1.05), at(0.55, -1.0), at(0.92, -0.85), at(1.02, -0.3), at(1.02, 0.45), at(0.9, 0.95), at(0.5, 1.0), at(hem, 1.0)]
    body = chaikin(body, 2)
    outer = b.get("coat") or b.get("cardigan")
    shirt = b["shirt"]
    if b.get("skirt"):
        # 小裙子：从腰往下撒开，盖住大腿
        sk = [at(0.35, -1.0), at(0.35, 1.0), (hip[0] + w * 0.78, hip[1] + b["thigh"] * 0.62), (hip[0] - w * 0.82, hip[1] + b["thigh"] * 0.66)]
        p.shape(chaikin(sk, 1), b["shirt"])
    if b.get("long_coat"):
        coat = [at(1.0, -0.9), at(1.0, 0.9), at(0.0, 1.05), (hip[0] + w * 0.62, hip[1] + b["thigh"] * 0.95),
                (hip[0] - w * 0.75, hip[1] + b["thigh"] * 0.95), at(0.0, -1.1)]
        p.shape(chaikin(coat, 1), outer)
        # 门襟里露出一条衬衫
        p.shape([at(0.99, 0.3), at(0.99, 0.75), at(0.55, 0.75)], ("paper",), line=1.4)
        p.line([at(0.55, 0.85), (hip[0] + w * 0.58, hip[1] + b["thigh"] * 0.9)], 1.4)
        # 腰带和背后的阴影
        p.line([at(0.3, -1.02), at(0.3, 1.02)], 2.4)
        p.blot(chaikin([at(0.98, -0.85), at(0.6, -0.62), at(0.0, -0.75), (hip[0] - w * 0.6, hip[1] + b["thigh"] * 0.9),
                        (hip[0] - w * 0.75, hip[1] + b["thigh"] * 0.93), at(0.0, -1.08), at(0.9, -1.0)], 1), "ink", 0.22)
    else:
        p.shape(body, outer if outer else shirt)
        # 背后一道阴影（墨网点），身体就圆起来了
        p.blot(chaikin([at(hem + 0.02, -1.0), at(0.5, -0.98), at(0.9, -0.8), at(0.85, -0.45), at(0.45, -0.6), at(hem + 0.05, -0.62)], 1), "ink", 0.24)
        if outer:
            # 敞着的外套：前襟露出里面的衣服
            inner = [at(0.98, 0.15), at(0.98, 0.95), at(0.05, 1.0), at(0.05, 0.62), at(0.6, 0.45)]
            p.shape(chaikin(inner, 1), shirt, line=1.6)
            if b.get("cardigan"):
                for t in (0.3, 0.55, 0.8):
                    p.dot(*at(t, 0.58), 1.4)
        if b.get("stripes"):
            # 海魂衫一样的横道（只是道道，不是海魂衫）
            for k in range(4):
                t = 0.12 + k * 0.21
                _paper_band(p, [at(t, -0.98), at(t, 0.98), at(t + 0.075, 0.98), at(t + 0.075, -0.98)])
        if b.get("stripe"):
            # 校服前襟的拉链
            p.line([at(0.05, 0.92), at(0.98, 0.7)], 1.3)
    collar = b.get("collar")
    if collar and not b.get("long_coat"):
        c0 = at(1.0, -0.2)
        c1 = at(1.0, 0.55)
        p.shape([c0, c1, at(0.86, 0.35)], collar, line=1.5)

    # ---- 头 ----
    hr = b["head"]
    hx, hy = head_c
    # 脖子
    p.limb([neck_top, (neck_top[0], neck_top[1] + 3), shoulder], 8.5 if b["stage"] != "child" else 7.5, b["skin"], line=1.8)
    _head(p, b, hx, hy, hr, blink, pose.get("tilt", 0.0))

    # ---- 近侧胳膊（压在身前） ----
    if busy is not None:
        k = busy
        tgt = (shoulder[0] + b["upper"] * 0.95, shoulder[1] + b["upper"] * 0.75 - 4 * math.sin(k * math.tau))
        near_arm = dict(near_arm, hand_to=tgt, bend=1)
        h = draw_arm(near_arm, False)
        # 手里的东西：一只碗 / 一块抹布 / 一本书，都画成一个小方块
        p.shape([(h[0] - 3, h[1] - 8), (h[0] + 13, h[1] - 10), (h[0] + 14, h[1] + 2), (h[0] - 2, h[1] + 4)], (b["role"], 0.35), line=1.6)
    elif wave is not None:
        ang = 128 + 8 * math.sin(wave * math.tau)
        near_arm = dict(near_arm, shoulder=ang, elbow=-30 - 22 * math.sin(wave * math.tau))
        draw_arm(near_arm, False)
    else:
        h = draw_arm(near_arm, False)
        if b.get("cane"):
            tip = (h[0] + 10, 0.0)
            p.line([h, (h[0] - 2, h[1] - 6)], 3.2)
            p.line([(h[0] - 3, h[1] - 6), tip], 3.2)


def _paper_band(p: Painter, pts):
    """在衣服上挖出一道纸白（横条纹）。"""
    p._clear(pts)
    p._fill("paper", None, pts)


def _stripe(p: Painter, pts, far):
    """校服袖子、裤腿上那道白杠。"""
    p._clear(pts, False, stroke_w=2.6)
    p._fill("paper", None, pts, False, stroke_w=2.6)


def _ik(a, c, l1, l2, bend=1):
    d = min(math.dist(a, c), l1 + l2 - 0.01)
    ang = math.atan2(c[1] - a[1], c[0] - a[0])
    cos_a = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)
    off = math.acos(max(-1.0, min(1.0, cos_a)))
    t = ang + off * bend
    return (a[0] + l1 * math.cos(t), a[1] + l1 * math.sin(t))


def _head(p: Painter, b, hx, hy, r, blink, tilt):
    st = b["stage"]
    q = b["role"] == "qing"
    grey = b["hair"] == "grey"
    hair = ("ink", 0.38) if grey else ("ink", None)
    # 后面的头发（梅的短发、马尾）
    if not q:
        if st in ("child", "teen"):
            # 马尾 / 小辫
            tail = [(hx - r * 0.7, hy - r * 0.35), (hx - r * 1.55, hy - r * 0.05), (hx - r * 1.65, hy + r * 0.75), (hx - r * 1.05, hy + r * 0.35)]
            p.shape(chaikin(tail, 2), hair)
            p.shape(ell(hx - r * 0.85, hy - r * 0.2, 3.2, 3.2, 12), ("mei", None), line=1.5)
        elif st in ("young",):
            back = [(hx - r * 1.08, hy - r * 0.4), (hx - r * 1.12, hy + r * 1.25), (hx - r * 0.1, hy + r * 1.3), (hx + r * 0.2, hy + r * 0.2)]
            p.shape(chaikin(back, 2), hair)
        elif st == "middle":
            back = [(hx - r * 1.05, hy - r * 0.3), (hx - r * 1.0, hy + r * 0.95), (hx - r * 0.2, hy + r * 1.0), (hx + r * 0.1, hy)]
            p.shape(chaikin(back, 2), hair)
        else:
            # 盘起来的发髻
            p.shape(ell(hx - r * 0.85, hy - r * 0.55, r * 0.48, r * 0.44, 18), hair)
    # 脸
    face = ell(hx, hy, r, r * 1.02, 36)
    # 下巴往前一点点
    face = [(x + max(0.0, (y - hy)) * 0.12 * (1 if x > hx else 0), y) for x, y in face]
    p.shape(face, b["skin"])
    # 耳朵
    ex, ey = hx - r * 0.18, hy + r * 0.16
    p.shape(ell(ex, ey, r * 0.16, r * 0.22, 12), b["skin"], line=1.4)
    # 头发（前面这一片）：盖住头顶和后脑勺，前面留出脸
    if q:
        if grey:
            cap = [(hx - r * 1.04, hy + r * 0.25), (hx - r * 1.08, hy - r * 0.5), (hx - r * 0.4, hy - r * 1.12), (hx + r * 0.5, hy - r * 1.02),
                   (hx + r * 0.95, hy - r * 0.45), (hx + r * 0.25, hy - r * 0.62), (hx - r * 0.35, hy - r * 0.2), (hx - r * 0.55, hy + r * 0.3)]
        else:
            cap = [(hx - r * 1.06, hy + r * 0.38), (hx - r * 1.1, hy - r * 0.55), (hx - r * 0.45, hy - r * 1.18), (hx + r * 0.55, hy - r * 1.1),
                   (hx + r * 1.08, hy - r * 0.42), (hx + r * 0.6, hy - r * 0.5), (hx + r * 0.32, hy - r * 0.32), (hx - r * 0.1, hy - r * 0.48),
                   (hx - r * 0.45, hy - r * 0.05), (hx - r * 0.62, hy + r * 0.42)]
        p.shape(chaikin(cap, 2), hair)
        if not grey and st in ("child", "teen"):
            # 头顶一撮翘毛（青的标志，从小到大）
            p.line([(hx - r * 0.05, hy - r * 1.08), (hx + r * 0.15, hy - r * 1.5), (hx + r * 0.42, hy - r * 1.42)], 2.4)
        if st in ("middle", "old"):
            # 眼镜
            p.line(ell(hx + r * 0.55, hy - r * 0.02, r * 0.27, r * 0.22, 16), 1.6, closed=True)
            p.line([(hx + r * 0.28, hy - r * 0.05), (hx - r * 0.05, hy - r * 0.1)], 1.4)
    else:
        if st == "old":
            cap = [(hx - r * 1.05, hy + r * 0.2), (hx - r * 1.05, hy - r * 0.5), (hx - r * 0.3, hy - r * 1.12), (hx + r * 0.6, hy - r * 0.95),
                   (hx + r * 0.95, hy - r * 0.4), (hx + r * 0.2, hy - r * 0.62), (hx - r * 0.4, hy - r * 0.1)]
        else:
            # 齐刘海 + 盖住耳朵的短发
            cap = [(hx - r * 1.08, hy + (r * 0.9 if st in ("child", "young", "middle") else r * 0.4)), (hx - r * 1.12, hy - r * 0.5),
                   (hx - r * 0.4, hy - r * 1.2), (hx + r * 0.6, hy - r * 1.1), (hx + r * 1.1, hy - r * 0.45), (hx + r * 1.05, hy - r * 0.18),
                   (hx + r * 0.42, hy - r * 0.26), (hx + r * 0.05, hy - r * 0.1), (hx - r * 0.12, hy + (r * 0.95 if st != "teen" else r * 0.5)),
                   (hx - r * 0.55, hy + (r * 1.05 if st != "teen" else r * 0.55))]
        p.shape(chaikin(cap, 2), hair)
        if st != "old":
            # 头发上一道高光（纸白）
            hl = [(hx - r * 0.45, hy - r * 0.95), (hx + r * 0.1, hy - r * 1.02), (hx + r * 0.05, hy - r * 0.88), (hx - r * 0.45, hy - r * 0.8)]
            _paper_band(p, chaikin(hl, 1))
        if st in ("middle", "old"):
            p.line(ell(hx + r * 0.56, hy - r * 0.0, r * 0.26, r * 0.21, 16), 1.5, closed=True)
    if q and not grey:
        hl = [(hx - r * 0.55, hy - r * 0.9), (hx - r * 0.05, hy - r * 1.03), (hx - r * 0.08, hy - r * 0.9), (hx - r * 0.55, hy - r * 0.76)]
        _paper_band(p, chaikin(hl, 1))
    # 眼睛、腮红、嘴
    exx, eyy = hx + r * 0.56, hy - r * 0.02
    if blink:
        p.line([(exx - 2.6, eyy + 0.5), (exx + 2.6, eyy + 0.5)], 1.6)
    else:
        p.dot(exx, eyy, 2.2 if st == "child" else 1.9)
    p.blot(ell(hx + r * 0.4, hy + r * 0.4, r * 0.24, r * 0.15, 14), "mei", 0.35, flat=True)
    p.line([(hx + r * 0.78, hy + r * 0.52), (hx + r * 0.9, hy + r * 0.5)], 1.3)
    if st == "old":
        # 皱纹两道
        p.line([(hx + r * 0.75, hy - r * 0.3), (hx + r * 0.9, hy - r * 0.18)], 1.0)


def draw_sleep(p: Painter, b, x0, y0, k):
    """躺着睡：人横过来，被子盖到肩膀，被子跟着呼吸起伏。"""
    p.ox, p.oy = x0, y0
    L = b["H"]
    r = b["head"]
    breathe = 1.5 * math.sin(k * math.pi)
    hx = -L * 0.42 + r
    hy = -r - 4
    # 枕头
    p.shape(chaikin([(hx - r * 1.5, -4), (hx - r * 1.4, -r * 1.3), (hx + r * 1.2, -r * 1.25), (hx + r * 1.3, -4)], 2), ("paper",), line=1.8)
    _head_lying(p, b, hx, hy, r)
    quilt = [(hx + r * 0.5, -1), (hx + r * 0.55, -r * 1.7 - breathe), (hx + r * 2.5, -r * 2.3 - breathe * 1.4), (hx + L * 0.45, -r * 2.1 - breathe * 1.2),
             (L * 0.52, -r * 1.6 - breathe), (L * 0.58, -1)]
    p.shape(chaikin(quilt, 2), (b["role"], 0.55))
    # 被面的花：几个小圆点
    for i in range(5):
        p.dot(hx + r * 1.9 + i * L * 0.12, -r * 1.0 - breathe * 0.8 + (i % 2) * 7, 2.6, b["role"], None)


def _head_lying(p, b, hx, hy, r):
    # 侧着躺的头：就是普通的头转了 -90 度太费事，直接画一张闭眼的侧脸，头发朝左
    face = ell(hx, hy, r, r, 30)
    p.shape(face, b["skin"])
    hair = ("ink", 0.38) if b["hair"] == "grey" else ("ink", None)
    cap = [(hx - r * 1.05, hy + r * 0.6), (hx - r * 1.1, hy - r * 0.5), (hx - r * 0.3, hy - r * 1.1), (hx + r * 0.6, hy - r * 0.95),
           (hx + r * 0.9, hy - r * 0.5), (hx + r * 0.2, hy - r * 0.45), (hx - r * 0.3, hy + r * 0.1)]
    p.shape(chaikin(cap, 2), hair)
    p.line(arc_pts(hx + r * 0.45, hy + r * 0.05, 3.0, 2.0, 10, 170, 6), 1.6)
    p.blot(ell(hx + r * 0.38, hy + r * 0.42, r * 0.22, r * 0.14, 12), "mei", 0.35, flat=True)


def draw_sit(p: Painter, b, x0, y0, k):
    """坐着：坐在一个 44 高的凳子上（场景里的凳子、长椅都是这个高度）；小孩脚够不着地，晃荡。"""
    swing = math.sin(k * math.pi) * (10 if b["stage"] == "child" else 2)
    seat = -44.0
    hip = (-4.0, seat)
    # 大腿水平往前，小腿往下垂
    th = 90 - 4
    knee_x = b["thigh"] * math.sin(math.radians(th))
    reach = -seat - b["ankle"] - 2  # 脚踩地需要的小腿竖直长度
    if b["shin"] >= reach:
        knee_deg_near = th - math.degrees(math.acos(min(1.0, reach / b["shin"]))) + 0
    else:
        knee_deg_near = th - 8
    legs = [dict(side="near", thigh=th, knee=knee_deg_near + swing, pitch=0), dict(side="far", thigh=th - 3, knee=knee_deg_near - swing * 0.5 + 6, pitch=0)]
    arms = [dict(side="near", shoulder=28, elbow=48), dict(side="far", shoulder=22, elbow=50)]
    pose = dict(legs=legs, arms=arms, lean=b["lean"] + 3, bob=0.0)
    draw_person(p, b, pose, x0, y0, sit=True)


# ----------------------------------------------------------------------
# 一整张表
# ----------------------------------------------------------------------

def sheet_for(role, stage) -> Sheet:
    b = build(role, stage)
    sh = Sheet(CELL_W * COLS, CELL_H * ROWS, scale=SCALE, seed=11 + len(role) * 7 + STAGES.index(stage))
    p = Painter(sh)

    def cell(r, c):
        return c * CELL_W + FOOT[0], r * CELL_H + FOOT[1]

    for i in range(8):
        x, y = cell(0, i)
        draw_person(p, b, pose_walk(b, i / 8.0), x, y)
    for i in range(4):
        x, y = cell(1, i)
        br = math.sin(i / 4.0 * math.tau)
        draw_person(p, b, pose_stand(b, br), x, y, blink=(i == 3))
    for i in range(4):
        x, y = cell(1, 4 + i)
        pose = pose_stand(b, 0.4 * math.sin(i / 4.0 * math.tau))
        pose["lean"] += 4
        draw_person(p, b, pose, x, y, busy=i / 4.0)
    for i in range(2):
        x, y = cell(2, i)
        draw_sit(p, b, x, y, i)
    for i in range(2):
        x, y = cell(2, 2 + i)
        draw_sleep(p, b, x, y, i)
    for i in range(4):
        x, y = cell(2, 4 + i)
        draw_person(p, b, pose_stand(b, 0.3), x, y, wave=i / 4.0)
    return sh


def save_rgba_small(sh: Sheet, path):
    """RGBA 量化成 96 色调色板（带透明），一张 600 KB → 130 KB 左右，看不出差别。"""
    import numpy as np
    from PIL import Image
    rgb = sh.composite(True, True)
    a = np.clip(sh.alpha() * 255.0 + 0.5, 0, 255).astype(np.uint8)
    img = Image.fromarray(np.dstack([rgb, a]), "RGBA")
    img.quantize(colors=96, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).save(path, optimize=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", nargs="?", const="/tmp/actors_preview.png")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    os.makedirs(OUT_DIR, exist_ok=True)
    stages = a.only.split(",") if a.only else STAGES
    sheets = []
    for stage in stages:
        for role in ROLES:
            sh = sheet_for(role, stage)
            path = os.path.join(OUT_DIR, f"{role}_{stage}.png")
            if a.preview:
                sheets.append(sh.composite())
            else:
                save_rgba_small(sh, path)
                print("✓", os.path.relpath(path, ROOT))
    if a.preview:
        import numpy as np
        from PIL import Image
        Image.fromarray(np.concatenate(sheets, axis=0)).save(a.preview)
        print("✓", a.preview)


if __name__ == "__main__":
    main()
