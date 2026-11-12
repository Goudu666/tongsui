#!/usr/bin/env python3
"""像素版的分层：远景、中景、门外的远景、四季的树、前景（沿用 tools/art/layers.py 的画法）。

layers.py 画什么、画在哪一样不改，这里只换「怎么落成像素」：
  · 每一层按它在屏幕上的大小画（以前引擎里 FAR_SCALE 0.62、MID_SCALE 0.9、FORE_SCALE 1.8、树 1/1.25 再缩放；
    现在画的时候就缩好，引擎里一律 1），每 3 个世界像素一个点，和底图的点一样大——不出「大小点」。
  · 方块（楼、窗、水箱、灯）吸到点的格子上：边是整点，窗是一样大的小方块。
  · 远近靠颜色分：远的只有四五个灰青色、几乎是平的；中景多几样颜色、楼顶一道亮边；树和前景用全色。
    这些颜色都从 palette.json（和底图共用的调色板）里挑，不抖动（平涂），只有烟是半透的格子。
  · 横着无缝：条宽是 12 的倍数（点数是 4 的倍数，拜耳格子也接得上），左右各多画一截再裁掉。
  · 夜里亮窗的 _lit.png：和窗同一个格子，一个点一个值，放大 3 倍（方的）。

    python3 tools/art/pixel/pxlayers.py                       # 全部 → client/art/layers/
    python3 tools/art/pixel/pxlayers.py far mid               # 只出远景、中景
    python3 tools/art/pixel/pxlayers.py --out /tmp/layers far           # 出到别处看看
"""
from __future__ import annotations

import argparse
import math
import os
import random
import sys

import cairo
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)
import riso  # noqa: E402
import scenes  # noqa: E402,F401  （pxlib.enable 要先有它）
import pxlib  # noqa: E402

pxlib.enable()
import layers  # noqa: E402

PX = pxlib.PX
OUT = layers.OUT
STRIP = layers.STRIP

# 每条在屏幕上多宽（世界像素 = 贴图像素）：原来 STRIP × 引擎缩放，取 12 的倍数（3 的倍数、点数是 4 的倍数）
FAR_W = 1272      # 2048 × 0.62 = 1269.8
MID_W = 1848      # 2048 × 0.9 = 1843.2
PLACE_W = 1644    # 2048 × 0.8 = 1638.4（海边、乡下：以前 far_scale 0.8）
FORE_W = 3672     # 2048 × 1.8 = 3686.4；前景一个点 6 世界像素（FORE_PT），宽是 24 的倍数
FORE_PT = 6
# 树：画布（世界像素），原来 (620, 700) 这些凑成 6 / 3 的倍数（脚底正中落在格子上）
TREE_CANVAS = {"huai": (624, 702), "willow": (642, 681), "young": (300, 381)}


# ----------------------------------------------------------------------
# 1. 画：layers.py 原样画，只是纸换成「按屏幕大小、带边、吸格子」的
# ----------------------------------------------------------------------

class _Spec:
    """这一张怎么画：贴图多大（像素）、layers 的一个单位是几个像素、左右多画几像素、一个点几像素。"""

    def __init__(self, w, h, s, pt=PX, margin=0, oy=0.0):
        self.w, self.h, self.s, self.pt, self.m = w, h, s, pt, margin
        self.origin = (-margin / s, oy)


_CUR: _Spec | None = None


def _sheet(width, height, scale=1.0, seed=7):
    sp = _CUR
    g = riso.Sheet((sp.w + 2 * sp.m) / sp.s, sp.h / sp.s, sp.s, origin=sp.origin, seed=seed)
    assert g.W == sp.w + 2 * sp.m and g.H == sp.h, (g.W, g.H, sp.w, sp.h)
    g._pt = sp.pt
    for n in ("brick", "glass", "thin"):
        pxlib._mark_ctx(g, n)
    global _SHEET
    _SHEET = g
    return g


_SHEET = None


class _Rnd(random.Random):
    """记下 layers 里开的每个随机数发生器，好在左右三份之间倒回去（三份画得一模一样）。"""
    live: list = []

    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        _Rnd.live.append(self)


class _RandomShim:
    Random = _Rnd

    def __getattr__(self, k):
        return getattr(random, k)


def _wrap(fn, *args, **kw):
    """横着无缝：layers.wrap 是把同一样东西在 x−STRIP、x、x+STRIP 各画一遍，可它把 off 加进了窗的哈希、
    中间还会多抽几次随机数，三份就不一样，接缝上的窗、草对不上。这里改成：三份都按 off=0 画，
    挪的是纸（整条宽正好是整数个点），随机数每份从同一处开始。"""
    g = _SHEET
    ctxs = [g.plates[c][l] for c in riso.COLORS for l in ("solid", "tint")] + [g.plates["paper"]["solid"]]
    ctxs += [v[1] for v in g._marks.values()]
    states = [(r, r.getstate()) for r in _Rnd.live]
    for off in (-STRIP, 0, STRIP):
        for r, s in states:
            r.setstate(s)
        for c in ctxs:
            c.save()
            c.translate(off, 0)
        try:
            fn(0, *args, **kw)
        finally:
            for c in ctxs:
                c.restore()


def _snap_rect(g, pts):
    """layers 的单位 → 纸像素，四条边吸到点的格子上（位置四舍五入，宽高四舍五入、至少一个点）。"""
    s, pt = g.scale, getattr(g, "_pt", PX)
    ox, oy = g.origin
    x0, y0 = pts[0]
    x1, y1 = pts[2]
    if x1 < x0:
        x0, x1 = x1, x0
    if y1 < y0:
        y0, y1 = y1, y0
    X0 = round((x0 - ox) * s / pt)
    Y0 = round((y0 - oy) * s / pt)
    W = max(1, round((x1 - x0) * s / pt))
    H = max(1, round((y1 - y0) * s / pt))
    # 底边贴着楼脚的方块（高出底边的那一截）不往上缩
    X0, Y0 = X0 * pt, Y0 * pt
    W, H = W * pt, H * pt
    return [((X0) / s + ox, (Y0) / s + oy), ((X0 + W) / s + ox, Y0 / s + oy),
            ((X0 + W) / s + ox, (Y0 + H) / s + oy), (X0 / s + ox, (Y0 + H) / s + oy)]


def _is_rect(pts):
    if len(pts) != 4:
        return False
    (a, b), (c, d), (e, f), (h, i) = pts
    return abs(b - d) < 1e-6 and abs(c - e) < 1e-6 and abs(f - i) < 1e-6 and abs(h - a) < 1e-6 and abs(c - a) > 1e-6


SNAP = True
_old_path = riso.Pen._path
_old_clear = riso.Sheet.clear
_old_paper = layers.paper


def _path(self, pts, closed):
    if SNAP and closed and _is_rect(pts):
        pts = _snap_rect(self.sheet, pts)
    return _old_path(self, pts, closed)


def _clear(self, pts, colors=None, layers=("solid", "tint")):
    if SNAP and _is_rect(pts):
        pts = _snap_rect(self, pts)
    return _old_clear(self, pts, colors, layers)


def _paper(g, pts):
    if SNAP and _is_rect(pts):
        pts = _snap_rect(g, pts)
    return _old_paper(g, pts)


riso.Pen._path = _path
riso.Sheet.clear = _clear
layers.paper = _paper
layers.Sheet = _sheet
layers.wrap = _wrap
layers.random = _RandomShim()


class LitPx:
    """夜里亮的窗：和纸一样大（不带边），方块同样吸格子，左右也接得上。"""

    def __init__(self, w, h, scale):
        sp = _CUR
        self.sp = sp
        self.a = np.zeros((sp.h, sp.w), np.float32)

    def rect(self, x, y, w, h, v=1.0):
        sp = self.sp
        s, pt = sp.s, sp.pt
        X0 = round(x * s / pt) * pt
        Y0 = round((y - sp.origin[1]) * s / pt) * pt
        W = max(1, round(w * s / pt)) * pt
        H = max(1, round(h * s / pt)) * pt
        for off in (-sp.w, 0, sp.w):
            x0, x1 = max(0, X0 + off), min(sp.w, X0 + off + W)
            y0, y1 = max(0, Y0), min(sp.h, Y0 + H)
            if x1 > x0 and y1 > y0:
                self.a[y0:y1, x0:x1] = np.maximum(self.a[y0:y1, x0:x1], v)


layers.Lit = LitPx


def draw(fn, args, sp: _Spec):
    global _CUR
    _CUR = sp
    try:
        return fn(*args)
    finally:
        _CUR = None


# ----------------------------------------------------------------------
# 2. 收成点：每个点按「盖住的那部分」的浓度算（不被半个点的边稀释），过半才算有
# ----------------------------------------------------------------------

def _cells(a, k):
    H, W = a.shape[0] // k * k, a.shape[1] // k * k
    return a[:H, :W].reshape(H // k, k, W // k, k)


def pool_cover(a, k, need=0.5, eps=0.02):
    """一格里有东西的那部分平均多浓；有东西的不到 need 就当没有。"""
    b = _cells(a, k)
    on = b > eps
    n = on.sum(axis=(1, 3))
    cov = n / (k * k)
    val = np.where(n > 0, (b * on).sum(axis=(1, 3)) / np.maximum(n, 1), 0.0)
    return np.where(cov >= need, val, 0.0).astype(np.float32), cov.astype(np.float32)


def points(g, k, crop=None):
    """纸 → 每个点的各版浓度（已经是点了，交给 pxlib.compose(k=1)）。"""
    H, W = g.H, g.W
    d, pa, br = pxlib.plates(g, crop or (0, H, 0, W))
    out = {}
    for c in ("ink", "qing", "mei"):
        s, t = d[c]
        sv, scov = pool_cover(s, k, 0.45)
        tv, tcov = pool_cover(t, k, 0.5)
        out[c] = (sv, tv)
    # 墨线：细线（盖住三成以上）也留着，不然远处的塔吊、天线断成一截一截
    s = d["ink"][0]
    lv, lcov = pool_cover(s, k, 0.28)
    out["ink"] = (np.maximum(out["ink"][0], lv), out["ink"][1])
    pa_pt = (pxlib.pool(pa, k, "mean") > 0.5).astype(np.float32)
    br_pt = {n: pxlib.pool(v, k, "mean") for n, v in br.items()}
    return out, pa_pt, br_pt, d


# ----------------------------------------------------------------------
# 3. 上色：pxlib.compose 的材质色 → 按远近收到调色板里的几样颜色上（平涂，不抖）
# ----------------------------------------------------------------------

PAL = pxlib.load_palette()


def _lin(c):
    c = np.asarray(c, np.float32) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _lab(c):
    """sRGB 0~255 → OKLab（挑最近的颜色用）。"""
    l = _lin(c)
    M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                   [0.2119034982, 0.6806995451, 0.1073969566],
                   [0.0883024619, 0.2817188376, 0.6299787005]], np.float32)
    M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                   [1.9779984951, -2.4285922050, 0.4505937099],
                   [0.0259040371, 0.7827717662, -0.8086757660]], np.float32)
    lms = np.cbrt(l @ M1.T)
    return lms @ M2.T


def nearest(col, pal, chroma=1.0):
    """每个颜色换成 pal 里最近的（OKLab，色相按 chroma 加权）。"""
    H, W, _ = col.shape
    a = _lab(col.reshape(-1, 3))
    b = _lab(pal)
    wv = np.array([1.0, chroma, chroma], np.float32)
    out = np.empty(len(a), np.int64)
    for i in range(0, len(a), 200000):
        dd = (((a[i:i + 200000, None, :] - b[None]) * wv) ** 2).sum(-1)
        out[i:i + 200000] = dd.argmin(1)
    return pal[out].reshape(H, W, 3), out.reshape(H, W)


def hexes(*hs):
    return np.array([pxlib._h(h) for h in hs], np.float32)


def grade(col, haze, hz_col, sat):
    """空气透视：往天色里推 haze，饱和度乘 sat。"""
    lum = (col * np.array([0.3, 0.55, 0.15], np.float32)).sum(-1, keepdims=True)
    c = lum + (col - lum) * sat
    return c * (1 - haze) + np.asarray(hz_col, np.float32) * haze


def rim(alpha, col, amt, color, solid=None):
    """上沿一道亮边：这个点有东西、它上面一个点没有（楼顶、树冠迎着天光的那一圈）。"""
    up = np.zeros_like(alpha)
    up[1:] = alpha[:-1]
    m = alpha & ~up
    if solid is not None:
        m &= solid
    col[m] = col[m] * (1 - amt) + np.asarray(color, np.float32) * amt
    return m


def to_rgba(col, alpha):
    return np.dstack([col.clip(0, 255).astype(np.uint8), (alpha * 255).astype(np.uint8)])


# 细线：比一个点还细的线（天线、塔吊、柳条、枝梢、草叶）不交给 cairo 抗锯齿，
# 按点走一条布雷森汉姆线，每个点整格涂满——一个点宽、不断、不糊。粗线照旧。
THIN = 1.6   # 线宽不到几个点算细线
_old_line = riso.Pen.line


def _bres(x0, y0, x1, y1):
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    out = []
    while True:
        out.append((x0, y0))
        if x0 == x1 and y0 == y1:
            return out
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def _line(self, pts, w=3.0, amp=0.9, cap="round", density=None, dash=None):
    g = self.sheet
    pt = getattr(g, "_pt", None)
    if not SNAP or pt is None or w * g.scale >= THIN * pt:
        return _old_line(self, pts, w, amp, cap, density, dash)
    s = g.scale
    ox, oy = g.origin
    P = [(int(math.floor((x - ox) * s / pt)), int(math.floor((y - oy) * s / pt))) for x, y in pts]
    cells = set()
    for a, b in zip(P[:-1], P[1:]):
        cells.update(_bres(a[0], a[1], b[0], b[1]))
    if len(P) == 1:
        cells.add(P[0])
    for c in (self.ctx, pxlib._mark_ctx(g, "thin")):
        c.new_path()
        for X, Y in cells:
            c.rectangle(X * pt / s + ox, Y * pt / s + oy, pt / s, pt / s)
        if c is self.ctx:
            self._src(density)
        else:
            c.set_source_rgba(0, 0, 0, 1)
        c.fill()
    return self


riso.Pen.line = _line


# ----------------------------------------------------------------------
# 4. 一条（远景 / 中景 / 前景）、一棵树：画 → 点
# ----------------------------------------------------------------------

class Pts:
    """一张画收成点以后：颜色（compose 的材质色）、有没有、墨线、各版浓度，和亮窗。"""

    def __init__(self, g, sp, lit=None, crop_m=True):
        k = sp.pt
        d, pa, br, raw = points(g, k)
        col, al, line = pxlib.compose(d, pa, br, k=1, relief=False)
        mp = sp.m // k if crop_m else 0
        w = sp.w // k
        cut = (lambda a: a[:, mp:mp + w]) if crop_m else (lambda a: a)
        self.col = cut(col)
        self.alpha = cut(al > 0.4)
        self.line = cut(line)
        self.q = cut(np.maximum(*d["qing"]))
        self.m = cut(np.maximum(*d["mei"]))
        self.ks = cut(d["ink"][0])
        self.kt = cut(d["ink"][1])
        # 很淡的墨（烟）：平均浓度，不管盖没盖满
        self.smoke = cut(pxlib.pool(raw["ink"][1], k, "mean"))
        self.paper = cut(pa)
        self.thin = cut(pxlib.pool(pxlib.mark_mask(g, "thin"), k, "mean") > 0.5)
        self.pt = k
        self.lit = None
        if lit is not None:
            self.lit = pxlib.pool(lit.a, k, "max")
        H, W = self.alpha.shape
        self.bay = pxlib.BAYER[np.arange(H)[:, None] % 4, np.arange(W)[None] % 4]


def strip_spec(W, h_units, pt=PX):
    s = W / STRIP
    Hpx = int(math.ceil(h_units * s / pt)) * pt
    return _Spec(W, Hpx, s, pt, 16 * pt, oy=h_units - Hpx / s)


def render_strip(fn, args, W, h_units, pt=PX):
    sp = strip_spec(W, h_units, pt)
    r = draw(fn, args, sp)
    g, lit = r if isinstance(r, tuple) else (r, None)
    return Pts(g, sp, lit)


_old_union = layers.union


def _union_tree(g, color, d, polys):
    """树冠一整片铺上去之前，先把底下的枝杈挖掉（孔版是叠印、枝从冠子里透出来；像素画里冠子挡着枝）。"""
    if color != "ink" and d is not None and d >= 0.25:
        for pts in polys:
            _old_clear(g, pts, colors=["ink"], layers=("solid",))
    return _old_union(g, color, d, polys)


def render_tree(kind, season):
    Wd, Hd = TREE_CANVAS[kind]
    _, _, h, r = layers.TREES[kind]
    layers.TREES[kind] = (Wd, Hd, h, r)
    sp = _Spec(Wd, Hd, 1.0, PX, 0, 0.0)
    layers.union = _union_tree
    try:
        g = draw(layers.draw_tree, (kind, season), sp)
    finally:
        layers.union = _old_union
    return Pts(g, sp, crop_m=False)


# ----------------------------------------------------------------------
# 5. 上色
# ----------------------------------------------------------------------

def _ramp(idx, ramp):
    return ramp[np.clip(idx, 0, len(ramp) - 1)]


def _fog(p, idx, rows, amt):
    """楼脚那一截罩着一层地气：越往下越往浅一档抖（拜耳），远的楼底下发虚。"""
    H = idx.shape[0]
    y = np.arange(H)[:, None]
    t = np.clip((y - (H - rows)) / rows, 0, 1) * amt
    return idx - (p.bay < t).astype(idx.dtype)


def _smoke(p, rgba, color, gain=7.0):
    """烟：淡墨的地方按浓度抖出一半一半的格子（像素画里半透明就这么画）。"""
    v = np.clip(p.smoke * gain, 0, 0.75)
    on = (~p.alpha) & (p.bay < v) & (p.smoke > 0.02)
    rgba[on, :3] = color
    rgba[on, 3] = 255


# 材质色（和 pxlib.compose 一个意思：纸 → 梅 / 青的两档，墨的浅色压成影子），不撒麻点，好让各条首尾接得上
def material(p: Pts, shade_gain=1.1, gain=1.0):
    C = pxlib.C
    H, W = p.alpha.shape

    def ramp(dd, hi, base, col):
        t = np.clip(dd / 0.7, 0, 1)[..., None]
        c1 = col + (hi - col) * np.clip(t * 2, 0, 1)
        return c1 + (base - c1) * np.clip(t * 2 - 1, 0, 1)

    col = np.broadcast_to(C["paper"], (H, W, 3)).copy()
    q, m = p.q * gain, p.m * gain
    col = ramp(m, C["mei_hi"], C["mei"], col)
    both = np.clip(np.minimum(q, m) * 2.0, 0, 1)[..., None]
    col = ramp(q, C["qing_hi"], C["qing"], col) * (1 - both) + C["plum"] * both
    sh = np.clip(p.kt * shade_gain, 0, 0.92)[..., None]
    col = col * (1 - sh) + C["shade"] * sh
    col[p.line] = C["line"]
    return col


def edges(alpha):
    """有东西的点里：上 / 下 / 左 / 右挨着空的。"""
    def nb(dy, dx):
        return pxlib._shift(alpha, dx, dy)
    return {"top": alpha & ~nb(1, 0), "bot": alpha & ~nb(-1, 0), "left": alpha & ~nb(0, 1), "right": alpha & ~nb(0, -1)}


def step(col, pal, k):
    """col 在 pal 的明度上挪 k 档（同色相附近找）：亮边、暗边用。"""
    a = _lab(col.reshape(-1, 3))
    b = _lab(pal)
    out = col.reshape(-1, 3).copy()
    tgt = a.copy()
    tgt[:, 0] += 0.075 * k
    dd = ((tgt[:, None, :] - b[None]) ** 2 * np.array([1.0, 2.5, 2.5])).sum(-1)
    # 至少要往那边挪一点
    dl = b[None, :, 0] - a[:, None, 0]
    dd = np.where(dl * np.sign(k) > 0.02, dd, 1e9)
    j = dd.argmin(1)
    ok = dd.min(1) < 1e8
    out[ok] = pal[j[ok]]
    return out.reshape(col.shape)


# 远景：城里的楼。只用几档灰青（调色板里的），平涂；后排的高楼浅一档（更远），前排矮楼压住底，窗比墙深一档
FAR = dict(rim="#B9D4C9", low="#8CA699", tall="#ABBBAF", lowwin="#6E8280", tallwin="#8CA699",
           struct="#7A9D8F", ink="#6E8280", base="#8CA699", smoke="#D7E7DA", smoke_hi="#D7E7DA")


def _solid(p, thr=0.12):
    """有东西：纸版（实的面）或者印得够浓的细线（天线、塔吊），烟那种淡墨不算。"""
    return p.paper.astype(bool) | (p.q > thr) | (p.m > thr) | (p.ks > 0.3) | ((p.kt > 0.15) & p.thin) | p.line


def look_far(p: Pts, pal=FAR, fog_rows=7):
    c = {k: hexes(v)[0] for k, v in pal.items()}
    al = _solid(p)
    v = np.maximum(p.q, p.m)
    ink_only = (v < 0.05) & (((p.kt > 0.15) & p.thin) | (p.ks > 0.3))
    H, W = v.shape
    col = np.zeros((H, W, 3), np.float32)
    col[:] = c["low"]
    col[v >= 0.215] = c["tall"]
    col[v >= 0.30] = c["struct"]
    col[v >= 0.42] = c["lowwin"]
    col[v >= 0.53] = c["tallwin"]
    col[ink_only] = c["ink"]
    e = edges(al)
    rim = e["top"] & ~ink_only
    col[rim] = c["rim"]
    # 楼脚一截地气：往浅里抖
    y = np.arange(H)[:, None]
    t = np.clip((y - (H - fog_rows)) / fog_rows, 0, 1) * 0.75
    fog = al & (p.bay < t)
    col[fog] = col[fog] * 0.5 + c["low"] * 0.5
    col[fog] = nearest(col[fog][None], hexes(*pal.values()))[0][0]
    rgba = to_rgba(col, al)
    # 烟：中间一团平涂、边上抖一半
    sm = (~al) & (p.smoke > 0.012)
    core = sm & (p.smoke > 0.06) & (p.bay < 0.8)
    edge = sm & ~core & (p.bay < np.clip(p.smoke * 9, 0, 0.5))
    rgba[core, :3] = c["smoke"]
    rgba[core, 3] = 255
    rgba[edge, :3] = c["smoke"]
    rgba[edge, 3] = 255
    top = core & ~pxlib._shift(core | edge, 0, 1)
    rgba[top, :3] = c["smoke_hi"]
    return rgba


# 中景：隔一两条街的楼。比底图少几样颜色、灰一点，但砖还是砖、青还是青
MID_PAL = hexes("#E9876B", "#D7836D", "#CE6C5A", "#B05E56", "#8E3036",
                "#88C1A3", "#6BB296", "#4D9D86", "#35726C", "#1E5E58",
                "#E8DAC2", "#D5C8B6", "#C1B4A8", "#A59996", "#8B7F85", "#6E6472", "#60586A", "#4C455D", "#3A3150",
                "#DFD2BD", "#C8E0D3", "#96B8A3")


def look_mid(p: Pts, pal=MID_PAL, sat=0.82, haze=0.08):
    al = _solid(p)
    col = material(p)
    col = grade(col, haze, (214, 222, 212), sat)
    col, _ = nearest(col, pal, chroma=1.6)
    # 窗：墙里挖出来的一块墨（没有梅、青）——玻璃压成深灰紫，窗台下面一道亮、窗楣底下一道影子
    win = al & (p.kt > 0.22) & (p.m < 0.05) & (p.q < 0.05) & ~p.thin & ~p.line
    dark = win & (p.kt > 0.4)
    col[win] = hexes("#6E6472")[0]
    col[dark] = hexes("#4C455D")[0]
    below = pxlib._shift(win, 0, 1) & ~win & al & ~p.line
    col[below] = step(col[below][None], pal, +1)[0]
    lintel = win & ~pxlib._shift(win, 0, 1)
    col[lintel] = hexes("#3A3150")[0]
    e = edges(al)
    # 上沿迎光亮一档；右边两个点暗一档（楼有个侧面），左边一个点暗一档
    col[e["top"]] = step(col[e["top"]][None], pal, +1)[0]
    right = (e["right"] | pxlib._shift(e["right"], -1, 0)) & al & ~e["top"] & ~win
    col[right] = step(col[right][None], pal, -1)[0]
    left = e["left"] & ~e["top"] & ~right
    col[left] = step(col[left][None], pal, -1)[0]
    return to_rgba(col, al)


# 门外的远景（海边的岬角和货轮、乡下的杨树行和水塔）：比城里的远景近一点、颜色多一点，还是灰
PLACE_PAL = hexes("#D7E7DA", "#B9D4C9", "#A6CEAF", "#96B8A3", "#7DB59B", "#7A9D8F", "#649787", "#537A76", "#35726C",
                  "#D7836D", "#CE6C5A", "#B05E56", "#F2E4C9", "#DFD2BD", "#C1B4A8", "#A59996", "#8B7F85", "#6E6472", "#4C455D")


def look_place(p: Pts):
    al = _solid(p)
    col = material(p, shade_gain=1.4, gain=1.3)
    col = grade(col, 0.06, (214, 222, 212), 0.8)
    col, _ = nearest(col, PLACE_PAL, chroma=1.8)
    e = edges(al)
    col[e["top"]] = step(col[e["top"]][None], PLACE_PAL, +1)[0]
    right = e["right"] & ~e["top"]
    col[right] = step(col[right][None], PLACE_PAL, -1)[0]
    return to_rgba(col, al)


# 树：冠子按季节一套四五档的绿（秋天是柿子红），浓淡照 layers 画的（叠的地方深、底下一道影子），
# 左上迎光亮一档、右下背光暗一档；枝干是深紫灰，左边一道亮；雪是纸白
TREE_RAMP = {
    "spring": ["#B9D0B4", "#8DC8A7", "#6BB296", "#4D9D86", "#35726C"],
    "summer": ["#88C1A3", "#55A58B", "#40937E", "#2C8A76", "#1E5E58"],
    "autumn": ["#E3B99F", "#DF957D", "#CE6C5A", "#B05E56", "#8E3036"],
    "green": ["#C6D2B8", "#96B8A3", "#7A9D8F", "#649787", "#537A76"],   # 秋天没黄透的
}
TREE_BASE = {("huai", "spring"): 0.3, ("huai", "summer"): 0.5, ("huai", "autumn"): 0.3,
             ("young", "spring"): 0.3, ("young", "summer"): 0.5, ("young", "autumn"): 0.3,
             ("willow", "spring"): 0.42, ("willow", "summer"): 0.58, ("willow", "autumn"): 0.32}
BARK = hexes("#6E6472", "#4C455D", "#3A3150", "#281D2C")


def look_tree(p: Pts, kind="", season=""):
    al = _solid(p)
    H, W = al.shape
    col = np.zeros((H, W, 3), np.float32)
    col[:] = hexes("#F2E4C9")[0]                      # 纸：雪、槐花底
    leaf = al & ((p.q > 0.04) | (p.m > 0.04))
    bark = al & ~leaf & ((p.ks > 0.3) | (p.kt > 0.3) | p.line)
    if season != "winter":
        base = TREE_BASE.get((kind, season), 0.4)
        dens = np.maximum(p.q, p.m) + p.kt * 0.3
        r = dens / base
        idx = np.where(r < 1.25, 1, np.where(r < 1.6, 2, 3))
        if kind == "willow":
            idx = np.where(r < 0.8, 1, np.where(r < 1.25, 2, 3))
            # 柳条一绺一绺深浅不一（按列哈希）
            xs = np.arange(W)[None, :]
            hsh = ((xs * 2654435761) >> 7) & 3
            idx = np.where((r >= 0.8) & (hsh == 0), idx - 1, idx)
        # 整个冠子的明暗：从左上往右下，亮一档 → 暗一档（交界按拜耳抖一下）
        ys, xs = np.nonzero(leaf)
        if len(ys):
            cy, cx = ys.mean(), xs.mean()
            ry, rx = max(ys.std(), 1), max(xs.std(), 1)
            yy, xx = np.mgrid[0:H, 0:W]
            t = ((xx - cx) / rx * 0.45 + (yy - cy) / ry * 0.75) / 1.2
            idx = idx - ((t + (p.bay - 0.5) * 0.25) < -0.75) + ((t + (p.bay - 0.5) * 0.25) > 0.55)
        # 冠子上沿那一道弧（layers 里描的深弧）在像素里画成迎光亮一档的弧：一团一团的叶子就分出来了
        arc = leaf & p.thin & (np.maximum(p.q, p.m) > 0.6) & (p.ks < 0.3) & (p.kt < 0.3)
        idx = np.where(arc, idx - 1, idx)
        # 冠子里的墨：叶子的小弧只压暗一档（画成黑线像一张张笑脸）
        idx = np.where(leaf & (p.ks > 0.3) & p.thin, idx + 1, idx)
        hl = leaf & ~(pxlib._shift(leaf, 1, 1))
        idx = np.where(hl, idx - 1, idx)
        if kind != "willow":
            # 背光那一圈（下沿、右沿）描一道最深的同色边，冠子从后面的墙上跳出来
            eg = edges(leaf)
            idx = np.where(eg["bot"] | eg["right"], 4, idx)
        idx = np.clip(idx, 0, 4)
        ramp = hexes(*TREE_RAMP[season])
        green = hexes(*TREE_RAMP["green"])
        c = ramp[idx]
        if season == "autumn":
            c = np.where(((p.q > p.m * 0.8) & (p.q > 0.04))[..., None], green[idx], c)
        col[leaf] = c[leaf]
        # 冠子底下露出来的几根枝（layers 里的淡墨粗枝）：画成树皮色
        twig = leaf & (p.kt > 0.38) & ~p.thin
        col[twig] = BARK[1]
        if kind == "willow":
            # 柳冠那一顶：只有一层淡色的地方（没挂柳条）边上两个点抖成一半，不像扣了一只碗
            dome = leaf & (r < 0.8)
            inner = pxlib._erode(leaf, 2)
            al = al & ~(dome & ~inner & (p.bay < 0.5))
        # 春天的槐花：冠子里挖白的小点（纸 + 一点梅）
    flower = al & ~leaf & ~bark & (p.m > 0.0)
    col[flower] = hexes("#F2E4C9")[0]
    # 枝干
    bk = np.full((H, W), 1)
    lf = bark & ~pxlib._shift(bark, 1, 0)
    rt = bark & ~pxlib._shift(bark, -1, 0)
    bk = np.where(lf & ~rt, 0, np.where(rt & ~lf, 2, bk))
    col[bark] = BARK[bk][bark]
    return to_rgba(col, al)


# 前景：贴着镜头的剪影（引擎里 fore_dof 压暗）。点大一倍（6 世界像素一个点）：离镜头近、对不上焦的那种大颗粒
FORE_RIVER_K = 0.75   # scene_art.gd：河边的前景按 FORE_SCALE × 0.75 贴


def fore_spec(kind):
    """(贴图宽, 一个点几个贴图像素, layers 单位 → 贴图像素)。河边那条引擎里缩 0.75 贴，贴图点就大成 8，屏幕上还是 6。"""
    if kind == "river":
        pt = round(FORE_PT / FORE_RIVER_K)
        W = int(round(STRIP * 1.8 * FORE_RIVER_K / FORE_RIVER_K / (pt * 4))) * pt * 4
        return W, pt
    return FORE_W, FORE_PT


def render_fore(kind):
    W, pt = fore_spec(kind)
    return render_strip(layers.draw_fore, (kind,), W, layers.FORE_H, pt)


def look_fore(p: Pts, kind=""):
    al = _solid(p)
    col = material(p)
    col, _ = nearest(col, PAL, chroma=1.3)
    e = edges(al)
    col[e["top"]] = step(col[e["top"]][None], PAL, +1)[0]
    return to_rgba(col, al)


def render_fore_kind(kind):
    return look_fore(render_fore(kind), kind)


LOOKS = {}


# ----------------------------------------------------------------------
# 6. 出图
# ----------------------------------------------------------------------

def save_rgba(pts_rgba, k, path):
    """每个点放大 k 倍（贴图像素 = 世界像素）。颜色本来就少，直接存 RGBA，不再压色。"""
    big = pxlib.up(pts_rgba, k)
    big[big[..., 3] == 0, :3] = 0
    Image.fromarray(np.ascontiguousarray(big), "RGBA").save(path, optimize=True)
    return big


def save_lit(p: Pts, path):
    """亮窗：一个点一个值（取格子里最亮的），放大成方块。"""
    a = p.lit if p.lit is not None else np.zeros(p.alpha.shape, np.float32)
    big = pxlib.up((np.clip(a, 0, 1) * 255).astype(np.uint8), p.pt)
    Image.fromarray(big, "L").save(path, optimize=True)


def build(what, out=OUT, verbose=True):
    os.makedirs(out, exist_ok=True)
    done = []

    def put(name, p, rgba):
        big = save_rgba(rgba, p.pt, os.path.join(out, name + ".png"))
        done.append(name)
        if verbose:
            print(f"  ✓ {name}.png  {big.shape[1]}×{big.shape[0]}")

    if "far" in what:
        for i, era in enumerate(layers.ERAS):
            p = render_strip(layers.draw_far, (i,), FAR_W, layers.FAR_H)
            put(f"far_{era}", p, look_far(p))
            save_lit(p, os.path.join(out, f"far_{era}_lit.png"))
    if "mid" in what:
        for i, era in enumerate(layers.ERAS):
            p = render_strip(layers.draw_mid, (i,), MID_W, layers.MID_H)
            put(f"mid_{era}", p, look_mid(p))
            save_lit(p, os.path.join(out, f"mid_{era}_lit.png"))
    if "places" in what:
        for kind in layers.PLACES:
            p = render_strip(layers.draw_place, (kind,), PLACE_W, layers.PLACE_H)
            put(f"far_{kind}", p, look_place(p))
            save_lit(p, os.path.join(out, f"far_{kind}_lit.png"))
    if "trees" in what:
        for kind in layers.TREES:
            for season in layers.SEASONS:
                p = render_tree(kind, season)
                put(f"tree_{kind}_{season}", p, look_tree(p, kind, season))
    if "fore" in what:
        for kind in layers.FORE_KINDS:
            p = render_fore(kind)
            put(f"fore_{kind}", p, look_fore(p, kind))
    return done


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("what", nargs="*", default=["far", "mid", "places", "trees", "fore"])
    ap.add_argument("--out", default=OUT)
    a = ap.parse_args()
    build(a.what or ["far", "mid", "places", "trees", "fore"], a.out)


if __name__ == "__main__":
    main()
