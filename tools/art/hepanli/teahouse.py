"""河畔茶社：街角一栋青砖小洋楼的一层，改成了街坊喝茶听书的茶社。

和红砖楼一样是剖面：揭开屋顶往里看。红砖楼是梅色的砖，这栋是墨色的青砖，一眼分得开。
范围：x 1452~1876，y 0~288（北墙在地图外）。
  北墙内立面  y 0~44：三扇拱窗、台口一道梅色的守旧（幕布），反白字「河畔茶社」
  小戏台      x 1540~1800，y 44~134，台沿 y 134~146；两头各有两级台阶
              台上的桌子和人是 street.py 画的活物，不在底图里
  堂座        y 150~274：花砖地（洋楼的老地砖），三张八仙桌配条凳，桌上盖碗、瓜子
  西墙        账柜 + 茶炉，炉上坐着大铜壶，一排暖壶
  东南角      门（x 1806~1858），门里立着今天的水牌；门楣上的匾在上层
可走：堂座、戏台（从两头台阶上）、门口；桌子、条凳、账柜不可走。
"""
import math
import random

from common import Ctx, _knockout_text, circle_pts, ellipse_pts, rect_pts, shadow, sign

X0, X1 = 1452, 1876          # 外墙外皮
YS = 288                     # 南墙外皮
WALL = 14
FACE = 44                    # 北墙内立面露出来的高度
SX0, SX1 = 1540, 1800        # 戏台东西
SY0, SY1, RISER = 44, 134, 12
DOOR = (1806, 1858)


def draw(ctx: Ctx):
    g, walk = ctx.g, ctx.walk
    g.clear(rect_pts(X0 - 4, -12, X1 - X0 + 8, YS + 12))
    walk.block_rect(X0 - 4, 0, X1 - X0 + 8, YS + 8)
    walk.add_rect(X0 + WALL, FACE + 4, X1 - X0 - 2 * WALL, YS - WALL - FACE - 4)
    walk.add_rect(DOOR[0] + 2, YS - WALL - 4, DOOR[1] - DOOR[0] - 4, WALL + 22)

    floor(ctx)
    north_face(ctx)
    stage(ctx)
    counter(ctx)
    tables(ctx)
    walls(ctx)
    door(ctx)

    # 晚上：台口一盏灯、堂里两盏
    ctx.anchor("window_light", (SX0 + SX1) / 2, 96)
    ctx.anchor("hall_lamp", 1560, 210)
    ctx.anchor("hall_lamp", 1780, 210)
    # 茶炉上的热气
    ctx.anchor("steam", X0 + WALL + 22, 150)


# ----------------------------------------------------------------------
# 地、墙
# ----------------------------------------------------------------------

def floor(ctx: Ctx):
    """花砖地：斜拼的方砖，交点上一颗青色的小菱形，隔一块压一点梅。"""
    g = ctx.g
    x0, y0, x1, y1 = X0 + WALL, FACE, X1 - WALL, YS - WALL
    area = rect_pts(x0, y0, x1 - x0, y1 - y0)
    g.pen("ink", 0.05).fill(area)
    T = 26
    with g.clip(area):
        k = -10
        while x0 + k * T < x1 + (y1 - y0):
            xa = x0 + k * T
            g.ink.line([(xa, y0), (xa + (y1 - y0), y1)], 0.8, amp=0, density=0.28)
            g.ink.line([(xa, y0), (xa - (y1 - y0), y1)], 0.8, amp=0, density=0.28)
            k += 1
        row = 0
        yy = y0
        while yy < y1 + T:
            xx = x0 + (T / 2 if row % 2 else 0)
            col = 0
            while xx < x1 + T:
                d = 3.2
                dia = [(xx, yy - d), (xx + d, yy), (xx, yy + d), (xx - d, yy)]
                if (row + col * 2) % 4 == 0:
                    g.pen("mei", 0.75).fill(dia)
                else:
                    g.pen("qing", 0.8).fill(dia)
                xx += T
                col += 1
            yy += T / 2
            row += 1


def brick(g, x, y, w, h, lw=2.6):
    """青砖墙的剖面：墨网点 + 砖缝。"""
    g.clear(rect_pts(x, y, w, h))
    g.pen("ink", 0.46).fill(rect_pts(x, y, w, h))
    if w > 10 and h > 10:
        g.ink.bricks(x, y, w, h, bw=18, bh=7, lw=0.8, density=0.5)
    g.ink.rect(x, y, w, h, lw=lw, amp=0.5)


def walls(ctx: Ctx):
    g = ctx.g
    brick(g, X0, -12, WALL, YS + 12)
    brick(g, X1 - WALL, -12, WALL, YS + 12)
    brick(g, X0, YS - WALL, DOOR[0] - X0, WALL)
    brick(g, DOOR[1], YS - WALL, X1 - DOOR[1], WALL)
    # 南墙上两个窗洞（剖切）：窗台留白，玻璃一道青线
    for wx in (1500, 1640):
        g.clear(rect_pts(wx, YS - WALL, 80, WALL))
        g.ink.rect(wx, YS - WALL, 80, WALL, lw=2)
        g.qing.line([(wx + 4, YS - WALL / 2), (wx + 76, YS - WALL / 2)], 2.2, amp=0.2)
    # 西墙上的壁炉（洋楼的老东西，早不烧了，摆着暖壶）
    fx, fy = X0 + WALL, 196
    g.clear(rect_pts(fx, fy, 12, 46))
    g.pen("ink", 0.7).fill(rect_pts(fx, fy + 8, 8, 30))
    g.ink.rect(fx, fy, 12, 46, lw=2)
    ctx.walk.block_rect(fx, fy - 2, 14, 50)


def north_face(ctx: Ctx):
    """北墙的内立面：白灰墙、木墙裙、三扇拱窗；正中是戏台的守旧。"""
    g = ctx.g
    x0, x1 = X0 + WALL, X1 - WALL
    face = rect_pts(x0, -12, x1 - x0, FACE + 12)
    g.clear(face)
    g.pen("qing", 0.26).fill(rect_pts(x0, FACE - 14, x1 - x0, 14))       # 墙裙
    g.ink.line([(x0, FACE - 14), (x1, FACE - 14)], 1.4, amp=0.3)
    g.ink.line([(x0, FACE), (x1, FACE)], 2.8)
    # 拱窗：两边各一扇（中间那扇被守旧挡住）
    for wx in (1494, 1838):
        arch = [(wx - 13, FACE - 15)] + [(wx + 13 * math.cos(math.pi - a * math.pi / 12), 15 - 13 * math.sin(a * math.pi / 12)) for a in range(13)] + [(wx + 13, FACE - 15)]
        g.clear(arch)
        g.pen("qing", 0.3).fill(arch)
        g.ink.poly(arch, 2.0, amp=0.3)
        g.ink.line([(wx, 3), (wx, FACE - 15)], 1.2, amp=0)
        g.ink.line([(wx - 13, 16), (wx + 13, 16)], 1.2, amp=0)
        for a in (-0.9, 0.9):   # 扇形窗棂
            g.ink.line([(wx, 16), (wx + 12 * math.sin(a), 16 - 12 * math.cos(a))], 0.9, amp=0)
    # 守旧：梅色的幕布，上沿一排水波纹的檐子
    cx0, cx1 = SX0 + 30, SX1 - 30
    cloth = rect_pts(cx0, -12, cx1 - cx0, FACE + 10)
    g.clear(cloth)
    g.mei.fill(cloth)
    k = cx0 + 14
    while k < cx1 - 6:   # 布褶
        g.ink.line([(k, 8), (k + 1, FACE - 3)], 0.9, amp=0.5, density=0.35)
        k += 22
    g.ink.rect(cx0, -12, cx1 - cx0, FACE + 10, lw=2.2)
    _knockout_text(g, "mei", "河畔茶社", (cx0 + cx1) / 2, 18, 24, False)
    # 两边的抱柱对联（青牌反白字）
    for px, text in ((cx0 - 16, "一壶清茶"), (cx1 + 16, "半日闲话")):
        sign(g, px, 22, text, "qing", size=8.6, vertical=True, pad=3)


# ----------------------------------------------------------------------
# 戏台
# ----------------------------------------------------------------------

def stage(ctx: Ctx):
    g, walk = ctx.g, ctx.walk
    top = rect_pts(SX0, SY0, SX1 - SX0, SY1 - SY0)
    shadow(g, [(SX1, SY0 + 8), (SX1 + 12, SY0 + 16), (SX1 + 12, SY1 + RISER + 8), (SX0 + 12, SY1 + RISER + 8), (SX0, SY1 + RISER)], 0.16)
    g.clear(rect_pts(SX0, SY0, SX1 - SX0, SY1 - SY0 + RISER))
    g.pen("ink", 0.10).fill(top)
    yy = SY0 + 15                                   # 台板
    while yy < SY1:
        g.ink.line([(SX0 + 2, yy), (SX1 - 2, yy)], 0.9, amp=0.3, density=0.4)
        yy += 15
    # 台毯：一块梅色的地毯，上台的人就站在这上头
    rug = rect_pts(SX0 + 64, SY0 + 34, SX1 - SX0 - 128, 44)
    g.clear(rug)
    g.pen("mei", 0.3).fill(rug)
    g.mei.rect(SX0 + 64, SY0 + 34, SX1 - SX0 - 128, 44, lw=1.6, amp=0.4)
    g.mei.rect(SX0 + 70, SY0 + 40, SX1 - SX0 - 140, 32, lw=0.9, amp=0.3)
    # 台沿
    g.pen("ink", 0.34).fill(rect_pts(SX0, SY1, SX1 - SX0, RISER))
    g.ink.rect(SX0, SY0, SX1 - SX0, SY1 - SY0, lw=2.6)
    g.ink.rect(SX0, SY1, SX1 - SX0, RISER, lw=2.4)
    k = SX0 + 20
    while k < SX1 - 10:                             # 台沿上一排小灯泡
        g.clear(circle_pts(k, SY1 + RISER / 2, 2.6, 10))
        g.ink.circle(k, SY1 + RISER / 2, 2.6, lw=1.0, amp=0)
        k += 26
    # 两头的台阶
    for sx in (SX0 - 26, SX1):
        for i in range(2):
            y = SY1 - 26 + i * 13
            g.clear(rect_pts(sx, y, 26, 13 + 6))
            g.pen("ink", 0.08).fill(rect_pts(sx, y, 26, 13))
            g.pen("ink", 0.3).fill(rect_pts(sx, y + 13, 26, 6))
            g.ink.rect(sx, y, 26, 19, lw=1.8)
    walk.block_rect(SX0 + 2, SY1 - 4, SX1 - SX0 - 4, RISER + 8)     # 台沿：从正面上不去
    walk.block_rect(SX0 - 5, SY0, 10, SY1 - SY0 - 30)                # 台侧
    walk.block_rect(SX1 - 5, SY0, 10, SY1 - SY0 - 30)
    # 台口挂的两只灯笼（上层）
    o = ctx.o
    for lx in (SX0 - 13, SX1 + 13):
        o.ink.line([(lx, -10), (lx, 30)], 1.2, amp=0)
        lan = ellipse_pts(lx, 44, 11, 14, 24)
        o.clear(lan)
        o.pen("mei", 0.9).fill(lan)
        o.ink.poly(lan, 1.8, amp=0.3)
        for dx in (-5, 0, 5):
            o.ink.line([(lx + dx, 31), (lx + dx * 1.3, 57)], 0.8, amp=0, density=0.6)
        o.ink.line([(lx, 58), (lx, 70)], 1.4, amp=0.6)


# ----------------------------------------------------------------------
# 堂座
# ----------------------------------------------------------------------

def baxian(ctx: Ctx, cx, cy, seed=0):
    """一张八仙桌（方桌）+ 南北两条长凳。cx, cy 是桌面中心。"""
    g = ctx.g
    rnd = random.Random(seed)
    w, d, h = 50, 34, 12
    x, y = cx - w / 2, cy - d / 2
    # 北边的条凳（在桌子后面，先画）
    bench(g, cx, y - 14)
    shadow(g, [(x + w, y + 6), (x + w + 10, y + 12), (x + w + 10, y + d + h + 8), (x + 8, y + d + h + 8), (x, y + d + h)], 0.16)
    g.clear(rect_pts(x, y, w, d + h))
    g.pen("ink", 0.12).fill(rect_pts(x, y, w, d))
    g.pen("ink", 0.36).fill(rect_pts(x, y + d, w, h))
    g.ink.rect(x, y, w, d, lw=2.4)
    g.ink.rect(x, y + d, w, h, lw=2.2)
    g.ink.line([(x + 5, y + d + h), (x + 4, y + d + h + 7)], 2.2)
    g.ink.line([(x + w - 5, y + d + h), (x + w - 4, y + d + h + 7)], 2.2)
    # 桌上：茶壶、两只盖碗、一碟瓜子
    tx, ty = cx - 2, cy - 4
    g.clear(ellipse_pts(tx, ty, 8, 6.5, 20))
    g.pen("qing", 0.55).fill(ellipse_pts(tx, ty, 8, 6.5, 20))
    g.ink.ellipse(tx, ty, 8, 6.5, lw=1.6)
    g.ink.dot(tx, ty - 1, 1.6)
    g.ink.line([(tx + 7, ty - 1), (tx + 13, ty - 5)], 2.0, amp=0)
    g.ink.arc(tx - 9, ty, 4, math.pi * 0.5, math.pi * 1.5, lw=1.5)
    for bx, by in ((cx - 17, cy + 8), (cx + 14, cy - 9)):
        g.clear(ellipse_pts(bx, by, 5.5, 4, 16))
        g.ink.ellipse(bx, by, 5.5, 4, lw=1.3)
        g.pen("mei").arc(bx, by, 3.6, 0.2, 2.9, lw=1.2)
    sx, sy = cx + 15, cy + 8
    g.ink.ellipse(sx, sy, 7, 4.5, lw=1.2)
    for _ in range(7):
        g.ink.dot(sx + rnd.uniform(-4, 4), sy + rnd.uniform(-2, 2), 0.9)
    bench(g, cx, y + d + h + 12)
    ctx.walk.block_rect(x - 4, y - 22, w + 8, d + h + 46)


def bench(g, cx, y, L=58):
    """条凳：一条窄板，两头露出腿。"""
    x = cx - L / 2
    shadow(g, [(x + L, y + 2), (x + L + 6, y + 5), (x + L + 6, y + 15), (x + 6, y + 15), (x, y + 12)], 0.14)
    g.clear(rect_pts(x, y, L, 12))
    g.pen("ink", 0.2).fill(rect_pts(x, y, L, 8))
    g.pen("ink", 0.4).fill(rect_pts(x, y + 8, L, 4))
    g.ink.rect(x, y, L, 12, lw=1.9)
    g.ink.line([(x, y + 8), (x + L, y + 8)], 1.2, amp=0.2)


def tables(ctx: Ctx):
    baxian(ctx, 1548, 204, seed=1)
    baxian(ctx, 1778, 200, seed=3)
    baxian(ctx, 1640, 222, seed=2)


def counter(ctx: Ctx):
    """西墙边的账柜和茶炉：大铜壶坐在炉子上，旁边一排暖壶、一摞盖碗。"""
    g = ctx.g
    x, y, w, d, h = X0 + WALL + 2, 62, 34, 70, 14
    shadow(g, [(x + w, y + 6), (x + w + 10, y + 12), (x + w + 10, y + d + h + 8), (x + 6, y + d + h + 8), (x, y + d + h)], 0.16)
    g.clear(rect_pts(x, y, w, d + h))
    g.pen("ink", 0.14).fill(rect_pts(x, y, w, d))
    g.pen("qing", 0.5).fill(rect_pts(x, y + d, w, h))
    g.ink.rect(x, y, w, d, lw=2.4)
    g.ink.rect(x, y + d, w, h, lw=2.2)
    # 算盘
    g.ink.rect(x + 6, y + 8, 22, 12, lw=1.3)
    for k in range(4):
        g.ink.line([(x + 10 + k * 5, y + 8), (x + 10 + k * 5, y + 20)], 0.8, amp=0)
        g.ink.dot(x + 10 + k * 5, y + 11 + (k % 2) * 4, 1.4)
    # 一摞盖碗
    for k in range(3):
        g.clear(ellipse_pts(x + 17, y + 44 - k * 4, 8, 4.5, 16))
        g.ink.ellipse(x + 17, y + 44 - k * 4, 8, 4.5, lw=1.3)
    # 暖壶：青、梅、青
    for k, col in enumerate(("qing", "mei", "qing")):
        bx, by = x + 8 + k * 9, y + 62
        body = rect_pts(bx - 4, by - 16, 8, 16)
        g.clear(body)
        g.pen(col, 0.85).fill(body)
        g.ink.rect(bx - 4, by - 16, 8, 16, lw=1.3)
        g.ink.rect(bx - 2.5, by - 20, 5, 4, lw=1.2, fill=True)
    ctx.walk.block_rect(x - 2, y - 4, w + 6, d + h + 8)
    # 茶炉 + 大铜壶
    kx, ky = x + 20, 172
    shadow(g, ellipse_pts(kx + 10, ky + 14, 22, 9), 0.18)
    stove = rect_pts(kx - 15, ky - 6, 30, 22)
    g.clear(stove)
    g.pen("ink", 0.5).fill(stove)
    g.ink.rect(kx - 15, ky - 6, 30, 22, lw=2.2)
    g.pen("mei").fill(rect_pts(kx - 6, ky + 6, 12, 6))      # 炉门里的火
    pot = ellipse_pts(kx, ky - 14, 15, 12, 28)
    g.clear(pot)
    g.pen("mei", 0.32).fill(pot)
    g.pen("ink", 0.12).fill(pot)
    g.ink.poly(pot, 2.2, amp=0.3)
    g.ink.line([(kx - 9, ky - 24), (kx, ky - 30), (kx + 9, ky - 24)], 2.0, amp=0.2)   # 提梁
    g.ink.line([(kx + 13, ky - 16), (kx + 25, ky - 26), (kx + 29, ky - 24)], 2.6, amp=0.2)  # 长嘴
    ctx.walk.block_rect(kx - 18, ky - 30, 50, 50)


# ----------------------------------------------------------------------
# 门口
# ----------------------------------------------------------------------

def door(ctx: Ctx):
    g, o = ctx.g, ctx.o
    d0, d1 = DOOR
    # 门槛 + 两扇敞开的门板（朝里开，贴着墙）
    g.clear(rect_pts(d0, YS - WALL, d1 - d0, WALL + 10))
    g.pen("ink", 0.14).fill(rect_pts(d0, YS - WALL, d1 - d0, WALL))
    g.ink.line([(d0, YS - WALL), (d0, YS + 4)], 3)
    g.ink.line([(d1, YS - WALL), (d1, YS + 4)], 3)
    g.ink.line([(d0, YS), (d1, YS)], 1.6, density=0.7)
    for hx, sd in ((d0, -1), (d1, 1)):
        leaf = [(hx, YS - WALL), (hx + sd * 6, YS - WALL - 24), (hx + sd * 10, YS - WALL - 24), (hx + sd * 4, YS - WALL)]
        g.clear(leaf)
        g.pen("qing", 0.7).fill(leaf)
        g.ink.poly(leaf, 1.6, amp=0.2)
    # 门外两级石阶接到街角
    g.clear(rect_pts(d0 - 4, YS, d1 - d0 + 8, 10))
    g.pen("ink", 0.08).fill(rect_pts(d0 - 4, YS, d1 - d0 + 8, 10))
    g.ink.rect(d0 - 4, YS, d1 - d0 + 8, 10, lw=1.8)
    # 门里的水牌
    bx, by = 1838, 232
    shadow(g, [(bx - 16, by + 26), (bx + 20, by + 26), (bx + 36, by + 35), (bx, by + 35)], 0.16)
    g.ink.line([(bx - 19, by + 27), (bx - 15, by - 24)], 2.2)
    g.ink.line([(bx + 19, by + 27), (bx + 15, by - 24)], 2.2)
    board = rect_pts(bx - 17, by - 26, 34, 50)
    g.clear(board)
    g.ink.fill(board)
    g.ink.rect(bx - 17, by - 26, 34, 50, lw=2.2)
    _knockout_text(g, "ink", "今日", bx, by - 16, 9, False)
    _knockout_text(g, "ink", "花茶", bx, by - 3, 10, False)
    _knockout_text(g, "ink", "评书", bx, by + 11, 10, False)
    ctx.walk.block_rect(bx - 20, by - 4, 44, 36)
    # 门楣上的匾（上层）：人从匾下面走进去
    sign(o, (d0 + d1) / 2, YS - 6, "茶社", "qing", size=17, pad=8)
    # 门边挂的幌子：一串梅色的小木牌
    hx = d1 + 10
    o.ink.line([(hx, YS - 4), (hx, YS + 8)], 1.4, amp=0)
    for k in range(3):
        tag = rect_pts(hx - 6, YS + 8 + k * 15, 12, 12)
        o.clear(tag)
        o.pen("mei", 0.9).fill(tag)
        o.ink.rect(hx - 6, YS + 8 + k * 15, 12, 12, lw=1.2)
