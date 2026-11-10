"""河畔里的街坊：一个参数化的小人儿（和 actors.py 的青、梅同一套画法，但不用走路）。

    fig(sheet, spec)      在当前原点（脚底）画一个人。spec 是一个 dict，见 DEFAULT。

只有正面 / 背面两种朝向、站 / 坐两种姿势——街坊们都在各忙各的，不满街跑。
骑车的人是侧面，另有一个极简的 rider()。
局部坐标：脚底为原点，y 向上为负（和 actors.py 一样）。
"""
from __future__ import annotations

import math

from actors import SKIN, STAGES, arc_pts, capsule, chaikin, ell, lerp, part, place, rotate, rrect, solid, stroke_clear, tint, tube
from riso import rect_pts

INK = solid("ink")

BUILDS = dict(STAGES)
BUILDS["fat"] = dict(STAGES["middle"], sw=13.5, hw=13.6, belly=3.6, aw=6.6)
BUILDS["granny"] = dict(STAGES["old"], L=26, T=27, sw=11.0, hw=11.2, belly=1.6)

DEFAULT = dict(
    build="middle",
    view="front",          # front / back
    pose="stand",          # stand / sit
    top=tint("ink", 0.3),
    sleeve=None,           # 默认跟 top 一样
    sleeve_len=1.0,        # <1 短袖；0 = 背心 / 光膀子
    pants=tint("ink", 0.34),
    pants_len=1.0,
    shoes=INK,
    hem=2.0,
    gown=False,            # 大褂 / 长衫：衣摆到脚面
    bare=False,            # 光膀子（游泳的大爷）
    apron=None,            # 围裙的颜色
    collar=None,           # "v" / "stand"（立领）/ "tee"
    buttons=False,         # 一排扣子（盘扣 / 对襟）
    stripe=None,           # 胸口一道杠（工作服的反光条、外卖服）
    hair="short",          # short / crew / bald / bun / perm / bob / none
    hair_color=INK,
    hat=None,              # cook / cap / straw / swim
    hat_color=tint("ink", 0.3),
    glasses=False,
    beard=None,            # mustache / goatee / white
    eyes="open",           # open / happy / closed
    mouth="smile",         # smile / open / flat
    brows=False,
    arms=("down", "down"),  # 画面左、右两只胳膊：down / hold / behind / up / out / hip / front
    props=(),              # [(名字, "l"/"r"/"c")]
)

WHITE_HAIR = tint("ink", 0.22)


class F:
    def __init__(self, s, spec):
        self.s = s
        d = dict(DEFAULT)
        d.update(spec)
        self.p = d
        for k, v in BUILDS[d["build"]].items():
            setattr(self, k, v)
        if d["sleeve"] is None:
            d["sleeve"] = d["top"]

    # --- 四肢 ---
    def hand(self, W, k=1.0):
        part(self.s, ell(W[0], W[1], self.hr * k, self.hr * k * 1.05), SKIN, self.lw * 0.85)

    def arm(self, pts, hand=True):
        s, p, lw = self.s, self.p, self.lw
        sl = 0.0 if p["bare"] else p["sleeve_len"]
        if sl < 1:
            tube(s, pts, self.aw - 1.4, SKIN, lw)
            if sl > 0:
                from actors import slice_path
                tube(s, slice_path(pts, 0, sl), self.aw + 0.8, p["sleeve"], lw)
        else:
            tube(s, pts, self.aw, p["sleeve"], lw)
        if hand:
            self.hand(pts[-1])

    def shoe(self, A):
        rx = (self.lgw + self.lw) / 2 + 0.9
        part(self.s, ell(A[0], A[1] - 0.4, rx, 2.3), self.p["shoes"], self.lw * 0.9)

    def leg(self, hip, ank):
        s, p, lw = self.s, self.p, self.lw
        cut = max(0.0, (self.lgw + 1.2) / 2 + lw - 3.0)
        pts = [hip, lerp(hip, ank, 0.5), (ank[0], ank[1] - cut)]
        if p["pants_len"] < 1:
            from actors import slice_path
            tube(s, pts, self.lgw - 1.6, SKIN, lw)
            tube(s, slice_path(pts, 0, p["pants_len"]), self.lgw + 1.2, p["pants"], lw)
        else:
            tube(s, pts, self.lgw, p["pants"], lw)
        self.shoe(ank)

    # --- 躯干 ---
    def torso(self, sy, hy, hem):
        sw, hw, T = self.sw, self.hw, hy - sy
        xm = hw + (sw - hw) * 0.35 + self.belly
        if self.p["gown"]:
            wy = sy + T * 0.85
            pts = [(-sw + 3.5, sy - 0.6), (sw - 3.5, sy - 0.6), (sw + 0.3, sy + 3.5), (xm, sy + T * 0.6), (hw + 0.6, wy),
                   (hw + 3.0, hem), (-hw - 3.0, hem), (-hw - 0.6, wy), (-xm, sy + T * 0.6), (-sw - 0.3, sy + 3.5)]
        else:
            pts = [(-sw + 3.5, sy - 0.6), (sw - 3.5, sy - 0.6), (sw + 0.3, sy + 3.5), (xm, sy + T * 0.6),
                   (hw + 0.6, hem), (-hw - 0.6, hem), (-xm, sy + T * 0.6), (-sw - 0.3, sy + 3.5)]
        return chaikin(pts, 2)

    def deco(self, tp, sy, hy, hem, back):
        s, p, lw = self.s, self.p, self.lw
        T = hy - sy
        thin = lw * 0.55
        with s.clip(tp):
            if p["stripe"]:
                yy = sy + T * 0.42
                s.clear(rect_pts(-40, yy, 80, 4.2))
                s.pen("paper").fill(rect_pts(-40, yy, 80, 4.2))
                s.pen(*p["stripe"]).fill(rect_pts(-40, yy, 80, 4.2))
                s.ink.line([(-40, yy), (40, yy)], w=thin, amp=0)
                s.ink.line([(-40, yy + 4.2), (40, yy + 4.2)], w=thin, amp=0)
            if p["gown"] and not back:
                # 大襟：从领口斜到右腋下，再一道直缝到底；三颗盘扣
                s.ink.line([(0, sy + 2), (self.sw * 0.55, sy + T * 0.3), (self.sw * 0.5, hem + 1)], w=1.2, amp=0.2)
                for k in range(3):
                    s.ink.dot(self.sw * 0.55 - 1.2, sy + T * (0.34 + k * 0.22), 1.0)
            elif p["gown"]:
                s.ink.line([(0, hy), (0, hem + 1)], w=1.0, amp=0, density=0.7)
            if p["buttons"] and not back:
                s.ink.line([(0, sy + 3), (0, hem + 1)], w=1.1, amp=0)
                for k in range(4):
                    y = sy + 6 + k * (T - 6) / 3.6
                    if y < hem - 1:
                        s.ink.dot(1.6, y, 0.85)
            if not p["gown"] and not p["bare"] and p["pants_len"] >= 0.5 and not p["apron"]:
                s.ink.line([(-40, hem - 2.6), (40, hem - 2.6)], w=thin, amp=0.2)
            if back and not p["bare"]:
                s.ink.line([(-30, sy + T * 0.24), (30, sy + T * 0.24)], w=thin, amp=0.3)
            if p["bare"] and not back:
                for sd in (-1, 1):   # 胸口两道弧、肚脐
                    s.ink.line(arc_pts(sd * self.sw * 0.42, sy + T * 0.3, 3.6, 2.4, 20, 160, 6), w=1.0, amp=0, density=0.7)
                s.ink.dot(0, sy + T * 0.72, 0.9)
        if back:
            return
        c = p["collar"]
        if c == "v":
            part(s, [(-3.8, sy - 1.0), (3.8, sy - 1.0), (0, sy + 5.4)], SKIN, thin)
        elif c == "stand":
            part(s, rrect(-4.6, sy - 2.2, 9.2, 3.6, 1.4), p["top"], thin)
            s.ink.line([(0, sy - 2.0), (0, sy + 1.4)], w=1.0, amp=0)
        elif c == "tee":
            part(s, arc_pts(0, sy - 1.0, 4.2, 3.4, 0, 180, 8), SKIN, thin)
        if p["apron"]:
            a0, a1 = sy + T * 0.3, hem + (self.L * 0.42 if not p["gown"] else 0)
            w0, w1 = self.sw * 0.62, self.hw + 1.4
            ap = chaikin([(-w0, a0), (w0, a0), (w1, a0 + T * 0.4), (w1, a1), (-w1, a1), (-w1, a0 + T * 0.4)], 1)
            part(s, ap, p["apron"], lw * 0.8)
            for sd in (-1, 1):
                s.ink.line([(sd * w0 * 0.9, a0), (sd * 2.6, sy - 0.5)], w=1.2, amp=0)
            part(s, rrect(-4.4, a0 + T * 0.5, 8.8, 5.2, 1.0), p["apron"], thin, occlude=False)

    # --- 头 ---
    def head(self, back):
        s, p, r, lw = self.s, self.p, self.r, self.lw
        rx, ry = r * 1.06, r * 0.97
        hair, hl = p["hair_color"], lw * 0.8
        R = r + 1.8
        st = p["hair"]
        if st == "bob" and not back:
            Rb = r + 2.4
            bk = arc_pts(0, 0, Rb * 1.03, Rb, 180, 360) + [(Rb * 1.03, 0.56 * r), (0.55 * r, 0.74 * r), (-0.55 * r, 0.74 * r), (-Rb * 1.03, 0.56 * r)]
            part(s, chaikin(bk, 1), hair, hl)
        if st == "bun":
            part(s, ell(0, -R - 3.2, 5.6, 4.6), hair, hl)
        if not back and st not in ("bob", "perm"):
            for sd in (-1, 1):
                part(s, ell(sd * (rx + 0.3), 0.16 * r, 0.25 * r, 0.3 * r), SKIN, hl)
        if st == "perm":
            part(s, self._cloud(150, 390, 9, R + 0.8), hair, hl)
        part(s, ell(0, 0, rx, ry), SKIN, lw)
        if back:
            if st == "bald":
                for sd in (-1, 1):
                    part(s, ell(sd * rx * 0.86, 0.2 * r, 0.26 * r, 0.42 * r), hair, hl)
                part(s, arc_pts(0, 0.1 * r, rx * 0.98, ry * 0.9, 20, 160, 12), hair, hl)
            elif st == "perm":
                part(s, self._cloud(150, 390, 10, R + 0.8) + [(0.9 * R, 0.45 * r), (-0.9 * R, 0.45 * r)], hair, hl, amp=0.2)
            elif st == "bob":
                Rb = r + 2.4
                pts = arc_pts(0, 0, Rb * 1.03, Rb, 174, 366, 28) + [(Rb * 1.03, 0.62 * r), (0.5 * rx, 0.72 * r), (-0.5 * rx, 0.72 * r), (-Rb * 1.03, 0.62 * r)]
                part(s, chaikin(pts, 1), hair, hl, amp=0.3)
            elif st != "none":
                bottom = [(0.80, 0.52), (0.4, 0.58), (0.0, 0.5), (-0.4, 0.58), (-0.80, 0.52)]
                pts = arc_pts(0, 0, R * 1.04, R, 154, 386, 28) + [(x * rx, y * r) for x, y in bottom]
                part(s, pts, hair, hl, amp=0.3)
                for sd in (-1, 1):
                    part(s, ell(sd * (rx + 0.2), 0.24 * r, 0.16 * r, 0.22 * r), SKIN, hl * 0.85)
        else:
            self.face()
            if st == "short":
                inner = [(0.92, 0.20), (0.84, -0.18), (0.5, -0.42), (0.0, -0.34), (-0.5, -0.42), (-0.84, -0.18), (-0.92, 0.20)]
                pts = arc_pts(0, 0, R * 1.04, R, 166, 374, 26) + [(x * rx, y * r) for x, y in inner]
                part(s, pts, hair, hl, amp=0.3)
            elif st == "crew":
                inner = [(0.9, -0.2), (0.7, -0.5), (0.0, -0.56), (-0.7, -0.5), (-0.9, -0.2)]
                pts = arc_pts(0, 0, R * 1.0, R * 0.97, 188, 352, 22) + [(x * rx, y * r) for x, y in inner]
                part(s, pts, hair, hl, amp=0.3)
            elif st == "bun":
                inner = [(0.92, 0.1), (0.8, -0.3), (0.3, -0.52), (0.0, -0.3), (-0.3, -0.52), (-0.8, -0.3), (-0.92, 0.1)]
                pts = arc_pts(0, 0, R * 1.04, R, 170, 370, 26) + [(x * rx, y * r) for x, y in inner]
                part(s, pts, hair, hl, amp=0.3)
            elif st == "bob":
                Rb = r + 2.4
                inner = [(0.75, 0.62), (0.79, -0.02), (0.66, -0.30), (0.33, -0.36), (0.0, -0.33), (-0.33, -0.36), (-0.66, -0.30), (-0.79, -0.02), (-0.75, 0.62)]
                pts = arc_pts(0, 0, Rb * 1.03, Rb, 180, 360, 26) + [(Rb * 1.03, 0.56 * r)] + [(x * rx, y * r) for x, y in inner] + [(-Rb * 1.03, 0.56 * r)]
                part(s, pts, hair, hl, amp=0.3)
            elif st == "perm":
                fr = self._cloud(168, 372, 8, R + 0.8) + [(0.88 * rx, 0.12 * r), (0.62 * rx, -0.3 * r), (0.2 * rx, -0.42 * r), (-0.2 * rx, -0.3 * r), (-0.62 * rx, -0.42 * r), (-0.88 * rx, 0.12 * r)]
                part(s, fr, hair, hl, amp=0.2)
            elif st == "bald":
                for sd in (-1, 1):   # 两鬓剩下的一撮
                    part(s, ell(sd * rx * 0.93, -0.12 * r, 0.2 * r, 0.36 * r), hair, hl)
                s.ink.line(arc_pts(0, 0, rx * 0.62, ry * 0.66, 232, 262, 5), w=1.0, amp=0, density=0.6)
        if hair == INK and st in ("short", "bob", "bun") and p["hat"] is None:
            stroke_clear(s, arc_pts(0, 0, (R if st != "bob" else r + 2.4) * 0.74, R * 0.72, 222 if not back else 290, 250 if not back else 318, 6), 1.3, colors=("ink",))
        self.hat(back)

    def _cloud(self, a0, a1, nb, Rp, amp=0.09):
        out = []
        n = nb * 6
        for i in range(n + 1):
            tt = i / n
            a = math.radians(a0 + (a1 - a0) * tt)
            m = 1 + amp * abs(math.sin(math.pi * tt * nb))
            out.append((Rp * 1.04 * m * math.cos(a), Rp * m * math.sin(a)))
        return out

    def face(self):
        s, p, r = self.s, self.p, self.r
        rx = r * 1.06
        ex, ey = rx * 0.40, r * 0.13
        er = r * 0.12
        for sd in (-1, 1):
            x = sd * ex
            if p["eyes"] == "open":
                s.ink.dot(x, ey, er)
            elif p["eyes"] == "happy":
                s.ink.line(arc_pts(x, ey + 0.9, 2.1, 2.0, 200, 340, 6), w=1.4, amp=0)
            else:
                s.ink.line(arc_pts(x, ey - 0.9, 2.1, 1.8, 20, 160, 6), w=1.4, amp=0)
            s.pen("mei", 0.25).fill(ell(sd * rx * 0.54, r * 0.46, r * 0.18, r * 0.12))
            if p["brows"]:
                s.ink.line([(x - sd * 2.6, ey - 5.4), (x + sd * 1.8, ey - 4.4)], w=1.5, amp=0)
        my = r * 0.45
        if p["beard"] == "white":      # 一把白胡子
            bd = chaikin([(-5.2, my - 1.5), (5.2, my - 1.5), (4.2, my + 5.5), (0, my + 10.5), (-4.2, my + 5.5)], 2)
            part(s, bd, SKIN, self.lw * 0.7)
            for dx in (-2, 0, 2):
                s.ink.line([(dx, my + 2), (dx * 0.6, my + 7.5)], w=0.8, amp=0, density=0.6)
        if p["mouth"] == "open":
            pts = [(-2.3, my - 0.4), (2.3, my - 0.4)] + arc_pts(0, my - 0.4, 2.3, 2.4, 0, 180, 8)
            s.ink.poly(pts, w=0.8, fill=True, amp=0)
        elif p["mouth"] == "flat":
            s.ink.line([(-1.8, my), (1.8, my)], w=1.3, amp=0)
        else:
            s.ink.line(arc_pts(0, my - 1.3, 1.7, 1.4, 30, 150, 6), w=1.3, amp=0)
        if p["beard"] == "mustache":
            for sd in (-1, 1):
                s.ink.line([(sd * 0.6, my - 2.6), (sd * 4.2, my - 1.6)], w=1.8, amp=0)
        elif p["beard"] == "goatee":
            s.ink.poly([(-2.2, my + 2.2), (2.2, my + 2.2), (0, my + 6.5)], w=0.8, fill=True, amp=0)
        if p["glasses"]:
            g = r * 0.27
            for sd in (-1, 1):
                s.ink.poly(ell(sd * ex, ey + 0.5, g, g * 0.85, 18), w=1.2, amp=0)
                s.ink.line([(sd * (ex + g), ey), (sd * (rx + 0.3), ey - 1.0)], w=1.1, amp=0)
            s.ink.line(arc_pts(0, ey + 0.2, ex - g, 1.2, 200, 340, 4), w=1.1, amp=0)

    def hat(self, back):
        s, p, r, lw = self.s, self.p, self.r, self.lw
        h = p["hat"]
        if not h:
            return
        rx = r * 1.06
        hc = p["hat_color"]
        if h == "cook":      # 白布帽：一个矮矮的圆筒
            band = [(-rx * 0.86, -r * 0.5), (rx * 0.86, -r * 0.5), (rx * 0.9, -r * 1.02), (-rx * 0.9, -r * 1.02)]
            crown = arc_pts(0, -r * 1.02, rx * 0.98, r * 0.42, 180, 360, 14)
            part(s, crown, SKIN, lw * 0.8)
            part(s, band, SKIN, lw * 0.8)
        elif h == "cap":     # 前进帽 / 鸭舌帽
            dome = arc_pts(0, -r * 0.42, rx * 1.02, r * 0.74, 180, 360, 16)
            part(s, dome, hc, lw * 0.8)
            if not back:
                brim = chaikin([(-rx * 0.84, -r * 0.44), (rx * 0.84, -r * 0.44), (rx * 0.66, -r * 0.24), (-rx * 0.66, -r * 0.24)], 1)
                part(s, brim, hc, lw * 0.8)
                s.pen("ink", 0.3).fill(brim)
            s.ink.dot(0, -r * 1.14, 1.4)
        elif h == "straw":   # 草帽：宽帽檐 + 小帽顶
            brim = ell(0, -r * 0.5, rx * 1.55, r * 0.34, 28)
            part(s, brim, tint("ink", 0.1), lw * 0.8)
            dome = arc_pts(0, -r * 0.56, rx * 0.86, r * 0.62, 180, 360, 14)
            part(s, dome, tint("ink", 0.1), lw * 0.8)
            for k in (-0.5, 0, 0.5):
                s.ink.line(arc_pts(0, -r * 0.56, rx * 0.86 * (1 - abs(k) * 0.5), r * (0.6 - abs(k) * 0.1), 200 + k * 30, 340 + k * 30, 6), w=0.7, amp=0, density=0.5)
            s.pen("mei").line([(-rx * 0.84, -r * 0.6), (rx * 0.84, -r * 0.6)], w=2.0, amp=0)
        elif h == "swim":    # 泳帽：紧紧箍着
            dome = arc_pts(0, -r * 0.2, rx * 1.03, r * 0.9, 184, 356, 18)
            part(s, dome, hc, lw * 0.8)
            s.ink.line(arc_pts(0, -r * 0.2, rx * 0.5, r * 0.88, 200, 340, 8), w=0.9, amp=0, density=0.7)
        elif h == "helmet":
            dome = arc_pts(0, -r * 0.3, rx * 1.1, r * 0.86, 180, 360, 18)
            part(s, dome, hc, lw * 0.8)
            s.ink.line([(-rx * 1.1, -r * 0.3), (rx * 1.1, -r * 0.3)], w=1.6, amp=0)

    # --- 胳膊的姿势 ---
    def arm_pts(self, sd, pose, sy, hy):
        sw, A = self.sw, self.A
        S = (sd * (sw - 2.6), sy + 3.6)
        if pose == "hold":      # 手在胸前端着东西
            return [S, (sd * (sw + 1.2), sy + 3.6 + A * 0.5), (sd * (sw * 0.55), sy + 3.6 + A * 0.42)], False
        if pose == "behind":    # 背着手
            return [S, (sd * (sw + 0.8), sy + 3.6 + A * 0.42), (sd * (self.hw * 0.4), hy - 3.0)], True
        if pose == "up":        # 举起来
            return [S, (sd * (sw + 6.0), sy + 0.5), (sd * (sw + 7.5), sy - A * 0.42)], False
        if pose == "high":      # 高举过头（举手机、扎猛子前伸胳膊）
            return [S, (sd * (sw + 3.5), sy - A * 0.3), (sd * (sw + 1.5), sy - A * 0.86)], False
        if pose == "out":       # 平伸出去（比划、指）
            return [S, (sd * (sw + A * 0.42), sy + 5.0), (sd * (sw + A * 0.82), sy + 2.0)], False
        if pose == "hip":       # 叉腰
            return [S, (sd * (sw + 6.5), sy + A * 0.5), (sd * (self.hw + 1.5), hy - 4.0)], False
        if pose == "front":     # 小臂抬到身前（摇扇子、打快板）
            return [S, (sd * (sw + 2.2), sy + 3.6 + A * 0.46), (sd * (sw + 3.4), sy + A * 0.34)], False
        W = (sd * (sw + 1.2), sy + 3.6 + A)
        E = lerp(S, W, 0.5)
        return [S, (E[0] + sd * 0.9, E[1]), W], False

    def draw(self):
        s, p, lw = self.s, self.p, self.lw
        L, T = self.L, self.T
        back = p["view"] == "back"
        sit = p["pose"] == "sit"
        hy = -(round(L * 0.6 + 1.5)) if sit else -L
        sy = hy - T
        hem = hy + p["hem"]
        if p["gown"]:
            hem = -6.5 if not sit else hy + 2
        lx = self.hw * 0.45
        if sit:
            if not back:
                for sd in (-1, 1):
                    kn = (sd * lx * 1.2, hy + 3.0)
                    ank = (sd * lx * 1.3, -4.0)
                    spec = SKIN if p["pants_len"] < 1 else (p["top"] if p["gown"] else p["pants"])
                    tube(s, [kn, (ank[0], ank[1] - max(0.0, (self.lgw + 1.2) / 2 + lw - 3.0))], self.lgw - (1.6 if p["pants_len"] < 1 else 0), spec, lw)
                    self.shoe(ank)
        else:
            for sd in (-1, 1):
                self.leg((sd * lx, hy - 2.5), (sd * lx * 1.06, -4.0))
        arms = [self.arm_pts(sd, pose, sy, hy) for sd, pose in zip((-1, 1), p["arms"])]
        if back:   # 背面：举着的手还在前面，其余照常
            pass
        for pts, under in arms:
            if under and not back:
                self.arm(pts, hand=False)
        part(s, rrect(-2.7, sy - self.n - 5, 5.4, self.n + 7, 1.5), SKIN, lw * 0.8)
        tp = self.torso(sy, hy, hem if not sit else hy + 1.5)
        part(s, tp, SKIN if p["bare"] else p["top"], lw)
        self.deco(tp, sy, hy, hem if not sit else hy + 1.5, back)
        if sit and not back:
            spec = p["top"] if p["gown"] else p["pants"]
            kw = lx * 1.2 + (self.lgw + lw) / 2 + 0.6
            part(s, rrect(-kw, hy - 2.5, 2 * kw, 7.0, 3.2), spec, lw)
            s.ink.line([(0, hy - 1.0), (0, hy + 4.0)], w=1.3, amp=0)
        hands = {}
        for (pts, under), sd, pose in zip(arms, (-1, 1), p["arms"]):
            if under and not back:
                continue
            if under and back:
                self.arm(pts, hand=False)
                part(s, ell(0, pts[-1][1], self.hr * 1.5, self.hr * 1.1), SKIN, lw * 0.85)
                continue
            self.arm(pts, hand=True)
            hands["l" if sd < 0 else "r"] = pts[-1]
        hands["c"] = (0, sy + 3.6 + self.A * 0.4)
        self.hands = hands
        self.hcy = sy - self.n - self.r * 0.95 + getattr(self, "hunch", 0) * 0.5
        for name, where in p["props"]:
            if name in PROPS_UNDER_HEAD:
                PROPS[name](self, hands.get(where, hands["c"]), -1 if where == "l" else 1)
        hcy = self.hcy
        with place(s, 0, hcy):
            self.head(back)
        for name, where in p["props"]:
            if name not in PROPS_UNDER_HEAD:
                PROPS[name](self, hands.get(where, hands["c"]), -1 if where == "l" else 1)


# ----------------------------------------------------------------------
# 手里的东西。W 是手的位置，d 是哪只手（-1 画面左 / 1 画面右）
# ----------------------------------------------------------------------

def p_fan(f, W, d):
    """打开的折扇：说相声的吃饭家伙。"""
    s = f.s
    c = (W[0], W[1])
    a0, a1 = (200, 310) if d < 0 else (230, 340)
    R = 13
    pts = [c] + arc_pts(c[0], c[1], R, R, a0, a1, 10)
    part(s, pts, SKIN, 1.6, amp=0.2)
    for k in range(1, 5):
        a = math.radians(a0 + (a1 - a0) * k / 5)
        s.ink.line([c, (c[0] + R * math.cos(a), c[1] + R * math.sin(a))], w=0.8, amp=0, density=0.7)
    s.pen("mei").line(arc_pts(c[0], c[1], R * 0.62, R * 0.62, a0 + 8, a1 - 8, 6), w=1.6, amp=0)
    f.hand(W)


def p_fan_closed(f, W, d):
    s = f.s
    tip = (W[0] + d * 5, W[1] - 13)
    s.ink.line([(W[0] - d * 1.5, W[1] + 4), tip], w=3.4, amp=0)
    stroke_clear(s, [(W[0], W[1] - 2), (tip[0] - d * 0.6, tip[1] + 1.5)], 1.2, colors=("ink",))
    f.hand(W)


def p_pufan(f, W, d):
    """蒲扇。"""
    s = f.s
    c = (W[0] + d * 4, W[1] - 13)
    s.ink.line([(W[0], W[1] + 3), c], w=2.0, amp=0)
    leaf = chaikin([(c[0] - 9, c[1] + 4), (c[0] - 10, c[1] - 6), (c[0], c[1] - 13), (c[0] + 10, c[1] - 6), (c[0] + 9, c[1] + 4), (c[0], c[1] + 7)], 2)
    part(s, leaf, tint("ink", 0.1), 1.6, amp=0.2)
    for k in (-0.5, 0, 0.5):
        s.ink.line([(c[0], c[1] + 6), (c[0] + k * 14, c[1] - 9)], w=0.7, amp=0, density=0.6)
    f.hand(W)


def p_clapper(f, W, d):
    """快板（两块竹板）。"""
    s = f.s
    for k, ang in ((0, -14), (1, 16)):
        pts = rotate(rrect(W[0] - 2.2, W[1] - 13, 4.4, 13, 1.2), ang * d, (W[0], W[1]))
        part(s, pts, tint("ink", 0.2), 1.3, amp=0)
    s.pen("mei").dot(W[0], W[1] - 1, 1.6)
    f.hand(W)


def p_spatula(f, W, d):
    """摊煎饼的刮板（T 字的小竹耙子）。"""
    s = f.s
    tip = (W[0] + d * 3, W[1] - 15)
    s.ink.line([(W[0], W[1] + 3), tip], w=2.0, amp=0)
    s.ink.line([(tip[0] - 6, tip[1]), (tip[0] + 6, tip[1])], w=2.6, amp=0)
    f.hand(W)


def p_wrench(f, W, d):
    s = f.s
    tip = (W[0] + d * 6, W[1] - 13)
    s.ink.line([(W[0] - d * 1, W[1] + 3), tip], w=2.6, amp=0)
    s.ink.line(arc_pts(tip[0], tip[1] - 2.4, 3.2, 3.2, 20, 320, 8), w=2.0, amp=0)
    f.hand(W)


def p_cage(f, W, d):
    """鸟笼：罩着一半青布。"""
    s = f.s
    cx, top = W[0] + d * 1.5, W[1] + 3
    s.ink.line(arc_pts(cx, top - 1, 2.6, 3, 180, 360, 6), w=1.6, amp=0)
    body = chaikin([(cx - 9, top + 6), (cx - 7, top), (cx + 7, top), (cx + 9, top + 6), (cx + 9, top + 20), (cx - 9, top + 20)], 1)
    part(s, body, SKIN, 1.6, amp=0.2)
    for k in range(-2, 3):
        s.ink.line([(cx + k * 3.6, top + 1), (cx + k * 3.6, top + 20)], w=0.7, amp=0, density=0.75)
    cover = [(cx - 9, top + 6), (cx - 7, top), (cx + 7, top), (cx + 9, top + 6), (cx + 9, top + 11), (cx - 9, top + 11)]
    with s.clip(body):
        s.pen("qing", 0.8).fill(cover)
    s.ink.line([(cx - 9, top + 11), (cx + 9, top + 11)], w=1.0, amp=0)
    s.ink.dot(cx + 2, top + 15.5, 1.9)        # 里头的鸟
    s.ink.line([(cx + 3.5, top + 15), (cx + 6, top + 14.4)], w=1.0, amp=0)
    s.ink.line([(cx - 10, top + 20), (cx + 10, top + 20)], w=2.0, amp=0)
    f.hand(W)


def p_phone(f, W, d):
    """举着的手机（屏幕朝自己，我们看见背面）。"""
    s = f.s
    pts = rrect(W[0] - 4.5, W[1] - 12, 9, 14, 1.8)
    part(s, pts, tint("ink", 0.12), 1.5, amp=0)
    s.ink.dot(W[0] - 1.6, W[1] - 8.6, 1.3)
    f.hand(W)


def p_bowl(f, W, d):
    """一只碗（茶汤 / 盖碗）。"""
    s = f.s
    cx, cy = W[0], W[1] - 2
    body = arc_pts(cx, cy, 7, 5.5, 180, 0, 10)
    part(s, body, SKIN, 1.5, amp=0)
    with s.clip(body):
        s.pen("qing").fill(rect_pts(cx - 8, cy + 1.6, 16, 1.6))
    part(s, ell(cx, cy, 7, 1.8, 14), tint("mei", 0.4), 1.2, occlude=False)
    for k in (-1, 1):
        s.ink.line([(cx + 1.5 * k, cy - 3), (cx + 0.4 * k, cy - 6), (cx + 1.8 * k, cy - 9)], w=1.0, amp=0, density=0.6)
    f.hand((W[0] - 6, W[1] + 1.5))
    f.hand((W[0] + 6, W[1] + 1.5))


def p_tanghulu(f, W, d):
    """插满糖堆儿的草靶子：一根长杆，顶上一捆草，扎着七八串。"""
    s = f.s
    top = (W[0] + d * 2, W[1] - 54)
    s.ink.line([(W[0], W[1] + 26), top], w=2.6, amp=0.2)
    hay = chaikin([(top[0] - 7, top[1] + 26), (top[0] - 8, top[1] + 2), (top[0], top[1] - 4), (top[0] + 8, top[1] + 2), (top[0] + 7, top[1] + 26)], 2)
    part(s, hay, tint("ink", 0.14), 1.6, amp=0.3)
    for k in range(4):
        s.ink.line([(top[0] - 6, top[1] + 4 + k * 6), (top[0] + 6, top[1] + 6 + k * 6)], w=0.7, amp=0, density=0.5)
    for k, (ang, y) in enumerate(((-62, 4), (58, 2), (-74, 12), (70, 11), (-50, 20), (48, 19), (-10, -2))):
        a = math.radians(ang - 90)
        base = (top[0], top[1] + y)
        for j in range(4):
            c = (base[0] + math.cos(a) * (7 + j * 4.6), base[1] + math.sin(a) * (7 + j * 4.6))
            if j == 3:
                s.ink.line([c, (c[0] + math.cos(a) * 5, c[1] + math.sin(a) * 5)], w=0.9, amp=0)
            else:
                part(s, ell(c[0], c[1], 2.5, 2.5, 10), solid("mei"), 0.9, amp=0)
    f.hand(W)


def p_rod(f, W, d):
    """鱼竿：斜着伸出画面。"""
    s = f.s
    tip = (W[0] + d * 38, W[1] - 44)
    s.ink.line([(W[0] - d * 5, W[1] + 6), W, tip], w=1.8, amp=0.2)
    s.ink.line([tip, (tip[0] + d * 3, tip[1] + 30)], w=0.8, amp=0.5, density=0.8)
    f.hand(W)


def p_towel(f, W, d):
    """搭在脖子上的白毛巾。"""
    s = f.s
    sy = f.hcy + f.r * 0.95 + f.n
    for sd in (-1, 1):
        t = [(sd * 1.5, sy - 2), (sd * 6.5, sy - 1), (sd * 7.5, sy + 13), (sd * 3.2, sy + 13)]
        part(s, chaikin(t, 1), SKIN, 1.3, amp=0.2)
        s.pen("qing").line([(sd * 3.6, sy + 10), (sd * 7.2, sy + 10)], w=1.2, amp=0)


def p_teapot(f, W, d):
    """手里托着的小紫砂壶。"""
    s = f.s
    cx, cy = W[0], W[1] - 4
    s.ink.line([(cx + d * 5, cy - 1), (cx + d * 10, cy - 4)], w=1.8, amp=0)
    s.ink.line(arc_pts(cx - d * 6, cy, 3, 3, 90, 270, 6) if d > 0 else arc_pts(cx - d * 6, cy, 3, 3, -90, 90, 6), w=1.4, amp=0)
    part(s, ell(cx, cy, 6, 4.6, 14), tint("mei", 0.6), 1.4, amp=0)
    s.pen("ink", 0.2).fill(ell(cx, cy, 6, 4.6, 14))
    s.ink.dot(cx, cy - 4.8, 1.3)
    f.hand(W)


PROPS = dict(fan=p_fan, fan_closed=p_fan_closed, pufan=p_pufan, clapper=p_clapper, spatula=p_spatula, wrench=p_wrench,
             cage=p_cage, phone=p_phone, bowl=p_bowl, tanghulu=p_tanghulu, rod=p_rod, towel=p_towel, teapot=p_teapot)
PROPS_UNDER_HEAD = {"towel", "tanghulu"}


def fig(s, spec):
    f = F(s, spec)
    f.draw()
    return f


# ----------------------------------------------------------------------
# 骑车的人（侧面，朝右；朝左由引擎翻转）
# ----------------------------------------------------------------------

def rider(s, hip, bar, pedal, pedal_far, top=tint("ink", 0.4), pants=tint("ink", 0.34), hair=INK, hat=None, hat_color=solid("qing"), r=12.5, lean=7.0, box=None):
    """hip 车座、bar 车把、pedal / pedal_far 近侧和远侧脚蹬的位置。"""
    lw = 2.6
    sh = (hip[0] + lean, hip[1] - 25)

    def leg(ped, spec, shade):
        knee = (lerp(hip, ped, 0.5)[0] + 8.5, lerp(hip, ped, 0.5)[1] - 2.5)
        tube(s, [hip, knee, ped], 6.2, spec, lw, shade=shade)
        part(s, capsule((ped[0] - 2.2, ped[1]), (ped[0] + 5.2, ped[1]), 2.4), INK, lw * 0.85)

    leg(pedal_far, pants, 0.25)
    if box:      # 后座的箱子（外卖）
        bx, by, bw, bh = hip[0] - 31, hip[1] - 23, 23, 22
        part(s, rrect(bx, by, bw, bh, 2.5), box, lw * 0.9)
        s.ink.line([(bx, by + 6), (bx + bw, by + 6)], w=1.2, amp=0)
    torso = chaikin([(hip[0] - 6.5, hip[1] + 1), (hip[0] + 6.5, hip[1] + 1), (sh[0] + 7.5, sh[1] + 5), (sh[0] + 5, sh[1] - 2), (sh[0] - 5, sh[1] - 2), (sh[0] - 8, sh[1] + 6)], 2)
    part(s, torso, top, lw)
    leg(pedal, pants, 0.0)
    elbow = (lerp(sh, bar, 0.55)[0] - 1, lerp(sh, bar, 0.55)[1] + 6.5)
    tube(s, [(sh[0] + 1, sh[1] + 4), elbow, bar], 5.4, top, lw)
    part(s, ell(bar[0], bar[1], 3.0, 3.1), SKIN, lw * 0.85)
    hc = (sh[0] + 2.5, sh[1] - 2.5 - r)
    with place(s, hc[0], hc[1]):
        rx, ry = r * 1.04, r * 0.97
        part(s, ell(0, 0, rx, ry), SKIN, lw)
        s.ink.dot(rx * 0.56, r * 0.13, r * 0.12)
        s.pen("mei", 0.25).fill(ell(rx * 0.5, r * 0.46, r * 0.17, r * 0.12))
        s.ink.line(arc_pts(rx * 0.84, r * 0.45 - 1.2, 1.3, 1.2, 40, 140, 5), w=1.2, amp=0)
        R = r + 1.6
        if hat == "helmet":
            dome = arc_pts(0, -r * 0.1, rx * 1.12, r * 1.02, 176, 368, 20) + [(rx * 1.3, r * 0.02), (rx * 0.2, -r * 0.04)]
            part(s, dome, hat_color, lw * 0.8, amp=0.2)
            s.ink.line([(-rx * 0.3, r * 0.1), (rx * 0.1, r * 0.86)], w=1.1, amp=0)
        else:
            inner = [(-0.52, 0.52), (-0.32, 0.12), (0.0, -0.18), (0.3, -0.3), (0.62, -0.26), (0.98, -0.34)]
            pts = arc_pts(0, 0, R * 1.03, R, 336, 146, 26) + [(x * rx, y * r) for x, y in inner]
            part(s, pts, hair, lw * 0.8, amp=0.3)
            part(s, ell(-0.3 * rx, 0.3 * r, 0.17 * r, 0.22 * r), SKIN, lw * 0.7)
            if hat == "cap":
                dome = arc_pts(0, -r * 0.42, rx * 1.04, r * 0.72, 180, 360, 16) + [(rx * 1.5, -r * 0.34), (rx * 1.0, -r * 0.3)]
                part(s, dome, hat_color, lw * 0.8)
