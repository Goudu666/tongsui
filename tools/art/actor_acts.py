"""《同岁》人物的专属动作和情绪动作：一个行动一套 4 帧的循环，套在 actors.py 的同一副骨架上。

每一套是一个函数 f(b, k) → draw_person 的参数（pose、sit、expr、hook），k = 0, ¼, ½, ¾ 是这一圈里的第几帧。
胳膊多半写 hand_rel=(dx, dy)：手在肩膀前 dx、下 dy（单位是胳膊全长 L），肘自己弯过去，所以五个年纪通用。
道具（本子、碗、球、车轮、炒锅…）在 hook 里按关节的位置画，跟着人走。

ACTS 的顺序就是精灵表 {role}_{stage}_act.png 里的顺序（每行两套，左 0~3 右 4~7），
client/scripts/world/actor.gd 的 ACT_LOOP 按名字对：改顺序两边一起改。
EMOTES 画在基础表 {role}_{stage}.png 的第 3、4 行。
"""
from __future__ import annotations

import math

TAU = math.tau


def _lerp(a, b, t):
    return a + (b - a) * t


def _pt(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


# ----------------------------------------------------------------------
# 姿势零件
# ----------------------------------------------------------------------

def stand_legs(b, near=(3, 4), far=(-4, 3)):
    kb = b.get("knee_bend", 0.0)
    return [dict(side="near", thigh=near[0] + kb * 0.5, knee=near[1] + kb, pitch=0),
            dict(side="far", thigh=far[0] + kb * 0.5, knee=far[1] + kb, pitch=0)]


def sit_legs(b, swing=0.0, seat=44.0):
    """坐在 44 高的凳子上：大腿水平往前，小腿往下垂（小孩够不着地，晃荡）。同 actors.draw_sit。"""
    th = 86
    reach = seat - b["ankle"] - 2
    if b["shin"] >= reach:
        kd = th - math.degrees(math.acos(min(1.0, reach / b["shin"])))
    else:
        kd = th - 8
    sw = swing * (10 if b["stage"] == "child" else 2)
    return [dict(side="near", thigh=th, knee=kd + sw, pitch=0), dict(side="far", thigh=th - 3, knee=kd - sw * 0.5 + 6, pitch=0)]


def arms(near, far, bend_near=1, bend_far=1):
    a = []
    for side, v, bd in (("near", near, bend_near), ("far", far, bend_far)):
        if isinstance(v, dict):
            a.append(dict(v, side=side))
        else:
            a.append(dict(side=side, shoulder=0, elbow=0, hand_rel=v, bend=bd))
    return a


def pose(b, legs, arm_list, lean=0.0, bob=0.0, tilt=0.0, **kw):
    d = dict(legs=legs, arms=arm_list, lean=b["lean"] + lean, bob=bob, tilt=tilt)
    d.update(kw)
    return d


def hand_at(J, rel, far=False):
    """和 draw_person 里一样算：手按 hand_rel 该落在哪（道具要在胳膊画出来之前先知道位置）。"""
    sh = J["shoulder"]
    sh = (sh[0] + (-3 if far else 1), sh[1] + 4)
    return (sh[0] + rel[0] * J["L"], sh[1] + rel[1] * J["L"])


def sz(J):
    """道具按人的个头缩放：成年人 1，小孩小一圈。"""
    return J["b"]["H"] / 170.0


# ----------------------------------------------------------------------
# 道具
# ----------------------------------------------------------------------

def chaikin(pts, it=2):
    for _ in range(it):
        out = []
        n = len(pts)
        for i in range(n):
            a, c = pts[i], pts[(i + 1) % n]
            out += [_pt(a, c, 0.25), _pt(a, c, 0.75)]
        pts = out
    return pts


def sweat(p, J, k):
    hx, hy, r = J["head"]
    y = hy - r * 0.6 + 6 * k
    pts = [(hx - r * 0.95, y - 6), (hx - r * 0.95 + 3.2, y + 1.5), (hx - r * 0.95, y + 4), (hx - r * 0.95 - 3.2, y + 1.5)]
    p.shape(pts, ("qing", 0.45), line=1.2)


def steam(p, x, y, k, n=2, h=26, color="ink", d=0.35):
    for i in range(n):
        x0 = x + (i - (n - 1) / 2) * 8
        ph = k * TAU + i * 2.1
        pts = [(x0 + 3 * math.sin(ph + j * 0.9), y - j * h / 6 - (k * 6) % 6) for j in range(6)]
        p.line(pts, 1.5, color, d)


def sparkle(p, x, y, s=7.0, color="mei"):
    for a in range(4):
        ang = math.radians(a * 45)
        p.line([(x - s * math.cos(ang), y - s * math.sin(ang)), (x + s * math.cos(ang), y + s * math.sin(ang))], 1.6 if a % 2 == 0 else 1.0, color)


def notebook(p, J, a, c, color):
    """一本摊开的本子，从 a 摊到 c（两只手底下）。"""
    t = 3.0 * sz(J)
    pts = [(a[0] - 4, a[1] + 2), (c[0] + 8, c[1] - 1), (c[0] + 9, c[1] + t + 1), (a[0] - 3, a[1] + t + 3)]
    p.shape(pts, ("paper",), line=1.5)
    p.line([(a[0] - 3, a[1] + t + 3), (c[0] + 9, c[1] + t + 1)], 2.2, color, None)
    mid = _pt(a, c, 0.5)
    p.line([(mid[0], mid[1] + 1), (mid[0] + 0.5, mid[1] + t + 2)], 0.9)


# ----------------------------------------------------------------------
# 二十套行动循环
# ----------------------------------------------------------------------

def act_write(b, k):
    """写作业：坐着弓着背，低头，本子摊在腿上，笔尖一划一划。"""
    s = math.sin(k * TAU)
    nr = (0.6 + 0.06 * math.cos(k * TAU), 0.55 + 0.03 * math.sin(2 * k * TAU))
    fr = (0.48, 0.6)

    def hook(p, layer, J):
        if layer == "body":
            notebook(p, J, hand_at(J, fr, True), hand_at(J, (0.74, 0.6)), b["role"])
        elif layer == "front":
            h = J["hand_near"]
            p.line([(h[0] + 1, h[1] + 3), (h[0] - 5, h[1] - 11)], 2.4, b["role"], None)
            p.line([(h[0] + 1, h[1] + 3), (h[0] + 2, h[1] + 5)], 1.4)
    return dict(pose=pose(b, sit_legs(b), arms(nr, fr), lean=12, tilt=18 + 2 * s), sit=True,
                expr="focus" if k != 0.75 else "think", hook=hook)


def act_read(b, k):
    """看书：两手捧着书，眼睛跟着行走，翻一页。"""
    nr, fr = (0.6, 0.18), (0.55, 0.22)

    def hook(p, layer, J):
        if layer != "front":
            return
        h1, h2 = J["hand_near"], J["hand_far"]
        c = _pt(h1, h2, 0.5)
        s = sz(J)
        w, h = 17 * s, 21 * s
        spine = (c[0] + 2, c[1] + 2)
        left = [spine, (spine[0] - w * 0.55, spine[1] - h * 0.95), (spine[0] - w * 0.5, spine[1] - h * 0.95 - 3), (spine[0] - 1, spine[1] - 4)]
        right = [spine, (spine[0] + w * 0.55, spine[1] - h * 0.95), (spine[0] + w * 0.6, spine[1] - h * 0.95 - 3), (spine[0] + 1, spine[1] - 4)]
        # 封皮
        p.shape([(spine[0] - w * 0.62, spine[1] - h), spine, (spine[0] + w * 0.66, spine[1] - h)], (b["role"], None), line=1.6)
        p.shape(left, ("paper",), line=1.3)
        p.shape(right, ("paper",), line=1.3)
        if k == 0.5:
            flip = [spine, (spine[0] + w * 0.15, spine[1] - h * 1.1), (spine[0] + w * 0.3, spine[1] - h * 1.05)]
            p.shape(flip, ("paper",), line=1.2)
        for i in range(3):
            y = spine[1] - h * (0.35 + i * 0.18)
            p.line([(spine[0] + 4, y), (spine[0] + w * 0.4, y - 3)], 0.8, "ink", 0.6)
    return dict(pose=pose(b, sit_legs(b), arms(nr, fr), lean=4, tilt=10), sit=True,
                expr="blink" if k == 0.75 else ("happy" if k == 0.5 else None), hook=hook)


def act_eat(b, k):
    """吃饭：一手端碗，一手筷子从碗里挑到嘴边，腮帮子鼓起来嚼。"""
    path = [(0.55, 0.36), (0.44, 0.08), (0.36, -0.1), (0.5, 0.18)]
    nr = path[int(k * 4) % 4]
    fr = (0.5, 0.4)

    def hook(p, layer, J):
        if layer == "body":
            c = hand_at(J, fr, True)
            s = sz(J)
            bw, bh = 12 * s + 3, 8 * s + 2
            bowl = [(c[0] - bw, c[1] - bh * 0.6)] + [(c[0] - bw * math.cos(math.radians(a)), c[1] - bh * 0.6 + bh * 1.2 * math.sin(math.radians(a))) for a in range(0, 181, 20)]
            p.shape(bowl, ("paper",), line=1.6)
            p.line([(c[0] - bw * 0.9, c[1] - bh * 0.15), (c[0] + bw * 0.9, c[1] - bh * 0.15)], 2.0, "qing", None)
            # 米饭冒尖
            p.shape([(c[0] - bw * 0.85, c[1] - bh * 0.6), (c[0] - bw * 0.3, c[1] - bh * 1.15), (c[0] + bw * 0.4, c[1] - bh * 1.1), (c[0] + bw * 0.85, c[1] - bh * 0.6)],
                    ("paper",), line=1.2)
            steam(p, c[0], c[1] - bh * 1.2, k, 2, 22 * s + 6)
        elif layer == "front":
            h = J["hand_near"]
            d = (12, 8) if k in (0.0, 0.75) else (11, -2)
            p.line([(h[0] - 3, h[1] - 3), (h[0] + d[0], h[1] + d[1])], 1.5)
            p.line([(h[0] - 2, h[1] - 1), (h[0] + d[0] + 1, h[1] + d[1] + 2)], 1.5)
    expr = {0.0: "happy", 0.25: None, 0.5: "chew", 0.75: "chew"}[k]
    return dict(pose=pose(b, sit_legs(b, math.sin(k * TAU) * 0.5), arms(nr, fr), lean=6, tilt=4), sit=True, expr=expr, hook=hook)


def act_type(b, k):
    """对着电脑：腿上一台本子，手指敲键盘，屏幕亮着一行行字。"""
    s = math.sin(k * TAU * 2)
    nr, fr = (0.72, 0.5 - 0.035 * s), (0.66, 0.53 + 0.035 * s)

    def hook(p, layer, J):
        if layer != "body":
            return
        a = hand_at(J, fr, True)
        c = hand_at(J, (0.72, 0.5))
        sc = sz(J)
        y = max(a[1], c[1]) + 4
        x0, x1 = a[0] - 12 * sc, c[0] + 10 * sc
        p.shape([(x0, y), (x1, y), (x1 + 1, y + 3.5), (x0 - 1, y + 3.5)], ("ink", 0.55, "flat"), line=1.4)
        # 屏幕往后仰着立起来，稍微转向镜头，看得见亮着的一面
        hgt = 26 * sc + 4
        scr = [(x1 - 2, y), (x1 + 8 * sc, y - hgt), (x1 - 14 * sc, y - hgt - 2), (x0 + 6 * sc, y)]
        p.shape(scr, ("paper",), line=1.6)
        p.blot([(x1 - 3, y - 2), (x1 + 5 * sc, y - hgt + 3), (x1 - 12 * sc, y - hgt + 1), (x0 + 8 * sc, y - 2)], b["role"], 0.25)
        for i in range(3):
            t = 0.3 + i * 0.2
            ya = y - hgt * t
            p.line([(x0 + 8 * sc + (x1 - 12 * sc - x0 - 8 * sc) * t * 0.6 + 4, ya), (x1 - 4 + 10 * sc * t - 6 * (i == 1), ya - 1)], 1.0, "ink", None)
    return dict(pose=pose(b, sit_legs(b), arms(nr, fr), lean=8, tilt=6), sit=True,
                expr="focus" if k != 0.5 else "think", hook=hook)


def act_kick(b, k):
    """踢球：颠球。近腿一抬把球颠起来，眼睛跟着球上下。"""
    near = {0.0: (8, 6), 0.25: (52, 22), 0.5: (6, 4), 0.75: (-12, 40)}[k]
    ball = {0.0: (34, -46), 0.25: (36, -30), 0.5: (30, -118), 0.75: (32, -82)}[k]
    tilt = {0.0: 6, 0.25: 14, 0.5: -14, 0.75: -4}[k]
    nr, fr = (0.42, 0.4), {"shoulder": -26, "elbow": 16}

    def hook(p, layer, J):
        if layer != "front":
            return
        s = sz(J)
        r = 8.5 * s + 1.5
        cx, cy = ball[0] * (0.7 + 0.3 * s), ball[1] * s
        p.shape([(cx + r * math.cos(a * TAU / 16), cy + r * math.sin(a * TAU / 16)) for a in range(16)], ("paper",), line=1.6)
        p.shape([(cx + r * 0.35 * math.cos(a * TAU / 5 + k), cy + r * 0.35 * math.sin(a * TAU / 5 + k)) for a in range(5)], ("ink", None), line=0.8)
        if k == 0.25:
            for i in range(3):
                a = math.radians(200 + i * 30)
                p.line([(cx + r * 1.4 * math.cos(a), cy + r * 1.4 * math.sin(a)), (cx + r * 2.0 * math.cos(a), cy + r * 2.0 * math.sin(a))], 1.2)
    return dict(pose=pose(b, stand_legs(b, near, (-4, 8)), arms(nr, fr), lean=3, tilt=tilt), expr="joy" if k == 0.5 else "happy", hook=hook)


def act_hop(b, k):
    """跳皮筋：蹲下、蹦起来、半空里两腿一勾、落地。皮筋在脚脖子那么高。"""
    legs = {
        0.0: stand_legs(b, (22, 38), (16, 34)),
        0.25: stand_legs(b, (6, 6), (-2, 4)),
        0.5: stand_legs(b, (34, 64), (-14, 46)),
        0.75: stand_legs(b, (8, 10), (0, 8)),
    }[k]
    bob = {0.0: 0, 0.25: 14, 0.5: 24, 0.75: 8}[k]
    nr, fr = ((0.42, 0.42), {"shoulder": -24, "elbow": 14}) if k in (0.0, 0.75) else ({"shoulder": 122, "elbow": 12}, {"shoulder": -128, "elbow": -10})

    def hook(p, layer, J):
        if layer == "front":
            p.line([(-80, -15), (80, -17)], 2.0, "mei", None)
    return dict(pose=pose(b, legs, arms(nr, fr), lean=2, bob=bob, tilt=-6 if k == 0.5 else 2),
                expr="joy" if k in (0.25, 0.5) else "happy", hook=hook)


def act_fix(b, k):
    """修车：蹲着，车轱辘立在面前，扳子一拧一拧。"""
    s = b["H"] / 170.0
    R = 30 * s + 4
    cx, cy = 34 + 26 * s, -R - 1
    turn = [0, 18, 34, 18][int(k * 4) % 4]
    legs = stand_legs(b, (78, 128), (64, 120))
    nr = {"side": "near", "shoulder": 0, "elbow": 0, "hand_to": (cx - 4 - 3 * math.cos(math.radians(turn)), cy - 6 + 4 * math.sin(math.radians(turn)))}
    fr = {"side": "far", "shoulder": 0, "elbow": 0, "hand_to": (cx - R * 0.15, cy - R * 0.95)}

    def hook(p, layer, J):
        if layer == "back":
            pts = [(cx + R * math.cos(a * TAU / 36), cy + R * math.sin(a * TAU / 36)) for a in range(36)]
            p.line(pts + [pts[0]], 5.0)
            p.line(pts + [pts[0]], 2.0, "ink", 0.0)
            for i in range(8):
                a = i * TAU / 8 + 0.2
                p.line([(cx, cy), (cx + R * 0.92 * math.cos(a), cy + R * 0.92 * math.sin(a))], 0.8, "ink", 0.8)
            p.dot(cx, cy, 3.2)
        elif layer == "front":
            h = J["hand_near"]
            a = math.radians(-120 + turn)
            e = (h[0] + 13 * math.cos(a), h[1] + 13 * math.sin(a))
            p.line([h, e], 3.0, "qing", None)
            p.line(_arc(e, 3.2, a), 1.6)
            if k >= 0.5:
                sweat(p, J, k - 0.5)
    return dict(pose=pose(b, legs, arms(nr, fr), lean=22, tilt=10), expr="effort" if k != 0.0 else "focus", hook=hook)


def _arc(c, r, a):
    return [(c[0] + r * math.cos(a + t), c[1] + r * math.sin(a + t)) for t in (-1.2, -0.4, 0.4, 1.2)]


def act_carry(b, k):
    """扛活、搬东西：蹲下抱起一箱、直起腰、再放下。"""
    u = 0.5 - 0.5 * math.cos(k * TAU)  # 0 蹲 → 1 直
    legs = stand_legs(b, (_lerp(58, 4, u), _lerp(100, 6, u)), (_lerp(48, -4, u), _lerp(92, 5, u)))
    nr = (0.62, _lerp(0.62, 0.18, u))
    fr = (0.55, _lerp(0.6, 0.15, u))

    def hook(p, layer, J):
        s = sz(J)
        a = hand_at(J, fr, True)
        w, h = 30 * s + 4, 22 * s + 4
        x0 = a[0] - 4
        y0 = a[1] - h * 0.55
        box = [(x0, y0), (x0 + w, y0 - 1), (x0 + w + 1, y0 + h), (x0 + 1, y0 + h + 1)]
        if layer == "body":
            p.shape(box, ("ink", 0.32), line=1.8)
            p.line([(x0 + 2, y0 + h * 0.35), (x0 + w - 1, y0 + h * 0.34)], 2.0, "mei", None)
            p.line([(x0 + w * 0.5, y0), (x0 + w * 0.52, y0 + h * 0.34)], 1.1)
        elif layer == "front" and u > 0.6:
            sweat(p, J, k)
    return dict(pose=pose(b, legs, arms(nr, fr), lean=_lerp(26, 5, u), tilt=_lerp(12, -2, u)),
                expr="effort" if u < 0.9 else "happy", hook=hook)


def act_cook(b, k):
    """炒菜：一手握锅柄，一手铲子翻；锅一颠，菜往上一蹦。"""
    toss = {0.0: 0, 0.25: 4, 0.5: 9, 0.75: 2}[k]
    fr = (0.52, 0.44 - toss / 80)
    nr = (0.78 + 0.07 * math.cos(k * TAU), 0.28 + 0.06 * math.sin(k * TAU))

    def hook(p, layer, J):
        s = sz(J)
        a = hand_at(J, fr, True)
        cx, cy = a[0] + 30 * s + 6, a[1] + 4
        w, d = 20 * s + 4, 9 * s + 2
        if layer == "body":
            p.line([a, (cx - w, cy - 2)], 3.0)
            wok = [(cx - w, cy - 2)] + [(cx - w * math.cos(math.radians(t)), cy - 2 + d * math.sin(math.radians(t))) for t in range(0, 181, 15)]
            p.shape(wok, ("ink", 0.72, "flat"), line=1.8)
            for i, (dx, hh) in enumerate(((-6, 6 + toss * 2.2), (2, 3 + toss * 3.0), (9, 5 + toss * 1.6))):
                p.dot(cx + dx * s, cy - 4 - hh, 2.6, ("mei", "qing", "mei")[i], None)
            steam(p, cx, cy - 10 - toss * 2, k, 3, 30 * s + 6)
        elif layer == "front":
            h = J["hand_near"]
            p.line([h, (h[0] + 4, h[1] + 16 * s + 4)], 2.2)
            p.line([(h[0] + 1, h[1] + 16 * s + 4), (h[0] + 8, h[1] + 16 * s + 5)], 3.2)
    return dict(pose=pose(b, stand_legs(b, (6, 8), (-6, 4)), arms(nr, fr), lean=5, tilt=12),
                expr="happy" if k == 0.5 else "focus", hook=hook)


def act_fish(b, k):
    """钓鱼：坐在马扎上，两手攥着竿，竿梢一点一点，眯着眼等。"""
    nr, fr = (0.52, 0.36), (0.4, 0.44)
    bob = 3.0 * math.sin(k * TAU)

    def hook(p, layer, J):
        if layer != "front":
            return
        h1 = J["hand_near"]
        h2 = hand_at(J, fr, True)
        d = (h1[0] - h2[0], h1[1] - h2[1])
        n = math.hypot(*d) or 1
        d = (d[0] / n, d[1] / n)
        butt = (h2[0] - d[0] * 10, h2[1] - d[1] * 10)
        tip = (92, -186 + bob * 2)
        p.line([butt, (h1[0] + 4, h1[1] - 3), tip], 2.4)
        p.line([butt, h2], 3.4, b["role"], None)
        sag = [(tip[0] + 2 * math.sin(i * 0.5), tip[1] + (8 - tip[1]) * i / 8) for i in range(9)]
        p.line(sag, 0.9, "ink", 0.7)
        p.dot(tip[0] + 1, 8 + 0.0, 2.2, "mei", None)
    return dict(pose=pose(b, sit_legs(b, seat=34.0), arms(nr, fr), lean=8, tilt=-4), sit=True, seat=34.0,
                expr={0.0: "bliss", 0.25: None, 0.5: "bliss", 0.75: "blink"}[k], hook=hook)


def act_chess(b, k):
    """下棋：一手托着下巴琢磨，一手捏起一个子儿、啪地落下。"""
    near = {0.0: (0.42, 0.62), 0.25: (0.72, 0.42), 0.5: (0.84, 0.5), 0.75: (0.62, 0.55)}[k]
    fr = (0.28, -0.12)

    def hook(p, layer, J):
        s = sz(J)
        hip = J["hip"]
        y = hip[1] - 14 * s
        if layer == "body":
            x0 = J["shoulder"][0] + 28 * s
            bw = 70 * s
            p.shape([(x0, y), (x0 + bw, y), (x0 + bw, y + 4), (x0, y + 4)], ("ink", 0.4), line=1.4)
            for i, (dx, col) in enumerate(((14 * s, "mei"), (36 * s, "ink"), (55 * s, "mei"))):
                p.shape([(x0 + dx + 5 * math.cos(a * TAU / 10), y - 2.4 + 2.2 * math.sin(a * TAU / 10)) for a in range(10)], ("paper",), line=1.2)
                p.dot(x0 + dx, y - 2.6, 1.3, col, None)
        elif layer == "front" and k in (0.25, 0.5):
            h = J["hand_near"]
            p.shape([(h[0] + 3 + 5 * math.cos(a * TAU / 10), h[1] + 4 + 2.2 * math.sin(a * TAU / 10)) for a in range(10)], ("paper",), line=1.2)
            if k == 0.5:
                for i in range(3):
                    a = math.radians(-150 + i * 60)
                    p.line([(h[0] + 3 + 8 * math.cos(a), h[1] + 1 + 6 * math.sin(a)), (h[0] + 3 + 12 * math.cos(a), h[1] + 1 + 9 * math.sin(a))], 1.1)
    return dict(pose=pose(b, sit_legs(b), arms(near, fr, 1, -1), lean=10, tilt=12),
                sit=True, expr="happy" if k == 0.5 else "think", hook=hook)


def act_talk(b, k):
    """聊天：手跟着话比划，嘴一张一合。"""
    near = {0.0: (0.35, 0.45), 0.25: (0.62, 0.05), 0.5: (0.5, 0.25), 0.75: (0.66, -0.05)}[k]
    return dict(pose=pose(b, stand_legs(b), arms(near, (0.08, 0.9)), lean=0, tilt=-3 if k in (0.25, 0.75) else 0),
                expr={0.0: None, 0.25: "open", 0.5: "happy", 0.75: "open"}[k])


def act_sing(b, k):
    """上台、唱、念稿：仰着头，一手往外送，一手按在胸口。"""
    s = math.sin(k * TAU)
    near = (0.55 + 0.06 * s, 0.02 - 0.06 * s)

    def hook(p, layer, J):
        if layer == "front" and k in (0.25, 0.75):
            hx, hy, r = J["head"]
            x, y = hx + r * 1.7, hy - r * 1.4 - (4 if k == 0.75 else 0)
            p.dot(x, y, 2.6, "mei", None)
            p.line([(x + 2.4, y), (x + 2.4, y - 10), (x + 6, y - 7)], 1.4, "mei", None)
    return dict(pose=pose(b, stand_legs(b), arms(near, (0.28, 0.32)), lean=-3 + 2 * s, tilt=-12),
                expr="sing" if k != 0.5 else "open", hook=hook)


def act_piano(b, k):
    """弹琴：手指在键上一起一落，脑袋跟着晃，眯着眼。"""
    s = math.sin(k * TAU)
    nr, fr = (0.84, 0.42 - 0.04 * s), (0.8, 0.45 + 0.04 * s)

    def hook(p, layer, J):
        if layer != "body":
            return
        a = hand_at(J, fr, True)
        y = a[1] + 3
        x0 = a[0] - 18
        p.shape([(x0, y), (x0 + 58, y), (x0 + 58, y + 6), (x0, y + 6)], ("paper",), line=1.4)
        for i in range(1, 12):
            x = x0 + i * 58 / 12
            p.line([(x, y), (x, y + 6)], 0.7)
            if i % 7 not in (0, 3):
                p.line([(x, y), (x, y + 3.2)], 2.4)
    return dict(pose=pose(b, sit_legs(b), arms(nr, fr), lean=6, tilt=4 * s), sit=True,
                expr="bliss" if k != 0.75 else "sing", hook=hook)


def act_kite(b, k):
    """放风筝、放鸽子：仰着脸，一手攥线往上一扯一扯，风筝在天上。"""
    s = math.sin(k * TAU)
    nr = {"shoulder": 148 + 6 * s, "elbow": 14}
    fr = (0.3, 0.12)

    def hook(p, layer, J):
        if layer != "front":
            return
        h = J["hand_near"]
        kx, ky = 74 + 4 * s, -196 + 3 * math.cos(k * TAU)
        p.line([(h[0] + 2 * (1 - t) + (kx - h[0]) * t, h[1] + (ky - h[1]) * t + 14 * math.sin(t * math.pi)) for t in [i / 10 for i in range(11)]], 0.9, "ink", 0.8)
        dia = [(kx, ky - 11), (kx + 8, ky), (kx, ky + 13), (kx - 8, ky)]
        p.shape(dia, ("mei", None), line=1.4)
        p.line([(kx, ky - 11), (kx, ky + 13)], 0.9)
        tail = [(kx + 2 * math.sin(i * 0.9 + k * TAU), ky + 13 + i * 4) for i in range(6)]
        p.line(tail, 1.2, "qing", None)
        # 线拐子
        f = J.get("hand_far", h)
        p.shape([(f[0] - 4, f[1] - 3), (f[0] + 5, f[1] - 4), (f[0] + 5, f[1] + 4), (f[0] - 4, f[1] + 5)], (b["role"], 0.5), line=1.2)
    return dict(pose=pose(b, stand_legs(b, (8, 6), (-8, 4)), arms(nr, fr), lean=-4, tilt=-18),
                expr="joy" if k in (0.25,) else "happy", hook=hook)


def act_gaze(b, k):
    """靠着栏杆、沿河溜达、阳台上站会儿：手背在身后，重心左右挪，看着远处。"""
    s = math.sin(k * TAU)
    legs = stand_legs(b, (3 + 2 * s, 4), (-4 + 2 * s, 3))
    return dict(pose=pose(b, legs, arms((-0.08, 0.9), (-0.14, 0.88), -1, -1), lean=1.5 * s, tilt=-5, no_cane=True),
                expr={0.0: None, 0.25: "bliss", 0.5: None, 0.75: "blink"}[k])


def act_wash(b, k):
    """洗澡、擦头：毛巾顶在脑袋上来回搓，冒着热气和泡泡。"""
    s = math.sin(k * TAU)
    nr, fr = (0.3 + 0.05 * s, -0.62), (0.05, -0.7 - 0.05 * s)

    def hook(p, layer, J):
        hx, hy, r = J["head"]
        if layer == "front":
            tw = [(hx - r * 1.15, hy - r * 0.2), (hx - r * 0.8, hy - r * 1.2), (hx + r * 0.4, hy - r * 1.3 + 2 * s), (hx + r * 1.1, hy - r * 0.7),
                  (hx + r * 0.9, hy - r * 0.45), (hx - r * 0.3, hy - r * 0.7), (hx - r * 0.85, hy + r * 0.5)]
            p.shape(chaikin(tw, 1), ("paper",), line=1.6)
            p.line([(hx - r * 0.6, hy - r * 1.0), (hx + r * 0.7, hy - r * 0.95)], 1.6, b["role"], None)
            for i in range(3):
                bx = hx + r * (1.3 + 0.4 * i) + 3 * math.sin(k * TAU + i)
                by = hy - r * (1.1 + 0.5 * i) - 8 * ((k + i * 0.3) % 1)
                p.line([(bx + 2.2 * math.cos(a * TAU / 10), by + 2.2 * math.sin(a * TAU / 10)) for a in range(11)], 0.9)
    return dict(pose=pose(b, stand_legs(b), arms(nr, fr), lean=2, tilt=6), expr="bliss" if k < 0.5 else "sing", hook=hook)


def act_exercise(b, k):
    """晨练、学游泳：伸胳膊、扩胸、往下够，跟着广播一拍一拍。"""
    a = {0.0: ({"shoulder": 172, "elbow": 4}, {"shoulder": -174, "elbow": -4}), 0.25: ((0.82, -0.12), (-0.7, -0.08)), 0.5: ((0.3, 0.88), (0.2, 0.88)), 0.75: ((0.82, -0.12), (-0.7, -0.08))}[k]
    legs = stand_legs(b, (6, 6), (-6, 4)) if k != 0.5 else stand_legs(b, (24, 40), (14, 36))
    return dict(pose=pose(b, legs, arms(*a), lean=0 if k != 0.5 else 16, tilt=-6 if k == 0.0 else (14 if k == 0.5 else 0), no_cane=True),
                expr="happy" if k != 0.0 else "joy")


def act_chalk(b, k):
    """出黑板报：踮着脚，一手举着粉笔在墙上写，一手捏着粉笔盒。"""
    s = math.sin(k * TAU)
    nr = {"shoulder": 132 + 5 * s, "elbow": 12 + 6 * math.cos(k * TAU)}

    def hook(p, layer, J):
        if layer == "front":
            h = J["hand_near"]
            p.line([(h[0] + 1, h[1] - 1), (h[0] + 7, h[1] - 4)], 2.8, "paper", None)
            p.line([(h[0] + 1, h[1] - 1), (h[0] + 7, h[1] - 4)], 0.8)
            f = J.get("hand_far")
            if f:
                p.shape([(f[0] - 4, f[1] - 6), (f[0] + 5, f[1] - 6), (f[0] + 5, f[1] + 3), (f[0] - 4, f[1] + 3)], ("mei", 0.5), line=1.2)
    return dict(pose=pose(b, stand_legs(b, (2, 2), (-6, 2)), arms(nr, (0.3, 0.42)), lean=-2, tilt=-10, bob=2),
                expr="focus", hook=hook)


def act_brush(b, k):
    """拿水在地上写字：弯着腰攥着长杆，海绵笔头在地上走，身后留一行水印。"""
    s = math.sin(k * TAU)
    nr, fr = (0.5, 0.52), (0.4, 0.42)

    def hook(p, layer, J):
        if layer == "back":
            for i, (x, w) in enumerate(((40, 10), (58, 7), (72, 12))):
                if i <= int(k * 4):
                    p.line([(x, -1.5), (x + w, -2.2)], 2.4, "ink", 0.3)
                    p.line([(x + w * 0.5, -5), (x + w * 0.4, 0)], 2.0, "ink", 0.3)
        if layer != "front":
            return
        h1 = J["hand_near"]
        h2 = hand_at(J, fr, True)
        tip = (64 + 14 * math.cos(k * TAU), -4)
        top = (h2[0] - (tip[0] - h2[0]) * 0.25, h2[1] - (tip[1] - h2[1]) * 0.25)
        p.line([top, tip], 2.2)
        p.shape([(tip[0] - 4, tip[1] - 6), (tip[0] + 4, tip[1] - 6), (tip[0] + 3, tip[1] + 2), (tip[0] - 3, tip[1] + 2)], ("ink", 0.7), line=1.2)
    return dict(pose=pose(b, stand_legs(b, (12, 14), (-4, 8)), arms(nr, fr), lean=14, tilt=16, no_cane=True),
                expr="bliss" if k != 0.5 else None, hook=hook)


ACTS = [
    ("write", act_write), ("read", act_read),
    ("eat", act_eat), ("type", act_type),
    ("kick", act_kick), ("hop", act_hop),
    ("fix", act_fix), ("carry", act_carry),
    ("cook", act_cook), ("fish", act_fish),
    ("chess", act_chess), ("talk", act_talk),
    ("sing", act_sing), ("piano", act_piano),
    ("kite", act_kite), ("gaze", act_gaze),
    ("wash", act_wash), ("exercise", act_exercise),
    ("chalk", act_chalk), ("brush", act_brush),
]


# ----------------------------------------------------------------------
# 情绪动作（基础表第 3、4 行）
# ----------------------------------------------------------------------

def emo_joy(b, k):
    """高兴：一蹲、两手举起来蹦一下。"""
    legs = {0.0: stand_legs(b, (26, 44), (18, 40)), 0.25: stand_legs(b, (4, 4), (-4, 3)),
            0.5: stand_legs(b, (24, 50), (-10, 34)), 0.75: stand_legs(b, (10, 14), (4, 12))}[k]
    up = k in (0.25, 0.5)
    a = arms({"shoulder": 152, "elbow": 14}, {"shoulder": -158, "elbow": -10}) if up else arms((0.4, 0.42), {"shoulder": -22, "elbow": 14})

    def hook(p, layer, J):
        if layer == "front" and up:
            hx, hy, r = J["head"]
            sparkle(p, hx + r * 2.0, hy - r * 1.2, 6)
            sparkle(p, hx - r * 1.8, hy - r * 0.6, 4.5, "qing")
    return dict(pose=pose(b, legs, a, lean=0 if up else 8, bob={0.0: 0, 0.25: 12, 0.5: 20, 0.75: 4}[k], tilt=-8 if up else 4, no_cane=True),
                expr="joy", hook=hook)


def emo_sad(b, k):
    """泄气：塌着肩、耷拉着脑袋，叹一口气。"""
    s = math.sin(k * TAU)
    return dict(pose=pose(b, stand_legs(b, (6, 10), (-2, 8)), arms((0.14, 0.88), (0.04, 0.9)), lean=12 + 2 * s, tilt=22 + 3 * s, bob=-0.8 * s, no_cane=True),
                expr="sad" if k != 0.75 else "blink")


def emo_five(b, k):
    """击掌：迎上去一步，手掌拍在一起（两个人面对面，由引擎摆好距离）。"""
    near = {0.0: (0.35, 0.15), 0.25: (0.62, -0.42), 0.5: (0.74, -0.58), 0.75: (0.55, -0.38)}[k]
    legs = stand_legs(b, (18, 8), (-10, 4)) if k in (0.25, 0.5) else stand_legs(b)

    def hook(p, layer, J):
        if layer == "front" and k == 0.5:
            h = J["hand_near"]
            for i in range(5):
                a = math.radians(-90 + (i - 2) * 32)
                p.line([(h[0] + 6 + 7 * math.cos(a), h[1] + 7 * math.sin(a)), (h[0] + 6 + 13 * math.cos(a), h[1] + 13 * math.sin(a))], 1.5, "mei", None)
    return dict(pose=pose(b, legs, arms(near, (0.05, 0.9)), lean=4 if k in (0.25, 0.5) else 0, tilt=-4, no_cane=True),
                expr="joy" if k in (0.5, 0.75) else "happy", hook=hook)


def emo_shy(b, k):
    """不好意思：挠挠后脑勺，嘿嘿一乐。"""
    s = math.sin(k * TAU * 2)
    return dict(pose=pose(b, stand_legs(b, (4, 6), (-6, 3)), arms({"shoulder": 150 + 4 * s, "elbow": 96}, (0.1, 0.88)), lean=2, tilt=8, no_cane=True),
                expr="shy")


EMOTES = [("joy", emo_joy), ("sad", emo_sad), ("five", emo_five), ("shy", emo_shy)]
