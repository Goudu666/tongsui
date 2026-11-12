#!/usr/bin/env python3
"""像素版的街景精灵：沿用 street.py 的画法（街坊、摊子、车、随年代换的街景），只换「怎么落成像素」。

每 3 个世界像素一个点；画的时候线和块都落在点上（pxsprite.crisp），合成用 pxlib，出图每个点放大 3 倍：
贴图 1 像素 = 1 世界像素，sprites.json 的 scale = 1，w / h / foot 都是贴图像素（= 世界像素），都是 3 的倍数，
foot 落在格子角上：引擎把脚底摆在格子上（x % 3 == 0、(y + 200) % 3 == 0）就和底图的点对得上。

和 street.py 不一样的几处：
  · 字：街上的牌子小，点阵字最小也有 8 个点高，放不下。比 8 个点小的字落成「小字」：每个字缩成几个点的一小块
    （远看是一行字，凑近也不是糊的灰）；够大的照常用缝合像素。
  · 贴地的影子（墨的浅色、不在纸版里）出成半透明的影子色，不再是一块实的。
  · street.py 要的老 actors 画法在 legacy_actors.py（actors.py 重写以后没有了）。

    python3 tools/art/pixel/pxstreet.py                    →  client/art/street/atlas.png + sprites.json
    python3 tools/art/pixel/pxstreet.py --sheet /tmp/s.png   另存一张带名字的总览图（放大看）
"""
from __future__ import annotations

import json
import math
import os
import sys
from contextlib import contextmanager

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)
import riso  # noqa: E402
import scenes  # noqa: E402
import pxlib  # noqa: E402
import pxsprite  # noqa: E402

pxlib.enable()
import legacy_actors  # noqa: E402

sys.modules["actors"] = legacy_actors
import street  # noqa: E402

PX = pxlib.PX
OUT_DIR = street.OUT_DIR
ATLAS_W = 2048
SHADE = pxlib.C["shade"]
SHADOW_A = 0.36          # 贴地影子压多深（半透明的影子色）
GY = int(pxlib.GRID0[1])


# ----------------------------------------------------------------------
# 小字
# ----------------------------------------------------------------------

_F12 = None


def small_glyphs(text, h, vertical=False):
    """一行（或一竖行）字，每个字缩成 h×h 个点的一小块：12px 点阵字按面积缩，过一道阈值。"""
    global _F12
    if _F12 is None:
        _F12 = ImageFont.truetype(pxlib.FONTS[12], 12)
    cells = []
    for ch in text:
        im = Image.new("L", (14, 14), 0)
        ImageDraw.Draw(im).text((1, 0), ch, font=_F12, fill=255)
        bb = im.getbbox()
        if bb is None:
            cells.append(np.zeros((h, max(1, h // 2)), np.uint8))
            continue
        im = im.crop(bb)
        ww = h if im.width > im.height * 0.7 else max(1, int(round(h * im.width / max(im.height, 1))))
        a = np.asarray(im.resize((ww, h), Image.BOX), np.float32) / 255.0
        cells.append((a > 0.36).astype(np.uint8) * 255)
    gap = 1
    if vertical:
        W = max(c.shape[1] for c in cells)
        out = np.zeros((len(cells) * (h + gap) - gap, W), np.uint8)
        for i, c in enumerate(cells):
            out[i * (h + gap):i * (h + gap) + h, (W - c.shape[1]) // 2:(W - c.shape[1]) // 2 + c.shape[1]] = c
    else:
        W = sum(c.shape[1] for c in cells) + gap * (len(cells) - 1)
        out = np.zeros((h, W), np.uint8)
        x = 0
        for c in cells:
            out[:, x:x + c.shape[1]] = c
            x += c.shape[1] + gap
    return Image.fromarray(out, "L")


def text_mask(g, text, x, y, size, anchor="mm", vertical=False):
    """和 pxlib._pixel_text_mask 一样落在格子上；字小（不到 8 个点）就用小字。"""
    a = size / PX
    if a >= 7.5:
        return pxlib._pixel_text_mask(g, text, x, y, size, anchor, vertical)
    h = max(3, int(round(a)) + 1)
    gl = small_glyphs(text, h, vertical)
    gx, gy, s = pxlib._grid(g)
    S = g.scale
    big = gl.resize((int(round(gl.width * s)), int(round(gl.height * s))), Image.NEAREST)
    px = (x - g.origin[0]) * S
    py = (y - g.origin[1]) * S
    ax = {"l": 0, "m": 0.5, "r": 1}[anchor[0]]
    ay = {"t": 0, "m": 0.5, "b": 1, "s": 0.85}[anchor[1]]
    ox = int(round(gx + round((px - ax * big.width - gx) / s) * s))
    oy = int(round(gy + round((py - ay * big.height - gy) / s) * s))
    return big, ox, oy


@contextmanager
def small_text():
    """印街景时换上小字（写字的 Sheet.text 和挖字的 scenes.knock 都换）。"""
    old_text, old_knock = riso.Sheet.text, scenes.knock

    def text(self, color, tint, s, x, y, size, anchor="mm", density=1.0, vertical=False):
        r = text_mask(self, s, x, y, size, anchor, vertical)
        if r is None:
            return
        img, ox, oy = r
        self._blit(color, "tint" if tint else "solid", img, ox, oy, density)

    def knock(g, color, txt, x, y, size, vertical=False, layer="solid"):
        r = text_mask(g, txt, x, y, size, "mm", vertical)
        if r is None:
            return
        img, ox, oy = r
        m = np.asarray(img, np.float32) / 255.0
        H, W = m.shape
        x0, y0 = max(0, ox), max(0, oy)
        x1, y1 = min(g.W, ox + W), min(g.H, oy + H)
        if x1 <= x0 or y1 <= y0:
            return
        surf = g._surfaces[(color, layer)]
        surf.flush()
        buf = np.ndarray((g.H, surf.get_stride()), np.uint8, surf.get_data())
        sub = buf[y0:y1, x0:x1].astype(np.float32)
        sub *= 1.0 - m[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
        buf[y0:y1, x0:x1] = sub.astype(np.uint8)
        surf.mark_dirty()

    riso.Sheet.text = text
    street._ko_abs = knock
    try:
        yield
    finally:
        riso.Sheet.text = old_text
        street._ko_abs = old_knock


# ----------------------------------------------------------------------
# 印
# ----------------------------------------------------------------------

# 人（街坊、骑车的）：里线换色（pxsprite.selout）；车、牌子、对岸的楼照旧是墨线
PEOPLE = {n for n, sp in street.SPRITES.items() if sp["draw"].__qualname__.startswith(("person.", "cyclist."))} | {"waimai"}


def frame_dims(sp):
    """一帧多少个点宽、高，脚底在第几个点（格子角）。"""
    fw = int(math.ceil(sp["w"] / PX))
    fh = int(math.ceil(sp["h"] / PX))
    fx = int(round(sp["foot"][0] / PX))
    fy = int(round(sp["foot"][1] / PX))
    return fw, fh, fx, fy


def render(name):
    """一张精灵（几帧横排）：回来每个点一个像素的 RGBA。"""
    sp = street.SPRITES[name]
    fw, fh, fx, fy = frame_dims(sp)
    n = sp["frames"]
    W, H = fw * PX * n, fh * PX
    # 纸的原点放在格子原点上：纸像素 3 的倍数就是格子角
    g = riso.Sheet(W, H, 1.0, origin=(0.0, float(GY)), seed=11)
    with pxsprite.crisp(g), small_text():
        for i in range(n):
            g._seed = 1000 + sum(map(ord, name))
            frame = riso.rect_pts(i * fw * PX, GY, fw * PX, H)
            with g.clip(frame):
                with legacy_actors.place(g, i * fw * PX + fx * PX, GY + fy * PX):
                    sp["draw"](g, i)
    d, pa, marks = pxlib.plates(g, (0, H, 0, W))
    col, alpha, line = pxlib.compose(d, pa, marks, PX, gx=0, gy=0)
    pl = pxsprite.pooled(d, pa)
    col, alpha, line = pxsprite.clean(col, alpha, line, pl)
    if name in PEOPLE:
        col, line = pxsprite.selout(col, alpha, line)
    rgba = pxsprite.finish(col, alpha, line)
    return ground_shadow(rgba, pl)


def ground_shadow(rgba, pl):
    """墨的浅色、不在纸版里、也没被别的东西盖住的那一抹（street.ground_shadow 的椭圆）：出成半透明的影子色。"""
    flo = (pl["ink_t"] > 0.08) & (pl["paper"] < 0.34) & (rgba[..., 3] == 0)
    out = rgba.copy()
    out[flo, :3] = SHADE.astype(np.uint8)
    out[flo, 3] = int(SHADOW_A * 255)
    return out


def pack(images):
    """按高度排架子；位置都是 3 的倍数（一个点 = 3×3），中间空 3 像素。"""
    order = sorted(images, key=lambda n: (-images[n].shape[0], n))
    x = y = shelf = 0
    pos = {}
    for n in order:
        h, w = images[n].shape[0] * PX, images[n].shape[1] * PX
        if x + w > ATLAS_W:
            x, y, shelf = 0, y + shelf + PX, 0
        pos[n] = (x, y)
        x += w + PX
        shelf = max(shelf, h)
    atlas = np.zeros((y + shelf, ATLAS_W, 4), dtype=np.uint8)
    for n, (px, py) in pos.items():
        big = pxlib.up(images[n], PX)
        atlas[py:py + big.shape[0], px:px + big.shape[1]] = big
    return atlas, pos


def contact_sheet(images, path, zoom=2):
    names = list(images)
    cols = 6
    tiles = {n: Image.fromarray(pxlib.up(images[n], PX * zoom), "RGBA") for n in names}
    cw = max(t.width for t in tiles.values()) + 16
    ch = max(t.height for t in tiles.values()) + 30
    rows = math.ceil(len(names) / cols)
    out = Image.new("RGB", (cols * cw, rows * ch), (0xD9, 0xC3, 0xA5))
    d = ImageDraw.Draw(out)
    f = ImageFont.truetype(pxlib.FONTS[12], 12)
    for k, n in enumerate(names):
        ox, oy = (k % cols) * cw + 8, (k // cols) * ch + 22
        out.paste(tiles[n], (ox, oy), tiles[n])
        d.text((ox, oy - 18), n, font=f, fill=(0x28, 0x1D, 0x2C))
    out.save(path)


def main(argv):
    only = [a for a in argv if a in street.SPRITES]
    names = only or list(street.SPRITES)
    images = {n: render(n) for n in names}
    if "--sheet" in argv:
        path = argv[argv.index("--sheet") + 1]
        contact_sheet(images, path)
        print("总览：", path)
        if only:
            return
    atlas, pos = pack(images)
    os.makedirs(OUT_DIR, exist_ok=True)
    if atlas.shape[0] > 2048:
        print(f"⚠ 图集高 {atlas.shape[0]}，超过 2048")
    Image.fromarray(atlas, "RGBA").save(os.path.join(OUT_DIR, "atlas.png"), optimize=True)
    meta = {"scale": 1.0, "px": PX, "sprites": {}}
    for n in names:
        sp = street.SPRITES[n]
        fw, fh, fx, fy = frame_dims(sp)
        meta["sprites"][n] = {"x": pos[n][0], "y": pos[n][1], "w": fw * PX, "h": fh * PX, "frames": sp["frames"],
                              "foot": [fx * PX, fy * PX]}
    with open(os.path.join(OUT_DIR, "sprites.json"), "w", encoding="utf-8") as fp:
        json.dump(meta, fp, ensure_ascii=False, indent=1)
    size = os.path.getsize(os.path.join(OUT_DIR, "atlas.png"))
    print(f"✓ {len(names)} 个精灵 → {os.path.relpath(OUT_DIR, riso.ROOT)}/atlas.png（{atlas.shape[1]}×{atlas.shape[0]}，{size / 1e6:.2f} MB）")


if __name__ == "__main__":
    main(sys.argv[1:])
