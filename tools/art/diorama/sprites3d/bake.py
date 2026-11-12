#!/usr/bin/env python3
"""微缩模型（C）画风的精灵：家里的东西（home.py）和街景（street.py）→ 录显示列表 → three.js 一张张拍 → 图集。

    python3 tools/art/diorama/sprites3d/bake.py                 # 两套都出：client/art/home/、client/art/street/
    python3 tools/art/diorama/sprites3d/bake.py home            # 只出家里的东西
    python3 tools/art/diorama/sprites3d/bake.py street
    python3 tools/art/diorama/sprites3d/bake.py home --only tv_bw_0,sofa    # 只拍这几张（看效果用，不写图集）
    python3 tools/art/diorama/sprites3d/bake.py --preview [out.png]         # 拿出好的图集往底图切片上摆几户人家看看

要先在 tools/art 下起 http 服务：python3 -m http.server 8765（run.js 也会自己起）。

和老画法的约定一样（引擎 client/scripts/world/home_life.gd、street_life.gd 不用改）：
  - 家里的东西：sprites.json {scale, scene, cab_top, sprites: {<名>_<qing|mei>: {x, y, w, h, at}}}，
    at 是贴图左上角在楼那张图上的世界坐标，引擎按 w/scale × h/scale 原样贴回去。3D 的东西会往左上探（离墙近的往上挪）、
    影子往右下落，所以框比老的大，at 跟着挪；框的边都落在 4 世界像素（= 5 贴图像素）的格子上，和底图切片的像素对齐。
  - 街景：sprites.json {scale, sprites: {<名>: {x, y, w, h, frames, foot}}}，w / h / foot 是世界像素，几帧横排。
"""
from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
import tempfile
import time

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import record_sprites as RS  # noqa: E402

scenes = RS.scenes
ROOT = RS.riso.ROOT
ATLAS_W = 2048
ATLAS_H_MAX = 2048

# 影子：量的底图（上半截墙亮处 (200,184,161)、影子里 (108,106,105)）：叠一层 50% 的 #101C31 正好压成那个冷一点的暗
SHADOW = dict(shadowColor="#101C31", shadowOpacity=0.5)

# ----------------------------------------------------------------------
# 家里的东西：每张精灵摆多前、多厚（中心 z、厚度，世界像素；和 ../scene3d/build.js 的 PROPS 一个口径：
# 后墙 z=0，人走在 z=120；底图的五斗柜 z 30±28、书桌 40±30、饭桌 62±32、脸盆架 40±20）
# ----------------------------------------------------------------------
HOME = {
    "curtain": dict(zc=46, d=16, wood=False),
    "boxes": dict(zc=62, d=30),
    "sewing": dict(zc=42, d=36),
    "sofa": dict(zc=46, d=52, wood=False),
    "clock_round": dict(zc=3, d=5),
    "clock_pendulum": dict(zc=7, d=12),
    "bookcase": dict(zc=31, d=62, tagz={"frame_pic": [4.0, 10.0]}),
    "cab_0": dict(zc=44, d=42), "cab_1": dict(zc=44, d=42), "cab_2": dict(zc=44, d=42, glossy=True),
    "tv_bw": dict(zc=44, d=30, glossy=True), "tv_color": dict(zc=44, d=40, glossy=True), "tv_flat": dict(zc=44, d=8, glossy=True),
    "console": dict(zc=84, d=22),
    "radio_dresser": dict(zc=30, d=22), "radio_case": dict(zc=28, d=22),
    "fridge": dict(zc=34, d=56, wood=False),
    "pc_crt": dict(zc=78, d=40, glossy=True), "pc_lcd": dict(zc=78, d=40, glossy=True),
    "tape": dict(zc=40, d=16), "phone": dict(zc=40, d=18, wood=False),
    "milk": dict(zc=10, d=16),
}
# 放宽多少（世界像素）：左、上、右、下。东西离墙越近往左上探得越少；影子往右下落
HOME_PAD = (64, 64, 112, 28)


def home_cfg(name):
    for k in sorted(HOME, key=len, reverse=True):
        if name == k or name.startswith(k + "_"):
            return dict(HOME[k])
    return dict(zc=40, d=30)


def _snap(v, step, up=False):
    return float(math.ceil(v / step) * step if up else math.floor(v / step) * step)


def home_jobs(only=None):
    hm = RS.load_home()
    BASE, CEIL = hm.BASE, hm.CEIL
    sl = hm.slots()
    t0, t1 = sl["T"]
    desk_top = BASE - 96
    jobs = []
    for name in hm.SPRITES:
        if only and name not in only:
            continue
        cfg = home_cfg(name)
        for role in ("qing", "mei"):
            rec = RS.record_home(hm, name, role)
            x0, y0, w, h = rec["frame"]
            pl, pt, pr, pb = HOME_PAD
            if role == "mei":      # 镜像那家影子照样往右落，探出去的照样往左上
                pass
            vx0, vy0 = _snap(x0 - pl, 4), _snap(y0 - pt, 4)
            vx1, vy1 = _snap(x0 + w + pr, 4, True), _snap(min(y0 + h + pb, BASE + 60), 4, True)
            # 接影子：底图这一段的墙、楼板、家具（render_sprite.js 的 baseModel）；底图没有的台面（书柜顶）另加一块板
            catchers = []
            exclude = []

            def mx(a, b):
                return (a, b) if role == "qing" else (hm.AXIS - b, hm.AXIS - a)
            if name in ("bookcase", "radio_case"):
                exclude = ["wardrobe", "frame_pic"]      # 书柜整个盖住底图的五斗柜和它顶上的相框
            if name == "radio_case":
                a, b = mx(sl["corner"] - 76, sl["corner"] + 76)
                catchers.append(dict(kind="floor", x0=a, x1=b, y=BASE - 316, z0=2.0, z1=56.0))
            job = dict(id=rec["name"], ops=rec["ops"], floors=[CEIL - 60, BASE], cfg=cfg, scale=scenes.ART_SCALE,
                       view=dict(x0=vx0, y0=vy0, x1=vx1, y1=vy1), catchers=catchers, **SHADOW,
                       base=dict(scene=hm.SCENE, x0=vx0, x1=vx1, y0=vy0, y1=vy1, exclude=exclude, floorY=BASE))
            if name == "floor_rich":
                a, b = mx(20, sl["fridge"][1] + 2)
                job["custom"] = dict(kind="floorCover", x0=a, x1=b, y=BASE, z0=3.0, z1=262.0)
                job["view"] = dict(x0=_snap(a - 16, 4), y0=_snap(BASE - 40, 4), x1=_snap(b + 16, 4, True), y1=_snap(BASE + 46, 4, True))
                job["catchers"] = []
                job["base"].update(x0=job["view"]["x0"], x1=job["view"]["x1"], y0=job["view"]["y0"], y1=job["view"]["y1"])
            jobs.append(job)
    return jobs


# ----------------------------------------------------------------------
# 街景：都立在人走的那条线上（z=120），脚底锚点不变
# ----------------------------------------------------------------------
STREET = {
    "stage_table": dict(zc=120, d=40),
    "notice": dict(zc=120, d=10),
    "locker": dict(zc=120, d=34, wood=False),
    "phone_booth": dict(zc=120, d=26, wood=False),
    "shared_bikes": dict(zc=120, d=8, wood=False),
    "river_warn": dict(zc=120, d=6, wood=False),
    "far_factory": dict(zc=120, d=34, wood=False),
    "far_towers": dict(zc=120, d=34, wood=False),
    "dafa": dict(zc=120, d=62, wood=False, glossy=True),
    "xiali": dict(zc=120, d=62, wood=False, glossy=True),
}
STREET_PAD = (28, 40, 150, 14)    # 左、上、右、下（影子往右后方拖得长）


def street_cfg(name):
    for k in sorted(STREET, key=len, reverse=True):
        if name == k or name.startswith(k + "_"):
            return dict(STREET[k], mode="furniture")
    return dict(zc=120, d=14, mode="figure", wood=False)


def street_jobs(only=None):
    ST, LA = RS.load_street()
    jobs = []
    for name, sp in ST.SPRITES.items():
        if only and name not in only:
            continue
        cfg = street_cfg(name)
        for i in range(sp["frames"]):
            rec = RS.record_street(ST, LA, name, i)
            x0, y0, w, h = rec["frame"]
            pl, pt, pr, pb = STREET_PAD
            view = dict(x0=x0 - pl, y0=y0 - pt, x1=x0 + w + pr, y1=y0 + h + pb)
            catchers = [dict(kind="floor", x0=view["x0"] - 300, x1=view["x1"] + 300, y=0.0, z0=-200.0, z1=400.0)]
            jobs.append(dict(id=rec["name"].replace("#", "__"), sprite=name, frame_i=i, ops=rec["ops"], floors=[0.0], cfg=cfg,
                             scale=ST.SCALE, view=view, catchers=catchers, **SHADOW))
    return jobs, ST


# ----------------------------------------------------------------------
# 拍、裁、拼
# ----------------------------------------------------------------------

def run(jobs, keep=None):
    tmp = keep or tempfile.mkdtemp(prefix="sprites3d_")
    os.makedirs(tmp, exist_ok=True)
    jp = os.path.join(tmp, "jobs.json")
    with open(jp, "w") as f:
        json.dump(jobs, f, ensure_ascii=False)
    t = time.time()
    subprocess.run(["node", os.path.join(HERE, "run.js"), jp, os.path.join(tmp, "cells")], check=True)
    print(f"拍了 {len(jobs)} 张 {time.time() - t:.1f} s", flush=True)
    return os.path.join(tmp, "cells")


def load(cells, jid):
    """一张精灵；有「接影子」那一张的话，挡的那张盖在它上面。"""
    im = Image.open(os.path.join(cells, jid + ".png")).convert("RGBA")
    cp = os.path.join(cells, jid + ".catch.png")
    if os.path.exists(cp):
        sh = Image.open(cp).convert("RGBA")
        sh.alpha_composite(im)
        im = sh
    return np.asarray(im)


def alpha_box(arrs, thr=3):
    """几张同样大的图合起来的不透明框（像素）。"""
    a = np.zeros(arrs[0].shape[:2], bool)
    for r in arrs:
        a |= r[..., 3] > thr
    ys, xs = np.nonzero(a)
    if not len(xs):
        return 0, 0, 1, 1
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def pack(images, pad=2):
    order = sorted(images, key=lambda n: (-images[n].shape[0], n))
    x = y = shelf = 0
    pos = {}
    for n in order:
        h, w = images[n].shape[:2]
        if x + w > ATLAS_W:
            x, y, shelf = 0, y + shelf + pad, 0
        pos[n] = (x, y)
        x += w + pad
        shelf = max(shelf, h)
    atlas = np.zeros((y + shelf, ATLAS_W, 4), dtype=np.uint8)
    for n, (px, py) in pos.items():
        h, w = images[n].shape[:2]
        atlas[py:py + h, px:px + w] = images[n]
    return atlas, pos


def save_atlas(atlas, path):
    """256 色（误差扩散抖动），透明的地方 RGB 清零。"""
    a = atlas[..., 3:4]
    arr = np.where(a == 0, 0, atlas).astype(np.uint8)
    img = Image.fromarray(arr, "RGBA").quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG)
    img.save(path, optimize=True)


def bake_home(only=None, keep=None):
    jobs = home_jobs(only)
    cells = run(jobs, keep)
    S = scenes.ART_SCALE
    step = int(round(4 * S))           # 5 像素 = 4 世界像素
    images, at = {}, {}
    for j in jobs:
        arr = load(cells, j["id"])
        x0, y0, x1, y1 = map(int, alpha_box([arr]))
        x0, y0 = (x0 // step) * step, (y0 // step) * step
        x1, y1 = -(-x1 // step) * step, -(-y1 // step) * step
        images[j["id"]] = arr[y0:y1, x0:x1]
        at[j["id"]] = [j["view"]["x0"] + x0 / S, j["view"]["y0"] + y0 / S]
    if only:
        return images, at, None
    atlas, pos = pack(images)
    out = os.path.join(ROOT, "client", "art", "home")
    os.makedirs(out, exist_ok=True)
    if atlas.shape[0] > ATLAS_H_MAX:
        print(f"⚠ 图集高 {atlas.shape[0]}，超过 {ATLAS_H_MAX}")
    save_atlas(atlas, os.path.join(out, "atlas.png"))
    hm = RS.load_home()
    meta = {"scale": S, "scene": hm.SCENE, "cab_top": {str(k): v for k, v in hm.CAB_TOP.items()}, "sprites": {}}
    for n in sorted(images):
        h, w = images[n].shape[:2]
        meta["sprites"][n] = {"x": pos[n][0], "y": pos[n][1], "w": w, "h": h, "at": [round(at[n][0], 2), round(at[n][1], 2)]}
    with open(os.path.join(out, "sprites.json"), "w", encoding="utf-8") as fp:
        json.dump(meta, fp, ensure_ascii=False, indent=1)
    size = os.path.getsize(os.path.join(out, "atlas.png"))
    print(f"✓ 家里的东西 {len(images)} 张 → client/art/home/atlas.png（{atlas.shape[1]}×{atlas.shape[0]}，{size / 1e6:.2f} MB）")
    return images, at, meta


def bake_street(only=None, keep=None):
    jobs, ST = street_jobs(only)
    cells = run(jobs, keep)
    S = ST.SCALE
    step = int(round(S))               # 2 像素 = 1 世界像素：w / h / foot 都是整数世界像素
    by = {}
    for j in jobs:
        by.setdefault(j["sprite"], []).append(j)
    images, meta_sp = {}, {}
    for name, js in by.items():
        js.sort(key=lambda j: j["frame_i"])
        arrs = [load(cells, j["id"]) for j in js]
        x0, y0, x1, y1 = map(int, alpha_box(arrs))
        x0, y0 = (x0 // step) * step, (y0 // step) * step
        x1, y1 = -(-x1 // step) * step, -(-y1 // step) * step
        v = js[0]["view"]
        fw, fh = x1 - x0, y1 - y0
        strip = np.zeros((fh, fw * len(arrs), 4), np.uint8)
        for i, a in enumerate(arrs):
            strip[:, i * fw:(i + 1) * fw] = a[y0:y1, x0:x1]
        images[name] = strip
        # 脚底：局部坐标原点（0, 0）在这张裁好的图里的位置
        meta_sp[name] = dict(w=fw // step, h=fh // step, frames=len(arrs), foot=[int(round(-v["x0"] - x0 / S)), int(round(-v["y0"] - y0 / S))])
    if only:
        return images, meta_sp, None
    atlas, pos = pack(images)
    out = os.path.join(ROOT, "client", "art", "street")
    os.makedirs(out, exist_ok=True)
    if atlas.shape[0] > ATLAS_H_MAX:
        print(f"⚠ 图集高 {atlas.shape[0]}，超过 {ATLAS_H_MAX}")
    save_atlas(atlas, os.path.join(out, "atlas.png"))
    meta = {"scale": S, "sprites": {}}
    for n in ST.SPRITES:
        if n in images:
            meta["sprites"][n] = {"x": pos[n][0], "y": pos[n][1], **meta_sp[n]}
    with open(os.path.join(out, "sprites.json"), "w", encoding="utf-8") as fp:
        json.dump(meta, fp, ensure_ascii=False, indent=1)
    size = os.path.getsize(os.path.join(out, "atlas.png"))
    print(f"✓ 街景 {len(images)} 张 → client/art/street/atlas.png（{atlas.shape[1]}×{atlas.shape[0]}，{size / 1e6:.2f} MB）")
    return images, meta_sp, meta


# ----------------------------------------------------------------------
# 预览：底图切片 + 这一层（和引擎 home_life.gd 一样贴）
# ----------------------------------------------------------------------

def _slices(sid, x0, x1):
    S = scenes.ART_SCALE
    n0, n1 = int(x0 // scenes.SLICE), int((x1 - 1) // scenes.SLICE)
    W = int(round((x1 - x0) * S))
    H = int(round((scenes.BOTTOM - scenes.TOP) * S))
    can = Image.new("RGBA", (W, H), (0xB9, 0xCF, 0xE2, 255))
    for k in range(n0, n1 + 1):
        p = os.path.join(ROOT, "client", "art", "scenes", f"{sid}_{k}.png")
        if os.path.exists(p):
            im = Image.open(p).convert("RGBA")
            can.alpha_composite(im, (int(round((k * scenes.SLICE - x0) * S)), 0))
    return can


def street_strip(W):
    """街景精灵（老的大地图那一层，现在横版里没在用）一个个立在街的底图上看看：脚底落在人行道上（y=760）。"""
    mp = os.path.join(ROOT, "client", "art", "street", "sprites.json")
    meta = json.load(open(mp))
    if meta.get("px"):
        return None
    S0 = scenes.ART_SCALE
    atlas = Image.open(os.path.join(ROOT, "client", "art", "street", "atlas.png")).convert("RGBA")
    k = S0 / meta["scale"]          # 精灵按底图的倍率缩回去
    ground = 760
    base = _slices("street", 0, W / S0)
    x = 20
    rows = []
    for n, sp in meta["sprites"].items():
        fw, fh = int(sp["w"] * meta["scale"]), int(sp["h"] * meta["scale"])
        fr = atlas.crop((sp["x"], sp["y"], sp["x"] + fw, sp["y"] + fh)).resize((max(1, int(fw * k)), max(1, int(fh * k))), Image.LANCZOS)
        if x + fr.width > base.width - 10:
            rows.append(base)
            base = _slices("street", 0, W / S0)
            x = 20
        base.alpha_composite(fr, (x, int(round((ground - scenes.TOP - sp["foot"][1]) * S0))))
        x += fr.width + 6
    rows.append(base)
    y0, y1 = int((ground - 150 - scenes.TOP) * S0), int((ground + 40 - scenes.TOP) * S0)
    strips = [r.crop((0, y0, W, y1)) for r in rows]
    out = Image.new("RGBA", (W, sum(s_.height for s_ in strips)))
    yy = 0
    for s_ in strips:
        out.paste(s_, (0, yy))
        yy += s_.height
    return out


def preview(out, homes=None):
    hm = RS.load_home()
    S = scenes.ART_SCALE
    meta = json.load(open(os.path.join(ROOT, "client", "art", "home", "sprites.json")))
    atlas = Image.open(os.path.join(ROOT, "client", "art", "home", "atlas.png")).convert("RGBA")
    homes = homes or [(0, ["radio", "milk"], 1, 0, ["tv"], 2), (1, ["tv", "radio", "phone", "fridge"], 3, 2, ["tv", "books", "radio", "fridge", "pc", "tape", "console"], 4),
                      (2, ["tv", "books", "radio", "phone", "fridge", "console"], 3, 1, ["tv", "pc", "milk", "tape", "fridge"], 6)]
    rows = []
    for wq, iq, dec, wm, im_, dec2 in homes:
        base = _slices(hm.SCENE, 0, 3 * scenes.SLICE + 128 + 128)
        for role, w, items, d in (("qing", wq, iq, dec), ("mei", wm, im_, dec2)):
            for k in hm.pick(w, items, d, role):
                key = f"{k}_{role}"
                sp = meta["sprites"].get(key)
                if not sp:
                    continue
                crop = atlas.crop((sp["x"], sp["y"], sp["x"] + sp["w"], sp["y"] + sp["h"]))
                base.alpha_composite(crop, (int(round(sp["at"][0] * S)), int(round((sp["at"][1] - scenes.TOP) * S))))
        y0 = int((hm.CEIL - 80 - scenes.TOP) * S)
        y1 = int((hm.BASE + 70 - scenes.TOP) * S)
        rows.append(base.crop((0, y0, base.width, y1)))
    st = street_strip(rows[0].width)
    if st is not None:
        rows.append(st)
    W = rows[0].width
    tot = Image.new("RGB", (W, sum(r.height for r in rows) + 8 * len(rows)), (40, 40, 48))
    y = 0
    for r in rows:
        tot.paste(r.convert("RGB"), (0, y))
        y += r.height + 8
    os.makedirs(os.path.dirname(out), exist_ok=True)
    tot.save(out)
    print("预览：", out, tot.size)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("what", nargs="*", default=[])
    ap.add_argument("--only", default="")
    ap.add_argument("--keep", default=None, help="中间文件放这儿（jobs.json、一张张的 png）")
    ap.add_argument("--preview", nargs="?", const="/mnt/project-files/tongsui/art/diorama/sprites_preview.png", default=None)
    a = ap.parse_args()
    only = set(s for s in a.only.split(",") if s) or None
    what = a.what or ([] if a.preview else ["home", "street"])
    if "home" in what:
        bake_home(only, a.keep)
    if "street" in what:
        bake_street(only, a.keep)
    if a.preview:
        preview(a.preview)


if __name__ == "__main__":
    main()
