#!/usr/bin/env python3
"""《同岁》角色精灵表生成器（孔版套色 + 墨线简笔）。

    python3 tools/art/actors.py      →  client/art/actors/{qing,mei}_{child,teen,young,middle,old}.png

每张 6 列 × 4 行，每格 96×128 世界像素（scale=2 → 192×256 像素），整张 1152×1024。
  行 0 朝下 / 行 1 朝上 / 行 2 朝右（朝左由引擎水平翻转）
    列 0 站立；列 1–4 走路（迈左脚、并拢、迈右脚、并拢）；列 5 在忙（双手在胸前端东西）
  行 3：列 0 睡觉，列 1 挥手（朝下），列 2 坐着（朝下），列 3–5 空
脚底中点固定在每格的 (48, 120) 世界像素处。

画法：每个部件"先挖空、再铺纸版、再上色、最后描墨线"，按从后往前的顺序叠，
所以前面的部件会盖住后面的（孔版上就是专色版挖空）。局部坐标以脚底为原点、y 向上为负。
"""
from __future__ import annotations

import math
import os
import sys
from contextlib import contextmanager
from dataclasses import dataclass

import cairo

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from riso import ROOT, Sheet, ellipse_pts, rect_pts, wobble  # noqa: E402

CELL_W, CELL_H = 96, 128
COLS, ROWS = 6, 4
FOOT = (48, 120)
SCALE = 2.0
OUT_DIR = os.path.join(ROOT, "client", "art", "actors")
ROLES = ("qing", "mei")
STAGE_ORDER = ("child", "teen", "young", "middle", "old")
INKS = ("ink", "qing", "mei")

SKIN = ("paper", None)  # 留白：只进纸版，不印墨


def solid(c):
    return (c, None)


def tint(c, d):
    return (c, d)


# ----------------------------------------------------------------------
# 几何
# ----------------------------------------------------------------------

def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def add(p, dx, dy):
    return (p[0] + dx, p[1] + dy)


def chaikin(pts, it=2, closed=True):
    """削角：把多边形磨圆一点，Q 版的身体都是软的。"""
    pts = list(pts)
    for _ in range(it):
        out = []
        n = len(pts)
        if not closed:
            out.append(pts[0])
        for i in range(n if closed else n - 1):
            p, q = pts[i], pts[(i + 1) % n]
            out.append(lerp(p, q, 0.25))
            out.append(lerp(p, q, 0.75))
        if not closed:
            out.append(pts[-1])
        pts = out
    return pts


def ell(cx, cy, rx, ry, n=None):
    return ellipse_pts(cx, cy, rx, ry, n or max(20, int(max(rx, ry) * 1.8)))


def arc_pts(cx, cy, rx, ry, a0, a1, n=None):
    """椭圆弧上的点，角度用度，屏幕坐标（0° 朝右，90° 朝下）。"""
    n = n or max(6, int(abs(a1 - a0) / 8))
    out = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        out.append((cx + rx * math.cos(a), cy + ry * math.sin(a)))
    return out


def rrect(x, y, w, h, r):
    r = max(0.1, min(r, w / 2, h / 2))
    pts = []
    for cx, cy, a0 in ((x + w - r, y + r, -90), (x + w - r, y + h - r, 0), (x + r, y + h - r, 90), (x + r, y + r, 180)):
        pts += arc_pts(cx, cy, r, r, a0, a0 + 90, 4)
    return pts


def polar(p, ang, length):
    """从 p 出发、与竖直向下夹角 ang 度（正 = 往 +x 方向）走 length。四肢都这样摆。"""
    a = math.radians(ang)
    return (p[0] + length * math.sin(a), p[1] + length * math.cos(a))


def capsule(p0, p1, r0, r1=None):
    r1 = r0 if r1 is None else r1
    ang = math.degrees(math.atan2(p1[1] - p0[1], p1[0] - p0[0]))
    return arc_pts(p1[0], p1[1], r1, r1, ang - 90, ang + 90, 8) + arc_pts(p0[0], p0[1], r0, r0, ang + 90, ang + 270, 8)


def rotate(pts, deg, c=(0.0, 0.0)):
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(c[0] + (x - c[0]) * ca - (y - c[1]) * sa, c[1] + (x - c[0]) * sa + (y - c[1]) * ca) for x, y in pts]


def slice_path(pts, t0, t1):
    """折线按长度取 [t0, t1] 那一段。"""
    seg = [math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]
    total = sum(seg) or 1.0

    def at(t):
        d = t * total
        for i, L in enumerate(seg):
            if d <= L or i == len(seg) - 1:
                return lerp(pts[i], pts[i + 1], 0 if L == 0 else min(1.0, d / L))
            d -= L
        return pts[-1]

    out = [at(t0)]
    acc = 0.0
    for i, L in enumerate(seg):
        acc += L
        if t0 * total < acc < t1 * total:
            out.append(pts[i + 1])
    out.append(at(t1))
    return out


# ----------------------------------------------------------------------
# 印刷动作
# ----------------------------------------------------------------------

def _all_ctx(s):
    return [s.plates[c][l] for c in INKS for l in ("solid", "tint")] + [s.plates["paper"]["solid"]]


@contextmanager
def place(s, x, y, rot=0.0, k=1.0):
    """把接下来所有版的坐标系移到 (x, y)，可选旋转（度）。"""
    cs = _all_ctx(s)
    for c in cs:
        c.save()
        c.translate(x, y)
        if rot:
            c.rotate(math.radians(rot))
        if k != 1.0:
            c.scale(k, k)
    try:
        yield
    finally:
        for c in cs:
            c.restore()


def _trace(ctx, pts, closed=False):
    ctx.new_path()
    ctx.move_to(*pts[0])
    for p in pts[1:]:
        ctx.line_to(*p)
    if closed:
        ctx.close_path()


def stroke_clear(s, pts, w, colors=INKS):
    """沿折线挖空一条（粗线形状的"挖空"）。"""
    for c in colors:
        for layer in ("solid", "tint"):
            ctx = s.plates[c][layer]
            ctx.save()
            _trace(ctx, pts)
            ctx.set_line_width(w)
            ctx.set_line_cap(cairo.LINE_CAP_ROUND)
            ctx.set_line_join(cairo.LINE_JOIN_ROUND)
            ctx.set_operator(cairo.OPERATOR_CLEAR)
            ctx.stroke()
            ctx.restore()


def paint(s, pts, spec):
    s.pen("paper").fill(pts)
    if spec is not None and spec[0] != "paper":
        s.pen(spec[0], spec[1]).fill(pts)


def part(s, pts, spec=SKIN, lw=2.6, amp=0.5, outline=True, occlude=True):
    """一个不透明部件：挖空 → 纸版 → 上色 → 墨线。"""
    if occlude:
        s.clear(pts)
    paint(s, pts, spec)
    if outline and lw > 0:
        s.ink.poly(pts, w=lw, amp=amp)


def tube(s, pts, w, spec, lw=2.6, amp=0.45, shade=0.0):
    """一根带墨边的管子（胳膊、腿、袖子）。w 是里面颜色的宽度。"""
    pw = wobble(pts, amp, step=10, seed=s.next_seed())
    stroke_clear(s, pw, w + 2 * lw)
    if lw > 0:
        s.ink.line(pw, w=w + 2 * lw, amp=0)
    stroke_clear(s, pw, w)
    s.pen("paper").line(pw, w=w + 2 * lw, amp=0)
    if spec is not None and spec[0] != "paper":
        s.pen(spec[0], spec[1]).line(pw, w=w, amp=0)
    if shade:
        s.pen("ink", shade).line(pw, w=w, amp=0)
    return pw


# ----------------------------------------------------------------------
# 角色设定
# ----------------------------------------------------------------------

# L 胯高（含鞋）  T 躯干（胯到肩）  n 脖子  r 头半径  sw/hw 肩/胯半宽  aw/lgw 胳膊/腿的颜色宽
# A 胳膊长  hand 手半径  lw 墨线宽  hunch 驼背（侧面肩往前探）
STAGES = {
    "child": dict(L=14, T=19, n=1.0, r=13.0, sw=9.0, hw=8.5, aw=5.0, lgw=5.5, A=15, hr=2.9, lw=2.5, hunch=0.0, belly=1.6),
    "teen": dict(L=26, T=27, n=1.0, r=14.0, sw=10.5, hw=8.6, aw=5.0, lgw=6.0, A=22, hr=3.0, lw=2.6, hunch=0.0, belly=0.0),
    "young": dict(L=32, T=31, n=2.0, r=14.5, sw=11.5, hw=9.2, aw=5.6, lgw=6.6, A=26, hr=3.2, lw=2.7, hunch=0.0, belly=0.0),
    "middle": dict(L=31, T=31, n=1.5, r=14.25, sw=12.5, hw=11.2, aw=6.2, lgw=7.2, A=26, hr=3.3, lw=2.7, hunch=0.0, belly=1.2),
    "old": dict(L=29, T=28, n=1.0, r=14.0, sw=11.5, hw=10.6, aw=5.8, lgw=6.8, A=24, hr=3.2, lw=2.7, hunch=3.0, belly=0.8),
}


@dataclass
class Look:
    top: tuple
    sleeve: tuple
    pants: tuple
    sleeve_len: float = 1.0          # <1：短袖/挽袖，露出小臂
    sleeve_upper: tuple | None = None  # 上半截袖子换色（校服）
    cuff: tuple | None = None        # 袖口罗纹
    pants_len: float = 1.0           # <1：短裤
    shoes: tuple = ("ink", None)
    hem: float = 2.0                 # 衣摆比胯低多少
    coat: bool = False               # 风衣：衣摆盖到膝
    hair: tuple = ("ink", None)


LOOKS = {
    ("qing", "child"): Look(top=solid("qing"), sleeve=solid("qing"), sleeve_len=0.42, pants=tint("ink", 0.34), pants_len=0.5, hem=1.5),
    ("qing", "teen"): Look(top=solid("qing"), sleeve=solid("qing"), sleeve_upper=SKIN, pants=solid("qing"), shoes=SKIN),
    ("qing", "young"): Look(top=tint("qing", 0.78), sleeve=tint("qing", 0.78), sleeve_len=0.62, pants=tint("ink", 0.32), hem=0.5),
    ("qing", "middle"): Look(top=solid("qing"), sleeve=solid("qing"), pants=tint("ink", 0.34), hem=3.0),
    ("qing", "old"): Look(top=tint("qing", 0.8), sleeve=tint("qing", 0.8), pants=tint("ink", 0.3), hem=3.0, hair=tint("ink", 0.22)),
    ("mei", "child"): Look(top=solid("mei"), sleeve=solid("mei"), sleeve_len=0.42, pants=tint("ink", 0.34), pants_len=0.5, hem=1.5),
    ("mei", "teen"): Look(top=solid("mei"), sleeve=solid("mei"), sleeve_upper=SKIN, pants=solid("mei"), shoes=SKIN),
    ("mei", "young"): Look(top=solid("mei"), sleeve=solid("mei"), pants=tint("ink", 0.32), coat=True),
    ("mei", "middle"): Look(top=tint("mei", 0.78), sleeve=tint("mei", 0.78), cuff=solid("mei"), pants=tint("ink", 0.32), hem=2.5),
    ("mei", "old"): Look(top=tint("mei", 0.3), sleeve=tint("mei", 0.3), pants=tint("ink", 0.32), hem=2.5, hair=tint("ink", 0.22)),
}


class Fig:
    def __init__(self, s: Sheet, role: str, stage: str):
        self.s, self.role, self.stage = s, role, stage
        for k, v in STAGES[stage].items():
            setattr(self, k, v)
        self.C = role
        self.look = LOOKS[(role, stage)]
        self.dw = self.sw * (0.86 if stage == "child" else 0.74)
        self.H = self.L + self.T + self.n + 2 * self.r
        if self.look.coat:
            self.look.hem = self.L * 0.46
        self.cane = role == "mei" and stage == "old"
        self.behind = role == "qing" and stage == "old"  # 背着手

    # ------------------------------------------------------------------
    # 四肢
    # ------------------------------------------------------------------
    def hand(self, W, prev=None, k=1.0):
        part(self.s, ell(W[0], W[1], self.hr * k, self.hr * k * 1.05), SKIN, self.lw * 0.85)

    def arm(self, pts, hand=True, shade=0.0, hand_k=1.0):
        s, lk, lw = self.s, self.look, self.lw
        if lk.sleeve_len < 1:
            tube(s, pts, self.aw - 1.4, SKIN, lw, shade=shade)
            tube(s, slice_path(pts, 0, lk.sleeve_len), self.aw + 0.8, lk.sleeve, lw, shade=shade)
        else:
            tube(s, pts, self.aw, lk.sleeve, lw, shade=shade)
            if lk.sleeve_upper:
                tube(s, slice_path(pts, 0, 0.42), self.aw, lk.sleeve_upper, lw, shade=shade)
            if lk.cuff:
                tube(s, slice_path(pts, 0.84, 1.0), self.aw + 0.4, lk.cuff, lw * 0.8)
            elif self.stage in ("middle", "old") and self.role == "qing":
                a, b = slice_path(pts, 0.82, 0.86)[0], pts[-1]
                d = math.dist(a, b) or 1
                nx, ny = -(b[1] - a[1]) / d, (b[0] - a[0]) / d
                h = (self.aw + lw) / 2
                s.ink.line([(a[0] - nx * h, a[1] - ny * h), (a[0] + nx * h, a[1] + ny * h)], w=1.2, amp=0)
        if hand:
            self.hand(pts[-1], k=hand_k)

    def leg(self, pts, view, foot_rot=0.0, shade=0.0, side=1):
        s, lk, lw = self.s, self.look, self.lw
        if lk.pants_len < 1:
            tube(s, pts, self.lgw - 1.6, SKIN, lw, shade=shade)
            tube(s, slice_path(pts, 0, lk.pants_len), self.lgw + 1.2, lk.pants, lw, shade=shade)
        else:
            pw = tube(s, pts, self.lgw, lk.pants, lw, shade=shade)
            if self.stage == "teen":  # 校服裤的白杠
                off = side * self.lgw * 0.28 if view in ("front", "back") else 0.0
                stroke_clear(s, [(x + off, y) for x, y in pw[1:-1]] if len(pw) > 3 else [(x + off, y) for x, y in pw], 1.5, colors=(self.C,))
        self.shoe(pts[-1], view, foot_rot)

    def shoe(self, A, view, rot=0.0):
        s, lw = self.s, self.lw
        ry = 2.3 if self.stage != "child" else 2.2
        if view in ("front", "back"):
            rx = (self.lgw + lw) / 2 + 0.9
            pts = ell(A[0], A[1] - 0.4, rx, ry)
        else:
            pts = capsule((A[0] - 1.6, A[1] - 0.4), (A[0] + 3.4 + self.lgw * 0.25, A[1] - 0.4), ry)
            if rot:
                pts = rotate(pts, rot, A)
        part(s, pts, self.look.shoes, lw * 0.9)

    # ------------------------------------------------------------------
    # 躯干
    # ------------------------------------------------------------------
    def torso_front(self, sy, hy, hem, flare=0.0):
        sw, hw, T = self.sw, self.hw, hy - sy
        xm = hw + (sw - hw) * 0.35 + self.belly
        pts = [(-sw + 3.5, sy - 0.6), (sw - 3.5, sy - 0.6), (sw + 0.3, sy + 3.5), (xm, sy + T * 0.6),
               (hw + 0.6 + flare, hem), (-hw - 0.6 - flare, hem), (-xm, sy + T * 0.6), (-sw - 0.3, sy + 3.5)]
        if self.look.coat:
            wy = sy + T * 0.8
            pts = pts[:3] + [(hw + 0.4, wy), (hw + 3.5 + flare, hem), (-hw - 3.5 - flare, hem), (-hw - 0.4, wy)] + pts[-1:]
        return chaikin(pts, 2)

    def torso_side(self, sy, hy, hem, shx, flare=0.0):
        d, T = self.dw, hy - sy

        def X(x, y):
            t = min(1.0, max(0.0, (hy - y) / T))
            return (x + shx * t, y)

        b = self.belly
        pts = [X(-d + 3, sy - 0.6), X(d - 3, sy - 0.6), X(d + 0.2, sy + 3.5), X(d + b, sy + T * 0.62),
               (d + 0.4 + flare, hem), (-d - 0.4 - flare * 0.6, hem), X(-d - 0.3 - shx * 0.45, sy + T * 0.32), X(-d, sy + 3.0)]
        if self.look.coat:
            wy = sy + T * 0.8
            pts = pts[:4] + [(d + 0.3, wy), (d + 3.2 + flare, hem), (-d - 2.6 - flare * 0.6, hem), (-d - 0.2, wy)] + pts[-2:]
        return chaikin(pts, 2)

    def neck(self, x, sy):
        n = self.n
        part(self.s, rrect(x - 2.7, sy - n - 5, 5.4, n + 7, 1.5), SKIN, self.lw * 0.8)

    # ------------------------------------------------------------------
    # 头
    # ------------------------------------------------------------------
    def head(self, view, eyes="open", mouth="smile"):
        s, r, lw = self.s, self.r, self.lw
        rx, ry = r * 1.06, r * 0.97
        hair = self.look.hair
        hl = lw * 0.8
        R = r + 1.8          # 青的短发
        Rb = r + 2.4         # 梅的波波头
        if self.role == "mei" and self.stage == "old":
            return self.perm_head(view, eyes, mouth)
        if view == "front":
            if self.role == "mei":
                back = arc_pts(0, 0, Rb * 1.03, Rb, 180, 360) + [(Rb * 1.03, 0.56 * r), (0.55 * r, 0.74 * r), (-0.55 * r, 0.74 * r), (-Rb * 1.03, 0.56 * r)]
                part(s, chaikin(back, 1), hair, hl)
            else:
                for sd in (-1, 1):
                    part(s, ell(sd * (rx + 0.3), 0.16 * r, 0.25 * r, 0.3 * r), SKIN, hl)
            part(s, ell(0, 0, rx, ry), SKIN, lw)
            self.face_front(eyes, mouth)
            if self.role == "qing":
                inner = [(0.92, 0.20), (0.84, -0.16), (0.63, -0.40), (0.47, -0.15), (0.27, -0.47), (0.05, -0.13),
                         (-0.17, -0.48), (-0.40, -0.19), (-0.60, -0.45), (-0.84, -0.17), (-0.92, 0.20)]
                pts = arc_pts(0, 0, R * 1.04, R, 166, 374, 26) + [(x * rx, y * r) for x, y in inner]
                part(s, pts, hair, hl, amp=0.3)
            else:
                inner = [(0.75, 0.62), (0.79, -0.02), (0.66, -0.30), (0.33, -0.36), (0.0, -0.33), (-0.33, -0.36), (-0.66, -0.30), (-0.79, -0.02), (-0.75, 0.62)]
                pts = arc_pts(0, 0, Rb * 1.03, Rb, 180, 360, 26) + [(Rb * 1.03, 0.56 * r)] + [(x * rx, y * r) for x, y in inner] + [(-Rb * 1.03, 0.56 * r)]
                part(s, pts, hair, hl, amp=0.3)
            self.shine(R if self.role == "qing" else Rb, 222, 250)
            if self.role == "qing":
                self.ahoge(0.08 * r, -R + 1.5, 1)
            if self.role == "mei" and self.stage == "child":
                self.clip_pin(0.52 * rx, -0.62 * r, -28)
            if self.stage == "old" and self.role == "qing":
                self.glasses_front()
        elif view == "back":
            part(s, ell(0, 0, rx, ry), SKIN, lw)
            if self.role == "qing":
                bottom = [(0.80, 0.52), (0.46, 0.46), (0.16, 0.62), (-0.14, 0.48), (-0.46, 0.60), (-0.80, 0.50)]
                pts = arc_pts(0, 0, R * 1.04, R, 154, 386, 28) + [(x * rx, y * r) for x, y in bottom]
                part(s, pts, hair, hl, amp=0.3)
                for sd in (-1, 1):
                    part(s, ell(sd * (rx + 0.2), 0.24 * r, 0.16 * r, 0.22 * r), SKIN, hl * 0.85)
                if self.stage == "old":  # 老花镜的镜腿
                    for sd in (-1, 1):
                        s.ink.line([(sd * (rx + 0.2), 0.02 * r), (sd * (rx - 1.5), 0.16 * r)], w=1.2, amp=0)
                self.ahoge(0.08 * r, -R + 1.5, 1)
            else:
                pts = arc_pts(0, 0, Rb * 1.03, Rb, 174, 366, 28) + [(Rb * 1.03, 0.62 * r), (0.5 * rx, 0.72 * r), (-0.5 * rx, 0.72 * r), (-Rb * 1.03, 0.62 * r)]
                part(s, chaikin(pts, 1), hair, hl, amp=0.3)
                if self.stage == "child":
                    self.clip_pin(-0.52 * rx, -0.62 * r, 28)
            self.shine(R if self.role == "qing" else Rb, 290, 318)
        else:  # side，朝 +x
            if self.role == "mei":
                back = arc_pts(0, 0, Rb * 1.02, Rb, 300, 172, 24) + [(-Rb * 1.05, 0.62 * r), (-0.2 * rx, 0.74 * r)]
                part(s, chaikin(back, 1), hair, hl)
            part(s, ell(0, 0, rx, ry), SKIN, lw)
            self.face_side(eyes, mouth)
            if self.role == "qing":
                inner = [(-0.52, 0.52), (-0.32, 0.12), (0.0, -0.18), (0.22, -0.06), (0.40, -0.40), (0.60, -0.18), (0.78, -0.44), (0.98, -0.34)]
                pts = arc_pts(0, 0, R * 1.03, R, 336, 146, 26) + [(x * rx, y * r) for x, y in inner]
                part(s, pts, hair, hl, amp=0.3)
                part(s, ell(-0.3 * rx, 0.3 * r, 0.17 * r, 0.22 * r), SKIN, hl * 0.85)
                self.ahoge(0.05 * r, -R + 1.5, 1)
                if self.stage == "old":
                    self.glasses_side()
            else:
                pts = arc_pts(0, 0, Rb * 1.02, Rb, 332, 172, 26) + [(-Rb * 1.05, 0.62 * r), (0.08 * rx, 0.7 * r), (0.15 * rx, 0.1 * r),
                                                                     (0.3 * rx, -0.26 * r), (0.62 * rx, -0.34 * r), (0.98 * rx, -0.30 * r)]
                part(s, pts, hair, hl, amp=0.3)
                if self.stage == "child":
                    self.clip_pin(0.22 * rx, -0.8 * r, -10)
            self.shine(R if self.role == "qing" else Rb, 222, 252)

    def perm_head(self, view, eyes, mouth):
        """梅·老年：一头短短的小卷（烫过的银发）。"""
        s, r, lw = self.s, self.r, self.lw
        rx, ry = r * 1.06, r * 0.97
        hair, hl = self.look.hair, lw * 0.8
        Rp = r + 2.6

        def cloud(a0, a1, nb, amp=0.09, k=1.0):
            out = []
            n = nb * 6
            for i in range(n + 1):
                tt = i / n
                a = math.radians(a0 + (a1 - a0) * tt)
                m = 1 + amp * abs(math.sin(math.pi * tt * nb))
                out.append((Rp * 1.04 * k * m * math.cos(a), Rp * k * m * math.sin(a)))
            return out

        def bumps(p0, p1, nb, amp=1.6):
            out = []
            n = nb * 5
            dx, dy = p1[0] - p0[0], p1[1] - p0[1]
            L = math.hypot(dx, dy) or 1
            nx, ny = dy / L, -dx / L
            for i in range(n + 1):
                tt = i / n
                b = amp * abs(math.sin(math.pi * tt * nb))
                out.append((p0[0] + dx * tt + nx * b, p0[1] + dy * tt + ny * b))
            return out

        if view == "front":
            part(s, cloud(150, 390, 9), hair, hl)
            part(s, ell(0, 0, rx, ry), SKIN, lw)
            self.face_front(eyes, mouth)
            fr = cloud(168, 372, 8) + bumps((0.88 * rx, 0.12 * r), (0.62 * rx, -0.3 * r), 1) + bumps((0.62 * rx, -0.3 * r), (-0.62 * rx, -0.3 * r), 4) + bumps((-0.62 * rx, -0.3 * r), (-0.88 * rx, 0.12 * r), 1)
            part(s, fr, hair, hl, amp=0.2)
            spots = [(-0.5, -0.66), (0.15, -0.8), (0.62, -0.55)]
        elif view == "back":
            part(s, ell(0, 0, rx, ry), SKIN, lw)
            pts = cloud(150, 390, 10) + bumps((0.97 * Rp, 0.4 * r), (-0.97 * Rp, 0.4 * r), 5, -1.6)
            part(s, pts, hair, hl, amp=0.2)
            spots = [(-0.5, -0.5), (0.1, -0.7), (0.55, -0.35), (-0.2, 0.05), (0.35, 0.15)]
        else:
            part(s, ell(0, 0, rx, ry), SKIN, lw)
            self.face_side(eyes, mouth)
            pts = cloud(336, 150, 9) + [(-0.6 * rx, 0.5 * r), (-0.1 * rx, 0.3 * r)] + bumps((0.0, 0.05 * r), (0.98 * rx, -0.32 * r), 3)
            part(s, pts, hair, hl, amp=0.2)
            spots = [(-0.5, -0.45), (0.0, -0.72), (-0.65, 0.05)]
        for x, y in spots:
            s.ink.line(arc_pts(x * rx, y * r, 1.6, 1.5, 200, 470, 8), w=1.0, amp=0, density=0.9)
        if eyes != "closed" and view == "front":
            pass

    def shine(self, R, a0, a1):
        """头发上一道留白的高光（只在墨实地的头发上）。"""
        if self.look.hair[1] is not None:
            # 白头发：几道细细的发丝
            for da in (-16, 4, 22):
                self.s.ink.line(arc_pts(0, 0, R * 0.68, R * 0.64, a0 + da, a1 + da - 6, 5), w=0.9, amp=0, density=0.85)
            return
        stroke_clear(self.s, arc_pts(0, 0, R * 0.74, R * 0.72, a0, a1, 6), 1.3, colors=("ink",))

    def ahoge(self, x, y, d=1):
        k = self.r / 14.0
        pts = [(x, y + 1), (x + d * 1.8 * k, y - 3.5 * k), (x + d * 0.6 * k, y - 7.2 * k), (x - d * 2.2 * k, y - 7.6 * k), (x - d * 3.0 * k, y - 5.4 * k)]
        hair = self.look.hair
        if hair[0] == "paper":
            tube(self.s, pts, 1.3, SKIN, self.lw * 0.55, amp=0)
        else:
            self.s.ink.line(pts, w=self.lw * 0.95, amp=0.2)

    def clip_pin(self, x, y, ang):
        """梅小时候的发夹：一颗小小的青色。"""
        pts = rotate(rrect(x - 3.2, y - 1.5, 6.4, 3.0, 1.4), ang, (x, y))
        part(self.s, pts, solid("qing"), 1.1, amp=0)

    def eye(self, x, y, kind):
        s, r = self.s, self.r
        er = r * (0.14 if self.stage == "child" else 0.12)
        if kind == "open":
            s.ink.dot(x, y, er)
        elif kind == "happy":
            s.ink.line(arc_pts(x, y + 0.9, 2.1, 2.0, 200, 340, 6), w=1.4, amp=0)
        else:  # closed
            s.ink.line(arc_pts(x, y - 0.9, 2.1, 1.8, 20, 160, 6), w=1.4, amp=0)

    def face_front(self, eyes, mouth):
        s, r = self.s, self.r
        rx = r * 1.06
        ex = rx * (0.40 if self.stage != "child" else 0.42)
        ey = r * (0.2 if self.stage == "child" else 0.13)
        for sd in (-1, 1):
            self.eye(sd * ex, ey, eyes)
            s.pen("mei", 0.25).fill(ell(sd * rx * 0.54, r * 0.46, r * 0.18, r * 0.12))
        my = r * (0.5 if self.stage == "child" else 0.45)
        if mouth == "open":
            pts = [(-2.3, my - 0.4), (2.3, my - 0.4)] + arc_pts(0, my - 0.4, 2.3, 2.4, 0, 180, 8)
            s.ink.poly(pts, w=0.8, fill=True, amp=0)
        else:
            s.ink.line(arc_pts(0, my - 1.3, 1.7, 1.4, 30, 150, 6), w=1.3, amp=0)

    def face_side(self, eyes, mouth):
        s, r = self.s, self.r
        rx = r * 1.06
        ey = r * (0.2 if self.stage == "child" else 0.13)
        self.eye(rx * 0.56, ey, eyes)
        s.pen("mei", 0.25).fill(ell(rx * 0.5, r * 0.46, r * 0.17, r * 0.12))
        my = r * (0.5 if self.stage == "child" else 0.45)
        s.ink.line(arc_pts(rx * 0.84, my - 1.2, 1.3, 1.2, 40, 140, 5), w=1.2, amp=0)

    def glasses_front(self):
        s, r = self.s, self.r
        rx = r * 1.06
        ex, ey = rx * 0.40, r * 0.13
        g = r * 0.27
        for sd in (-1, 1):
            s.ink.poly(ell(sd * ex, ey + 0.5, g, g * 0.85, 18), w=1.2, amp=0)
            s.ink.line([(sd * (ex + g), ey), (sd * (rx + 0.3), ey - 1.0)], w=1.1, amp=0)
        s.ink.line(arc_pts(0, ey + 0.2, ex - g, 1.2, 200, 340, 4), w=1.1, amp=0)

    def glasses_side(self):
        s, r = self.s, self.r
        rx = r * 1.06
        ex, ey = rx * 0.58, r * 0.13
        g = r * 0.25
        s.ink.poly(ell(ex, ey + 0.5, g * 0.7, g * 0.85, 16), w=1.2, amp=0)
        s.ink.line([(ex - g * 0.7, ey), (-0.12 * rx, ey - 0.5)], w=1.1, amp=0)

    # ------------------------------------------------------------------
    # 手里的东西
    # ------------------------------------------------------------------
    def prop(self, cx, cy):
        s, lw = self.s, self.lw * 0.85
        w = self.prop_w()
        if self.role == "qing":
            # 一碗热汤面：碗沿一道梅色，冒热气，插着筷子
            h = w * 0.48
            rim = cy - h * 0.3
            for k in (-1, 1):
                s.ink.line([(cx + 1.5 * k, rim - 2.5), (cx + 0.2 * k + 0.5, rim - 5.5), (cx + 1.8 * k, rim - 8.5), (cx + 0.6 * k, rim - 11.5)], w=1.2, amp=0, density=0.7)
            s.ink.line([(cx + w * 0.05, rim + 1), (cx + w * 0.55, rim - 9.5)], w=1.4, amp=0)
            s.ink.line([(cx + w * 0.16, rim + 1), (cx + w * 0.68, rim - 8.0)], w=1.4, amp=0)
            part(s, rrect(cx - w * 0.17, rim + h - 1.2, w * 0.34, 2.6, 0.8), SKIN, lw)
            body = arc_pts(cx, rim, w / 2, h, 180, 0, 14)
            part(s, body, SKIN, lw)
            with s.clip(body):
                s.pen("mei").fill(rect_pts(cx - w, rim + h * 0.28, 2 * w, 2.0))
            part(s, ell(cx, rim, w / 2, 1.9, 18), tint("ink", 0.4), lw * 0.8, occlude=False)
        else:
            # 一小盆绿植：青色的叶子
            top = cy - 1.5
            bot = cy + w * 0.5
            for ang, L in ((-38, w * 0.55), (32, w * 0.6), (-4, w * 0.75)):
                base = (cx, top - 1)
                tip = polar(base, 180 + ang, L)
                mid = lerp(base, tip, 0.5)
                d = math.dist(base, tip)
                leaf = rotate(ell(mid[0], mid[1], d / 2, d * 0.2, 14), math.degrees(math.atan2(tip[1] - base[1], tip[0] - base[0])) - 0, mid)
                part(s, leaf, solid("qing"), 1.3, amp=0.2)
                s.ink.line([base, lerp(base, tip, 0.8)], w=0.9, amp=0)
            pot = [(cx - w / 2, top), (cx + w / 2, top), (cx + w * 0.36, bot), (cx - w * 0.36, bot)]
            part(s, pot, tint("ink", 0.45), lw)
            part(s, rrect(cx - w / 2 - 1, top - 2.2, w + 2, 3.2, 1.0), SKIN, lw * 0.9)

    def prop_w(self):
        return max(15.0, self.sw * 1.6)

    def cane_draw(self, top, tip, d):
        """拐杖：墨实地，弯钩朝 d 一侧。"""
        s = self.s
        tip = (tip[0], tip[1] - 1.2)
        s.ink.line([top, tip], w=2.4, amp=0.2)
        c = (top[0] + d * 2.3, top[1])
        hook = arc_pts(c[0], c[1], 2.3, 2.3, 180, 360, 8) if d > 0 else arc_pts(c[0], c[1], 2.3, 2.3, 0, -180, 8)
        s.ink.line(hook + [(c[0] + d * 2.3, top[1] + 1.8)], w=2.4, amp=0)

    # ------------------------------------------------------------------
    # 服装细节
    # ------------------------------------------------------------------
    def deco_torso(self, view, tp, sy, hy, hem, shx=0.0):
        """画在躯干上、胳膊下面的东西。"""
        s, lw, T, C = self.s, self.lw, hy - sy, self.C
        st, role = self.stage, self.role
        thin = lw * 0.55
        side = view == "side"
        d = self.dw
        fx = (d + shx) if side else 0.0  # 侧面时衣服前襟的位置
        with s.clip(tp):
            if st == "teen":
                yk = sy + T * 0.32
                s.clear(rect_pts(-40, sy - 8, 80, yk - sy + 8), colors=(C,))
                s.ink.line([(-30, yk), (30, yk)], w=thin, amp=0.3)
                if view == "front":
                    s.ink.line([(0, sy + 4), (0, hem + 1)], w=1.3, amp=0)
                elif side:
                    s.ink.line([(fx - 1.5, sy + 4), (d - 1.2, hem + 1)], w=1.3, amp=0)
            elif st == "young" and role == "qing":
                s.ink.line([(-30, hy - 0.8), (30, hy - 0.8)], w=2.0, amp=0.2)
                if view == "front":
                    s.ink.line([(0, sy + 3), (0, hy - 1.5)], w=1.0, amp=0, density=0.8)
                    for k in range(4):
                        y = sy + 6 + k * (T - 8) / 3.5
                        if y < hy - 2.5:
                            s.ink.dot(1.4, y, 0.75)
                    part(s, rrect(-2, hy - 2.2, 4, 3, 0.6), SKIN, 1.0)
                elif view == "back":
                    s.ink.line([(-30, sy + T * 0.22), (30, sy + T * 0.22)], w=thin, amp=0.3)
            elif st == "middle" and role == "qing":
                band = hem - 3.4
                s.pen("ink", 0.35).fill(rect_pts(-40, band, 80, 6))
                s.ink.line([(-40, band), (40, band)], w=thin, amp=0.2)
                if view == "front":
                    s.ink.line([(0, sy + 5), (0, hem + 1)], w=1.3, amp=0)
                    for sd in (-1, 1):
                        s.ink.line([(sd * (self.hw - 4.5), hy - 9), (sd * (self.hw - 2.0), hy - 3.5)], w=1.2, amp=0)
                elif side:
                    s.ink.line([(fx - 1.6, sy + 4), (d - 1.3, hem + 1)], w=1.3, amp=0)
                    s.ink.line([(shx * 0.3 + 0.5, hy - 9), (shx * 0.2 + 2.5, hy - 3.5)], w=1.2, amp=0)
                else:
                    s.ink.line([(-30, sy + T * 0.25), (30, sy + T * 0.25)], w=thin, amp=0.3)
            elif st == "old" and role == "qing":
                s.ink.line([(-40, hem - 3), (40, hem - 3)], w=thin, amp=0.2)
                if view == "front":
                    vy = sy + T * 0.45
                    s.ink.line([(0, vy), (0, hem + 1)], w=1.1, amp=0)
                    for k in range(3):
                        s.ink.dot(1.6, vy + 2.5 + k * 5, 0.9)
                    for sd in (-1, 1):
                        x0 = sd * (self.hw - 1.2) - (5.5 if sd > 0 else 0)
                        part(s, rrect(x0, hy - 9, 5.5, 5, 1), self.look.top, thin, occlude=False)
                elif side:
                    s.ink.line([(fx - 1.6, sy + 4), (d - 1.2, hem + 1)], w=1.1, amp=0)
                    part(s, rrect(shx * 0.2 - 1, hy - 9, 5.5, 5, 1), self.look.top, thin, occlude=False)
            elif st == "young" and role == "mei":
                wy = sy + T * 0.8
                for yy in (wy - 1.6, wy + 1.6):
                    s.ink.line([(-40, yy), (40, yy)], w=1.1, amp=0.2)
                if view == "front":
                    for yy in (sy + T * 0.48, sy + T * 0.64):
                        for sd in (-1, 1):
                            s.ink.dot(sd * 3.0, yy, 0.9)
                    s.ink.line([(0.5, wy + 1.6), (1.2, hem + 1)], w=1.1, amp=0)
                    part(s, rrect(-2.3, wy - 2.3, 4.6, 4.6, 0.8), SKIN, 1.1)
                    s.ink.line([(1.6, wy + 1.5), (3.0, wy + 6.5)], w=1.6, amp=0)
                elif view == "back":
                    s.ink.line([(0, hy + 1), (0, hem + 1)], w=1.1, amp=0)
                    s.ink.line([(-30, sy + T * 0.25), (30, sy + T * 0.25)], w=thin, amp=0.3)
                else:
                    s.ink.line([(d + 0.2, wy + 1.6), (d + 2.0, hem + 1)], w=1.1, amp=0)
                    part(s, rrect(d * 0.1 - 2.3, wy - 2.3, 4.6, 4.6, 0.8), SKIN, 1.1)
            elif st == "middle" and role == "mei":
                band = hem - 3.6
                s.pen("mei").fill(rect_pts(-40, band, 80, 6))
                s.ink.line([(-40, band), (40, band)], w=thin, amp=0.2)
                yy = sy + T * 0.34
                for k in range(-6, 7):
                    s.pen("mei").dot(k * 3.4 + (0 if view != "side" else shx * 0.6), yy, 1.15)
                for k in range(-6, 7):
                    s.pen("mei").dot(k * 3.4 + 1.7 + (0 if view != "side" else shx * 0.6), yy + 3.0, 0.7)
            elif st == "old" and role == "mei":
                s.ink.line([(-40, hem - 3), (40, hem - 3)], w=thin, amp=0.2)

        # 衣领、领口（盖在躯干上面）
        if view == "front":
            if st == "teen":
                part(s, [(-3.8, sy - 1.0), (3.8, sy - 1.0), (0, sy + 4.4)], SKIN, thin)
            elif st == "young" and role == "qing":
                for sd in (-1, 1):
                    part(s, [(sd * 0.4, sy + 0.6), (sd * 5.8, sy - 1.0), (sd * 4.4, sy + 4.2)], SKIN, thin)
            elif st == "middle" and role == "qing":
                part(s, [(-3.6, sy - 1.0), (3.6, sy - 1.0), (0, sy + 6)], SKIN, thin)
                for sd in (-1, 1):
                    part(s, [(sd * 3.4, sy - 1.6), (sd * 7.6, sy + 0.2), (sd * 1.2, sy + 6.8)], solid("qing"), thin)
            elif st == "old" and role == "qing":
                part(s, [(-4.4, sy - 1.0), (4.4, sy - 1.0), (0, sy + T * 0.45)], SKIN, thin)
            elif st == "young" and role == "mei":
                part(s, [(-4.4, sy - 1.0), (4.4, sy - 1.0), (0, sy + T * 0.38)], SKIN, thin)
                for sd in (-1, 1):
                    part(s, [(sd * 4.2, sy - 1.6), (sd * (self.sw - 2.2), sy + 1.2), (sd * 1.0, sy + T * 0.37)], solid("mei"), thin)
            elif st == "middle" and role == "mei":
                part(s, rrect(-5.0, sy - 1.8, 10.0, 3.4, 1.6), solid("mei"), thin)
            elif st == "old" and role == "mei":
                pass
        elif view == "side":
            if st == "teen" or (st == "young" and role == "qing"):
                part(s, [(fx - 3.6, sy - 1.2), (fx + 0.4, sy - 0.2), (fx - 1.4, sy + 3.2)], SKIN, thin)
            elif st == "middle" and role == "qing":
                part(s, [(fx - 5.0, sy - 1.8), (fx + 0.2, sy - 0.4), (fx - 2.6, sy + 5.5)], solid("qing"), thin)
            elif st == "middle" and role == "mei":
                part(s, rrect(fx - 7.5, sy - 1.8, 7.0, 3.2, 1.5), solid("mei"), thin)
            elif st == "young" and role == "mei":
                part(s, [(fx - 5.5, sy - 1.8), (fx + 0.6, sy - 0.2), (fx - 1.2, sy + T * 0.34)], solid("mei"), thin)
        else:  # back
            if st == "middle" and role == "mei":
                part(s, rrect(-5.0, sy - 1.8, 10.0, 3.0, 1.4), solid("mei"), thin)
            elif st == "middle" and role == "qing":
                part(s, rrect(-6.0, sy - 2.2, 12.0, 4.0, 1.6), solid("qing"), thin)
            elif st == "young" and role == "qing":
                part(s, rrect(-5.0, sy - 2.0, 10.0, 3.2, 1.2), tint("qing", 0.78), thin)
            elif st == "young" and role == "mei":
                part(s, rrect(-6.0, sy - 2.2, 12.0, 4.0, 1.6), solid("mei"), thin)

        # 书包背带（梅·童年，在胳膊下）
        if role == "mei" and st == "child":
            if view == "front":
                for sd in (-1, 1):
                    tube(s, [(sd * self.sw * 0.36, sy - 0.8), (sd * self.sw * 0.3, sy + T * 0.5)], 1.8, solid("qing"), 1.1, amp=0)
            elif side:
                self.backpack_side(sy, hy, shx)
                tube(s, [(-d * 0.4 + shx, sy + 0.2), (shx + 1.5, sy + 0.6), (fx - 1.2, sy + T * 0.55)], 1.8, solid("qing"), 1.1, amp=0)

    def backpack_side(self, sy, hy, shx):
        s, T, d = self.s, hy - sy, self.dw
        x0 = -d - 5.8 + shx * 0.35
        body = rrect(x0, sy + 1.2, 7.2, T - 2.0, 3.0)
        part(s, body, tint("qing", 0.72), self.lw * 0.8)
        part(s, rrect(x0 - 0.4, sy + 0.8, 7.6, T * 0.45, 3.0), solid("qing"), self.lw * 0.7)

    def deco_over(self, view, sy, hy, shx=0.0):
        """盖在胳膊上面、头下面的东西（红领巾、书包、披肩）。"""
        s, lw, T = self.s, self.lw, hy - sy
        st, role = self.stage, self.role
        d = self.dw
        if role == "qing" and st == "child":
            m = solid("mei")
            if view == "front":
                part(s, rrect(-5.8, sy - 1.8, 11.6, 3.4, 1.6), m, 1.2)
                part(s, [(0, sy + 1.0), (-4.2, sy + 8.6), (-1.0, sy + 9.0)], m, 1.2)
                part(s, [(0.6, sy + 1.0), (3.4, sy + 9.6), (5.6, sy + 8.0)], m, 1.2)
                part(s, ell(0.3, sy + 1.4, 2.1, 1.9), m, 1.2)
            elif view == "back":
                part(s, [(-7.0, sy - 1.2), (7.0, sy - 1.2), (0, sy + 8.5)], m, 1.2)
            else:
                fx = d + shx
                part(s, [(-1.0 + shx * 0.5, sy - 1.0), (-d - 1.2, sy), (-d * 0.4, sy + 6.5)], m, 1.2)
                part(s, rrect(-d * 0.2 + shx * 0.6, sy - 2.0, d + 1.5, 3.2, 1.4), m, 1.2)
                part(s, [(fx - 1.5, sy + 0.5), (fx + 2.2, sy + 8.0), (fx + 0.2, sy + 8.8)], m, 1.2)
                part(s, ell(fx - 1.0, sy + 0.8, 2.0, 1.8), m, 1.2)
        if role == "mei" and st == "child" and view == "back":
            sw = self.sw
            body = rrect(-sw + 1.6, sy + 1.6, 2 * sw - 3.2, T - 2.6, 3.5)
            part(s, body, tint("qing", 0.72), lw * 0.85)
            part(s, rrect(-sw + 1.2, sy + 1.2, 2 * sw - 2.4, T * 0.42, 3.5), solid("qing"), lw * 0.8)
            part(s, rrect(-1.6, sy + T * 0.36, 3.2, 3.4, 0.8), SKIN, 1.0)
        if role == "mei" and st == "old":
            self.shawl(view, sy, hy, shx)

    def shawl(self, view, sy, hy, shx):
        s, lw, T, sw, d = self.s, self.lw, hy - sy, self.sw, self.dw
        m = solid("mei")
        if view == "front":
            pts = [(-sw * 0.42, sy - 1.4), (-sw - 2.6, sy + 1.6), (-sw - 4.2, sy + T * 0.5), (-sw * 0.3, sy + T * 0.58),
                   (0, sy + T * 0.7), (sw * 0.3, sy + T * 0.58), (sw + 4.2, sy + T * 0.5), (sw + 2.6, sy + 1.6), (sw * 0.42, sy - 1.4), (0, sy + 1.2)]
            edge = [pts[2], pts[3], pts[4], pts[5], pts[6]]
        elif view == "back":
            pts = [(-sw * 0.42, sy - 1.8), (sw * 0.42, sy - 1.8), (sw + 2.6, sy + 1.6), (sw + 4.2, sy + T * 0.5), (0, sy + T * 0.72), (-sw - 4.2, sy + T * 0.5), (-sw - 2.6, sy + 1.6)]
            edge = [pts[3], pts[4], pts[5]]
        else:
            pts = [(-d * 0.6 + shx, sy - 1.8), (d * 0.3 + shx, sy - 1.6), (d + shx + 1.6, sy + 1.0), (d + shx * 0.6 + 2.6, sy + T * 0.46),
                   (shx * 0.4, sy + T * 0.5), (-d - 2.4, sy + T * 0.56), (-d - 1.8 + shx * 0.3, sy + 1.0)]
            edge = [pts[3], pts[4], pts[5]]
        sm = chaikin(pts, 1)
        part(s, sm, m, lw * 0.9)
        # 流苏
        for i in range(len(edge) - 1):
            a, b = edge[i], edge[i + 1]
            n = max(2, int(math.dist(a, b) / 2.6))
            for k in range(n):
                p = lerp(a, b, (k + 0.5) / n)
                s.ink.line([add(p, 0, 0.6), add(p, 0, 3.2)], w=1.0, amp=0)
        if view == "front":
            part(s, ell(0, sy + 3.4, 1.9, 1.9), solid("qing"), 1.0)

    # ------------------------------------------------------------------
    # 姿势：正面 / 背面
    # ------------------------------------------------------------------
    def draw_front(self, kind="stand", phase=0, back=False):
        s, lk, lw = self.s, self.look, self.lw
        L, T, sw, A = self.L, self.T, self.sw, self.A
        walk = kind == "walk"
        stride = walk and phase in (0, 2)
        bob = 1.5 if stride else 0.0
        hy = -L + bob
        sy = hy - T
        hem = hy + lk.hem
        lx = self.hw * 0.45
        view = "back" if back else "front"

        # 腿：迈步时后脚跟抬起
        lift = {-1: 0.0, 1: 0.0}
        fwd = 0
        if stride:
            fwd = 1 if phase == 0 else -1  # 正面：角色的左 = 画面 +x
            if back:
                fwd = -fwd
            lift[-fwd] = 2.4
        for sd in sorted((-1, 1), key=lambda k: -lift[k]):
            hip = (sd * lx, hy - 2.5)
            ank = (sd * lx * 1.06, -4.0 - lift[sd])
            self.leg([hip, lerp(hip, ank, 0.5), ank], view, side=sd)

        # 胳膊
        arms = []  # (pts, under_torso, hand)
        cs = (-1 if not back else 1) if self.cane else 0
        busy = kind == "busy"
        for sd in (-1, 1):
            S = (sd * (sw - 2.6), sy + 3.6)
            if busy:
                E = (sd * (sw + 1.2), sy + 3.6 + A * 0.5)
                W = (sd * (self.prop_w() / 2 + 0.5), sy + 3.6 + A * 0.4)
                if back:
                    arms.append(([S, E, (sd * (sw - 1.5), E[1] - 1.5)], True, False))
                else:
                    arms.append(([S, E, W], False, False))
                continue
            if kind == "wave" and sd == 1:
                E = (sw + 6.0, sy + 0.5)
                W = (sw + 7.5, sy - A * 0.42)
                arms.append(([S, E, W], False, "wave"))
                continue
            if sd == cs:
                cl = 2.0 if (walk and not stride) else 0.0
                E = (sd * (sw + 2.4), sy + 3.6 + A * 0.45 - cl * 0.5)
                W = (sd * (sw + 3.6), sy + 3.6 + A * 0.8 - cl)
                arms.append(([S, E, W], False, "cane"))
                continue
            if self.behind:
                E = (sd * (sw + 0.8), sy + 3.6 + A * 0.42)
                if back:
                    W = (sd * 2.2, hy - 3.0)
                    arms.append(([S, E, W], False, "clasp"))
                else:
                    arms.append(([S, E, (sd * (self.hw * 0.4), hy - 3.0)], True, False))
                continue
            W = (sd * (sw + 1.2), sy + 3.6 + A)
            if stride:
                if sd == -fwd:   # 和迈出的腿相反的手往前摆：看起来短一点
                    W = (W[0] - sd * 1.4, W[1] - 3.6)
                else:
                    W = (W[0] + sd * 0.6, W[1] - 1.0)
            E = lerp(S, W, 0.5)
            E = (E[0] + sd * 0.9, E[1])
            arms.append(([S, E, W], False, True))

        for pts, under, hd in arms:
            if under:
                self.arm(pts, hand=False)
        self.neck(0, sy)
        tp = self.torso_front(sy, hy, hem)
        part(s, tp, lk.top, lw)
        self.deco_torso(view, tp, sy, hy, hem)
        clasp = None
        for pts, under, hd in arms:
            if under:
                continue
            if hd == "cane":
                W = pts[-1]
                self.arm(pts, hand=False)
                self.cane_draw((W[0], W[1] - 2.5), (W[0] + cs * 1.4, -((2.0 if (walk and not stride) else 0.0))), -cs if not back else -cs)
                self.hand(W)
            elif hd == "wave":
                self.arm(pts, hand=False)
                self.hand(pts[-1], k=1.15)
                W = pts[-1]
                for rr in (4.5, 7.0):
                    s.ink.line(arc_pts(W[0], W[1], rr, rr, -60, 10, 6), w=1.2, amp=0, density=0.85)
            elif hd == "clasp":
                self.arm(pts, hand=False)
                clasp = pts[-1]
            else:
                self.arm(pts, hand=bool(hd))
        if clasp is not None:
            part(s, ell(0, clasp[1], self.hr * 1.5, self.hr * 1.1), SKIN, lw * 0.85)
        self.deco_over(view, sy, hy)
        if busy and not back:
            cy = sy + 3.6 + A * 0.4 - 1.0
            self.prop(0, cy)
            for pts, _, _ in arms:
                self.hand(pts[-1])
            if self.cane:  # 拐杖挂在小臂上
                W = arms[0][0][-1]
                s.ink.line([(W[0] - 2.5, W[1] + 1.0), (W[0] - 3.2, W[1] + 30)], w=2.4, amp=0.2)
        hcy = sy - self.n - self.r * 0.95 + self.hunch * 0.5
        eyes = "happy" if kind == "wave" else "open"
        mouth = "open" if kind == "wave" else "smile"
        with place(s, 0, hcy):
            self.head(view, eyes, mouth)

    # ------------------------------------------------------------------
    # 侧面（朝右）
    # ------------------------------------------------------------------
    def draw_side(self, kind="stand", phase=0):
        s, lk, lw = self.s, self.look, self.lw
        L, T, A = self.L, self.T, self.A
        walk = kind == "walk"
        stride = walk and phase in (0, 2)
        bob = 1.5 if stride else 0.0
        hy = -L + bob
        sy = hy - T
        shx = self.hunch
        hem = hy + lk.hem
        Lleg = L - 4.0
        hip = (0.0, hy - 1.0)
        Lleg_eff = Lleg - 1.0

        def straight(ang, x0=0.0):
            h = (hip[0] + x0, hip[1])
            k = polar(h, ang, Lleg_eff / 2)
            return [h, k, polar(k, ang, Lleg_eff / 2)]

        # 腿
        legs = {}
        if stride:
            th = math.degrees(math.acos(max(-1, min(1, (Lleg_eff - bob) / Lleg_eff))))
            th = max(th, 14.0)
            near_fwd = phase == 0
            legs["near"] = (straight(th if near_fwd else -th), 0.0)
            legs["far"] = (straight(-th if near_fwd else th), 0.0)
        elif walk:
            swing = "far" if phase == 1 else "near"
            sup = "near" if swing == "far" else "far"
            legs[sup] = (straight(0.0), 0.0)
            h = hip
            k = polar(h, 22, Lleg_eff / 2)
            legs[swing] = ([h, k, polar(k, -38, Lleg_eff / 2)], 28.0)
        else:
            legs["far"] = (straight(0.0, -1.6), 0.0)
            legs["near"] = (straight(0.0, 1.0), 0.0)
        # 腿脚落地：直腿的脚踝钉在 y=-4
        for key, (pts, rot) in legs.items():
            if rot == 0.0:
                dy = -4.0 - pts[-1][1]
                legs[key] = ([pts[0]] + [(x, y + dy * (i / (len(pts) - 1))) for i, (x, y) in enumerate(pts[1:], 1)], rot)

        # 胳膊
        S = (shx * 0.9 + 0.3, sy + 3.6)
        Sf = (S[0] - 1.4, S[1] - 0.4)
        busy = kind == "busy"
        if busy:
            near = (6.0, 80.0)
            far = (2.0, 78.0)
        elif stride:
            a = -32.0 if phase == 0 else 32.0
            near = (a, a + (18.0 if a > 0 else 6.0))
            far = (-a, -a + (18.0 if -a > 0 else 6.0))
        elif walk:
            near, far = (4.0, 12.0), (-3.0, 3.0)
        else:
            near, far = (2.0, 9.0), (-2.0, 5.0)
        if self.behind and not busy:
            near = (-12.0, -78.0)
            far = None
        cane_tip = None
        if self.cane and not busy:
            sw_ = {0: -4.0, 1: 2.0, 2: 6.0, 3: 2.0}.get(phase, 0.0) if walk else 0.0
            near = (16.0 + sw_, 30.0 + sw_)
            if walk and stride:
                far = (-8.0 if phase == 0 else 8.0, (-8.0 if phase == 0 else 8.0) + 10)
            elif walk:
                far = (0.0, 6.0)

        def arm_pts(S0, ang):
            E = polar(S0, ang[0], A * 0.5)
            return [S0, E, polar(E, ang[1], A * 0.5)]

        if far is not None:
            self.arm(arm_pts(Sf, far), hand=not busy, shade=0.18)
        for key in ("far", "near"):
            pts, rot = legs[key]
            self.leg(pts, "side", rot, shade=0.18 if key == "far" else 0.0)
        self.neck(shx * 1.1 + 0.3, sy)
        flare = 1.2 if (lk.coat and stride) else 0.0
        tp = self.torso_side(sy, hy, hem, shx, flare)
        part(s, tp, lk.top, lw)
        self.deco_torso("side", tp, sy, hy, hem, shx)
        npts = arm_pts(S, near)
        if busy:
            W = npts[-1]
            self.arm(npts, hand=False)
            self.deco_over("side", sy, hy, shx)
            self.prop(W[0] + self.prop_w() * 0.32, W[1] - 1.0)
            self.hand(W)
            if self.cane:
                s.ink.line([(W[0] - 1.0, W[1] + 1.0), (W[0] - 1.6, W[1] + 30)], w=2.4, amp=0.2)
        elif self.cane:
            W = npts[-1]
            lift = 1.8 if (walk and not stride) else 0.0
            cane_tip = (W[0] + 3.5, -lift)
            self.arm(npts, hand=False)
            self.cane_draw((W[0], W[1] - 2.5), cane_tip, 1)
            self.hand(W)
        else:
            self.arm(npts, hand=True)
        if not busy:
            self.deco_over("side", sy, hy, shx)
        hcx = shx * 1.35 + 1.4
        hcy = sy - self.n - self.r * 0.95 + self.hunch * 0.5
        with place(s, hcx, hcy):
            self.head("side")

    # ------------------------------------------------------------------
    # 行 3
    # ------------------------------------------------------------------
    def draw_sleep(self):
        with place(self.s, 0, -1.4):
            self._sleep()

    def _sleep(self):
        s, lw, r = self.s, self.lw, self.r
        Lq = min(self.H * 0.92, 76.0)
        x0 = -Lq / 2
        # 枕头
        pil = rrect(x0 - 3, -7.5, 2 * r + 6, 7.5, 3.2)
        part(s, pil, SKIN, lw * 0.85)
        for k in (0.35, 0.65):
            s.ink.line([(x0 - 3 + (2 * r + 6) * k, -5.6), (x0 - 3 + (2 * r + 6) * k + 2.5, -2.0)], w=1.0, amp=0, density=0.7)
        hk = 0.86
        r = r * hk
        hcx, hcy = x0 + r + 1.5, -7.0 - r * 0.8
        with place(s, hcx, hcy, -58, hk):
            self.head("front", "closed", "smile")
        # 被子：角色色，留白小花点
        hq = self.sw * 2.2 + 5
        qx0 = hcx + r * 0.42
        qx1 = Lq / 2 + 1.5
        W = qx1 - qx0
        ctrl = [(qx0, 0.0), (qx0 - 1.5, -hq * 0.55), (qx0 + 1.5, -hq * 0.92), (qx0 + W * 0.22, -hq * 1.02), (qx0 + W * 0.48, -hq * 0.74),
                (qx0 + W * 0.72, -hq * 0.9), (qx0 + W * 0.92, -hq * 0.62), (qx1 + 1.0, -hq * 0.25), (qx1, 0.0)]
        quilt = chaikin(ctrl, 3)
        part(s, quilt, solid(self.C), lw)
        with s.clip(quilt):
            for iy in range(0, 6):
                for ix in range(0, 16):
                    x = qx0 + 4 + ix * 5.6 + (2.8 if iy % 2 else 0)
                    y = -3.5 - iy * 5.0
                    if self.role == "qing":
                        s.clear(rect_pts(x - 1.4, y - 0.4, 2.8, 0.8), colors=(self.C,))
                        s.clear(rect_pts(x - 0.4, y - 1.4, 0.8, 2.8), colors=(self.C,))
                    else:
                        s.clear(ell(x, y, 0.95, 0.95, 8), colors=(self.C,))
            s.ink.line([(qx0 - 5, -0.8), (qx1 + 5, -0.8)], w=lw, amp=0.2)
        # 被头翻过来的一道白边
        fold = chaikin([(qx0 - 1.0, -0.5), (qx0 - 2.2, -hq * 0.55), (qx0 + 0.8, -hq * 0.95), (qx0 + 5.0, -hq * 0.98), (qx0 + 3.2, -hq * 0.5), (qx0 + 4.0, -0.5)], 2)
        part(s, fold, SKIN, lw * 0.85)
        self.hand((qx0 + 4.5, -hq * 0.62), k=0.95)

    def draw_sit(self):
        s, lk, lw = self.s, self.look, self.lw
        L, T, sw, A = self.L, self.T, self.sw, self.A
        hs = round(L * 0.6 + 1.5)
        hy = -hs
        sy = hy - T
        lx = self.hw * 0.48
        # 小腿
        for sd in (-1, 1):
            kn = (sd * lx * 1.15, hy + 3.0)
            ank = (sd * lx * 1.25, -4.0)
            spec = SKIN if lk.pants_len < 1 else lk.pants
            tube(s, [kn, ank], self.lgw - (1.6 if lk.pants_len < 1 else 0), spec, lw)
            if self.stage == "teen":
                stroke_clear(s, [(kn[0] + sd * self.lgw * 0.28, kn[1] + 2), (ank[0] + sd * self.lgw * 0.28, ank[1] - 1)], 1.5, colors=(self.C,))
            self.shoe(ank, "front")
        if self.cane:
            self.cane_draw((-(sw + 2.5), hy - 7.0), (-(sw + 5.5), -0.5), 1)
        arms = []
        for sd in (-1, 1):
            S = (sd * (sw - 2.6), sy + 3.6)
            E = (sd * (sw + 1.6), sy + 3.6 + A * 0.5)
            W = (sd * (lx * 1.1 + 0.5), hy - 0.5)
            arms.append([S, E, W])
        self.neck(0, sy)
        tp = self.torso_front(sy, hy, hy + 1.5)
        part(s, tp, lk.top, lw)
        self.deco_torso("front", tp, sy, hy, hy + 1.5)
        # 大腿朝镜头：一块圆圆的"膝盖面"，中间一道缝（风衣就是衣摆）
        spec = lk.top if lk.coat else lk.pants
        kw = lx * 1.15 + (self.lgw + lw) / 2 + 0.6
        lap = rrect(-kw, hy - 2.5, 2 * kw, 7.0, 3.2)
        part(s, lap, spec, lw)
        s.ink.line([(0, hy - 1.0), (0, hy + 4.0)], w=1.3, amp=0)
        for pts in arms:
            self.arm(pts)
        self.deco_over("front", sy, hy)
        hcy = sy - self.n - self.r * 0.95 + self.hunch * 0.5
        with place(s, 0, hcy):
            self.head("front")


# ----------------------------------------------------------------------
# 出图
# ----------------------------------------------------------------------

def build(role, stage, out_dir=OUT_DIR):
    s = Sheet(CELL_W * COLS, CELL_H * ROWS, scale=SCALE, seed=11)
    f = Fig(s, role, stage)

    def cell(col, row, fn, *a, **kw):
        s._seed = 1000  # 每格同一套抖动种子：走路时线条不会"沸腾"
        with place(s, col * CELL_W + FOOT[0], row * CELL_H + FOOT[1]):
            fn(*a, **kw)

    for row, back in ((0, False), (1, True)):
        cell(0, row, f.draw_front, "stand", 0, back)
        for ph in range(4):
            cell(1 + ph, row, f.draw_front, "walk", ph, back)
        cell(5, row, f.draw_front, "busy", 0, back)
    cell(0, 2, f.draw_side, "stand")
    for ph in range(4):
        cell(1 + ph, 2, f.draw_side, "walk", ph)
    cell(5, 2, f.draw_side, "busy")
    cell(0, 3, f.draw_sleep)
    cell(1, 3, f.draw_front, "wave", 0, False)
    cell(2, 3, f.draw_sit)
    path = os.path.join(out_dir, f"{role}_{stage}.png")
    s.save_rgba(path)
    return path


def main(argv):
    roles = [a for a in argv if a in ROLES] or list(ROLES)
    stages = [a for a in argv if a in STAGE_ORDER] or list(STAGE_ORDER)
    for role in roles:
        for stage in stages:
            p = build(role, stage)
            print(os.path.relpath(p, ROOT), os.path.getsize(p) // 1024, "KB")


if __name__ == "__main__":
    main(sys.argv[1:])
