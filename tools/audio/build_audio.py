#!/usr/bin/env python3
"""生成《同岁》的全部声音 → client/audio/。

    python3 tools/audio/build_audio.py              # 全部
    python3 tools/audio/build_audio.py music        # 只做配乐
    python3 tools/audio/build_audio.py amb sfx      # 只做环境音和音效
    python3 tools/audio/build_audio.py --only whistle_a,radio   # 只做指定的几个

需要 numpy、scipy 和命令行里的 ffmpeg（带 libvorbis）。
同一份代码生成的文件逐字节相同；没改的声音不会在 git 里显示为改动。
生成后用 Godot 打开一次项目（或 godot --headless --editor --quit）让它导入。
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from tongsui_audio import amb, highlight, music, sfx  # noqa: E402
from tongsui_audio.dsp import SR, lufs, peak_db, write_ogg  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
# TONGSUI_AUDIO_OUT=目录：生成到别处（几个人同时试声音时各用各的，不碰 client/audio 和它的清单）
OUT = Path(os.environ["TONGSUI_AUDIO_OUT"]) if os.environ.get("TONGSUI_AUDIO_OUT") else ROOT / "client" / "audio"
Q_MUSIC, Q_VOICE, Q_HE, Q_AMB, Q_SFX = 2.0, 1.0, 0.0, 1.0, 3.0
Q_LAYER = 0.0  # 时段 / 天气那几层（morn、eve）：垫在后面，码率低一点省包体


def _info(y, extra=None):
    d = dict(seconds=round(len(y) / SR, 3), lufs=round(lufs(y), 1), peak=round(peak_db(y), 1))
    d.update(extra or {})
    return d


def job_stage(stage: str):
    loops = music.stage_loops(stage)
    out = {}
    for k, y in loops["stems"].items():
        rel = "music/%s_%s.ogg" % (stage, k)
        if k == "he":  # 「合」是一层很软的垫底，单声道低码率就够
            y = y.mean(axis=1)
        write_ogg(OUT / rel, y, {"bed": Q_MUSIC, "he": Q_HE, "morn": Q_LAYER, "eve": Q_LAYER}.get(k, Q_VOICE))
        out[rel] = _info(y, dict(loop=True))
    for kind in ("call_qing", "call_mei", "resonance", "mismatch"):
        y = music.stinger(stage, kind)
        rel = "music/%s_%s.ogg" % (stage, kind)
        write_ogg(OUT / rel, y, Q_VOICE)
        out[rel] = _info(y)
    meta = dict(bpm=loops["bpm"], seconds=round(loops["length"], 4), bar=round(loops["bar"], 4), bars=music.BARS,
                stems=list(loops["stems"]))
    return out, {stage: meta}


def job_single(name: str):
    fn = {"title": music.title_loop, "roll": music.roll_loop, "ending": music.ending}[name]
    r = fn()
    rel = "music/%s.ogg" % name
    write_ogg(OUT / rel, r["audio"], Q_MUSIC)
    return {rel: _info(r["audio"], dict(loop=name != "ending"))}, {}


def job_highlight(name: str):
    """高光：关口揭晓（<阶段>_rise / pass / top / miss）和长大（grow_<阶段>）。不循环。"""
    y = highlight.render(name)
    rel = "music/%s.ogg" % name
    write_ogg(OUT / rel, y, Q_VOICE)
    return {rel: _info(y)}, {}


def job_loop(name: str):
    y = amb.render_loop(name)
    rel = "amb/%s.ogg" % name
    write_ogg(OUT / rel, y, Q_AMB)
    return {rel: _info(y, dict(loop=True))}, {}


def job_shot(name: str):
    y = amb.render_shot(name)
    rel = "amb/%s.ogg" % name
    write_ogg(OUT / rel, y, Q_AMB + 1)
    return {rel: _info(y)}, {}


def job_sfx(name: str):
    y = sfx.render(name)
    rel = "sfx/%s.ogg" % name
    write_ogg(OUT / rel, y, Q_SFX)
    return {rel: _info(y)}, {}


def run(job):
    fn, arg = job
    t0 = time.time()
    files, stages = globals()[fn](arg)
    return files, stages, "%-10s %-14s %5.1fs" % (fn[4:], arg, time.time() - t0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("groups", nargs="*", default=["music", "amb", "sfx"])
    ap.add_argument("--only", default="")
    ap.add_argument("--jobs", type=int, default=4)
    args = ap.parse_args()
    jobs = []
    if "music" in args.groups:
        jobs += [("job_stage", s) for s in music.STAGES] + [("job_single", n) for n in ("title", "roll", "ending")]
        jobs += [("job_highlight", n) for n in highlight.names()]
    if "amb" in args.groups:
        jobs += [("job_loop", n) for n in amb.LOOPS] + [("job_shot", n) for n in amb.SHOTS]
    if "sfx" in args.groups:
        jobs += [("job_sfx", n) for n in sfx.names()]
    if args.only:
        want = set(args.only.split(","))
        jobs = [j for j in jobs if j[1] in want]
    manifest_path = OUT / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {"files": {}, "stages": {}}
    with ProcessPoolExecutor(args.jobs) as ex:
        for files, stages, line in ex.map(run, jobs):
            manifest["files"].update(files)
            manifest["stages"].update(stages)
            print(line, flush=True)
    for rel in list(manifest["files"]):
        p = OUT / rel
        if not p.exists():
            del manifest["files"][rel]
        else:
            manifest["files"][rel]["bytes"] = p.stat().st_size
    manifest["files"] = dict(sorted(manifest["files"].items()))
    manifest["sample_rate"] = SR
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n")
    total = sum(f["bytes"] for f in manifest["files"].values())
    print("%d 个文件，共 %.2f MB → %s" % (len(manifest["files"]), total / 1e6, OUT))


if __name__ == "__main__":
    main()
