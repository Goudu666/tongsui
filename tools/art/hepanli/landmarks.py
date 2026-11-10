"""街上不会变的小东西：胡同口的路牌。

会随年代变的东西（街坊、公告栏、电话亭、车）不在底图里：
street.py 画、引擎按年代摆（content/street.yaml）。
"""
from common import Ctx, _knockout_text, rect_pts


def draw(ctx: Ctx):
    hutong_sign(ctx)


def hutong_sign(ctx: Ctx):
    """线儿胡同口的路牌：一根杆子顶一块青牌子（上层），和街角「海河」那块是一套。"""
    g, o = ctx.g, ctx.o
    sx, sy = 1780, 1074
    g.ink.dot(sx, sy, 3.5)
    ctx.walk.block_circle(sx, sy, 6)
    o.ink.line([(sx, sy), (sx, sy - 70)], 3)
    plate = rect_pts(sx - 36, sy - 90, 72, 22)
    o.clear(plate)
    o.qing.fill(plate)
    o.ink.rect(sx - 36, sy - 90, 72, 22, lw=1.8)
    _knockout_text(o, "qing", "线儿胡同", sx, sy - 79, 14, False)
