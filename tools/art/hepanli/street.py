"""楼下的老街「河畔里」+ 两边的人行道。

可走：y 720~1080，x 0~1900（东头接海河边的步道）。
  北人行道 y 720~760：红砖楼门口、早点铺门口
  马路     y 760~1000：zone alley
  南人行道 y 1000~1080：小学、自行车铺、小花园的门口都开在这里
"""
import math
import random

from common import Ctx, bicycle, circle_pts, ellipse_pts, pole, rect_pts, shadow, spot, stool, tree, wire

X1 = 1900


def draw(ctx: Ctx):
    g, o, walk = ctx.g, ctx.o, ctx.walk
    rnd = random.Random(11)
    walk.add_rect(0, 722, X1, 358)

    # 人行道：方砖
    for y0, y1 in ((720, 760), (1000, 1080)):
        g.pen("ink", 0.07).fill(rect_pts(0, y0, X1, y1 - y0))
        x = 0
        while x < X1:
            g.ink.line([(x, y0), (x, y1)], 1.0, amp=0.3, density=0.35)
            x += 40
        g.ink.line([(0, (y0 + y1) / 2), (X1, (y0 + y1) / 2)], 1.0, amp=0.3, density=0.3)
    # 马路牙子
    g.ink.line([(-10, 760), (X1 + 10, 760)], 3.2)
    g.ink.line([(-10, 766), (X1 + 10, 766)], 1.2, density=0.6)
    g.ink.line([(-10, 1000), (X1 + 10, 1000)], 3.2)
    g.ink.line([(-10, 994), (X1 + 10, 994)], 1.2, density=0.6)
    # 柏油路：很淡的墨网点 + 一些补丁
    g.pen("ink", 0.16).fill(rect_pts(0, 767, X1, 227))
    for _ in range(9):
        px, py = rnd.uniform(40, X1 - 120), rnd.uniform(790, 950)
        pw, ph = rnd.uniform(50, 120), rnd.uniform(20, 40)
        g.pen("ink", 0.22).fill(rect_pts(px, py, pw, ph))
    # 中间的虚线
    x = 20
    while x < X1:
        g.clear(rect_pts(x, 878, 56, 5))
        x += 130
    # 井盖
    for mx in (860, 1580):
        g.clear(ellipse_pts(mx, 930, 22, 14))
        g.ink.ellipse(mx, 930, 22, 14, lw=2.2)
        g.ink.hatch(ellipse_pts(mx, 930, 19, 11), 0, 5, 1.0)

    _extras(ctx)

    # 跳皮筋 / 跳房子：路边的粉笔画（梅色细线，像孩子画的）
    rx, ry = spot("alley_rope")
    hop = [(rx - 150 + i * 46, ry + 40) for i in range(5)]
    for i, (hx, hy) in enumerate(hop):
        g.mei.rect(hx, hy, 42, 42, lw=2.0, amp=1.6)
        g.mei.text(str(i + 1), hx + 21, hy + 21, 22)
    g.mei.arc(rx + 95, ry + 61, 26, -math.pi / 2, math.pi / 2, lw=2.0, amp=1.4)
    g.mei.text("天", rx + 104, ry + 61, 20)
    # 两只小板凳之间的皮筋
    stool(g, rx - 110, ry - 30, "qing")
    stool(g, rx + 110, ry - 30, "mei")
    g.mei.line([(rx - 100, ry - 34), (rx + 100, ry - 34)], 1.6, amp=0.2)
    g.mei.line([(rx - 100, ry - 26), (rx + 100, ry - 26)], 1.6, amp=0.2)
    ctx.anchor("chalk", rx, ry)

    # 北人行道：门口的东西
    for bx in (150, 520):  # 楼门口停的自行车
        bicycle(g, bx, 752, 1 if bx < 300 else -1)
    # 煤球垛
    for i in range(3):
        for j in range(4):
            g.ink.circle(1000 + j * 16 + (i % 2) * 8, 748 - i * 10, 7.5, lw=1.5, fill=True, density=0.75)
    walk.block_rect(990, 722, 72, 32)
    # 绿色信报箱
    g.clear(rect_pts(600, 724, 64, 26))
    g.qing.rect(600, 724, 64, 26, lw=2, fill=True)
    for k in range(4):
        g.ink.line([(606 + k * 15, 732), (617 + k * 15, 732)], 1.6)
    walk.block_rect(598, 722, 68, 30)

    # 南人行道：一排国槐，树冠在上层
    for tx in (90, 700, 1430, 1830):
        tree(ctx, tx, 1046, 66, seed=int(tx))
    # 电线杆 + 电线（全在上层，角色从电线下走过）
    tops = [pole(ctx, px, 1012, 130) for px in (40, 560, 1080, 1620)]
    for (a1, a2), (b1, b2) in zip(tops, tops[1:]):
        wire(o, a2, b1, 30)
        wire(o, (a2[0], a2[1] + 6), (b1[0], b1[1] + 6), 38)
    # 电线上落着的鸟（引擎会让它们偶尔飞走）
    for wx in (300, 340, 1330):
        ctx.anchor("wire_bird", wx, 912)
    # 路灯光圈（晚上引擎会点亮）
    for lx in (560, 1080):
        ctx.anchor("street_lamp", lx, 1000)


def _extras(ctx: Ctx):
    g, o, walk = ctx.g, ctx.o, ctx.walk
    # 路名：像旧地图一样，大字直接印在马路上（墨网点，压在柏油上）
    for i, ch in enumerate("河畔里"):
        g.ink.text(ch, 300 + i * 120, 935, 70, density=0.3)
    g.ink.text("H E P A N L I", 420, 980, 16, density=0.45)

    # 斑马线：早点铺门口过街
    for k in range(7):
        g.clear(rect_pts(1690, 776 + k * 31, 110, 16))
        g.pen("ink", 0.06).fill(rect_pts(1690, 776 + k * 31, 110, 16))

    # 冰棍车（南人行道）：白箱子 + 梅白条纹的阳伞（伞在上层）
    cx, cy = 1210, 1040
    shadow(g, rect_pts(cx - 30, cy - 4, 76, 30), 0.16)
    g.clear(rect_pts(cx - 36, cy - 22, 72, 40))
    g.ink.rect(cx - 36, cy - 22, 72, 26, lw=2.4)
    g.pen("ink", 0.2).fill(rect_pts(cx - 36, cy + 4, 72, 14))
    g.ink.rect(cx - 36, cy + 4, 72, 14, lw=2.4)
    g.qing.text("冰棍", cx, cy - 9, 16)
    for wx in (cx - 24, cx + 24):
        g.ink.circle(wx, cy + 20, 7, lw=2, fill=True, density=0.5)
    walk.block_rect(cx - 40, cy - 26, 80, 50)
    ux, uy, R = cx, cy - 46, 52
    for k in range(8):
        a0, a1 = k * math.tau / 8, (k + 1) * math.tau / 8
        pts = [(ux, uy), (ux + R * math.cos(a0), uy + R * 0.62 * math.sin(a0)), (ux + R * math.cos(a1), uy + R * 0.62 * math.sin(a1))]
        o.clear(pts)
        if k % 2 == 0:
            o.pen("mei", 0.85).fill(pts)
        o.ink.poly(pts, 1.6, amp=0.3)
    o.ink.line([(ux, uy), (ux, cy - 18)], 2.4)
    ctx.anchor("ice_cart", cx, cy)

    # 板儿车（三轮）停在楼边
    tx, ty = 1300, 752
    shadow(g, rect_pts(tx - 50, ty - 6, 110, 12), 0.14)
    g.clear(rect_pts(tx - 50, ty - 34, 70, 26))
    g.pen("ink", 0.14).fill(rect_pts(tx - 50, ty - 34, 70, 26))
    g.ink.rect(tx - 50, ty - 34, 70, 26, lw=2.2)
    g.ink.hatch(rect_pts(tx - 50, ty - 34, 70, 26), 0, 6, 1.0, density=0.6)
    for wx in (tx - 40, tx + 10):
        g.ink.circle(wx, ty - 8, 9, lw=2)
    g.ink.circle(tx + 46, ty - 10, 11, lw=2)
    g.ink.line([(tx + 20, ty - 20), (tx + 46, ty - 10)], 2.4)
    g.ink.line([(tx + 34, ty - 40), (tx + 46, ty - 10)], 2.4)
    g.ink.line([(tx + 26, ty - 42), (tx + 42, ty - 40)], 3)
    # 车上一捆大白菜
    for k in range(4):
        g.pen("qing", 0.5).ellipse(tx - 40 + k * 15, ty - 24, 8, 6, lw=1.4, fill=True)
    walk.block_rect(tx - 54, ty - 36, 116, 34)

    # 趴在树荫里的大黄狗
    dx, dy = 820, 1060
    g.clear(ellipse_pts(dx, dy, 22, 11))
    g.ink.ellipse(dx, dy, 22, 11, lw=2.2)
    g.pen("ink", 0.12).fill(ellipse_pts(dx, dy, 20, 9))
    g.clear(circle_pts(dx + 22, dy - 4, 9, 16))
    g.ink.circle(dx + 22, dy - 4, 9, lw=2.2)
    g.ink.poly([(dx + 16, dy - 11), (dx + 20, dy - 18), (dx + 24, dy - 12)], 1.8, fill=True)
    g.ink.line([(dx - 22, dy + 2), (dx - 34, dy - 4)], 2.4)
    g.ink.line([(dx + 20, dy - 4), (dx + 24, dy - 4)], 1.6)
    ctx.anchor("dog", dx, dy)
    walk.block_circle(dx + 6, dy, 18)

    # 地上的落叶、水洼
    rnd = random.Random(5)
    for _ in range(40):
        lx, ly = rnd.uniform(20, X1 - 20), rnd.uniform(770, 1070)
        if 990 < ly < 1004 or 756 < ly < 770:
            continue
        a = rnd.uniform(0, math.tau)
        g.pen(rnd.choice(["qing", "qing", "mei"]), 0.9).line([(lx, ly), (lx + 6 * math.cos(a), ly + 6 * math.sin(a))], 3.0)
    for px, py in ((560, 820), (1500, 960)):
        g.clear(ellipse_pts(px, py, 34, 12))
        g.pen("qing", 0.18).fill(ellipse_pts(px, py, 34, 12))
        g.qing.arc(px, py, 26, math.pi * 1.1, math.pi * 1.5, lw=1.4)
