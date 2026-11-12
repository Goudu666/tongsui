#!/usr/bin/env python3
"""像素版的街坊和路人：folks.py 画谁、干什么营生一概照旧，只换画法（pxactor 的 PxPainter：材质四档、内外描线、点阵脸）。

    python3 tools/art/pixel/pxfolks.py                 →  client/art/folks/<图>.png、walkers.png、index.json
    python3 tools/art/pixel/pxfolks.py --only street   →  只出这几张（逗号分隔，walkers 出路人）
    python3 tools/art/pixel/pxfolks.py --preview DIR   →  所有图集拼一张 + 几个街坊站在像素街景上的样张

布局和主角一样（pxactor）：一格 66×74 个点 = 198×222 世界像素，脚底在点 (33, 69) = 世界 (99, 207)；
每个点最近邻放大 3 倍出图，贴图 1 像素 = 1 世界像素，index.json 的 scale 是 1。
  <图>.png：一个街坊一行，列 0~3 干活的一圈（营生），列 4~7 歇着
  walkers.png：一种路人一行，8 帧走路
头身比和主角一样用大头（pxactor.CHIBI），一眼是同一个世界的人。

和主角分得开：主角是饱和的青、梅，街坊一律穿灰一档的颜色（燕麦、灰绿、石板蓝、豆沙、姜黄、砖红…，见 RAMPS），
连道具上的青、梅也换成灰一档的（_SWAP）。每人另有发色、肤色、帽子、烫发、发髻、头巾、胡子、红领巾这些小零碎（PX），
高矮胖瘦也各不相同，剪影分得开。
"""
from __future__ import annotations

import argparse
import copy
import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)
import actors  # noqa: E402
import actor_acts as A  # noqa: E402
import folks  # noqa: E402
import pxactor as PA  # noqa: E402
from actors import chaikin, draw_person, ell, pose_stand, pose_walk  # noqa: E402

PX = PA.PX
OUT = 3                    # 1 贴图像素 = 1 世界像素
CW, CH = PA.CW, PA.CH      # 66×74 点
FOOT = PA.FOOT             # (33, 69) 点
OUT_DIR = folks.OUT_DIR


# ----------------------------------------------------------------------
# 街坊的颜色：灰一档、暖一点，和底图的米色、砖红、灰绿一路（亮、本色、暗、线）
# ----------------------------------------------------------------------
RAMPS = {
    "oat":      ["#F4E8D2", "#DCCBAE", "#B8A486", "#5E4E44"],   # 燕麦、米白的确良
    "sage":     ["#C6D8BC", "#9DB89F", "#74927C", "#34473F"],   # 灰绿
    "slate":    ["#AEB8C8", "#8390A6", "#5E6A82", "#2C3242"],   # 石板蓝
    "plum":     ["#BE92A8", "#93657F", "#6B3F5B", "#33192C"],   # 豆沙紫
    "rose":     ["#F0CABC", "#D6A090", "#B0766A", "#5E363A"],   # 藕荷、豆沙粉
    "mustard":  ["#EED89A", "#D0AC60", "#A28044", "#523C1E"],   # 姜黄
    "brick":    ["#D99A84", "#B86C58", "#8A4A3E", "#45231F"],   # 砖红（比梅灰、比梅黄）
    "olive":    ["#C6C49A", "#9E9C6E", "#75744F", "#393926"],   # 军绿、邮政绿
    "denim":    ["#ABBED2", "#8098B4", "#5C7292", "#2A3448"],   # 洗旧的蓝
    "workblue": ["#93A8BE", "#6A839E", "#4E6480", "#252F40"],   # 劳动布、大襟褂子的蓝
    "charcoal": ["#7C7786", "#585361", "#3F3B48", "#1C1A22"],   # 深灰裤子
    "khaki":    ["#D4C29C", "#B09A76", "#877456", "#43372A"],   # 卡其、风衣
    "lilac":    ["#D6C8E0", "#B2A0C6", "#8A779F", "#41365A"],   # 浅紫开衫
    "leather":  ["#B4876A", "#88604A", "#634434", "#2E1E18"],   # 皮夹克
    "straw":    ["#F6E4AC", "#DEC07A", "#B4944F", "#5C4524"],   # 草帽、蒲扇、筐
    "aqua":     ["#D4EADF", "#A9D2C2", "#7FAE9E", "#3E6460"],   # 道具上的浅青（灰一档）
    "teal_m":   ["#9CC6B4", "#6E9E8C", "#527A6C", "#28403A"],   # 道具上的青（灰一档）
    "red_m":    ["#E6957E", "#C85F50", "#98463E", "#4A1E1C"],   # 道具上的红（红领巾、十字、辣椒）
    "salt":     ["#A8A2B0", "#7A7484", "#5A5464", "#26222C"],   # 花白头发
    "chestnut": ["#8E6A56", "#634638", "#47322A", "#1E1412"],   # 染过的栗色头发
    "skin_tan": ["#F4CCA4", "#DAA67E", "#B67E60", "#6A3C32"],   # 晒黑的
    "white":    ["#FFFFFF", "#F4F1EC", "#D4CECB", "#6E6470"],   # 白褂子、白毛
}
RAMPS = {k: [PA._h(c) for c in v] for k, v in RAMPS.items()}
PA.RAMP.update(RAMPS)
HAIRS = {"hair", "grey", "salt", "chestnut", "white"}
SKINS = {"skin", "skin_tan"}
# 动作里写死的青、梅（汗珠、婴儿车、风筝、传单…）：街坊身上换成灰一档的
_SWAP = {"qing": "teal_m", "qing_lt": "aqua", "mei": "red_m", "mei_lt": "rose", "navy": "charcoal"}


class FolkPainter(PA.PxPainter):
    """PxPainter + 每人自己的肤色、发色；青梅换掉。"""

    def __init__(self, cols, rows):
        super().__init__(cols, rows)
        self.skin_mat = "skin"
        self.hair_mat = None
        self.in_head = False

    def shape(self, pts, spec, line=None, line_color="ink"):
        if len(pts) == 14 and spec == ("paper",):
            xs = [x for x, _ in pts]
            if max(xs) - min(xs) > 11:      # 14 点的圆不一定是手（婴儿车轱辘）
                spec = ("white",)
        super().shape(pts, spec, line, line_color)

    def _emit(self, pts, closed, stroke, m, far=False, tone=1):
        m = _SWAP.get(m, m)
        if not self.in_head:
            m = self.remap.get(m, m)
        if m == "skin":
            m = self.skin_mat
        elif self.in_head and self.hair_mat and m in ("hair", "grey"):
            m = self.hair_mat
        super()._emit(pts, closed, stroke, m, far, tone)

    def line(self, pts, w=2.3, color="ink", density=None, closed=False):
        if density is not None and density <= 0.05:
            return
        m = "line" if color == "ink" else _SWAP.get(PA.mat_of((color, density)), PA.mat_of((color, density)))
        self._mask_op(pts, closed, max(w, PX * 0.9), lambda sel: self._paint_sel(sel, PA.RAMP[m][1], lock=True))

    def band(self, pts, closed=True, stroke=None):
        def fn(sel):
            ids = self._arr(self.ids)
            rid = ids[..., 2].astype(np.int32) | (ids[..., 1].astype(np.int32) << 8)
            on = sel & (ids[..., 3] > 0)
            for hm in HAIRS:
                keys = [k for k, v in self.mat.items() if v == hm]
                if keys:
                    hit = on & np.isin(rid, keys)
                    self._paint_sel(hit, PA.RAMP[hm][0] if hm != "hair" else PA.RAMP["hair"][0], lock=True)
                    on = on & ~hit
            self._paint_sel(on, PA.RAMP["cloth"][1], lock=True)
        self._mask_op(pts, closed, stroke, fn)

    def pix(self, X, Y, rgb, only_skin=False):
        X, Y = int(X), int(Y)
        if not (0 <= X < self.W and 0 <= Y < self.H):
            return
        if only_skin:
            ids = self._arr(self.ids)
            rid = int(ids[Y, X, 2]) | (int(ids[Y, X, 1]) << 8)
            if self.mat.get(rid) not in SKINS:
                return
        col = self._arr(self.col)
        col[Y, X] = (rgb[2], rgb[1], rgb[0], 255)
        self.lock[Y, X] = True
        self.col.mark_dirty()


_orig_head = actors._head


def _head(p, b, *a, **k):
    """画头的时候换发色（头发都是 ("ink", None) / ("ink", 0.38) 那两块）。"""
    p.in_head = True
    try:
        _orig_head(p, b, *a, **k)
    finally:
        p.in_head = False


# ----------------------------------------------------------------------
# 长相：在 folks.FOLKS 的骨架上改颜色、加零碎
# ----------------------------------------------------------------------
# 键：shirt / coat / cardigan / pants / apron / shoes → 材质名；hat=(种类, 材质)；hair 发色；skin 肤色；prop 道具色（b["role"]）
# 零碎：perm 烫发、bun 头顶发髻、scarf 头巾（材质）、beard（"mustache" / "white"）、scarf_red 红领巾、bag 挎包（材质）、
#       basket 菜篮子、glasses、h 身高倍数、w 胖瘦倍数、belly、kid 身边带个小孩（接孩子）
PX_LOOK = {
    # 楼下
    "shop_ayi": dict(shirt="white", cardigan="rose", pants="charcoal", perm=True, hair="hair", prop="mustard", w=1.08, h=0.95, glasses=False),
    "shop_clerk": dict(shirt="white", coat="mustard", pants="khaki", prop="teal_m"),
    "grinder": dict(shirt="oat", coat="workblue", pants="charcoal", hat=("cap", "olive"), apron="leather", beard="mustache", skin="skin_tan", glasses=False),
    "barber": dict(shirt="white", coat="white", pants="charcoal", hair="salt", glasses=True, h=1.03),
    # 河对岸
    "piano_teacher": dict(shirt="white", coat="lilac", pants="charcoal", hair="hair", prop="plum", h=1.04),
    "bath_uncle": dict(shirt="white", pants="slate", apron="khaki", skin="skin_tan", belly=0.4, w=1.12, glasses=False, hair="salt"),
    "site_worker": dict(shirt="khaki", pants="denim", hat=("helmet", "mustard"), skin="skin_tan", prop="khaki"),
    "greeter": dict(shirt="rose", pants="charcoal", hair="chestnut", bun=True, prop="mustard"),
    "clerk": dict(shirt="white", cardigan="sage", pants="khaki", glasses=True, prop="plum"),
    "guard_office": dict(shirt="white", coat="slate", pants="charcoal", hat=("cap", "charcoal"), glasses=False, h=1.04),
    # 外地
    "dorm_ayi": dict(shirt="white", cardigan="plum", pants="charcoal", bun=True, hair="salt", prop="mustard", glasses=True, w=1.06),
    "stall_owner": dict(shirt="oat", pants="denim", apron="olive", scarf=None, prop="charcoal", skin="skin_tan"),
    "coworker": dict(shirt="white", coat="charcoal", pants="charcoal", glasses=True),
    "postal": dict(shirt="white", coat="olive", pants="khaki", prop="olive", hair="hair", bun=True),
    # 楼里
    "er_nainai": dict(remap={"grey": "straw", "steel": "straw"}, shirt="oat", cardigan="plum", pants="charcoal", hair="grey", prop="straw", glasses=False, h=0.94),
    "coal": dict(shirt="charcoal", coat="workblue", pants="charcoal", hat=("cap", "charcoal"), skin="skin_tan", glasses=False),
    "junk": dict(shirt="oat", coat="khaki", pants="slate", hat=("cap", "olive"), skin="skin_tan", glasses=False, beard="mustache"),
    "silou": dict(shirt="white", coat="denim", pants="khaki", hair="chestnut"),
    # 医院
    "nurse": dict(shirt="white", coat="white", pants="white", prop="aqua", hair="hair", bun=True),
    "porter": dict(shirt="white", coat="sage", pants="slate", glasses=False),
    "queue_old": dict(shirt="oat", coat="grey", pants="charcoal", hat=("cap", "charcoal"), hair="grey", glasses=True, h=0.96),
    # 早市
    "soy_seller": dict(shirt="oat", cardigan="brick", pants="charcoal", apron="white", scarf="rose", prop="straw", glasses=False, w=1.06),
    "veg_seller": dict(shirt="oat", coat="olive", pants="charcoal", hat=("cap", "khaki"), apron="leather", skin="skin_tan", glasses=False),
    "wholesale_boss": dict(shirt="mustard", coat="leather", pants="charcoal", belly=0.45, w=1.14, glasses=False, hair="hair"),
    "scrap_buyer": dict(shirt="khaki", coat="sage", pants="charcoal", hat=("straw", "straw"), skin="skin_tan", glasses=False),
    # 海边
    "shell_seller": dict(shirt="mustard", pants="khaki", apron="sage", hat=("straw", "straw"), skin="skin_tan", prop="rose"),
    "lifeguard": dict(shirt="brick", pants="denim", hat=("cap", "mustard"), skin="skin_tan", h=1.05),
    "angler": dict(shirt="white", coat="sage", pants="khaki", hat=("straw", "straw"), skin="skin_tan", hair="grey", prop="leather"),
    "inn_clerk": dict(shirt="white", cardigan="denim", pants="charcoal", hair="hair", bun=True, prop="slate"),
    # 中学
    "shed_ayi": dict(shirt="sage", pants="charcoal", apron="denim", scarf="slate", prop="rose", w=1.05, glasses=False),
    "stationery": dict(shirt="white", cardigan="mustard", pants="khaki", glasses=True, hair="salt"),
    "dean": dict(shirt="white", coat="charcoal", pants="charcoal", glasses=True, h=1.05),
    # 新楼
    "property": dict(shirt="slate", pants="charcoal", hat=("cap", "slate"), prop="slate"),
    "next_door": dict(shirt="rose", cardigan="oat", pants="denim", perm=True, hair="chestnut", prop="rose", glasses=False),
    "dog_walker": dict(shirt="white", coat="sage", pants="khaki", hair="chestnut", glasses=False, prop="red_m"),
    # 公园
    "conductor": dict(shirt="white", coat="plum", pants="charcoal", hair="white", beard="mustache_w", glasses=False),
    "writer": dict(shirt="white", pants="charcoal", hat=("cap", "oat"), beard="white", hair="grey", glasses=False),
    "stroller": dict(stroller=True, dx=-12, shirt="rose", cardigan="lilac", pants="charcoal", hair="grey", prop="rose", glasses=False, h=0.95),
    "kite_old": dict(shirt="oat", coat="khaki", pants="slate", hat=("cap", "sage"), glasses=False, prop="straw"),
    # 小学
    "guard": dict(shirt="oat", coat="olive", pants="charcoal", hat=("cap", "olive"), glasses=True, prop="slate"),
    "teacher": dict(shirt="white", cardigan="mustard", pants="charcoal", glasses=True, prop="rose", hair="hair"),
    "grandparents": dict(shirt="oat", cardigan="plum", pants="charcoal", hair="grey", glasses=False, kid=True, h=0.95),
    # 出租屋
    "landlord": dict(remap={"grey": "straw", "steel": "straw"}, shirt="mustard", pants="charcoal", perm=True, hair="hair", belly=0.3, w=1.1, prop="straw", glasses=False),
    "neighbor_rent": dict(shirt="white", coat="sage", pants="khaki"),
    # 海河边
    "yam": dict(shirt="oat", coat="leather", pants="charcoal", hat=("cap", "charcoal"), apron="khaki", skin="skin_tan", glasses=False),
    "photog": dict(shirt="white", coat="khaki", pants="denim", hat=("cap", "sage")),
    "runner": dict(shirt="lilac", pants="charcoal", hair="hair", bun=True, glasses=False),
    # 乡下
    "grandma_v": dict(remap={"grey": "straw", "steel": "straw"}, shirt="workblue", cardigan="-", pants="charcoal", hair="grey", prop="straw", glasses=False, h=0.93),
    "gate_old": dict(remap={"grey": "straw", "steel": "straw"}, shirt="white", coat="oat", pants="charcoal", hat=("straw", "straw"), skin="skin_tan", glasses=False),
    "cousin": dict(shirt="white", pants="olive", skin="skin_tan", prop="teal_m"),
}

WALK_LOOK = {
    "bag_man": dict(shirt="oat", coat="slate", pants="charcoal", bag="leather", glasses=False),
    "basket_aunt": dict(shirt="rose", cardigan="oat", pants="charcoal", perm=True, basket=True, glasses=False),
    "cane_old": dict(shirt="oat", coat="khaki", pants="charcoal", hat=("cap", "charcoal"), hair="grey", glasses=True),
    "kid": dict(shirt="mustard", pants="denim", scarf_red=True, shoes="white"),
    "student": dict(shirt="white", coat="slate", pants="slate", bag="leather"),
    "coat_woman": dict(shirt="white", coat="khaki", pants="charcoal", hair="chestnut"),
}

_BODY_KEYS = ("shirt", "coat", "cardigan", "pants", "apron", "shoes")


def px_body(b0, ov):
    """folks.look 的骨架 → 像素版：大头、换材质、高矮胖瘦。"""
    b = copy.deepcopy(b0)
    st = b["stage"]
    boost = PA.CHIBI[st]
    b["head"] *= boost
    b["torso"] -= b["head"] * (boost - 1) * 2 / boost * 0.6
    b["skin"] = (ov.get("skin", "skin"),)
    b["shoes"] = ("shoe",) if b["shoes"][0] == "ink" else b["shoes"]
    for k in _BODY_KEYS:
        if ov.get(k) == "-":
            b[k] = None
        elif ov.get(k):
            b[k] = (ov[k],)
    if b.get("apron") and b["apron"][0] in ("ink", "paper"):
        b["apron"] = ("white",) if b["apron"][0] == "paper" else ("khaki",)
    if "hat" in ov:
        b["hat"] = (ov["hat"][0], (ov["hat"][1],)) if ov["hat"] else None
    elif b.get("hat"):
        kind, spec = b["hat"]
        b["hat"] = (kind, spec if spec is None else ("charcoal",))
    ov = dict(ov)
    ov["glasses"] = ov.get("glasses", b.get("glasses", False))
    b["glasses"] = False          # actors 的眼镜是一圈墨，这么小看着像黑眼圈：换成点出来的（extras）
    if "prop" in ov:
        b["role"] = ov["prop"]
    elif b["role"] in ("ink",):
        b["role"] = "khaki"
    if "belly" in ov:
        b["belly"] = ov["belly"]
    h = ov.get("h", 1.0)
    if h != 1.0:
        for k in ("leg", "thigh", "shin", "ankle", "torso", "upper", "fore", "H"):
            b[k] *= h
    w = ov.get("w", 1.0)
    if w != 1.0:
        for k in ("waist", "chest"):
            b[k] *= w
        b["limb"] *= 1 + (w - 1) * 0.6
    b["px"] = dict(ov)
    return b


def _hair_mat(b):
    ov = b.get("px", {})
    if ov.get("hair"):
        return ov["hair"]
    return "grey" if b.get("hair") == "grey" else "hair"


# ----------------------------------------------------------------------
# 零碎：帽子、头巾、烫发、胡子、红领巾、挎包、菜篮子
# ----------------------------------------------------------------------

def glasses(p, b, hx, hy, r):
    """点出来的眼镜：一圈细框（上沿深、下沿浅）把眼珠框住，一条镜腿往耳朵去。"""
    ex, ey = p.to_px(hx + r * 0.52, hy - r * 0.04)
    F = PA.RAMP["line"][1]
    G = PA.RAMP["steel"][3]
    for dx in (-1, 0, 1):
        p.pix(ex + dx, ey - 1, F)
        p.pix(ex + dx, ey + 2, G, only_skin=True)
    for dy in (0, 1):
        p.pix(ex - 2, ey + dy, G, only_skin=True)
        p.pix(ex + 2, ey + dy, G, only_skin=True)
    for dx in (-3, -4, -5):
        p.pix(ex + dx, ey, F, only_skin=True)


def extras(p, layer, J):
    b = J["b"]
    ov = b.get("px", {})
    hx, hy, r = J["head"]
    hm = _hair_mat(b)
    if layer == "body":
        if ov.get("perm"):
            # 烫发：后脑勺一圈小卷，剪影鼓起来
            for a in range(140, 290, 30):
                t = math.radians(a)
                p.shape(ell(hx + r * 1.0 * math.cos(t), hy + r * 0.95 * math.sin(t), r * 0.36, r * 0.36, 12), (hm,))
        if ov.get("bun"):
            p.shape(ell(hx - r * 0.55, hy - r * 0.95, r * 0.42, r * 0.38, 14), (hm,))
        if ov.get("bag") and b["stage"] != "teen":
            hip = J["hip"]
            sh = J["shoulder"]
            p.line([(sh[0] + 3, sh[1] + 1), (hip[0] - 6, hip[1] - 6)], 2.4, ov["bag"], None)
        if ov.get("bag") and b["stage"] == "teen":
            sh = J["shoulder"]
            bx, by = sh[0] - b["waist"] * 0.5 - 2, sh[1] + 6
            p.shape(chaikin([(bx - 13, by), (bx + 4, by - 3), (bx + 4, by + 34), (bx - 12, by + 32)], 1), (ov["bag"],))
            p.line([(sh[0] - 4, sh[1] + 1), (sh[0] + 4, sh[1] + 16)], 2.0, ov["bag"], None)
    if layer == "front":
        if ov.get("perm"):
            # 头顶再压几个卷：每个卷自己有一道亮边，看着是一卷一卷的
            for a in range(195, 300, 26):
                t = math.radians(a)
                p.shape(ell(hx - r * 0.1 + r * 0.92 * math.cos(t), hy + r * 0.92 * math.sin(t), r * 0.33, r * 0.3, 12), (hm,))
        if ov.get("scarf_red"):
            # 红领巾：脖子前头一个三角
            sh = J["shoulder"]
            cw = b["chest"] * 0.5
            p.shape([(sh[0] - 2, sh[1] + 1), (sh[0] + cw + 2, sh[1] + 2), (sh[0] + cw * 0.9, sh[1] + 7), (sh[0] + cw * 0.55, sh[1] + 17),
                     (sh[0] + cw * 0.35, sh[1] + 8)], ("red_m",))
        if ov.get("bag") and b["stage"] != "teen":
            hip = J["hip"]
            p.shape([(hip[0] - 14, hip[1] - 12), (hip[0] + 2, hip[1] - 12), (hip[0] + 3, hip[1] + 4), (hip[0] - 13, hip[1] + 4)], (ov["bag"],))
        if ov.get("scarf"):
            # 头巾：包住头顶和后脑勺，后面一个结
            m = ov["scarf"]
            pts = [(hx - r * 1.12, hy + r * 0.45), (hx - r * 1.15, hy - r * 0.45), (hx - r * 0.5, hy - r * 1.18), (hx + r * 0.5, hy - r * 1.12),
                   (hx + r * 1.05, hy - r * 0.5), (hx + r * 0.95, hy - r * 0.25), (hx + r * 0.2, hy - r * 0.42), (hx - r * 0.45, hy - r * 0.1),
                   (hx - r * 0.6, hy + r * 0.5)]
            p.shape(chaikin(pts, 2), (m,))
            p.shape([(hx - r * 1.05, hy + r * 0.3), (hx - r * 1.55, hy + r * 0.55), (hx - r * 1.3, hy + r * 0.85)], (m,))
        hat = b.get("hat")
        if hat and hat[0] == "straw":
            spec = hat[1]
            p.shape(ell(hx, hy - r * 0.62, r * 1.75, r * 0.3, 24), spec)
            p.shape(chaikin([(hx - r * 0.85, hy - r * 0.62), (hx - r * 0.75, hy - r * 1.25), (hx + r * 0.75, hy - r * 1.25), (hx + r * 0.85, hy - r * 0.62)], 1), spec)
            p.line([(hx - r * 0.85, hy - r * 0.72), (hx + r * 0.85, hy - r * 0.72)], 2.4, "red_m" if ov.get("prop") != "rose" else "sage", None)
        if ov.get("glasses"):
            glasses(p, b, hx, hy, r)
        beard = ov.get("beard")
        if beard:
            mx, my = p.to_px(hx + r * 0.84, hy + r * 0.5)
            if beard in ("mustache", "mustache_w"):
                c = PA.RAMP["hair"][1] if beard == "mustache" else PA.RAMP["white"][2]
                for dx in (-2, -1, 0):
                    p.pix(mx + dx, my - 1, c)
            elif beard == "white":
                # 一小撮山羊胡：下巴底下垂下来
                c, d = PA.RAMP["white"][1], PA.RAMP["white"][2]
                for (dx, dy, col) in ((-1, 1, c), (0, 1, c), (-1, 2, c), (0, 2, d), (-1, 3, c), (-1, 4, d), (-2, 1, c)):
                    p.pix(mx + dx, my + dy, col)
                p.pix(mx - 1, my + 5, PA.RAMP["white"][3])
                p.pix(mx, my + 3, PA.RAMP["white"][3])
        if ov.get("stroller"):
            # 婴儿车的车架：车斗底下两根腿接到轱辘上
            x0 = J["hand_near"][0] + 6
            for wx in (x0 + 12, x0 + 44):
                p.line([(wx + (6 if wx < x0 + 30 else -6), -25), (wx, -9)], 2.0, "steel", None)
        if ov.get("basket"):
            h = J["hand_near"]
            # 菜篮子：一捆葱、一棵白菜冒出来
            p.shape([(h[0] + 6, h[1] + 4), (h[0] + 10, h[1] - 16), (h[0] + 13, h[1] + 4)], ("sage",))
            p.shape(ell(h[0] - 3, h[1] + 2, 7, 6, 12), ("aqua",))
            p.shape([(h[0] - 11, h[1] + 4), (h[0] + 11, h[1] + 4), (h[0] + 8, h[1] + 18), (h[0] - 8, h[1] + 18)], ("straw",))
            p.line([(h[0] - 10, h[1] + 4), (h[0], h[1] - 5), (h[0] + 10, h[1] + 4)], 2.0, "straw", None)


def dress(p, layer, J):
    """folks.dress（工作帽、安全帽、护士帽、围裙）+ 我们的零碎。"""
    b = J["b"]
    hat = b.get("hat")
    if hat and hat[0] == "straw":
        b["hat"] = None
        folks.dress(p, layer, J)
        b["hat"] = hat
    else:
        folks.dress(p, layer, J)
    extras(p, layer, J)


def hooked(fn, b, k):
    d = fn(b, k)
    inner = d.get("hook")

    def hook(p, layer, J):
        if inner:
            inner(p, layer, J)
        dress(p, layer, J)
    d["hook"] = hook
    return d


def draw(p, b, x0, y0, **kw):
    p.skin_mat = b["skin"][0]
    p.hair_mat = _hair_mat(b)
    p.remap = b["px"].get("remap", {})
    draw_person(p, b, x0=x0, y0=y0, **kw)
    p.skin_mat, p.hair_mat, p.remap = "skin", None, {}


def cell_origin(r, c):
    return (c * CW + FOOT[0]) * PX, (r * CH + FOOT[1]) * PX


# 接孩子的老人身边那个小孙子
_KID = None


def kid_body():
    global _KID
    if _KID is None:
        _KID = px_body(folks.look(True, "child", ("mustard",), pants=("denim",)), dict(shirt="sage", pants="denim", scarf_red=True, shoes="white"))
        _KID["bag"] = False
    return _KID


def draw_kid(p, x, y, k, busy):
    kb = kid_body()
    if busy:
        d = dict(pose=pose_stand(kb, 0.3), wave=k, expr="happy")
    else:
        d = dict(pose=pose_stand(kb, math.sin(k * math.tau)), expr="blink" if k == 0.75 else None)
    d["hook"] = dress
    draw(p, kb, x + 50, y, **d)


# ----------------------------------------------------------------------
# 出图
# ----------------------------------------------------------------------

def folk_bodies():
    out = {}
    for nid, (b, fn, sit, bub) in folks.FOLKS.items():
        out[nid] = (px_body(b, PX_LOOK.get(nid, {})), fn, sit, bub)
    return out


def scene_sheet(ids, bodies):
    p = FolkPainter(8, len(ids))
    for row, nid in enumerate(ids):
        b, fn, sit, _ = bodies[nid]
        kid = b["px"].get("kid")
        dx = b["px"].get("dx", 0)
        for i in range(4):
            x, y = cell_origin(row, i)
            x += dx
            draw(p, b, x, y, **hooked(fn, b, i / 4.0))
            if kid:
                draw_kid(p, x, y, i / 4.0, True)
            d = folks.idle(b, i / 4.0, sit)
            d["hook"] = dress
            x, y = cell_origin(row, 4 + i)
            x += dx
            draw(p, b, x, y, **d)
            if kid:
                draw_kid(p, x, y, i / 4.0, False)
    return p.finish()


def walker_sheet():
    p = FolkPainter(8, len(folks.WALKERS))
    for row, (name, b0) in enumerate(folks.WALKERS):
        b = px_body(b0, WALK_LOOK.get(name, {}))
        for i in range(8):
            pose = pose_walk(b, i / 8.0)
            if b["px"].get("basket"):
                pose["arms"] = [a if a["side"] == "far" else dict(side="near", shoulder=0, elbow=0, hand_rel=(0.3, 0.62)) for a in pose["arms"]]
            x, y = cell_origin(row, i)
            draw(p, b, x, y, pose=pose, hook=dress)
    return p.finish()


def up(arr, k=OUT):
    return np.repeat(np.repeat(arr, k, 0), k, 1)


def save(arr, path):
    Image.fromarray(np.ascontiguousarray(up(arr)), "RGBA").save(path, optimize=True)


def setup():
    PA.patch()
    actors._head = _head


def flat(img, bg=(214, 196, 178)):
    al = img[..., 3:4] / 255.0
    return (img[..., :3] * al + np.array(bg) * (1 - al)).astype(np.uint8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", default="", help="样张目录")
    ap.add_argument("--only", default="", help="只出这几张图（逗号分隔），加 walkers 出路人")
    a = ap.parse_args()
    setup()
    data = json.load(open(folks.FOLKS_JSON, encoding="utf-8"))
    only = set(a.only.split(",")) if a.only else None
    missing = [n["id"] for lst in data.values() for n in lst if n["id"] not in folks.FOLKS]
    if missing:
        sys.exit("folks.py 里还没给这几位画长相：" + ", ".join(missing))
    bodies = folk_bodies()
    index = {"scale": 1.0, "px": PX, "cell": [CW * PX, CH * PX], "foot": [FOOT[0] * PX, FOOT[1] * PX], "scenes": {}, "folks": {},
             "walkers": [w[0] for w in folks.WALKERS]}
    sheets = {}
    for scene, lst in sorted(data.items()):
        ids = [n["id"] for n in lst]
        index["scenes"][scene] = ids
        for row, nid in enumerate(ids):
            _b, _fn, sit, bubbles = bodies[nid]
            index["folks"][nid] = {"scene": scene, "row": row, "sit": sit, "bubbles": bubbles}
        if only and scene not in only:
            continue
        sheets[scene] = scene_sheet(ids, bodies)
    if not only or "walkers" in only:
        sheets["walkers"] = walker_sheet()
    if a.preview:
        os.makedirs(a.preview, exist_ok=True)
        for name, arr in sheets.items():
            Image.fromarray(up(flat(arr), 2)).save(os.path.join(a.preview, f"sheet_{name}.png"))
        print("✓", a.preview)
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, arr in sheets.items():
        path = os.path.join(OUT_DIR, f"{name}.png")
        save(arr, path)
        print("✓", os.path.relpath(path, PA.ROOT))
    with open(os.path.join(OUT_DIR, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("✓", os.path.relpath(os.path.join(OUT_DIR, "index.json"), PA.ROOT))


if __name__ == "__main__":
    main()
