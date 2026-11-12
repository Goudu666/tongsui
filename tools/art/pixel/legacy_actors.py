"""老 actors.py 里的几样画法（tools/art/street.py、street_fig.py 还在用）。

actors.py 在 d149e8b（侧视骨骼人物）重写以后不再有这些名字，tools/art/street.py 直接跑会 ImportError。
这里原样留一份（取自 d149e8b^:tools/art/actors.py 的几何、印刷动作和 STAGES），
pxstreet.py 在 import street 之前把它挂成 sys.modules["actors"]。只给街景精灵用。
"""
from __future__ import annotations

import math
import os
import sys
from contextlib import contextmanager

import cairo

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from riso import Sheet, ellipse_pts, rect_pts, wobble  # noqa: E402,F401

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
