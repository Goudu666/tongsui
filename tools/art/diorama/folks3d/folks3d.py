#!/usr/bin/env python3
"""微缩模型（C）画风的街坊和路人：和主角同一副塑料小人（pose3d/figure.js，造型甲、toy 材质），换衣服、发型、帽子。

    python3 tools/art/diorama/folks3d/folks3d.py                 # 十四张图 + walkers.png + index.json → client/art/folks/
    python3 tools/art/diorama/folks3d/folks3d.py --only street,walkers
    python3 tools/art/diorama/folks3d/folks3d.py --no-render     # 不渲染，只从已有的表拼总览
    python3 tools/art/diorama/folks3d/folks3d.py --contact X.png # 总览换个地方存

谁在哪张图、哪个年纪、几点在、说什么：content/maps/<图>.yaml 的 npcs（npm run content → client/data/folks.json）。
动作（营生、歇着、走路）借 tools/art/folks.py 的那一套骨架，一帧一帧和孔版是同一个意思；
长相不用 folks.py 的网点配色，在下面的 LOOKS 里一人一套（主角是青绿、梅红，街坊不用这两个色）。
表的格式同 folks.gd（孔版时的约定）：每格 200×220 世界像素，脚底 (100, 206)，1.25 倍；
<图>.png 一人一行，列 0~3 干活、4~7 歇着；walkers.png 一种一行 8 帧走路。人朝右，朝左由引擎翻。
"""
from __future__ import annotations

import argparse
import copy
import json
import os
import shutil
import sys
import time

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
POSE3D = os.path.join(os.path.dirname(HERE), "pose3d")
ART = os.path.dirname(os.path.dirname(HERE))  # tools/art
sys.path.insert(0, POSE3D)
sys.path.insert(0, ART)
import poses  # noqa: E402  （先 import：它把 actors 里画 2D 脸的函数换成空的）
import figures  # noqa: E402
import folks as F2  # noqa: E402  tools/art/folks.py：FOLKS（动作）、WALKERS、idle

ROOT = figures.ROOT
OUT_DIR = os.path.join(ROOT, "client", "art", "folks")
FOLKS_JSON = os.path.join(ROOT, "client", "data", "folks.json")
CONTACT = "/mnt/project-files/tongsui/art/diorama/folks_sheet.png"
PAGE = "diorama/folks3d/page.html"
CELL, FOOT = figures.CELL, figures.FOOT
SCALE = 1.25
SS = 2
DESIGN = figures.DESIGNS[figures.DEFAULT_DESIGN]

# ----------------------------------------------------------------------
# 颜色（主角：青 #2E8B6E、梅 #D94A3A；街坊用这些）
# ----------------------------------------------------------------------
WHITE, CREAM, SAND = "#F5F0E6", "#EFE2C8", "#D8CBB0"
NAVY, NAVYDK, DENIM, WORK, BLUE, SKY = "#3D4A6E", "#2F3A58", "#4F6A92", "#4C6A9A", "#5F86AE", "#A9C2DE"
GREY, GREYLT, CHAR, SLATE, PGREY = "#8C8C94", "#C2BEB8", "#4A4650", "#5D6F86", "#5A6070"
KHAKI, CAMEL, BROWN, BROWNDK, TAN = "#B9A67E", "#C9A57A", "#8C5E45", "#6A5040", "#CDB48E"
MUSTARD, OCHRE, ORANGE, YELLOW = "#D9A43C", "#C98B3A", "#E8913A", "#F2C14E"
PLUM, LAV, MAUVE, LILAC = "#8C5A86", "#A89BC9", "#B98AA0", "#D6CBE4"
OLIVE, ARMY = "#7C8248", "#6B7048"
SHOE, CLOTHSHOE, SNEAK = "#46363C", "#2E2A30", "#F2EDE4"
H_DARK, H_BLACK, H_BROWN, H_GREY, H_SALT = "#3A2A2C", "#2A2228", "#5A3E34", "#B9B2B4", "#857A80"
SKIN_TAN, SKIN_DEEP = "#E2A47C", "#D89470"


def hair(style, color=H_DARK, **kw):
    return dict(style=style, color=color, grey=color in (H_GREY,), **kw)


def look(top, bottom=NAVY, shoe=SHOE, *, jacket=None, coat=None, buttons=None, hair_=None, hat=None, apron=None, glasses=False,
         skin=None, accent=None, sleeve=None, shorts=False, skirt=None, skinLegs=False, collar=None, sole=None, socks=None,
         face=None, sleeves=None, towel=None, basket=False, briefcase=None, satchel=None, ears=None, trim=None, zip_=None,
         bag=None, belt=None, stripes=None, stool=None):
    """一个人的样子 → figure.js 的 spec.look。jacket = 敞怀的外套 / 开衫（和 top 同色就是扣上的）；coat = 过膝长褂。"""
    o = dict(top=top, bottom=bottom, shoe=shoe)
    for k, v in dict(jacket=jacket, coat=coat, buttons=buttons, sleeve=sleeve, shorts=shorts or None, skirt=skirt, skinLegs=skinLegs or None,
                     collar=collar, sole=sole, socks=socks, trim=trim, zip=zip_, bag=bag, stripes=stripes).items():
        if v is not None:
            o[k] = v
    if coat:
        if belt:
            o["belt"] = belt
        else:
            o["noBelt"] = True
    lk = dict(outfit=o, hair=hair_ or hair("crew"), glasses=glasses, accent=accent or dict(qing=BLUE, mei=OCHRE))
    for k, v in dict(hat=hat, apron=apron, skin=skin, face=face, sleeves=sleeves, towel=towel, basket=basket or None,
                     briefcase=briefcase, satchel=satchel, ears=ears, stool=stool).items():
        if v is not None:
            lk[k] = v
    return lk


def cap(color=NAVY, **kw):
    return dict(kind="cap", color=color, **kw)


LOOKS = {
    # 楼下
    "shop_ayi": look(CREAM, NAVY, CLOTHSHOE, jacket=OCHRE, buttons=CREAM, hair_=hair("perm", H_BROWN, seed=3), sleeves=BLUE, ears=False, face=dict(lines=1)),
    "shop_clerk": look(SKY, DENIM, SNEAK, jacket=GREY, collar=WHITE, sole=WHITE, hair_=hair("side", H_BLACK, seed=5)),
    "grinder": look(GREYLT, BROWNDK, CLOTHSHOE, jacket=WORK, buttons=SAND, hat=cap(SLATE), apron="#7A5A44", face=dict(stubble=1, lines=1), ears=True),
    "barber": look(WHITE, PGREY, SHOE, coat="#F8F6F0", collar=WHITE, glasses=True, hair_=hair("side", H_BLACK, seed=7), face=dict(moustache="#3A2A2C")),
    # 河对岸
    "piano_teacher": look(WHITE, NAVY, SHOE, coat=CAMEL, belt=BROWN, hair_=hair("long", H_BROWN, part=1), ears=False, accent=dict(qing=BLUE, mei=PLUM)),
    "bath_uncle": look(WHITE, PGREY, CLOTHSHOE, sleeve="short", apron=SLATE, towel=WHITE, hair_=hair("buzz", H_BLACK), face=dict(stubble=1), skin="#F0B08A"),
    "site_worker": look(ARMY, WORK, BROWNDK, sleeve="short", hat=dict(kind="helmet", color=YELLOW), skin=SKIN_TAN, hair_=hair("buzz", H_BLACK), towel="#E8E0D0"),
    "greeter": look(MUSTARD, NAVY, SNEAK, sole=WHITE, collar=WHITE, sleeve="short", hair_=hair("pony", H_DARK, tie=BLUE, high=1), satchel=BLUE),
    "clerk": look(WHITE, PGREY, SHOE, jacket=LAV, buttons=WHITE, glasses=True, hair_=hair("bob", H_DARK, part=1), ears=False),
    "guard_office": look(NAVYDK, NAVYDK, SHOE, jacket=NAVYDK, buttons=YELLOW, collar=SKY, hat=cap(NAVYDK, badge=YELLOW), hair_=hair("crew", H_BLACK)),
    # 外地
    "dorm_ayi": look(WHITE, PGREY, CLOTHSHOE, jacket="#7C97BA", buttons=WHITE, hair_=hair("bun", H_BROWN, seed=9), face=dict(lines=1)),
    "stall_owner": look(GREYLT, DENIM, SHOE, sleeve="short", apron=WHITE, towel=WHITE, hair_=hair("crew", H_BLACK, seed=4), face=dict(stubble=1)),
    "coworker": look(WHITE, CHAR, SHOE, jacket=CHAR, collar=WHITE, glasses=True, hair_=hair("side", H_DARK, seed=12)),
    "postal": look(WHITE, NAVY, SHOE, jacket=ARMY, buttons=YELLOW, collar=WHITE, hair_=hair("bob", H_BLACK), ears=False),
    # 楼里
    "er_nainai": look(LILAC, PGREY, CLOTHSHOE, jacket=PLUM, buttons=WHITE, hair_=hair("bun", H_GREY), glasses="gold", accent=dict(qing=BLUE, mei=PLUM)),
    "coal": look(CHAR, CHAR, CLOTHSHOE, jacket="#3E3A40", hat=cap("#3E3A40"), sleeves="#2E2A30", face=dict(soot=1, stubble=1), skin="#E8AE88"),
    "junk": look(GREYLT, BROWNDK, CLOTHSHOE, jacket="#7C97BA", hat=cap(KHAKI), face=dict(stubble=1, lines=1)),
    "silou": look(WHITE, DENIM, SNEAK, sole=WHITE, jacket=TAN, collar=WHITE, hair_=hair("kid", H_BLACK, seed=19), satchel=BROWN),
    # 医院
    "nurse": look(WHITE, WHITE, WHITE, coat="#FBF9F4", collar=SKY, hair_=hair("bun", H_DARK, bunE=10), hat=dict(kind="nurse", color=WHITE), ears=False),
    "porter": look(WHITE, BLUE, SHOE, jacket=SKY, hair_=hair("crew", H_SALT), face=dict(lines=1)),
    "queue_old": look(CREAM, PGREY, CLOTHSHOE, jacket="#7A6A5A", buttons=CREAM, hat=cap(GREY), glasses="gold", face=dict(lines=1)),
    # 早市
    "soy_seller": look(CREAM, PGREY, CLOTHSHOE, jacket="#8A5060", apron=WHITE, sleeves=BLUE, hair_=hair("perm", H_DARK, seed=21), ears=False),
    "veg_seller": look(GREYLT, BROWNDK, "#3A4A3A", jacket=ARMY, buttons=YELLOW, hat=cap(ARMY), apron="#5A5048", face=dict(stubble=1, lines=1), skin=SKIN_TAN),
    "wholesale_boss": look(WHITE, CHAR, SHOE, jacket="#3A3438", collar=WHITE, hair_=hair("side", H_BLACK, seed=33), face=dict(moustache="#2A2228"), satchel="#3A3438"),
    "scrap_buyer": look(GREYLT, NAVY, CLOTHSHOE, jacket=SLATE, hat=cap(GREY), sleeves=NAVY, face=dict(stubble=1), skin=SKIN_TAN),
    # 中学
    "shed_ayi": look(SKY, NAVY, CLOTHSHOE, jacket=BLUE, apron=KHAKI, sleeves="#6E7E9A", hair_=hair("perm", H_BROWN, seed=27), ears=False),
    "stationery": look(WHITE, PGREY, SHOE, jacket=BROWN, buttons=CREAM, collar=WHITE, glasses=True, hair_=hair("bald", H_DARK)),
    "dean": look("#5A5E66", "#5A5E66", SHOE, jacket="#5A5E66", buttons="#3A3E46", collar=WHITE, glasses=True, hair_=hair("side", H_BLACK, seed=2)),
    # 新楼
    "property": look(BLUE, NAVY, SHOE, jacket=BLUE, buttons=WHITE, collar=WHITE, hat=cap(BLUE, badge=YELLOW)),
    "next_door": look(MAUVE, PGREY, SHOE, jacket=GREYLT, hair_=hair("perm", H_BROWN, seed=41), ears=False),
    "dog_walker": look(WHITE, NAVY, SNEAK, sole=WHITE, jacket=LAV, zip_=WHITE, hair_=hair("pony", H_BROWN, tie=PLUM), accent=dict(qing=BLUE, mei=PLUM)),
    # 公园
    "conductor": look(WHITE, "#3A3E4A", SHOE, jacket="#3A3E4A", collar=WHITE, hair_=hair("side", H_GREY, seed=8), glasses="gold"),
    "writer": look(WHITE, PGREY, CLOTHSHOE, jacket="#E6DFD2", buttons=BROWN, hat=cap(SAND), face=dict(lines=1)),
    "stroller": look(CREAM, PGREY, CLOTHSHOE, jacket=MUSTARD, buttons=CREAM, hair_=hair("perm", H_GREY, seed=44), ears=False, accent=dict(qing=BLUE, mei=PLUM)),
    "kite_old": look(CREAM, PGREY, CLOTHSHOE, jacket=TAN, hat=cap(NAVY), face=dict(lines=1)),
    # 小学
    "guard": look(NAVYDK, NAVYDK, CLOTHSHOE, jacket=NAVYDK, buttons=YELLOW, hat=cap(NAVYDK, badge="#D86A6A"), glasses="gold", face=dict(lines=1)),
    "teacher": look(WHITE, NAVY, SHOE, jacket=BLUE, buttons=WHITE, glasses=True, hair_=hair("bob", H_BLACK), skirt=NAVY, skinLegs=True, ears=False),
    "grandparents": look(CREAM, PGREY, CLOTHSHOE, jacket=BROWN, buttons=CREAM, hair_=hair("perm", H_GREY, seed=50), ears=False, glasses="gold"),
    # 出租屋
    "landlord": look(MAUVE, "#7A6E8A", "#8A5060", hair_=hair("perm", H_BLACK, seed=55), ears=False, sleeve="short", face=dict(lines=1)),
    "neighbor_rent": look(GREYLT, DENIM, SHOE, sleeve="short", hair_=hair("kid", H_BLACK, seed=60), face=dict(stubble=1)),
    # 海河边
    "yam": look(GREYLT, BROWNDK, CLOTHSHOE, jacket=BROWNDK, buttons=SAND, hat=cap("#4A4048"), apron="#5A5048", sleeves=NAVY, face=dict(stubble=1, lines=1)),
    "photog": look(WHITE, KHAKI, SHOE, jacket=KHAKI, collar=WHITE, hat=dict(kind="ball", color=NAVY), hair_=hair("crew", H_BLACK), satchel=BROWN),
    "runner": look(LAV, NAVY, SNEAK, sole=WHITE, jacket=PLUM, zip_=WHITE, trim=WHITE, hair_=hair("pony", H_DARK, tie=WHITE, high=1), accent=dict(qing=BLUE, mei=PLUM)),
    # 海边
    "shell_seller": look(MUSTARD, NAVY, "#8A5A3A", sleeve="short", hat=dict(kind="straw", color="#E3C88A", band=BLUE), apron=BLUE, hair_=hair("bun", H_DARK), skin=SKIN_TAN),
    "lifeguard": look(ORANGE, BLUE, "#E8E0D0", sleeve="short", shorts=True, hat=dict(kind="ball", color=YELLOW, brim=ORANGE), skin=SKIN_DEEP, hair_=hair("buzz", H_BLACK)),
    "angler": look(WHITE, PGREY, CLOTHSHOE, jacket=KHAKI, hat=dict(kind="bucket", color=SAND), face=dict(lines=1)),
    "inn_clerk": look(WHITE, NAVY, SHOE, jacket=NAVY, buttons=WHITE, collar=WHITE, hair_=hair("bob", H_DARK, part=1), ears=False),
    # 乡下
    "grandma_v": look(NAVY, CLOTHSHOE, CLOTHSHOE, jacket=NAVY, buttons=WHITE, hair_=hair("bun", H_GREY), face=dict(lines=1), skin="#EFB48C"),
    "gate_old": look(WHITE, PGREY, CLOTHSHOE, sleeve="short", hat=dict(kind="straw", color="#E3C88A", band=BROWN), face=dict(lines=1), skin=SKIN_TAN),
    "cousin": look(WHITE, KHAKI, "#3A3A44", sleeve="short", shorts=True, hair_=hair("kid", H_BLACK, seed=62), skin=SKIN_DEEP),
}

WALKER_LOOKS = {
    "bag_man": look(WHITE, CHAR, SHOE, jacket=GREY, collar=WHITE, hair_=hair("side", H_BLACK, seed=70), briefcase=BROWNDK),
    "basket_aunt": look(CREAM, PGREY, CLOTHSHOE, jacket=MUSTARD, buttons=CREAM, hair_=hair("perm", H_BROWN, seed=71), ears=False, basket=True),
    "cane_old": look(CREAM, PGREY, CLOTHSHOE, jacket=BLUE, hat=cap(GREY), glasses="gold", face=dict(lines=1)),
    "kid": look(YELLOW, KHAKI, "#4A6AA0", sleeve="short", shorts=True, socks=WHITE, sole=WHITE, stripes=WHITE, hair_=hair("kid", H_BLACK, seed=73)),
    "student": look(WHITE, "#3F6FB0", SNEAK, jacket="#3F6FB0", trim=WHITE, zip_=WHITE, collar=WHITE, sole="#D9D2C8", bag=PLUM, hair_=hair("pony", H_DARK, tie=BLUE, high=1)),
    "coat_woman": look(WHITE, CHAR, SHOE, coat="#9A8E86", belt="#6A5E58", hair_=hair("long", H_BROWN), ears=False, satchel=PLUM),
}


# ----------------------------------------------------------------------
# 一格一格
# ----------------------------------------------------------------------

def body(b0):
    return poses.body_from(copy.deepcopy(b0), DESIGN)


def spec_for(b, lk, male):
    s = poses.figure_spec(b)
    s["role"] = "qing" if male else "mei"  # 3D 那边：男的耳朵露着、女的眼角一挑
    s["hair"] = "grey" if lk["hair"].get("grey") else "ink"
    s["look"] = lk
    return s


def cell_px():
    return [int(CELL[0] * SCALE * SS), int(CELL[1] * SCALE * SS)]


def folk_frames(fid):
    b0, fn, sit, _ = F2.FOLKS[fid]
    b = body(b0)
    out = []
    for i in range(4):
        out.append(poses.frame(b, **fn(b, i / 4.0)))
    for i in range(4):
        out.append(poses.frame(b, **F2.idle(b, i / 4.0, sit)))
    if fn is F2.act_steam:  # 烤山芋：孔版画的扁炉子换成 3D 的汽油桶（热气留着）；歇着的时候炉子也在
        for fr in out:
            fr["props"] = [p for p in fr["props"] if not (p["layer"] == "back" and p["t"] != "line")
                           and not (p["layer"] == "back" and p["spec"] and p["spec"][0] == "mei")]
            fr["stove"] = [48]
    if fn is F2.act_stroller:  # 推婴儿车：孔版的车子换成 3D 的（车筐、篷子、四个轱辘，里头一个娃娃），收在格子里头
        for fr in out[:4]:
            fr["props"] = []
            fr["stroller"] = True
    return b, out


def walker_frames(name, b0):
    b = body(b0)
    out = []
    for i in range(8):
        pose = F2.pose_walk(b, i / 8.0)
        if b.get("basket"):  # 挎篮子：近侧胳膊不甩，弯着挎住
            pose["arms"] = [a if a["side"] == "far" else dict(side="near", shoulder=0, elbow=0, hand_rel=(0.3, 0.62)) for a in pose["arms"]]
        out.append(poses.frame(b, pose))
    return b, out


def jobs_for(scenes, with_walkers):
    jobs = []
    view, px = figures.view_cell(), cell_px()
    for scene, ids in scenes:
        for row, fid in enumerate(ids):
            b, frs = folk_frames(fid)
            spec = spec_for(b, LOOKS[fid], F2.FOLKS[fid][0]["male"])
            for c, fr in enumerate(frs):
                jobs.append(dict(id=f"{scene}_{row}_{c}", spec=spec, frame=fr, design=figures.js_design(DESIGN), variant="toy", view=view, px=px, shadow=True))
    if with_walkers:
        for row, (name, b0) in enumerate(F2.WALKERS):
            b, frs = walker_frames(name, b0)
            spec = spec_for(b, WALKER_LOOKS[name], b0["male"])
            for c, fr in enumerate(frs):
                jobs.append(dict(id=f"walkers_{row}_{c}", spec=spec, frame=fr, design=figures.js_design(DESIGN), variant="toy", view=view, px=px, shadow=True))
    return jobs


def pack(cells, name, rows):
    cw, ch = int(CELL[0] * SCALE), int(CELL[1] * SCALE)
    sheet = Image.new("RGBA", (cw * 8, ch * rows), (0, 0, 0, 0))
    for r in range(rows):
        for c in range(8):
            sheet.alpha_composite(figures.load(cells, f"{name}_{r}_{c}", (cw, ch)), (c * cw, r * ch))
    return sheet


def save_png(im, path):
    """256 色（误差扩散抖动），透明的地方 RGB 清零：同 scene3d / sprites3d 的 bake。"""
    arr = np.asarray(im.convert("RGBA"))
    arr = np.where(arr[..., 3:4] == 0, 0, arr).astype(np.uint8)
    Image.fromarray(arr, "RGBA").quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG).save(path, optimize=True)


# ----------------------------------------------------------------------
# 总览
# ----------------------------------------------------------------------

PICKS = [(0, "干活"), (2, "干活"), (4, "歇"), (7, "眨眼")]


def contact(path, scenes, names):
    bg = (236, 226, 210)
    sc = 0.62
    cw, ch = int(CELL[0] * sc), int(CELL[1] * sc)
    per = 3                       # 一行排三位
    lab = 26
    blockw = cw * len(PICKS) + 20
    folks = [(scene, row, fid) for scene, ids in scenes for row, fid in enumerate(ids)]
    nrow = (len(folks) + per - 1) // per
    wrows = (len(F2.WALKERS) + 1) // 2
    gh = CELL[1] * 2 + 60
    W = 20 + blockw * per
    H = 70 + (ch + lab) * nrow + 50 + (ch + lab) * wrows + gh + 20
    im = Image.new("RGBA", (W, H), bg + (255,))
    d = ImageDraw.Draw(im)
    f = figures.font
    d.text((16, 14), "《同岁》街坊和路人 · 微缩模型（同主角一盒小人）", fill=(70, 55, 60), font=f(30))
    cache = {}

    def sheet(n):
        if n not in cache:
            cache[n] = Image.open(os.path.join(OUT_DIR, n + ".png")).convert("RGBA")
        return cache[n]

    def cell(n, r, c, s=sc):
        S = SCALE
        im0 = sheet(n).crop((int(c * CELL[0] * S), int(r * CELL[1] * S), int((c + 1) * CELL[0] * S), int((r + 1) * CELL[1] * S)))
        return im0.resize((int(CELL[0] * s), int(CELL[1] * s)), Image.LANCZOS)

    y0 = 70
    for i, (scene, row, fid) in enumerate(folks):
        x = 20 + (i % per) * blockw
        y = y0 + (i // per) * (ch + lab)
        d.text((x + 4, y + 2), f"{scene} · {names.get(fid, fid)}", fill=(90, 70, 70), font=f(17))
        for j, (c, _n) in enumerate(PICKS):
            im.alpha_composite(cell(scene, row, c), (x + j * cw, y + lab))
    y = y0 + nrow * (ch + lab) + 10
    d.text((16, y + 6), "路人（走路 8 帧里挑 4 帧）", fill=(70, 55, 60), font=f(22))
    y += 40
    for i, (name, _b) in enumerate(F2.WALKERS):
        x = 20 + (i % 2) * (cw * 4 + 30)
        yy = y + (i // 2) * (ch + lab)
        d.text((x + 4, yy + 2), name, fill=(90, 70, 70), font=f(17))
        for j, c in enumerate((0, 2, 4, 6)):
            im.alpha_composite(cell("walkers", i, c), (x + j * cw, yy + lab))
    # 原大：先放两个主角（青年、站），再放每位街坊歇着那一帧、路人
    y = H - gh - 10
    d.text((16, y), "游戏里原大（1 世界像素 = 1 像素）：左边两个是主角", fill=(70, 55, 60), font=f(20))
    x = 10
    for role in ("qing", "mei"):
        a = Image.open(os.path.join(ROOT, "client", "art", "actors", f"{role}_young.png")).convert("RGBA")
        c0 = a.crop((0, CELL[1] * 2, CELL[0] * 2, CELL[1] * 4)).resize(CELL, Image.LANCZOS).crop((50, 0, 150, CELL[1]))
        im.alpha_composite(c0, (x, y + 26))
        x += 56
    x += 20
    # 街坊（歇着那一帧）+ 路人，分两排，一个挨一个站（像一条街上的人）
    row_imgs = [cell(sc_, r_, 4, 1.0) for sc_, r_, _f in folks] + [cell("walkers", i, 1, 1.0) for i in range(len(F2.WALKERS))]
    half = (len(row_imgs) + 1) // 2
    for k, ci in enumerate(row_imgs):
        line, j = divmod(k, half)
        x0 = x + j * ((W - x - 110) // max(1, half - 1)) if line == 0 else 10 + j * ((W - 120) // max(1, half - 1))
        im.alpha_composite(ci.crop((50, 0, 150, CELL[1])), (x0, y + 26 + line * (CELL[1] + 10)))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.convert("RGB").save(path, optimize=True)
    print("✓", path)


def try_out(path, ids, cols=(0, 2, 4), zoom=1.6):
    """调长相用：几位街坊 / 路人，各挑几格放大拼一张（不写表）。"""
    jobs, rows = [], []
    view = figures.view_cell()
    px = [int(CELL[0] * zoom * SS), int(CELL[1] * zoom * SS)]
    for fid in ids:
        if fid in LOOKS:
            b, frs = folk_frames(fid)
            spec = spec_for(b, LOOKS[fid], F2.FOLKS[fid][0]["male"])
        else:
            b0 = dict(F2.WALKERS)[fid]
            b, frs = walker_frames(fid, b0)
            spec = spec_for(b, WALKER_LOOKS[fid], b0["male"])
        for c in cols:
            jobs.append(dict(id=f"t_{fid}_{c}", spec=spec, frame=frs[c], design=figures.js_design(DESIGN), variant="toy", view=view, px=px, shadow=True))
        rows.append(fid)
    cells = figures.run_jobs(jobs, page=PAGE)
    cw, ch = int(CELL[0] * zoom), int(CELL[1] * zoom)
    per = max(1, 12 // len(cols))
    nr = (len(rows) + per - 1) // per
    im = Image.new("RGBA", (cw * len(cols) * min(per, len(rows)), (ch + 24) * nr), (236, 226, 210, 255))
    d = ImageDraw.Draw(im)
    for i, fid in enumerate(rows):
        x, y = (i % per) * cw * len(cols), (i // per) * (ch + 24)
        d.text((x + 6, y + 2), fid, fill=(90, 70, 70), font=figures.font(18))
        for j, c in enumerate(cols):
            im.alpha_composite(figures.load(cells, f"t_{fid}_{c}", (cw, ch)), (x + j * cw, y + 24))
    im.convert("RGB").save(path)
    shutil.rmtree(os.path.dirname(cells), ignore_errors=True)
    print("✓", path)


# ----------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="只出这几张图（逗号分隔），加 walkers 出路人")
    ap.add_argument("--no-render", action="store_true", help="不渲染，只拼总览")
    ap.add_argument("--contact", default=CONTACT, help="总览存哪（空串 = 不拼）")
    ap.add_argument("--workers", type=int, default=0)
    ap.add_argument("--try", dest="try_", default="", help="调长相：几位的 id（逗号分隔），拼一张放大的到 --out")
    ap.add_argument("--out", default="folks_try.png")
    a = ap.parse_args()
    if a.try_:
        try_out(a.out, a.try_.split(","))
        return
    folks = json.load(open(FOLKS_JSON, encoding="utf-8"))
    missing = [n["id"] for lst in folks.values() for n in lst if n["id"] not in LOOKS or n["id"] not in F2.FOLKS]
    if missing:
        sys.exit("这几位还没有长相（folks3d.py 的 LOOKS / folks.py 的 FOLKS）：" + ", ".join(missing))
    names = {n["id"]: n.get("name", n["id"]) for lst in folks.values() for n in lst}
    scenes = [(s, [n["id"] for n in lst]) for s, lst in sorted(folks.items())]
    only = set(a.only.split(",")) if a.only else None
    if not a.no_render:
        t = time.time()
        todo = [(s, ids) for s, ids in scenes if not only or s in only]
        walk = not only or "walkers" in only
        jobs = jobs_for(todo, walk)
        cells = figures.run_jobs(jobs, workers=a.workers or None, page=PAGE)
        os.makedirs(OUT_DIR, exist_ok=True)
        for s, ids in todo:
            path = os.path.join(OUT_DIR, f"{s}.png")
            save_png(pack(cells, s, len(ids)), path)
            print("✓", os.path.relpath(path, ROOT))
        if walk:
            path = os.path.join(OUT_DIR, "walkers.png")
            save_png(pack(cells, "walkers", len(F2.WALKERS)), path)
            print("✓", os.path.relpath(path, ROOT))
        shutil.rmtree(os.path.dirname(cells), ignore_errors=True)
        index = {"scale": SCALE, "cell": list(CELL), "foot": list(FOOT), "scenes": {}, "folks": {}, "walkers": [w[0] for w in F2.WALKERS]}
        for s, ids in scenes:
            index["scenes"][s] = ids
            for row, fid in enumerate(ids):
                _b, _fn, sit, bubbles = F2.FOLKS[fid]
                index["folks"][fid] = {"scene": s, "row": row, "sit": sit, "bubbles": bubbles}
        with open(os.path.join(OUT_DIR, "index.json"), "w", encoding="utf-8") as fh:
            json.dump(index, fh, ensure_ascii=False, indent=1)
            fh.write("\n")
        print("✓", os.path.relpath(os.path.join(OUT_DIR, "index.json"), ROOT), f"（共 {time.time() - t:.0f} s）")
    if a.contact:
        contact(a.contact, scenes, names)


if __name__ == "__main__":
    main()
