"""海河边：沿河步道、护栏、海河水面、一座老钢桁架铁桥。

范围：x 1880~2400，y 0~1600。
  步道   x 1880~2210（方石板；西边一溜冬青，柳树、长椅、路灯靠河这边）
  护栏   x≈2210（石头压顶 + 铁栏杆）
  水面   x 2224~2400（青网点 + 手画水纹，几处反光留白，一条小船）
  铁桥   桥面 y 636~704，从护栏往东伸出画面；桥面在地面层，钢桁架在上层
  观景台 river_bank (2140, 820) 东边：护栏开口，三级台阶下到一个半圆的亲水平台
  北头   y 0~150：草坪；水面尽头是对岸一排楼的剪影（晚上点灯）
  南头   y 1490~1600：草坪
可走：步道 + 台阶/平台 + 桥面；水面、护栏、冬青不可走。
"""
import math
import random

from common import Ctx, circle_pts, ellipse_pts, rect_pts, shadow, spot, tree

WX0 = 1880            # 步道西沿（接早点铺街角、马路）
RAIL = 2178           # 护栏
WATER0 = 2192         # 水面西沿（河堤）
XR = 2412             # 画到画面外一点
Y0, Y1 = 150, 1490    # 步道南北两头（再外面是草坪）
DECK0, DECK1 = 624, 716   # 桥面
PCX, PCY, PRX, PRY = 2190, 824, 84, 58   # 亲水平台（半椭圆）


def draw(ctx: Ctx):
    g, walk = ctx.g, ctx.walk
    bx, by = spot("river_bank")

    walk.add_rect(WX0, Y0, RAIL - WX0, Y1 - Y0)
    walk.add_rect(RAIL - 12, DECK0, XR - RAIL + 12, DECK1 - DECK0)          # 桥面
    walk.add_poly(_half_ellipse(PCX, PCY, PRX - 8, PRY - 8))              # 平台
    walk.add_rect(RAIL - 12, PCY - PRY + 8, 24, 2 * PRY - 16)              # 台阶

    water(ctx)
    far_bank(ctx)
    promenade(ctx)
    lawns(ctx)
    railing(ctx)
    platform(ctx, bx, by)
    bridge_deck(ctx)
    boat(ctx, 2322, 1010)
    furniture(ctx)
    bridge_truss(ctx)

    # 水面上的地名注记（像旧地图）
    g.ink.text("海河", 2348, 300, 34, density=0.8, vertical=True)

    # 风筝（引擎画、会飘）和水面的涟漪
    for kx, ky in ((2296, 540), (2356, 790), (2268, 1060)):
        ctx.anchor("kite", kx, ky)
    for rx, ry in ((2300, 300), (2350, 470), (2330, 930), (2280, 1190), (2350, 1380), (2300, 1540)):
        ctx.anchor("ripple", rx, ry)


def _half_ellipse(cx, cy, rx, ry, n=24):
    return [(cx + rx * math.sin(math.pi * k / n), cy - ry * math.cos(math.pi * k / n)) for k in range(n + 1)]


# ----------------------------------------------------------------------
# 水
# ----------------------------------------------------------------------

def water(ctx: Ctx):
    g = ctx.g
    rnd = random.Random(23)
    area = rect_pts(WATER0, -12, XR - WATER0, 1624)
    g.pen("qing", 0.36).fill(area)
    # 河堤投在水上的影子
    g.pen("ink", 0.16).fill(rect_pts(WATER0, -12, 14, 1624))
    # 手画的水纹：一簇一簇的短波浪线
    for _ in range(30):
        cx, cy = rnd.uniform(WATER0 + 30, XR - 10), rnd.uniform(70, 1600)
        if DECK0 - 30 < cy < DECK1 + 40:
            continue
        L = rnd.uniform(26, 60)
        for k in range(rnd.randint(1, 3)):
            yy = cy + k * 9
            x0 = cx - L / 2 + k * rnd.uniform(-6, 10)
            pts = [(x0 + L * t / 12, yy + 2.2 * math.sin(t * math.pi / 3)) for t in range(13)]
            g.qing.line(pts, 2.0, amp=0.3)
    # 反光：几道留白
    for _ in range(22):
        cx, cy = rnd.uniform(WATER0 + 40, XR - 20), rnd.uniform(130, 1580)
        if DECK0 - 30 < cy < DECK1 + 40:
            continue
        L = rnd.uniform(18, 54)
        g.clear([(cx - L / 2, cy), (cx, cy - 3), (cx + L / 2, cy), (cx, cy + 3)])
    # 河堤：一道粗墨线 + 石头压顶
    g.ink.line([(WATER0, -12), (WATER0, 1612)], 3.4)


def far_bank(ctx: Ctx):
    """水面北头：河往东北拐，远远看见对岸一排楼的剪影（很淡的墨），晚上窗户亮灯。"""
    g = ctx.g
    rnd = random.Random(41)
    yb = 104                                  # 对岸岸线
    g.clear(rect_pts(WATER0 + 2, -12, XR - WATER0, yb + 12))
    g.pen("ink", 0.07).fill(rect_pts(WATER0 + 2, -12, XR - WATER0, yb + 12))
    x = WATER0 + 10
    while x < XR:
        w = rnd.uniform(22, 44)
        h = rnd.uniform(40, 112)
        top = yb - h
        g.pen("ink", rnd.choice([0.14, 0.2, 0.26])).fill(rect_pts(x, top, w, h))
        g.ink.rect(x, top, w, h, lw=1.4, density=0.5)
        # 窗：几颗点，个别亮着（梅）
        for wy in range(int(top + 8), int(yb - 6), 10):
            for wx in range(int(x + 6), int(x + w - 4), 9):
                if rnd.random() < 0.18:
                    g.pen("mei", 0.85).fill(rect_pts(wx, wy, 4, 5))
                    if rnd.random() < 0.5:
                        ctx.anchor("far_light", wx + 2, wy + 2)
                elif rnd.random() < 0.4:
                    g.ink.fill(rect_pts(wx, wy, 3, 4), density=0.45)
        x += w + rnd.uniform(2, 10)
    # 对岸的烟囱、厂房、后来的摩天轮都随年代变，是 street.py 画的活物，不在底图里
    # 对岸的岸线（双线，像石堤）
    g.ink.line([(WATER0, yb), (XR, yb)], 2.4, density=0.8)
    g.ink.line([(WATER0, yb + 6), (XR, yb + 6)], 1.2, density=0.5)
    # 对岸倒影：岸线下面几道断续的短横
    for k in range(6):
        y = yb + 14 + k * 7
        x = WATER0 + 14 + (k % 3) * 9
        while x < XR:
            L = rnd.uniform(8, 22)
            g.ink.line([(x, y), (x + L, y)], 1.4, amp=0.2, density=0.35)
            x += L + rnd.uniform(10, 26)


# ----------------------------------------------------------------------
# 步道
# ----------------------------------------------------------------------

def promenade(ctx: Ctx):
    g = ctx.g
    x0, x1 = WX0, RAIL
    g.pen("ink", 0.06).fill(rect_pts(x0, -12, x1 - x0, 1624))
    # 大方石板，靠河一侧错缝
    S = 64
    y = 0
    while y < 1600:
        g.ink.line([(x0, y), (x1 - 26, y)], 1.0, amp=0.3, density=0.3)
        y += S
    for x in range(int(x0 + S), int(x1 - 26), S):
        g.ink.line([(x, -12), (x, 1612)], 1.0, amp=0.3, density=0.26)
    # 靠护栏一溜长条石（压顶前的一条深色石带）
    band = rect_pts(x1 - 26, -12, 26, 1624)
    g.pen("ink", 0.14).fill(band)
    y = 0
    while y < 1600:
        g.ink.line([(x1 - 26, y), (x1, y)], 1.2, amp=0.2, density=0.5)
        y += 32
    g.ink.line([(x1 - 26, -12), (x1 - 26, 1612)], 1.6, density=0.7)

    # 中间一条红砖甬路（梅色），把长长的步道分成两半
    bx0, bw = 2000, 40
    g.pen("mei", 0.2).fill(rect_pts(bx0, -12, bw, 1624))
    g.mei.bricks(bx0, -12, bw, 1624, 20, 10, 1.0, density=0.55, seed=5)
    g.ink.line([(bx0, -12), (bx0, 1612)], 1.6, density=0.8)
    g.ink.line([(bx0 + bw, -12), (bx0 + bw, 1612)], 1.6, density=0.8)

    # 桥头：一片颜色深一点的石板广场，接上桥面
    plaza = rect_pts(2060, DECK0 - 28, RAIL - 2060, DECK1 - DECK0 + 56)
    g.clear(plaza)
    g.pen("ink", 0.11).fill(plaza)
    for x in range(2070, RAIL, 14):
        g.ink.line([(x, DECK0 - 26), (x, DECK1 + 26)], 1.0, amp=0.2, density=0.32)
    g.ink.box(2060, DECK0 - 28, RAIL - 2060, DECK1 - DECK0 + 56, 2.2, over=6)

    # 马路到这儿就到头了：一道路牙子收口 + 一排石墩（车进不来，人能走）
    g.ink.line([(WX0 + 20, 760), (WX0 + 20, 1000)], 3.0)
    g.ink.line([(WX0 + 14, 766), (WX0 + 14, 994)], 1.2, density=0.6)
    for yy in range(790, 1000, 52):
        bx, by = WX0 + 52, yy
        shadow(g, ellipse_pts(bx + 8, by + 6, 11, 6), 0.16)
        g.clear(circle_pts(bx, by, 9, 20))
        g.pen("ink", 0.2).fill(circle_pts(bx, by, 9, 20))
        g.ink.circle(bx, by, 9, lw=2.2)
        ctx.walk.block_circle(bx, by, 9)

    # 西边一溜冬青（北段、南段；中间对着街角和马路的地方敞开）
    for ya, yb in ((-12, 296), (1090, 1270), (1336, 1612)):
        hedge(ctx, WX0 + 4, ya, 40, yb - ya)


def hedge(ctx: Ctx, x, y, w, h):
    g = ctx.g
    rnd = random.Random(int(y))
    pts = rect_pts(x, y, w, h)
    shadow(g, [(x + w, y + 6), (x + w + 14, y + 14), (x + w + 14, y + h + 8), (x + w, y + h)], 0.16)
    g.clear(pts)
    g.pen("qing", 0.5).fill(pts)
    # 边上一圈小圆弧，像修剪过的灌木
    yy = y
    while yy < y + h:
        r = rnd.uniform(9, 13)
        g.qing.arc(x + w - 2, yy + r, r, -math.pi / 2, math.pi / 2, lw=2.0)
        g.qing.arc(x + 2, yy + r, r, math.pi / 2, math.pi * 1.5, lw=2.0)
        yy += r * 2
    for _ in range(int(h / 30)):
        lx, ly = x + rnd.uniform(8, w - 8), y + rnd.uniform(8, h - 8)
        g.ink.arc(lx, ly, 5, 0.3, 2.6, lw=1.4)
    ctx.walk.block_rect(x - 2, max(y, 0), w + 6, h)


def lawns(ctx: Ctx):
    """北头、南头的草坪：青网点 + 几笔短草，一个花坛。"""
    g = ctx.g
    rnd = random.Random(9)
    for ya, yb in ((-12, Y0 - 10), (Y1 + 10, 1612)):
        pts = rect_pts(WX0 + 44, ya, RAIL - 26 - WX0 - 44, yb - ya)
        g.clear(pts)
        g.pen("qing", 0.2).fill(pts)
        for _ in range(int((yb - ya) * 0.35)):
            gx, gy = rnd.uniform(WX0 + 52, RAIL - 34), rnd.uniform(ya + 8, yb - 6)
            g.qing.line([(gx, gy), (gx - 2, gy - 7)], 1.4, amp=0)
            g.qing.line([(gx + 4, gy), (gx + 6, gy - 6)], 1.4, amp=0)
        edge = yb if ya < 0 else ya
        g.ink.line([(WX0 + 40, edge), (RAIL - 22, edge)], 2.4)
        g.ink.line([(WX0 + 40, edge + (4 if ya < 0 else -4)), (RAIL - 22, edge + (4 if ya < 0 else -4))], 1.0, density=0.6)
    # 北头一个圆花坛（月季：梅色小点）
    fx, fy = 2050, 66
    g.clear(circle_pts(fx, fy, 40, 40))
    g.pen("qing", 0.4).fill(circle_pts(fx, fy, 40, 40))
    g.ink.circle(fx, fy, 40, lw=2.6)
    g.ink.circle(fx, fy, 46, lw=1.2, density=0.6)
    for _ in range(26):
        a, r = rnd.uniform(0, math.tau), rnd.uniform(4, 32)
        g.mei.dot(fx + r * math.cos(a), fy + r * math.sin(a) * 0.9, 3.2)
    # 南头一块刻字的石头
    sx, sy = 2070, 1548
    stone = [(sx - 40, sy + 10), (sx - 30, sy - 18), (sx + 14, sy - 24), (sx + 42, sy - 6), (sx + 36, sy + 14), (sx - 10, sy + 20)]
    shadow(g, [(p[0] + 10, p[1] + 8) for p in stone], 0.18)
    g.clear(stone)
    g.pen("ink", 0.16).fill(stone)
    g.ink.poly(stone, 2.6)
    g.ink.text("亲水", sx, sy - 2, 19)


def railing(ctx: Ctx):
    """护栏：石头压顶 + 铸铁栏杆（立柱、两道横杆、中间一个个小圈），桥头和台阶处开口。"""
    g = ctx.g
    gaps = [(DECK0 - 16, DECK1 + 16), (PCY - PRY + 6, PCY + PRY - 6)]

    def segs(a, b):
        cur = a
        for ga, gb in gaps:
            if ga > cur and ga < b:
                yield cur, ga
                cur = gb
        yield cur, b

    for ya, yb in segs(-12, 1612):
        g.clear(rect_pts(RAIL - 6, ya, 14, yb - ya))
        g.pen("ink", 0.1).fill(rect_pts(RAIL - 6, ya, 14, yb - ya))
        g.ink.line([(RAIL - 6, ya), (RAIL - 6, yb)], 2.6)
        g.ink.line([(RAIL + 7, ya), (RAIL + 7, yb)], 1.4, density=0.8)
        # 铸铁栏杆：立柱 + 柱间的小圈
        y = ya + 10
        k = 0
        while y < yb - 6:
            if k % 4 == 0:
                g.ink.fill(rect_pts(RAIL - 4, y - 3, 8, 6))
            else:
                g.ink.circle(RAIL + 1, y, 2.8, lw=1.2)
            y += 12
            k += 1
        for yy in (ya, yb):
            g.ink.fill(rect_pts(RAIL - 8, yy - 5, 16, 10))
        ctx.walk.block_rect(RAIL - 8, ya, 20, yb - ya)


# ----------------------------------------------------------------------
# 亲水平台
# ----------------------------------------------------------------------

def platform(ctx: Ctx, bx, by):
    g, o = ctx.g, ctx.o
    he = _half_ellipse(PCX, PCY, PRX, PRY)
    # 影子（右下，落在水上）
    shadow(g, [(p[0] + 12, p[1] + 10) for p in he], 0.18)
    g.clear(he)
    g.pen("ink", 0.08).fill(he)
    # 同心的铺地缝
    for k in (0.4, 0.7):
        arc = _half_ellipse(PCX, PCY, PRX * k, PRY * k)
        g.ink.line(arc, 1.0, amp=0.3, density=0.35)
    for a in (0.25, 0.5, 0.75):
        t = math.pi * a
        g.ink.line([(PCX + PRX * 0.4 * math.sin(t), PCY - PRY * 0.4 * math.cos(t)), (PCX + PRX * math.sin(t), PCY - PRY * math.cos(t))], 1.0, amp=0.2, density=0.35)
    # 台阶：三级往下（东）走
    sy0, sy1 = PCY - PRY + 8, PCY + PRY - 8
    g.clear(rect_pts(RAIL - 14, sy0, 24, sy1 - sy0))
    for i, x in enumerate((RAIL - 14, RAIL - 6, RAIL + 2)):
        g.pen("ink", 0.06 + i * 0.06).fill(rect_pts(x, sy0, 8, sy1 - sy0))
        g.ink.line([(x, sy0), (x, sy1)], 1.6)
    g.ink.line([(RAIL - 14, sy0), (RAIL + 10, sy0)], 2)
    g.ink.line([(RAIL - 14, sy1), (RAIL + 10, sy1)], 2)
    # 平台边：一圈栏杆。半圈往东凸，南边那段的立柱"往上长"露出高度
    rail = _half_ellipse(PCX, PCY, PRX, PRY, 32)
    g.ink.line(rail, 3.0)
    top = [(x, y - 16) for x, y in _half_ellipse(PCX, PCY, PRX - 4, PRY - 4, 32)]
    o.ink.line(top, 2.2)
    for k, (x, y) in enumerate(rail[1:-1]):
        tx, ty = top[k + 1]
        o.ink.line([(x, y), (tx, ty)], 1.6 if k % 4 else 2.6)
    # 救生圈（梅白相间），挂在栏杆上
    lx, ly = rail[22]
    o.clear(circle_pts(lx, ly - 12, 11, 24))
    for i in range(8):
        a0, a1 = i * math.tau / 8, (i + 1) * math.tau / 8
        seg = [(lx + 11 * math.cos(a0 + (a1 - a0) * j / 4), ly - 12 + 11 * math.sin(a0 + (a1 - a0) * j / 4)) for j in range(5)]
        seg += [(lx + 6 * math.cos(a1 - (a1 - a0) * j / 4), ly - 12 + 6 * math.sin(a1 - (a1 - a0) * j / 4)) for j in range(5)]
        if i % 2 == 0:
            o.mei.fill(seg)
    o.ink.circle(lx, ly - 12, 11, lw=1.8)
    o.ink.circle(lx, ly - 12, 6, lw=1.4)
    # 系船的铁桩
    mx, my = rail[8]
    g.ink.circle(mx - 12, my + 6, 5, lw=2, fill=True)
    ctx.walk.block_circle(mx - 12, my + 6, 7)
    # 平台外一圈水纹
    rnd = random.Random(3)
    for k in range(3):
        arc = _half_ellipse(PCX, PCY, PRX + 12 + k * 10, PRY + 10 + k * 9, 20)
        a = rnd.randint(2, 8)
        g.qing.line(arc[a:a + 6 + k], 1.6, amp=0.6)
        g.qing.line(arc[a + 9:a + 13], 1.6, amp=0.6)
    _ = bx, by


# ----------------------------------------------------------------------
# 铁桥
# ----------------------------------------------------------------------

def bridge_deck(ctx: Ctx):
    """桥面（地面层，可走）：钢板路面 + 两边人行道 + 桥头两根石柱。"""
    g, o = ctx.g, ctx.o
    x0 = RAIL - 10
    # 桥身投在水上的影子（往右下）
    shadow(g, [(WATER0, DECK1), (XR, DECK1), (XR, DECK1 + 20), (WATER0 + 20, DECK1 + 20)], 0.24)
    # 桥墩：桥面南北两边各露出一个分水尖
    for px in (2316,):
        for yy, s in ((DECK0, -1), (DECK1, 1)):
            tip = [(px - 14, yy), (px, yy + s * 20), (px + 14, yy)]
            g.clear(tip)
            g.pen("ink", 0.3).fill(tip)
            g.ink.poly(tip, 2.0)
            g.qing.arc(px, yy + s * 14, 22, 0.3 if s > 0 else math.pi + 0.3, 2.8 if s > 0 else math.pi + 2.8, lw=1.6)
    deck = rect_pts(x0, DECK0, XR - x0, DECK1 - DECK0)
    g.clear(deck)
    g.pen("ink", 0.1).fill(deck)
    # 两边人行道（略浅），中间行车道上一道道横向钢板缝
    for ya in (DECK0, DECK1 - 12):
        g.clear(rect_pts(x0, ya, XR - x0, 12))
        g.pen("ink", 0.05).fill(rect_pts(x0, ya, XR - x0, 12))
        g.ink.line([(x0, ya + (12 if ya == DECK0 else 0)), (XR, ya + (12 if ya == DECK0 else 0))], 1.4, density=0.7)
    x = x0 + 8
    while x < XR:
        g.ink.line([(x, DECK0 + 12), (x, DECK1 - 12)], 1.0, amp=0.2, density=0.4)
        x += 14
    g.ink.line([(x0, DECK0), (XR, DECK0)], 3.0)
    g.ink.line([(x0, DECK1), (XR, DECK1)], 3.2)
    # 桥头石柱 + 柱头灯
    for yy in (DECK0 - 10, DECK1 + 10):
        cx = RAIL - 2
        shadow(g, [(cx + 10, yy - 10), (cx + 28, yy - 2), (cx + 28, yy + 16), (cx + 10, yy + 10)], 0.18)
        g.clear(rect_pts(cx - 11, yy - 11, 22, 22))
        g.pen("ink", 0.2).fill(rect_pts(cx - 11, yy - 11, 22, 22))
        g.ink.rect(cx - 11, yy - 11, 22, 22, lw=2.4)
        g.ink.rect(cx - 6, yy - 6, 12, 12, lw=1.4)
        ctx.walk.block_rect(cx - 13, yy - 13, 26, 26)
        # 柱头上一盏灯（上层）：短铁杆 + 球形灯罩
        o.ink.line([(cx, yy - 4), (cx, yy - 44)], 4)
        o.clear(circle_pts(cx, yy - 52, 9, 20))
        o.pen("mei", 0.25).fill(circle_pts(cx, yy - 52, 9, 20))
        o.ink.circle(cx, yy - 52, 9, lw=2.2)
        o.ink.line([(cx - 6, yy - 62), (cx + 6, yy - 62)], 2.6)
        ctx.anchor("street_lamp", cx, yy)
    _ = o


def bridge_truss(ctx: Ctx):
    """钢桁架（上层）：南北两片桁架，高度往上露一半；上弦之间有横撑。
    原创的简笔：平行弦、斜腹杆、端头斜杆，上弦刷青漆，铆钉墨点。"""
    o = ctx.o
    P = 52                    # 节间
    H = 64                    # 桁架高度在画面上露出的部分（实际高 × 0.5）
    xs = RAIL + 18            # 端头
    pts_x = []
    x = xs
    while x < XR + P:
        pts_x.append(x)
        x += P
    for yb in (DECK0, DECK1):
        yt = yb - H
        front = yb == DECK1
        lw = 4.2 if front else 3.0
        # 上弦：两道墨线夹一条青
        band = [(xs + P, yt - 5), (XR + 20, yt - 5), (XR + 20, yt + 5), (xs + P, yt + 5)]
        o.clear(band)
        o.qing.fill(band)
        o.ink.line([(xs + P, yt - 5), (XR + 20, yt - 5)], lw * 0.7, amp=0.3)
        o.ink.line([(xs + P, yt + 5), (XR + 20, yt + 5)], lw * 0.7, amp=0.3)
        # 下弦
        o.ink.line([(xs, yb), (XR + 20, yb)], lw, amp=0.3)
        # 端斜杆
        o.ink.line([(xs, yb), (xs + P, yt)], lw + 1.2, amp=0.3)
        o.ink.line([(xs + 5, yb), (xs + P + 5, yt)], 1.2, amp=0.2)
        # 竖杆 + 斜腹杆（人字形，Pratt 的意思）
        for i, px in enumerate(pts_x[1:]):
            o.ink.line([(px, yb), (px, yt)], lw * 0.75, amp=0.2)
            nx = px + P
            o.ink.line([(px, yt), (nx, yb)] if i % 2 == 0 else [(px, yb), (nx, yt)], lw * 0.6, amp=0.2)
            o.ink.dot(px, yt, 2.6)
            o.ink.dot(px, yb, 2.6)
        if front:
            # 前面这片桁架的影子：很淡地落在桥面上（右下）
            pass
    # 上弦之间的横撑（从上往下看，挡在桥面上方，细一点）
    yt0, yt1 = DECK0 - H, DECK1 - H
    for i, px in enumerate(pts_x[1:]):
        o.ink.line([(px, yt0 + 5), (px, yt1 - 5)], 2.0, amp=0.2)
        nx = px + P
        o.ink.line([(px, yt0 + 5), (nx, yt1 - 5)], 1.1, amp=0.2, density=0.6)
        o.ink.line([(px, yt1 - 5), (nx, yt0 + 5)], 1.1, amp=0.2, density=0.6)
    # 桥门：端头一道门式横梁，挂一块梅色小牌（不写名字，只有三道横）
    gx = xs + P
    o.ink.line([(gx, yt0), (gx, yt1)], 4.2, amp=0.2)
    o.ink.line([(gx + 6, yt0), (gx + 6, yt1)], 1.6, amp=0.2)
    mx, my = gx + 3, (yt0 + yt1) / 2
    plate = rect_pts(mx - 9, my - 16, 18, 32)
    o.clear(plate)
    o.mei.fill(plate)
    o.ink.rect(mx - 9, my - 16, 18, 32, lw=1.8)
    for k in range(3):
        o.clear(rect_pts(mx - 4, my - 9 + k * 8, 8, 2.4))


# ----------------------------------------------------------------------
# 小船、长椅、路灯、柳树
# ----------------------------------------------------------------------

def boat(ctx: Ctx, x, y):
    """一条拴在平台边上的小木船（船头朝北）。"""
    g = ctx.g
    L, Wd = 92, 30
    hull = []
    for k in range(17):
        t = k / 16
        yy = y - L / 2 + L * t
        w = Wd / 2 * math.sin(math.pi * min(1.0, t * 1.15)) ** 0.7
        hull.append((x + w, yy))
    hull += [(2 * x - px, py) for px, py in reversed(hull)]
    shadow(g, [(px + 10, py + 6) for px, py in hull], 0.22)
    g.clear(hull)
    g.pen("ink", 0.1).fill(hull)
    g.ink.poly(hull, 2.6)
    inner = [(x + (px - x) * 0.72, y + (py - y) * 0.84) for px, py in hull]
    g.ink.poly(inner, 1.4, density=0.7)
    for k in (-14, 6, 24):
        g.ink.line([(x - 10, y + k), (x + 10, y + k)], 3.4)
    g.mei.line([(px, py) for px, py in hull[3:14]], 2.4, amp=0.3)
    # 一支桨
    g.ink.line([(x - 4, y - 4), (x - 30, y + 30)], 2.4)
    g.ink.ellipse(x - 33, y + 34, 5, 8, lw=1.6)
    # 拴船的绳子：拉到平台的铁桩
    rail = _half_ellipse(PCX, PCY, PRX, PRY, 32)
    mx, my = rail[8]
    g.ink.line([(x - 2, y - L / 2 + 4), ((x + mx) / 2 + 6, (y - L / 2 + my) / 2 + 12), (mx - 12, my + 6)], 1.4, amp=0.4)


def bench(ctx: Ctx, x, y, L=66):
    """面朝河（东）的长椅：座面南北向，靠背在西边、往上立起来。"""
    g, o = ctx.g, ctx.o
    shadow(g, [(x - 8, y + L), (x + 12, y + L), (x + 30, y + L + 10), (x + 10, y + L + 10)], 0.16)
    shadow(g, [(x + 10, y + 6), (x + 22, y + 12), (x + 22, y + L + 8), (x + 10, y + L)], 0.14)
    seat = rect_pts(x - 8, y, 18, L)
    g.clear(seat)
    g.pen("mei", 0.28).fill(seat)
    for k in range(1, 3):
        g.ink.line([(x - 8 + k * 6, y + 2), (x - 8 + k * 6, y + L - 2)], 1.0, amp=0.1, density=0.7)
    g.ink.rect(x - 8, y, 18, L, lw=2.2)
    for yy in (y + 6, y + L - 6):
        g.ink.line([(x - 6, yy), (x - 6, yy + 10)], 2.2)
        g.ink.line([(x + 8, yy), (x + 8, yy + 10)], 2.2)
    # 靠背：上层，角色坐下时靠背在前面一点点
    back = [(x - 14, y - 14), (x - 8, y - 14), (x - 8, y + L - 14), (x - 14, y + L - 14)]
    o.clear(back)
    o.pen("mei", 0.4).fill(back)
    o.ink.poly(back, 2.0)
    o.ink.line([(x - 11, y - 14), (x - 11, y)], 1.6)
    o.ink.line([(x - 11, y + L - 14), (x - 11, y + L)], 1.6)
    ctx.walk.block_rect(x - 14, y, 26, L)


def lamp(ctx: Ctx, x, y, h=120):
    """河边的老式路灯：铸铁杆 + 一个球灯罩（上层）。"""
    g, o = ctx.g, ctx.o
    shadow(g, [(x, y), (x + h * 0.5, y + h * 0.16), (x + h * 0.5 + 5, y + h * 0.16 + 5), (x + 5, y + 5)], 0.12)
    g.ink.circle(x, y, 8, lw=2.2)
    g.ink.dot(x, y, 4)
    o.ink.line([(x, y), (x, y - h)], 4)
    o.ink.line([(x - 5, y - 12), (x + 5, y - 12)], 3)
    o.ink.line([(x - 14, y - h + 4), (x, y - h + 12), (x + 14, y - h + 4)], 2.2)
    for sx in (-14, 14):
        o.clear(circle_pts(x + sx, y - h + 12, 7, 18))
        o.ink.circle(x + sx, y - h + 12, 7, lw=1.8)
        o.ink.line([(x + sx - 4, y - h + 3), (x + sx + 4, y - h + 3)], 2.4)
    ctx.walk.block_circle(x, y, 9)
    ctx.anchor("street_lamp", x, y)


def fisher_spot(ctx: Ctx, x, y):
    """钓鱼的人刚走开：一只马扎、一个铁皮水桶、一根靠在栏杆上的鱼竿。"""
    from common import stool
    g, o = ctx.g, ctx.o
    stool(g, x, y, "qing")
    shadow(g, ellipse_pts(x + 30, y + 6, 13, 5), 0.16)
    g.clear(rect_pts(x + 14, y - 14, 20, 18))
    g.pen("ink", 0.12).fill(rect_pts(x + 14, y - 14, 20, 18))
    g.ink.line([(x + 14, y - 14), (x + 14, y + 4)], 1.8)
    g.ink.line([(x + 34, y - 14), (x + 34, y + 4)], 1.8)
    g.ink.arc(x + 24, y + 4, 10, 0, math.pi, lw=1.8, amp=0.1)
    g.pen("qing", 0.6).fill(ellipse_pts(x + 24, y - 14, 10, 4))
    g.ink.ellipse(x + 24, y - 14, 10, 4, lw=1.8)
    o.ink.line([(x - 6, y + 2), (RAIL + 60, y - 120)], 1.6, amp=0.3)
    o.ink.line([(RAIL + 60, y - 120), (RAIL + 74, y - 40)], 0.8, amp=0.6, density=0.8)
    ctx.walk.block_rect(x - 12, y - 14, 48, 24)


def furniture(ctx: Ctx):
    # 柳树沿河一排（树冠在上层，垂到步道上）
    for ty in (260, 520, 1020, 1260, 1470):
        tree(ctx, RAIL - 50, ty, 72, kind="willow", seed=ty)
    # 内侧两棵国槐（西边冬青前面）
    for ty in (1170, 1440):
        tree(ctx, 1964, ty, 60, seed=ty + 3)
    # 长椅（柳树之间，面朝河）
    for by in (362, 1290):
        bench(ctx, RAIL - 30, by)
    # 钓鱼的地方
    fisher_spot(ctx, RAIL - 46, 1110)
    # 路灯
    for ly in (318, 1180):
        lamp(ctx, RAIL - 16, ly)
