"""《同岁》的乐器。全部是合成的，没有采样。

两个家族，对应两位玩家：
  拨（青）：八音盒 → 木吉他 → 电吉他 → 钢琴 → 颤音琴      一下一下的，有头没尾
  吟（梅）：竖笛   → 口琴   → 合成主音 → 大提琴 → 单簧管    连着的，有气息
（11-12 起老年不再用三弦、二胡：用户不要水墨 / 国风的意境。sanxian 和 erhu 留着，二胡只在街上的环境音里。）

拨的乐器按「每个泛音各自衰减」做加法合成；吟的乐器先画一条连续的音高曲线
（带滑音和揉弦），再让每个泛音穿过共鸣峰，所以揉弦时音色会跟着动。
"""
from __future__ import annotations

from functools import lru_cache

import numpy as np

from .dsp import (SR, TAU, adsr, bp, cents, colored, fade, hp, lfo_noise, lp, midi, modal, peak, reson, rng_for,
                  sec, shelf, softclip, times, white)


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


def music_box_hit(m: float, vel: float = 0.6) -> np.ndarray:
    """早上那一层用的八音盒（老年）：童年的那只，隔了几十年又响了。"""
    return music_box(m, 0.6, vel) * 0.8


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
    y = _string(f, dur, vel, pluck_pos=0.22 if nylon else 0.15, tau0=2.6 if nylon else 3.2,
                tau_slope=1500 if nylon else 2200, n_harm=18 if nylon else 26, bright=0.35 if nylon else 0.6,
                inharm=0.00008, release=0.35, seed=int(m * 10))
    rng = np.random.default_rng(int(m * 100) + 2)
    k = sec(0.008)
    y[:k] += bp(white(k, rng), 800, 4000) * np.linspace(1, 0, k) * 0.16 * vel  # 指甲碰弦（轻一点，不扎）
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
    y = lp(y, 1800 + 3200 * vel)  # 毛毡软，但别闷在被子里
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
    y[:kn] += bp(white(kn, rng), 1000, 4500) * np.linspace(1, 0, kn) * 0.4 * vel  # 指甲
    y = y + reson(y, 760, 3.5, 0.9) + reson(y, 1850, 4.0, 0.4) + reson(y, 290, 5.0, 0.4)  # 皮面
    y = shelf(y, 2800, -4.0)  # 2~6 kHz 那一截太冲，按下去一点
    hold = sec(dur)
    if hold < n:
        y[hold:] *= np.exp(-np.arange(n - hold) / (SR * 0.05))
    return fade(y * vel * 0.33, 0.0008, 0.05)


@lru_cache(maxsize=4096)
def vibes(m: float, dur: float, vel: float = 0.7) -> np.ndarray:
    """颤音琴（老年）：软槌敲铝条。铝条的泛音是 1 : 4 : 10，底下的共鸣管只放大基音，
    电机转着让共鸣管一开一合，余音里有慢慢的「哇——哇——」。松踏板就收掉。"""
    f = midi(m)
    n = sec(dur + 1.2)
    tt = times(n)
    tau = 2.8 * (440.0 / f) ** 0.35
    y = modal(n, [f, 4.0 * f, 10.0 * f], [tau, tau * 0.18, 0.05], [1.0, 0.11 * vel, 0.025 * vel])
    trem = 1.0 - 0.26 * (0.5 + 0.5 * np.sin(TAU * 4.6 * tt + m))  # 电机，只作用在共鸣管放大的那部分
    y = y * (0.55 + 0.45 * trem)
    rng = np.random.default_rng(int(m * 100) + 15)
    k = sec(0.01)
    y[:k] += lp(white(k, rng), 1400) * np.linspace(1, 0, k) ** 2 * 0.12 * vel  # 毛线槌
    hold = sec(dur)
    if hold < n:
        y[hold:] *= np.exp(-np.arange(n - hold) / (SR * 0.25))
    return fade(lp(y, 6000) * vel * 0.42, 0.001, 0.08)


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
    # 可选：air 气声的频带（默认 1200~7000），chiff 吐音那一下气声多冒多少（默认 0，不冒）
    "recorder": dict(formants=[(900, 1.2, 3)], tilt=-13.0, cutoff=5000, harm=8, even=0.35, breath=0.026,
                     air=(900, 5000), chiff=1.6, attack=0.035, release=0.07, vib=(4.6, 5.0, 0.35), glide=0.012,
                     drift=5.0),
    "harmonica": dict(formants=[(1400, 0.7, 7), (2700, 0.5, 2.5), (600, 0.8, 4)], tilt=-6.5, cutoff=5200, harm=24,
                      even=0.9, breath=0.012, air=(900, 4500), chiff=0.8, attack=0.045, release=0.09,
                      vib=(5.2, 6.0, 0.3), glide=0.02, drift=3.0),
    "lead": dict(formants=[(1100, 1.0, 4)], tilt=-10.5, cutoff=3800, harm=10, even=0.25, breath=0.006,
                 attack=0.03, release=0.12, vib=(5.4, 14.0, 0.28), glide=0.05, drift=1.5),
    "cello": dict(formants=[(250, 0.6, 4), (480, 0.5, 4), (1500, 0.6, 5.5), (2600, 0.5, 2)], tilt=-7.5, cutoff=4500,
                  harm=30, even=0.95, breath=0.012, attack=0.11, release=0.16, vib=(5.0, 16.0, 0.3), glide=0.06,
                  drift=2.0),
    "erhu": dict(formants=[(520, 0.5, 4), (1150, 0.45, 10), (2100, 0.4, 4), (3100, 0.45, 3.0)], tilt=-7.5,
                 cutoff=6000, harm=32, even=0.9, breath=0.016, air=(800, 4500), attack=0.07, release=0.12,
                 vib=(5.8, 26.0, 0.22), glide=0.085, drift=3.0),
    "pad": dict(formants=[(500, 1.2, 3)], tilt=-12.0, cutoff=2600, harm=12, even=0.7, breath=0.0,
                attack=0.5, release=0.9, vib=(4.2, 4.0, 0.6), glide=0.03, drift=4.0),
    "organ": dict(formants=[(700, 1.0, 4), (1800, 0.8, 2)], tilt=-8.0, cutoff=3200, harm=14, even=0.5, breath=0.01,
                  attack=0.3, release=0.6, vib=(0.0, 0.0, 1.0), glide=0.01, drift=6.0),
    # ---- 傍晚那一层（eve）用的：暖、低、长 ----
    "ocarina": dict(formants=[(700, 1.0, 2)], tilt=-20.0, cutoff=3000, harm=5, even=0.15, breath=0.008,
                    air=(600, 3000), chiff=0.8, attack=0.07, release=0.18, vib=(4.8, 7.0, 0.4), glide=0.03, drift=3.0),
    "xiao": dict(formants=[(800, 0.9, 3), (1600, 0.7, 1)], tilt=-15.0, cutoff=3500, harm=8, even=0.3, breath=0.022,
                 air=(500, 3200), chiff=0.6, attack=0.13, release=0.28, vib=(4.5, 10.0, 0.45), glide=0.08, drift=4.0),
    "xun": dict(formants=[(450, 0.8, 3)], tilt=-17.0, cutoff=2400, harm=7, even=0.12, breath=0.022,
                air=(400, 2500), chiff=0.5, attack=0.16, release=0.32, vib=(4.0, 8.0, 0.5), glide=0.06, drift=5.0),
    "viola": dict(formants=[(380, 0.6, 5), (800, 0.5, 3), (1700, 0.6, 2.5)], tilt=-9.0, cutoff=3800, harm=24,
                  even=0.95, breath=0.006, attack=0.2, release=0.32, vib=(5.0, 13.0, 0.35), glide=0.07, drift=2.0),
    "strings": dict(formants=[(300, 0.8, 3), (1000, 0.8, 2)], tilt=-11.0, cutoff=2200, harm=20, even=0.9,
                    breath=0.0, attack=0.8, release=1.3, vib=(5.0, 7.0, 0.6), glide=0.1, drift=3.0),
    "warm": dict(formants=[(420, 1.0, 2)], tilt=-10.0, cutoff=1600, harm=18, even=0.8, breath=0.0,
                 attack=0.9, release=1.4, vib=(0.0, 0.0, 1.0), glide=0.05, drift=5.0),
    "glass": dict(formants=[(1500, 1.5, 0)], tilt=-24.0, cutoff=4000, harm=3, even=0.4, breath=0.0,
                  attack=1.2, release=1.6, vib=(0.0, 0.0, 1.0), glide=0.05, drift=2.0),
    # ---- 11-12 换掉国风之后加的 ----
    # 单簧管（老年的梅）：闭管，奇次泛音为主，低音区又暗又圆；几乎不揉音
    "clarinet": dict(formants=[(380, 0.7, 3), (1500, 0.6, 4), (2900, 0.5, 1.5)], tilt=-9.5, cutoff=4200, harm=22,
                     even=0.18, breath=0.012, air=(700, 4200), chiff=0.5, attack=0.06, release=0.12,
                     vib=(4.6, 3.5, 0.5), glide=0.03, drift=2.0),
    # 柔音号（老年傍晚）：铜管里最软的，像远处有人在阳台上吹
    "flugel": dict(formants=[(560, 0.8, 4), (1150, 0.7, 3), (2300, 0.6, 0.5)], tilt=-12.5, cutoff=3000, harm=16,
                   even=0.9, breath=0.01, air=(600, 3200), chiff=0.4, attack=0.07, release=0.2, vib=(5.0, 9.0, 0.4),
                   glide=0.035, drift=2.5),
    # 芯片主旋律（青年的梅）：25% 脉冲波，连着吹时音高快速滑过去，揉音晚进来
    "pulse": dict(formants=[(900, 1.2, 2)], tilt=-8.0, cutoff=2500, harm=24, even=1.0, duty=0.25, breath=0.0,
                  attack=0.006, release=0.06, vib=(5.6, 11.0, 0.3), glide=0.01, drift=1.0),
    # 口风琴（少年傍晚）：音乐课上那种，簧片的鼻音，不揉音
    "melodica": dict(formants=[(1250, 0.8, 4), (500, 0.9, 2)], tilt=-10.5, cutoff=3600, harm=20,
                     even=0.75, breath=0.01, air=(900, 4000), chiff=0.6, attack=0.035, release=0.08,
                     vib=(0.0, 0.0, 1.0), glide=0.015, drift=3.0),
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
        if "duty" in p:  # 脉冲波：谐波按占空比挖掉一些（芯片主旋律）
            a_k = a_k * float(_pulse_amps(np.array([k]), p["duty"])[0])
        if k > 3:
            a_k = a_k * bright ** (k / 6.0)
        out += a_k * np.sin(k * phase + rng.uniform(0, TAU))
    out /= max(1e-9, np.sqrt(np.mean(out[amp > 0.05] ** 2)) if (amp > 0.05).any() else 1.0)
    if p["breath"] > 0:
        lo, hi = p.get("air", (1200, 7000))
        air = bp(white(n, rng), lo, hi) * p["breath"] * 1.6
        air *= 0.6 + 0.4 * np.abs(lfo_noise(n, 9.0, rng))
        if p.get("chiff", 0) > 0:  # 气声主要在吐音那一下，拉长了就淡下去（真吹的时候也是这样）
            on = np.zeros(n)
            for st, du, m, vel in notes:
                a = sec(st)
                if 0 <= a < n:
                    k = min(n - a, sec(0.18))
                    on[a:a + k] = np.maximum(on[a:a + k], np.exp(-np.arange(k) / (SR * 0.045)))
            air *= 0.55 + p["chiff"] * on
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


# ============================================================ 早上那一层（morn）：亮、稀、高 ====
# 都是一下一下的高音点。2~6 kHz 是耳朵最敏感的地方，所以高的泛音都压得很低，亮靠基音的音区，不靠刺。

@lru_cache(maxsize=1024)
def glock(m: float, vel: float = 0.6) -> np.ndarray:
    """玩具钟琴：软槌敲小钢条。钢条的泛音是 2.76、5.4 倍，不和谐，所以压得很轻。"""
    f = midi(m)
    n = sec(2.0)
    tau = 1.1 * (1000.0 / f) ** 0.3
    y = modal(n, [f, 2.76 * f, 5.40 * f], [tau, 0.22, 0.06], [1.0, 0.08 * vel, 0.02 * vel])
    rng = np.random.default_rng(int(m * 100) + 11)
    k = sec(0.006)
    y[:k] += lp(white(k, rng), 2500) * np.linspace(1, 0, k) * 0.1 * vel  # 槌头是软的
    return fade(lp(y, 6000) * vel * 0.5, 0.0008, 0.06)


@lru_cache(maxsize=1024)
def harmonic(m: float, vel: float = 0.6) -> np.ndarray:
    """吉他的泛音：手指轻点十二品，几乎是一个纯音，挂得很久。"""
    f = midi(m)
    n = sec(3.0)
    y = modal(n, [f, 2.0 * f, 3.0 * f], [1.7 * (660.0 / f) ** 0.3, 0.5, 0.15], [1.0, 0.07, 0.015])
    rng = np.random.default_rng(int(m * 100) + 12)
    k = sec(0.01)
    y[:k] += lp(white(k, rng), 1800) * np.linspace(1, 0, k) ** 2 * 0.06 * vel
    return fade(y * vel * 0.5, 0.004, 0.08)


@lru_cache(maxsize=1024)
def fm_bell(m: float, vel: float = 0.6) -> np.ndarray:
    """电子铃（青年）：两算子调频，调制比 3.5 有一点钟的味道，亮的那一下很快收掉。"""
    f = midi(m)
    n = sec(2.4)
    tt = times(n)
    idx = (0.9 * vel + 0.1) * np.exp(-tt / 0.18) + 0.08
    y = np.sin(TAU * f * tt + idx * np.sin(TAU * 3.5 * f * tt)) * np.exp(-tt / (1.3 * (880.0 / f) ** 0.3))
    return fade(lp(y, 2800, 4) * vel * 0.32, 0.002, 0.08)


@lru_cache(maxsize=1024)
def celesta(m: float, vel: float = 0.6) -> np.ndarray:
    """钢片琴（中年）：毛毡槌敲钢片，底下有木头共鸣箱，比钟琴圆。"""
    f = midi(m)
    n = sec(2.2)
    tau = 1.0 * (700.0 / f) ** 0.4
    y = modal(n, [f, 2.0 * f, 4.1 * f], [tau, tau * 0.3, 0.06], [1.0, 0.07, 0.025 * vel])
    rng = np.random.default_rng(int(m * 100) + 13)
    k = sec(0.012)
    y[:k] += lp(white(k, rng), 900) * np.linspace(1, 0, k) ** 2 * 0.25 * vel  # 毡槌和琴键的那一下闷响
    y = y + reson(y, 600, 2.5, 0.2)
    return fade(lp(y, 5000) * vel * 0.45, 0.001, 0.06)


@lru_cache(maxsize=1024)
def bowl(m: float, vel: float = 0.5) -> np.ndarray:
    """小铜碗（老年）：轻轻碰一下。每个泛音是一对差一点的频率，余音里有慢慢的「嗡——嗡——」。"""
    f = midi(m)
    n = sec(4.0)
    pairs = [(1.0, 1.0, 2.6), (2.71, 0.06, 1.0), (5.15, 0.012, 0.35)]
    fr, de, am = [], [], []
    for ratio, a, tau in pairs:
        for d in (-1, 1):
            fr.append(f * ratio * (1 + d * 0.0012 * ratio))
            de.append(tau)
            am.append(a * 0.5)
    y = modal(n, fr, de, am)
    rng = np.random.default_rng(int(m * 100) + 14)
    k = sec(0.008)
    y[:k] += lp(white(k, rng), 1500) * np.linspace(1, 0, k) * 0.05 * vel
    return fade(lp(y, 5000) * vel * 0.5, 0.002, 0.2)


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


# ============================================================ 芯片（11-12 画面定成像素以后加的） ====
# 老游戏机的声音：方波（脉冲波）、阶梯三角波、噪声。但这里是「暖的」芯片——全部带限合成（不混叠），
# 3.5 kHz 以上很快掉下去，音量包络按 16 级台阶走（那一点「一格一格」的味道），跟真乐器混着用。

def _pulse_amps(k: np.ndarray, duty: float) -> np.ndarray:
    """占空比 duty 的脉冲波第 k 次谐波的幅度（相对 1/k）。duty=0.5 是方波，只有奇次谐波。"""
    return np.abs(np.sin(np.pi * k * duty)) / (np.pi * duty)


def _steps(env: np.ndarray, levels: int = 16) -> np.ndarray:
    """把包络量化成 levels 级台阶，再用 1.5 毫秒抹一下台阶的棱，免得「咔咔」响。"""
    q = np.round(np.clip(env, 0, 1) * (levels - 1)) / (levels - 1)
    w = max(3, sec(0.0015))
    return np.convolve(np.pad(q, (w, w), mode="edge"), np.ones(2 * w + 1) / (2 * w + 1), mode="valid")


@lru_cache(maxsize=4096)
def chip(m: float, dur: float, vel: float = 0.7, duty: float = 0.25, decay: float = 0.9) -> np.ndarray:
    """芯片的一声：脉冲波，起音一点点往下弯（像老卡带的音高包络），按住时一格一格变轻，晚一点进来的轻揉音。"""
    f = midi(m)
    n = sec(dur + 0.25)
    tt = times(n)
    k = np.arange(1, 25)
    amps = _pulse_amps(k, duty) / k
    gain = _spectral_env([(800, 1.2, 2)], -3.5, 2500)
    vib = cents(9.0 * np.sin(TAU * 5.6 * tt) * np.clip((tt - 0.28) / 0.2, 0, 1))
    bend = cents(35.0 * np.exp(-tt / 0.012))
    ph = TAU * np.cumsum(f * vib * bend) / SR
    y = np.zeros(n)
    for kk, a in zip(k, amps):
        fk = f * kk
        if fk > SR * 0.45:
            break
        y += a * gain(fk) * np.sin(kk * ph)
    env = 0.35 + 0.65 * np.exp(-tt / max(0.08, decay * (440.0 / f) ** 0.2))
    hold = sec(dur)
    if hold < n:
        env[hold:] *= np.exp(-np.arange(n - hold) / (SR * 0.045))
    y = y * _steps(env)
    y = y / (np.max(np.abs(y)) + 1e-9)
    return fade(y * vel * 0.32, 0.002, 0.03)


@lru_cache(maxsize=4096)
def tri_bass(m: float, dur: float, vel: float = 0.7) -> np.ndarray:
    """阶梯三角波贝斯：三角波量化成 32 级（老游戏机那种有一点颗粒的低音），低通磨圆，不刺。"""
    f = midi(m)
    n = sec(dur + 0.12)
    tt = times(n)
    ph = (f * tt) % 1.0
    tri = 1.0 - 4.0 * np.abs(ph - 0.5)
    tri = np.round(tri * 15.5) / 15.5
    y = lp(tri, 1100, 4)
    env = np.ones(n)
    hold = sec(dur)
    if hold < n:
        env[hold:] = np.exp(-np.arange(n - hold) / (SR * 0.03))
    return fade(y * env * vel * 0.5, 0.004, 0.02)


def chip_noise(kind: str = "hat", vel: float = 0.5, seed: int = 0) -> np.ndarray:
    """噪声鼓：hat 是短的高噪声，snare 是带一点音高的中频噪声。用 15 位移位寄存器那种「粗」的噪声，再磨一磨。"""
    rng = np.random.default_rng(700 + seed)
    hold = 6 if kind == "hat" else 14  # 每个随机值保持几个采样：越大越粗、越低
    n = sec(0.08 if kind == "hat" else 0.18)
    raw = np.repeat(rng.choice([-1.0, 1.0], n // hold + 1), hold)[:n]
    tt = times(n)
    if kind == "hat":
        y = bp(raw, 4500, 9000) * _steps(np.exp(-tt / 0.018), 8) * 0.3
    else:
        body = np.sin(TAU * 190 * tt) * np.exp(-tt / 0.03) * 0.5
        y = (bp(raw, 800, 4200) * 0.6 + body) * _steps(np.exp(-tt / 0.055), 8)
    return fade(y * vel * 0.45, 0.0005, 0.01)


@lru_cache(maxsize=1024)
def chip_blip(m: float, vel: float = 0.6) -> np.ndarray:
    """早上那一层的芯片小铃：一声很短的方波 + 一个同音的轻回声（老游戏没有混响，只有这种假回声）。"""
    a = chip(m, 0.09, vel, 0.25, 0.15)
    b = chip(m, 0.07, vel * 0.4, 0.5, 0.12)
    out = np.zeros(len(a) + sec(0.11) + len(b))
    out[:len(a)] += a
    out[sec(0.11):sec(0.11) + len(b)] += b
    return lp(out, 2400, 4) * 0.9
