#!/usr/bin/env python3
"""仿真微缩（real）look test：一条命令出全部交付物。

    cd tools/art && python3 -m http.server 8765 &        # 已经起了就不用
    python3 tools/art/diorama/real/make.py               # 贴图 + 渲染 + 对比 + glb（约 6~8 分钟，4 核）
    python3 tools/art/diorama/real/make.py renders       # 只出图；还有 textures / glb / figures 几段

输出到 /mnt/project-files/tongsui/art/diorama/real/（--out 改）。渲染按 1.8 倍超采样（3840×2160），再 Lanczos 缩回 1920×1080。
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"
TMP = tempfile.mkdtemp(prefix="real_")
SS = 1.8


def font(sz):
    try:
        return ImageFont.truetype(FONT, sz)
    except Exception:
        return ImageFont.load_default()


def shoot(name, *args):
    out = os.path.join(TMP, name + ".png")
    cmd = ["node", os.path.join(HERE, "shoot.js"), *args, "--out", out]
    print("·", " ".join(cmd[2:]), flush=True)
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
    return out


def jpg(src, dst, size=(1920, 1080), q=90):
    im = Image.open(src).convert("RGB")
    if size and im.size != size:
        im = im.resize(size, Image.LANCZOS)
    im.save(dst, quality=q, optimize=True)
    print("✓", dst, flush=True)
    return im


def label(im, text, xy=(24, 18), sz=34):
    d = ImageDraw.Draw(im)
    f = font(sz)
    x, y = xy
    w = d.textlength(text, font=f)
    d.rectangle([x - 12, y - 8, x + w + 12, y + sz + 10], fill=(24, 22, 22))
    d.text((x, y), text, fill=(240, 234, 222), font=f)
    return im


def renders(out):
    street = ["street", "--x", "900", "--w", "2133", "--scale", str(SS)]
    real = jpg(shoot("real", *street, "--post"), os.path.join(out, "real_street.jpg"))
    nodof = jpg(shoot("nodof", *street), os.path.join(out, "real_street_nodof.jpg"))
    toy = jpg(shoot("toy", *street, "--look", "toy"), os.path.join(TMP, "toy.jpg"))
    jpg(shoot("realb", *street, "--post", "--figs", "b"), os.path.join(out, "real_street_design_b.jpg"))
    # 对比：上 现行玩具版，中 仿真（素），下 仿真 + 镜头
    W, H = 1600, 900
    cmp_ = Image.new("RGB", (W, H * 3 + 16), (24, 22, 22))
    for i, (im, t) in enumerate([(toy, "现在：玩具塑料（toy）"), (nodof, "仿真微缩：材质 + 光（不加景深）"), (real, "仿真微缩：+ 移轴景深、色差、暗角、颗粒")]):
        cmp_.paste(label(im.resize((W, H), Image.LANCZOS), t), (0, i * (H + 8)))
    cmp_.save(os.path.join(out, "compare.jpg"), quality=88, optimize=True)
    print("✓ compare.jpg", flush=True)
    # 小人特写：同一个场景、同一套光，镜头凑近（甲 / 乙 / 现行玩具）
    close = ["street", "--x", "1530", "--w", "250", "--top", "585", "--bottom", "772", "--scale", "5"]
    ca = Image.open(shoot("close_a", *close)).convert("RGB")
    cb = Image.open(shoot("close_b", *close, "--figs", "b")).convert("RGB")
    ct = Image.open(shoot("close_toy", *close, "--look", "toy")).convert("RGB")
    w, h = ca.size
    sheet = Image.new("RGB", (w * 3 + 16, h), (24, 22, 22))
    for i, (im, t) in enumerate([(ct, "现行 toy 塑料"), (ca, "仿真 · 甲（Q 版 1:3）"), (cb, "仿真 · 乙（修长 1:5）")]):
        sheet.paste(label(im, t, sz=30), (i * (w + 8), 0))
    sheet = sheet.resize((sheet.width * 2 // 3, sheet.height * 2 // 3), Image.LANCZOS)
    sheet.save(os.path.join(out, "figures_closeup.jpg"), quality=90, optimize=True)
    print("✓ figures_closeup.jpg", flush=True)


def building(out):
    b = ["building", "--x", "0", "--w", "2133", "--scale", str(SS)]
    data = json.load(open(os.path.join(HERE, "..", "scene3d", "out", "building.json")))
    jpg(shoot("bld", *b, "--post", "--json", json.dumps({"focusY": data["floors"][len(data["floors"]) // 2] - 60})), os.path.join(out, "real_building.jpg"))


def textures(out):
    subprocess.run([sys.executable, os.path.join(HERE, "textures.py")], check=True)
    dst = os.path.join(out, "textures")
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(os.path.join(HERE, "out", "tex"), dst)
    print("✓", dst, flush=True)


def glb(out):
    d = os.path.join(out, "glb")
    os.makedirs(d, exist_ok=True)
    subprocess.run(["node", os.path.join(HERE, "shoot.js"), "street", "--x", "900", "--w", "2133", "--glb", os.path.join(d, "street_looktest.glb")], check=True)


def figures(out):
    d = os.path.join(out, "glb")
    os.makedirs(d, exist_ok=True)
    os.makedirs(os.path.join(d, "toy"), exist_ok=True)
    names = []
    for role in ("qing", "mei"):
        for st in ("child", "teen", "young", "middle", "old"):
            n = f"{role}_{st}"
            names.append(n)
            subprocess.run(["node", os.path.join(HERE, "shoot.js"), "--figure", n, "--glb", os.path.join(d, n + ".glb")], check=True)
            subprocess.run(["node", os.path.join(HERE, "shoot.js"), "--figure", n, "--mats", "toy", "--glb", os.path.join(d, "toy", n + ".glb")], check=True)
    shutil.copy(os.path.join(HERE, "GLB_README.md"), os.path.join(d, "README.md"))
    # 预览（读回 glb：正面 + 关节点、侧面、斜 45°、炸开）：glb 先拷到 http 服务能取到的地方
    srv = os.path.join(HERE, "out", "glbtest")
    os.makedirs(srv, exist_ok=True)
    for n in names:
        shutil.copy(os.path.join(d, n + ".glb"), os.path.join(srv, n + ".glb"))
    for part, ns in (("qing", names[:5]), ("mei", names[5:])):
        subprocess.run(["node", os.path.join(HERE, "shoot.js"), "--preview", ",".join(f"/diorama/real/out/glbtest/{n}.glb" for n in ns),
                        "--out", os.path.join(d, f"preview_{part}.png")], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("what", nargs="*", default=["textures", "renders", "building", "glb", "figures"])
    ap.add_argument("--out", default="/mnt/project-files/tongsui/art/diorama/real")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    subprocess.run([sys.executable, os.path.join(HERE, "figs.py")], check=True)
    for w in a.what:
        globals()[w](a.out)
    shutil.rmtree(TMP, ignore_errors=True)


if __name__ == "__main__":
    main()
