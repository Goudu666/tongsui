#!/usr/bin/env python3
"""微缩模型（C）画风的两个主角：three.js 搭小人、离线渲染成精灵表。

    python3 tools/art/diorama/pose3d/figures.py --variant toy                 # 出图 → client/art/actors/{qing,mei}_{stage}[_act].png
    python3 tools/art/diorama/pose3d/figures.py --variant clay --only teen     # 只出一个年纪
    python3 tools/art/diorama/pose3d/figures.py --preview out.png --variant toy   # 两个人五个年纪：站、走、招手、坐，拼一张（2 倍）
    python3 tools/art/diorama/pose3d/figures.py --design a --portrait out.png  # 造型方案：全身 + 大头特写

格子、脚底、倍数和墨线版一样（actor.gd：CELL 200×220、FOOT (100, 206)、底图 2 倍、行动表 1.5 倍），人朝右。
每格先按 SS 倍超采样渲染，再用 Lanczos 缩回来。
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import poses  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
OUT_DIR = os.path.join(ROOT, "client", "art", "actors")
CELL = (200, 220)
FOOT = (100, 206)
COLS, ROWS, ACT_ROWS = 8, 5, 11
ART_SCALE, ACT_ART_SCALE = 2.0, 1.5
SS = 2
FONT = "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"

# 造型方案：头身比（头的倍数、腿的倍数，相对 actors.build）、眼睛画法、胳膊腿粗细
DESIGNS = {
    "a": dict(name="甲 · 大头Q版（约 1:3）", head=dict(child=1.3, teen=1.55, young=1.6, middle=1.55, old=1.5),
              leg=dict(child=0.92, teen=0.8, young=0.8, middle=0.8, old=0.82), neck=0.5,
              eye="oval", fringe="spiky", eyeScale=1.0, limbK=1.18, handK=1.12, yaw=58, headPitch=-8, eyeLon=24, eyeLat=-8, mouthLat=-33, noseK=0.06, noseLat=-22),
    "b": dict(name="乙 · 绘本修长（约 1:5）", head=dict(child=1.08, teen=1.1, young=1.08, middle=1.08, old=1.08),
              leg=dict(child=1.0, teen=1.0, young=1.0, middle=1.0, old=1.0), neck=1.0,
              eye="bean", fringe="swept", eyeScale=0.95, limbK=1.0, handK=1.05, yaw=55, headPitch=-6, eyeLon=23, eyeLat=-3, headShape=[0.96, 1.03, 0.96], mouthLat=-32, noseK=0.09, noseLat=-18),
    "c": dict(name="丙 · 大眼娃娃（约 1:3.5）", head=dict(child=1.22, teen=1.32, young=1.34, middle=1.3, old=1.28),
              leg=dict(child=0.96, teen=0.92, young=0.92, middle=0.9, old=0.9), neck=0.7,
              eye="anime", fringe="chunky", eyeScale=1.3, limbK=0.95, handK=1.05, yaw=56, headPitch=-8, eyeLon=26, eyeLat=-9, mouthLat=-36, noseK=0.045, noseLat=-24, mouthK=1.2, headShape=[1.0, 0.93, 1.06]),
}
DEFAULT_DESIGN = "a"


def js_design(d):
    return {k: v for k, v in d.items() if k not in ("head", "leg", "neck", "arm")}


def view_cell():
    """一格的取景：屏幕坐标（世界像素，y 向下），脚底在原点。"""
    return dict(x0=-FOOT[0], x1=CELL[0] - FOOT[0], y0=-FOOT[1], y1=CELL[1] - FOOT[1])


def job(jid, b, fr, design, variant, view, px, shadow=True, bg=None):
    return dict(id=jid, spec=poses.figure_spec(b), frame=fr, design=js_design(design), variant=variant, view=view, px=px, shadow=shadow, bg=bg)


def _server_up():
    import urllib.request
    try:
        urllib.request.urlopen("http://localhost:8765/diorama/pose3d/page.html", timeout=2).read()
        return True
    except Exception:
        return False


def run_jobs(jobs, workers=None, page=None):
    """把格子分给几个 Chromium 一起渲（swiftshader 是 CPU 渲染，一个进程只吃满一个核）。"""
    tmp = tempfile.mkdtemp(prefix="pose3d_")
    out = os.path.join(tmp, "cells")
    workers = workers or max(1, min(4, os.cpu_count() or 1, (len(jobs) + 7) // 8))
    srv = None
    if not _server_up():  # tools/art 下起一个 http 服务（ES 模块要走 http）
        srv = subprocess.Popen([sys.executable, "-m", "http.server", "8765"], cwd=os.path.dirname(os.path.dirname(HERE)),
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(50):
            if _server_up():
                break
            time.sleep(0.1)
    t = time.time()
    procs = []
    try:
        for w in range(workers):
            part = jobs[w::workers]
            jp = os.path.join(tmp, f"jobs{w}.json")
            with open(jp, "w") as f:
                json.dump(part, f, ensure_ascii=False)
            procs.append(subprocess.Popen(["node", os.path.join(HERE, "render.js"), jp, out] + ([page] if page else [])))
        bad = [p.wait() for p in procs]
        if any(bad):
            raise SystemExit(f"渲染失败：{bad}")
    finally:
        for p in procs:
            if p.poll() is None:
                p.kill()
        if srv:
            srv.terminate()
    print(f"渲染 {len(jobs)} 格，{workers} 路，{time.time() - t:.1f} s", flush=True)
    return out


def load(cells, jid, size):
    im = Image.open(os.path.join(cells, jid + ".png")).convert("RGBA")
    if im.size != size:
        im = im.resize(size, Image.LANCZOS)
    return im


# ----------------------------------------------------------------------
# 精灵表
# ----------------------------------------------------------------------

def sheet_jobs(role, stage, design, variant):
    b = poses.body(role, stage, design)
    out = []
    for suffix, cells, scale in (("", poses.base_cells(b), ART_SCALE), ("_act", poses.act_cells(b), ACT_ART_SCALE)):
        px = [int(CELL[0] * scale * SS), int(CELL[1] * scale * SS)]
        for r, c, fr in cells:
            out.append(job(f"{role}_{stage}{suffix}_{r}_{c}", b, fr, design, variant, view_cell(), px))
    return out


def pack_sheet(cells, role, stage, suffix):
    scale = ART_SCALE if not suffix else ACT_ART_SCALE
    rows = ROWS if not suffix else ACT_ROWS
    cw, ch = int(CELL[0] * scale), int(CELL[1] * scale)
    sheet = Image.new("RGBA", (cw * COLS, ch * rows), (0, 0, 0, 0))
    for r in range(rows):
        for c in range(COLS):
            jid = f"{role}_{stage}{suffix}_{r}_{c}"
            if os.path.exists(os.path.join(cells, jid + ".png")):
                sheet.alpha_composite(load(cells, jid, (cw, ch)), (c * cw, r * ch))
    return sheet


def save_sheet(im, path):
    # 量化成 256 色带透明：一张 3200×2200 的表 ~ 几百 KB
    q = im.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    q.save(path, optimize=True)


# ----------------------------------------------------------------------
# 预览 / 造型方案
# ----------------------------------------------------------------------

def font(sz):
    try:
        return ImageFont.truetype(FONT, sz)
    except OSError:
        return ImageFont.load_default()


STAGE_CN = dict(child="小时候", teen="中学", young="青年", middle="中年", old="老年")
ROLE_CN = dict(qing="青", mei="梅")


def preview(path, design_key, variant, stages, zoom=2.0, bg=(236, 226, 210)):
    """两个人五个年纪，每人：站、走一帧、招手、坐。"""
    design = DESIGNS[design_key]
    picks = [("站", "base", 1, 0), ("走", "base", 0, 2), ("走", "base", 0, 5), ("招手", "base", 2, 5), ("坐", "base", 2, 0)]
    jobs, layout = [], []
    px = [int(CELL[0] * zoom * SS), int(CELL[1] * zoom * SS)]
    for stage in stages:
        for role in poses.ROLES:
            b = poses.body(role, stage, design)
            base = {(r, c): fr for r, c, fr in poses.base_cells(b)}
            row = []
            for name, _kind, r, c in picks:
                jid = f"pv_{role}_{stage}_{r}_{c}"
                jobs.append(job(jid, b, base[(r, c)], design, variant, view_cell(), px))
                row.append(jid)
            layout.append((role, stage, row))
    cells = run_jobs(jobs)
    cw, ch = int(CELL[0] * zoom), int(CELL[1] * zoom)
    lab = 60
    W = lab + cw * len(picks) * 2
    H = 70 + ch * len(stages)
    im = Image.new("RGBA", (W, H), bg + (255,))
    d = ImageDraw.Draw(im)
    d.text((16, 16), f"《同岁》主角 · 微缩模型 · {variant} · {design['name']}", fill=(70, 55, 60), font=font(30))
    for i, (role, stage, row) in enumerate(layout):
        y = 70 + (i // 2) * ch
        x0 = lab + (i % 2) * cw * len(picks)
        if i % 2 == 0:
            d.text((10, y + ch // 2 - 20), STAGE_CN[stage], fill=(90, 70, 70), font=font(22))
        for j, jid in enumerate(row):
            im.alpha_composite(load(cells, jid, (cw, ch)), (x0 + j * cw, y))
    d.line([(lab + cw * len(picks), 70), (lab + cw * len(picks), H)], fill=(205, 190, 172), width=2)
    im.convert("RGB").save(path, quality=92)
    shutil.rmtree(os.path.dirname(cells), ignore_errors=True)
    print("✓", path)


def portrait(path, design_key, variant, stages=("child", "teen", "young", "old"), bg=(236, 226, 210)):
    """造型方案：每个年纪两个人站着（游戏里那个角度）+ 两个大头特写。"""
    design = DESIGNS[design_key]
    jobs, cols = [], []
    zoom = 2.4
    fpx = [int(150 * zoom * SS), int(220 * zoom * SS)]
    for stage in stages:
        for role in poses.ROLES:
            b = poses.body(role, stage, design)
            base = {(r, c): fr for r, c, fr in poses.base_cells(b)}
            fr = base[(1, 0)]
            jid = f"pt_{role}_{stage}"
            jobs.append(job(jid, b, fr, design, variant, dict(x0=-75, x1=75, y0=-206, y1=14), fpx))
            hx, hy = fr["head"]
            r = b["head"]
            s = r * 2.1
            hv = dict(x0=hx - s, x1=hx + s, y0=hy - s * 1.1 + r * 0.05, y1=hy + s * 0.9 + r * 0.05)
            hpx = [int(300 * SS), int(300 * SS)]
            jobs.append(job(jid + "_head", b, dict(fr, expr=None), design, variant, hv, hpx, shadow=False))
            # 再来一张笑的
            jobs.append(job(jid + "_smile", b, dict(fr, expr="happy"), design, variant, hv, [int(150 * SS), int(150 * SS)], shadow=False))
            cols.append((role, stage, jid))
    cells = run_jobs(jobs)
    fw, fh = int(150 * zoom), int(220 * zoom)
    pad = 20
    colw = fw + 300 + pad
    W = pad + colw * 2
    H = 90 + (fh + pad) * len(stages)
    im = Image.new("RGBA", (W, H), bg + (255,))
    d = ImageDraw.Draw(im)
    d.text((pad, 18), f"造型方案 {design['name']} · 材质 {variant}", fill=(70, 55, 60), font=font(34))
    for i, (role, stage, jid) in enumerate(cols):
        si = stages.index(stage)
        x = pad + (0 if role == "qing" else colw)
        y = 90 + si * (fh + pad)
        im.alpha_composite(load(cells, jid, (fw, fh)), (x, y))
        im.alpha_composite(load(cells, jid + "_head", (300, 300)), (x + fw, y))
        im.alpha_composite(load(cells, jid + "_smile", (150, 150)), (x + fw + 75, y + 300))
        d.text((x + 8, y + 6), f"{ROLE_CN[role]} · {STAGE_CN[stage]}", fill=(90, 70, 70), font=font(24))
    im.convert("RGB").save(path, quality=93)
    shutil.rmtree(os.path.dirname(cells), ignore_errors=True)
    print("✓", path)


CONTACT_PICKS = [  # (标签, 表, 行, 列)
    ("站", "", 1, 0), ("走", "", 0, 1), ("走", "", 0, 3), ("走", "", 0, 5), ("忙", "", 1, 5), ("坐", "", 2, 0), ("睡", "", 2, 2),
    ("招手", "", 2, 5), ("高兴", "", 3, 2), ("泄气", "", 3, 4), ("击掌", "", 4, 2), ("挠头", "", 4, 4),
    ("写", "_act", 0, 1), ("吃", "_act", 1, 1), ("踢球", "_act", 2, 0), ("修车", "_act", 3, 1), ("炒菜", "_act", 4, 2),
    ("钓鱼", "_act", 4, 5), ("风筝", "_act", 7, 1), ("唱", "_act", 6, 1),
]


def contact(path, sheet_dir, stages, roles, scale=0.62, bg=(236, 226, 210)):
    """从出好的精灵表里挑几格拼一张总览；最底下一行是游戏里的原大（1 世界像素 = 1 像素）。"""
    cw, ch = int(CELL[0] * scale), int(CELL[1] * scale)
    lab = 90
    rows = [(r, s) for s in stages for r in roles]
    W = lab + cw * len(CONTACT_PICKS)
    gh = CELL[1] + 40
    H = 60 + 30 + ch * len(rows) + gh
    im = Image.new("RGBA", (W, H), bg + (255,))
    d = ImageDraw.Draw(im)
    d.text((14, 12), "《同岁》主角精灵表总览 · 微缩模型", fill=(70, 55, 60), font=font(30))
    for j, (name, *_x) in enumerate(CONTACT_PICKS):
        d.text((lab + j * cw + 6, 62), name, fill=(110, 90, 90), font=font(18))
    cache = {}
    for i, (role, stage) in enumerate(rows):
        y = 90 + i * ch
        d.text((8, y + ch // 2 - 12), f"{ROLE_CN[role]}·{STAGE_CN[stage]}", fill=(90, 70, 70), font=font(20))
        for j, (_n, suf, r, c) in enumerate(CONTACT_PICKS):
            key = (role, stage, suf)
            if key not in cache:
                cache[key] = Image.open(os.path.join(sheet_dir, f"{role}_{stage}{suf}.png")).convert("RGBA")
            sc = ART_SCALE if not suf else ACT_ART_SCALE
            cell = cache[key].crop((int(c * CELL[0] * sc), int(r * CELL[1] * sc), int((c + 1) * CELL[0] * sc), int((r + 1) * CELL[1] * sc)))
            im.alpha_composite(cell.resize((cw, ch), Image.LANCZOS), (lab + j * cw, y))
    # 原大：每个年纪两人并排站、走
    y = H - gh
    d.text((8, y + 6), "游戏里原大（1 世界像素 = 1 像素）", fill=(90, 70, 70), font=font(20))
    x = lab
    for stage in stages:
        for role in roles:
            key = (role, stage, "")
            for (r, c) in ((1, 0), (0, 2)):
                cell = cache[key].crop((int(c * CELL[0] * 2), int(r * CELL[1] * 2), int((c + 1) * CELL[0] * 2), int((r + 1) * CELL[1] * 2)))
                cell = cell.resize(CELL, Image.LANCZOS).crop((50, 0, 150, CELL[1]))
                im.alpha_composite(cell, (x, y + 30))
                x += 70
        x += 30
    im.convert("RGB").save(path)
    print("✓", path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", default="toy", choices=("toy", "clay", "lowpoly"))
    ap.add_argument("--design", default=DEFAULT_DESIGN, choices=tuple(DESIGNS))
    ap.add_argument("--only", default="", help="只出这些年纪，逗号分开")
    ap.add_argument("--roles", default="")
    ap.add_argument("--preview", help="出一张预览（不写精灵表）")
    ap.add_argument("--portrait", help="出一张造型方案（全身 + 大头）")
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--contact", help="出完表以后再拼一张总览 PNG（只拼不渲染：加 --no-render）")
    ap.add_argument("--no-render", action="store_true")
    a = ap.parse_args()
    stages = a.only.split(",") if a.only else list(poses.STAGES)
    roles = a.roles.split(",") if a.roles else list(poses.ROLES)
    if a.preview:
        preview(a.preview, a.design, a.variant, stages)
        return
    if a.portrait:
        portrait(a.portrait, a.design, a.variant, tuple(s for s in stages if s != "middle") if not a.only else tuple(stages))
        return
    if a.no_render:
        contact(a.contact, a.out, stages, roles)
        return
    t = time.time()
    jobs = []
    for stage in stages:
        for role in roles:
            jobs += sheet_jobs(role, stage, DESIGNS[a.design], a.variant)
    cells = run_jobs(jobs)
    os.makedirs(a.out, exist_ok=True)
    for stage in stages:
        for role in roles:
            for suffix in ("", "_act"):
                path = os.path.join(a.out, f"{role}_{stage}{suffix}.png")
                save_sheet(pack_sheet(cells, role, stage, suffix), path)
                print("✓", os.path.relpath(path, ROOT))
    shutil.rmtree(os.path.dirname(cells), ignore_errors=True)
    print(f"共 {time.time() - t:.0f} s")
    if a.contact:
        contact(a.contact, a.out, stages, roles)


if __name__ == "__main__":
    main()
