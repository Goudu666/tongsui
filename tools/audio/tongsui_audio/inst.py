"""《同岁》的乐器。全部是合成的，没有采样。

两个家族，对应两位玩家：
  拨（青）：八音盒 → 木吉他 → 电吉他 → 钢琴 → 三弦      一下一下的，有头没尾
  吟（梅）：竖笛   → 口琴   → 合成主音 → 大提琴 → 二胡   连着的，有气息

拨的乐器按「每个泛音各自衰减」做加法合成；吟的乐器先画一条连续的音高曲线
（带滑音和揉弦），再让每个泛音穿过共鸣峰，所以揉弦时音色会跟着动。
"""
from __future__ import annotations

from functools import lru_cache

import numpy as np

from .dsp import (SR, TAU, adsr, bp, cents, colored, fade, hp, lfo_noise, lp, midi, modal, peak, reson, rng_for,
                  sec, softclip, times, white)


# ============================================================ 拨：加法 ====

def _partials(freq: float, n: int, amps, taus, inharm: float = 0.0, detune: float = 0.0, seed: int = 0):
    tt = times(n)
    out = np.zeros(n)
    rng = np.random.default_rng(seed)
    for k, (a, tau) in enumerate(zip(amps, taus), start=1):
        fk = freq * k * np.sqrt(1.0 + inharm * k * k) * (1.0 + detune * rng.uniform(-1, 1))
        if fk > SR * 0.45 or a == 0:
            continue
        out += a * np.exp(-tt / tau) * np.sin(TAU * fk * tt + rng.uniform(0, TAU) * (k > 1))
    return out


def _string(freq, dur, vel, *, pluck_pos, tau0, tau_slope, n_harm, bright, inharm, release, seed, damp=0.06):
    """拨弦：泛音初始幅度由拨弦位置决定，越高的泛音掉得越快；松手后整体快速收掉。"""
    n = sec(dur + release)
    k = np.arange(1, n_harm + 1)
    amps = np.abs(np.sin(k * np.pi * pluck_pos)) / k ** (1.0 + (1.0 - bright) * 0.9 + (1 - vel) * 0.5)
    taus = tau0 / (1.0 + (k * freq / tau_slope) ** 1.15)
    y = _partials(freq, n, amps, taus, inharm, 0.0004, seed)
    hold = sec(dur)
    if hold < n:
        y[hold:] *= np.exp(-np.arange(n - hold) / (SR * damp))
    return y


@lru_cache(maxsize=4096)
def music_box(m: float, dur: float, vel: float = 0.8) -> np.ndarray:
    """八音盒：梳齿几乎是纯音，上面一点很高很短的非谐波泛音，像玻璃。"""
    f = midi(m)
    n = sec(max(dur, 0.2) + 1.6)
    tau = 1.5 * (523.0 / f) ** 0.45
    y = modal(n, [f, 2.0 * f, 3.01 * f, 6.27 * f, 9.1 * f], [tau, tau * 0.45, tau * 0.25, 0.06, 0.03],
              [1.0, 0.16, 0.05, 0.14 * vel, 0.06 * vel])
    rng = np.random.default_rng(int(m * 100))
    k = sec(0.004)
    y[:k] += hp(white(k, rng), 3000) * np.linspace(1, 0, k) * 0.12 * vel
    y = reson(y, 420, 2.0, 0.25) + y  # 木盒子的一点共鸣
    return fade(y * vel, 0.0005, 0.05)


@lru_cache(maxsize=4096)
def kalimba(m: float, dur: float, vel: float = 0.8) -> np.ndarray:
    """拇指琴 / 木琴一类的软木头音，童年的伴奏。"""
    f = midi(m)
    n = sec(max(dur, 0.15) + 0.9)
    tau = 0.55 * (330.0 / f) ** 0.4
    y = modal(n, [f, 3.92 * f, 9.2 * f, 2.0 * f], [tau, 0.07, 0.025, tau * 0.5], [1.0, 0.22 * vel, 0.08 * vel, 0.08])
    rng = np.random.default_rng(int(m * 100) + 1)
    k = sec(0.012)
    y[:k] += lp(white(k, rng), 900) * np.linspace(1, 0, k) ** 2 * 0.5 * vel
    return fade(y * vel, 0.001, 0.04)


@lru_cache(maxsize=4096)
def guitar(m: float, dur: float, vel: float = 0.8, nylon: bool = False) -> np.ndarray:
    """木吉他。nylon=True 更闷更圆，用来做分解和弦的伴奏。"""
    f = midi(m)
    y = _string(f, dur, vel, pluck_pos=0.22 if nylon else 0.14, tau0=2.6 if nylon else 3.2,
                tau_slope=1500 if nylon else 2600, n_harm=18 if nylon else 28, bright=0.35 if nylon else 0.7,
                inharm=0.00008, release=0.35, seed=int(m * 10))
    rng = np.random.default_rng(int(m * 100) + 2)
    k = sec(0.008)
    y[:k] += bp(white(k, rng), 800, 5000) * np.linspace(1, 0, k) * 0.25 * vel  # 指甲碰弦
    y = y + reson(y, 105, 6, 0.5) + reson(y, 215, 5, 0.35) + reson(y, 410, 4, 0.2)  # 琴箱
    return fade(y * vel * 0.6, 0.001, 0.05)


@lru_cache(maxsize=4096)
def egtr(m: float, dur: float, vel: float = 0.8) -> np.ndarray:
    """清音电吉他：延音长，拾音器位置带来的梳状感，两路微微失谐当合唱。"""
    f = midi(m)
    a = _string(f, dur, vel, pluck_pos=0.2, tau0=4.5, tau_slope=3200, n_harm=22, bright=0.55, inharm=0.00005,
                release=0.5, seed=int(m * 10) + 5, damp=0.12)
    b = _string(f * cents(7), dur, vel, pluck_pos=0.2, tau0=4.5, tau_slope=3200, n_harm=22, bright=0.55,
                inharm=0.00005, release=0.5, seed=int(m * 10) + 6, damp=0.12)
    y = peak(a + 0.6 * b, 2400, 1.2, 4.0)
    return fade(lp(y, 5200) * vel * 0.5, 0.002, 0.06)


@lru_cache(maxsize=4096)
def piano(m: float, dur: float, vel: float = 0.7) -> np.ndarray:
    """蒙了毛毡的立式钢琴：软，带一点琴槌的闷响，三根弦微微不齐。"""
    f = midi(m)
    n_h = 26 if m < 60 else 16
    k = np.arange(1, n_h + 1)
    hammer = np.abs(np.sin(k * np.pi / 8.5)) + 0.08
    amps = hammer / k ** (1.25 + (1 - vel) * 0.9)
    tau0 = 4.2 * (261.0 / f) ** 0.55
    taus = tau0 / k ** 0.85
    n = sec(dur + 0.6)
    b_inh = 0.00035 * (f / 261.0) ** 1.2
    y = np.zeros(n)
    for i, det in enumerate([-1.1, 0.0, 1.3]):
        y += _partials(f * cents(det), n, amps, taus, b_inh, 0.0, int(m * 10) + i)
    # 两段衰减：前快后慢
    tt = times(n)
    y *= 0.55 + 0.45 * np.exp(-tt / 0.35)
    hold = sec(dur)
    if hold < n:
        y[hold:] *= np.exp(-np.arange(n - hold) / (SR * 0.11))
    rng = np.random.default_rng(int(m * 100) + 3)
    kn = sec(0.03)
    y[:kn] += lp(white(kn, rng), 500) * np.linspace(1, 0, kn) ** 2 * 0.35 * vel
    y = lp(y, 1500 + 3000 * vel)
    return fade(y * vel * 0.28, 0.002, 0.08)


@lru_cache(maxsize=4096)
def epiano(m: float, dur: float, vel: float = 0.7) -> np.ndarray:
    """电钢琴（音叉式）：两算子调频，敲下去亮一下再变圆，带一点金属的「叮」。"""
    f = midi(m)
    n = sec(dur + 0.7)
    tt = times(n)
    idx = (1.6 * vel + 0.25) * np.exp(-tt / 0.28) + 0.22
    body = np.sin(TAU * f * tt + idx * np.sin(TAU * f * tt))
    tine = 0.10 * vel * np.exp(-tt / 0.05) * np.sin(TAU * f * 14.0 * tt + 0.6 * np.sin(TAU * f * tt))
    y = (body + tine) * np.exp(-tt / (2.6 * (261.0 / f) ** 0.4))
    hold = sec(dur)
    if hold < n:
        y[hold:] *= np.exp(-np.arange(n - hold) / (SR * 0.14))
    return fade(lp(y, 4200) * vel * 0.4, 0.003, 0.08)


@lru_cache(maxsize=4096)
def sanxian(m: float, dur: float, vel: float = 0.8, slide: float = 0.0) -> np.ndarray:
    """三弦：蟒皮蒙的鼓面，头子硬、收得快、带鼻音；slide 是起音时从下面滑上来的半音数。"""
    f = midi(m)
    n = sec(dur + 0.4)
    tt = times(n)
    k = np.arange(1, 25)
    amps = np.abs(np.sin(k * np.pi * 0.09)) / k ** 0.85
    taus = (1.25 * (196.0 / f) ** 0.3) / (1.0 + (k * f / 1700.0) ** 1.3)
    if slide != 0.0:
        bend = cents(-100.0 * slide * np.exp(-tt / 0.07))
    else:
        bend = cents(18.0 * np.exp(-tt / 0.02))  # 弦刚拨开时音高略高
    ph = TAU * np.cumsum(f * bend) / SR
    y = np.zeros(n)
    rng = np.random.default_rng(int(m * 10) + 9)
    for kk, a, tau in zip(k, amps, taus):
        if f * kk > SR * 0.45:
            break
        y += a * np.exp(-tt / tau) * np.sin(kk * ph + rng.uniform(0, TAU))
    kn = sec(0.006)
    y[:kn] += bp(white(kn, rng), 1200, 6000) * np.linspace(1, 0, kn) * 0.6 * vel  # 指甲
    y = y + reson(y, 760, 3.5, 0.9) + reson(y, 1850, 4.0, 0.55) + reson(y, 290, 5.0, 0.4)  # 皮面
    hold = sec(dur)
    if hold < n:
        y[hold:] *= np.exp(-np.arange(n - hold) / (SR * 0.05))
    return fade(y * vel * 0.33, 0.0008, 0.05)


@lru_cache(maxsize=4096)
def bass(m: float, dur: float, vel: float = 0.7, soft: bool = True) -> np.ndarray:
    f = midi(m)
    y = _string(f, dur, vel, pluck_pos=0.3, tau0=2.2, tau_slope=500 if soft else 900, n_harm=10, bright=0.2,
                inharm=0.0, release=0.2, seed=int(m * 10) + 4)
    return fade(lp(y, 700 if soft else 1400) * vel * 0.8, 0.004, 0.05)


# ============================================================ 吟：连音 ====

def _spectral_env(formants, tilt_db_oct: float, cutoff: float):
    """共鸣峰曲线：返回一个函数 gain(freq)，用对数频率网格查表。"""
    grid = np.geomspace(40.0, SR / 2, 512)
    g = np.zeros_like(grid)
    for fc, width_oct, gdb in formants:
        g += gdb * np.exp(-0.5 * (np.log2(grid / fc) / width_oct) ** 2)
    g += tilt_db_oct * np.log2(grid / 200.0)
    g -= 24.0 * np.clip(np.log2(grid / cutoff), 0, None)
    lin = 10 ** (g / 20.0)
    lg = np.log(grid)
    return lambda fr: np.interp(np.log(np.maximum(fr, 40.0)), lg, lin)


MODELS = {
    # name: 共鸣峰 (Hz, 宽度/倍频程, dB)，频谱倾斜，高切，泛音数，奇偶比，气息噪声，起音，收音，揉弦(Hz, 音分, 延迟)，滑音秒
    "recorder": dict(formants=[(900, 1.2, 3)], tilt=-13.0, cutoff=5000, harm=8, even=0.35, breath=0.045,
                     attack=0.035, release=0.07, vib=(4.6, 5.0, 0.35), glide=0.012, drift=5.0),
    "harmonica": dict(formants=[(1500, 0.7, 8), (2800, 0.5, 6), (600, 0.8, 3)], tilt=-5.0, cutoff=6500, harm=26,
                      even=0.9, breath=0.02, attack=0.045, release=0.09, vib=(5.2, 6.0, 0.3), glide=0.02, drift=3.0),
    "lead": dict(formants=[(1100, 1.0, 4)], tilt=-10.0, cutoff=4200, harm=10, even=0.25, breath=0.006,
                 attack=0.03, release=0.12, vib=(5.4, 14.0, 0.28), glide=0.05, drift=1.5),
    "cello": dict(formants=[(250, 0.6, 6), (480, 0.5, 5), (1500, 0.6, 5), (2600, 0.5, 2)], tilt=-7.5, cutoff=4500,
                  harm=30, even=0.95, breath=0.012, attack=0.11, release=0.16, vib=(5.0, 16.0, 0.3), glide=0.06,
                  drift=2.0),
    "erhu": dict(formants=[(520, 0.5, 4), (1150, 0.45, 10), (2100, 0.4, 5), (3100, 0.45, 7)], tilt=-6.0, cutoff=7000,
                 harm=32, even=0.9, breath=0.02, attack=0.07, release=0.12, vib=(5.8, 26.0, 0.22), glide=0.085,
                 drift=3.0),
    "pad": dict(formants=[(500, 1.2, 3)], tilt=-12.0, cutoff=2600, harm=12, even=0.7, breath=0.0,
                attack=0.5, release=0.9, vib=(4.2, 4.0, 0.6), glide=0.03, drift=4.0),
    "organ": dict(formants=[(700, 1.0, 4), (1800, 0.8, 2)], tilt=-8.0, cutoff=3200, harm=14, even=0.5, breath=0.01,
                  attack=0.3, release=0.6, vib=(0.0, 0.0, 1.0), glide=0.01, drift=6.0),
}


def sustained_line(notes, total: float, model: str, seed: int = 1, level: float = 0.5, glide_scale: float = 1.0):
    """把一串音（start_sec, dur_sec, midi, vel）渲染成一条连着的旋律线。

    相邻两个音之间如果没有空隙，音高曲线会滑过去（二胡的滑音、口琴的连吹），
    每个音各有一个小的音量包络，所以换音时听得出「换弓」。
    """
    p = MODELS[model]
    n = sec(total)
    rng = np.random.default_rng(seed)
    logf = np.zeros(n)
    amp = np.zeros(n)
    vib_depth = np.zeros(n)
    filled = np.zeros(n, dtype=bool)
    notes = sorted(notes)
    for i, (st, du, m, vel) in enumerate(notes):
        a, b = sec(st), min(n, sec(st + du + p["release"]))
        if a >= n:
            continue
        hold = min(n, sec(st + du)) - a
        env = adsr(hold, p["attack"] * (1.3 - 0.5 * vel), 0.25, 0.82, p["release"])[: b - a]
        b = a + len(env)
        # 每个音里一点气息 / 弓压的起伏
        env = env * (1.0 + 0.07 * lfo_noise(len(env), 3.0, rng))
        amp[a:b] = np.maximum(amp[a:b], env * vel)
        end = min(n, sec(st + du) + sec(0.02))
        logf[a:end] = np.log(midi(m))
        filled[a:end] = True
        rate, depth, delay = p["vib"]
        if depth > 0 and du > delay + 0.12:
            k = hold - sec(delay)
            vib_depth[a + sec(delay):a + hold] = depth * np.minimum(1.0, np.arange(k) / (SR * 0.25))
    if not filled.any():
        return np.zeros(n)
    # 没有音的地方沿用最近的音高，避免滑音从 0 滑上来
    idx = np.where(filled, np.arange(n), 0)
    np.maximum.accumulate(idx, out=idx)
    first = np.argmax(filled)
    logf = logf[idx]
    logf[:first] = logf[first]
    g = max(8, sec(p["glide"] * glide_scale))
    kernel = np.hanning(g * 2 + 1)
    kernel /= kernel.sum()
    logf = np.convolve(np.pad(logf, g, mode="edge"), kernel, mode="valid")
    vib_depth = np.convolve(np.pad(vib_depth, 600, mode="edge"), np.ones(1201) / 1201, mode="valid")
    tt = times(n)
    rate = p["vib"][0] * (1.0 + 0.06 * lfo_noise(n, 0.7, rng))
    vib = np.sin(TAU * np.cumsum(rate) / SR) * vib_depth
    drift = p["drift"] * lfo_noise(n, 1.5, rng)
    freq = np.exp(logf) * cents(vib + drift)
    phase = TAU * np.cumsum(freq) / SR
    gain = _spectral_env(p["formants"], p["tilt"], p["cutoff"])
    out = np.zeros(n)
    bright = 0.6 + 0.4 * np.clip(amp, 0, 1)  # 用力时亮一点
    for k in range(1, p["harm"] + 1):
        fk = freq * k
        a_k = gain(fk) * (1.0 if k % 2 == 1 else p["even"]) * np.where(fk < SR * 0.45, 1.0, 0.0)
        if k > 3:
            a_k = a_k * bright ** (k / 6.0)
        out += a_k * np.sin(k * phase + rng.uniform(0, TAU))
    out /= max(1e-9, np.sqrt(np.mean(out[amp > 0.05] ** 2)) if (amp > 0.05).any() else 1.0)
    if p["breath"] > 0:
        air = bp(white(n, rng), 1200, 7000) * p["breath"] * 1.6
        air *= 0.6 + 0.4 * np.abs(lfo_noise(n, 9.0, rng))
        out += air
    return out * amp * level * 0.25


def harmonica_line(notes, total: float, seed: int = 1, level: float = 0.5):
    """复音口琴：两排簧片差几个音分，自己就会颤。"""
    a = sustained_line(notes, total, "harmonica", seed, level)
    shifted = [(st, du, m + 0.11, vel) for st, du, m, vel in notes]
    b = sustained_line(shifted, total, "harmonica", seed + 1, level)
    return 0.6 * a + 0.5 * b


def ensemble_line(notes, total: float, model: str, seed: int = 1, level: float = 0.5, voices: int = 3, spread: float = 9.0):
    out = np.zeros(sec(total))
    for v in range(voices):
        det = (v - (voices - 1) / 2) * spread / 100.0
        out += sustained_line([(st, du, m + det, vel) for st, du, m, vel in notes], total, model, seed + v * 13, level)
    return out / np.sqrt(voices)


# ============================================================ 打击 ====

def kick(vel: float = 0.8) -> np.ndarray:
    n = sec(0.28)
    tt = times(n)
    f = 46 + 70 * np.exp(-tt / 0.035)
    y = np.sin(TAU * np.cumsum(f) / SR) * np.exp(-tt / 0.11)
    return fade(lp(y, 900) * vel, 0.001, 0.03)


def rim(vel: float = 0.6, seed: int = 0) -> np.ndarray:
    rng = np.random.default_rng(seed)
    y = modal(sec(0.09), [1720, 2480, 760], [0.018, 0.012, 0.03], [1.0, 0.5, 0.4], rng, 0.0015)
    return y * vel * 0.5


def hat(vel: float = 0.4, seed: int = 0, open_: bool = False) -> np.ndarray:
    rng = np.random.default_rng(100 + seed)
    n = sec(0.22 if open_ else 0.06)
    y = hp(white(n, rng), 7000, 3) * np.exp(-times(n) / (0.07 if open_ else 0.014))
    return fade(y * vel * 0.25, 0.0005, 0.005)


def shaker(vel: float = 0.4, seed: int = 0) -> np.ndarray:
    rng = np.random.default_rng(200 + seed)
    n = sec(0.09)
    env = np.sin(np.pi * np.arange(n) / n) ** 2 * np.exp(-times(n) / 0.04)
    return bp(white(n, rng), 3500, 9000) * env * vel * 0.3


def woodblock(vel: float = 0.6, pitch: float = 1.0, seed: int = 0) -> np.ndarray:
    rng = np.random.default_rng(300 + seed)
    return modal(sec(0.12), [880 * pitch, 1420 * pitch, 2650 * pitch], [0.03, 0.02, 0.008], [1.0, 0.55, 0.25], rng, 0.001) * vel * 0.5


def triangle(vel: float = 0.4) -> np.ndarray:
    return modal(sec(1.6), [4180, 5630, 7910, 10240], [0.7, 0.5, 0.35, 0.2], [1.0, 0.7, 0.5, 0.3]) * vel * 0.12


def clapper(big: bool, vel: float = 0.8, seed: int = 0) -> np.ndarray:
    """快板。big=大板（两片厚竹，「呱」），否则是节子（五片小竹，「嘀」，有一点散）。"""
    rng = np.random.default_rng(400 + seed)
    if big:
        y = modal(sec(0.12), [1120, 1710, 2580, 3900, 520], [0.022, 0.016, 0.011, 0.007, 0.03],
                  [1.0, 0.8, 0.5, 0.3, 0.3], rng, 0.0015)
        return y * vel * 0.7
    y = np.zeros(sec(0.1))
    for j in range(3):  # 几片小板先后碰上
        at = sec(rng.uniform(0, 0.007) * j)
        p = modal(sec(0.06), [2350 * rng.uniform(0.95, 1.05), 3480, 5150], [0.012, 0.009, 0.006], [1.0, 0.6, 0.35], rng, 0.001)
        y[at:at + len(p)] += p[: len(y) - at] * (0.9 ** j)
    return y * vel * 0.38
