"""小花园 + 南边的街坊 + 地图南边收边。

  x 620~860,  y 1080~1500  街心小花园（可走）：一圈矮冬青，北边留个口；大国槐，
                           树下石桌石凳（桌上一盘没下完的象棋），南头一根晾衣绳（上层，锚点 laundry）。
  x 1400~1880, y 1080~1600  老平房，一排一排的灰瓦屋顶（不可走）。第一排西头是小卖部：
                           朝北冲着人行道，门口一块梅色条纹雨棚（上层）、招牌、人行道上一台冰柜。
  y 1500~1600              地图最南边：花园、车铺南面再一排平房屋顶；小学南面一道铁栏杆。
东边 x > 1880 是海河，不画。

可走：花园（北边冬青的缺口接南人行道）。
"""
import math
import random

from common import Ctx, circle_pts, ellipse_pts, rect_pts, shadow, sign, tree
from kit_south import block, grass, ground_tex, hedge, hedge_v

EAST = 1878


def draw(ctx: Ctx):
    garden(ctx)
    houses(ctx)
    south_edge(ctx)
    shop(ctx)


# ----------------------------------------------------------------------
# 小花园
# ----------------------------------------------------------------------

def garden(ctx: Ctx):
    g, o, walk = ctx.g, ctx.o, ctx.walk
    x0, x1, y0, y1 = 622, 858, 1080, 1500
    ground_tex(g, x0, y0, x1 - x0, y1 - y0, 0.05, seed=31, specks=40)
    walk.add_rect(x0 + 10, y0 - 2, x1 - x0 - 20, y1 - y0 - 24)

    # 甬路：从北边的口子进来，一条砖铺的小路弯到石桌那儿
    path = []
    for i in range(11):
        t = i / 10
        path.append((757 + 14 * math.sin(t * 2.6), 1094 + t * 160))
    for (ax, ay), (bx, by) in zip(path, path[1:]):
        g.clear(rect_pts(min(ax, bx) - 17, ay, abs(bx - ax) + 34, by - ay + 1))
        g.pen("ink", 0.09).fill(rect_pts(min(ax, bx) - 17, ay, abs(bx - ax) + 34, by - ay + 1))
    for (ax, ay), (bx, by) in zip(path, path[1:]):
        for k in range(3):
            yy = ay + k * (by - ay) / 3
            xx = ax + (bx - ax) * k / 3
            g.ink.line([(xx - 17, yy), (xx + 17, yy)], 0.9, amp=0, density=0.4)
    g.ink.line([(p[0] - 17, p[1]) for p in path], 1.4, amp=0.4, density=0.7)
    g.ink.line([(p[0] + 17, p[1]) for p in path], 1.4, amp=0.4, density=0.7)
    # 石桌下一块圆形的砖地
    cx, cy = 770, 1300
    g.clear(circle_pts(cx, cy, 58, 60))
    g.pen("ink", 0.08).fill(circle_pts(cx, cy, 58, 60))
    g.ink.circle(cx, cy, 58, lw=1.6, density=0.8)

    # 草
    grass(g, (640, 1250, 70, 150), n=22, seed=33)
    grass(g, (796, 1130, 40, 100), n=10, seed=34)
    grass(g, (650, 1420, 190, 50), n=14, seed=35)

    # 一圈矮冬青（北边留口子）
    hedge(ctx, x0 + 6, 1088, 98, seed=41)
    hedge(ctx, 792, 1088, x1 - 6 - 792, seed=42)
    hedge_v(ctx, x0 + 4, 1114, 360, seed=43)
    hedge_v(ctx, x1 - 20, 1114, 360, seed=44)
    hedge(ctx, x0 + 6, 1474, x1 - x0 - 12, seed=45)

    # 石桌石凳，下了一半的象棋
    stone_table(ctx, cx, cy)

    # 大国槐（树冠在上层，石桌在它的影子边上）
    tree(ctx, 676, 1214, 80, seed=690)

    # 晾衣绳：两根铁杆，一条床单、一件毛衣、一双袜子（上层，会被风吹——锚点 laundry）
    p0, p1 = (660, 1458), (834, 1458)
    for px, py in (p0, p1):
        shadow(g, [(px, py), (px + 40, py + 12), (px + 43, py + 14), (px + 3, py + 2)], 0.13)
        g.ink.circle(px, py, 3, lw=1.4, fill=True)
        o.ink.line([(px, py), (px, py - 64)], 2.4, amp=0)
        walk.block_circle(px, py, 6)
    ly = p0[1] - 62
    pts = [(p0[0] + (p1[0] - p0[0]) * t / 20, ly + 10 * 4 * (t / 20) * (1 - t / 20)) for t in range(21)]
    o.ink.line(pts, 1.2, amp=0)

    def sag(x):
        t = (x - p0[0]) / (p1[0] - p0[0])
        return ly + 40 * t * (1 - t)

    # 床单（青）
    sx0, sx1 = 682, 742
    sheet_pts = [(sx0, sag(sx0)), (sx1, sag(sx1)), (sx1 + 2, sag(sx1) + 40), (sx0 + 2, sag(sx0) + 42)]
    o.clear(sheet_pts)
    o.pen("qing", 0.4).fill(sheet_pts)
    o.ink.poly(sheet_pts, 1.6, amp=0.8)
    for k in range(1, 4):
        o.qing.line([(sx0 + k * 15, sag(sx0 + k * 15) + 2), (sx0 + k * 15 + 1, sag(sx0 + k * 15) + 38)], 1.0, amp=0.6, density=0.8)
    # 毛衣（梅）
    mx = 770
    my = sag(mx)
    sweater = [(mx - 13, my), (mx + 13, my), (mx + 22, my + 12), (mx + 15, my + 15), (mx + 11, my + 8),
               (mx + 11, my + 30), (mx - 11, my + 30), (mx - 11, my + 8), (mx - 15, my + 15), (mx - 22, my + 12)]
    o.clear(sweater)
    o.pen("mei", 0.7).fill(sweater)
    o.ink.poly(sweater, 1.5, amp=0.4)
    # 袜子
    for sxk in (800, 810):
        sy = sag(sxk)
        o.ink.line([(sxk, sy), (sxk, sy + 12), (sxk + 5, sy + 15)], 3.0, amp=0)
    # 和楼顶床单同一个格式：x 中点、y 上沿、w 宽、h 高
    ctx.anchor("laundry", (sx0 + sx1) / 2, sag((sx0 + sx1) / 2), w=sx1 - sx0, h=42)
    ctx.anchor("laundry", mx, my, w=44, h=30)


def stone_table(ctx: Ctx, cx, cy):
    g = ctx.g

    def drum(x, y, r, h, top=0.1, side=0.28, lw=2.2):
        """石鼓 / 石桌：顶面一个圆，正面露出一截圆柱。"""
        shadow(g, ellipse_pts(x + r * 0.5, y + h + r * 0.35, r * 1.05, r * 0.6), 0.16)
        top_pts = circle_pts(x, y, r, 40)
        # 外轮廓：上半圆 + 往下挪 h 的下半圆
        sil = [(x + r * math.cos(a * math.pi / 20), y - r * math.sin(a * math.pi / 20)) for a in range(21)]
        sil += [(x - r * math.cos(a * math.pi / 20), y + h + r * math.sin(a * math.pi / 20)) for a in range(21)]
        g.clear(sil)
        g.pen("ink", side).fill(sil)
        g.clear(top_pts)
        g.pen("ink", top).fill(top_pts)
        g.ink.poly(sil, lw, amp=0.4)
        g.ink.poly(top_pts, lw * 0.8, amp=0.4)

    seats = [(cx, cy - 44), (cx - 46, cy - 2), (cx + 46, cy - 2), (cx, cy + 36)]
    drum(*seats[0], 9, 8)
    drum(cx, cy - 6, 30, 16, top=0.08, side=0.3, lw=2.6)
    # 棋盘：九路十行，中间一道“楚河”
    bw, bh = 32, 36
    bx0, by0 = cx - bw / 2, cy - 6 - bh / 2
    for i in range(9):
        x = bx0 + i * bw / 8
        g.ink.line([(x, by0), (x, by0 + bh * 4 / 9)], 0.7, amp=0, density=0.7)
        g.ink.line([(x, by0 + bh * 5 / 9), (x, by0 + bh)], 0.7, amp=0, density=0.7)
    for j in range(10):
        y = by0 + j * bh / 9
        g.ink.line([(bx0, y), (bx0 + bw, y)], 0.7, amp=0, density=0.7)
    g.ink.line([(bx0, by0), (bx0, by0 + bh)], 0.7, amp=0, density=0.7)
    g.ink.line([(bx0 + bw, by0), (bx0 + bw, by0 + bh)], 0.7, amp=0, density=0.7)
    rnd = random.Random(64)
    for k in range(13):
        i, j = rnd.randint(0, 8), rnd.randint(0, 9)
        col = "mei" if j >= 5 else "ink"
        if rnd.random() < 0.2:
            col = "ink" if col == "mei" else "mei"
        px, py = bx0 + i * bw / 8, by0 + j * bh / 9
        g.clear(circle_pts(px, py, 2.6, 12))
        g.pen(col).dot(px, py, 2.4)
    for sx, sy in seats[1:]:
        drum(sx, sy, 9, 8)
    ctx.walk.block_circle(cx, cy + 4, 32)
    for sx, sy in seats:
        ctx.walk.block_circle(sx, sy + 6, 9)
    ctx.anchor("chess", cx, cy - 6)


# ----------------------------------------------------------------------
# 南边的老平房
# ----------------------------------------------------------------------

ROWS = [  # (y 顶, 进深, 正面高)
    (1090, 74, 28),
    (1224, 78, 28),
    (1360, 78, 28),
    (1500, 78, 28),
]


def house(ctx: Ctx, x, y, w, d, h, rnd, door=True, kind=None):
    """一间平房。kind: tile 灰瓦两坡顶（北坡亮、南坡暗，屋脊东西走向）/ flat 油毡平顶（斜排线 + 女儿墙）。
    正面一门一窗，有的门边贴着春联（两条梅色）。"""
    g = ctx.g
    kind = kind or ("tile" if rnd.random() < 0.68 else "flat")
    block(g, x, y, w, d, h, top=None, face=("ink", 0.06), lw=2.4, shadow_len=14)
    if kind == "tile":
        rid = y + d * 0.42
        g.pen("ink", 0.08).fill(rect_pts(x, y, w, rid - y))
        g.pen("ink", 0.2).fill(rect_pts(x, rid, w, y + d - rid))
        k = x + 6
        while k < x + w - 3:
            g.ink.line([(k, y + 3), (k + 1, rid - 2)], 0.9, amp=0.3, density=0.35)
            g.ink.line([(k, rid + 2), (k - 1, y + d - 3)], 0.9, amp=0.3, density=0.45)
            k += 7
        g.ink.line([(x, rid), (x + w, rid)], 2.6, amp=0.4)
    else:
        g.pen("ink", 0.14).fill(rect_pts(x, y, w, d))
        g.ink.hatch(rect_pts(x + 5, y + 5, w - 10, d - 10), -35, 11, 0.9, density=0.35)
        g.ink.rect(x + 5, y + 5, w - 10, d - 10, lw=1.2, density=0.6)
    g.ink.line([(x - 2, y + d), (x + w + 2, y + d)], 2.6, amp=0.4)
    if h > 0 and door:
        fy = y + d
        dx = x + rnd.uniform(0.12, 0.3) * w
        g.pen("ink", 0.55).fill(rect_pts(dx, fy + 4, 14, h - 4))
        g.ink.rect(dx, fy + 4, 14, h - 4, lw=1.6)
        if rnd.random() < 0.4:
            for cx in (dx - 5, dx + 17):
                g.mei.rect(cx, fy + 5, 3, h - 7, lw=0.8, fill=True, amp=0)
        wx = dx + 32 if dx + 58 < x + w else x + 8
        nwin = 2 if wx + 60 < x + w - 4 and rnd.random() < 0.5 else 1
        for i in range(nwin):
            if wx + 22 < x + w - 4:
                g.pen("ink", 0.3).fill(rect_pts(wx, fy + 6, 22, 13))
                g.qing.rect(wx, fy + 6, 22, 13, lw=1.6, amp=0.3)
                g.qing.line([(wx + 11, fy + 6), (wx + 11, fy + 19)], 1.1, amp=0)
            wx += 34


def roof_things(ctx: Ctx, x, y, kind, rnd):
    """屋顶上的零碎：冬储大白菜、煤球、一截烟筒、压瓦的砖。"""
    g = ctx.g
    if kind == "cabbage":
        for k in range(6):
            cx, cy = x + k * 13 + rnd.uniform(-1, 1), y + rnd.uniform(-1, 1)
            g.clear(ellipse_pts(cx, cy, 7, 5, 16))
            g.pen("qing", 0.55).fill(ellipse_pts(cx, cy, 7, 5, 16))
            g.ink.ellipse(cx, cy, 7, 5, lw=1.2)
            g.ink.line([(cx - 3, cy), (cx + 3, cy)], 0.8, amp=0)
    elif kind == "chimney":
        block(g, x, y, 12, 8, 14, top=("ink", 0.7), face=("ink", 0.3), lw=1.6, shadow_len=8)
    elif kind == "bricks":
        for k in range(3):
            g.clear(rect_pts(x + k * 22, y + (k % 2) * 6, 14, 7))
            g.pen("mei", 0.45).fill(rect_pts(x + k * 22, y + (k % 2) * 6, 14, 7))
            g.ink.rect(x + k * 22, y + (k % 2) * 6, 14, 7, lw=1.1)
    elif kind == "pots":
        for k in range(3):
            px = x + k * 14
            g.ink.circle(px, y, 4.5, lw=1.4)
            g.pen("qing", 0.8).dot(px, y - 2, 3.4)


def house_row(ctx: Ctx, x0, x1, y, d, h, seed, widths=None):
    rnd = random.Random(seed)
    x = x0
    i = 0
    while x < x1 - 30:
        w = widths[i] if widths and i < len(widths) else rnd.choice((84, 96, 108, 120))
        if w < 0:          # 负数 = 留一块空院子
            x += -w
            i += 1
            continue
        w = min(w, x1 - x)
        if x1 - (x + w) < 50:
            w = x1 - x
        house(ctx, x, y, w, d, h, rnd)
        x += w
        i += 1


def houses(ctx: Ctx):
    g = ctx.g
    x0 = 1404
    # 胡同（不可走，只画地）
    ground_tex(g, x0, 1080, EAST - x0, 520, 0.08, seed=51, specks=60)
    g.ink.line([(x0, 1081), (EAST, 1081)], 2.2)
    # 第一排：西头留给小卖部（shop() 里画）
    house_row(ctx, 1556, EAST, *ROWS[0], seed=52, widths=[96, 112, 116])
    house_row(ctx, x0, EAST, *ROWS[1], seed=53, widths=[96, 78, -78, 120, 96])
    house_row(ctx, x0, EAST, *ROWS[2], seed=54, widths=[120, 96, 108])
    rnd = random.Random(55)
    roof_things(ctx, 1676, 1250, "cabbage", rnd)
    roof_things(ctx, 1790, 1100, "chimney", rnd)
    roof_things(ctx, 1460, 1236, "chimney", rnd)
    roof_things(ctx, 1700, 1376, "bricks", rnd)
    roof_things(ctx, 1830, 1260, "chimney", rnd)
    # 胡同里门口的花盆、一辆靠墙的车
    roof_things(ctx, 1450, 1214, "pots", rnd)
    roof_things(ctx, 1700, 1350, "pots", rnd)
    from common import bicycle
    bicycle(g, 1800, 1218, -1, scale=0.85)
    # 胡同里一棵老槐树，树冠盖住半个屋顶
    g.pen("ink", 0.05).fill(rect_pts(1578, ROWS[1][0], 78, ROWS[1][1] + ROWS[1][2]))
    tree(ctx, 1617, 1318, 60, seed=1612)
    # 电视天线（上层，高高地支在屋顶上）
    for ax, ay in ((1520, 1268), (1740, 1124)):
        ctx.o.ink.line([(ax, ay), (ax, ay - 58)], 1.6, amp=0)
        for k in range(4):
            yy = ay - 58 + k * 8
            ctx.o.ink.line([(ax - 12 + k * 2, yy), (ax + 12 - k * 2, yy)], 1.2, amp=0)
        ctx.g.ink.dot(ax, ay, 2)


def shop(ctx: Ctx):
    """小卖部：第一排西头的一间，朝北冲着人行道开窗。"""
    g, o, walk = ctx.g, ctx.o, ctx.walk
    x, y, d, h = 1474, ROWS[0][0], ROWS[0][1], ROWS[0][2]
    w = 1556 - x
    rnd = random.Random(57)
    # 西头那一小间（树下，堆杂物的小棚）
    block(g, 1404, y + 10, 70, d - 10, h, top=("ink", 0.14), face=("ink", 0.08), lw=2.2, shadow_len=10)
    g.ink.hatch(rect_pts(1404, y + 10, 70, d - 10), -35, 9, 1.0, density=0.4)
    house(ctx, x, y, w, d, h, rnd)
    # 招牌立在屋檐上（冲北）
    sign(g, x + w / 2, y + 16, "小卖部", color="qing", size=17, pad=7)
    # 雨棚（上层）：梅白条纹，从北墙伸到人行道上
    ax0, ax1, ay0, ay1 = x - 4, x + w + 4, y + 2, y - 28
    awn = [(ax0 + 6, ay0), (ax1 - 6, ay0), (ax1, ay1), (ax0, ay1)]
    o.clear(awn)
    n = 8
    for i in range(n):
        t0, t1 = i / n, (i + 1) / n
        pts = [(ax0 + 6 + (ax1 - ax0 - 12) * t0, ay0), (ax0 + 6 + (ax1 - ax0 - 12) * t1, ay0),
               (ax0 + (ax1 - ax0) * t1, ay1), (ax0 + (ax1 - ax0) * t0, ay1)]
        if i % 2 == 0:
            o.pen("mei", 0.85).fill(pts)
    o.ink.poly(awn, 2.0, amp=0.4)
    sc = (ax1 - ax0) / 8
    for i in range(8):
        o.ink.arc(ax0 + sc * (i + 0.5), ay1, sc / 2, math.pi, math.tau, lw=1.4, amp=0.2)
    # 冰柜（人行道上）
    fx, fy, fw, fd, fh = x + 8, 1030, 56, 22, 12
    block(g, fx, fy, fw, fd, fh, top=None, face=("ink", 0.2), lw=2.2, shadow_len=10)
    g.pen("qing", 0.22).fill(rect_pts(fx + 3, fy + 3, fw / 2 - 4, fd - 6))
    g.pen("qing", 0.38).fill(rect_pts(fx + fw / 2 + 1, fy + 3, fw / 2 - 4, fd - 6))
    g.ink.line([(fx + fw / 2, fy + 2), (fx + fw / 2, fy + fd - 2)], 1.4, amp=0)
    g.clear(rect_pts(fx + 8, fy + 6, 6, 2))
    g.clear(rect_pts(fx + 36, fy + 8, 8, 2))
    g.mei.text("冷饮", fx + fw / 2, fy + fd + fh / 2, 9)
    walk.block_rect(fx - 2, fy - 2, fw + 4, fd + fh + 4)
    # 一箱汽水瓶
    bx, by = fx + fw + 8, 1046
    block(g, bx, by, 24, 16, 8, top=("ink", 0.12), face=("ink", 0.3), lw=1.6, shadow_len=6)
    for i in range(4):
        for j in range(3):
            g.qing.circle(bx + 4 + i * 5.3, by + 3 + j * 5, 1.8, lw=1.0)
    walk.block_rect(bx - 2, by - 2, 28, 28)


# ----------------------------------------------------------------------
# 南边收边
# ----------------------------------------------------------------------

def south_edge(ctx: Ctx):
    g = ctx.g
    # 花园、车铺南面：再一排平房（一直接到东边那几排）
    ground_tex(g, 600, 1500, 1404 - 600, 100, 0.08, seed=61)
    house_row(ctx, 612, EAST, *ROWS[3], seed=62, widths=[120, 108, 96, 120, 84, 108, 120, 96, 108, 120, 96, 84])
    roof_things(ctx, 980, 1514, "cabbage", random.Random(63))
    roof_things(ctx, 1280, 1520, "chimney", random.Random(64))
    roof_things(ctx, 760, 1516, "bricks", random.Random(65))
    # 小学南面：一条草地 + 一道铁栏杆
    y0 = 1558
    ground_tex(g, 0, y0, 606, 1600 - y0, 0.05, seed=66)
    grass(g, (0, y0 + 4, 600, 36), n=40, seed=67)
    ry = 1592
    g.ink.line([(0, ry), (604, ry)], 2.0, amp=0.4)
    g.ink.line([(0, ry - 22), (604, ry - 22)], 1.6, amp=0.4)
    x = 4
    while x < 604:
        g.ink.line([(x, ry), (x, ry - 26)], 1.2, amp=0)
        g.ink.dot(x, ry - 27, 1.4)
        x += 10
    shadow(g, rect_pts(0, ry, 606, 6), 0.14)
