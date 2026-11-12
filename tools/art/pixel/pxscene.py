#!/usr/bin/env python3
"""像素版的十几张图：沿用 scenes.py 的画法，换掉合成那一步（见 pxlib）。

整张图按 3×3 世界像素一个点收拢；一段一段画（每段宽度是 3 的倍数，格子在各段之间对得上），
拼成整张点图，再按 scenes.py 的切片规矩切开输出：每片 SLICE 世界像素宽，每个点放大成 3×3
（贴图一个像素 = 一个世界像素，引擎里 ART_SCALE = 1）。

    python3 tools/art/pixel/pxscene.py --preview street --x 1000 --w 2000 --out /tmp/x.png
    python3 tools/art/pixel/pxscene.py --fit-palette            # 从十几张图里抽色，定调色板
    python3 tools/art/pixel/pxscene.py [图 id ...]              # 出图 → client/art/scenes/
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)
import scenes  # noqa: E402
import pxlib  # noqa: E402

PX = pxlib.PX
CHUNK = 1200          # 每段画多宽（世界像素，3 的倍数）
M = 48                # 每段两边多画一截（3 的倍数），裁掉
OUT_SCALE = 1.0       # 贴图像素 / 世界像素


def vshade(sc):
    """墙越往下越沉、贴地那一截压暗（和 scenes.relief 一个意思），每行一个数。"""
    ys = scenes.TOP + (np.arange((scenes.BOTTOM - scenes.TOP) // PX) + 0.5) * PX
    out = np.zeros_like(ys)
    prev = scenes.TOP
    for fy in sc.get("floors", [scenes.GROUND]):
        inside = (ys >= prev) & (ys < fy)
        t = np.clip((ys - prev) / max(fy - prev, 1.0), 0, 1)
        out += inside * (0.08 * t ** 1.6 + 0.20 * np.clip(1 - (fy - ys) / 60.0, 0, 1) ** 2)
        below = (ys >= fy) * np.clip(1 - (ys - fy) / 24.0, 0, 1)
        out += 0.12 * below ** 2
        prev = fy
    return out.astype(np.float32)


def chunk(sc, x, w):
    """画 [x, x+w) 一段（x、w 都是 3 的倍数），回来每个点的颜色。"""
    top = scenes.TOP
    g = scenes.OSheet(w + 2 * M, (scenes.BOTTOM - top) + 2 * M, 1.0, origin=(x - M, top - M), seed=7)
    scenes.DRAW[sc["id"]](g, sc)
    d, pa, br = pxlib.plates(g, (M, M + scenes.BOTTOM - top, M, M + w))
    return pxlib.compose(d, pa, br, PX, gx=x // PX, gy=int(top - pxlib.GRID0[1]) // PX, vshade=vshade(sc))


def render_cols(sc, x0, x1):
    x0 = int(x0) // PX * PX
    x1 = int(math.ceil(x1 / PX)) * PX
    parts = []
    x = x0
    while x < x1:
        w = min(CHUNK, x1 - x)
        parts.append(chunk(sc, x, w))
        x += w
    col = np.concatenate([p[0] for p in parts], 1)
    al = np.concatenate([p[1] for p in parts], 1)
    ln = np.concatenate([p[2] for p in parts], 1)
    return col, al, ln, x0


def render(sc, x0, x1, cent=None):
    col, al, ln, x0 = render_cols(sc, x0, x1)
    return pxlib.finish(col, al, ln, cent, gx=x0 // PX, gy=int(scenes.TOP - pxlib.GRID0[1]) // PX), x0


def fit_palette(ids):
    sc_all = scenes.load_scenes()
    cols = []
    for sid in ids:
        sc = sc_all[sid]
        W = sc["width"]
        for x in np.linspace(0, max(0, W - 1200), 3):
            col, al, ln, _ = render_cols(sc, x, x + 1200)
            cols.append(col[(al > 0.5) & ~ln])
        print("  抽色", sid)
    cent = pxlib.fit_palette(cols, k=47)
    pxlib.save_palette(cent)
    print("调色板 →", pxlib.PAL_PATH, len(cent), "色")


def build(ids):
    out = scenes.OUT
    os.makedirs(out, exist_ok=True)
    sc_all = scenes.load_scenes()
    cent = pxlib.load_palette()
    apath = os.path.join(out, "anchors.json")
    allanch = {}
    if os.path.exists(apath):
        with open(apath, encoding="utf-8") as f:
            allanch = json.load(f).get("scenes", {})
    for sid in ids:
        allanch[sid] = scenes.collect_anchors(sc_all[sid])
    with open(apath, "w", encoding="utf-8") as f:
        json.dump({"slice": scenes.SLICE, "top": scenes.TOP, "bottom": scenes.BOTTOM, "scale": OUT_SCALE, "px": PX,
                   "scenes": allanch}, f, ensure_ascii=False, separators=(",", ":"))
    for sid in ids:
        sc = sc_all[sid]
        W = int(sc["width"])
        arr, x0 = render(sc, 0, W, cent)
        big = pxlib.up(arr, PX)[:, :W]
        n = math.ceil(W / scenes.SLICE)
        keep = {f"{sid}_{k}.png.import" for k in range(n)} | {f"{sid}_mask.png.import"}
        for f in sorted(os.listdir(out)):
            if f.startswith(sid + "_") and (f.endswith(".png") or f.endswith(".png.import")) and f not in keep:
                os.remove(os.path.join(out, f))
        for k in range(n):
            sl = big[:, k * scenes.SLICE:(k + 1) * scenes.SLICE]
            save_png(sl, os.path.join(out, f"{sid}_{k}.png"))
        mw, mh = int(math.ceil(W / scenes.MASK_STEP)), int((scenes.BOTTOM - scenes.TOP) / scenes.MASK_STEP)
        Image.fromarray(big[:, :, 3], "L").resize((mw, mh), Image.BOX).save(os.path.join(out, f"{sid}_mask.png"), optimize=True)
        size = sum(os.path.getsize(os.path.join(out, f)) for f in os.listdir(out) if f.startswith(sid + "_") and f.endswith(".png"))
        print(f"  {sid}（{sc['name']}）{n} 片 ✓  {size / 1e6:.1f} MB")


def save_png(arr, path):
    img = Image.fromarray(np.ascontiguousarray(arr), "RGBA")
    img = img.quantize(colors=64, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    img.save(path, optimize=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--preview")
    ap.add_argument("--x", type=float, default=0)
    ap.add_argument("--w", type=float, default=1920)
    ap.add_argument("--out", default="/tmp/pxscene.png")
    ap.add_argument("--zoom", type=int, default=2)
    ap.add_argument("--fit-palette", action="store_true")
    a = ap.parse_args()
    pxlib.enable()
    scenes.ANCHORS = None
    if a.fit_palette:
        fit_palette(a.ids or list(scenes.DRAW))
        return
    if a.preview:
        sc = scenes.load_scenes()[a.preview]
        arr, _ = render(sc, a.x, a.x + a.w)
        bg = np.zeros_like(arr)
        bg[...] = (150, 170, 200, 255)
        al = arr[..., 3:4] / 255.0
        comp = (arr[..., :3] * al + bg[..., :3] * (1 - al)).astype(np.uint8)
        Image.fromarray(pxlib.up(comp, a.zoom)).save(a.out)
        print(a.out, comp.shape)
        return
    build(a.ids or list(scenes.DRAW))


if __name__ == "__main__":
    main()
