#!/usr/bin/env python3
"""不开 Godot 先看一眼：照引擎的摆法把一屏拼出来（天 → 远景 → 中景 → 底图 → 树 → 人），出一张图。

天是 shaders/sky.gdshader 的 numpy 版（色带 + 拜耳抖动、像素云、太阳），只为预览，和着色器大体一致；
光与空气（grade.gdshader）、夜版不在这里。

    python3 tools/art/pixel/pxpreview.py street --x 1200 --time dusk --out /tmp/p.png
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
from riso import ROOT  # noqa: E402

PX = 3
VIEW_H = scenes.BOTTOM - scenes.TOP   # 引擎镜头竖着看得见 1200 世界像素
BAYER = pxlib.BAYER


def _mix(a, b, t):
    return a + (b - a) * t


def sky_col(s, dusk, night):
    s = s[..., None]
    dz, dm, dh = np.array([0.38, 0.58, 0.84]), np.array([0.58, 0.76, 0.90]), np.array([0.90, 0.92, 0.86])
    day = np.where(s < 0.6, _mix(dz, dm, s / 0.6), _mix(dm, dh, (s - 0.6) / 0.4))
    uz, um, uh = np.array([0.22, 0.20, 0.46]), np.array([0.70, 0.40, 0.56]), np.array([1.00, 0.68, 0.42])
    du = np.where(s < 0.55, _mix(uz, um, s / 0.55), _mix(um, uh, (s - 0.55) / 0.45))
    nz, nh = np.array([0.05, 0.06, 0.16]), np.array([0.16, 0.20, 0.40])
    ni = _mix(nz, nh, s * s)
    c = _mix(day, du, dusk)
    return _mix(c, ni, night)


def fbm(x, y, seed=0):
    def vn(px, py):
        ix, iy = np.floor(px), np.floor(py)
        fx, fy = px - ix, py - iy
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)

        def h(a, b):
            v = np.sin(a * 127.1 + b * 311.7 + seed * 17.0) * 43758.5453
            return v - np.floor(v)
        return _mix(_mix(h(ix, iy), h(ix + 1, iy), fx), _mix(h(ix, iy + 1), h(ix + 1, iy + 1), fx), fy)
    return vn(x, y) * 0.55 + vn(x * 2.03 + 7.1, y * 2.03 + 7.1) * 0.3 + vn(x * 4.1 + 3.3, y * 4.1 + 3.3) * 0.15


def sky(W, H, x0, horizon, dusk=0.0, night=0.0, day_t=0.3):
    """W×H 个点的天（点坐标），x0：左边是第几个点；horizon：地平线（世界 y，相对 TOP）。"""
    qx = np.arange(W)[None, :] + x0
    qy = np.arange(H)[:, None]
    wy = (qy + 0.5) * PX
    wx = (qx + 0.5) * PX
    t = np.clip(wy / max(horizon, 1), 0, 1)
    b = BAYER[qy % 4, qx % 4]
    tt = t * 11
    s = (np.floor(tt) + (b < (tt - np.floor(tt)))) / 11
    col = sky_col(np.broadcast_to(s, (H, W)), dusk, night)
    # 云
    cxw = wx[0] - (x0 * PX + W * PX / 2) * 0.93
    n = fbm(cxw[None, :] * 0.0021, wy * 0.0105)
    ndn = fbm(cxw[None, :] * 0.0021, (wy + 6) * 0.0105)
    nup = fbm(cxw[None, :] * 0.0021, (wy - 6) * 0.0105)
    band = (wy > VIEW_H * 0.12) & (wy < horizon - 60)
    th = 0.6
    cl = (n > th) & band
    lit = _mix(np.array([1.0, 0.98, 0.94]), np.array([1.0, 0.80, 0.62]), dusk)
    lit = _mix(lit, np.array([0.30, 0.34, 0.52]), night)
    shade = _mix(lit, sky_col(np.array(0.25), dusk, night) * 0.8, 0.45)
    shade = _mix(shade, np.array([0.62, 0.42, 0.62]), dusk * 0.5)
    c = np.broadcast_to(lit, col.shape).copy()
    sel = cl & (ndn < th)
    c[sel] = shade
    mid = cl & (ndn >= th) & (n - th < 0.025) & (b < 0.5)
    c[mid] = shade
    top = cl & (nup < th)
    c[top] = _mix(lit, np.array([1.0, 1, 1]), 0.35 * (1 - night))
    col = np.where(cl[..., None], c, col)
    # 太阳
    if night < 0.5:
        cx = (x0 + W / 2) * PX + W * PX * _mix(-0.34, 0.34, day_t)
        cy = _mix(VIEW_H * 0.12, horizon - 40, abs(day_t - 0.5) * 2 ** 1.6)
        cy = _mix(cy, horizon - 70, dusk)
        sr = 36 + dusk * 18
        sd = np.hypot(wx - cx, wy - cy)
        sun_c = _mix(np.array([1.0, 0.97, 0.82]), np.array([1.0, 0.56, 0.36]), dusk)
        h1 = 1 - np.clip((sd - sr) / (sr * 1.2), 0, 1)
        h2 = 1 - np.clip((sd - sr * 2.2) / (sr * 1.8), 0, 1)
        on = ~cl
        m2 = on & (b < h2 * 0.5)
        col[m2] = _mix(col[m2], sun_c, 0.5)
        m1 = on & (b < h1)
        col[m1] = _mix(col[m1], sun_c, 0.75)
        col[on & (sd < sr)] = sun_c
    return (col * 255).clip(0, 255)


def load_actor(role, stage, row=1, col=0):
    im = np.asarray(Image.open(os.path.join(ROOT, "client", "art", "actors", f"{role}_{stage}.png")).convert("RGBA"))
    h, w = im.shape[0] // 5, im.shape[1] // 8
    return im[row * h:(row + 1) * h, col * w:(col + 1) * w]


def paste(dst, src, x, y):
    """dst/src 都是世界像素（1 像素 = 1 世界像素）的 RGBA / RGB。"""
    H, W = dst.shape[:2]
    h, w = src.shape[:2]
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(W, x + w), min(H, y + h)
    if x1 <= x0 or y1 <= y0:
        return
    s = src[y0 - y:y1 - y, x0 - x:x1 - x].astype(np.float32)
    a = s[..., 3:4] / 255.0
    dst[y0:y1, x0:x1, :3] = dst[y0:y1, x0:x1, :3] * (1 - a) + s[..., :3] * a


def layer_strip(name):
    p = os.path.join(ROOT, "client", "art", "layers", name)
    return np.asarray(Image.open(p).convert("RGBA")) if os.path.exists(p) else None


def layout():
    """scene_art.gd 里的 LAYOUT（远景、中景楼脚）。"""
    import re
    src = open(os.path.join(ROOT, "client", "scripts", "world", "scene_art.gd"), encoding="utf-8").read()
    out = {}
    for m in re.finditer(r'"(\w+)": \{([^}]*)\}', src.split("const LAYOUT")[1].split("\n}")[0]):
        d = {}
        for k, v in re.findall(r'"(\w+)": ([^,]+)', m.group(2)):
            v = v.strip()
            d[k] = None if v == "null" else (v.strip('"') if v.startswith('"') else float(v))
        out[m.group(1)] = d
    return out


def render(sid, x, w=2133, time="day", actors=(("qing", "young", 0), ("mei", "young", 0)), ax=None, season="summer"):
    sc = scenes.load_scenes()[sid]
    x = int(x) // PX * PX
    w = int(w) // PX * PX
    with open(os.path.join(ROOT, "client", "art", "scenes", "anchors.json"), encoding="utf-8") as f:
        anc = json.load(f)["scenes"].get(sid, {})
    horizon = anc.get("layer", {}).get("horizon", sc["floors"][0]) - scenes.TOP
    dusk, night = {"day": (0, 0), "dusk": (1, 0), "night": (0, 1)}[time]
    s = sky(w // PX, VIEW_H // PX, x // PX, horizon, dusk, night, day_t=0.75 if time == "dusk" else 0.3)
    canvas = np.zeros((VIEW_H, w, 3), np.float32)
    canvas[:] = np.repeat(np.repeat(s, PX, 0), PX, 1)
    # 远景、中景（有就贴；按 scene_art 的视差摆，这里镜头左边 = x）
    era = "young"
    lay = layout().get(sid, {})
    hz = np.array([0.90, 0.92, 0.88]) * (1 - dusk) + np.array([0.97, 0.80, 0.66]) * dusk * 0.8 + np.array([0.90, 0.92, 0.88]) * dusk * 0.2
    for kind, par, hz_amt in (("far", 0.1, 0.42), ("mid", 0.32, 0.12)):
        if kind in lay and lay[kind] is None:
            continue
        st = layer_strip(f"{kind}_{lay.get(kind + '_kind', era)}.png")
        if st is None:
            continue
        base = lay.get(kind, horizon + scenes.TOP if kind == "far" else horizon + scenes.TOP + 60)
        st = st.astype(np.float32)
        hzv = float(lay.get(kind + "_haze", hz_amt))
        st[..., :3] = st[..., :3] * (1 - hzv) + hz * 255 * hzv
        st[..., :3] *= (1 - dusk * 0.4) + np.array([0.98, 0.70, 0.52]) * dusk * 0.4
        tw = st.shape[1]
        off = int(x * par) % tw
        off -= off % PX
        reps = np.concatenate([st] * (w // tw + 2), 1)[:, off:off + w]
        paste(canvas, reps, 0, int(base - scenes.TOP - st.shape[0]))
    # 底图
    full = np.zeros((VIEW_H, 0, 4), np.uint8)
    k0, k1 = x // scenes.SLICE, (x + w) // scenes.SLICE
    parts = []
    for k in range(k0, k1 + 1):
        p = os.path.join(ROOT, "client", "art", "scenes", f"{sid}_{k}.png")
        if os.path.exists(p):
            parts.append(np.asarray(Image.open(p).convert("RGBA")))
    full = np.concatenate(parts, 1)[:, x - k0 * scenes.SLICE:x - k0 * scenes.SLICE + w]
    paste(canvas, full, 0, 0)
    # 树（不缩放，落在格子上）
    trees = {"huai": [624, 702], "willow": [642, 681], "young": [300, 381]}
    for a in anc.get("trees", []):
        kind = a[4]
        if kind not in trees:
            continue
        t = layer_strip(f"tree_{kind}_{season}.png")
        if t is None:
            continue
        tx = int(round((a[0] - trees[kind][0] / 2) / 3) * 3) - x
        ty = int(round((a[1] - trees[kind][1] - scenes.TOP) / 3) * 3)
        paste(canvas, t, tx, ty)
    # 人
    gy = sc["floors"][0] - scenes.TOP if sc.get("top", 0) == 0 else sc["floors"][0] - sc["top"] - scenes.TOP
    ax = ax if ax is not None else w // 2
    for i, (role, stage, row) in enumerate(actors):
        a = load_actor(role, stage, row=row, col=i)
        paste(canvas, a, ax - 99 + i * 110, int(gy) - 207)
    return canvas.clip(0, 255).astype(np.uint8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scene")
    ap.add_argument("--x", type=float, default=1000)
    ap.add_argument("--w", type=float, default=2133)
    ap.add_argument("--time", default="day")
    ap.add_argument("--out", default="/tmp/pxpreview.png")
    ap.add_argument("--stage", default="young")
    a = ap.parse_args()
    img = render(a.scene, a.x, a.w, a.time, actors=(("qing", a.stage, 1), ("mei", a.stage, 1)))
    Image.fromarray(img).resize((img.shape[1] * 9 // 10, img.shape[0] * 9 // 10), Image.BILINEAR).save(a.out)
    print(a.out)


if __name__ == "__main__":
    main()
