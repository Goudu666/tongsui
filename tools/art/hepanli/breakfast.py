"""街角的早点铺 + 东边通向海河的街角（报刊亭）。

范围：x 1440~1900，y 290~720（再往南是北人行道，street.py 画）。
  铺子房子     x 1468~1792：屋顶边 y 292~338，朝南的正面 y 338~410
  雨棚         上层，x 1528~1736，y 360~414（梅色条纹，角色从下面走过被盖住）
  摊子         y 414~450：鏊子、豆浆桶、一摞笼屉；玩家站在 (1630, 470) 买煎饼果子
  门口         y 450~720：水泥地，两三张折叠小桌和马扎
  街角         x 1800~1900：人行道方砖、报刊亭（青色铁皮），往东就是海河边
可走：门口 + 街角，和北人行道（y 720~760）、海河步道（x ≥ 1880）连起来；铺子里面不进。
"""
import math
import random

from common import Ctx, bicycle, ellipse_pts, rect_pts, shadow, sign, spot, stool

SX0, SX1 = 1468, 1792          # 铺子东西两头
ROOF0, FACE0, FACE1 = 290, 330, 404   # 屋顶边上沿、正面上沿、正面下沿（墙根）
CORNER0, CORNER1 = 1800, 1900


def draw(ctx: Ctx):
    g, walk = ctx.g, ctx.walk
    px, py = spot("breakfast_stall")

    # ---------------- 可走区域 ----------------
    walk.add_rect(1460, 456, CORNER0 - 1460, 268)      # 门口
    walk.add_rect(CORNER0 - 8, 300, CORNER1 - CORNER0 + 8, 424)  # 街角（北头也通）

    forecourt(ctx)
    corner(ctx)
    shop(ctx)
    stall(ctx, px, py)
    tables(ctx)
    awning(ctx)


# ----------------------------------------------------------------------
# 地面
# ----------------------------------------------------------------------

def forecourt(ctx: Ctx):
    """门口的水泥地：很淡的墨网点 + 伸缩缝 + 几块油渍、一个下水箅子。"""
    g = ctx.g
    rnd = random.Random(31)
    x0, y0, x1, y1 = 1446, FACE1, CORNER0, 720
    g.pen("ink", 0.06).fill(rect_pts(x0, y0, x1 - x0, y1 - y0))
    for yy in (520, 620):
        g.ink.line([(x0, yy), (x1, yy)], 1.1, amp=0.4, density=0.32)
    for xx in (1560, 1690):
        g.ink.line([(xx, y0 + 40), (xx, y1)], 1.1, amp=0.4, density=0.32)
    # 西边一道矮墙，和隔壁分开
    g.clear(rect_pts(1440, 300, 16, 420))
    g.pen("ink", 0.22).fill(rect_pts(1440, 300, 16, 420))
    g.ink.rect(1440, 300, 16, 420, lw=2.2)
    for yy in range(312, 720, 22):
        g.ink.line([(1440, yy), (1456, yy)], 1.0, amp=0.2, density=0.5)
    ctx.walk.block_rect(1440, 300, 18, 420)
    # 油渍、水渍（倒豆浆的地方）
    for cx, cy, r in ((1612, 500, 30), (1700, 470, 18), (1520, 470, 22)):
        g.pen("ink", 0.12).fill(ellipse_pts(cx, cy, r, r * 0.45))
    # 下水箅子
    g.clear(rect_pts(1748, 694, 34, 18))
    g.ink.rect(1748, 694, 34, 18, lw=1.8)
    for k in range(5):
        g.ink.line([(1753 + k * 6, 697), (1753 + k * 6, 709)], 1.2, amp=0)
    # 墙根下一溜碎砖
    for _ in range(6):
        bx, by = rnd.uniform(1470, 1530), rnd.uniform(FACE1 + 4, FACE1 + 14)
        g.ink.rect(bx, by, 9, 5, lw=1.2)


def corner(ctx: Ctx):
    """街角：人行道方砖、报刊亭、一辆靠墙的自行车、往海河去的路牌。"""
    g, o = ctx.g, ctx.o
    x0, x1, y0, y1 = CORNER0, CORNER1 + 4, 296, 720
    g.pen("ink", 0.07).fill(rect_pts(x0, y0, x1 - x0, y1 - y0))
    for yy in range(y0 + 40, y1, 40):
        g.ink.line([(x0, yy), (x1, yy)], 1.0, amp=0.3, density=0.32)
    g.ink.line([(x0 + 50, y0), (x0 + 50, y1)], 1.0, amp=0.3, density=0.28)
    # 铺子东墙投在街角上的影子（光从左上来）
    shadow(g, [(SX1, ROOF0 + 6), (SX1 + 30, ROOF0 + 26), (SX1 + 30, FACE1 + 28), (SX1, FACE1)], 0.16)
    # 北头一道矮院墙（再往北是邻居的屋顶）
    g.clear(rect_pts(x0 - 8, 284, x1 - x0 + 8, 14))
    g.pen("ink", 0.25).fill(rect_pts(x0 - 8, 284, x1 - x0 + 8, 14))
    g.ink.line([(x0 - 14, 284), (x1 + 6, 284)], 2.4)
    g.ink.line([(x0 - 14, 298), (x1 + 6, 298)], 2.6)

    # 靠在铺子东墙边的自行车（车头朝北，侧着放）
    bicycle(g, 1846, 532, facing=1, scale=0.85)
    ctx.walk.block_rect(1814, 494, 66, 44)
    # 两个摞起来的空箱子
    for i, (bx, by) in enumerate(((1806, 318), (1810, 306))):
        g.clear(rect_pts(bx, by, 34, 22))
        g.pen("mei" if i == 0 else "ink", 0.35).fill(rect_pts(bx, by, 34, 22))
        g.ink.rect(bx, by, 34, 22, lw=2)
        g.ink.line([(bx + 4, by + 8), (bx + 30, by + 8)], 1.2, amp=0.2)
    ctx.walk.block_rect(1804, 300, 42, 44)

    kiosk(ctx, 1814, 560)

    # 小路牌：往东去海河边
    sx, sy = 1872, 470
    g.ink.dot(sx, sy, 3.5)
    ctx.walk.block_circle(sx, sy, 6)
    o.ink.line([(sx, sy), (sx, sy - 74)], 3)
    o.clear(rect_pts(sx - 22, sy - 92, 50, 22))
    o.qing.poly([(sx - 22, sy - 92), (sx + 18, sy - 92), (sx + 30, sy - 81), (sx + 18, sy - 70), (sx - 22, sy - 70)], 1.8, fill=True)
    o.ink.poly([(sx - 22, sy - 92), (sx + 18, sy - 92), (sx + 30, sy - 81), (sx + 18, sy - 70), (sx - 22, sy - 70)], 1.8)
    from common import _knockout_text
    _knockout_text(o, "qing", "海河", sx, sy - 81, 14, False)


def kiosk(ctx: Ctx, x, y):
    """报刊亭：青色铁皮小亭子。x, y 是顶面左上角；顶面 72×34，正面高 40（露出一半）。"""
    g = ctx.g
    w, d, fh = 74, 34, 44
    top = rect_pts(x, y, w, d)
    front = rect_pts(x, y + d, w, fh)
    # 影子
    shadow(g, [(x + w, y + 4), (x + w + 26, y + 20), (x + w + 26, y + d + fh + 14), (x + w, y + d + fh)], 0.17)
    shadow(g, [(x + 6, y + d + fh), (x + w, y + d + fh), (x + w + 22, y + d + fh + 12), (x + 20, y + d + fh + 12)], 0.15)
    g.clear(top)
    g.clear(front)
    # 顶：铁皮，带一圈出檐
    g.pen("qing", 0.55).fill(rect_pts(x - 4, y - 4, w + 8, d + 6))
    g.qing.rect(x - 4, y - 4, w + 8, d + 6, lw=2.2)
    g.ink.rect(x - 4, y - 4, w + 8, d + 6, lw=2.0)
    for k in range(1, 6):
        g.ink.line([(x - 4 + k * (w + 8) / 6, y - 2), (x - 4 + k * (w + 8) / 6, y + d)], 1.0, amp=0.2, density=0.55)
    # 正面：上半截是挂满报刊的窗口，下半截铁皮
    g.pen("qing").fill(front)
    g.clear(rect_pts(x + 6, y + d + 4, w - 12, 20))
    cols = ["mei", "ink", "qing", "mei", "ink"]
    for i in range(5):
        mx = x + 8 + i * 12
        c = cols[i]
        g.pen(c, 0.55 if c != "ink" else 0.3).fill(rect_pts(mx, y + d + 6, 10, 15))
        g.ink.rect(mx, y + d + 6, 10, 15, lw=1.0)
        g.ink.line([(mx + 2, y + d + 10), (mx + 8, y + d + 10)], 1.0, amp=0, density=0.8)
    g.ink.rect(x + 6, y + d + 4, w - 12, 20, lw=1.6)
    g.ink.rect(x, y + d, w, fh, lw=2.4)
    g.ink.line([(x - 4, y + d + 2), (x + w + 4, y + d + 2)], 2.6)
    for k in range(4):
        g.ink.line([(x + 6, y + d + 30 + k * 4), (x + w - 6, y + d + 30 + k * 4)], 1.0, amp=0.2, density=0.6)
    # 门口一摞捆着的报纸
    g.clear(rect_pts(x + w - 26, y + d + fh + 2, 22, 12))
    g.ink.rect(x + w - 26, y + d + fh + 2, 22, 12, lw=1.6)
    g.ink.line([(x + w - 15, y + d + fh + 2), (x + w - 15, y + d + fh + 14)], 1.2, amp=0)
    ctx.walk.block_rect(x - 6, y - 6, w + 12, d + fh + 20)


# ----------------------------------------------------------------------
# 铺子
# ----------------------------------------------------------------------

def shop(ctx: Ctx):
    g, o = ctx.g, ctx.o
    rnd = random.Random(5)
    ctx.walk.block_rect(SX0 - 10, ROOF0 - 6, SX1 - SX0 + 20, FACE1 - ROOF0 + 46)

    # 屋顶边：平顶，油毡 + 压砖
    roof = rect_pts(SX0, ROOF0, SX1 - SX0, FACE0 - ROOF0)
    g.clear(roof)
    g.pen("ink", 0.16).fill(roof)
    g.ink.hatch(roof, 30, 13, 1.1, density=0.4)
    for _ in range(7):
        bx, by = rnd.uniform(SX0 + 20, SX1 - 30), rnd.uniform(ROOF0 + 8, FACE0 - 14)
        g.clear(rect_pts(bx, by, 14, 7))
        g.ink.rect(bx, by, 14, 7, lw=1.3)
    g.ink.box(SX0, ROOF0, SX1 - SX0, FACE0 - ROOF0, 2.8, over=6)
    # 屋顶上的铁皮烟囱（后厨灶台）
    cx, cy = SX0 + 46, ROOF0 + 22
    g.ink.circle(cx, cy, 8, lw=2.2)
    o.ink.line([(cx, cy), (cx, cy - 30)], 9)
    o.ink.poly([(cx - 12, cy - 30), (cx + 12, cy - 30), (cx + 6, cy - 38), (cx - 6, cy - 38)], 2.2, fill=True)
    ctx.anchor("smoke", cx, cy - 42)

    # 正面：刷白的墙裙 + 砖墙
    face = rect_pts(SX0, FACE0, SX1 - SX0, FACE1 - FACE0)
    g.clear(face)
    g.pen("mei", 0.32).fill(rect_pts(SX0, FACE0, SX1 - SX0, 28))
    g.mei.bricks(SX0, FACE0, SX1 - SX0, 28, 26, 7, 1.0, density=0.6)
    g.pen("ink", 0.05).fill(rect_pts(SX0, FACE0 + 28, SX1 - SX0, FACE1 - FACE0 - 28))
    # 西头一扇窗：窗台上一块小黑板
    wx = SX0 + 14
    g.pen("ink", 0.38).fill(rect_pts(wx, FACE0 + 34, 46, 30))
    g.ink.rect(wx, FACE0 + 34, 46, 30, lw=2)
    g.ink.line([(wx + 23, FACE0 + 34), (wx + 23, FACE0 + 64)], 1.6)
    g.ink.line([(wx - 4, FACE0 + 66), (wx + 50, FACE0 + 66)], 2.6)
    # 门口大开间（被雨棚挡住上半截），里面黑黢黢的
    ox0, ox1 = 1540, 1724
    g.pen("ink", 0.62).fill(rect_pts(ox0, FACE0 + 30, ox1 - ox0, FACE1 - FACE0 - 30))
    for k in range(1, 5):   # 卸下来的门板靠在里面
        xx = ox0 + k * (ox1 - ox0) / 5
        g.ink.line([(xx, FACE0 + 30), (xx, FACE1)], 1.4, density=0.5)
    g.ink.rect(ox0, FACE0 + 30, ox1 - ox0, FACE1 - FACE0 - 30, lw=2.4)
    # 东头：一扇小门（后厨）+ 竖着的招牌「煎饼果子」
    dx = SX1 - 44
    g.pen("qing", 0.45).fill(rect_pts(dx, FACE0 + 32, 26, FACE1 - FACE0 - 32))
    g.ink.rect(dx, FACE0 + 32, 26, FACE1 - FACE0 - 32, lw=2)
    g.ink.dot(dx + 21, FACE0 + 56, 2)
    # 墙的轮廓
    g.ink.line([(SX0 - 6, FACE1), (SX1 + 6, FACE1)], 3.2)
    g.ink.line([(SX0, FACE0 - 4), (SX0, FACE1 + 4)], 3.0)
    g.ink.line([(SX1, FACE0 - 4), (SX1, FACE1 + 4)], 3.0)
    g.ink.line([(SX0 - 6, FACE0), (SX1 + 6, FACE0)], 2.4)
    # 招牌：屋檐下一块横的「早点」
    sign(g, 1630, FACE0 - 8, "早点", "mei", size=30, pad=16)
    # 门口西边一块立着的小黑板（A 字架），粉笔写着菜名
    menu_board(ctx, 1494, 440)
    # 竖招牌：挂在东墙角，伸出来
    vx, vy = SX1 + 2, 372
    g.ink.line([(SX1, vy - 46), (vx + 16, vy - 46)], 2.2)
    sign(g, vx + 16, vy + 4, "煎饼果子", "mei", size=15, vertical=True, pad=7)
    shadow(g, [(vx + 28, vy - 40), (vx + 40, vy - 34), (vx + 40, vy + 56), (vx + 28, vy + 50)], 0.15)


def menu_board(ctx: Ctx, x, y):
    """A 字架小黑板：x, y 是板子中心。"""
    g = ctx.g
    shadow(g, [(x - 18, y + 30), (x + 22, y + 30), (x + 44, y + 42), (x + 4, y + 42)], 0.16)
    g.ink.line([(x - 20, y + 30), (x - 16, y - 26)], 2.2)
    g.ink.line([(x + 20, y + 30), (x + 16, y - 26)], 2.2)
    g.clear(rect_pts(x - 17, y - 26, 34, 52))
    g.ink.fill(rect_pts(x - 17, y - 26, 34, 52))
    g.ink.rect(x - 17, y - 26, 34, 52, lw=2.2)
    # 粉笔字：纸色挖出来
    from common import _knockout_text
    _knockout_text(g, "ink", "锅巴菜", x, y - 12, 11, False)
    _knockout_text(g, "ink", "豆浆", x, y + 5, 11, False)
    g.clear([(x - 10, y + 16), (x + 10, y + 15), (x + 10, y + 17), (x - 10, y + 18)])
    ctx.walk.block_rect(x - 22, y - 26, 44, 60)


def stall(ctx: Ctx, px, py):
    """门口支出来的摊子：一张不锈钢台面的推车，上面鏊子、面糊盆、豆浆桶，旁边一摞笼屉。"""
    g = ctx.g
    x0, x1 = 1552, 1710
    ty0, ty1, fy1 = 406, 436, 452      # 台面（顶面）、前脸下沿
    ctx.walk.block_rect(x0 - 4, ty0 - 6, 1790 - x0, fy1 - ty0 + 6)
    # 影子
    shadow(g, [(x0 + 10, fy1), (x1 + 4, fy1), (x1 + 30, fy1 + 14), (x0 + 30, fy1 + 14)], 0.17)
    g.clear(rect_pts(x0, ty0, x1 - x0, fy1 - ty0))
    # 台面
    g.pen("ink", 0.1).fill(rect_pts(x0, ty0, x1 - x0, ty1 - ty0))
    g.ink.rect(x0, ty0, x1 - x0, ty1 - ty0, lw=2.4)
    # 前脸：青漆铁皮
    g.pen("qing", 0.7).fill(rect_pts(x0, ty1, x1 - x0, fy1 - ty1))
    g.ink.rect(x0, ty1, x1 - x0, fy1 - ty1, lw=2.4)
    for k in range(1, 4):
        xx = x0 + k * (x1 - x0) / 4
        g.ink.line([(xx, ty1), (xx, fy1)], 1.2, amp=0.2, density=0.6)
    # 鏊子：大圆铁板，嵌在台面里
    ax, ay = 1596, 421
    g.clear(ellipse_pts(ax, ay, 34, 15))
    g.pen("ink", 0.72).fill(ellipse_pts(ax, ay, 32, 13))
    g.ink.ellipse(ax, ay, 34, 15, lw=2.6)
    # 摊开的一张煎饼：纸色留白 + 一圈梅（鸡蛋）
    g.clear(ellipse_pts(ax - 3, ay, 21, 9))
    g.pen("mei", 0.3).fill(ellipse_pts(ax - 3, ay, 21, 9))
    g.mei.ellipse(ax - 3, ay, 21, 9, lw=1.6)
    g.ink.line([(ax + 18, ay - 2), (ax + 40, ay - 14)], 2.6)   # 刮板的把
    ctx.anchor("steam", ax, ay - 10)
    # 面糊盆、鸡蛋筐
    g.clear(ellipse_pts(1646, 421, 13, 7))
    g.ink.ellipse(1646, 421, 13, 7, lw=2)
    g.pen("ink", 0.25).fill(ellipse_pts(1646, 422, 9, 4))
    for i in range(4):
        g.ink.circle(1665 + (i % 2) * 8, 416 + (i // 2) * 8, 3.4, lw=1.4)
    # 豆浆桶：不锈钢大桶，站在推车东头
    bx, by = 1692, 404
    g.clear(rect_pts(bx - 14, by, 28, 32))
    g.clear(ellipse_pts(bx, by, 14, 7))
    g.pen("ink", 0.12).fill(rect_pts(bx - 14, by, 28, 30))
    g.ink.line([(bx - 14, by), (bx - 14, by + 30)], 2.2)
    g.ink.line([(bx + 14, by), (bx + 14, by + 30)], 2.2)
    g.ink.arc(bx, by + 30, 14, 0, math.pi, lw=2.2, amp=0.2)
    g.ink.line([(bx + 7, by + 3), (bx + 7, by + 28)], 3, density=0.25)
    g.ink.ellipse(bx, by, 14, 7, lw=2.2)
    g.ink.line([(bx - 3, by - 1), (bx + 4, by - 22)], 2.2)    # 舀子把
    ctx.anchor("steam", bx, by - 6)
    # 一摞笼屉（包子），坐在一只煤炉上，摞起来往上长
    lx, ly = 1764, 448
    shadow(g, ellipse_pts(lx + 14, ly + 4, 26, 8), 0.16)
    g.clear(rect_pts(lx - 16, ly - 14, 32, 16))
    g.pen("ink", 0.55).fill(rect_pts(lx - 16, ly - 14, 32, 16))   # 煤炉
    g.ink.rect(lx - 16, ly - 14, 32, 16, lw=2)
    g.pen("mei").fill(rect_pts(lx - 5, ly - 9, 10, 6))             # 炉口的火
    ly -= 20
    for i in range(4):
        cy = ly - i * 10
        side = rect_pts(lx - 22, cy - 10, 44, 10)
        g.clear(side)
        g.clear(ellipse_pts(lx, cy, 22, 8))
        g.pen("mei", 0.14).fill(side)
        g.pen("mei", 0.14).fill(ellipse_pts(lx, cy, 22, 8))
        for k in range(-18, 20, 5):   # 竹篾
            g.ink.line([(lx + k, cy - 9), (lx + k, cy + 6 - abs(k) * 0.12)], 1.0, amp=0, density=0.45)
        g.ink.arc(lx, cy, 22, 0, math.pi, lw=2, amp=0.2)
        g.ink.line([(lx - 22, cy - 10), (lx - 22, cy)], 2)
        g.ink.line([(lx + 22, cy - 10), (lx + 22, cy)], 2)
    top = ly - 4 * 10
    g.clear(ellipse_pts(lx, top, 22, 8))
    g.pen("ink", 0.2).fill(ellipse_pts(lx, top, 22, 8))
    g.ink.ellipse(lx, top, 22, 8, lw=2.2)
    g.ink.ellipse(lx, top, 12, 4, lw=1.2, density=0.7)
    g.ink.line([(lx - 6, top - 1), (lx + 6, top - 1)], 2.6)     # 盖子上的提手
    ctx.anchor("steam", lx, top - 6)
    _ = px, py


def tables(ctx: Ctx):
    """门口两张折叠小方桌 + 马扎（南半边，给去马路的人留出中间的道）。"""
    g = ctx.g
    for (tx, ty, seed) in ((1510, 552, 1), (1702, 590, 2), (1522, 662, 3)):
        rnd = random.Random(seed)
        w, d, h = 58, 38, 22   # 桌面、腿高（露出一半）
        shadow(g, [(tx + 6, ty + d + h), (tx + w + 4, ty + d + h), (tx + w + 30, ty + d + h + 14), (tx + 28, ty + d + h + 14)], 0.16)
        # 腿
        for lx in (tx + 5, tx + w - 5):
            g.ink.line([(lx, ty + d), (lx, ty + d + h)], 2.2)
        g.ink.line([(tx + 5, ty + d + h * 0.6), (tx + w - 5, ty + d + h * 0.6)], 1.2, amp=0.2, density=0.6)
        g.clear(rect_pts(tx, ty, w, d + 5))
        g.ink.rect(tx, ty, w, d, lw=2.4)
        g.ink.line([(tx, ty + d + 4), (tx + w, ty + d + 4)], 2.0)
        g.ink.line([(tx, ty + d), (tx, ty + d + 4)], 2.0)
        g.ink.line([(tx + w, ty + d), (tx + w, ty + d + 4)], 2.0)
        # 桌上的碗和筷子
        for _ in range(2):
            bx, by = tx + rnd.uniform(12, w - 12), ty + rnd.uniform(10, d - 10)
            g.clear(ellipse_pts(bx, by, 9, 6))
            g.ink.ellipse(bx, by, 9, 6, lw=1.6)
            g.qing.arc(bx, by, 6, 0.2, math.pi - 0.2, lw=1.4)
        g.ink.line([(tx + 8, ty + 8), (tx + 22, ty + 6)], 1.4, amp=0)
        g.ink.line([(tx + 8, ty + 11), (tx + 22, ty + 9)], 1.4, amp=0)
        ctx.walk.block_rect(tx - 4, ty - 2, w + 8, d + h + 4)
        # 马扎：桌子两边
        stool(g, tx - 20, ty + d + 8, rnd.choice(["qing", "ink"]))
        stool(g, tx + w + 20, ty + d + 10, rnd.choice(["mei", "ink"]))
        if seed != 2:
            stool(g, tx + w / 2, ty + d + h + 22, "ink")
            ctx.walk.block_circle(tx + w / 2, ty + d + h + 22, 10)
        ctx.walk.block_circle(tx - 20, ty + d + 8, 10)
        ctx.walk.block_circle(tx + w + 20, ty + d + 10, 10)


def awning(ctx: Ctx):
    """梅色条纹雨棚：在上层（正片叠底盖住角色）。地面层这块先挖空，免得透出底下的东西。"""
    g, o = ctx.g, ctx.o
    x0, x1 = 1524, 1734
    yb, yf = 352, 394                 # 贴墙的后沿、前沿（往南斜下来）
    pts = [(x0 + 8, yb), (x1 - 8, yb), (x1, yf), (x0, yf)]
    g.clear(pts)
    # 影子：落在台面和地上（右下）
    g.pen("ink", 0.15).fill([(x0 + 20, yf), (x1 + 16, yf), (x1 + 16, yf + 10), (x0 + 20, yf + 10)])
    n = 9
    for i in range(n):
        if i % 2 == 0:
            a0, a1 = i / n, (i + 1) / n
            seg = [
                (x0 + 8 + (x1 - x0 - 16) * a0, yb), (x0 + 8 + (x1 - x0 - 16) * a1, yb),
                (x0 + (x1 - x0) * a1, yf), (x0 + (x1 - x0) * a0, yf),
            ]
            o.mei.fill(seg)
        else:
            a0, a1 = i / n, (i + 1) / n
            seg = [
                (x0 + 8 + (x1 - x0 - 16) * a0, yb), (x0 + 8 + (x1 - x0 - 16) * a1, yb),
                (x0 + (x1 - x0) * a1, yf), (x0 + (x1 - x0) * a0, yf),
            ]
            o.pen("ink", 0.05).fill(seg)
    o.ink.poly(pts, 2.6)
    # 前沿的荷叶边（一溜小半圆）
    sw = (x1 - x0) / n
    for i in range(n):
        cx = x0 + sw * (i + 0.5)
        arc = [(cx + sw / 2 * math.cos(a), yf + 8 * math.sin(a)) for a in [k * math.pi / 8 for k in range(9)]]
        poly = [(cx - sw / 2, yf)] + arc[::-1] + [(cx + sw / 2, yf)]
        if i % 2 == 0:
            o.mei.fill(poly)
        else:
            o.pen("ink", 0.05).fill(poly)
        o.ink.line(arc, 1.8, amp=0.2)
    # 两根支杆（落在推车外面）
    for sx in (x0 + 3, x1 - 3):
        o.ink.line([(sx, yf), (sx, yf + 50)], 2.4)
        g.ink.dot(sx, yf + 50, 3)
