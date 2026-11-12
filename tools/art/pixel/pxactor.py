#!/usr/bin/env python3
"""像素版的人：沿用 actors.py 的骨架、姿势、二十套动作，只换画法。

每 3 个世界像素是 1 个像素点（PX）。每块面按自己的材质填色、不抗锯齿；画完以后整张表过一遍：
  · 外轮廓：人外面一圈深色（按挨着的那块材质取它最深的一档）
  · 内线：后画的块压在先画的块上，接缝处先画那块压一档深色
  · 受光：光从前上方来，每块顶边亮一档、背面和底边暗一档；远侧的胳膊腿整块暗一档
  · 脸：眼睛、嘴、腮红按点位一个一个点上去，不走矢量
输出时每个点放大 OUT 倍（最近邻），引擎用线性过滤缩放也不糊。

    python3 tools/art/pixel/pxactor.py --preview out.png      # 主角十张表拼一张预览
    python3 tools/art/pixel/pxactor.py                         # 出图 → client/art/actors/
"""
from __future__ import annotations

import argparse
import math
import os
import sys

import cairo
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import actors  # noqa: E402
import actor_acts  # noqa: E402
from riso import ROOT  # noqa: E402

PX = 3                 # 世界像素 / 像素点
OUT = 3                # 输出放大倍数（每个点 3×3：贴图 1 像素 = 1 世界像素，引擎 ART_SCALE = 1）
CW, CH = 66, 74        # 一格多少个点（世界 198×222）
FOOT = (33, 69)        # 脚底在格子里的点位（世界 99, 207）
NORMAL = {"child": 1.15, "teen": 1.18, "young": 1.2, "middle": 1.18, "old": 1.16}
CHIBI = {"child": 1.32, "teen": 1.34, "young": 1.36, "middle": 1.32, "old": 1.3}
HEAD_BOOST = dict(CHIBI)   # 大头（Q 版）；--normal 换回常规头身

# ----------------------------------------------------------------------
# 材质：每种四档（亮、本色、暗、线）
# ----------------------------------------------------------------------
def _h(s):
    return tuple(int(s[i:i + 2], 16) for i in (1, 3, 5))


RAMP = {
    "skin":   ["#FFE3C8", "#F6C6A0", "#DE9C7C", "#8E4E44"],
    "hair":   ["#5A4A6A", "#33283E", "#211A2B", "#140F1C"],
    "grey":   ["#E2DEE6", "#B9B3C2", "#8E879C", "#4E4858"],
    "qing":   ["#62CBB0", "#2FA088", "#1F7468", "#123F3E"],
    "qing_lt": ["#A8E2CF", "#7CCDB6", "#4FA392", "#1F5452"],
    "mei":    ["#FF8A8C", "#E4495E", "#AE2F4C", "#5A1630"],
    "mei_lt": ["#FFC2C0", "#F79A9C", "#D46E7E", "#7A2A44"],
    "navy":   ["#5E6C98", "#3E4870", "#2B3256", "#171B33"],
    "cloth":  ["#FFFFFF", "#F1EDE6", "#CFC7C4", "#6E6470"],
    "shoe":   ["#6A5560", "#3E3138", "#2A2026", "#140E12"],
    "bag":    ["#F5C873", "#DDA13E", "#AE7330", "#5A3518"],
    "brown":  ["#C9A07A", "#9E7654", "#74533E", "#3A271E"],
    "steel":  ["#C8CED6", "#9AA2AE", "#6C7380", "#353A44"],
    "wood":   ["#D49A62", "#A86E44", "#7A4C30", "#3E2418"],
    "red":    ["#FF8A6A", "#E5523E", "#B03A30", "#5A1A18"],
    "line":   ["#2A1E2C", "#2A1E2C", "#2A1E2C", "#1A1220"],
}
RAMP = {k: [_h(c) for c in v] for k, v in RAMP.items()}
EYE = _h("#22182A")
BLUSH = _h("#F59A98")
MOUTH = _h("#B3384E")
SWEAT = _h("#9ED8F0")


def mat_of(spec):
    """把 actors.py 的 (版, 浓度[, flat]) 翻成材质名。"""
    if spec is None:
        return None
    if spec[0] == "_far":
        return mat_of(spec[1])
    c = spec[0]
    d = spec[1] if len(spec) > 1 else None
    flat = len(spec) > 2 and spec[2] == "flat"
    if c in RAMP:
        return c
    if c == "paper":
        return "cloth"
    if c == "qing":
        return "qing" if d is None or d >= 0.7 else "qing_lt"
    if c == "mei":
        return "mei" if d is None or d >= 0.7 else "mei_lt"
    if c == "ink":
        if d is None:
            return "hair"
        if flat:
            return "navy"
        if 0.3 <= d <= 0.42:
            return "grey"
        return "brown" if d > 0.42 else "steel"
    return "steel"


# ----------------------------------------------------------------------
# 画笔
# ----------------------------------------------------------------------
class PxPainter:
    def __init__(self, cols, rows):
        self.W, self.H = cols * CW, rows * CH
        self.col = cairo.ImageSurface(cairo.FORMAT_ARGB32, self.W, self.H)
        self.ids = cairo.ImageSurface(cairo.FORMAT_ARGB32, self.W, self.H)
        self.cc = self._mk(self.col)
        self.ic = self._mk(self.ids)
        self.ox = self.oy = 0.0
        self.xf = None
        self.n = 0
        self.mat = {0: None}          # 块 id → 材质
        self.far = {}                 # 块 id → 远侧（整块暗一档）
        self.shade_mask = np.zeros((self.H, self.W), bool)
        self.lock = np.zeros((self.H, self.W), bool)   # 脸、细线：不参与描边和受光

    def _mk(self, s):
        c = cairo.Context(s)
        c.set_antialias(cairo.ANTIALIAS_NONE)
        c.scale(1.0 / PX, 1.0 / PX)
        return c

    def _xy(self, x, y):
        if self.xf is not None:
            deg, (cx, cy) = self.xf
            a = math.radians(deg)
            ca, sa = math.cos(a), math.sin(a)
            x, y = cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca
        return x + self.ox, y + self.oy

    def _path(self, c, pts, closed):
        c.new_path()
        c.move_to(*self._xy(*pts[0]))
        for x, y in pts[1:]:
            c.line_to(*self._xy(x, y))
        if closed:
            c.close_path()

    def _new_id(self, m, far=False):
        self.n += 1
        self.mat[self.n] = m
        if far:
            self.far[self.n] = True
        return self.n

    def _emit(self, pts, closed, stroke, m, far=False, tone=1):
        rid = self._new_id(m, far)
        col = RAMP[m][tone]
        for c, rgb in ((self.cc, col), (self.ic, (rid & 255, (rid >> 8) & 255, 0))):
            c.save()
            self._path(c, pts, closed)
            c.set_source_rgb(*(v / 255 for v in rgb))
            if stroke is None:
                c.fill()
            else:
                c.set_line_width(max(stroke, PX * 1.0))
                c.set_line_cap(cairo.LINE_CAP_ROUND)
                c.set_line_join(cairo.LINE_JOIN_ROUND)
                c.stroke()
            c.restore()

    # --- actors.Painter 的接口 ---
    def shape(self, pts, spec, line=None, line_color="ink"):
        if spec is not None and spec[0] == "skin" and len(pts) == 12:
            return  # 耳朵：这么小画出来是一块疙瘩，不要
        if len(pts) == 14 and spec in (("paper",), ("ink", 0.1, "flat")):
            spec = ("skin",) if spec == ("paper",) else ("_far", ("skin",))  # 手
        m = mat_of(spec)
        if m is None:
            return
        self._emit(pts, True, None, m, far=spec[0] == "_far")

    def limb(self, pts, width, spec, line=None):
        m = mat_of(spec)
        if m is None:
            return
        self._emit(pts, False, width, m, far=spec[0] == "_far")

    def line(self, pts, w=2.3, color="ink", density=None, closed=False):
        if density is not None and density <= 0.05:
            return
        if closed and w < 1.7 and color == "ink" and len(pts) <= 20:
            xs = [x for x, _ in pts]
            if max(xs) - min(xs) < 24:
                # 眼镜：这么小画一圈只是一团乱线。记一笔，画脸时按眼睛的位置点上去
                self.glasses = True
                self._skip_temple = True
                return
        if getattr(self, "_skip_temple", False) and not closed and w <= 1.45:
            self._skip_temple = False   # 眼镜腿：也不要
            return
        m = "line" if color == "ink" else mat_of((color, density))
        self._mask_op(pts, closed, max(w, PX * 0.9), lambda sel: self._paint_sel(sel, RAMP[m][1], lock=True))

    def dot(self, x, y, r, color="ink", density=None):
        m = "line" if color == "ink" and density is None else mat_of((color, density))
        self._emit(actors.ell(x, y, max(r, PX * 0.6), max(r, PX * 0.6), 12), True, None, m)

    def blot(self, pts, color, density=None, flat=False):
        if color == "ink" and density is not None and density < 0.5:
            self._mask_op(pts, True, None, lambda sel: self.shade_mask.__setitem__(sel, True))
        elif color == "mei":
            return  # 腮红由脸上点
        else:
            self.shape(pts, (color, density))

    def _clear(self, pts, closed=True, stroke_w=None):
        pass

    def _fill(self, color, density, pts, closed=True, stroke_w=None, op=None):
        if color == "paper":
            return
        self.shape(pts, (color, density))

    # --- 掩码操作：在已经画上的东西上改色 ---
    def _mask_op(self, pts, closed, stroke, fn):
        s = cairo.ImageSurface(cairo.FORMAT_A8, self.W, self.H)
        c = self._mk(s)
        self._path(c, pts, closed)
        c.set_source_rgba(0, 0, 0, 1)
        if stroke is None:
            c.fill()
        else:
            c.set_line_width(stroke)
            c.set_line_cap(cairo.LINE_CAP_ROUND)
            c.stroke()
        s.flush()
        a = np.ndarray((self.H, s.get_stride()), np.uint8, s.get_data())[:, :self.W] > 0
        fn(a)

    def _arr(self, s):
        s.flush()
        return np.ndarray((self.H, self.W, 4), np.uint8, s.get_data())

    def _paint_sel(self, sel, rgb, lock=False, only_on=None):
        col = self._arr(self.col)
        ids = self._arr(self.ids)
        if only_on is not None:
            sel = sel & only_on
        col[sel, 2], col[sel, 1], col[sel, 0], col[sel, 3] = rgb[0], rgb[1], rgb[2], 255
        if lock:
            self.lock |= sel
            # 细线也要有 id，好让外轮廓认得它
            ids[sel, 3] = 255
        self.col.mark_dirty()
        self.ids.mark_dirty()

    def band(self, pts, closed=True, stroke=None):
        """纸白道道：压在头发上就是头发高光，压在衣服上就是白杠。"""
        def fn(sel):
            ids = self._arr(self.ids)
            rid = ids[..., 2].astype(np.int32) | (ids[..., 1].astype(np.int32) << 8)
            on = sel & (ids[..., 3] > 0)
            hair = np.isin(rid, [k for k, v in self.mat.items() if v in ("hair", "grey")])
            self._paint_sel(on & hair, RAMP["hair"][0], lock=True)
            self._paint_sel(on & ~hair, RAMP["cloth"][1], lock=True)
        self._mask_op(pts, closed, stroke, fn)

    def pix(self, X, Y, rgb, only_skin=False):
        X, Y = int(X), int(Y)
        if not (0 <= X < self.W and 0 <= Y < self.H):
            return
        col = self._arr(self.col)
        if only_skin:
            ids = self._arr(self.ids)
            rid = int(ids[Y, X, 2]) | (int(ids[Y, X, 1]) << 8)
            if self.mat.get(rid) != "skin":
                return
        col[Y, X] = (rgb[2], rgb[1], rgb[0], 255)
        self.lock[Y, X] = True
        self.col.mark_dirty()

    def to_px(self, x, y):
        X, Y = self._xy(x, y)
        return math.floor(X / PX), math.floor(Y / PX)

    # --- 收尾：描边、受光 ---
    def finish(self):
        col = self._arr(self.col).copy()
        ids = self._arr(self.ids)
        rgb = col[..., [2, 1, 0]].astype(np.int32)
        a = col[..., 3] > 0
        rid = ids[..., 2].astype(np.int32) | (ids[..., 1].astype(np.int32) << 8)
        rid[~a] = 0
        H, W = rid.shape
        mats = self.mat
        lut_m = np.array([0] * (max(mats) + 1))
        names = list(RAMP)
        for k, v in mats.items():
            lut_m[k] = names.index(v) + 1 if v else 0
        mid = lut_m[rid]
        ramp = np.array([[[0, 0, 0]] * 4] + [RAMP[n] for n in names], np.int32)  # (n+1, 4, 3)
        far = np.zeros_like(a)
        for k in self.far:
            far |= rid == k
        out = rgb.copy()
        lock = self.lock
        def sh(arr, dy, dx, fill=0):
            r = np.full_like(arr, fill)
            ys = slice(max(dy, 0), H + min(dy, 0)); yd = slice(max(-dy, 0), H + min(-dy, 0))
            xs = slice(max(dx, 0), W + min(dx, 0)); xd = slice(max(-dx, 0), W + min(-dx, 0))
            r[yd, xd] = arr[ys, xs]
            return r
        # 本色 → 受光：顶边亮、背面和底边暗、远侧整块暗
        base_tone = np.where(far | self.shade_mask, 2, 1)
        up = sh(rid, -1, 0)
        back = sh(rid, 0, -1)
        down = sh(rid, 1, 0)
        tall = np.ones_like(a)
        tone = base_tone.copy()
        tone = np.where((up != rid) & a & ~far, np.minimum(tone, 0), tone)
        tone = np.where(((back != rid) | (down != rid)) & a, np.maximum(tone, 2), tone)
        recol = ramp[mid, tone]
        paint = a & ~lock & (mid > 0)
        out[paint] = recol[paint]
        # 内线：挨着后画（id 更大）的块，这一侧压成线色
        line_tone = ramp[mid, 3]
        inner = np.zeros_like(a)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            nb = sh(rid, dy, dx)
            nbm = sh(mid, dy, dx)
            inner |= a & (nb > rid) & (nb > 0) & (nbm != mid) & ~sh(lock, dy, dx, False)
        inner &= ~lock
        out[inner] = line_tone[inner]
        # 外轮廓：透明处挨着人 → 挨着那块的线色
        olc = np.zeros_like(out)
        ol = np.zeros_like(a)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            nm = sh(mid, dy, dx)
            hit = ~a & (nm > 0) & ~ol
            olc[hit] = ramp[nm, 3][hit]
            ol |= hit
        out[ol] = olc[ol]
        alpha = (a | ol).astype(np.uint8) * 255
        return np.dstack([out.clip(0, 255).astype(np.uint8), alpha])


# ----------------------------------------------------------------------
# 换掉 actors 里跟版有关的几处
# ----------------------------------------------------------------------
def far_spec(spec):
    if spec is None:
        return None
    if spec[0] == "paper":
        return ("_far", ("skin",)) if False else ("_far", ("paper",))
    return ("_far", spec)


def paper_band(p, pts):
    p.band(pts)


def stripe(p, pts, far):
    p.band(pts, closed=False, stroke=2.6)


def face(p, b, hx, hy, r, expr=None):
    st = b["stage"]
    ex, ey = p.to_px(hx + r * 0.52, hy + r * 0.08)
    mx, my = p.to_px(hx + r * 0.84, hy + r * 0.56)
    bx, by = p.to_px(hx + r * 0.3, hy + r * 0.42)
    big = st != "old"
    girl = not b.get("male", b["role"] == "qing")
    E = EYE

    def eye_open(dx=0, dy=0, tall=2):
        if big and tall == 2:
            # 2×3 的眼睛，前上角一点高光；女孩前上角再挑一根睫毛；大人眼睛上头一道眉
            for yy in range(-1, 2):
                for xx in (-1, 0):
                    p.pix(ex + dx + xx, ey + dy + yy, E)
            p.pix(ex + dx, ey + dy - 1, _h("#FFF6EE"))
            if girl:
                p.pix(ex + dx + 1, ey + dy - 2, E, only_skin=True)
            if st in ("young", "middle"):
                p.pix(ex + dx - 1, ey + dy - 3, RAMP["hair"][1], only_skin=True)
                p.pix(ex + dx, ey + dy - 3, RAMP["hair"][1], only_skin=True)
            return
        for k in range(tall):
            p.pix(ex + dx, ey + dy - k + 1, E)

    def eye_arc(up=True):
        if up:
            p.pix(ex - 1, ey + 1, E); p.pix(ex, ey, E); p.pix(ex + 1, ey + 1, E)
        else:
            p.pix(ex - 1, ey, E); p.pix(ex, ey + 1, E); p.pix(ex + 1, ey, E)

    blush = True
    if expr in (None, "", "blink", "sleepy"):
        if expr in ("blink", "sleepy"):
            p.pix(ex - 1, ey + 1, E); p.pix(ex, ey + 1, E)
        else:
            eye_open()
        blush = st in ("child", "teen") or (girl and st == "young")
    elif expr in ("happy", "shy", "bliss"):
        eye_arc(expr != "bliss")
    elif expr == "joy":
        eye_arc(True)
        p.pix(mx - 1, my, MOUTH); p.pix(mx, my, MOUTH); p.pix(mx - 1, my + 1, MOUTH)
    elif expr in ("open", "sing", "surprise"):
        if expr == "sing":
            eye_arc(False)
        elif expr == "surprise":
            eye_open(tall=3)
            p.pix(ex, ey - 3, E)
        else:
            eye_open()
        p.pix(mx - 1, my, MOUTH)
        if expr != "open":
            p.pix(mx - 1, my + 1, MOUTH)
    elif expr == "focus":
        eye_open(dy=1, tall=1)
        p.pix(ex - 1, ey - 1, E); p.pix(ex, ey - 2, E)
        blush = False
    elif expr == "think":
        eye_open(dy=-1, tall=1)
        p.pix(ex - 1, ey - 3, E); p.pix(ex, ey - 3, E)
    elif expr == "effort":
        p.pix(ex - 1, ey - 1, E); p.pix(ex, ey, E); p.pix(ex - 1, ey + 1, E)
        p.pix(mx - 1, my, _h("#FFFFFF")); p.pix(mx - 2, my, MOUTH)
    elif expr == "sad":
        eye_open(dy=1, tall=1)
        p.pix(ex, ey - 2, E); p.pix(ex - 1, ey - 1, E)
        p.pix(mx - 1, my + 1, MOUTH)
        blush = False
    elif expr == "chew":
        eye_arc(True)
        p.pix(mx, my, RAMP["skin"][2])
    if blush or expr in ("happy", "shy", "joy", "chew"):
        p.pix(bx, by, BLUSH, only_skin=True)
        if expr == "shy" or big:
            p.pix(bx - 1, by, BLUSH, only_skin=True)
    if st == "old":
        p.pix(ex + 1, ey - 3, RAMP["skin"][2], only_skin=True)
    if getattr(p, "glasses", False):
        p.glasses = False
        fr = RAMP["line"][1]
        for dx in (-2, -1, 0, 1, 2):
            p.pix(ex + dx, ey - 2, fr)
        p.pix(ex + 2, ey - 1, fr, only_skin=True)
        p.pix(ex + 1, ey, _h("#DCEBF0"), only_skin=True)
        p.pix(ex + 1, ey - 1, _h("#FFFFFF"), only_skin=True)


def patch():
    actors.far_spec = far_spec
    actors._paper_band = paper_band
    actors._stripe = stripe
    actors._face = face
    actor_acts_face = getattr(actor_acts, "_face", None)
    if actor_acts_face is not None:
        actor_acts._face = face


def build(role, stage):
    b = actors.build(role, stage)
    b["skin"] = ("skin",)
    if b["shoes"][0] == "ink":
        b["shoes"] = ("shoe",)
    if stage == "teen" and b.get("bag"):
        pass
    b["head"] *= HEAD_BOOST[stage]
    b["torso"] -= b["head"] * (HEAD_BOOST[stage] - 1) * 2 / HEAD_BOOST[stage] * 0.6
    return b


def cell_origin(r, c):
    return (c * CW + FOOT[0]) * PX, (r * CH + FOOT[1]) * PX


def sheet_for(role, stage):
    b = build(role, stage)
    p = PxPainter(actors.COLS, actors.ROWS)
    for i in range(8):
        actors.draw_person(p, b, actors.pose_walk(b, i / 8.0), *cell_origin(0, i))
    for i in range(4):
        br = math.sin(i / 4.0 * math.tau)
        actors.draw_person(p, b, actors.pose_stand(b, br), *cell_origin(1, i), blink=(i == 3))
    for i in range(4):
        pose = actors.pose_stand(b, 0.4 * math.sin(i / 4.0 * math.tau))
        pose["lean"] += 4
        actors.draw_person(p, b, pose, *cell_origin(1, 4 + i), busy=i / 4.0)
    for i in range(2):
        actors.draw_sit(p, b, *cell_origin(2, i), i)
    for i in range(2):
        actors.draw_sleep(p, b, *cell_origin(2, 2 + i), i)
    for i in range(4):
        actors.draw_person(p, b, actors.pose_stand(b, 0.3), *cell_origin(2, 4 + i), wave=i / 4.0)
    for j, (_name, fn) in enumerate(actor_acts.EMOTES):
        for i in range(4):
            x, y = cell_origin(3 + j // 2, (j % 2) * 4 + i)
            actors.draw_person(p, b, x0=x, y0=y, **fn(b, i / 4.0))
    return p.finish()


def act_sheet_for(role, stage):
    b = build(role, stage)
    p = PxPainter(actors.COLS, actors.ACT_ROWS)
    for j, (_name, fn) in enumerate(actor_acts.ACTS):
        for i in range(4):
            x, y = cell_origin(j // 2, (j % 2) * 4 + i)
            actors.draw_person(p, b, x0=x, y0=y, **fn(b, i / 4.0))
    return p.finish()


def up(arr, k=OUT):
    return np.repeat(np.repeat(arr, k, 0), k, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview")
    ap.add_argument("--only", default="")
    ap.add_argument("--chibi", action="store_true", help="大头版（默认就是）")
    ap.add_argument("--normal", action="store_true", help="常规头身")
    a = ap.parse_args()
    if a.normal:
        HEAD_BOOST.update(NORMAL)
    patch()
    stages = a.only.split(",") if a.only else list(actors.STAGES)
    if a.preview:
        rows = []
        for st in stages:
            for role in actors.ROLES:
                s = sheet_for(role, st)
                rows.append(s[: CH * 2])  # 走路 + 站
        img = np.concatenate(rows, 0)
        bg = np.zeros_like(img); bg[...] = (214, 196, 178, 255)
        al = img[..., 3:4] / 255.0
        comp = (img[..., :3] * al + bg[..., :3] * (1 - al)).astype(np.uint8)
        Image.fromarray(up(comp, 3)).save(a.preview)
        print(a.preview)
        return
    out = os.path.join(ROOT, "client", "art", "actors")
    for st in stages:
        for role in actors.ROLES:
            for suf, fn in (("", sheet_for), ("_act", act_sheet_for)):
                arr = up(fn(role, st))
                path = os.path.join(out, f"{role}_{st}{suf}.png")
                img = Image.fromarray(arr, "RGBA").quantize(colors=128, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
                img.save(path, optimize=True)
                print("✓", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
