"""像素画的共用一层：把 riso.Sheet 上画的三块版（墨、青、梅）收成一张像素画。

所有老画法（scenes / layers / home / street / folks）都在 riso.Sheet 上画；这里不重写它们，
只做两件事：
  1. enable()：换掉几样「孔版味」的画法——
       · 手抖的线 → 直线（wobble 不抖）
       · 排线 → 一层浅色（像素里排线只会变成一排噪点）
       · 砖缝 → 记进一块「砖」版，合成时按点阵铺砖
       · 字 → 点阵字（缝合像素 12px），落在 3×3 的格子上
  2. compose()：三块版 → 每 PX 世界像素一个点的颜色，按材质上色，再压到固定调色板。

固定调色板（palette.json）十几张图共用，所以各张图、各片之间颜色接得上。
"""
from __future__ import annotations

import json
import math
import os
import sys

import cairo
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import riso  # noqa: E402

PX = 3
BAYER = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0
FONTS = {8: os.path.join(HERE, "fonts", "fusion-pixel-8px-proportional-zh_hans.otf"),
         10: os.path.join(HERE, "fonts", "fusion-pixel-10px-proportional-zh_hans.otf"),
         12: os.path.join(HERE, "fonts", "fusion-pixel-12px-proportional-zh_hans.ttf")}
PAL_PATH = os.path.join(HERE, "palette.json")


def _h(s):
    return np.array([int(s[i:i + 2], 16) for i in (1, 3, 5)], np.float32)


# 材质色。纸 = 抹灰墙；梅 = 红砖、红漆；青 = 绿漆、树、水；墨的浅色 = 影子
C = {
    "paper": _h("#F2E4C9"),
    "paper_lo": _h("#D9C3A5"),
    "mei": _h("#C24A3E"),
    "mei_hi": _h("#E9876B"),
    "mei_lo": _h("#8E3036"),
    "qing": _h("#2C8A76"),
    "qing_hi": _h("#7DC6A3"),
    "qing_lo": _h("#1E5E58"),
    "plum": _h("#6B3A58"),
    "shade": _h("#3A3150"),
    "mortar": _h("#E7C6A8"),
    "line": _h("#281D2C"),
}


# ----------------------------------------------------------------------
# 1. 换画法
# ----------------------------------------------------------------------

_ON = False
GRID0 = (0.0, -200.0)   # 格子从哪个世界坐标起（scenes 的切片从 y = TOP 画起）


def _grid(g):
    """这张纸上 3×3 格子的原点（纸像素）和一格多大（纸像素）。"""
    s = g.scale * PX
    ox = ((GRID0[0] - g.origin[0]) * g.scale) % s
    oy = ((GRID0[1] - g.origin[1]) * g.scale) % s
    return ox, oy, s


MARKS = ("brick", "glass")   # 记号版：不印墨，只记「这块是砖墙 / 玻璃」，合成时按点阵铺


def _mark_ctx(g, name):
    if not hasattr(g, "_marks"):
        g._marks = {}
    if name not in g._marks:
        surf = cairo.ImageSurface(cairo.FORMAT_A8, g.W, g.H)
        ctx = cairo.Context(surf)
        ctx.scale(g.scale, g.scale)
        ctx.translate(-g.origin[0], -g.origin[1])
        g._marks[name] = (surf, ctx)
    return g._marks[name][1]


def _brick_ctx(g):
    return _mark_ctx(g, "brick")


def mark_rect(g, name, x, y, w, h):
    c = _mark_ctx(g, name)
    c.rectangle(x, y, w, h)
    c.set_source_rgba(0, 0, 0, 1)
    c.fill()


def mark_mask(g, name):
    if not hasattr(g, "_marks") or name not in g._marks:
        return np.zeros((g.H, g.W), np.float32)
    surf = g._marks[name][0]
    surf.flush()
    buf = np.ndarray((g.H, surf.get_stride()), np.uint8, surf.get_data())
    return buf[:, : g.W].astype(np.float32) / 255.0


def brick_mask(g):
    return mark_mask(g, "brick")


def pick_font(a):
    """字高 a 个点 → (几号点阵字, 放大几倍)。"""
    if a < 10.5:
        return 8, 1
    if a < 12.5:
        return 10, 1
    return 12, max(1, int(a / 18 + 0.5))


def _glyphs(text, n, vertical, px=12):
    """点阵字：一个字 px 个点高，n 倍。返回 0/1 的 L 图（点为单位）。"""
    f = ImageFont.truetype(FONTS[px], px)
    if vertical:
        step = px + 1
        img = Image.new("L", (px + 2, step * len(text) + 2), 0)
        d = ImageDraw.Draw(img)
        for i, ch in enumerate(text):
            d.text((1, step * i + 1), ch, font=f, fill=255)
    else:
        w = int(math.ceil(f.getlength(text))) + 2
        img = Image.new("L", (w, px + 4), 0)
        d = ImageDraw.Draw(img)
        d.text((1, 1), text, font=f, fill=255)
    img = img.point(lambda v: 255 if v > 110 else 0)
    bb = img.getbbox()
    if bb is None:
        return None
    img = img.crop(bb)
    if n > 1:
        img = img.resize((img.width * n, img.height * n), Image.NEAREST)
    return img


def _pixel_text_mask(g, text, x, y, size, anchor, vertical):
    """在纸上（纸像素）落一块点阵字：返回 (mask, ox, oy)，对齐到 3×3 格子。"""
    px, n = pick_font(size / PX)
    gl = _glyphs(text, n, vertical, px)
    if gl is None:
        return None
    gx, gy, s = _grid(g)
    S = g.scale
    big = gl.resize((int(round(gl.width * s)), int(round(gl.height * s))), Image.NEAREST)
    px = (x - g.origin[0]) * S
    py = (y - g.origin[1]) * S
    ax = {"l": 0, "m": 0.5, "r": 1}[anchor[0]]
    ay = {"t": 0, "m": 0.5, "b": 1, "s": 0.85}[anchor[1]]
    ox = px - ax * big.width
    oy = py - ay * big.height
    ox = int(round(gx + round((ox - gx) / s) * s))
    oy = int(round(gy + round((oy - gy) / s) * s))
    return big, ox, oy


def enable():
    """换上像素画法（只换一次）。scenes 要在这之前 import。"""
    global _ON
    if _ON:
        return
    _ON = True

    riso.wobble = lambda pts, amp=0.9, step=16.0, seed=0, closed=False: [tuple(p) for p in pts]

    def hatch(self, pts, angle=45.0, gap=10.0, w=1.6, amp=0.5, density=None):
        d = (self.density if density is None else density) * min(1.0, 1.5 * w / gap)
        self.fill(pts, density=d)
        return self

    def bricks(self, x, y, w, h, bw=34.0, bh=12.0, lw=1.4, density=None, seed=None):
        c = _brick_ctx(self.sheet)
        c.rectangle(x, y, w, h)
        c.set_source_rgba(0, 0, 0, 1)
        c.fill()
        return self

    riso.Pen.hatch = hatch
    riso.Pen.bricks = bricks

    old_clear = riso.Sheet.clear

    def clear(self, pts, colors=None, layers=("solid", "tint")):
        old_clear(self, pts, colors, layers)
        for surf, c in (getattr(self, "_marks", {}).values() if colors is None else ()):
            c.save()
            c.new_path()
            c.move_to(*pts[0])
            for p in pts[1:]:
                c.line_to(*p)
            c.close_path()
            c.set_operator(cairo.OPERATOR_CLEAR)
            c.fill()
            c.restore()

    riso.Sheet.clear = clear

    def text(self, color, tint, s, x, y, size, anchor="mm", density=1.0, vertical=False):
        r = _pixel_text_mask(self, s, x, y, size, anchor, vertical)
        if r is None:
            return
        img, ox, oy = r
        self._blit(color, "tint" if tint else "solid", img, ox, oy, density)

    riso.Sheet.text = text

    import scenes  # noqa: E402

    def fbricks(g, x, y, w, h, bw=30.0, bh=11.0, lw=0.9, d=0.32, seed=1):
        if not scenes.visible(g, x, x + w):
            return
        c = _brick_ctx(g)
        c.rectangle(x, y, w, h)
        c.set_source_rgba(0, 0, 0, 1)
        c.fill()

    def fhatch(g, color, x, y, w, h, angle=45.0, gap=9.0, lw=1.2, d=1.0, tint=False):
        if not scenes.visible(g, x, x + w):
            return
        c = scenes._ctx(g, color, tint)
        c.rectangle(x, y, w, h)
        c.set_source_rgba(0, 0, 0, d * min(1.0, 1.5 * lw / gap))
        c.fill()

    def knock(g, color, text, x, y, size, vertical=False, layer="solid"):
        r = _pixel_text_mask(g, text, x, y, size, "mm", vertical)
        if r is None:
            return
        img, ox, oy = r
        m = np.asarray(img, np.float32) / 255.0
        H, W = m.shape
        x0, y0 = max(0, ox), max(0, oy)
        x1, y1 = min(g.W, ox + W), min(g.H, oy + H)
        if x1 <= x0 or y1 <= y0:
            return
        surf = g._surfaces[(color, layer)]
        surf.flush()
        buf = np.ndarray((g.H, surf.get_stride()), np.uint8, surf.get_data())
        sub = buf[y0:y1, x0:x1].astype(np.float32)
        sub *= 1.0 - m[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
        buf[y0:y1, x0:x1] = sub.astype(np.uint8)
        surf.mark_dirty()

    old_window = scenes.window

    def window(g, x, y, w, h, panes=2, lit=False, frame="ink", curtain=None, sill=True, glass=True, night=False):
        old_window(g, x, y, w, h, panes, lit, frame, curtain, sill, glass, night)
        if glass and not lit:
            mark_rect(g, "glass", x, y, w, h)

    scenes.window = window
    scenes.fbricks = fbricks
    scenes.fhatch = fhatch
    scenes.knock = knock


# ----------------------------------------------------------------------
# 2. 合成
# ----------------------------------------------------------------------

def pool(a, k, how):
    H, W = a.shape[0] // k * k, a.shape[1] // k * k
    b = a[:H, :W].reshape(H // k, k, W // k, k)
    return b.max(axis=(1, 3)) if how == "max" else b.mean(axis=(1, 3))


def paper_alpha(g):
    g._paper.flush()
    buf = np.ndarray((g.H, g._paper.get_stride()), np.uint8, g._paper.get_data())
    return buf[:, : g.W].astype(np.float32) / 255.0


def plates(g, crop):
    """纸像素的各版浓度，裁掉 crop=(y0, y1, x0, x1)，要求对齐 3×3 格子。"""
    y0, y1, x0, x1 = crop
    d = {}
    for c in ("ink", "qing", "mei"):
        d[c] = (g.density(c, "solid")[y0:y1, x0:x1], g.density(c, "tint")[y0:y1, x0:x1])
    br = {n: mark_mask(g, n)[y0:y1, x0:x1] for n in MARKS}
    return d, paper_alpha(g)[y0:y1, x0:x1], br


def _shift(a, dx, dy):
    out = np.zeros_like(a)
    H, W = a.shape
    out[max(0, dy):H + min(0, dy), max(0, dx):W + min(0, dx)] = a[max(0, -dy):H - max(0, dy), max(0, -dx):W - max(0, dx)]
    return out


def _erode(m, r):
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out &= _shift(m, dx, dy)
    return out


def _dilate(m, r):
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out |= _shift(m, dx, dy)
    return out


def compose(d, pa, br, k=PX, gx=0, gy=0, relief=True, vshade=None):
    """各版浓度（纸像素，每 k 个一格）→ 每格的颜色、不透明度、描线。
    gx, gy：这块左上角是第几个点（世界坐标 / PX），砖缝按它对齐，各片接得上。"""
    ink_s, ink_t = d["ink"]
    line = pool(ink_s, k, "max")
    ink_avg = pool(ink_s, k, "mean")
    ink_tint = pool(ink_t, k, "mean")
    q = pool(np.maximum(*d["qing"]), k, "mean")
    qs = pool(d["qing"][0], k, "mean")
    m = pool(np.maximum(*d["mei"]), k, "mean")
    ms = pool(d["mei"][0], k, "mean")
    brk = pool(br["brick"], k, "mean") > 0.5
    gls = pool(br["glass"], k, "mean") > 0.5
    alpha = np.maximum.reduce([pool(pa, k, "max"), line, ink_tint, q, m])
    H, W = q.shape

    def ramp(dd, hi, base, col):
        t = np.clip(dd / 0.7, 0, 1)[..., None]
        c1 = col + (hi - col) * np.clip(t * 2, 0, 1)
        return c1 + (base - c1) * np.clip(t * 2 - 1, 0, 1)

    col = np.broadcast_to(C["paper"], (H, W, 3)).copy()
    col = ramp(m, C["mei_hi"], C["mei"], col)
    both = np.clip(np.minimum(q, m) * 2.0, 0, 1)[..., None]
    col = ramp(q, C["qing_hi"], C["qing"], col) * (1 - both) + C["plum"] * both

    # 砖：一块 8×3 个点（横缝 1 点、竖缝错半块）；红砖墙上明显，灰墙上淡
    if brk.any():
        yy = (np.arange(H) + gy)[:, None]
        xx = (np.arange(W) + gx)[None, :]
        row = yy // 4
        mortar_h = (yy % 4) == 3
        mortar_v = ((xx + (row % 2) * 5) % 10) == 0
        # 每块砖深浅不一（按砖的编号哈希）
        bid = (xx + (row % 2) * 5) // 10
        hsh = ((bid * 73856093) ^ (row * 19349663)) & 0xFF
        var = (hsh / 255.0 - 0.5)[..., None]
        red = (m > 0.25)[..., None]
        on = brk[..., None]
        mort = (mortar_h | mortar_v)[..., None]
        brick_col = col * (1 + 0.10 * var)
        brick_col = np.where(red, brick_col, col * (1 - 0.05 + 0.06 * var))
        mort_col = np.where(red, C["mortar"] * 0.92 + col * 0.08, col * 0.86 + C["shade"] * 0.14)
        col = np.where(on, np.where(mort, mort_col, brick_col), col)

    # 玻璃：浅青的一块，斜着两道反光
    glass = gls & (line < 0.6)
    if glass.any():
        yy = (np.arange(H) + gy)[:, None]
        xx = (np.arange(W) + gx)[None, :]
        dg = (xx + yy) % 13
        glint = glass & ((dg == 0) | (dg == 1) | (dg == 4))
        col[glint] = col[glint] * 0.45 + 255 * 0.55

    # 大片平涂（抹灰墙、水泥地、马路）上撒一点点麻点：按点的编号哈希，各片接得上
    yy = (np.arange(H) + gy)[:, None]
    xx = (np.arange(W) + gx)[None, :]
    hs = ((xx * 374761393 + yy * 668265263) ^ ((xx * 2246822519) >> 7)) & 0xFFFF
    flat = ~brk & ~gls & (q < 0.05) & (alpha > 0.5)
    speck = flat & (hs < 0.03 * 65536)
    col[speck] = col[speck] * 0.93
    lite = flat & (hs > 0.985 * 65536)
    col[lite] = col[lite] * 0.96 + 255 * 0.04

    # 墨的浅色 → 影子；细线、排线的平均 → 也压暗一点
    sh = np.clip(ink_tint * 1.1 + ink_avg * 0.45, 0, 0.92)[..., None]
    if vshade is not None:
        sh = np.clip(sh + vshade[:H, None, None], 0, 0.92)
    col = col * (1 - sh) + C["shade"] * sh

    is_line = (line > 0.6) & (ink_avg > 0.16)

    if relief:
        # 成块的东西（招牌、雨棚、檐口、门、家具）往右下投一道硬影子
        solid = (np.maximum.reduce([ink_avg, qs, ms]) > 0.55) | is_line
        blk = _dilate(_erode(solid, 1), 1)
        cast = _shift(blk, 2, 2) & ~blk & ~is_line & (alpha > 0.5)
        col[cast] = col[cast] * 0.72 + C["shade"] * 0.28
    col[is_line] = C["line"]
    return col, alpha, is_line


# ----------------------------------------------------------------------
# 3. 调色板
# ----------------------------------------------------------------------

def load_palette():
    if os.path.exists(PAL_PATH):
        with open(PAL_PATH) as f:
            return np.array([_h(c) for c in json.load(f)["colors"]], np.float32)
    return None


def fit_palette(cols, k=48, seed=3):
    """材质本色钉死（平涂的墙、砖、漆正好落在色上，不起抖动的点），其余 k 色按图里的颜色聚。"""
    rng = np.random.default_rng(seed)
    pts = np.concatenate([c.reshape(-1, 3) for c in cols])
    samp = pts[rng.integers(0, len(pts), min(60000, len(pts)))]
    fixed = np.array([v for kk, v in C.items()], np.float32)
    nf = len(fixed)
    cent = list(fixed)
    for _ in range(k):
        dd = ((samp[:, None, :] - np.array(cent)[None]) ** 2).sum(-1).min(1)
        cent.append(samp[rng.choice(len(samp), p=dd / dd.sum())])
    cent = np.array(cent)
    for _ in range(20):
        dd = ((samp[:, None, :] - cent[None]) ** 2).sum(-1)
        lab = dd.argmin(1)
        for j in range(nf, len(cent)):
            sel = samp[lab == j]
            if len(sel):
                cent[j] = sel.mean(0)
    return np.round(cent).clip(0, 255)


def save_palette(cent):
    with open(PAL_PATH, "w") as f:
        json.dump({"colors": ["#%02X%02X%02X" % tuple(int(v) for v in c) for c in cent]}, f, indent=0)


def quantize(col, cent, dither, gx=0, gy=0):
    H, W, _ = col.shape
    flat = col.reshape(-1, 3)
    out = np.empty(len(flat), np.int64)
    by = BAYER[(np.arange(H)[:, None] + gy) % 4, (np.arange(W)[None] + gx) % 4].reshape(-1)
    dth = dither.reshape(-1)
    step = 200000
    for i in range(0, len(flat), step):
        f = flat[i:i + step]
        dd = ((f[:, None, :] - cent[None]) ** 2).sum(-1)
        o = np.argsort(dd, 1)[:, :2]
        d1 = np.sqrt(np.take_along_axis(dd, o[:, :1], 1))[:, 0]
        d2 = np.sqrt(np.take_along_axis(dd, o[:, 1:2], 1))[:, 0]
        t = d1 / (d1 + d2 + 1e-6)
        out[i:i + step] = np.where(dth[i:i + step] & (by[i:i + step] < t), o[:, 1], o[:, 0])
    return cent[out].reshape(H, W, 3)


def finish(col, alpha, is_line, cent=None, gx=0, gy=0):
    """颜色 → 调色板 → RGBA uint8（每个点一个像素）。"""
    if cent is None:
        cent = load_palette()
    if cent is None:
        cent = fit_palette([col[alpha > 0.5]])
    out = quantize(col, cent, ~is_line, gx, gy)
    a = (alpha > 0.4).astype(np.uint8) * 255
    return np.dstack([out.clip(0, 255).astype(np.uint8), a])


def up(arr, k):
    return np.repeat(np.repeat(arr, k, 0), k, 1)
