"""红砖楼：楼顶 + 三楼剖面（青家 / 楼道 / 梅家）。

外墙 x 120~1360，y 20~722。楼顶揭开一半：北边是楼顶平台，往南是剖开的三楼。
屋里按"老天津单元房"画：墙裙刷绿漆、白墙、暖气片、五斗柜、写字台、圆桌、双人床、脸盆架。
楼道正中，北头上楼顶，南头下楼通到街上。
"""
import math
import random

from common import Ctx, circle_pts, ellipse_pts, rect_pts, shadow, spot, stool

X0, X1 = 120, 1360          # 外墙外皮
Y0, YCUT0, YCUT1, YS = 20, 222, 258, 722   # 楼顶北墙、剖切带、南墙外皮
WALL = 16                   # 外墙厚
HALL = (690, 790)           # 楼道两侧墙中线
FACE = 52                   # 北墙内立面（看得到的那一截墙）的高度


def draw(ctx: Ctx):
    roof(ctx)
    cut_band(ctx)
    for role in ("qing", "mei"):
        home(ctx, role)
    hallway(ctx)
    walls(ctx)


# ----------------------------------------------------------------------
# 墙
# ----------------------------------------------------------------------

def brick_wall(g, pts_rect, lw=2.6):
    x, y, w, h = pts_rect
    g.clear(rect_pts(x, y, w, h))
    g.pen("mei", 0.62).fill(rect_pts(x, y, w, h))
    if w > 10 and h > 10:
        g.ink.bricks(x, y, w, h, bw=18, bh=8, lw=0.8, density=0.35)
    g.ink.rect(x, y, w, h, lw=lw, amp=0.5)


def walls(ctx: Ctx):
    g, walk = ctx.g, ctx.walk
    # 外墙（剖到的部分画成红砖实体）
    brick_wall(g, (X0, YCUT1, WALL, YS - YCUT1))
    brick_wall(g, (X1 - WALL, YCUT1, WALL, YS - YCUT1))
    # 南墙，楼门口留洞
    brick_wall(g, (X0, YS - 22, 705 - X0, 22))
    brick_wall(g, (775, YS - 22, X1 - 775, 22))
    # 南墙上的窗洞（剖切）：窗台用纸色，玻璃一条青线
    for wx in (220, 420, 920, 1140):
        g.clear(rect_pts(wx, YS - 22, 90, 22))
        g.ink.rect(wx, YS - 22, 90, 22, lw=2)
        g.qing.line([(wx + 4, YS - 11), (wx + 86, YS - 11)], 2.4, amp=0.2)
    # 楼道两侧的内墙，门洞在 y 440~500
    for cx in HALL:
        brick_wall(g, (cx - 6, YCUT1, 12, 440 - YCUT1), lw=2.2)
        brick_wall(g, (cx - 6, 500, 12, YS - 22 - 500), lw=2.2)
    # 楼门：门框 + 门牌
    g.ink.line([(705, YS - 22), (705, YS + 6)], 3)
    g.ink.line([(775, YS - 22), (775, YS + 6)], 3)
    g.pen("ink", 0.2).fill(rect_pts(706, YS - 22, 68, 22))
    plate_x, plate_y = 800, YS + 2
    g.clear(rect_pts(plate_x, plate_y, 64, 18))
    g.qing.rect(plate_x, plate_y, 64, 18, lw=1.6, fill=True)
    from common import _knockout_text
    _knockout_text(g, "qing", "3号楼", plate_x + 32, plate_y + 9, 14, False)
    walk.add_rect(708, YS - 30, 64, 40)


def cut_band(ctx: Ctx):
    """楼顶楼板的剖切面：墨排线 + 一条粗线。楼道那里是楼梯口。"""
    g = ctx.g
    for x, w in ((X0, HALL[0] + 10 - X0), (HALL[1] - 10, X1 - HALL[1] + 10)):
        pts = rect_pts(x, YCUT0, w, YCUT1 - YCUT0)
        g.clear(pts)
        g.pen("ink", 0.28).fill(pts)
        g.ink.hatch(pts, 45, 7, 1.3)
        g.ink.line([(x, YCUT0), (x + w, YCUT0)], 3.4)
        g.ink.line([(x, YCUT1), (x + w, YCUT1)], 3.4)
    # 剖切线上的"揭开"标记：两端各一个小折断符号
    for x in (X0 - 4, X1 + 4):
        g.ink.line([(x - 12, YCUT0 + 6), (x, YCUT0 + 14), (x - 6, YCUT0 + 22), (x + 6, YCUT0 + 30)], 2)


# ----------------------------------------------------------------------
# 楼顶
# ----------------------------------------------------------------------

def roof(ctx: Ctx):
    g, o, walk = ctx.g, ctx.o, ctx.walk
    rnd = random.Random(42)
    inner = (X0 + WALL, Y0 + WALL, X1 - X0 - 2 * WALL, YCUT0 - Y0 - WALL)
    ix, iy, iw, ih = inner
    walk.add_rect(ix + 6, iy + 6, iw - 12, ih - 4)
    # 隔热砖铺的屋面：淡墨 + 方格
    g.pen("ink", 0.08).fill(rect_pts(*inner))
    x = ix
    while x < ix + iw:
        g.ink.line([(x, iy), (x, iy + ih)], 1.0, amp=0.3, density=0.3)
        x += 48
    y = iy
    while y < iy + ih:
        g.ink.line([(ix, y), (ix + iw, y)], 1.0, amp=0.3, density=0.3)
        y += 48
    # 女儿墙（北、东、西）
    for r in ((X0, Y0, X1 - X0, WALL), (X0, Y0, WALL, YCUT0 - Y0), (X1 - WALL, Y0, WALL, YCUT0 - Y0)):
        brick_wall(g, r, 2.4)
    # 女儿墙的影子
    shadow(g, rect_pts(ix, iy, iw, 10), 0.14)
    shadow(g, rect_pts(ix, iy, 10, ih), 0.12)

    # --- 鸽子笼（楼顶放鸽子的地方）---
    px, py = spot("roof_pigeon")
    cx, cy, cw, cd = px - 70, iy + 4, 140, 44
    shadow(g, rect_pts(cx + 10, cy + 12, cw, cd + 20), 0.16)
    g.clear(rect_pts(cx, cy, cw, cd + 22))
    g.pen("ink", 0.12).fill(rect_pts(cx, cy, cw, cd))          # 顶
    g.ink.rect(cx, cy, cw, cd, lw=2.4)
    g.ink.hatch(rect_pts(cx, cy, cw, cd), 0, 6, 0.9, density=0.5)
    g.pen("qing", 0.55).fill(rect_pts(cx, cy + cd, cw, 22))    # 正面：青漆木板 + 铁丝网
    g.ink.rect(cx, cy + cd, cw, 22, lw=2.4)
    g.ink.hatch(rect_pts(cx + 30, cy + cd + 3, cw - 60, 16), 45, 5, 0.8)
    g.ink.hatch(rect_pts(cx + 30, cy + cd + 3, cw - 60, 16), -45, 5, 0.8)
    for k in (0, 1):  # 两扇小门
        g.ink.rect(cx + 6 + k * (cw - 30), cy + cd + 4, 18, 14, lw=1.6)
    walk.block_rect(cx - 4, cy - 4, cw + 8, cd + 26)
    for i in range(6):
        ctx.anchor("pigeon", cx + 20 + i * 20, cy + 10 + (i % 2) * 14)
    ctx.anchor("pigeon_home", px, cy + 20)
    # 鸽哨挂在笼边
    g.ink.circle(cx + cw + 10, cy + 30, 5, lw=1.6)

    # --- 晾衣绳：两根杆子，绳上的床单在上层，会飘（引擎做动画） ---
    for (ax, bx, ly) in ((200, 600, 78), (230, 560, 150)):
        g.ink.circle(ax, ly + 26, 5, lw=2, fill=True)
        g.ink.circle(bx, ly + 26, 5, lw=2, fill=True)
        walk.block_circle(ax, ly + 26, 7)
        walk.block_circle(bx, ly + 26, 7)
        o.ink.line([(ax, ly + 26), (ax, ly)], 3)
        o.ink.line([(bx, ly + 26), (bx, ly)], 3)
        pts = [(ax + (bx - ax) * t / 20, ly + 10 * 4 * (t / 20) * (1 - t / 20)) for t in range(21)]
        o.ink.line(pts, 1.4, amp=0.1)
    sheets = [(250, 82, 66, "qing", 0.75, "stripe"), (340, 86, 58, "paper", 0, "flower"), (430, 85, 70, "mei", 0.7, "plain"),
              (270, 155, 48, "ink", 0.18, "plain"), (350, 158, 40, "mei", 0.35, "stripe"), (450, 156, 54, "qing", 0.4, "plain")]
    for sx, sy, sw, col, d, pat in sheets:
        sh = 56 if sy < 120 else 40
        pts = [(sx, sy), (sx + sw, sy), (sx + sw + 3, sy + sh), (sx - 2, sy + sh - 3)]
        o.clear(pts)
        if col != "paper":
            o.pen(col, d).fill(pts)
        o.ink.poly(pts, 1.8)
        if pat == "stripe":
            for k in range(1, 4):
                o.ink.line([(sx + sw * k / 4, sy + 2), (sx + sw * k / 4 + 1, sy + sh - 2)], 1.2, density=0.6)
        elif pat == "flower":
            for k in range(3):
                fx, fy = sx + 14 + k * 16, sy + 16 + (k % 2) * 18
                for a in range(5):
                    o.mei.dot(fx + 4 * math.cos(a * 1.257), fy + 4 * math.sin(a * 1.257), 2.4)
        ctx.anchor("laundry", sx + sw / 2, sy, w=sw, h=sh)
        # 床单在地上的影子
        shadow(g, [(sx + 18, sy + 34), (sx + sw + 22, sy + 34), (sx + sw + 28, sy + 46), (sx + 22, sy + 46)], 0.12)

    # --- 水箱 ---
    tx, ty, tw, td = 1180, iy + 6, 110, 56
    shadow(g, rect_pts(tx + 12, ty + 14, tw, td + 26), 0.18)
    g.clear(rect_pts(tx, ty, tw, td + 26))
    g.pen("ink", 0.18).fill(rect_pts(tx, ty, tw, td))
    g.ink.rect(tx, ty, tw, td, lw=2.6)
    g.ink.circle(tx + 30, ty + 26, 12, lw=2)
    g.pen("ink", 0.4).fill(rect_pts(tx, ty + td, tw, 26))
    g.ink.rect(tx, ty + td, tw, 26, lw=2.6)
    for k in range(1, 5):
        g.ink.line([(tx + k * tw / 5, ty + td), (tx + k * tw / 5, ty + td + 26)], 1.2)
    g.ink.line([(tx - 12, ty + 10), (tx - 12, ty + td + 26)], 2)  # 爬梯
    walk.block_rect(tx - 16, ty - 4, tw + 22, td + 32)

    # --- 电视天线（上层）---
    for ax, ay in ((990, 70), (1310, 160)):
        g.ink.dot(ax, ay, 4)
        o.ink.line([(ax, ay), (ax, ay - 90)], 2.6)
        for k, L in enumerate((46, 36, 26)):
            yy = ay - 90 + k * 14
            o.ink.line([(ax - L / 2, yy), (ax + L / 2, yy)], 2.0)
        o.mei.line([(ax - 6, ay - 50), (ax + 6, ay - 50)], 3)  # 一圈红布条
        walk.block_circle(ax, ay, 6)

    # --- 凉席 + 小板凳 + 蒲扇（夏天晚上上来乘凉）---
    mx, my = 900, 150
    pts = rect_pts(mx, my, 110, 52)
    g.clear(pts)
    g.pen("qing", 0.22).fill(pts)
    g.ink.rect(mx, my, 110, 52, lw=2)
    g.ink.hatch(pts, 90, 5, 0.8, density=0.6)
    stool(g, mx + 140, my + 24, "mei")
    g.ink.ellipse(mx + 30, my + 26, 14, 18, lw=1.6)  # 蒲扇
    g.ink.line([(mx + 30, my + 44), (mx + 34, my + 58)], 2)

    # --- 一排花盆和葱（沿北墙）---
    for i, kx in enumerate(range(860, 1150, 42)):
        g.clear(ellipse_pts(kx, iy + 14, 13, 8))
        g.mei.ellipse(kx, iy + 14, 13, 8, lw=2, fill=True, density=0.7)
        if i % 2 == 0:
            for a in (-0.5, 0, 0.5):
                g.qing.line([(kx, iy + 12), (kx + a * 16, iy - 2)], 2.2)
        else:
            g.qing.circle(kx, iy + 8, 7, lw=1.8, fill=True, density=0.6)
            g.mei.dot(kx + 2, iy + 6, 2.6)
        walk.block_circle(kx, iy + 14, 10)

    # 楼顶上楼梯间的出口（楼道正北）
    ox, oy = HALL[0] + 10, YCUT0 - 26
    g.ink.line([(ox, oy), (ox, YCUT0)], 2.6)
    g.ink.line([(HALL[1] - 10, oy), (HALL[1] - 10, YCUT0)], 2.6)
    g.ink.line([(ox, oy), (HALL[1] - 10, oy)], 1.4, dash=[6, 6])
    walk.add_rect(HALL[0] + 14, oy, HALL[1] - HALL[0] - 28, YCUT1 - oy + 6)
    ctx.g.ink.text("楼顶", X0 + 70, iy + 24, 22, density=0.75)


# ----------------------------------------------------------------------
# 屋里
# ----------------------------------------------------------------------

def furn(g, x, y, w, d, h, top=("ink", 0.10), front=("ink", 0.30), lw=2.4):
    """一件家具：顶面 (x,y,w,d) + 朝南的正面（高 h*0.5）+ 右下的影子。返回正面矩形。"""
    fh = h * 0.5
    shadow(g, [(x + w, y + 6), (x + w + fh * 0.6, y + 6 + fh * 0.4), (x + w + fh * 0.6, y + d + fh + fh * 0.4), (x + fh * 0.6, y + d + fh + fh * 0.4), (x, y + d + fh)], 0.15)
    g.clear(rect_pts(x, y, w, d + fh))
    if top:
        g.pen(top[0], top[1]).fill(rect_pts(x, y, w, d))
    if front:
        g.pen(front[0], front[1]).fill(rect_pts(x, y + d, w, fh))
    g.ink.rect(x, y, w, d, lw=lw)
    g.ink.rect(x, y + d, w, fh, lw=lw)
    return (x, y + d, w, fh)


def home(ctx: Ctx, role):
    g, walk = ctx.g, ctx.walk
    mirror = role == "mei"
    rx0, rx1 = (X0 + WALL, HALL[0] - 6) if not mirror else (HALL[1] + 6, X1 - WALL)
    fy0 = YCUT1 + FACE  # 地面从这里开始

    def mx(x, w=0):
        """以青家为准写坐标，梅家左右镜像。"""
        return x if not mirror else (X0 + X1) - x - w

    # 地面
    floor = rect_pts(rx0, YCUT1, rx1 - rx0, YS - 22 - YCUT1)
    if role == "qing":
        g.pen("mei", 0.14).fill(floor)  # 刷了红漆的木地板
        y = fy0
        while y < YS - 22:
            g.ink.line([(rx0, y), (rx1, y)], 1.0, amp=0.3, density=0.35)
            off = 0 if int((y - fy0) / 22) % 2 == 0 else 60
            for xx in range(int(rx0 + off), int(rx1), 120):
                g.ink.line([(xx, y), (xx, y + 22)], 1.0, amp=0.2, density=0.35)
            y += 22
    else:
        g.pen("ink", 0.07).fill(floor)  # 水磨石
        rnd = random.Random(9)
        for _ in range(420):
            xx, yy = rnd.uniform(rx0, rx1), rnd.uniform(fy0, YS - 22)
            g.pen(rnd.choice(["ink", "qing", "mei"])).dot(xx, yy, rnd.uniform(1.0, 2.2), density=0.6)
        for gx in range(int(rx0) + 90, int(rx1), 90):
            g.ink.line([(gx, fy0), (gx, YS - 22)], 1.0, amp=0, density=0.4)
    walk.add_rect(rx0 + 4, fy0 + 2, rx1 - rx0 - 8, YS - 22 - fy0 - 4)

    # 北墙内立面：上白下绿（墙裙），一扇窗，暖气片
    face = rect_pts(rx0, YCUT1, rx1 - rx0, FACE)
    g.clear(face)
    g.pen("qing", 0.42).fill(rect_pts(rx0, YCUT1 + FACE * 0.55, rx1 - rx0, FACE * 0.45))
    g.ink.line([(rx0, YCUT1 + FACE * 0.55), (rx1, YCUT1 + FACE * 0.55)], 1.6)
    g.ink.line([(rx0, fy0), (rx1, fy0)], 2.6)
    # 窗
    wx = mx(350, 120)
    g.clear(rect_pts(wx, YCUT1 + 4, 120, 30))
    g.pen("qing", 0.2).fill(rect_pts(wx, YCUT1 + 4, 120, 30))
    g.ink.rect(wx, YCUT1 + 4, 120, 30, lw=2.2)
    g.ink.line([(wx + 60, YCUT1 + 4), (wx + 60, YCUT1 + 34)], 1.8)
    g.ink.line([(wx, YCUT1 + 19), (wx + 120, YCUT1 + 19)], 1.2)
    # 窗花（梅色，剪纸）
    for k in (0, 1):
        fx = wx + 30 + k * 60
        g.mei.circle(fx, YCUT1 + 19, 8, lw=1.8, fill=True, density=0.85)
        g.clear(circle_pts(fx, YCUT1 + 19, 3, 10), colors=["mei"])
    # 暖气片：窗下一排竖条
    rx = wx + 10
    for k in range(9):
        g.clear(rect_pts(rx + k * 11, fy0 - 18, 8, 18))
        g.ink.rect(rx + k * 11, fy0 - 18, 8, 18, lw=1.4, fill=True, density=0.2)
    ctx.anchor("radiator", wx + 60, fy0 + 4, role=role)
    # 挂历 / 奖状
    cx = mx(560, 34)
    g.clear(rect_pts(cx, YCUT1 + 4, 34, 26))
    g.ink.rect(cx, YCUT1 + 4, 34, 26, lw=1.6)
    g.mei.rect(cx + 3, YCUT1 + 7, 28, 6, lw=0, fill=True, stroke=False)
    for k in range(3):
        g.ink.line([(cx + 5, YCUT1 + 17 + k * 4), (cx + 29, YCUT1 + 17 + k * 4)], 1, density=0.6)
    if role == "qing":
        ax = mx(600, 50)
        g.clear(rect_pts(ax, YCUT1 + 6, 50, 20))
        g.mei.rect(ax, YCUT1 + 6, 50, 20, lw=1.6)
        g.mei.text("奖状", ax + 25, YCUT1 + 16, 12)

    # --- 写字台（desk spot 的北边）---
    dx, dy = spot("desk_" + role)
    fr = furn(g, dx - 62, fy0 - 10, 124, 34, 30, top=("qing" if role == "qing" else "mei", 0.32), front=("ink", 0.25))
    g.ink.line([(fr[0] + fr[2] / 2, fr[1] + 3), (fr[0] + fr[2] / 2, fr[1] + fr[3] - 3)], 1.4)
    for k in (0.25, 0.75):
        g.ink.dot(fr[0] + fr[2] * k, fr[1] + fr[3] / 2, 1.8)
    # 台灯 + 一摞书 + 作业本
    lx = dx + (36 if not mirror else -36)
    g.ink.circle(lx, fy0 + 2, 6, lw=1.6)
    g.ink.line([(lx, fy0 + 2), (lx - 6, fy0 - 16)], 2)
    g.mei.ellipse(lx - 8, fy0 - 18, 11, 6, lw=1.8, fill=True, density=0.9)
    for k in range(3):
        g.clear(rect_pts(dx - 46, fy0 + 8 - k * 5, 30, 5))
        g.pen(["qing", "mei", "ink"][k], 0.6).rect(dx - 46, fy0 + 8 - k * 5, 30, 5, lw=1.2, fill=True)
    g.clear(rect_pts(dx - 8, fy0 + 4, 26, 18))
    g.ink.rect(dx - 8, fy0 + 4, 26, 18, lw=1.4)
    g.ink.line([(dx - 4, fy0 + 10), (dx + 14, fy0 + 10)], 1, density=0.6)
    walk.block_rect(fr[0] - 4, fy0 - 10, fr[2] + 8, 34 + 15 + 6)
    # 椅子在人身后
    stool(g, dx, dy + 34, "ink", 12)

    # --- 圆桌 + 饭菜 ---
    tx, ty = spot("table_" + role)
    tcx, tcy = tx, ty - 46
    shadow(g, ellipse_pts(tcx + 14, tcy + 16, 54, 26), 0.15)
    g.clear(ellipse_pts(tcx, tcy, 52, 26))
    g.pen("ink", 0.10).fill(ellipse_pts(tcx, tcy, 52, 26))
    g.ink.ellipse(tcx, tcy, 52, 26, lw=2.4)
    g.ink.line([(tcx + 52 * math.cos(a * math.pi / 16), tcy + 7 + 26 * math.sin(a * math.pi / 16)) for a in range(1, 16)], 1.6)
    g.ink.line([(tcx - 30, tcy + 26), (tcx - 32, tcy + 40)], 2.4)
    g.ink.line([(tcx + 30, tcy + 26), (tcx + 32, tcy + 40)], 2.4)
    # 两只碗一盘菜
    for bx, col in ((tcx - 22, "qing"), (tcx + 20, "mei")):
        g.clear(ellipse_pts(bx, tcy - 4, 11, 6))
        g.ink.ellipse(bx, tcy - 4, 11, 6, lw=1.6)
        g.pen(col).arc(bx, tcy - 4, 9, 0.3, 2.8, lw=1.6)
    g.clear(ellipse_pts(tcx, tcy + 8, 16, 7))
    g.ink.ellipse(tcx, tcy + 8, 16, 7, lw=1.6)
    g.pen("qing", 0.7).fill(ellipse_pts(tcx, tcy + 7, 10, 4))
    g.ink.line([(tcx + 26, tcy + 10), (tcx + 44, tcy + 2)], 1.4)  # 筷子
    g.ink.line([(tcx + 28, tcy + 13), (tcx + 46, tcy + 5)], 1.4)
    walk.block_poly(ellipse_pts(tcx, tcy + 6, 54, 30))
    ctx.anchor("window_light", tcx, tcy)  # 晚上饭桌上那盏灯
    stool(g, tcx - 70, tcy + 6, "ink")
    stool(g, tcx + 70, tcy + 6, "ink")
    walk.block_circle(tcx - 70, tcy + 8, 12)
    walk.block_circle(tcx + 70, tcy + 8, 12)

    # --- 五斗柜 + 电视 / 收音机 ---
    kx = mx(510, 120)
    if role == "qing":
        kx = mx(470, 110)
    fr = furn(g, kx, fy0 - 12, 110, 30, 50, top=("ink", 0.14), front=("mei", 0.35))
    for k in range(1, 3):
        g.ink.line([(fr[0], fr[1] + fr[3] * k / 3), (fr[0] + fr[2], fr[1] + fr[3] * k / 3)], 1.2)
    walk.block_rect(kx - 4, fy0 - 12, 118, 30 + 25 + 4)
    if role == "qing":
        # 电视（带蕾丝罩）
        g.clear(rect_pts(kx + 22, fy0 - 26, 60, 34))
        g.ink.rect(kx + 22, fy0 - 26, 60, 34, lw=2.2)
        g.pen("qing", 0.3).fill(rect_pts(kx + 28, fy0 - 22, 40, 26))
        g.ink.circle(kx + 75, fy0 - 14, 3, lw=1.2)
        g.ink.line([(kx + 30, fy0 - 26), (kx + 18, fy0 - 44)], 1.6)
        g.ink.line([(kx + 60, fy0 - 26), (kx + 74, fy0 - 46)], 1.6)
        for k in range(6):
            g.ink.arc(kx + 26 + k * 10, fy0 - 26, 5, 0, math.pi, lw=1.0)
    else:
        # 收音机（听相声）+ 一盆君子兰
        g.clear(rect_pts(kx + 14, fy0 - 18, 52, 24))
        g.mei.rect(kx + 14, fy0 - 18, 52, 24, lw=2, fill=True, density=0.75)
        g.ink.rect(kx + 14, fy0 - 18, 52, 24, lw=2)
        g.clear(circle_pts(kx + 30, fy0 - 6, 7, 14), colors=["mei"])
        g.ink.circle(kx + 30, fy0 - 6, 7, lw=1.4)
        g.ink.hatch(circle_pts(kx + 30, fy0 - 6, 6, 14), 0, 3, 0.8)
        g.ink.line([(kx + 58, fy0 - 18), (kx + 70, fy0 - 42)], 1.6)
        ctx.anchor("radio", kx + 40, fy0 - 20)
        g.clear(ellipse_pts(kx + 90, fy0 - 2, 10, 6))
        g.mei.ellipse(kx + 90, fy0 - 2, 10, 6, lw=1.6, fill=True, density=0.6)
        for a in (-1.0, -0.5, 0.0, 0.5, 1.0):
            g.qing.line([(kx + 90, fy0 - 4), (kx + 90 + a * 18, fy0 - 26 + abs(a) * 8)], 3.2)
        g.mei.dot(kx + 90, fy0 - 26, 4)

    # --- 双人床（床就在 sleep 点上）---
    bx, by = spot("bed_" + role)
    bw, bd = 190, 120
    x0 = (bx - 100) if not mirror else (bx + 100 - bw)
    x0 = max(x0, rx0 + 6) if not mirror else min(x0, rx1 - 6 - bw)
    y0 = by - 66
    shadow(g, rect_pts(x0 + 12, y0 + 12, bw, bd + 16), 0.15)
    g.clear(rect_pts(x0, y0, bw, bd + 16))
    g.pen("ink", 0.12).fill(rect_pts(x0, y0 + bd, bw, 16))
    g.ink.rect(x0, y0 + bd, bw, 16, lw=2.2)
    g.ink.rect(x0, y0, bw, bd, lw=2.4)
    # 床头
    hx = x0 if not mirror else x0 + bw - 14
    g.pen("ink", 0.4).fill(rect_pts(hx, y0 - 4, 14, bd + 8))
    g.ink.rect(hx, y0 - 4, 14, bd + 8, lw=2.2)
    # 枕头
    px0 = x0 + 20 if not mirror else x0 + bw - 20 - 34
    for k in (0, 1):
        g.clear(rect_pts(px0, y0 + 12 + k * 52, 34, 40))
        g.ink.rect(px0, y0 + 12 + k * 52, 34, 40, lw=1.8)
        g.pen("qing" if role == "qing" else "mei", 0.25).fill(rect_pts(px0 + 4, y0 + 16 + k * 52, 26, 32))
    # 被子：自己的颜色，格子
    qx = x0 + 64 if not mirror else x0 + 10
    qpts = rect_pts(qx, y0 + 6, bw - 76, bd - 12)
    g.clear(qpts)
    col = "qing" if role == "qing" else "mei"
    g.pen(col, 0.6).fill(qpts)
    g.ink.poly(qpts, 2)
    for k in range(1, 4):
        g.pen(col).line([(qx + (bw - 76) * k / 4, y0 + 6), (qx + (bw - 76) * k / 4, y0 + bd - 6)], 1.6)
    g.pen(col).line([(qx, y0 + bd / 2), (qx + bw - 76, y0 + bd / 2)], 1.6)

    # --- 脸盆架（wash spot 的南边）---
    wx, wy = spot("basin_" + role)
    sx, sy = wx, wy + 44
    shadow(g, ellipse_pts(sx + 10, sy + 8, 30, 12), 0.15)
    for a in (0, 2.1, 4.2):
        g.ink.line([(sx, sy), (sx + 24 * math.cos(a), sy + 10 * math.sin(a) + 6)], 2.4)
    g.clear(ellipse_pts(sx, sy - 4, 26, 12))
    g.ink.ellipse(sx, sy - 4, 26, 12, lw=2.4)
    g.pen("qing", 0.25).fill(ellipse_pts(sx, sy - 3, 20, 8))
    g.mei.dot(sx - 6, sy - 4, 3)  # 搪瓷盆底的大红花
    g.mei.dot(sx + 2, sy - 2, 2.4)
    # 毛巾、暖壶
    g.ink.line([(sx - 26, sy - 14), (sx - 26, sy + 8)], 2)
    g.clear(rect_pts(sx - 34, sy - 14, 16, 20))
    g.pen(col, 0.5).rect(sx - 34, sy - 14, 16, 20, lw=1.6, fill=True)
    hx2 = sx + 46 if not mirror else sx - 46
    g.clear(rect_pts(hx2 - 8, sy - 26, 16, 32))
    g.pen("mei" if role == "qing" else "qing", 0.8).rect(hx2 - 8, sy - 26, 16, 32, lw=1.8, fill=True)
    g.ink.rect(hx2 - 5, sy - 32, 10, 6, lw=1.6, fill=True)
    walk.block_rect(sx - 38, sy - 20, 100 if not mirror else 40, 34) if not mirror else walk.block_rect(sx - 62, sy - 20, 100, 34)

    # --- 衣柜（贴外墙）---
    wx0 = rx0 + 2 if not mirror else rx1 - 2 - 44
    fr = furn(g, wx0, fy0 + 70, 44, 120, 70, top=("ink", 0.14), front=None)
    g.ink.line([(wx0 + 22, fy0 + 74), (wx0 + 22, fy0 + 186)], 1.2)
    g.pen("qing", 0.25).fill(rect_pts(wx0 + 6, fy0 + 80, 10, 100))  # 穿衣镜
    walk.block_rect(wx0 - 2, fy0 + 66, 50, 160)

    # 地上的小东西
    if role == "qing":
        # 鱼缸（在五斗柜旁边的小方凳上）
        fx, fy = mx(620, 0), fy0 + 50
        stool(g, fx, fy + 8, "ink", 14)
        g.clear(rect_pts(fx - 18, fy - 22, 36, 26))
        g.pen("qing", 0.35).fill(rect_pts(fx - 18, fy - 14, 36, 18))
        g.ink.rect(fx - 18, fy - 22, 36, 26, lw=1.8)
        g.mei.line([(fx - 6, fy - 6), (fx + 2, fy - 8), (fx + 6, fy - 4), (fx + 2, fy - 2), (fx - 6, fy - 6)], 2)
        walk.block_circle(fx, fy, 18)
        ctx.anchor("fish", fx, fy - 8)
    else:
        # 缝纫机
        fx = mx(575, 80)
        furn(g, fx, fy0 + 40, 80, 34, 36, top=("ink", 0.3), front=("ink", 0.15))
        g.ink.arc(fx + 40, fy0 + 46, 14, math.pi, math.tau, lw=2.4)
        g.ink.circle(fx + 66, fy0 + 52, 5, lw=1.6)
        walk.block_rect(fx - 4, fy0 + 36, 88, 62)
    # 门口的鞋
    door_x = rx1 - 30 if not mirror else rx0 + 30
    for k, c in enumerate(("ink", "mei" if role == "mei" else "qing")):
        g.pen(c, 0.7).ellipse(door_x - 8 + k * 14, 530 + k * 4, 5, 10, lw=1.4, fill=True)
    # 房间名
    g.pen(col).text("青家" if role == "qing" else "梅家", (rx0 + 56) if not mirror else (rx1 - 56), YS - 50, 24, density=0.8)


# ----------------------------------------------------------------------
# 楼道
# ----------------------------------------------------------------------

def hallway(ctx: Ctx):
    g, walk = ctx.g, ctx.walk
    x0, x1 = HALL[0] + 6, HALL[1] - 6
    floor = rect_pts(x0, YCUT1 - 4, x1 - x0, YS - YCUT1 + 4)
    g.pen("ink", 0.16).fill(floor)
    walk.add_rect(x0 + 2, YCUT1 - 4, x1 - x0 - 4, YS - 22 - YCUT1 + 4)
    # 两扇门：门洞 + 半开的门扇（推开到楼道里）
    for side, wx in ((-1, HALL[0]), (1, HALL[1])):
        g.clear(rect_pts(wx - 8, 440, 16, 60))
        g.pen("ink", 0.3).fill(rect_pts(wx - 8, 440, 16, 60))
        walk.add_rect(wx - 20, 446, 40, 48)
        # 门扇：门轴在门洞北端，门推开到楼道里，虚线画开门的弧
        a_open = math.pi / 2 + side * 0.95
        g.ink.line([(wx, 440), (wx + 56 * math.cos(a_open), 440 + 56 * math.sin(a_open))], 3.4, amp=0)
        n = 12
        arc = [(wx + 56 * math.cos(math.pi / 2 + (a_open - math.pi / 2) * t / n), 440 + 56 * math.sin(math.pi / 2 + (a_open - math.pi / 2) * t / n)) for t in range(n + 1)]
        g.ink.line(arc, 1.0, amp=0, dash=[3, 4], density=0.7)
        # 春联的一角
        g.clear(rect_pts(wx - 6 + side * 10, 380, 9, 52))
        g.mei.rect(wx - 6 + side * 10, 380, 9, 52, lw=1, fill=True)
        # 门牌号
        g.clear(rect_pts(wx + side * 16 - 10, 426, 20, 12))
        g.ink.rect(wx + side * 16 - 10, 426, 20, 12, lw=1.2)
        g.ink.text("301" if side < 0 else "302", wx + side * 16, 432, 9)
    # 北头：上楼顶的楼梯（台阶向北收窄）
    for k in range(9):
        y = YCUT1 - 2 + k * 11
        g.ink.line([(x0 + 2, y), (x1 - 2, y)], 1.8, amp=0.3)
    g.ink.line([(x0 + 2, YCUT1 - 2), (x0 + 2, YCUT1 + 88)], 2.4)
    g.ink.text("上楼顶", (x0 + x1) / 2, YCUT1 + 104, 14, density=0.7)
    # 南头：下楼的楼梯
    for k in range(11):
        y = 560 + k * 12
        g.ink.line([(x0 + 2, y), (x1 - 2, y)], 1.8, amp=0.3)
    g.ink.line([(x1 - 22, 560), (x1 - 22, 690)], 2.2)  # 扶手
    g.ink.text("下楼", (x0 + x1) / 2 - 10, 546, 14, density=0.7)
    # 楼层号、墙上的"小广告"、一辆靠墙的自行车把手、一盏声控灯
    g.ink.text("3F", (x0 + x1) / 2, 395, 22, density=0.55)
    g.clear(circle_pts((x0 + x1) / 2, 520, 9, 16))
    g.ink.circle((x0 + x1) / 2, 520, 9, lw=1.6)
    ctx.anchor("hall_lamp", (x0 + x1) / 2, 520)
    # 楼道里的白菜（冬储大白菜，天津楼道一景）
    for k in range(2):
        cx, cy = x0 + 16 + k * 18, 640 + k * 6
        g.clear(ellipse_pts(cx, cy, 10, 16))
        g.pen("qing", 0.45).fill(ellipse_pts(cx, cy - 4, 9, 10))
        g.ink.ellipse(cx, cy, 10, 16, lw=1.6)
        g.ink.line([(cx, cy - 12), (cx, cy + 12)], 1)
    walk.block_rect(x0, 620, 40, 40)
