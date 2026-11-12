#!/usr/bin/env python3
"""底图：录显示列表 → three.js 出切片 → 收进 client/art/scenes/（和孔版时一样的切片、mask、anchors.json）。

    python3 tools/art/diorama/scene3d/bake.py [图 id ...] [--variant toy]

要先在 tools/art 下起 http 服务：python3 -m http.server 8765
"""
from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import record  # noqa: E402

scenes = record.scenes
OUT = scenes.OUT
SCALE = 1.25


def save_png(arr, path):
    # 3D 渲染：压成 256 色（误差扩散抖动，看不出色带），一片 1280×1500 从 600KB 降到 100KB 上下
    a = arr[..., 3:4]
    arr = np.where(a == 0, 0, arr).astype(np.uint8)
    img = Image.fromarray(arr, "RGBA").quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG)
    img.save(path, optimize=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--variant", default="toy")
    a = ap.parse_args()
    record.enable()
    allsc = scenes.load_scenes()
    ids = a.ids or list(scenes.DRAW)
    apath = os.path.join(OUT, "anchors.json")
    allanch = {}
    if os.path.exists(apath):
        with open(apath, encoding="utf-8") as f:
            allanch = json.load(f).get("scenes", {})
    for sid in ids:
        d = record.record(sid)
        with open(os.path.join(HERE, "out", f"{sid}.json"), "w", encoding="utf-8") as f:
            json.dump(d, f, ensure_ascii=False, separators=(",", ":"))
        allanch[sid] = d["anchors"]
    subprocess.run(["node", os.path.join(HERE, "bake.js"), *ids, "--variant", a.variant, "--scale", str(SCALE)], check=True)
    with open(apath, "w", encoding="utf-8") as f:
        json.dump({"slice": scenes.SLICE, "top": scenes.TOP, "bottom": scenes.BOTTOM, "scale": SCALE, "scenes": allanch}, f,
                  ensure_ascii=False, separators=(",", ":"))
    for sid in ids:
        sc = allsc[sid]
        n = math.ceil(sc["width"] / scenes.SLICE)
        keep = {f"{sid}_{k}.png.import" for k in range(n)} | {f"{sid}_mask.png.import"}
        for f in sorted(os.listdir(OUT)):
            if f.startswith(sid + "_") and (f.endswith(".png") or f.endswith(".png.import")) and f not in keep:
                os.remove(os.path.join(OUT, f))
        masks = []
        for k in range(n):
            arr = np.asarray(Image.open(os.path.join(HERE, "out", "tiles", f"{sid}_{k}.png")).convert("RGBA"))
            save_png(arr, os.path.join(OUT, f"{sid}_{k}.png"))
            masks.append(arr[:, :, 3])
        full = np.concatenate(masks, axis=1)[:, : int(round(sc["width"] * SCALE))]
        mw, mh = int(math.ceil(sc["width"] / scenes.MASK_STEP)), int((scenes.BOTTOM - scenes.TOP) / scenes.MASK_STEP)
        Image.fromarray(full, "L").resize((mw, mh), Image.BOX).save(os.path.join(OUT, f"{sid}_mask.png"), optimize=True)
        size = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT) if f.startswith(sid + "_") and f.endswith(".png"))
        print(f"  {sid}（{sc['name']}）{n} 片  {size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
