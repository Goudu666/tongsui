"""生成河畔里地图：python3 tools/art/build_map.py

输出到 client/art/map/：
  ground_{col}_{row}.png   地面层切片（每片 800×800 世界像素，2 倍输出 = 1600×1600）
  over_{col}_{row}.png     上层切片（白底，引擎里用正片叠底盖在角色上面；全白的片不输出）
  walk.png                 可走区域（10 世界像素一格，白 = 能走）
  anchors.json             环境动画锚点

预览某一块（调美术时用，快）：
  python3 tools/art/build_map.py --region 1400,250,500,450 --scale 1 --out /tmp/x.png [--walk]
"""
from __future__ import annotations

import argparse
import importlib
import json
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "hepanli"))

from riso import ROOT, Sheet  # noqa: E402
from common import MAP, SPOTS, W, H, Ctx, WalkMask  # noqa: E402

# 画的顺序：先铺地，再画大块，后画的可以挖空盖住先画的
MODULES = ["ground", "street", "building", "breakfast", "teahouse", "river", "bikeshop", "school", "south", "landmarks"]
TILE = 800
MARGIN = 16
OUT = os.path.join(ROOT, "client", "art", "map")


def run_modules(g, o, walk, anchors, only=None):
    ctx = Ctx(g, o, walk, anchors)
    for name in MODULES:
        if only and name not in only:
            continue
        try:
            mod = importlib.import_module(name)
        except ModuleNotFoundError as e:
            if e.name == name:
                continue
            raise
        mod.draw(ctx)


def collect_walk_and_anchors():
    walk = WalkMask()
    anchors: dict = {}
    # 用一张极小的印张跑一遍，只为了拿到可走区域和锚点
    g = Sheet(8, 8, 1.0)
    o = Sheet(8, 8, 1.0)
    run_modules(g, o, walk, anchors)
    return walk, anchors


def check_walk(walk: WalkMask):
    """所有互动点、出生点都要能走到，而且彼此连通。"""
    cell = 10
    small = walk.img.resize((W // cell, H // cell), Image.BOX)
    grid = np.asarray(small) > 127
    pts = {sid: s["at"] for sid, s in SPOTS.items()}
    for r, p in MAP["spawn"].items():
        pts["spawn_" + r] = p
    bad = [k for k, (x, y) in pts.items() if not grid[int(y // cell), int(x // cell)]]
    if bad:
        print("⚠ 这些点不在可走区域里：", bad)
        return grid, False
    sx, sy = pts["spawn_qing"]
    seen = np.zeros_like(grid)
    q = deque([(int(sy // cell), int(sx // cell))])
    seen[q[0]] = True
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < grid.shape[0] and 0 <= nx < grid.shape[1] and grid[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    lost = [k for k, (x, y) in pts.items() if not seen[int(y // cell), int(x // cell)]]
    if lost:
        print("⚠ 这些点走不到（和青的出生点不连通）：", lost)
    return grid, not lost


def _save_png(arr, path):
    """三块墨叠出来的颜色本来就少：量化成 64 色调色板 PNG，肉眼无差，体积小四倍。"""
    img = Image.fromarray(arr, "RGB").quantize(colors=64, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    img.save(path, optimize=True)


def render_region(x, y, w, h, scale, only=None):
    g = Sheet(w, h, scale, origin=(x, y))
    o = Sheet(w, h, scale, origin=(x, y))
    run_modules(g, o, WalkMask(), {}, only)
    return g.composite(True), o.composite(False)


def build_all(scale=2.0):
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.startswith(("ground_", "over_")) and f.endswith(".png"):
            os.remove(os.path.join(OUT, f))
    walk, anchors = collect_walk_and_anchors()
    grid, ok = check_walk(walk)
    Image.fromarray((grid * 255).astype(np.uint8), "L").save(os.path.join(OUT, "walk.png"))
    with open(os.path.join(OUT, "anchors.json"), "w", encoding="utf-8") as f:
        json.dump({"tile": TILE, "scale": scale, "size": [W, H], "anchors": anchors}, f, ensure_ascii=False, indent=1)
    m = int(MARGIN * scale)
    for row in range(H // TILE):
        for col in range(W // TILE):
            x0, y0 = col * TILE - MARGIN, row * TILE - MARGIN
            gimg, oimg = render_region(x0, y0, TILE + 2 * MARGIN, TILE + 2 * MARGIN, scale)
            gimg = gimg[m:-m, m:-m]
            oimg = oimg[m:-m, m:-m]
            _save_png(gimg, os.path.join(OUT, f"ground_{col}_{row}.png"))
            if oimg.min() < 250:
                _save_png(oimg, os.path.join(OUT, f"over_{col}_{row}.png"))
            print(f"  切片 {col},{row} ✓")
    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
    print(f"✓ 河畔里地图已生成：{OUT}（{total / 1e6:.1f} MB）{'' if ok else '  ⚠ 可走区域有问题，见上'}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--region", help="x,y,w,h 只预览这一块")
    ap.add_argument("--scale", type=float, default=2.0)
    ap.add_argument("--out", help="预览图输出路径")
    ap.add_argument("--walk", action="store_true", help="预览时把可走区域叠成淡青色、互动点画红圈")
    ap.add_argument("--only", help="只画这些模块（逗号分隔），调试用")
    a = ap.parse_args()
    if not a.region:
        build_all(a.scale)
        return
    x, y, w, h = map(int, a.region.split(","))
    only = a.only.split(",") if a.only else None
    gimg, oimg = render_region(x, y, w, h, a.scale, only)
    img = (gimg.astype(np.float32) * oimg.astype(np.float32) / 255.0).astype(np.uint8)
    if a.walk:
        walk, _ = collect_walk_and_anchors()
        grid, _ = check_walk(walk)
        big = np.asarray(Image.fromarray((grid * 255).astype(np.uint8)).resize((int(W * a.scale), int(H * a.scale)), Image.NEAREST))
        sub = big[int(y * a.scale) : int((y + h) * a.scale), int(x * a.scale) : int((x + w) * a.scale)] > 127
        sub = sub[: img.shape[0], : img.shape[1]]
        img = img.astype(np.float32)
        img[sub] = img[sub] * 0.75 + np.array([60, 200, 255]) * 0.25
        img = img.astype(np.uint8)
        from PIL import ImageDraw

        pil = Image.fromarray(img)
        d = ImageDraw.Draw(pil)
        for s in SPOTS.values():
            sx, sy = (s["at"][0] - x) * a.scale, (s["at"][1] - y) * a.scale
            d.ellipse([sx - 6, sy - 6, sx + 6, sy + 6], outline=(255, 0, 0), width=2)
        img = np.asarray(pil)
    Image.fromarray(img, "RGB").save(a.out or "/tmp/hepanli_preview.png")
    print("预览：", a.out)


if __name__ == "__main__":
    main()
