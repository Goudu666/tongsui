"""精灵（家里的东西、街景）共用的一层：在 pxlib 上再收紧一点，让小东西的线和块都落在点上。

底图大，pxlib 的通用合成（三块版按 3×3 收拢）够用；精灵小，一根 0.9 宽、不在格子上的线收拢以后
会变成一串半深不浅的点，一个 r=1 的小圆点会变成一块浅色的毛边。所以画精灵的时候换一套「落点」的画法：

  crisp(g)：在这张纸上画的时候（只在这段 with 里）——
    · 线：每个拐点挪到它所在那个点的正中，线宽一律一个点（≥3.4 的粗线两个点，拐点挪到格子角上），平头；
          整根线缩成一个点的（很短的小刻度）就印一个点
    · 填色、挖空、裁切：拐点挪到最近的格子角上——填的块正好是整点，描边正好压在块的最外一圈点上
    · 小圆点（r < 2.4）：就是它所在的那一个点；大一点的：圆心挪到点中，按半径数点
  这些都是在设备坐标（纸像素）里挪的，所以镜像（梅家）、平移旋转（place）都照样对。

  clean(...)：合成以后收拾毛边——只是被半根线碰到、既不是线也不在纸版里的点，去掉。
  outline(...)：外轮廓上没有墨线的地方补一圈（小精灵贴在什么底上都看得清）。
"""
from __future__ import annotations

import math
import os
import sys
from contextlib import contextmanager

import cairo
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)
import riso  # noqa: E402
import pxlib  # noqa: E402

PX = pxlib.PX


def npts(w):
    """原来 w 宽的线，落成几个点宽。"""
    return max(1, int(w / PX + 0.5))


def dev_w(n):
    """n 个点宽的线，在纸上画多宽：奇数个点线心在点中，偶数个点线心在格子线上；两边各留一点，不碰邻点。"""
    return n * PX - (1.0 if n % 2 else 1.5)


def _snapper(g, ctx, mode):
    """回来一个函数：用户坐标的点 → 挪好以后的用户坐标。mode = center / corner。"""
    ox, oy, s = pxlib._grid(g)

    def f(p):
        dx, dy = ctx.user_to_device(float(p[0]), float(p[1]))
        if mode == "center":
            dx = ox + (math.floor((dx - ox) / s) + 0.5) * s
            dy = oy + (math.floor((dy - oy) / s) + 0.5) * s
        else:
            dx = ox + round((dx - ox) / s) * s
            dy = oy + round((dy - oy) / s) * s
        return ctx.device_to_user(dx, dy)
    return f


def _dedupe(pts):
    out = []
    for p in pts:
        if not out or abs(out[-1][0] - p[0]) > 1e-6 or abs(out[-1][1] - p[1]) > 1e-6:
            out.append(p)
    return out


def _cell(ctx, g, p, density):
    """把用户坐标 p 所在的那个点整个涂上。"""
    ox, oy, s = pxlib._grid(g)
    dx, dy = ctx.user_to_device(float(p[0]), float(p[1]))
    cx = ox + math.floor((dx - ox) / s) * s
    cy = oy + math.floor((dy - oy) / s) * s
    ctx.save()
    ctx.identity_matrix()
    ctx.new_path()
    ctx.rectangle(cx, cy, s, s)
    ctx.set_operator(cairo.OPERATOR_OVER)
    ctx.set_source_rgba(0, 0, 0, density)
    ctx.fill()
    ctx.restore()


SOFT_W = 1.1      # 比这细的墨线（细部：刻度、按键、钩花的小眼）不描成墨线，落成一道暗一档的颜色
SOFT = 0.42       # 落成墨的浅色版的多少
SOFT_DOT = 0.5    # 小圆点按直径 × 这个数比 SOFT_W（r < 1.1 的算细部）


def _soft(pen, w, density):
    """细的墨线 → 墨的浅色版（合成时是压暗一档，不是一道黑线）。回来 (画在哪块版上, 浓度)。"""
    dens = pen.density if density is None else density
    if pen.color == "ink" and pen.tint is None and w < SOFT_W:
        return pen.sheet.plates["ink"]["tint"], dens * SOFT
    return pen.ctx, dens


@contextmanager
def crisp(g):
    """画这张纸的时候，线和块都落在点上（见文件头）。只改这张纸：别的纸照旧。"""
    P, S = riso.Pen, riso.Sheet
    saved = {(P, "line"): P.line, (P, "poly"): P.poly, (P, "dot"): P.dot, (S, "clear"): S.clear, (S, "clip"): S.clip}
    sub = type(g) if (type(g) is not S and "clear" in type(g).__dict__) else None
    if sub is not None:
        saved[(sub, "clear")] = sub.__dict__["clear"]
    mine = lambda obj: (obj.sheet if isinstance(obj, P) else obj) is g  # noqa: E731

    def line(self, pts, w=3.0, amp=0.9, cap="round", density=None, dash=None):
        if not mine(self) or len(pts) < 1:
            return saved[(P, "line")](self, pts, w, amp, cap, density, dash)
        n = npts(w)
        c, dens = _soft(self, w, density)
        f = _snapper(g, c, "center" if n % 2 else "corner")
        q = _dedupe([f(p) for p in pts])
        if len(q) == 1:
            if n == 1:
                _cell(c, g, pts[0], dens)
            return self
        c.new_path()
        c.move_to(*q[0])
        for p in q[1:]:
            c.line_to(*p)
        c.set_line_width(dev_w(n))
        c.set_line_cap(cairo.LINE_CAP_BUTT if n == 1 else cairo.LINE_CAP_SQUARE)
        c.set_line_join(cairo.LINE_JOIN_ROUND)
        c.set_operator(cairo.OPERATOR_OVER)
        c.set_source_rgba(0, 0, 0, dens)
        c.stroke()
        # 平头的线两头各差半个点：头尾两个点补满
        if n == 1:
            for p in (pts[0], pts[-1]):
                _cell(c, g, p, dens)
        return self

    def poly(self, pts, w=3.0, fill=False, stroke=True, amp=0.9, density=None, fill_density=None):
        if not mine(self):
            return saved[(P, "poly")](self, pts, w, fill, stroke, amp, density, fill_density)
        if fill:
            f = _snapper(g, self.ctx, "corner")
            q = _dedupe([f(p) for p in pts])
            if len(q) >= 3:
                self._path(q, True)
                self._src(fill_density if fill_density is not None else density)
                self.ctx.fill()
        if stroke:
            line(self, list(pts) + [pts[0]], w, amp, "round", density)
        return self

    def dot(self, x, y, r=2.0, density=None):
        if not mine(self):
            return saved[(P, "dot")](self, x, y, r, density)
        dens = self.density if density is None else density
        if r < 2.4:
            c, dens = _soft(self, r * 2 * SOFT_DOT, density)
            _cell(c, g, (x, y), dens)
            return self
        # 圆心落到点中，半径以内的点都涂上
        n = int(math.ceil(r / PX)) + 1
        for j in range(-n, n + 1):
            for i in range(-n, n + 1):
                if math.hypot(i * PX, j * PX) <= r + 0.6:
                    _cell(self.ctx, g, (x + i * PX, y + j * PX), dens)
        return self

    def snapped_clear(base):
        def clear(self, pts, colors=None, layers=("solid", "tint")):
            if mine(self) and len(pts) >= 3:
                f = _snapper(g, self.plates["ink"]["solid"], "corner")
                q = _dedupe([f(p) for p in pts])
                if len(q) < 3:
                    return
                pts = q
            return base(self, pts, colors, layers)
        return clear
    clear = snapped_clear(saved[(S, "clear")])

    @contextmanager
    def clip(self, pts):
        if mine(self) and len(pts) >= 3:
            f = _snapper(g, self.plates["ink"]["solid"], "corner")
            pts = _dedupe([f(p) for p in pts]) or pts
        with saved[(S, "clip")](self, pts):
            yield

    P.line, P.poly, P.dot, S.clear, S.clip = line, poly, dot, clear, clip
    if sub is not None:
        sub.clear = snapped_clear(saved[(sub, "clear")])
    try:
        yield g
    finally:
        for (cls, name), fn in saved.items():
            setattr(cls, name, fn)


# ----------------------------------------------------------------------
# 合成以后
# ----------------------------------------------------------------------

def pooled(d, pa):
    """几样常用的「每个点」的量。"""
    ink_s, ink_t = d["ink"]
    return dict(
        line=pxlib.pool(ink_s, PX, "max"),
        ink=pxlib.pool(ink_s, PX, "mean"),
        ink_t=pxlib.pool(ink_t, PX, "mean"),
        q=pxlib.pool(np.maximum(*d["qing"]), PX, "mean"),
        m=pxlib.pool(np.maximum(*d["mei"]), PX, "mean"),
        paper=pxlib.pool(pa, PX, "mean"),
    )


def clean(col, alpha, line, pl):
    """只是被半根线碰到、不是线、也不在纸版里的点（多出来的一圈毛边）去掉。"""
    body = (pl["paper"] > 0.34) | (pl["q"] > 0.3) | (pl["m"] > 0.3) | (pl["ink_t"] > 0.4)
    fringe = ~line & ~body & (alpha > 0.4)
    alpha = alpha.copy()
    alpha[fringe] = 0.0
    return col, alpha, line


def outline(rgba, color=None, where=None):
    """外轮廓补一圈墨线：透明的点挨着（上下左右）不透明的点、而那个点不是墨线色的，就补上。
    where：只在这些点补（布尔，和 rgba 同形），None = 全补。"""
    color = np.asarray(pxlib.C["line"] if color is None else color, np.uint8)
    a = rgba[..., 3] == 255
    near = pxlib._shift(a, 1, 0) | pxlib._shift(a, -1, 0) | pxlib._shift(a, 0, 1) | pxlib._shift(a, 0, -1)
    add = near & ~a
    if where is not None:
        add &= where
    out = rgba.copy()
    out[add, :3] = color
    out[add, 3] = 255
    return out


def finish(col, alpha, line, dither=None, gx=0, gy=0):
    """和 pxlib.finish 一样落到调色板上，但精灵默认不抖动：小块面上的拜耳网格只会是一片棋盘格。
    dither：要抖的点（布尔），None = 都不抖。"""
    cent = pxlib.load_palette()
    d = np.zeros(line.shape, bool) if dither is None else dither & ~line
    out = pxlib.quantize(col, cent, d, gx, gy)
    a = (alpha > 0.4).astype(np.uint8) * 255
    return np.dstack([out.clip(0, 255).astype(np.uint8), a])


def selout(col, alpha, line, keep=5, dark=0.58):
    """人身上的里线换成「旁边那块颜色暗一档」（外轮廓、眼睛眉毛这类孤立的小点照旧是墨线）。
    小人只有三十来个点高，里外全是黑线就成了一团黑；里线换色以后衣服、胳膊、脸各自分得开。
    keep：一个线点周围 5×5 里线点不超过这么多，算孤立的小点（眼睛、扣子），不动。"""
    op = alpha > 0.4
    sh = pxlib._shift
    nb8 = [(dx, dy) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dx or dy]
    interior = line.copy()
    for dx, dy in nb8:
        interior &= sh(op, dx, dy)
    cnt = np.zeros(line.shape, np.int32)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            cnt += sh(line, dx, dy)
    acc = np.zeros(col.shape, np.float32)
    n = np.zeros(line.shape, np.float32)
    fill = op & ~line
    for dx, dy in nb8:
        f = sh(fill, dx, dy)
        acc += np.stack([sh(col[..., k] * fill, dx, dy) for k in range(3)], -1)
        n += f
    mean = acc / np.maximum(n, 1)[..., None]
    # 挨着纸色（脸、手）的线不动：眼睛、嘴、手指头靠它
    skin = np.zeros(line.shape, bool)
    for dx, dy in nb8:
        skin |= sh(fill & (np.abs(col - pxlib.C["paper"]).sum(-1) < 40), dx, dy)
    go = interior & (cnt > keep) & (n >= 2) & ~skin
    out = col.copy()
    out[go] = mean[go] * dark + pxlib.C["shade"] * (1 - dark) * 0.6 + mean[go] * (1 - dark) * 0.4 * 0.5
    return out, line & ~go
