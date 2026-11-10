"""修车铺（x 860~1400, y 1080~1500）：一个小院子，修车爷爷的铺子在院子北边、贴着人行道，
朝南开着卷帘门（按约定我们只看得见朝南的正面），门头梅色招牌「修车」，门口一块青色雨棚（上层）。
门里黑洞洞地挂着车圈；门边墙上挂着那把旧二胡。门口一张工作台，玩家站在台子南边 (1120, 1280) 帮爷爷修车。
院子里：倒过来修的车（车轮朝天）、打气筒、一盆水（找漏气）、一摞旧轮胎、等着修的二八车。

可走：铺子西边一条宽过道从南人行道进来 + 整个院子；房子、台子、车、杂物挡住。
锚点：spoke（倒放车的两个车轮，引擎让它转）。
"""
import math
import random

from common import Ctx, _knockout_text, bicycle, ellipse_pts, rect_pts, shadow, sign, spot, stool
from kit_south import block, ground_tex

BX, BY = spot("bike_bench")   # (1120, 1280)
SHOP_X0, SHOP_X1 = 1036, 1368
ROOF_Y, ROOF_D, FACE_H = 1088, 70, 98
BASE = ROOF_Y + ROOF_D + FACE_H   # 1256 墙根
DOOR_X0, DOOR_X1 = 1084, 1224
YARD_X0, YARD_X1, YARD_Y1 = 864, 1384, 1478


def draw(ctx: Ctx):
    g, o, walk = ctx.g, ctx.o, ctx.walk
    rnd = random.Random(1120)

    # ---------- 地面：压实的土院子 ----------
    ground_tex(g, YARD_X0, 1080, YARD_X1 - YARD_X0, YARD_Y1 - 1080, 0.07, seed=21, specks=70)
    # 油渍、车辙
    for ox, oy, rx, ry in ((1150, 1330, 34, 12), (1290, 1380, 22, 8), (950, 1300, 18, 7), (1010, 1430, 26, 9)):
        g.pen("ink", 0.2).fill(ellipse_pts(ox, oy, rx, ry, 18))
    walk.add_rect(YARD_X0, 1078, DOOR_X0 - 48 - YARD_X0, BASE - 1078)   # 西边的过道
    walk.add_rect(YARD_X0, BASE - 4, YARD_X1 - YARD_X0, YARD_Y1 - BASE + 4)

    # 院墙：东边一条墙头，南边一道矮砖墙
    g.clear(rect_pts(YARD_X1, 1084, 12, YARD_Y1 - 1084))
    g.pen("ink", 0.3).fill(rect_pts(YARD_X1, 1084, 12, YARD_Y1 - 1084))
    g.ink.rect(YARD_X1, 1084, 12, YARD_Y1 - 1084, lw=2.0)
    walk.block_rect(YARD_X1 - 2, 1080, 16, YARD_Y1 - 1080)
    block(g, YARD_X0 - 4, YARD_Y1, YARD_X1 - YARD_X0 + 16, 8, 22, top=("ink", 0.3), face=("mei", 0.2), lw=2.0, shadow_len=0)
    g.mei.bricks(YARD_X0 - 3, YARD_Y1 + 9, YARD_X1 - YARD_X0 + 14, 20, bw=28, bh=7, lw=1.0, density=0.55)
    walk.block_rect(YARD_X0 - 4, YARD_Y1 - 6, YARD_X1 - YARD_X0 + 16, 40)

    # ---------- 铺子 ----------
    shop(ctx)

    # ---------- 等着修的车（西边过道里靠着墙） ----------
    bicycle(g, 990, 1150, -1)
    bicycle(g, 996, 1214, 1, color="qing")
    walk.block_rect(950, 1140, 88, 14)
    walk.block_rect(956, 1204, 88, 14)
    # 路边一个旧轮胎当招牌：靠在小板凳上，写着「打气」
    tire_sign(ctx, 900, 1100)

    # ---------- 门口：工作台 ----------
    bench(ctx)

    # ---------- 院子里 ----------
    flipped_bike(ctx, 1222, 1336)
    pump(ctx, 1282, 1330)
    basin(ctx, 1036, 1326)
    stool(g, 1176, 1318, "mei", 10)
    walk.block_rect(1164, 1308, 24, 18)
    tire_pile(ctx, 1336, 1410)
    crate(ctx, 900, 1380)
    bicycle(g, 1060, 1456, 1)
    walk.block_rect(1016, 1444, 90, 14)


def shop(ctx: Ctx):
    g, o, walk = ctx.g, ctx.o, ctx.walk
    x0, x1, w = SHOP_X0, SHOP_X1, SHOP_X1 - SHOP_X0
    fy = ROOF_Y + ROOF_D
    block(g, x0, ROOF_Y, w, ROOF_D, FACE_H, top=("ink", 0.12), face=("ink", 0.06), lw=2.8, shadow_len=26)
    walk.block_rect(x0 - 2, 1080, w + 4, BASE - 1080 + 2)
    # 石棉瓦屋顶：一道道瓦楞 + 压着的砖头和一个旧轮胎
    k = x0 + 8
    while k < x1 - 4:
        g.ink.line([(k, ROOF_Y + 4), (k, fy - 4)], 1.0, amp=0.3, density=0.45)
        k += 9
    for bx, by in ((1090, 1100), (1250, 1130), (1320, 1104)):
        g.clear(rect_pts(bx, by, 16, 8))
        g.pen("mei", 0.5).fill(rect_pts(bx, by, 16, 8))
        g.ink.rect(bx, by, 16, 8, lw=1.3)
    g.clear(ellipse_pts(1170, 1118, 17, 11))
    g.ink.ellipse(1170, 1118, 17, 11, lw=4.5)
    g.pen("ink", 0.12).fill(ellipse_pts(1170, 1118, 9, 5))
    # 烟筒
    g.ink.rect(1300, 1124, 9, 22, lw=1.6, fill=True, density=0.85)
    # 正面：白灰墙，淡淡的砖缝
    g.ink.bricks(x0 + 2, fy + 2, w - 4, FACE_H - 4, bw=30, bh=9, lw=0.8, density=0.18)
    # 卷帘门：卷起来的卷筒 + 黑洞洞的屋里
    dy0 = fy + 44
    g.clear(rect_pts(DOOR_X0, dy0, DOOR_X1 - DOOR_X0, BASE - dy0))
    g.pen("ink", 0.5).fill(rect_pts(DOOR_X0, dy0, DOOR_X1 - DOOR_X0, BASE - dy0))
    g.ink.rect(DOOR_X0, dy0, DOOR_X1 - DOOR_X0, BASE - dy0, lw=2.4)
    g.clear(rect_pts(DOOR_X0 - 6, dy0 - 9, DOOR_X1 - DOOR_X0 + 12, 9))
    g.pen("ink", 0.4).fill(rect_pts(DOOR_X0 - 6, dy0 - 9, DOOR_X1 - DOOR_X0 + 12, 9))
    g.ink.rect(DOOR_X0 - 6, dy0 - 9, DOOR_X1 - DOOR_X0 + 12, 9, lw=1.8)
    for k in range(4):
        g.ink.line([(DOOR_X0 - 4, dy0 - 7 + k * 2.2), (DOOR_X1 + 4, dy0 - 7 + k * 2.2)], 0.6, amp=0, density=0.6)
    # 屋里挂着的车圈（挖白的细圈，像暗处反光）
    for cx, cy, r in ((1112, 1226, 13), (1140, 1222, 11), (1196, 1228, 14)):
        g.clear([(cx + r * math.cos(a * math.tau / 40), cy + r * math.sin(a * math.tau / 40)) for a in range(40)])
        g.pen("ink", 0.5).fill(ellipse_pts(cx, cy, r - 1.6, r - 1.6, 40))
        g.clear(rect_pts(cx - 0.7, cy - r, 1.4, 2 * r))
    g.clear(rect_pts(1100, 1205, 110, 1.6))  # 挂车圈的铁丝
    # 招牌「修车」（门头）
    sign(g, (DOOR_X0 + DOOR_X1) / 2, fy + 20, "修车", color="mei", size=24)
    # 门边墙上挂着的旧二胡
    erhu(g, 1054, 1184)
    # 门东边墙上：车圈、内胎（一条红的）
    for cx, cy, r in ((1252, 1200, 15), (1288, 1206, 13)):
        g.ink.dot(cx, cy - r - 3, 1.6)
        g.ink.circle(cx, cy, r, lw=2.0)
        g.ink.circle(cx, cy, 2, lw=1.2)
        for a in range(0, 360, 45):
            t = math.radians(a)
            g.ink.line([(cx, cy), (cx + r * math.cos(t), cy + r * math.sin(t))], 0.7, amp=0, density=0.5)
    g.ink.dot(1325, 1182, 1.6)
    g.ink.line([(1325, 1182), (1314, 1196), (1312, 1220), (1325, 1236), (1338, 1220), (1336, 1196), (1325, 1182)], 3.2, amp=0.6)
    g.ink.dot(1350, 1186, 1.6)
    g.mei.line([(1350, 1186), (1342, 1200), (1341, 1222), (1350, 1232), (1359, 1222), (1358, 1200), (1350, 1186)], 3.0, amp=0.6)
    # 小黑板「补胎」（粉笔字）
    g.clear(rect_pts(1240, 1228, 34, 20))
    g.ink.rect(1240, 1228, 34, 20, lw=1.6, fill=True, density=0.85)
    _knockout_text(g, "ink", "补胎", 1257, 1238, 11, False)

    # 雨棚（上层）：青色帆布，一道一道的条纹，前沿一排小波浪
    ax0, ax1, ay0, ay1 = DOOR_X0 - 14, DOOR_X1 + 14, fy + 38, fy + 58
    shadow(g, [(ax0 + 20, BASE + 2), (ax1 + 24, BASE + 2), (ax1 + 30, BASE + 22), (ax0 + 26, BASE + 22)], 0.13)
    awn = [(ax0 + 6, ay0), (ax1 - 6, ay0), (ax1, ay1), (ax0, ay1)]
    o.clear(awn)
    o.pen("qing", 0.18).fill(awn)
    n = 10
    for i in range(0, n, 2):
        t0, t1 = i / n, (i + 1) / n
        o.pen("qing", 0.7).fill([(ax0 + 6 + (ax1 - ax0 - 12) * t0, ay0), (ax0 + 6 + (ax1 - ax0 - 12) * t1, ay0),
                                  (ax0 + (ax1 - ax0) * t1, ay1), (ax0 + (ax1 - ax0) * t0, ay1)])
    o.ink.poly(awn, 2.2, amp=0.5)
    sc = (ax1 - ax0) / 12
    for i in range(12):
        o.ink.arc(ax0 + sc * (i + 0.5), ay1, sc / 2, 0, math.pi, lw=1.2, amp=0.2)
    # 两根撑杆
    for px in (ax0 + 2, ax1 - 2):
        o.ink.line([(px, ay1), (px, BASE + 8)], 1.8, amp=0)


def erhu(g, x, y):
    """挂在墙上的二胡：琴杆、两个弦轴、琴筒，旁边斜挂着弓。"""
    g.ink.dot(x, y - 6, 1.5)
    g.ink.line([(x, y - 4), (x, y + 44)], 2.0, amp=0.2)
    g.ink.line([(x - 4, y + 2), (x + 4, y + 2)], 1.6, amp=0)
    g.ink.line([(x - 4, y + 8), (x + 4, y + 8)], 1.6, amp=0)
    g.clear(rect_pts(x - 6, y + 42, 12, 11))
    g.pen("ink", 0.5).fill(rect_pts(x - 6, y + 42, 12, 11))
    g.ink.rect(x - 6, y + 42, 12, 11, lw=1.6)
    g.mei.line([(x + 1, y + 30), (x + 3, y + 40), (x + 2, y + 50)], 1.6, amp=0.3)   # 红穗子
    g.ink.line([(x - 12, y + 2), (x + 12, y + 56)], 1.0, amp=0.2, density=0.8)       # 弓


def tire_sign(ctx, x, y):
    g = ctx.g
    shadow(g, ellipse_pts(x + 8, y + 22, 26, 6), 0.14)
    g.clear(ellipse_pts(x, y, 20, 20, 40))
    g.ink.circle(x, y, 20, lw=6)
    g.ink.circle(x, y, 11, lw=1.2, density=0.6)
    g.ink.text("打气", x, y + 34, 13)
    ctx.walk.block_rect(x - 22, y - 4, 44, 26)


def bench(ctx: Ctx):
    g = ctx.g
    tx, ty, tw, td, th = BX - 46, BASE - 10, 92, 14, 11
    block(g, tx, ty, tw, td, th, top=("ink", 0.2), face=("ink", 0.4), lw=2.2, shadow_len=12)
    for k in (1, 2):
        g.ink.line([(tx + 2, ty + k * td / 3), (tx + tw - 2, ty + k * td / 3)], 0.8, amp=0, density=0.5)
    # 台上：扳手、一个小铁盒、一卷胶皮
    g.ink.line([(tx + 12, ty + 4), (tx + 34, ty + 9)], 2.2, amp=0)
    g.ink.circle(tx + 10, ty + 3.5, 3, lw=1.6)
    g.clear(rect_pts(tx + 50, ty + 1, 16, 10))
    g.qing.rect(tx + 50, ty + 1, 16, 10, lw=1.4, fill=True)
    g.ink.rect(tx + 50, ty + 1, 16, 10, lw=1.4)
    g.ink.circle(tx + 78, ty + 6, 5, lw=2.2)
    ctx.walk.block_rect(tx - 2, ty, tw + 4, td + th + 2)


def flipped_bike(ctx: Ctx, x, y):
    """倒过来修的车：车座和车把着地，两个轮子朝天。"""
    g = ctx.g
    r = 17
    bx, fx = x - 28, x + 28
    wy = y - 31
    shadow(g, ellipse_pts(x + 10, y + 3, 52, 7), 0.15)
    seat, bar, crank = (x - 10, y - 4), (x + 18, y - 2), (x, wy)
    g.ink.line([(bx, wy), seat, crank, (bx, wy)], 2.6)
    g.ink.line([seat, bar, crank], 2.6)
    g.ink.line([bar, (fx, wy)], 2.6)
    g.ink.line([(seat[0] - 9, y), (seat[0] + 7, y)], 4)              # 车座着地
    g.ink.line([(bar[0] - 4, y), (bar[0] + 10, y + 1)], 2.6)         # 车把着地
    g.ink.circle(crank[0], crank[1], 5, lw=1.8)
    for wx in (bx, fx):
        g.ink.circle(wx, wy, r, lw=2.4)
        g.ink.dot(wx, wy, 2.2)
        ctx.anchor("spoke", wx, wy, r=r)
    # 前轮的外胎扒下来一截（正在补胎）
    g.ink.arc(fx, wy, r + 4, -2.4, -1.2, lw=3.2, amp=0.6)
    ctx.walk.block_rect(x - 48, y - 10, 96, 16)


def pump(ctx: Ctx, x, y):
    g = ctx.g
    shadow(g, [(x, y), (x + 22, y + 7), (x + 26, y + 9), (x + 4, y + 2)], 0.15)
    g.ink.line([(x - 8, y), (x + 8, y)], 2.4, amp=0)
    g.clear(rect_pts(x - 3, y - 36, 6, 36))
    g.pen("qing", 0.7).fill(rect_pts(x - 3, y - 36, 6, 36))
    g.ink.rect(x - 3, y - 36, 6, 36, lw=1.6)
    g.ink.line([(x, y - 36), (x, y - 44)], 1.4, amp=0)
    g.ink.line([(x - 9, y - 44), (x + 9, y - 44)], 2.6, amp=0)
    # 气管连到倒放的车轮
    g.ink.line([(x - 2, y - 4), (x - 18, y - 2), (x - 26, y - 12), (x - 34, y - 26)], 1.4, amp=0.6)
    ctx.walk.block_rect(x - 10, y - 6, 20, 10)


def basin(ctx: Ctx, x, y):
    """搪瓷脸盆，一盆水，内胎按在水里找漏气（冒几个泡）。"""
    g = ctx.g
    shadow(g, ellipse_pts(x + 8, y + 6, 26, 11), 0.15)
    g.clear(ellipse_pts(x, y, 25, 12, 40))
    g.ink.ellipse(x, y, 25, 12, lw=2.2)
    g.mei.ellipse(x, y, 22.5, 10, lw=1.6)
    g.pen("qing", 0.45).fill(ellipse_pts(x, y + 1, 20, 8, 40))
    g.ink.arc(x - 3, y + 1, 13, math.pi * 1.05, math.pi * 1.95, lw=3.0, amp=0.3)
    g.ink.arc(x - 3, y + 1, 13, math.pi * 0.05, math.pi * 0.45, lw=3.0, amp=0.3)
    for bx, by, br in ((x + 8, y - 2, 2.2), (x + 12, y - 5, 1.5), (x + 5, y - 6, 1.2)):
        g.ink.circle(bx, by, br, lw=1.0)
    ctx.walk.block_rect(x - 26, y - 10, 52, 22)


def tire_pile(ctx: Ctx, x, y):
    g = ctx.g
    shadow(g, ellipse_pts(x + 10, y + 8, 30, 12), 0.16)
    for k in range(4):
        cy = y - k * 7
        g.clear(ellipse_pts(x, cy, 24, 11, 40))
        g.pen("ink", 0.5).fill(ellipse_pts(x, cy, 24, 11, 40))
        g.ink.ellipse(x, cy, 24, 11, lw=2.0)
    g.clear(ellipse_pts(x, y - 21, 12, 5, 30))
    g.pen("ink", 0.14).fill(ellipse_pts(x, y - 21, 12, 5, 30))
    g.ink.ellipse(x, y - 21, 12, 5, lw=1.4)
    ctx.walk.block_rect(x - 26, y - 14, 52, 26)


def crate(ctx: Ctx, x, y):
    """一个木箱子，里面堆着旧零件，旁边靠着两个车圈。"""
    g = ctx.g
    block(g, x, y, 44, 22, 18, top=("ink", 0.1), face=("ink", 0.24), lw=2.0, shadow_len=12)
    g.ink.line([(x + 2, y + 31), (x + 42, y + 31)], 1.0, amp=0, density=0.5)
    for cx, cy, r in ((x + 12, y + 10, 5), (x + 24, y + 12, 4), (x + 33, y + 8, 5)):
        g.ink.circle(cx, cy, r, lw=1.4)
    for k, cx in enumerate((x + 58, x + 66)):
        g.ink.ellipse(cx, y + 24, 6, 18, lw=2.0)
    ctx.walk.block_rect(x - 2, y + 14, 76, 30)
