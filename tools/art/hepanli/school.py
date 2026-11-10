"""河畔里小学（x 0~620, y 1080~1600）。

北边一道红砖围墙沿着南人行道，(320, ~1150) 开校门：两根水泥门柱，西柱挂竖牌，两扇铁栅栏门往里敞着。
门里是操场（煤渣跑道 + 梅色跑道线 + 青网点的场地），东边一溜旗杆、水泥乒乓球台、双杠单杠，
南边一栋三层教学楼（按约定只看见屋顶和朝南的正面）。

可走：校门口（人行道进来）+ 整个操场；墙、门柱、器材、楼都挡住。
锚点：flag（旗杆顶，引擎画飘的旗）。
"""
import math
import random

from common import Ctx, ellipse_pts, rect_pts, shadow, sign, spot
from kit_south import block, grass, ground_tex

GX, GY = spot("school_gate")      # (320, 1200)
WALL_BASE = 1150                   # 围墙墙根（地面上的那条线）
WALL_H = 32                        # 墙露出的正面高度
WALL_D = 10                        # 墙厚（顶面）
PIL_W, PIL_D, PIL_H = 34, 24, 86   # 门柱
GATE_L, GATE_R = GX - 36, GX + 36  # 门洞
YARD = (22, WALL_BASE, 572, 246)   # 操场可走范围 x, y, w, h
BLD_Y = 1400                       # 教学楼屋顶北沿


def draw(ctx: Ctx):
    g, o, walk = ctx.g, ctx.o, ctx.walk
    rnd = random.Random(1080)

    # ---------- 墙外：一条窄窄的绿化带，门口一块水泥地 ----------
    top = WALL_BASE - WALL_H - WALL_D
    ground_tex(g, 0, 1080, 610, top - 1080 + 2, 0.05, seed=2)
    grass(g, (0, 1082, GATE_L - 40, top - 1082), n=26, seed=4)
    grass(g, (GATE_R + 40, 1082, 600 - GATE_R - 40, top - 1082), n=24, seed=5)
    g.clear(rect_pts(GATE_L - 4, 1080, GATE_R - GATE_L + 8, WALL_BASE - 1080))
    g.pen("ink", 0.09).fill(rect_pts(GATE_L - 4, 1080, GATE_R - GATE_L + 8, WALL_BASE - 1080))
    g.ink.line([(0, 1081), (608, 1081)], 2.2)
    walk.add_rect(GATE_L, 1078, GATE_R - GATE_L, WALL_BASE - 1078 + 4)

    # ---------- 操场地面 ----------
    yx, yy, yw, yh = YARD
    ground_tex(g, yx, yy, yw, yh + 6, 0.05, seed=7, specks=60)
    walk.add_rect(*YARD)

    # 跑道：体育场形（两条直道 + 两个半圆）
    cx, cy, half, R = 250, 1292, 116, 80

    def stadium(r, n=28):
        pts = []
        for i in range(n + 1):
            a = -math.pi / 2 + math.pi * i / n
            pts.append((cx + half + r * math.cos(a), cy + r * math.sin(a)))
        for i in range(n + 1):
            a = math.pi / 2 + math.pi * i / n
            pts.append((cx - half + r * math.cos(a), cy + r * math.sin(a)))
        return pts

    outer, inner = stadium(R), stadium(R - 20)
    g.pen("ink", 0.17).fill(outer)            # 煤渣跑道
    g.clear(inner)
    g.pen("qing", 0.26).fill(inner)           # 场地
    g.pen("ink", 0.06).fill(inner)
    for r, lw in ((R, 2.0), (R - 10, 1.3), (R - 20, 2.0)):
        g.mei.poly(stadium(r), lw, amp=0.7)
    # 起跑线
    for k in range(3):
        g.mei.line([(cx - 30 + k * 7, cy + R - 20), (cx - 30 + k * 7, cy + R)], 1.4, amp=0)
    # 场地上的白线：中线、中圈、两个小球门
    g.clear(rect_pts(cx - 1.6, cy - R + 22, 3.2, 2 * R - 44))
    ring = ellipse_pts(cx, cy, 22, 22, 40)
    g.clear(ring)
    g.pen("qing", 0.26).fill(ellipse_pts(cx, cy, 19, 19, 40))
    g.pen("ink", 0.06).fill(ellipse_pts(cx, cy, 19, 19, 40))
    g.clear(rect_pts(cx - 1.6, cy - 19, 3.2, 38))
    # 两个小球门（俯视：门线 + 网兜）
    for sgn in (-1, 1):
        gx = cx + sgn * (half + 52)
        g.ink.line([(gx, cy - 22), (gx, cy + 22)], 2.2, amp=0.3)
        g.ink.line([(gx, cy - 22), (gx - sgn * 10, cy - 22)], 1.6, amp=0.2)
        g.ink.line([(gx, cy + 22), (gx - sgn * 10, cy + 22)], 1.6, amp=0.2)
        g.ink.hatch(rect_pts(min(gx, gx - sgn * 10), cy - 22, 10, 44), 45, 4, 0.8, density=0.5)

    # ---------- 东边：旗台、乒乓球台、双杠单杠 ----------
    fx, fy = 528, 1196
    block(g, fx - 28, fy - 18, 56, 30, 8, top=("ink", 0.07), face=("ink", 0.28), lw=2.0)
    block(g, fx - 16, fy - 13, 32, 18, 5, top=("ink", 0.10), face=("ink", 0.3), lw=1.6, shadow_len=0)
    walk.block_rect(fx - 30, fy - 20, 60, 46)
    pole_h = 170
    shadow(g, [(fx, fy), (fx + pole_h * 0.5, fy + pole_h * 0.16), (fx + pole_h * 0.5 + 4, fy + pole_h * 0.16 + 4), (fx + 4, fy + 4)], 0.13)
    g.ink.circle(fx, fy - 4, 4, lw=1.6, fill=True)
    o.ink.line([(fx, fy - 4), (fx, fy - 4 - pole_h)], 3.0, amp=0.2)
    o.ink.circle(fx, fy - 6 - pole_h, 3.2, lw=1.4, fill=True)
    ctx.anchor("flag", fx, fy - 4 - pole_h, base_y=fy)

    # 水泥乒乓球台（南北放）
    tx, ty, tw, td = 503, 1244, 48, 80
    block(g, tx, ty, tw, td, 12, top=("ink", 0.16), face=("ink", 0.34), lw=2.2, shadow_len=10)
    g.ink.line([(tx + 3, ty + td / 2), (tx + tw - 3, ty + td / 2)], 1.0, amp=0, density=0.5)
    g.clear(rect_pts(tx + 3, ty + 2, 1.6, td - 4))
    g.clear(rect_pts(tx + tw - 4.6, ty + 2, 1.6, td - 4))
    g.clear(rect_pts(tx + tw / 2 - 0.8, ty + 2, 1.6, td - 4))
    # 网：一块砖立在当中
    g.clear(rect_pts(tx - 2, ty + td / 2 - 6, tw + 4, 7))
    g.pen("mei", 0.55).fill(rect_pts(tx - 2, ty + td / 2 - 6, tw + 4, 7))
    g.ink.rect(tx - 2, ty + td / 2 - 6, tw + 4, 7, lw=1.4)
    walk.block_rect(tx - 2, ty - 2, tw + 4, td + 14)

    # 双杠
    bx0, bx1, by = 470, 530, 1356
    for dy in (0, 12):
        yb = by + dy
        shadow(g, [(bx0, yb), (bx1, yb), (bx1 + 14, yb + 5), (bx0 + 14, yb + 5)], 0.12)
    for dy in (0, 12):
        yb = by + dy
        for px in (bx0 + 6, bx1 - 6):
            g.ink.line([(px, yb), (px, yb - 26)], 2.2, amp=0)
        g.ink.line([(bx0, yb - 26), (bx1, yb - 26)], 2.4, amp=0.3)
    walk.block_rect(bx0, by - 4, bx1 - bx0, 20)
    # 单杠（高一点）+ 底下一小块沙坑
    sx0, sx1, sy = 548, 586, 1372
    g.pen("ink", 0.10).fill(ellipse_pts((sx0 + sx1) / 2, sy + 2, 24, 10))
    for _ in range(18):
        g.ink.dot(rnd.uniform(sx0 - 2, sx1 + 2), sy + rnd.uniform(-5, 8), 0.9, density=0.6)
    shadow(g, [(sx0, sy), (sx1, sy), (sx1 + 20, sy + 7), (sx0 + 20, sy + 7)], 0.12)
    for px in (sx0, sx1):
        g.ink.line([(px, sy), (px, sy - 44)], 2.6, amp=0)
    g.ink.line([(sx0 - 3, sy - 44), (sx1 + 3, sy - 44)], 2.0, amp=0)
    walk.block_rect(sx0 - 2, sy - 6, sx1 - sx0 + 4, 12)

    # ---------- 南边的教学楼 ----------
    building(ctx)

    # ---------- 围墙 + 校门（最后画，盖住操场的边） ----------
    walls(ctx)
    gate(ctx)


def building(ctx: Ctx):
    g = ctx.g
    x0, x1 = 34, 586
    roof_d, face_h = 58, 96
    y0 = BLD_Y
    block(g, x0, y0, x1 - x0, roof_d, face_h, top=("ink", 0.13), face=("ink", 0.07), lw=2.8, shadow_len=24)
    # 屋顶：女儿墙内沿 + 防水卷材的接缝
    g.ink.rect(x0 + 7, y0 + 7, x1 - x0 - 14, roof_d - 14, lw=1.3, density=0.6)
    g.ink.hatch(rect_pts(x0 + 8, y0 + 8, x1 - x0 - 16, roof_d - 16), 90, 26, 1.0, density=0.3)
    # 楼梯间 + 水箱
    block(g, 268, y0 + 4, 60, 30, 16, top=("ink", 0.2), face=("ink", 0.3), lw=2.0, shadow_len=10)
    g.clear(rect_pts(286, y0 + 36, 14, 12))
    g.pen("qing", 0.7).fill(rect_pts(286, y0 + 36, 14, 12))
    g.ink.rect(286, y0 + 36, 14, 12, lw=1.4)
    block(g, 470, y0 + 12, 30, 18, 12, top=("ink", 0.25), face=("ink", 0.4), lw=1.6, shadow_len=8)
    # 正面：三层窗户（绿漆窗框），楼层线
    fy0 = y0 + roof_d
    floor_h = face_h / 3
    for f in range(1, 3):
        g.ink.line([(x0, fy0 + f * floor_h), (x1, fy0 + f * floor_h)], 1.1, density=0.45)
    door_x = 300
    for f in range(3):
        wy = fy0 + f * floor_h + 8
        x = x0 + 18
        while x < x1 - 30:
            if f == 2 and abs(x + 11 - door_x) < 30:
                x += 40
                continue
            g.pen("ink", 0.32).fill(rect_pts(x, wy, 22, 17))
            g.qing.rect(x, wy, 22, 17, lw=1.8, amp=0.3)
            g.qing.line([(x + 11, wy), (x + 11, wy + 17)], 1.3, amp=0)
            g.qing.line([(x, wy + 6), (x + 22, wy + 6)], 1.3, amp=0)
            x += 40
    # 南门：门洞 + 两级台阶
    dy = fy0 + 2 * floor_h + 4
    g.clear(rect_pts(door_x - 22, dy, 44, floor_h - 4))
    g.pen("ink", 0.55).fill(rect_pts(door_x - 22, dy, 44, floor_h - 4))
    g.ink.rect(door_x - 22, dy, 44, floor_h - 4, lw=2)
    g.ink.line([(door_x, dy), (door_x, dy + floor_h - 4)], 1.2, density=0.6)
    g.ink.rect(door_x - 30, fy0 + face_h, 60, 6, lw=1.6)
    # 门头上一条梅色的标语牌（小面积实地）
    g.clear(rect_pts(door_x - 46, fy0 + 2 * floor_h - 14, 92, 14))
    g.mei.rect(door_x - 46, fy0 + 2 * floor_h - 14, 92, 14, lw=1.4, fill=True)
    from common import _knockout_text
    _knockout_text(g, "mei", "好好学习", door_x, fy0 + 2 * floor_h - 7, 10, False)


def walls(ctx: Ctx):
    g = ctx.g
    top = WALL_BASE - WALL_H - WALL_D

    def wall_seg(x0, x1):
        block(g, x0, top, x1 - x0, WALL_D, WALL_H, top=("ink", 0.32), face=("mei", 0.2), lw=2.2, shadow_len=0)
        g.mei.bricks(x0 + 1, top + WALL_D + 1, x1 - x0 - 2, WALL_H - 2, bw=28, bh=8, lw=1.0, density=0.6)
        ctx.walk.block_rect(x0, WALL_BASE - 12, x1 - x0, 14)

    # 墙的影子落在操场上（往右下一点点）
    shadow(g, rect_pts(10, WALL_BASE, GATE_L - PIL_W - 10, 10), 0.14)
    shadow(g, rect_pts(GATE_R + PIL_W, WALL_BASE, 596 - GATE_R - PIL_W, 10), 0.14)
    wall_seg(8, GATE_L - PIL_W + 4)
    wall_seg(GATE_R + PIL_W - 4, 604)
    # 西墙、东墙：只露出墙头一条
    for wx, y_end in ((2, BLD_Y), (596, 1556)):
        g.clear(rect_pts(wx, top, 10, y_end - top))
        g.pen("ink", 0.32).fill(rect_pts(wx, top, 10, y_end - top))
        g.ink.rect(wx, top, 10, y_end - top, lw=2.0)
        ctx.walk.block_rect(wx - 2, top, 14, y_end - top)
    # 东墙南头的正面
    block(g, 596, 1556, 10, 0, 24, top=None, face=("mei", 0.3), lw=2.0, shadow_len=0)


def gate(ctx: Ctx):
    g, o, walk = ctx.g, ctx.o, ctx.walk
    pt = WALL_BASE + 8 - PIL_D - PIL_H  # 门柱顶面的 y
    for px in (GATE_L - PIL_W, GATE_R):
        # 柱子的上半截高出人行道一点，那一截放到上层（人从柱子后面走过）
        for sheet, clip in ((o, rect_pts(px - 40, pt - 40, PIL_W + 80, 1080 - pt + 40)),
                            (g, rect_pts(px - 40, 1080, PIL_W + 120, 200))):
            with sheet.clip(clip):
                block(sheet, px, pt, PIL_W, PIL_D, PIL_H, top=("ink", 0.3), face=("ink", 0.1), lw=2.4, shadow_len=22)
                sheet.ink.line([(px - 3, pt + PIL_D + 8), (px + PIL_W + 3, pt + PIL_D + 8)], 2.2)
        walk.block_rect(px, WALL_BASE - 16, PIL_W, 24)
    # 竖牌挂在西柱上
    sign(g, GATE_L - PIL_W / 2, pt + PIL_D + 8 + (PIL_H - 8) / 2 - 6, "河畔里小学", color="ink", size=13, vertical=True, pad=5)
    # 两扇铁栅栏门，往里敞着
    for hx, sgn in ((GATE_L, 1), (GATE_R, -1)):
        hy = WALL_BASE - 4
        a = math.radians(122)
        L = 36
        tx, ty = hx + sgn * L * math.cos(a), hy + L * math.sin(a)
        gh = 24
        n = 5
        shadow(g, [(hx, hy), (tx, ty), (tx + 12, ty + 4), (hx + 12, hy + 4)], 0.12)
        for i in range(n + 1):
            t = i / n
            bx, by = hx + (tx - hx) * t, hy + (ty - hy) * t
            g.ink.line([(bx, by), (bx, by - gh)], 1.1 if 0 < i < n else 2.0, amp=0)
        for k in (0, gh * 0.5, gh):
            g.ink.line([(hx, hy - k), (tx, ty - k)], 1.8, amp=0.2)
        walk.block_poly([(hx - 2, hy - 2), (tx - 2, ty - 2), (tx + 2, ty + 2), (hx + 2, hy + 2)])
