#!/usr/bin/env python3
"""家里的东西（tools/art/home.py）和街景（tools/art/street.py）的精灵：把老画法录成显示列表，给 3D 那边搭模型。

借 ../scene3d/record.py 的那一套（Pen / Sheet 的每一笔换成一条记录、画法函数包一层记名字），多做三件事：
  - 认 cairo 的坐标变换：梅家是青家镜像着画的（home.mirrored），街景的东西在 place() 平移 / 旋转过的坐标里画，
    记录的点一律换算成「这张纸的世界坐标」（user_to_device ÷ 倍率 + 原点）。写字的照旧不认变换（和老画法一样）。
  - 认 clip：老画法里「在车身里头涂一道腰线」靠的是 cairo 剪裁，录下来的面和线按剪裁框裁一刀（凸包近似）。
  - 管子（legacy_actors.tube：胳膊、腿、车架）记成一条 tube，不再是墨线 + 纸线 + 色线三根叠着的线。

每张精灵记成一份 {name, kind, box, ops}，box 是老画法里这张精灵在世界里的框（家里的东西：楼那张图的世界坐标；
街景：脚底为原点的局部坐标）。
"""
from __future__ import annotations

import functools
import math
import os
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
DIORAMA = os.path.dirname(HERE)
ART = os.path.dirname(DIORAMA)
sys.path.insert(0, os.path.join(DIORAMA, "scene3d"))
sys.path.insert(0, os.path.join(ART, "pixel"))
sys.path.insert(0, ART)

import record as R  # noqa: E402  （../scene3d/record.py，只读借用）

riso = R.riso
scenes = R.scenes

CLIP: list = []        # 剪裁框（世界坐标的凸包），里到外
_MUTE = [0]            # >0 时不记（tube 里面那几根线）


# ---------------------------------------------------------------- 坐标
def _xf(ctx, sheet, pts):
    """当前 cairo 坐标系里的点 → 世界坐标。"""
    S, (ox, oy) = sheet.scale, sheet.origin
    out = []
    for x, y in pts:
        dx, dy = ctx.user_to_device(float(x), float(y))
        out.append((dx / S + ox, dy / S + oy))
    return out


def _xk(ctx):
    """当前坐标系的缩放（线宽、点的半径跟着变）。"""
    a, b, c, d, _, _ = tuple(ctx.get_matrix())
    return math.sqrt(abs(a * d - b * c)) or 1.0


def _base_k(sheet):
    return sheet.scale


# ---------------------------------------------------------------- 剪裁（凸多边形，Sutherland–Hodgman / Cyrus–Beck）
def _hull(pts):
    p = sorted(set((round(x, 3), round(y, 3)) for x, y in pts))
    if len(p) < 3:
        return p

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, hi = [], []
    for q in p:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], q) <= 0:
            lo.pop()
        lo.append(q)
    for q in reversed(p):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], q) <= 0:
            hi.pop()
        hi.append(q)
    return lo[:-1] + hi[:-1]     # 逆时针（y 向下时看着是顺时针）


def _inside(p, a, b):
    return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= 0


def _isect(p, q, a, b):
    x1, y1, x2, y2 = p[0], p[1], q[0], q[1]
    x3, y3, x4, y4 = a[0], a[1], b[0], b[1]
    den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
    if abs(den) < 1e-9:
        return q
    t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
    return (x1 + t * (x2 - x1), y1 + t * (y2 - y1))


def clip_poly(pts, hull):
    out = list(pts)
    n = len(hull)
    for i in range(n):
        a, b = hull[i], hull[(i + 1) % n]
        inp, out = out, []
        if not inp:
            break
        s = inp[-1]
        for e in inp:
            if _inside(e, a, b):
                if not _inside(s, a, b):
                    out.append(_isect(s, e, a, b))
                out.append(e)
            elif _inside(s, a, b):
                out.append(_isect(s, e, a, b))
            s = e
    return out


def clip_line(pts, hull):
    """折线裁进凸多边形，可能断成几截。"""
    pieces, cur = [], []
    n = len(hull)
    for i in range(len(pts) - 1):
        p, q = pts[i], pts[i + 1]
        t0, t1 = 0.0, 1.0
        dx, dy = q[0] - p[0], q[1] - p[1]
        ok = True
        for j in range(n):
            a, b = hull[j], hull[(j + 1) % n]
            # 内侧：cross(b-a, x-a) >= 0
            ex, ey = b[0] - a[0], b[1] - a[1]
            num = ex * (p[1] - a[1]) - ey * (p[0] - a[0])
            den = ex * dy - ey * dx
            if abs(den) < 1e-12:
                if num < 0:
                    ok = False
                    break
                continue
            t = -num / den
            if den > 0:
                t0 = max(t0, t)
            else:
                t1 = min(t1, t)
            if t0 > t1:
                ok = False
                break
        if not ok:
            if len(cur) > 1:
                pieces.append(cur)
            cur = []
            continue
        a = (p[0] + dx * t0, p[1] + dy * t0)
        b = (p[0] + dx * t1, p[1] + dy * t1)
        if cur and (abs(cur[-1][0] - a[0]) > 1e-6 or abs(cur[-1][1] - a[1]) > 1e-6):
            if len(cur) > 1:
                pieces.append(cur)
            cur = []
        if not cur:
            cur = [a]
        cur.append(b)
        if t1 < 1.0:
            pieces.append(cur)
            cur = []
    if len(cur) > 1:
        pieces.append(cur)
    return pieces


def _cl_poly(pts):
    for h in CLIP:
        pts = clip_poly(pts, h)
        if len(pts) < 3:
            return None
    return pts


def _cl_line(pts):
    out = [pts]
    for h in CLIP:
        nxt = []
        for q in out:
            nxt += clip_line(q, h)
        out = nxt
    return out


def _in_clip(p):
    return all(len(clip_poly([p, (p[0] + 0.01, p[1]), (p[0], p[1] + 0.01)], h)) >= 3 for h in CLIP)


# ---------------------------------------------------------------- 画笔：先换算坐标、再裁、再记
def emit(k, pts=None, **kw):
    if _MUTE[0]:
        return
    R.emit(k, pts, **kw)


def _pen_line(self, pts, w=3.0, amp=0.9, cap="round", density=None, dash=None):
    k = _xk(self.ctx) / _base_k(self.sheet)
    for q in _cl_line(_xf(self.ctx, self.sheet, pts)):
        emit("line", q, c=self.color, d=self.density if density is None else density, w=w * k, dash=1 if dash else None)
    return self


def _pen_poly(self, pts, w=3.0, fill=False, stroke=True, amp=0.9, density=None, fill_density=None):
    P = _xf(self.ctx, self.sheet, [tuple(p) for p in pts])
    k = _xk(self.ctx) / _base_k(self.sheet)
    if fill:
        q = _cl_poly(P)
        if q:
            fd = fill_density if fill_density is not None else density
            emit("fill", q, c=self.color, d=self.density if fd is None else fd)
    if stroke:
        if CLIP:
            for q in _cl_line(P + [P[0]]):
                emit("line", q, c=self.color, d=self.density if density is None else density, w=w * k)
        else:
            emit("ring", P, c=self.color, d=self.density if density is None else density, w=w * k, filled=1 if fill else None)
    return self


def _pen_dot(self, x, y, r=2.0, density=None):
    p = _xf(self.ctx, self.sheet, [(x, y)])
    if CLIP and not _in_clip(p[0]):
        return self
    emit("dot", p, c=self.color, d=self.density if density is None else density, w=r * _xk(self.ctx) / _base_k(self.sheet))
    return self


def _pen_hatch(self, pts, angle=45.0, gap=10.0, w=1.6, amp=0.5, density=None):
    q = _cl_poly(_xf(self.ctx, self.sheet, [tuple(p) for p in pts]))
    if q:
        emit("hatch", q, c=self.color, d=self.density if density is None else density, ang=angle, gap=gap, w=w)
    return self


def _sheet_clear(self, pts, colors=None, layers=("solid", "tint")):
    ctx = self.plates["ink"]["solid"]
    q = _cl_poly(_xf(ctx, self, [tuple(p) for p in pts]))
    if q:
        emit("clear", q, only=list(colors) if colors else None)


def _sheet_text(self, color, tint, s, x, y, size, anchor="mm", density=1.0, vertical=False):
    # 老画法写字不认 cairo 的变换（街景先自己换算成绝对坐标再写），这里也照原样记
    emit("text", [(x, y)], c=color, d=density, s=s, size=size, anchor=anchor, v=1 if vertical else None)


def _knock(g, color, text, x, y, size, vertical=False, layer="solid"):
    emit("text", [(x, y)], c="paper", d=1.0, s=text, size=size, v=1 if vertical else None, knock=color)


class _Clip:
    def __init__(self, sheet, pts):
        self.h = _hull(_xf(sheet.plates["ink"]["solid"], sheet, [tuple(p) for p in pts]))

    def __enter__(self):
        CLIP.append(self.h)

    def __exit__(self, *a):
        CLIP.pop()


def _sheet_clip(self, pts):
    return _Clip(self, pts)


def _noop(*a, **k):
    return None


# ---------------------------------------------------------------- 画法函数记名字
def wrap(name, fn):
    return R._wrap(name, fn)


def wrap_module(mod, names):
    for n in names:
        if hasattr(mod, n):
            setattr(mod, n, wrap(n, getattr(mod, n)))


_ON = [False]


def enable():
    if _ON[0]:
        return
    _ON[0] = True
    R.enable()                     # scenes.py 的画法函数（钟、相框……）包好名字
    riso.Pen.line = _pen_line
    riso.Pen.poly = _pen_poly
    riso.Pen.dot = _pen_dot
    riso.Pen.hatch = _pen_hatch
    riso.Sheet.clear = _sheet_clear
    scenes.OSheet.clear = _sheet_clear
    riso.Sheet.text = _sheet_text
    riso.Sheet.clip = _sheet_clip
    scenes.knock = _knock


def begin():
    R.REC = []
    R.STACK.clear()
    CLIP.clear()


def end():
    out, R.REC = R.REC, None
    return out


# ---------------------------------------------------------------- 家里的东西
HOME_HELPERS = ("body", "box", "doily", "knob", "glare", "floor_shadow", "_tv")


def load_home():
    enable()
    import home
    home.register()
    wrap_module(home, HOME_HELPERS)
    for name, sp in home.SPRITES.items():
        if not getattr(sp["draw"], "_wrapped3d", False):
            f = wrap("sp:" + name, sp["draw"])
            f._wrapped3d = True
            sp["draw"] = f
    return home


def record_home(home, name, role):
    """一张家里的精灵（青家 / 梅家）。坐标是楼那张图的世界坐标。"""
    x0, y0, w, h = home.frame_of(name, role)
    g = scenes.OSheet(w, h, 1.0, origin=(x0, y0))
    begin()
    with home.mirrored(g, role == "mei"):
        home.SPRITES[name]["draw"](g, role)
    ops = end()
    return {"name": f"{name}_{role}", "sprite": name, "role": role, "kind": "home", "frame": [x0, y0, w, h], "ops": ops}


# ---------------------------------------------------------------- 街景
def load_street():
    enable()
    import legacy_actors as LA
    _tube0 = LA.tube

    def tube(s, pts, w, spec, lw=2.6, amp=0.45, shade=0.0):
        ctx = s.plates["ink"]["solid"]
        k = _xk(ctx) / _base_k(s)
        P = _xf(ctx, s, pts)
        col, d = (spec if spec is not None else ("paper", None))
        for q in _cl_line(P):
            emit("tube", q, c=col, d=1.0 if d is None else d, w=w * k, lw=lw * k, shade=shade or None)
        _MUTE[0] += 1
        try:
            return _tube0(s, pts, w, spec, lw, 0.0, shade)
        finally:
            _MUTE[0] -= 1
    LA.tube = wrap("tube", tube)
    LA.stroke_clear = _noop
    wrap_module(LA, ("part",))
    sys.modules["actors"] = LA
    import street_fig as SF
    for n in ("hand", "arm", "shoe", "leg", "deco", "head", "face", "hat", "draw"):
        setattr(SF.F, n, wrap("fig." + n, getattr(SF.F, n)))
    wrap_module(SF, ("fig", "rider"))       # 先包好，street import 的时候拿到的就是包过的
    import street as ST
    ST._ko_abs = _knock
    # 精灵的画法在调用时按名字找 street 的全局函数：换成包过的就行
    wrap_module(ST, ("ground_shadow", "_board", "_wheel", "_bike", "_cycle", "_scribble"))
    for name, sp in ST.SPRITES.items():
        if not getattr(sp["draw"], "_wrapped3d", False):
            f = wrap("sp:" + name, sp["draw"])
            f._wrapped3d = True
            sp["draw"] = f
    return ST, LA


def record_street(ST, LA, name, frame_i):
    sp = ST.SPRITES[name]
    s = riso.Sheet(sp["w"], sp["h"], 1.0, origin=(-sp["foot"][0], -sp["foot"][1]))
    begin()
    sp["draw"](s, frame_i)
    ops = end()
    fx, fy = sp["foot"]
    return {"name": f"{name}#{frame_i}", "sprite": name, "frame_i": frame_i, "kind": "street",
            "frame": [-fx, -fy, sp["w"], sp["h"]], "ops": ops}


if __name__ == "__main__":
    import json
    hm = load_home()
    d = record_home(hm, sys.argv[1] if len(sys.argv) > 1 else "tv_bw_0", sys.argv[2] if len(sys.argv) > 2 else "qing")
    kinds = {}
    for o in d["ops"]:
        kinds[o["k"]] = kinds.get(o["k"], 0) + 1
    print(d["frame"], kinds)
    print(json.dumps(d["ops"][:8], ensure_ascii=False))
