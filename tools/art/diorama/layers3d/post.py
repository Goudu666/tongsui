#!/usr/bin/env python3
"""把 bake.js 拍的原图（out/raw/，S 倍超采样）收成游戏用的贴图：缩回原大小、按远近虚化，写进 client/art/layers/（太大的才减色）。

    python3 post.py                 # 全部
    python3 post.py tree far        # 名字里带这几个字的
    python3 post.py --preview /mnt/project-files/tongsui/art/diorama/layers_preview.png   # 顺手拼一张预览

尺寸沿用 tools/art/layers.py（孔版时的契约，引擎里 FAR_SCALE 0.62、MID_SCALE 0.9、FORE_SCALE 1.8、树 1/1.25 再缩放）：
  远景 far_<年代>.png 2048×620、门外 far_sea / far_village 2048×300、中景 mid_<年代>.png 2048×640、
  前景 fore_<种>.png 2048×240、树 tree_<种>_<季>.png 画布 × 1.25。
远景、中景还有 _lit.png（灰度，和画同样大）：夜里哪些窗亮，引擎（far_layer.gdshader）读它的 r 点灯。
移轴景深：远景轻轻虚一点（引擎还会再虚一点），中景几乎不虚，前景虚得多（贴着镜头，对不上焦）；
横条虚化时左右接着算，平铺不出缝。
"""
from __future__ import annotations

import argparse
import glob
import os

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
RAW = os.path.join(HERE, "out", "raw")
OUT = os.path.join(ROOT, "client", "art", "layers")

TREES = {"huai": (620, 700), "willow": (640, 680), "young": (300, 380)}
# 种类 → (宽, 高, 虚多少（目标像素的 σ）)
STRIPS = {"far": (2048, 620, 1.1), "place": (2048, 300, 0.9), "mid": (2048, 640, 0.45), "fore": (2048, 240, 2.4)}


def spec(name):
    if name.startswith("tree_"):
        kind = name.split("_")[1]
        w, h = TREES[kind]
        return round(w * 1.25), round(h * 1.25), 0.0, False
    if name.startswith("far_sea") or name.startswith("far_village"):
        return STRIPS["place"][0], STRIPS["place"][1], STRIPS["place"][2], True
    for k in ("far", "mid", "fore"):
        if name.startswith(k + "_"):
            w, h, s = STRIPS[k]
            return w, h, s, True
    raise ValueError(name)


def blur_rgba(img: Image.Image, sigma: float, wrap: bool) -> Image.Image:
    """预乘了 alpha 再虚，边上不起黑圈；横条左右接着虚。"""
    if sigma <= 0:
        return img
    a = np.asarray(img)
    p = int(sigma * 4) + 2
    if wrap:
        a = np.concatenate([a[:, -p:], a, a[:, :p]], axis=1)
    im = Image.fromarray(a, "RGBA").convert("RGBa").filter(ImageFilter.GaussianBlur(sigma)).convert("RGBA")
    a = np.asarray(im)
    if wrap:
        a = a[:, p:-p]
    return Image.fromarray(np.ascontiguousarray(a), "RGBA")


def blur_l(img: Image.Image, sigma: float, wrap: bool) -> Image.Image:
    a = np.asarray(img)
    p = int(sigma * 4) + 2
    if wrap:
        a = np.concatenate([a[:, -p:], a, a[:, :p]], axis=1)
    a = np.asarray(Image.fromarray(a, "L").filter(ImageFilter.GaussianBlur(sigma)))
    if wrap:
        a = a[:, p:-p]
    return Image.fromarray(np.ascontiguousarray(a), "L")


MAX_KB = 700


def save_rgba(img: Image.Image, path: str):
    """透明的地方 RGB 清零（不留脏色）；存全色 RGBA（圆球上的渐变不起台阶），太大了才减成 256 色。"""
    a = np.asarray(img).copy()
    a[a[..., 3] == 0, :3] = 0
    img = Image.fromarray(a, "RGBA")
    img.save(path, optimize=True)
    if os.path.getsize(path) <= MAX_KB * 1024:
        return
    # 减色前撒一点点噪点再量化，渐变上的台阶就散开了（PIL 的八叉树量化 RGBA 时不抖动）
    rnd = np.random.default_rng(7)
    b = a.astype(np.float32)
    b[..., :3] += rnd.uniform(-2.5, 2.5, b[..., :3].shape)
    b = np.clip(b, 0, 255).astype(np.uint8)
    b[a[..., 3] == 0, :3] = 0
    q = Image.fromarray(b, "RGBA").quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    q.save(path, optimize=True)


def process(name):
    w, h, sigma, wrap = spec(name)
    src = Image.open(os.path.join(RAW, name + ".png")).convert("RGBA")
    img = src.resize((w, h), Image.LANCZOS)
    img = blur_rgba(img, sigma, wrap)
    save_rgba(img, os.path.join(OUT, name + ".png"))
    lit_p = os.path.join(RAW, name + "_lit.png")
    lit = None
    if os.path.exists(lit_p):
        lit = Image.open(lit_p).convert("L").resize((w, h), Image.BOX)
        lit = blur_l(lit, max(0.5, sigma * 0.6), wrap)
        # 一圈淡淡的光晕（窗外头那点暖光）
        glow = np.asarray(blur_l(lit, 3.0, wrap)).astype(np.float32) * 0.5
        la = np.maximum(np.asarray(lit).astype(np.float32), glow)
        lit = Image.fromarray(np.clip(la, 0, 255).astype(np.uint8), "L")
        lit.save(os.path.join(OUT, name + "_lit.png"), optimize=True)
    return img, lit


def sky(w, h, top=(141, 170, 214), bot=(236, 222, 214)):
    t = np.linspace(0, 1, h)[:, None, None]
    a = np.array(top)[None, None] * (1 - t) + np.array(bot)[None, None] * t
    return Image.fromarray(np.repeat(a, w, axis=1).astype(np.uint8), "RGB").convert("RGBA")


def over(bg: Image.Image, fg: Image.Image, xy=(0, 0)):
    bg.alpha_composite(fg, xy)
    return bg


def night(img: Image.Image, lit: Image.Image | None):
    """预览用：照 far_layer.gdshader 的样子把白天的画压成夜里，再按 lit 点灯。"""
    a = np.asarray(img).astype(np.float32) / 255
    col = a[..., :3] * (np.array([0.17, 0.24, 0.50]) * 1.15 * 0.8 + 0.2)
    if lit is not None:
        l = np.asarray(lit).astype(np.float32)[..., None] / 255
        col = col * (1 - l * 0.95) + np.array([1.0, 0.86, 0.5]) * l * 0.95
    out = np.dstack([np.clip(col, 0, 1) * 255, a[..., 3:] * 255]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def preview(made: dict, path: str):
    W = 2100
    rows = []
    # 树：三种 × 四季，缩一半摆在天色上
    for kind in TREES:
        names = [f"tree_{kind}_{s}" for s in ("spring", "summer", "autumn", "winter")]
        ims = [made[n][0] for n in names if n in made]
        if not ims:
            continue
        ims = [im.resize((im.width // 2, im.height // 2), Image.LANCZOS) for im in ims]
        h = max(i.height for i in ims) + 20
        row = sky(W, h)
        x = 20
        for im in ims:
            over(row, im, (x, h - im.height - 10))
            x += im.width + 30
        rows.append(row)
    # 横条：远景、中景叠在一起看（白天一条、夜里一条），门外两条，前景几条
    strips = [n for n in made if not n.startswith("tree_")]
    for era, darks in (("child", (False,)), ("middle", (False, True)), ("old", (False,))):
        f, m = made.get(f"far_{era}"), made.get(f"mid_{era}")
        if not f and not m:
            continue
        for dark in darks:
            row = sky(W, 520) if not dark else sky(W, 520, (20, 28, 60), (70, 60, 90))
            if f:
                fi = f[0] if not dark else night(f[0], f[1])
                fi = fi.resize((round(fi.width * 0.62), round(fi.height * 0.62)), Image.LANCZOS)
                if not dark:  # 空气透视（引擎里 haze 0.42）
                    fa = np.asarray(fi).astype(np.float32)
                    fa[..., :3] = fa[..., :3] * 0.58 + np.array([230, 235, 224]) * 0.42
                    fi = Image.fromarray(fa.astype(np.uint8), "RGBA")
                for k in range(3):
                    over(row, fi, (k * fi.width, 470 - fi.height))
            if m:
                mi = m[0] if not dark else night(m[0], m[1])
                mi = mi.resize((round(mi.width * 0.9 * 0.6), round(mi.height * 0.9 * 0.6)), Image.LANCZOS)
                for k in range(3):
                    over(row, mi, (k * mi.width, 520 - mi.height))
            rows.append(row)
    for n in strips:
        if n.startswith("far_sea") or n.startswith("far_village") or n in ("fore_street", "fore_field", "fore_market"):
            im = made[n][0]
            sc = 1.0 if n.startswith("fore_") else 0.8
            im = im.resize((round(im.width * sc), round(im.height * sc)), Image.LANCZOS)
            row = sky(W, im.height + 20)
            over(row, im.crop((0, 0, min(W, im.width), im.height)), (0, 20))
            if im.width < W:
                over(row, im.crop((0, 0, W - im.width, im.height)), (im.width, 20))
            rows.append(row)
    H = sum(r.height for r in rows) + 6 * len(rows)
    sheet = Image.new("RGBA", (W, H), (40, 36, 44, 255))
    y = 0
    for r in rows:
        sheet.alpha_composite(r, (0, y))
        y += r.height + 6
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sheet.convert("RGB").save(path, quality=88) if path.endswith(".jpg") else sheet.convert("RGB").save(path, optimize=True)
    print("预览：", path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("what", nargs="*")
    ap.add_argument("--preview")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    names = sorted(os.path.basename(p)[:-4] for p in glob.glob(os.path.join(RAW, "*.png")) if not p.endswith("_lit.png"))
    if a.what:
        names = [n for n in names if any(w in n for w in a.what)]
    made = {}
    for n in names:
        made[n] = process(n)
        print("✓", n, os.path.getsize(os.path.join(OUT, n + ".png")) // 1024, "KB")
    if a.preview:
        preview(made, a.preview)


if __name__ == "__main__":
    main()
