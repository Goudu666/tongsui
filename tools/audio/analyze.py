#!/usr/bin/env python3
"""量声音：响度、真峰值、亮不亮、扎不扎、音高在不在 D 宫五声上。没有耳朵，就靠这些数。

    python3 tools/audio/analyze.py client/audio/sfx --out /tmp/an          # 一个目录
    python3 tools/audio/analyze.py client/audio/sfx/bead.ogg x.wav --out /tmp/an
    python3 tools/audio/analyze.py client/audio/sfx client/audio/amb --out /tmp/an --game   # 再算游戏里实际多响
    python3 tools/audio/analyze.py ... --no-png                               # 不画频谱图

输出：<out>/analysis.md（表）、<out>/analysis.json、<out>/spec/<名字>.png（频谱图）。

每一列的口径：
- 积分 LUFS：BS.1770 带门限的综合响度。短于 400 ms 的声音退回不带门限的整段均方（和 dsp.lufs 一样）。
  对一下就完的短声音，这个数偏大（分母只有它自己那么长），比较时看下一列。
- 短时最大（M max）：400 ms 窗、10 ms 一步的瞬时响度（BS.1770 的 momentary）取最大。前后补静音，
  所以 50 ms 的「嗒」会被摊在 400 ms 里——这更接近耳朵对短声音的感觉。混音按这一列对齐。
- 真峰值：4 倍过采样后的峰值（dBTP）。
- 质心：功率谱的重心（Hz），越高越亮。
- 2–6k：2~6 kHz 占全频带的能量（K 加权后，dB）。耳朵最敏感、最容易「扎」的一段。-6 以上就要留心。
- 音高：起音后最多 0.6 秒的频谱里，谐波和最大的那个基频；音名和离 D 宫五声（D E F# A B）最近的音差几音分。
  「分音」列出最响的几个谱峰（相对最响峰 20 dB 以内、6 kHz 以下）各自离五声几音分，多音的声音（琶音、和弦）看这一列。
  「音高感」：谱峰比谱的中位数高多少 dB。低于 25 的基本是噪声 / 闷响，音高那几列只作参考。

--game 再读 client/scripts/audio/mix_table.gd（BUS_DB、CUE_DB）和声景表，按调用处的 db、pitch（CALLS 表，
抄自 reveal.gd / juice.gd / main_observer.gd / audio_director.gd）算出每个声音在游戏里的短时最大响度：
    游戏里 = 文件的 M max（按 pitch 变速后重量）+ CUE_DB + 调用处 db + 总线
算盘珠是一串，单独按 reveal.gd 的数法模拟一整串再量。
"""
from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
ROOT = Path(__file__).resolve().parents[2]
NOTE = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
PENTA = (2, 4, 6, 9, 11)  # D 宫五声：D E F# A B
MUSIC_LUFS = -20.0        # 配乐四轨全开的文件响度（docs/AUDIO.md §8、合同）

# 调用处传的 (db, pitch)。pitch 有好几个取值的列一串，量的时候取最响的那个。
# 来源：reveal.gd _process、juice.gd _landed / _stamp_together、main.gd（settle）、main_observer.gd、audio_director.gd
CALLS = {
    "bead": [(-2.0, 1.0)],                                   # 一串，另算（simulate_beads）
    "gain": [(-3.0, p) for p in (1.0, 1.1225, 1.2599, 1.4983, 1.6818, 2.0, 2.245, 2.52)] + [(-2.0, 1.5)],
    "seal": [(-4.0, 1.0), (-1.0, 1.12)],
    "pass": [(0.0, 1.0)],
    "miss": [(-1.0, 1.0)],
    "settle": [(-2.0, 1.0)],
    "coin": [(-6.0, 1.0), (0.0, 1.0)],
    "tap": [(0.0, 0.96), (0.0, 1.04), (-2.0, 0.84), (0.0, 1.12)],
    "type": [(0.0, 0.92), (0.0, 1.08)],
}
ACT_DB = -4.0       # audio_director.act()：自己做的事；对方的再轻 6 dB 以上
STEP_DB = -9.0      # audio_director.step()：自己的脚步
STEP_PITCH = (0.92 * 0.93, 1.18 * 1.07)

# 分类和目标：游戏里的短时最大响度比配乐（MUSIC_LUFS + BUS_DB.Music）响多少 LU。
# 配乐总线一改，目标跟着走。mix_table.gd 的注释抄的是这张表，两边要一起改。
#   点按最轻（一直在按，听一小时不能烦）< 反馈（轻而清楚）< 提示 < 结果、仪式（最重，但不超过配乐 +2 LU）
CLASSES = {
    "点按": {"tap": -14, "page": -16, "toast": -12, "type": -22},
    "反馈": {"bead": -10, "gain": -7, "coin": -8, "cord": -10},
    "结果": {"pass": 0, "seal": -1, "settle": -1, "xingmu": -2, "miss": -3, "stamp": -5},
    "仪式": {"death": 0, "birth": -1, "day_end": -2},
    "提示": {"shake": -5, "bell_duet": -6, "error": -8, "door_open": -10, "door_close": -10},
}
ACT_TARGET = -6                    # act_*：自己做的事
ACT_EXTRA = {"act_sleep": -10}     # 拉灯就是 cord，按反馈算
STEP_TARGET = -17                  # step_*：一直在走，最轻的一档（不走 CUE_DB，由 sfx.py 的文件响度管）
AMB_TARGET = -8                    # 环境单发（离得最近、地点权重 1 的时候）：远处的生活，比自己的行动轻
HARSH_AT, HARSH_LU = -6.0, 2       # 2~6 kHz 占比高于 -6 dB 的，目标再让 2 LU（车铃、钢镚儿、纸、铅笔……）


# ---------------------------------------------------------------- 读 ----

def read(path: Path) -> np.ndarray:
    """→ (n, 2) float64，44.1 kHz。"""
    if path.suffix.lower() == ".wav":
        sr, y = wavfile.read(str(path))
        y = y.astype(np.float64) / (32768.0 if y.dtype == np.int16 else 1.0)
        if sr != SR:
            y = signal.resample_poly(y, SR, sr, axis=0)
    else:
        raw = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(path), "-f", "f32le",
                              "-ac", "2", "-ar", str(SR), "pipe:1"], capture_output=True, check=True).stdout
        y = np.frombuffer(raw, dtype="<f4").astype(np.float64).reshape(-1, 2)
    return y if y.ndim == 2 else np.stack([y, y], axis=1)


def collect(args) -> list[Path]:
    out = []
    for a in args:
        p = Path(a)
        if p.is_dir():
            out += sorted(q for q in p.iterdir() if q.suffix.lower() in (".ogg", ".wav"))
        elif p.exists():
            out.append(p)
        else:
            print("没有这个文件：%s" % p, file=sys.stderr)
    return out


# ---------------------------------------------------------------- 量 ----

def _biquad(kind, fc, q, gain_db=0.0):
    a_ = 10 ** (gain_db / 40.0)
    w0 = 2 * math.pi * fc / SR
    alpha = math.sin(w0) / (2 * q)
    cs = math.cos(w0)
    if kind == "hs":
        b = [a_ * ((a_ + 1) + (a_ - 1) * cs + 2 * math.sqrt(a_) * alpha), -2 * a_ * ((a_ - 1) + (a_ + 1) * cs),
             a_ * ((a_ + 1) + (a_ - 1) * cs - 2 * math.sqrt(a_) * alpha)]
        a = [(a_ + 1) - (a_ - 1) * cs + 2 * math.sqrt(a_) * alpha, 2 * ((a_ - 1) - (a_ + 1) * cs),
             (a_ + 1) - (a_ - 1) * cs - 2 * math.sqrt(a_) * alpha]
    else:
        b = [(1 + cs) / 2, -(1 + cs), (1 + cs) / 2]
        a = [1 + alpha, -2 * cs, 1 - alpha]
    return np.array(b) / a[0], np.array(a) / a[0]


_K = (_biquad("hs", 1500.0, 1 / math.sqrt(2), 4.0), _biquad("hp", 38.0, 0.5))


def k_weight(x: np.ndarray) -> np.ndarray:
    (b1, a1), (b2, a2) = _K
    return signal.lfilter(b2, a2, signal.lfilter(b1, a1, x, axis=0), axis=0)


def integrated(x: np.ndarray) -> float:
    s = k_weight(x)
    block, hop = int(0.4 * SR), int(0.1 * SR)
    if len(s) < block:
        return -0.691 + 10 * math.log10(float((s ** 2).mean(axis=0).sum()) + 1e-12)
    c = np.cumsum(np.concatenate([[0.0], (s ** 2).sum(axis=1)]))
    st = np.arange(0, len(s) - block + 1, hop)
    p = (c[st + block] - c[st]) / block
    l = -0.691 + 10 * np.log10(p + 1e-12)
    keep = p[l > -70]
    if len(keep) == 0:
        return -70.0
    rel = -0.691 + 10 * math.log10(keep.mean()) - 10
    keep = keep[(-0.691 + 10 * np.log10(keep + 1e-12)) > rel]
    return float(-0.691 + 10 * math.log10(keep.mean() + 1e-12))


def momentary_max(x: np.ndarray) -> float:
    """400 ms 窗、10 ms 一步的瞬时响度最大值。前后各补 400 ms 静音。"""
    block, hop = int(0.4 * SR), int(0.01 * SR)
    pad = np.zeros((block, 2))
    s = k_weight(np.concatenate([pad, x, pad]))
    c = np.cumsum(np.concatenate([[0.0], (s ** 2).sum(axis=1)]))
    st = np.arange(0, len(s) - block + 1, hop)
    p = (c[st + block] - c[st]) / block
    return float(-0.691 + 10 * math.log10(p.max() + 1e-12))


def true_peak(x: np.ndarray) -> float:
    up = signal.resample_poly(x, 4, 1, axis=0)
    return float(20 * math.log10(np.max(np.abs(up)) + 1e-12))


def _psd(x: np.ndarray, weighted: bool):
    # 整段一次 FFT、不加窗（声音前后本来就是静的）。welch 那种分段加窗会把短声音的起音压掉，
    # 衰减快的高分音就被少算了——一个 0.1 秒的「嗒」能少算 8 dB
    m = (k_weight(x) if weighted else x).mean(axis=1)
    p = np.abs(np.fft.rfft(m)) ** 2
    return np.fft.rfftfreq(len(m), 1 / SR), p


def centroid(x: np.ndarray) -> float:
    f, p = _psd(x, False)
    sel = f > 30
    return float((f[sel] * p[sel]).sum() / (p[sel].sum() + 1e-20))


def band_share(x: np.ndarray, lo=2000.0, hi=6000.0) -> float:
    f, p = _psd(x, True)
    return float(10 * math.log10(p[(f >= lo) & (f < hi)].sum() / (p[f > 30].sum() + 1e-20) + 1e-20))


def note_of(f: float):
    """→ (音名, 离最近的五声音几音分)"""
    m = 69 + 12 * math.log2(f / 440.0)
    name = NOTE[int(round(m)) % 12] + str(int(round(m)) // 12 - 1)
    c = (m * 100.0) % 1200.0
    best = min((((c - pc * 100.0 + 600.0) % 1200.0) - 600.0 for pc in PENTA), key=abs)
    return name, float(best)


def pitch(x: np.ndarray):
    """→ dict(f0, note, cents, tonal, partials=[(Hz, 相对 dB, 音名, 音分)])"""
    m = x.mean(axis=1)
    env = np.abs(m)
    on = int(np.argmax(env > env.max() * 0.03))
    seg = m[on + int(0.004 * SR): on + int(0.6 * SR)]
    if len(seg) < 512:
        seg = m[on:]
    nfft = 1 << 17
    spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), nfft))
    f = np.fft.rfftfreq(nfft, 1 / SR)
    sdb = 20 * np.log10(spec + 1e-12)
    band = (f > 50) & (f < 6000)
    top = sdb[band].max()
    tonal = float(top - np.median(sdb[band]))
    pk, _ = signal.find_peaks(sdb, prominence=8, distance=int(20 / (f[1] - f[0])))
    pk = [i for i in pk if 50 < f[i] < 6000 and sdb[i] > top - 20]
    pk.sort(key=lambda i: -sdb[i])
    partials = []
    for i in pk[:6]:
        # 抛物线插值，把峰的频率估得细一点
        a, b, c = sdb[i - 1], sdb[i], sdb[i + 1]
        d = 0.5 * (a - c) / (a - 2 * b + c + 1e-12)
        fr = f[i] + d * (f[1] - f[0])
        nm, ct = note_of(fr)
        partials.append((round(float(fr), 1), round(float(b - top), 1), nm, round(ct)))
    # 基频：在谱峰和它们的 1/2、1/3 里找谐波和最大的
    lin = spec / (spec.max() + 1e-12)
    cands = sorted({p[0] / k for p in partials for k in (1, 2, 3) if p[0] / k > 60})
    best, f0 = -1.0, partials[0][0] if partials else 0.0
    for c0 in cands:
        sc = 0.0
        for h in range(1, 9):
            j = int(round(h * c0 / (f[1] - f[0])))
            w = max(1, int(j * 0.015))
            if j + w < len(lin):
                sc += lin[j - w: j + w + 1].max() / h ** 0.5
        if sc > best * 1.05:
            best, f0 = sc, c0
    nm, ct = note_of(f0) if f0 > 0 else ("-", 0.0)
    return dict(f0=round(float(f0), 1), note=nm, cents=round(ct), tonal=round(tonal), partials=partials)


def analyze(y: np.ndarray) -> dict:
    p = pitch(y)
    return dict(seconds=round(len(y) / SR, 3), lufs=round(integrated(y), 1), m_max=round(momentary_max(y), 1),
                true_peak=round(true_peak(y), 1), centroid=round(centroid(y)), harsh=round(band_share(y), 1), **p)


def repitch(y: np.ndarray, ratio: float) -> np.ndarray:
    """像 pitch_scale 那样变速（音高、时长一起变）。"""
    if abs(ratio - 1.0) < 1e-4:
        return y
    n = int(len(y) / ratio)
    src = np.arange(n) * ratio
    return np.stack([np.interp(src, np.arange(len(y)), y[:, c]) for c in range(2)], axis=1)


# ---------------------------------------------------------------- 画 ----

def spectrogram(y: np.ndarray, title: str, path: Path) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    m = y.mean(axis=1)
    nper = 1024 if len(m) > 4096 else 256
    f, t, s = signal.spectrogram(m, SR, nperseg=nper, noverlap=nper * 7 // 8, window="hann")
    sdb = 10 * np.log10(s + 1e-14)
    fig, ax = plt.subplots(figsize=(7, 3.2), dpi=110)
    ax.pcolormesh(t, f, sdb, shading="auto", cmap="magma", vmin=sdb.max() - 80, vmax=sdb.max())
    ax.set_yscale("symlog", linthresh=500)
    ax.set_ylim(40, 16000)
    ax.axhspan(2000, 6000, color="white", alpha=0.06)
    for pc in PENTA:  # D 宫五声的位置（D4 往上三个八度）
        for o in range(3, 8):
            fr = 440.0 * 2 ** ((pc + 12 * (o + 1) - 69) / 12.0)
            if 60 < fr < 6000:
                ax.axhline(fr, color="cyan", lw=0.3, alpha=0.35)
    ax.set_xlabel("s")
    ax.set_ylabel("Hz")
    ax.set_title(title, fontsize=9)
    fig.tight_layout()
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path)
    plt.close(fig)


# ---------------------------------------------------------------- 游戏里 ----

def read_table(src: str, name: str) -> dict:
    """从 gdscript 里抠出 const NAME := {"a": 1.0, ...}（可以跨行、带 # 注释）。"""
    m = re.search(r"const\s+%s\s*:=\s*\{" % name, src)
    if not m:
        return {}
    i, depth = m.end(), 1
    while depth:
        depth += {"{": 1, "}": -1}.get(src[i], 0)
        i += 1
    body = re.sub(r"#[^\n]*", "", src[m.end(): i - 1])
    return {k: float(v) for k, v in re.findall(r'"(\w+)"\s*:\s*(-?[\d.]+)', body)}


def simulate_beads(bead: np.ndarray, pitch_of, score=72, lo=20.0, fps=60.0) -> np.ndarray:
    """照 reveal.gd 的 _process 数一遍：每两分一颗，两颗至少隔 35 ms。pitch_of(k) → pitch。"""
    dur = min(max(0.65 + abs(score - lo) / 70.0, 0.8), 1.7)
    out = np.zeros((int((dur + 0.5) * SR), 2))
    t, last, at = 0.0, -1, -1.0
    while t <= dur + 1 / fps:
        x = min(max(t / dur, 0.0), 1.0)
        k = 1.0 - (1.0 - x) ** 2.6
        v = lo + (score - lo) * k
        step = int(v // 2)
        if step != last and t - at > 0.035:
            last, at = step, t
            b = repitch(bead, pitch_of(k))
            i = int(t * SR)
            j = min(len(out), i + len(b))
            out[i:j] += b[: j - i]
        t += 1 / fps
    return out


def game_table(rows: dict, files: dict, mix_src: Path, scape: Path | None, bead_pitch) -> list[dict]:
    src = mix_src.read_text()
    bus, cue = read_table(src, "BUS_DB"), read_table(src, "CUE_DB")
    music = MUSIC_LUFS + bus.get("Music", 0.0)
    shots = {}
    if scape and scape.exists():
        for s in json.loads(scape.read_text())["shots"]:
            for f in s["files"]:
                shots.setdefault(f, s.get("db", -12.0))
    cls_of = {n: (cl, t) for cl, tg in CLASSES.items() for n, t in tg.items()}
    out = []
    for key, r in rows.items():
        group, name = key.split("/", 1) if "/" in key else ("sfx", key)
        y = files[key]
        if group == "amb":
            if name not in shots:
                continue  # 循环的那些另有口径（声景表的床），这里只看单发
            g = shots[name] + bus.get("Ambience", 0.0)
            m = r["m_max"] + g
            tgt = AMB_TARGET - (HARSH_LU if r["harsh"] > HARSH_AT else 0)
            out.append(dict(name=key, cls="环境单发", calls="声景 %+g" % shots[name], cue_db=None, game=round(m, 1),
                            rel=round(m - music, 1), target=tgt, tp=round(r["true_peak"] + g, 1),
                            need=round(shots[name] + (music + tgt - m), 1)))
            continue
        if name.startswith("step_"):
            cl, tgt = "脚步", STEP_TARGET
            calls = [(STEP_DB, p) for p in STEP_PITCH]
            cdb = 0.0   # 脚步不走 CUE_DB
        else:
            if name.startswith("act_"):
                cl, tgt = "行动", ACT_EXTRA.get(name, ACT_TARGET)
                calls = [(ACT_DB, 1.0)]
            else:
                cl, tgt = cls_of.get(name, ("其他", None))
                calls = CALLS.get(name, [(0.0, 1.0)])
            cdb = cue.get(name, -6.0)
        if name == "bead":
            train = simulate_beads(y, bead_pitch)
            best = (momentary_max(train) + calls[0][0], calls[0][0], 1.0)
            tpk = true_peak(train) + calls[0][0]
        else:
            best, tpk = None, -99.0
            for d, p in calls:
                yy = repitch(y, p)
                mm = momentary_max(yy) + d
                if best is None or mm > best[0]:
                    best = (mm, d, p)
                tpk = max(tpk, true_peak(yy) + d)
        if tgt is not None and r["harsh"] > HARSH_AT:
            tgt -= HARSH_LU
        g = cdb + bus.get("Sfx", 0.0)
        m = best[0] + g
        out.append(dict(name=key, cls=cl, calls="%+g dB × %.2f" % (best[1], best[2]), cue_db=cdb, game=round(m, 1),
                        rel=round(m - music, 1), target=tgt, tp=round(tpk + g, 1),
                        need=None if tgt is None else round(cdb + (music + tgt - m), 1)))
    order = list(CLASSES) + ["行动", "脚步", "其他", "环境单发"]
    out.sort(key=lambda d: (order.index(d["cls"]), d["name"]))
    return out, music


# ---------------------------------------------------------------- 主 ----

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--out", required=True)
    ap.add_argument("--no-png", action="store_true")
    ap.add_argument("--game", action="store_true", help="按 mix_table.gd 和调用处的 db / pitch 算游戏里的响度")
    ap.add_argument("--mix", default=str(ROOT / "client/scripts/audio/mix_table.gd"))
    ap.add_argument("--scape", default=str(ROOT / "client/audio/soundscape.json"))
    ap.add_argument("--bead-pitch", default="penta", choices=["penta", "linear"],
                    help="模拟算盘珠时 pitch 怎么取：penta = 现在 reveal.gd 的五声取值；linear = 老的 0.85 + 0.5k")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    rows, files = {}, {}
    for p in collect(args.paths):
        key = "%s/%s" % (p.parent.name, p.stem)
        y = read(p)
        files[key] = y
        rows[key] = analyze(y)
        if not args.no_png:
            r = rows[key]
            spectrogram(y, "%s  M %.1f  TP %.1f  2-6k %.1f dB  f0 %s %+d" % (key, r["m_max"], r["true_peak"], r["harsh"],
                                                                         r["note"], r["cents"]),
                        out / "spec" / (key.replace("/", "_") + ".png"))
    md = ["| 文件 | 时长 s | 积分 LUFS | 短时最大 | 真峰值 | 质心 Hz | 2–6k dB | 基频 | 音名 | 离五声 ¢ | 音高感 | 分音（Hz 相对dB 音名 ¢） |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for k, r in rows.items():
        parts = "; ".join("%g %+g %s %+d" % p for p in r["partials"][:4])
        md.append("| %s | %.2f | %.1f | %.1f | %.1f | %d | %.1f | %.0f | %s | %+d | %d | %s |" % (
            k, r["seconds"], r["lufs"], r["m_max"], r["true_peak"], r["centroid"], r["harsh"], r["f0"], r["note"],
            r["cents"], r["tonal"], parts))
    result = {"files": rows}
    if args.game:
        bead_pitch = (lambda k: PENTA_BEAD[min(int(k * len(PENTA_BEAD)), len(PENTA_BEAD) - 1)]) \
            if args.bead_pitch == "penta" else (lambda k: 0.85 + 0.5 * k)
        game, music = game_table(rows, files, Path(args.mix), Path(args.scape), bead_pitch)
        result["game"] = game
        result["music_lufs"] = music
        md += ["", "## 游戏里（短时最大，LUFS）", "",
               "配乐参照 %.1f LUFS（文件 %.0f + Music 总线）。「相对」= 比配乐响多少 LU；「该改成」= 让它落到目标上的 CUE_DB（环境单发是声景表的 db；脚步是文件要动多少 dB）。" % (
                   music, MUSIC_LUFS), "",
               "| 声音 | 分类 | 最响的那次调用 | CUE_DB | 游戏里 | 相对配乐 | 目标 | 该改成 | 游戏里真峰值 |",
               "|---|---|---|---|---|---|---|---|---|"]
        for g in game:
            md.append("| %s | %s | %s | %s | %.1f | %+.1f | %s | %s | %.1f |" % (
                g["name"], g["cls"], g["calls"], "-" if g["cue_db"] is None else "%g" % g["cue_db"], g["game"], g["rel"],
                "-" if g["target"] is None else "%+d" % g["target"], "-" if g.get("need") is None else "%g" % g["need"],
                g["tp"]))
    (out / "analysis.md").write_text("\n".join(md) + "\n")
    (out / "analysis.json").write_text(json.dumps(result, ensure_ascii=False, indent=1) + "\n")
    print("\n".join(md))


# reveal.gd 里算盘珠的五声取值（B4 D5 E5 F#5 A5 相对 D 的倍数，见 reveal.gd _process）
PENTA_BEAD = [0.8409, 1.0, 1.1225, 1.2599, 1.4983]

if __name__ == "__main__":
    main()
