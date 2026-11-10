"""孔版套色（Risograph）印刷模拟。

《同岁》所有美术都"印"在一张米白纸上，只用三块版：
  墨 ink  #2B2A33   线稿、阴影
  青 qing #2E8B7A   海河、树、玩家「青」
  梅 mei  #D9485F   红砖楼、招牌、玩家「梅」
两块专色叠在一起就是深紫（共同回忆的颜色）。

每块版有两层：
  solid 实地：线、实心块，边缘抗锯齿
  tint  网点：浅色铺底，合成时转成带颗粒的调幅网点（每块版网角不同）
合成时青、梅两块版各自错位一两个像素，像真的孔版套印一样。

坐标一律用"世界像素"（和 content/map.yaml 一致），Sheet 按 scale 倍超采样输出。
"""
from __future__ import annotations

import math
import os
import random
from contextlib import contextmanager

import cairo
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

PAPER = (0xF4, 0xEE, 0xE1)
COLORS = {
    "ink": (0x2B, 0x2A, 0x33),
    "qing": (0x2E, 0x8B, 0x7A),
    "mei": (0xD9, 0x48, 0x5F),
}
# 网角：三块版错开，避免撞网
SCREEN_ANGLE = {"ink": 45.0, "qing": 15.0, "mei": 75.0}
# 套印错位（输出像素）。只给专色，墨版是基准
MISREG = {"ink": (0, 0), "qing": (2, 1), "mei": (-1, 2)}

FONT_CANDIDATES = [
    os.path.join(ROOT, "client", "fonts", "LXGWWenKai-Regular.ttf"),
    "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
]


def font_path() -> str:
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            return p
    raise FileNotFoundError("找不到中文字体：先运行 bash tools/fetch_addons.sh 下载霞鹜文楷")


# ----------------------------------------------------------------------
# 手绘感
# ----------------------------------------------------------------------

def wobble(pts, amp=0.9, step=16.0, seed=0, closed=False):
    """把折线细分并加一点平滑抖动，像手画的线。amp=0 时原样返回。"""
    pts = [tuple(map(float, p)) for p in pts]
    if amp <= 0 or len(pts) < 2:
        return pts
    if closed:
        pts = pts + [pts[0]]
    rnd = random.Random(seed)
    ph = [rnd.uniform(0, 6.283) for _ in range(4)]
    out = []
    acc = 0.0
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        L = math.hypot(x1 - x0, y1 - y0)
        n = max(1, int(L / step))
        nx, ny = (-(y1 - y0) / L, (x1 - x0) / L) if L > 0 else (0.0, 0.0)
        for k in range(n):
            t = k / n
            s = acc + t * L
            off = amp * (0.6 * math.sin(s * 0.031 + ph[0]) + 0.4 * math.sin(s * 0.093 + ph[1]))
            out.append((x0 + (x1 - x0) * t + nx * off, y0 + (y1 - y0) * t + ny * off))
        acc += L
    if closed:
        out.append(out[0])
    else:
        out.append(pts[-1])
    return out


def rect_pts(x, y, w, h):
    return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]


def circle_pts(cx, cy, r, n=None):
    n = n or max(12, int(r * 0.8))
    return [(cx + r * math.cos(a * math.tau / n), cy + r * math.sin(a * math.tau / n)) for a in range(n)]


def ellipse_pts(cx, cy, rx, ry, n=None):
    n = n or max(12, int(max(rx, ry) * 0.8))
    return [(cx + rx * math.cos(a * math.tau / n), cy + ry * math.sin(a * math.tau / n)) for a in range(n)]


# ----------------------------------------------------------------------
# 画笔
# ----------------------------------------------------------------------

class Pen:
    """在一块版上画东西。density 是这一笔的浓度：solid 版通常 1，tint 版 0.1~0.6。"""

    def __init__(self, sheet: "Sheet", color: str, tint: float | None):
        self.sheet = sheet
        self.color = color
        self.tint = tint
        plate = sheet.plates[color]
        self.ctx: cairo.Context = plate["tint"] if tint is not None else plate["solid"]
        self.density = tint if tint is not None else 1.0
        self.seed = sheet.next_seed()

    def _src(self, density=None):
        self.ctx.set_operator(cairo.OPERATOR_OVER)
        self.ctx.set_source_rgba(0, 0, 0, self.density if density is None else density)

    def _path(self, pts, closed):
        c = self.ctx
        c.new_path()
        c.move_to(*pts[0])
        for p in pts[1:]:
            c.line_to(*p)
        if closed:
            c.close_path()

    # --- 线 ---
    def line(self, pts, w=3.0, amp=0.9, cap="round", density=None, dash=None):
        pts = wobble(pts, amp, seed=self.sheet.next_seed())
        self._path(pts, False)
        self._stroke(w, cap, density, dash)
        return self

    def poly(self, pts, w=3.0, fill=False, stroke=True, amp=0.9, density=None, fill_density=None):
        if fill:
            self._path([tuple(p) for p in pts], True)
            self._src(fill_density if fill_density is not None else density)
            self.ctx.fill()
        if stroke:
            self._path(wobble(pts, amp, seed=self.sheet.next_seed(), closed=True), True)
            self._stroke(w, "round", density)
        return self

    def fill(self, pts, density=None):
        return self.poly(pts, fill=True, stroke=False, density=density)

    def rect(self, x, y, w, h, lw=3.0, fill=False, stroke=True, amp=0.9, density=None):
        return self.poly(rect_pts(x, y, w, h), lw, fill, stroke, amp, density)

    def box(self, x, y, w, h, lw=3.0, over=8.0, amp=0.9, density=None):
        """建筑草图式方框：四条边两头各出头 over 像素。"""
        self.line([(x - over, y), (x + w + over, y)], lw, amp, density=density)
        self.line([(x - over, y + h), (x + w + over, y + h)], lw, amp, density=density)
        self.line([(x, y - over), (x, y + h + over)], lw, amp, density=density)
        self.line([(x + w, y - over), (x + w, y + h + over)], lw, amp, density=density)
        return self

    def circle(self, cx, cy, r, lw=3.0, fill=False, stroke=True, amp=0.6, density=None):
        return self.poly(circle_pts(cx, cy, r), lw, fill, stroke, amp, density)

    def ellipse(self, cx, cy, rx, ry, lw=3.0, fill=False, stroke=True, amp=0.6, density=None):
        return self.poly(ellipse_pts(cx, cy, rx, ry), lw, fill, stroke, amp, density)

    def arc(self, cx, cy, r, a0, a1, lw=3.0, amp=0.4, density=None):
        n = max(6, int(abs(a1 - a0) * r / 6))
        pts = [(cx + r * math.cos(a0 + (a1 - a0) * i / n), cy + r * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]
        return self.line(pts, lw, amp, density=density)

    def dot(self, x, y, r=2.0, density=None):
        self.ctx.new_path()
        self.ctx.arc(x, y, r, 0, math.tau)
        self._src(density)
        self.ctx.fill()
        return self

    def _stroke(self, w, cap, density, dash=None):
        c = self.ctx
        c.set_line_width(w)
        c.set_line_cap({"round": cairo.LINE_CAP_ROUND, "butt": cairo.LINE_CAP_BUTT, "square": cairo.LINE_CAP_SQUARE}[cap])
        c.set_line_join(cairo.LINE_JOIN_ROUND)
        if dash:
            c.set_dash(dash)
        self._src(density)
        c.stroke()
        if dash:
            c.set_dash([])

    # --- 纹理 ---
    def hatch(self, pts, angle=45.0, gap=10.0, w=1.6, amp=0.5, density=None):
        """在多边形里画平行排线（阴影、草地、水面都用它）。"""
        c = self.ctx
        c.save()
        self._path([tuple(p) for p in pts], True)
        c.clip()
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        R = math.hypot(max(xs) - min(xs), max(ys) - min(ys)) / 2 + gap
        a = math.radians(angle)
        dx, dy = math.cos(a), math.sin(a)
        nx, ny = -dy, dx
        k = -R
        while k <= R:
            p0 = (cx + nx * k - dx * R, cy + ny * k - dy * R)
            p1 = (cx + nx * k + dx * R, cy + ny * k + dy * R)
            self.line([p0, p1], w, amp, cap="butt", density=density)
            k += gap
        c.restore()
        return self

    def bricks(self, x, y, w, h, bw=34.0, bh=12.0, lw=1.4, density=None, seed=None):
        """砖缝：横缝 + 错缝的竖缝。"""
        rnd = random.Random(seed if seed is not None else self.sheet.next_seed())
        c = self.ctx
        c.save()
        c.rectangle(x, y, w, h)
        c.clip()
        row = 0
        yy = y
        while yy < y + h:
            self.line([(x, yy), (x + w, yy)], lw, 0.4, cap="butt", density=density)
            off = (bw / 2) * (row % 2)
            xx = x - off
            while xx < x + w:
                if rnd.random() > 0.08:
                    self.line([(xx, yy), (xx, yy + bh)], lw, 0.2, cap="butt", density=density)
                xx += bw
            yy += bh
            row += 1
        c.restore()
        return self

    def text(self, s, x, y, size=28, anchor="mm", density=None, vertical=False):
        self.sheet.text(self.color, self.tint is not None, s, x, y, size, anchor, self.density if density is None else density, vertical)
        return self


# ----------------------------------------------------------------------
# 一张印张
# ----------------------------------------------------------------------

class Sheet:
    """一张纸，三块版。width/height 是世界像素，scale 是输出倍率。"""

    def __init__(self, width, height, scale=2.0, origin=(0.0, 0.0), seed=7):
        self.w, self.h, self.scale = width, height, scale
        self.origin = origin
        self.W, self.H = int(round(width * scale)), int(round(height * scale))
        self.plates = {}
        self._surfaces = {}
        for c in COLORS:
            self.plates[c] = {}
            for layer in ("solid", "tint"):
                surf = cairo.ImageSurface(cairo.FORMAT_A8, self.W, self.H)
                ctx = cairo.Context(surf)
                ctx.scale(scale, scale)
                ctx.translate(-origin[0], -origin[1])
                ctx.set_antialias(cairo.ANTIALIAS_GOOD)
                self.plates[c][layer] = ctx
                self._surfaces[(c, layer)] = surf
        # 纸版：不印墨，只记录"这里有一张纸"（精灵的不透明区域）
        self._paper = cairo.ImageSurface(cairo.FORMAT_A8, self.W, self.H)
        pctx = cairo.Context(self._paper)
        pctx.scale(scale, scale)
        pctx.translate(-origin[0], -origin[1])
        self.plates["paper"] = {"solid": pctx, "tint": pctx}
        self._seed = seed
        self._fonts = {}

    def next_seed(self):
        self._seed += 1
        return self._seed

    def pen(self, color="ink", tint=None) -> Pen:
        return Pen(self, color, tint)

    # 便捷：sheet.ink / sheet.qing / sheet.mei 直接拿实地画笔
    @property
    def ink(self):
        return self.pen("ink")

    @property
    def qing(self):
        return self.pen("qing")

    @property
    def mei(self):
        return self.pen("mei")

    @contextmanager
    def clip(self, pts):
        """限制接下来所有版的绘制范围。"""
        for c in COLORS:
            for layer in ("solid", "tint"):
                ctx = self.plates[c][layer]
                ctx.save()
                ctx.new_path()
                ctx.move_to(*pts[0])
                for p in pts[1:]:
                    ctx.line_to(*p)
                ctx.close_path()
                ctx.clip()
        try:
            yield
        finally:
            for c in COLORS:
                for layer in ("solid", "tint"):
                    self.plates[c][layer].restore()

    def clear(self, pts, colors=None, layers=("solid", "tint")):
        # colors 默认挖空三块墨版（纸版不动）
        """挖空（露出纸色）。在已经画过的东西上面再画一个"不透明"物体前先挖空。"""
        for c in colors or COLORS:
            for layer in layers:
                ctx = self.plates[c][layer]
                ctx.save()
                ctx.new_path()
                ctx.move_to(*pts[0])
                for p in pts[1:]:
                    ctx.line_to(*p)
                ctx.close_path()
                ctx.set_operator(cairo.OPERATOR_CLEAR)
                ctx.fill()
                ctx.restore()

    def clear_rect(self, x, y, w, h, **kw):
        self.clear(rect_pts(x, y, w, h), **kw)

    def clear_circle(self, cx, cy, r, **kw):
        self.clear(circle_pts(cx, cy, r, 48), **kw)

    def _font(self, size_px):
        if size_px not in self._fonts:
            self._fonts[size_px] = ImageFont.truetype(font_path(), size_px)
        return self._fonts[size_px]

    def text(self, color, tint, s, x, y, size, anchor="mm", density=1.0, vertical=False):
        """用霞鹜文楷写字（PIL 渲染后贴进版里）。vertical=True 竖排。"""
        S = self.scale
        f = self._font(int(size * S))
        if vertical:
            chars = list(s)
            step = size * S * 1.05
            W = int(size * S * 1.4)
            H = int(step * len(chars) + size * S * 0.4)
            img = Image.new("L", (W, H), 0)
            d = ImageDraw.Draw(img)
            for i, ch in enumerate(chars):
                d.text((W / 2, step * (i + 0.5) + size * S * 0.2), ch, font=f, fill=255, anchor="mm")
        else:
            bbox = f.getbbox(s, anchor="ls")
            W = bbox[2] - bbox[0] + 8
            H = int(size * S * 1.5)
            img = Image.new("L", (W, H), 0)
            d = ImageDraw.Draw(img)
            d.text((4 - bbox[0], int(size * S * 1.12)), s, font=f, fill=255, anchor="ls")
        # 锚点
        px = (x - self.origin[0]) * S
        py = (y - self.origin[1]) * S
        ax = {"l": 0, "m": 0.5, "r": 1}[anchor[0]]
        ay = {"t": 0, "m": 0.5, "b": 1}[anchor[1]]
        ox, oy = int(round(px - ax * img.width)), int(round(py - ay * img.height))
        self._blit(color, "tint" if tint else "solid", img, ox, oy, density)

    def _blit(self, color, layer, img: Image.Image, ox, oy, density=1.0):
        surf = self._surfaces[(color, layer)]
        surf.flush()
        stride = surf.get_stride()
        buf = np.ndarray((self.H, stride), dtype=np.uint8, buffer=surf.get_data())
        a = np.asarray(img, dtype=np.float32) / 255.0 * density
        x0, y0 = max(0, ox), max(0, oy)
        x1, y1 = min(self.W, ox + img.width), min(self.H, oy + img.height)
        if x1 <= x0 or y1 <= y0:
            return
        src = a[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
        dst = buf[y0:y1, x0:x1].astype(np.float32) / 255.0
        out = 1.0 - (1.0 - dst) * (1.0 - src)
        buf[y0:y1, x0:x1] = np.clip(out * 255.0 + 0.5, 0, 255).astype(np.uint8)
        surf.mark_dirty()

    def stamp(self, other: "Sheet", x, y):
        """把另一张（小）印张的各版叠印到这里（世界坐标 x, y 为对方原点）。"""
        for c in COLORS:
            for layer in ("solid", "tint"):
                a = other.density(c, layer)
                img = Image.fromarray((a * 255).astype(np.uint8), "L")
                self._blit(c, layer, img, int(round((x - self.origin[0]) * self.scale)), int(round((y - self.origin[1]) * self.scale)))

    # ------------------------------------------------------------------
    # 合成
    # ------------------------------------------------------------------

    def density(self, color, layer):
        surf = self._surfaces[(color, layer)]
        surf.flush()
        stride = surf.get_stride()
        buf = np.ndarray((self.H, stride), dtype=np.uint8, buffer=surf.get_data())
        return buf[:, : self.W].astype(np.float32) / 255.0

    def plate_coverage(self, color, grain=0.35, pitch=None, seed=1):
        """一块版最终的墨量（0~1）：实地 + 网点化的浅色。"""
        solid = self.density(color, "solid")
        tint = self.density(color, "tint")
        pitch = pitch or 4.0 * self.scale
        cov = solid
        if tint.max() > 0:
            ys, xs = np.mgrid[0 : self.H, 0 : self.W].astype(np.float32)
            xs += self.origin[0] * self.scale
            ys += self.origin[1] * self.scale
            a = math.radians(SCREEN_ANGLE[color])
            u = (xs * math.cos(a) + ys * math.sin(a)) * (math.tau / pitch)
            v = (-xs * math.sin(a) + ys * math.cos(a)) * (math.tau / pitch)
            T = 0.5 - (np.cos(u) + np.cos(v)) * 0.25  # 圆网点阈值场
            n = _noise(self.W, self.H, seed + sum(map(ord, color)), self.origin, self.scale, cell=3)
            d = tint * (1.0 + grain * n)
            fw = 0.16
            ht = np.clip((d - T) / fw + 0.5, 0.0, 1.0) * (tint > 0.003)
            cov = 1.0 - (1.0 - solid) * (1.0 - ht)
        # 孔版的"吃墨不均"：实地上一层很淡的低频斑驳
        n2 = _noise(self.W, self.H, seed + 31 + sum(map(ord, color)), self.origin, self.scale, cell=40)
        cov = cov * (1.0 - 0.10 * np.clip(n2, 0, 1))
        return cov

    def composite(self, paper=True, misreg=True):
        """合成成 RGB（uint8）。paper=False 时底色是白，用于"正片叠底"的上层贴图。"""
        base = np.array(PAPER if paper else (255, 255, 255), dtype=np.float32) / 255.0
        out = np.ones((self.H, self.W, 3), dtype=np.float32) * base
        for c, rgb in COLORS.items():
            cov = self.plate_coverage(c)
            if misreg and MISREG[c] != (0, 0):
                dx, dy = MISREG[c]
                cov = _shift(cov, int(dx * self.scale / 2), int(dy * self.scale / 2))
            ink = np.array(rgb, dtype=np.float32) / 255.0
            out *= 1.0 - cov[..., None] * (1.0 - ink)
        return np.clip(out * 255.0 + 0.5, 0, 255).astype(np.uint8)

    def alpha(self):
        """精灵的不透明度：纸版（sheet.pen("paper") 画的剪影）∪ 实际印上的墨。"""
        self._paper.flush()
        stride = self._paper.get_stride()
        buf = np.ndarray((self.H, stride), dtype=np.uint8, buffer=self._paper.get_data())
        a = buf[:, : self.W].astype(np.float32) / 255.0
        for c in COLORS:
            cov = self.plate_coverage(c)
            if MISREG[c] != (0, 0):
                dx, dy = MISREG[c]
                cov = _shift(cov, int(dx * self.scale / 2), int(dy * self.scale / 2))
            a = 1.0 - (1.0 - a) * (1.0 - cov)
        return a

    def save_rgba(self, path, misreg=True):
        """精灵：RGB 按纸色合成，alpha = 纸版剪影 ∪ 墨。"""
        os.makedirs(os.path.dirname(path), exist_ok=True)
        rgb = self.composite(True, misreg)
        a = np.clip(self.alpha() * 255.0 + 0.5, 0, 255).astype(np.uint8)
        Image.fromarray(np.dstack([rgb, a]), "RGBA").save(path, optimize=True)

    def save(self, path, paper=True, misreg=True):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        Image.fromarray(self.composite(paper, misreg), "RGB").save(path, optimize=True)


def _shift(a, dx, dy):
    if dx == 0 and dy == 0:
        return a
    out = np.zeros_like(a)
    H, W = a.shape
    xs0, xs1 = max(0, -dx), min(W, W - dx)
    ys0, ys1 = max(0, -dy), min(H, H - dy)
    out[ys0 + dy : ys1 + dy, xs0 + dx : xs1 + dx] = a[ys0:ys1, xs0:xs1]
    return out


def _noise(W, H, seed, origin=(0, 0), scale=1.0, cell=6):
    """世界坐标对齐的值噪声（-1~1）：切图拼接处不会断。"""
    cellpx = cell * scale
    gx0 = int(math.floor(origin[0] * scale / cellpx)) - 1
    gy0 = int(math.floor(origin[1] * scale / cellpx)) - 1
    gw = int(W / cellpx) + 4
    gh = int(H / cellpx) + 4
    # 每个格点的值由世界格点坐标决定（可重复）
    gy, gx = np.mgrid[gy0 : gy0 + gh, gx0 : gx0 + gw]
    h = (gx * 374761393 + gy * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    vals = ((h & 0xFFFF) / 65535.0 * 2.0 - 1.0).astype(np.float32)
    img = Image.fromarray(vals, "F").resize((int(gw * cellpx), int(gh * cellpx)), Image.BICUBIC)
    arr = np.asarray(img, dtype=np.float32)
    ox = int(round(origin[0] * scale - gx0 * cellpx))
    oy = int(round(origin[1] * scale - gy0 * cellpx))
    return arr[oy : oy + H, ox : ox + W]
