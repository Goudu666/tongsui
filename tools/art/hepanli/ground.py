"""底图：纸 + 地图边上的邻居屋顶（不能走，只是让河畔里看起来在一片城市里）。"""
import random

from common import Ctx, rect_pts


def roofs(ctx: Ctx, x, y, w, h, seed=1, ridge="h"):
    """一片邻居家的平屋顶：墨网点 + 排线 + 几个烟囱/水箱。"""
    g = ctx.g
    rnd = random.Random(seed)
    g.pen("ink", 0.10).fill(rect_pts(x, y, w, h))
    g.ink.hatch(rect_pts(x, y, w, h), 35 if ridge == "h" else -35, 14, 1.1, density=0.45)
    g.ink.box(x, y, w, h, 2.4, over=5)
    for _ in range(max(1, int(w * h / 40000))):
        cx, cy = x + rnd.uniform(20, w - 40), y + rnd.uniform(20, h - 40)
        g.clear(rect_pts(cx, cy, 22, 18))
        g.ink.rect(cx, cy, 22, 18, lw=2)
        g.pen("ink", 0.35).fill(rect_pts(cx, cy + 12, 22, 6))


def draw(ctx: Ctx):
    # 西边、北边的邻居
    roofs(ctx, -10, -10, 118, 718, seed=3, ridge="v")
    roofs(ctx, 1372, -10, 66, 718, seed=5, ridge="v")
    # 东北角原来也是一片屋顶，现在是河畔茶社（teahouse.py）
