"""高光音乐：关口揭晓和长大。不循环，叠在压低了的配乐上面。

关口揭晓，每个阶段一套，用这个阶段的两件乐器：
  <阶段>_rise  数分时往上爬：伴奏乐器的上行五声，底下一串轻轻的滚奏越来越响。
               停在 A 上不解决。算盘珠在上面响，所以 1.5~4 kHz 整段让出来。
  <阶段>_pass  够线：主题第 13~16 小节的浓缩。青往上、梅往下，从两头往中间走，
               落在同一个音上，Dadd9 托开。不吹号，要的是「话接上了」。
  <阶段>_top   够着名次档：pass 再加一层——高八度的应答，最后铃的余晖。
  <阶段>_miss  差一点：半句话悬着，低音垫一个下属和弦接住（先哏后疼），停在 A7sus4 上。
长大：grow_<阶段>（进入这个阶段时放）。上一阶段的青说「小皮球」半句，
  新阶段的梅接后半句、落在主音上，新阶段的伴奏在最后一小节进来。像翻过一页。

谱子写成 (拍, 时值, 级, 八度)，八度按「实际音区」写（八度 0 = D4 那一组），
各阶段乐器自带的八度在 _abs 里扣掉，所以青、梅能真落在同一个音上。
"""
from __future__ import annotations

import numpy as np
from scipy import signal

from . import inst
from .dsp import Mix, db, echo, fade, hp, lp, lufs, modal, peak, rng_for, sec, times, to_stereo, trim, white
from .music import CHORD, P, STAGES, Clock, _space, voice_m, voice_q

ORDER = list(STAGES)  # child teen young middle old
KINDS = ("rise", "pass", "top", "miss")
PAN_Q, PAN_M = -0.25, 0.25
TARGET = -18.0  # 高光整段的响度（配乐全开是 -20）
TRUE_PEAK = -2.0  # 编码前留 0.5 dB 给 Vorbis，解码后 ≤ -1.5

# 每个阶段两条线整体挪的音区（半音）。中年老年低一个八度：大提琴、二胡、三弦的好听的地方在下面。
REG = {"child": 0, "teen": 0, "young": 0, "middle": -12, "old": -12}
# 揭晓和长大的速度：比配乐快一点，但老年仍然慢
BPM_PASS = {"child": 150, "teen": 144, "young": 152, "middle": 140, "old": 132}
BPM_MISS = {"child": 108, "teen": 100, "young": 108, "middle": 92, "old": 88}
BPM_GROW = {"teen": 104, "young": 106, "middle": 100, "old": 92}


def names() -> list[str]:
    out = ["%s_%s" % (s, k) for s in ORDER for k in KINDS]
    return out + ["grow_%s" % s for s in ORDER[1:]]


def render(name: str) -> np.ndarray:
    if name.startswith("grow_"):
        new = name[5:]
        if new not in ORDER[1:]:
            raise KeyError(name)
        return grow(ORDER[ORDER.index(new) - 1], new)
    stage, _, kind = name.rpartition("_")
    if stage not in STAGES or kind not in KINDS:
        raise KeyError(name)
    return {"rise": rise, "pass": lambda s: reveal(s, False), "top": lambda s: reveal(s, True), "miss": miss}[kind](stage)


# ------------------------------------------------------------ 工具 ----

def _abs(stage: str, role: str, line, shift: int = 0):
    """把按实际音区写的谱子换成 voice_q / voice_m 要的八度（扣掉乐器自带的八度）。"""
    octv = STAGES[stage][role][1]
    k = (REG[stage] + shift) // 12 - octv
    return [(b, d, deg, o + k) for b, d, deg, o in line]


def _q(stage: str, ck: Clock, line, shift: int = 0) -> np.ndarray:
    q = voice_q(stage, ck, _abs(stage, "q", line, shift)).buf.mean(axis=1)
    if STAGES[stage]["q"][0] == "egtr":  # 电吉他带一点回声，和配乐一样
        q = echo(q, 0.75 * ck.spb, 0.35, 0.18, 2600, 2).mean(axis=1)
    return q


def _m(stage: str, ck: Clock, line, shift: int = 0) -> np.ndarray:
    m = voice_m(stage, ck, _abs(stage, "m", line, shift))
    if STAGES[stage]["m"][0] == "lead":
        m = echo(m, 0.75 * ck.spb, 0.35, 0.16, 2400, 2).mean(axis=1)
    if STAGES[stage]["m"][0] == "erhu":  # 二胡 3 kHz 那个峰在高光里贴得太近，收一点
        m = peak(m, 3000, 0.9, -4.0)
    return m


def _penta(lo: int, hi: int) -> list[int]:
    """lo~hi 之间 D 宫五声的音（含两头）。"""
    return [m for m in range(lo, hi + 1) if (m - 62) % 12 in (0, 2, 4, 7, 9)]


def true_peak(x: np.ndarray) -> float:
    """四倍过采样量真峰值（dBTP）。"""
    y = signal.resample_poly(np.asarray(x, dtype=np.float64), 4, 1, axis=0)
    return float(20 * np.log10(np.max(np.abs(y)) + 1e-12))


def _limit(x: np.ndarray, ceil_db: float) -> np.ndarray:
    """很轻的前瞻限幅：只削最尖的几个头（拨弦的第一下），不碰整体动态。"""
    thr = db(ceil_db)
    mag = np.abs(x).max(axis=1)
    w = sec(0.004)
    env = np.lib.stride_tricks.sliding_window_view(np.pad(mag, (w, w), mode="edge"), 2 * w + 1).max(axis=1)
    g = np.minimum(1.0, thr / np.maximum(env, 1e-9))
    g = np.convolve(np.pad(g, (w, w), mode="edge"), np.hanning(2 * w + 1) / np.hanning(2 * w + 1).sum(), mode="valid")
    return x * g[:, None]


def _finish(y: np.ndarray, length: float, tail: float, target: float = TARGET) -> np.ndarray:
    """切掉开头的空白；到 length 秒收住，最后 tail 秒慢慢淡下去（越到后面掉得越快，像余音自己散了），
    再把听不见的尾巴切掉。调到目标响度，真峰值压在 TRUE_PEAK 下。"""
    mag = np.abs(y).max(axis=1)
    start = int(np.argmax(mag > mag.max() * db(-50)))
    y = np.array(y[max(0, start - sec(0.002)):][:sec(length)], copy=True)
    k = min(len(y), sec(tail))
    y[-k:] *= ((1.0 - np.linspace(0, 1, k)) ** 2.2)[:, None]
    y = trim(y, -54.0, 0.05)
    y = y * db(target - lufs(y))
    for _ in range(4):  # 峰超了先轻轻限一下，不行再整体降
        tp = true_peak(y)
        if tp <= TRUE_PEAK:
            break
        y = _limit(y, TRUE_PEAK - 0.4) if tp - TRUE_PEAK < 3.0 else y * db(TRUE_PEAK - tp)
    tp = true_peak(y)
    if tp > TRUE_PEAK:
        y = y * db(TRUE_PEAK - tp)
    return y


# ------------------------------------------------------------ 乐器 ----

def roll(dur: float, f0: float, seed: int, rate: float = 17.0, lo_db: float = -28.0, hi_db: float = -3.0) -> np.ndarray:
    """软槌滚奏：一串很密的软敲，鼓腔的音连成一片，越来越响。只有低频，不占算盘珠的地方。"""
    rng = np.random.default_rng(seed)
    n = sec(dur + 0.8)
    out = np.zeros(n)
    hit_n = sec(0.7)
    tt = times(hit_n)
    body = (np.sin(2 * np.pi * f0 * tt) + 0.45 * np.sin(2 * np.pi * f0 * 1.51 * tt + 1.0) * np.exp(-tt / 0.18)
            + 0.25 * np.sin(2 * np.pi * f0 * 1.99 * tt + 2.0) * np.exp(-tt / 0.12)) * np.exp(-tt / 0.42)
    t = 0.0
    i = 0
    while t < dur:
        x = t / dur
        g = db(lo_db + (hi_db - lo_db) * x ** 0.7 + float(rng.uniform(-1.2, 1.2)))
        at = sec(t)
        k = min(hit_n, n - at)
        thump = lp(white(sec(0.012), rng), 500) * np.linspace(1, 0, sec(0.012)) ** 2 * 0.6
        out[at:at + k] += body[:k] * g
        out[at:at + len(thump)] += thump[: n - at] * g
        t += (1.0 / rate) * (1.0 + float(rng.uniform(-0.12, 0.12)))
        i += 1
    return fade(lp(out, 700, 3), 0.001, 0.3)


def bell(m: float, vel: float = 0.6, ring: float = 2.6) -> np.ndarray:
    """碰铃一类的小铃：几个不成谐波的泛音，高的掉得快，余音长。"""
    f = 440.0 * 2 ** ((m - 69) / 12)
    n = sec(ring + 0.4)
    rng = np.random.default_rng(int(m * 31))
    y = modal(n, [f, 2.76 * f, 5.40 * f, 8.93 * f, 1.003 * f],
              [ring * 0.55, ring * 0.22, ring * 0.09, ring * 0.04, ring * 0.5],
              [1.0, 0.35, 0.16, 0.06, 0.5], rng, 0.0008)
    return fade(lp(y, 9000) * vel * 0.32, 0.0008, 0.3)


def _pad(notes, total: float, model: str, seed: int, level: float = 0.5, voices: int = 3, spread: float = 9.0):
    """每个音单独一条（叠起来，不滑音）。notes: (起秒, 秒, midi, 力度)。"""
    out = np.zeros(sec(total))
    for i, nt in enumerate(notes):
        out += inst.ensemble_line([nt], total, model, seed + 7 * i, level, voices, spread)
    return out


# ---- 伴奏的一个和弦：按各阶段配乐里伴奏的样子弹 ----

def comp(stage: str, mx: Mix, t: float, dur: float, name: str, spb: float, vel: float, rng, bass: bool = True):
    root, tones, he = CHORD[name]
    if stage == "child":  # 拇指琴分解和弦
        pat = [tones[0], tones[2], tones[1], tones[2]]
        for i in range(max(1, int(round(dur / (0.5 * spb))))):
            acc = (0.6 if i % 4 == 0 else 0.46) * vel
            mx.add(inst.kalimba(pat[i % 4], 0.45, round(acc, 2)), t + i * 0.5 * spb + abs(rng.uniform(0, 0.004)),
                   0.5, pan=0.18 * (1 if i % 2 else -1))
    elif stage == "teen":  # 尼龙弦分解
        pat = [root + 12, tones[1], tones[2], tones[1], tones[0], tones[1], tones[2], tones[1]]
        for i in range(max(1, int(round(dur / (0.5 * spb))))):
            v = (0.6 if i == 0 else 0.46) * vel
            mx.add(inst.guitar(pat[i % 8], 1.4 * spb, round(v, 2), True), t + i * 0.5 * spb + abs(rng.uniform(0, 0.006)),
                   1.0, pan=-0.12)
    elif stage == "young":  # 电钢琴一下
        voicing = tones + [he[1] if he[1] not in tones else tones[0] + 12]
        for j, m in enumerate(voicing):
            mx.add(inst.epiano(m, min(dur, 1.6 * spb), round(0.5 * vel, 2)), t + j * 0.006, 0.6, pan=0.25 * (j - 1.5) / 1.5)
    elif stage == "middle":  # 弦乐长音
        y = _pad([(0.0, dur, m, 0.6 * vel) for m in tones], dur + 1.2, "pad", 60, 0.5, 3, 10.0)
        mx.add(y, t, 0.45)
    elif stage == "old":  # 只有根音和五度两个长音
        y = _pad([(0.0, dur, root + 12, 0.55 * vel), (0.0, dur, root + 19, 0.45 * vel)], dur + 1.0, "organ", 70, 0.5, 2, 6.0)
        mx.add(y, t, 0.38)
    if bass:
        if stage == "middle":
            mx.add(inst.piano(root, dur * 1.1, round(0.45 * vel, 2)), t, 1.0, pan=-0.15)
        elif stage != "old":
            mx.add(inst.bass(root, dur * 0.95, round(0.6 * vel, 2), stage != "young"), t, 0.55)


def bloom(stage: str, mx: Mix, t: float, spb: float, vel: float, rng, full: bool = False, ring: float = 2.4):
    """落音时把 Dadd9 托开：从低到高摊开的和弦 + 一层垫子。full 是名次档：更宽更厚。"""
    spread = [38, 45, 57, 64, 66, 69] + ([74, 76, 78] if full else [74])
    gap = 0.045 if stage in ("middle", "old") else 0.035
    if stage == "child":
        for j, m in enumerate(spread):
            mx.add(inst.kalimba(m, 1.2, round(0.55 * vel, 2)), t + j * gap, 0.42, pan=-0.4 + 0.8 * j / len(spread))
    elif stage == "teen":
        for j, m in enumerate(spread):  # 扫弦，慢一点
            mx.add(inst.guitar(m, ring, round(0.5 * vel, 2), True), t + j * 0.028, 0.9, pan=-0.3 + 0.6 * j / len(spread))
    elif stage == "young":
        for j, m in enumerate(spread[1:]):
            mx.add(inst.epiano(m, ring * 0.8, round(0.5 * vel, 2)), t + j * 0.01, 0.55, pan=0.3 * (j / 4 - 1))
        mx.add(inst.kick(0.5), t, 0.35)
    elif stage == "middle":
        for j, m in enumerate(spread[:5]):
            mx.add(inst.piano(m, ring, round(0.42 * vel, 2)), t + j * gap, 0.9, pan=-0.3 + 0.15 * j)
    # 垫子：老年用风琴，其余用弦
    model = "organ" if stage == "old" else "pad"
    tones = [50, 57, 64, 66] + ([69, 74] if full else [])
    if stage == "old":
        tones = [38, 45, 57, 64] + ([69] if full else [])
    y = _pad([(0.0, ring, m, 0.6) for m in tones], ring + 1.4, model, 81, 0.5, 3 if full else 2, 8.0)
    mx.add(y, t, (0.42 if stage == "old" else 0.32) * vel)
    if stage != "old":
        mx.add(inst.bass(38, ring * 0.9, round(0.65 * vel, 2)), t, 0.6)
    else:
        mx.add(inst.sanxian(38, ring * 0.6, 0.5), t, 0.5)


# ------------------------------------------------------------ 揭晓 ----

def rise(stage: str) -> np.ndarray:
    """往上爬：伴奏乐器的上行五声，一路越弹越密越响，停在悬着的 A 上。"""
    rng = rng_for(stage + "_rise")
    dur = 2.25
    mx = Mix(dur + 2.0)
    lo, hi = {"child": (57, 88), "teen": (50, 76), "young": (50, 76), "middle": (50, 76), "old": (50, 69)}[stage]
    notes = _penta(lo, hi)
    while notes and (notes[-1] - 62) % 12 != 4:  # 停在「2」上：A 上面的五度，悬着
        notes.pop()
    k = len(notes)
    at = [dur * 0.92 * (i / k) ** 0.78 for i in range(k)]  # 越来越密
    vel = [0.32 + 0.5 * (i / max(1, k - 1)) ** 1.2 for i in range(k)]
    for i, (m, t, v) in enumerate(zip(notes, at, vel)):
        pan = -0.35 + 0.7 * i / max(1, k - 1)
        last = i >= k - 2
        if stage == "child":
            mx.add(inst.kalimba(m, 1.2 if last else 0.5, round(v, 2)), t, 0.55, pan)
        elif stage == "teen":
            mx.add(inst.guitar(m, 1.6 if last else 0.9, round(v, 2), True), t, 1.0, pan)
        elif stage == "young":
            mx.add(inst.epiano(m, 1.4 if last else 0.6, round(v, 2)), t, 0.7, pan)
        elif stage == "middle":
            mx.add(inst.piano(m, 1.6 if last else 0.8, round(v * 0.9, 2)), t, 1.1, pan)
    if stage == "old":  # 风琴一个音一个音叠上去，叠成一片
        ln = [(t, dur + 0.3 - t, m, 0.35 + 0.35 * i / max(1, k - 1)) for i, (m, t) in enumerate(zip(notes, at))]
        mx.add(_pad(ln, dur + 1.6, "organ", 71, 0.5, 2, 6.0), 0.0, 0.5)
        for i, (m, t) in enumerate(zip(notes, at)):  # 三弦轻轻点着
            if i % 2 == 0:
                mx.add(inst.sanxian(m, 0.5, round(0.3 + 0.3 * i / k, 2)), t, 0.5, pan=0.2)
    # 底下：A 的长音（属，不落回 D）+ 弦的悬挂和弦慢慢涨上来
    sus = CHORD["A7sus4"]
    swell = _pad([(0.0, dur + 0.2, m, 0.5) for m in sus[1]], dur + 1.6, "organ" if stage == "old" else "pad", 91, 0.5, 2, 8.0)
    ramp = np.linspace(0.25, 1.0, len(swell)) ** 1.5
    mx.add(swell * ramp, 0.0, 0.35 if stage != "middle" else 0.5)
    if stage != "old":
        mx.add(inst.bass(sus[0] - 12 if stage != "young" else sus[0], dur + 0.4, 0.55), 0.0, 0.5)
    # 滚奏是「轻」的：比上面的音低 7 dB（老年 9 dB），只给一个越来越紧的底
    r = roll(dur + 0.15, 110.0 if stage != "old" else 98.0, 300 + ORDER.index(stage), 15.0 if stage == "old" else 18.0)
    mx.add(r * db(lufs(mx.buf) - (9.0 if stage == "old" else 7.0) - lufs(r)), 0.0)
    y = _space(mx.buf, stage, 19, 0.04)
    # 给算盘珠让地方：1.4 kHz 往上整段压下去（六阶，到 2 kHz 已经掉 20 dB）
    y = lp(y, 1400, 6)
    if stage == "young":  # 只有青年有一点反向镲的气（全在 6 kHz 以上）
        n = sec(dur + 0.2)
        air = hp(white(n, rng), 6500, 4) * np.linspace(0, 1, n) ** 2.5 * db(-40)
        y[:n] += to_stereo(fade(air, 0.01, 0.15), 0.0)
    return _finish(y, dur + 0.45, 0.5, TARGET - 0.5)


# 第 13~16 小节的浓缩（拍）：青 3 5 6 —，梅 5' 3' 2' —，然后同时：青往上 2 3 5 6，梅往下 6' 5' 3' 2'，第 6 拍都落 1'
PASS_Q = [(0, .5, 3, 0), (.5, .5, 5, 0), (1, 1, 6, 0),
          (4, .5, 2, 0), (4.5, .5, 3, 0), (5, .5, 5, 0), (5.5, .5, 6, 0)]
PASS_M = [(2, .5, 5, 1), (2.5, .5, 3, 1), (3, 1, 2, 1),
          (4, .5, 6, 1), (4.5, .5, 5, 1), (5, .5, 3, 1), (5.5, .5, 2, 1)]
PASS_PROG = [(0, 2, "D"), (2, 2, "Bm7"), (4, 1, "Gmaj7"), (5, 1, "A7sus4")]
LAND = 6.0
# 名次档：落音之后青在高八度把「往上」再说一遍，落在更高的 1' 上
TOP_Q = [(7, .5, 3, 1), (7.5, .5, 5, 1), (8, .5, 6, 1), (8.5, 2.5, 1, 2)]


def reveal(stage: str, top: bool) -> np.ndarray:
    rng = rng_for(stage + ("_top" if top else "_pass"))
    bpm = BPM_PASS[stage]
    hold = 5.0 if top else 3.0
    ck = Clock(bpm, (0, 4))
    spb = ck.spb
    ring = (4.8 if top else 2.8) * spb + 0.6
    q_line = PASS_Q + [(LAND, hold, 1, 1)]
    m_line = PASS_M + [(LAND, hold + (1.5 if top else 0.0), 1, 1)]
    mx = Mix(ck.length + 3.0)
    mx.add(_q(stage, ck, q_line), 0.0, 1.0, PAN_Q)
    mx.add(_m(stage, ck, m_line), 0.0, 0.95, PAN_M)
    for b, beats, name in PASS_PROG:
        comp(stage, mx, ck.t(b), beats * spb, name, spb, 0.75, rng)
    bloom(stage, mx, ck.t(LAND), spb, 1.0 if top else 0.85, rng, full=top, ring=ring)
    if top:
        mx.add(_q(stage, ck, TOP_Q), 0.0, 0.7, -PAN_Q)  # 应答放在对面
        t_b = ck.t(8.5)
        for j, (m, v) in enumerate([(86, 0.55), (93, 0.4), (90, 0.3)]):  # D6 A6 F#6：铃的余晖
            mx.add(bell(m, v, 2.8 - 0.4 * j), t_b + j * 0.32 * spb * 2, 0.5, pan=0.35 - 0.35 * j)
    y = _space(mx.buf, stage, 23, 0.06 if top else 0.04)
    end = ck.t(8.5) + 2.4 if top else ck.t(LAND) + 1.8
    return _finish(y, end, 1.6 if top else 1.1)


# 差一点：青「小皮球」，梅「架脚——」停在 2 上；下属 G 接住，最后悬在 A7sus4
MISS_Q = [(0, .5, 3, 0), (.5, .5, 5, 0), (1, 1.5, 6, 0)]
MISS_M = [(2, .5, 5, 1), (2.5, .5, 3, 1), (3, 2.4, 2, 1)]


def miss(stage: str) -> np.ndarray:
    rng = rng_for(stage + "_miss")
    ck = Clock(BPM_MISS[stage], (0, 3))
    spb = ck.spb
    mx = Mix(ck.length + 3.0)
    mx.add(_q(stage, ck, MISS_Q), 0.0, 1.0, PAN_Q)
    mx.add(_m(stage, ck, MISS_M), 0.0, 0.9, PAN_M)
    comp(stage, mx, 0.0, 2 * spb, "D", spb, 0.55, rng)
    # 第 3 拍：低音轻轻垫一个 G（下属），把悬着的 2 接住；第 4 拍挪到 A7sus4，不解决
    g, a = CHORD["G"], CHORD["A7sus4"]
    t1, t2 = ck.t(3.0), ck.t(4.0)
    model = "organ" if stage == "old" else "pad"
    pad = _pad([(t1, t2 - t1 + 0.1, m, 0.55) for m in g[1]] + [(t2, 1.6 * spb, m, 0.5) for m in a[1]],
               ck.length + 2.0, model, 95, 0.5, 2, 8.0)
    mx.add(pad, 0.0, 0.4 if stage != "old" else 0.45)
    if stage == "old":
        mx.add(inst.sanxian(43, 1.2 * spb, 0.45), t1, 0.5)
        mx.add(inst.sanxian(45, 1.8 * spb, 0.4), t2, 0.45)
    elif stage == "middle":
        mx.add(inst.piano(43, 1.6 * spb, 0.42), t1, 1.0, pan=-0.15)
        mx.add(inst.piano(45, 2.4 * spb, 0.38), t2, 1.0, pan=-0.15)
    else:
        mx.add(inst.bass(43, 1.4 * spb, 0.55), t1, 0.55)
        mx.add(inst.bass(45, 2.2 * spb, 0.5), t2, 0.5)
    if stage in ("child", "teen", "young"):  # 伴奏乐器在 sus 上轻轻点一下 D（四度那个音），不往 C# 走
        note = {"child": inst.kalimba(74, 1.0, 0.4), "teen": inst.guitar(74, 1.6, 0.4, True),
                "young": inst.epiano(74, 1.4, 0.38)}[stage]
        mx.add(note, t2 + 0.5 * spb, 0.45 if stage != "teen" else 0.9, pan=0.2)
    y = _space(mx.buf, stage, 29, 0.06)
    return _finish(y, ck.t(5.4) + 0.75, 0.9)


# ------------------------------------------------------------ 长大 ----

GROW_Q = [(0, .75, 3, 0), (.75, .75, 5, 0), (1.5, 1.5, 6, 0)]       # 上一阶段：小皮球——
GROW_M = [(3.5, .75, 5, 1), (4.25, .75, 3, 1), (5, 2, 2, 1)]        # 新阶段：架脚踢——
GROW_LAND = 7.0                                                     # 落在 1'


def grow(prev: str, new: str) -> np.ndarray:
    rng = rng_for("grow_" + new)
    bpm = BPM_GROW[new]
    ck = Clock(bpm, (0, 4))
    spb = ck.spb
    # 上一页：旧阶段的青说半句，旧伴奏在下面托一个 D，然后让开
    a = Mix(ck.length + 3.0)
    a.add(_q(prev, ck, GROW_Q), 0.0, 1.0, PAN_Q)
    comp(prev, a, 0.0, 3.0 * spb, "D", spb, 0.6, rng)
    a_buf = _space(a.buf, prev, 31, 0.05)
    # 新的一页：新阶段的梅接后半句并落在 1' 上，青在落音上应一下，伴奏在最后一小节进来
    b = Mix(ck.length + 3.0)
    m_line = GROW_M + [(GROW_LAND, 3.5, 1, 1)]
    b.add(_m(new, ck, m_line), 0.0, 1.0, PAN_M)
    b.add(_q(new, ck, [(GROW_LAND, 3.0, 1, 0), (GROW_LAND + 1.5, 2.0, 5, 0)]), 0.0, 0.7, PAN_Q)
    # 旧和新之间垫一个很轻的 Bm7 → A7sus4，不然中间空着像断了
    model = "organ" if new == "old" else "pad"
    mid = _pad([(ck.t(3.5), 1.5 * spb, m, 0.4) for m in CHORD["Bm7"][1]] +
               [(ck.t(5.0), 2.0 * spb, m, 0.4) for m in CHORD["A7sus4"][1]], ck.length + 2.0, model, 33, 0.5, 2, 8.0)
    b.add(mid, 0.0, 0.22)
    t_land = ck.t(GROW_LAND)
    comp(new, b, t_land, 4.0 * spb, "Dadd9", spb, 0.8, rng)
    bloom(new, b, t_land, spb, 0.6, rng, full=False, ring=4.0 * spb)
    b_buf = _space(b.buf, new, 37, 0.05)
    n = max(len(a_buf), len(b_buf))
    y = np.zeros((n, 2))
    y[:len(a_buf)] += a_buf
    y[:len(b_buf)] += b_buf
    return _finish(y, t_land + 3.4 * spb + 0.5, 1.3)
