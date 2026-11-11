"""河畔里的环境音。全部合成，没有录音。

分两类：
  LOOPS   铺底的循环（空气、河水、鏊子、蝉、话匣子……），首尾无缝
  SHOTS   隔一阵响一下的单发声（车铃、鸽哨、锅铲、船笛、快板……）

哪个声音在哪儿、几点钟、哪个年代响，不在这里定，在 client/audio/soundscape.json 里定。
这里只负责把声音本身做对：干声在近处，远近由 far() 推出去。
"""
from __future__ import annotations

import numpy as np

from . import inst
from .dsp import (SR, TAU, Mix, bp, bursts, cents, colored, db, echo, fade, far, hp, level, lfo_noise, loop_wrap, loop_xfade, lp,
                  midi, modal, moving_band, peak, reson, reverb, rng_for, sec, shelf, softclip, swell, times, to_stereo, trim,
                  white)

LOOP_LUFS = -28.0
SHOT_PEAK = -4.0


# ============================================================ 人声（不成字的） ====

VOWELS = {"a": (800, 1250, 2600), "o": (520, 900, 2500), "e": (560, 1500, 2500), "i": (310, 2250, 3000),
          "u": (360, 760, 2400), "v": (310, 1900, 2300), "r": (500, 1400, 1700)}


def babble(dur: float, rng, f0: float, rate: float = 5.5, phrase=(4, 12), pause=(0.25, 0.6), lively: float = 1.0,
           starts=None) -> np.ndarray:
    """听不清字的说话声：有声调、有音节、有句读，就是没有词。

    做法是加法合成：声带的每个泛音穿过三个会动的共鸣峰。隔着墙、隔着话匣子的小喇叭听，
    人耳只认得出节奏和腔调——说相声的那种一个长一个短的节奏。
    starts 可以指定每一句的 (开始秒, 音节数)。
    """
    n = sec(dur)
    semi = np.zeros(n)
    amp = np.zeros(n)
    form = np.zeros((3, n))
    cons = np.zeros(n)
    voiced = np.zeros(n, dtype=bool)
    plan = []
    if starts is None:
        t = 0.08
        while t < dur - 0.4:
            k = int(rng.integers(phrase[0], phrase[1] + 1))
            plan.append((t, k))
            t += k / rate + rng.uniform(*pause)
    else:
        plan = list(starts)
    keys = list(VOWELS)
    for t, k in plan:
        for j in range(k):
            syl = rng.uniform(0.75, 1.3) / rate
            if t + syl > dur - 0.03:
                break
            a, b = sec(t), sec(t + syl)
            x = np.linspace(0, 1, b - a)
            tone = int(rng.integers(0, 5))
            contour = [0.0 - 1.0 * x, 4.0 + 0.0 * x, 0.0 + 5.0 * x, -1.0 - 3.5 * np.sin(np.pi * x) + 2.5 * x * x,
                       5.0 - 8.0 * x][tone]
            semi[a:b] = (contour - 2.5 * j / max(1, k)) * lively
            amp[a:b] = np.sin(np.pi * x) ** 0.6 * rng.uniform(0.55, 1.0)
            f = VOWELS[keys[int(rng.integers(0, len(keys)))]]
            for i in range(3):
                form[i, a:b] = f[i] * rng.uniform(0.94, 1.06)
            voiced[a:b] = True
            if rng.uniform() < 0.45:
                c = min(b - a, sec(rng.uniform(0.03, 0.07)))
                cons[a:a + c] = np.hanning(c) * rng.uniform(0.3, 0.8)
                amp[a:a + c] *= np.linspace(0.1, 1, c)
            t += syl
    idx = np.where(voiced, np.arange(n), 0)
    np.maximum.accumulate(idx, out=idx)
    k_s = np.hanning(sec(0.03) | 1)
    k_s /= k_s.sum()
    semi = np.convolve(semi[idx], k_s, mode="same")
    for i in range(3):
        row = form[i, idx]
        row[row == 0] = (500, 1500, 2500)[i]
        form[i] = np.convolve(row, k_s, mode="same")
    amp = np.convolve(amp, k_s, mode="same")
    freq = f0 * 2 ** (semi / 12.0) * cents(8 * lfo_noise(n, 6, rng))
    ph = TAU * np.cumsum(freq) / SR
    out = np.zeros(n)
    bw, fg = (70.0, 100.0, 140.0), (1.0, 0.55, 0.3)
    for k in range(1, 36):
        fk = freq * k
        if fk.min() > 4500:
            break
        a_k = np.zeros(n)
        for i in range(3):
            a_k += fg[i] / (1.0 + ((fk - form[i]) / bw[i]) ** 2)
        out += a_k / k ** 0.5 * np.sin(k * ph + rng.uniform(0, TAU))
    out *= amp
    out += hp(white(n, rng), 2800) * cons * 0.35
    return out / (np.abs(out).max() + 1e-9)


def laughter(dur: float, rng, people: int = 14) -> np.ndarray:
    n = sec(dur)
    out = np.zeros(n)
    for _ in range(people):
        t0 = rng.uniform(0, dur * 0.35)
        rate = rng.uniform(4.2, 6.2)
        k = int(rng.integers(4, 9))
        f0 = rng.uniform(170, 380)
        y = babble(k / rate + 0.3, rng, f0, rate, starts=[(0.02, k)], lively=0.6)
        y *= np.exp(-times(len(y)) / rng.uniform(0.4, 0.9))
        a = sec(t0)
        y = y[: n - a]
        out[a:a + len(y)] += y * rng.uniform(0.4, 1.0)
    out += bp(white(n, rng), 600, 2600) * swell(n, 0.2, 1.0) * 0.5  # 笑声底下的那层气
    return out * swell(n, 0.18, 0.7)


def applause(dur: float, rng) -> np.ndarray:
    n = sec(dur)
    y = bursts(n, rng, 70, (0.004, 0.012), (900, 3600))
    return y * swell(n, 0.25, 0.8) / (np.abs(y).max() + 1e-9)


def radio(x: np.ndarray, rng) -> np.ndarray:
    """话匣子的小喇叭：窄、有点破、带一层沙沙的底噪。"""
    y = bp(x, 380, 2900, 2)
    y = softclip(y * 2.2, 1.5)
    y = peak(y, 1300, 1.5, 5.0)
    hiss = bp(white(len(y), rng), 500, 4000) * 0.02 * (1 + 0.3 * lfo_noise(len(y), 0.4, rng))
    return y + hiss


# ============================================================ 循环 ====

def air_day():
    """白天的底：远处的车流合成一片，偶尔一阵小风。"""
    rng = rng_for("air_day")
    n = sec(20)
    hum = lp(colored(n, rng, -6), 220) * 0.9 * (1 + 0.25 * lfo_noise(n, 0.15, rng))
    mid = bp(colored(n, rng, -3), 250, 1800) * 0.25 * (1 + 0.4 * lfo_noise(n, 0.3, rng))
    breeze = moving_band(n, rng, 500, 2500, 0.15) * 0.05 * (0.5 + 0.5 * lfo_noise(n, 0.2, rng)) ** 2
    l = hum + mid + breeze
    rng2 = rng_for("air_day_r")
    r = lp(colored(n, rng2, -6), 220) * 0.9 + bp(colored(n, rng2, -3), 250, 1800) * 0.25 + breeze
    return loop_xfade(np.stack([l, 0.6 * r + 0.4 * l], axis=1), 3.0)


def air_night():
    """夜里：车少了，只剩很低的一层嗡，和窗缝里的风。"""
    rng = rng_for("air_night")
    n = sec(20)
    hum = lp(colored(n, rng, -8), 140) * (1 + 0.2 * lfo_noise(n, 0.1, rng))
    wind = moving_band(n, rng, 250, 900, 0.1) * 0.06 * (0.5 + 0.5 * lfo_noise(n, 0.12, rng)) ** 2
    y = hum + wind
    return loop_xfade(to_stereo(y, 0.0) + to_stereo(lp(colored(n, rng, -8), 200) * 0.3, 0.6), 3.0)


def crickets():
    """蛐蛐。三四只，各叫各的。"""
    rng = rng_for("crickets")
    n = sec(16)
    mx = Mix(16)
    for i in range(4):
        f = rng.uniform(4100, 4900)
        chirp_rate = rng.uniform(1.6, 2.6)
        pulse = rng.uniform(52, 66)
        tt = times(n)
        gate = (np.sin(TAU * chirp_rate * tt + rng.uniform(0, TAU)) > 0.55).astype(float)
        gate = np.convolve(gate, np.hanning(200) / 100, mode="same")
        y = np.sin(TAU * f * tt) * (0.5 + 0.5 * np.sin(TAU * pulse * tt)) ** 4 * gate
        y *= 0.6 + 0.4 * lfo_noise(n, 0.2, rng)
        mx.add(y, 0, rng.uniform(0.3, 1.0), pan=rng.uniform(-0.8, 0.8))
    return loop_xfade(mx.buf[:n], 1.0)


def cicada():
    """知了。先是一下一下的，越叫越密，最后连成一片再泄下去。"""
    rng = rng_for("cicada")
    n = sec(18)
    mx = Mix(18)
    for i, (t0, d) in enumerate([(0.3, 10.5), (7.5, 9.5)]):
        m = sec(d)
        tt = times(m)
        x = np.linspace(0, 1, m)
        rate = 3.5 + 14.0 * np.clip(x / 0.45, 0, 1) ** 2
        rasp = 0.5 + 0.5 * np.sin(TAU * np.cumsum(rate) / SR)
        rasp = np.where(x > 0.5, 1.0, rasp ** 2)
        buzz = (0.55 + 0.45 * np.sign(np.sin(TAU * (165 + 12 * i) * tt)))
        car = reson(white(m, rng), 5200 + 500 * i, 2.5) + 0.5 * reson(white(m, rng), 7400, 3.0)
        y = car * buzz * rasp * swell(m, 0.6, 0.6)
        mx.add(y, t0, 0.8, pan=-0.5 + 1.0 * i)
    return _fold(mx.buf, sec(17))


def _fold(x, n):
    return loop_wrap(x, n)


def river():
    """海河：水拍岸的一层，偶尔咕咚一声，上面一点风。"""
    rng = rng_for("river")
    n = sec(20)
    wave = 0.5 + 0.5 * np.sin(TAU * 0.23 * times(n) + lfo_noise(n, 0.2, rng) * 1.5)
    wash = bp(colored(n, rng, -3), 300, 2400) * (0.25 + 0.75 * wave ** 3)
    low = lp(colored(n, rng, -6), 180) * 0.7
    lap = bursts(n, rng, 9, (0.02, 0.07), (500, 3000)) * (0.3 + 0.7 * wave ** 2) * 3.0
    y = Mix(20)
    y.add(wash + low, 0, 1.0, pan=-0.2)
    y.add(lap, 0, 0.6, pan=0.3)
    for _ in range(11):  # 水泡：一小段往上翘的正弦
        d = sec(rng.uniform(0.03, 0.09))
        f0 = rng.uniform(280, 800)
        tt = times(d)
        b = np.sin(TAU * (f0 * tt + 0.5 * f0 * 9 * tt * tt)) * np.exp(-tt / (d / SR * 0.4))
        y.add(fade(b, 0.002, 0.005), rng.uniform(0.2, 19.0), rng.uniform(0.1, 0.3), pan=rng.uniform(-0.6, 0.6))
    wind = moving_band(n, rng, 300, 1400, 0.12) * 0.05 * (0.5 + 0.5 * lfo_noise(n, 0.15, rng)) ** 2
    y.add(wind, 0, 1.0, pan=0.1)
    return loop_xfade(y.buf[:n], 3.0)


def roof_wind():
    rng = rng_for("roof_wind")
    n = sec(20)
    g = (0.5 + 0.5 * lfo_noise(n, 0.18, rng)) ** 2
    a = moving_band(n, rng, 250, 1300, 0.16) * g
    b = moving_band(n, rng, 700, 3200, 0.22, q=2.0) * g ** 2 * 0.35
    flap = bursts(n, rng, 2.5, (0.03, 0.08), (300, 1500)) * g * 4.0  # 晾着的被单
    y = to_stereo(a, -0.3) + to_stereo(b, 0.4) + to_stereo(flap, 0.2) * 0.3
    return loop_xfade(y, 3.0)


def sizzle():
    """鏊子：面糊摊开之后那一片细密的滋啦，底下一层热气。"""
    rng = rng_for("sizzle")
    n = sec(14)
    body = hp(white(n, rng), 3500) * (0.6 + 0.4 * np.abs(lfo_noise(n, 14, rng))) * (0.7 + 0.3 * lfo_noise(n, 0.5, rng))
    pops = bursts(n, rng, 160, (0.001, 0.005), (2500, 9000), 2.0) * 5.0
    steam = bp(white(n, rng), 900, 3000) * 0.12 * (0.7 + 0.3 * lfo_noise(n, 0.7, rng))
    y = to_stereo(body * 0.4 + pops, 0.0) + to_stereo(steam, -0.3)
    return loop_xfade(y, 2.0)


def hallway_tone():
    """楼道：一点电流的嗡，暖气管偶尔「当」一声。"""
    rng = rng_for("hallway")
    n = sec(18)
    tt = times(n)
    hum = (np.sin(TAU * 50 * tt) + 0.5 * np.sin(TAU * 100 * tt + 1) + 0.2 * np.sin(TAU * 150 * tt + 2)) * 0.25
    room = lp(colored(n, rng, -6), 300) * 0.6 + bp(colored(n, rng, -3), 300, 1200) * 0.08
    mx = Mix(18)
    mx.add(hum * (1 + 0.1 * lfo_noise(n, 0.3, rng)) + room, 0)
    for t0 in (4.3, 11.9, 12.5):
        tick = modal(sec(0.6), [612, 1490, 2380], [0.12, 0.07, 0.04], [1.0, 0.5, 0.3], rng)
        mx.add(far(tick, 0.55, 1.6), t0, 0.12, pan=rng.uniform(-0.5, 0.5))
    return loop_xfade(mx.buf[:n], 2.0)


def clock():
    """家里的座钟。嘀、嗒，两下音高不一样。"""
    rng = rng_for("clock")
    mx = Mix(4)
    for i in range(4):
        hi = i % 2 == 0
        y = modal(sec(0.12), [2350 if hi else 1900, 3900, 410], [0.012, 0.006, 0.03], [1.0, 0.4, 0.5], rng, 0.001)
        mx.add(y, i * 1.0 + 0.01, 1.0)
    out = reverb(mx.buf[: sec(4)], 0.35, 0.12, 3500, 21)
    return _fold(out, sec(4))


def radio_xiangsheng():
    """话匣子里的相声。逗哏的话密、调门高；捧哏的就那么几个字；包袱响了，台下乐。"""
    rng = rng_for("radio")
    total = 26.0
    mx = Mix(total)
    script = [  # (开始, 谁, 音节数)
        (0.6, "dou", 9), (2.6, "peng", 1), (3.1, "dou", 12), (5.7, "peng", 2), (6.4, "dou", 7), (8.0, "peng", 1),
        (8.5, "dou", 22), (12.6, "peng", 4),
        (16.6, "dou", 6), (17.9, "peng", 2), (18.6, "dou", 10), (20.6, "peng", 3),
    ]
    for t0, who, k in script:
        if who == "dou":
            rate = 7.2 if k > 15 else 5.8  # 长的那句是贯口，越说越快
            y = babble(k / rate + 0.4, rng, 205, rate, starts=[(0.02, k)], lively=1.15)
            mx.add(y, t0, 0.9)
        else:
            y = babble(k / 4.6 + 0.4, rng, 128, 4.6, starts=[(0.02, k)], lively=0.7)
            mx.add(y, t0, 0.75)
    mx.add(laughter(3.0, rng), 13.5, 0.7)
    mx.add(applause(2.6, rng), 14.2, 0.35)
    mx.add(laughter(2.0, rng, 8), 21.6, 0.5)
    y = radio(mx.mono()[: sec(total)], rng)
    hiss = bp(white(sec(total + 2), rng), 500, 4000) * 0.012
    y = fade(y, 0.3, 0.6) + loop_xfade(hiss, 2.0)
    return _fold(far(y, 0.35, 0.7, 31), sec(total))


def school_din():
    """课间：一操场的孩子，听不清谁在喊什么。"""
    rng = rng_for("school")
    total = 16.0
    mx = Mix(total + 1)
    for _ in range(26):
        d = rng.uniform(0.5, 2.2)
        y = babble(d, rng, rng.uniform(290, 460), rng.uniform(4.5, 6.5), phrase=(2, 7), pause=(0.2, 0.9), lively=1.4)
        mx.add(y * swell(len(y), 0.3), rng.uniform(0, total - 0.5), rng.uniform(0.15, 0.6), pan=rng.uniform(-0.9, 0.9))
    steps = bursts(sec(total), rng, 14, (0.01, 0.03), (200, 1200)) * 0.5
    mx.add(steps, 0, 0.4)
    y = _fold(mx.buf, sec(total))
    return _fold(far(y, 0.6, 1.1, 33), sec(total))


def traffic_modern():
    """后来的街：自行车少了，多了一层持续的胎噪。"""
    rng = rng_for("traffic")
    n = sec(20)
    mx = Mix(20)
    base = bp(colored(n, rng, -4), 120, 1500) * (1 + 0.3 * lfo_noise(n, 0.2, rng))
    mx.add(base, 0, 0.5)
    for _ in range(5):  # 一辆辆过去
        d = sec(rng.uniform(3.5, 6))
        y = bp(colored(d, rng, -3), 200, 2600) * swell(d, rng.uniform(0.4, 0.6), 2.0)
        mx.add(y, rng.uniform(0, 14), rng.uniform(0.4, 0.8), pan=rng.uniform(-0.7, 0.7))
    return loop_xfade(_fold(mx.buf, n), 3.0)


# ============================================================ 天气 ====
# 下雨、下雪、秋风。画面上的天气（client/scripts/world/weather.gd）有了，耳朵里也得有。
# 循环的做法：噪声那几层多做 k 秒再首尾交叠（loop_xfade）；一下一下的雨点、滴水是「事件」，
# 撒在 0~n 之间，尾巴折回开头（loop_wrap），所以接缝上一个点不多、一个点不少。

DRIP = (587.3, 659.3, 880.0, 987.8)  # 屋檐滴水的「叮」落在 D 宫五声上（D5 E5 A5 B5），和配乐不打架


def _bubble(rng, f0: float, d: float = 0.03, rise: float = 1.6, click: float = 0.3) -> np.ndarray:
    """水泡：一滴水砸进水里，带进去一个小气泡，气泡响一声往上翘的「啵」（Minnaert 共振）。"""
    n = sec(d * 4)
    tt = times(n)
    f = f0 * (1.0 + rise * tt / (d * 4))
    y = np.sin(TAU * np.cumsum(f) / SR) * np.exp(-tt / d)
    k = sec(0.002)
    y[:k] += white(k, rng) * np.linspace(1, 0, k) * click
    return fade(y, 0.0015, 0.01)


def _drop_events(mx: Mix, rng, n: int, rate: float, f_lo: float, f_hi: float, gain: float, d=(0.012, 0.035), pan=0.8):
    """往带子上撒 rate 个/秒的水泡。"""
    for _ in range(rng.poisson(rate * n / SR)):
        y = _bubble(rng, rng.uniform(f_lo, f_hi), rng.uniform(*d), rng.uniform(0.6, 2.4), rng.uniform(0.1, 0.5))
        mx.add(y, rng.uniform(0, n / SR), gain * rng.uniform(0.2, 1.0) ** 1.5, pan=rng.uniform(-pan, pan))


def _eaves(mx: Mix, rng, n: int, periods, gain: float):
    """屋檐滴水：几个滴水的地方，各滴各的，差不多匀，又不齐。"""
    for i, per in enumerate(periods):
        f0 = DRIP[i % len(DRIP)]
        pan = (-0.7, 0.55, -0.2, 0.8)[i % 4]
        t = rng.uniform(0, per)
        while t < n / SR:
            y = _bubble(rng, f0 * rng.uniform(0.985, 1.015), rng.uniform(0.035, 0.06), 0.9, 0.25)
            y = y + 0.25 * lp(white(len(y), rng), 900) * np.exp(-times(len(y)) / 0.008)  # 落地那一下
            mx.add(y, t, gain * rng.uniform(0.55, 1.0), pan=pan)
            t += per * rng.uniform(0.75, 1.3)


def _rain_body(n: int, rng, heavy: bool) -> np.ndarray:
    """雨的那一片：成千上万的雨点合成一层「沙——」。高频不能太亮，不然听一会儿就累。"""
    hiss = bp(colored(n, rng, -4.5), 350, 4500) * (0.8 + 0.2 * lfo_noise(n, 0.25, rng))
    grit = bursts(n, rng, 900 if heavy else 380, (0.001, 0.004), (700, 4000), 1.6) * (4.0 if heavy else 3.0)
    tap = bursts(n, rng, 60 if heavy else 30, (0.003, 0.009), (350, 1800), 2.0) * 6.0  # 近处打在东西上的
    roar = hp(lp(colored(n, rng, -5), 500), 140 if heavy else 220) * (0.9 if heavy else 0.2) * (1 + 0.25 * lfo_noise(n, 0.2, rng))
    y = hiss * (0.55 if heavy else 0.45) + grit + tap + roar
    y = peak(y, 3000, 0.7, -6.0)                            # 3 kHz 附近挖一块：扎耳朵的那段，听一小时会累
    return shelf(lp(y, 5000 if heavy else 4000), 2500, -4.0)


def _gutter(n: int, rng) -> np.ndarray:
    """下水口哗哗的流水：带通噪声，被很快的随机起伏切成一串咕噜。"""
    flow = bp(colored(n, rng, -3), 300, 1600)
    gurgle = (0.5 + 0.5 * lfo_noise(n, 11, rng)) ** 2
    return reson(flow, 620, 2.0, 1.0) * gurgle * (0.7 + 0.3 * lfo_noise(n, 0.3, rng))


def rain(heavy: bool = False):
    """户外的雨。轻：细密的一层，屋檐慢慢滴，积水里偶尔啵一声。重：一片哗哗，下水口在流，水泡密。"""
    name = "rain_heavy" if heavy else "rain_light"
    rng = rng_for(name)
    dur, k = 16.0, 3.0
    n, nk = sec(dur), sec(dur + k)
    l = _rain_body(nk, rng, heavy)
    r = _rain_body(nk, rng_for(name + "_r"), heavy)
    bed = np.stack([l * 0.8 + r * 0.2, r * 0.8 + l * 0.2], axis=1)
    if heavy:
        bed = bed + to_stereo(_gutter(nk, rng), 0.35) * 0.35
    bed = loop_xfade(bed, k)
    ev = Mix(dur)
    _drop_events(ev, rng, n, 16 if heavy else 6, 900, 2600, 0.10 if heavy else 0.09)      # 积水里的水泡
    _eaves(ev, rng, n, (0.55, 0.8, 1.15, 0.37) if heavy else (1.3, 2.1, 1.7), 0.18 if heavy else 0.2)
    ev_buf = loop_wrap(reverb(ev.buf, 0.7, 0.18, 4000, 101), n)
    return bed + ev_buf * (1.0 if heavy else 1.2)


def rain_indoor():
    """屋里听雨：外头那一片隔着墙，只剩闷闷的低处；窗玻璃上细细的嗒嗒；窗台上一滴一滴。"""
    rng = rng_for("rain_in")
    dur, k = 14.0, 2.5
    n, nk = sec(dur), sec(dur + k)
    muffled = lp(colored(nk, rng, -3.5), 650) * (0.85 + 0.15 * lfo_noise(nk, 0.2, rng))
    muffled = hp(muffled, 70)
    room = lp(colored(nk, rng, -6), 160) * 0.25
    bed = loop_xfade(to_stereo(muffled, -0.1) + to_stereo(room, 0.2) + to_stereo(lp(colored(nk, rng, -3.5), 650), 0.6) * 0.4, k)
    ev = Mix(dur)
    for _ in range(rng.poisson(14 * dur)):                   # 玻璃上的雨点：很短，有一点玻璃的声
        f = rng.uniform(1900, 3300)
        y = modal(sec(0.03), [f, f * 1.63], [0.006, 0.004], [1.0, 0.4], rng, 0.0008)
        ev.add(lp(y, 3800), rng.uniform(0, dur), 0.08 * rng.uniform(0.2, 1.0) ** 2, pan=rng.uniform(-0.9, 0.2))
    t = 0.4
    while t < dur:                                            # 窗台：铁皮雨搭上一滴一滴「嗒」
        y = modal(sec(0.18), [740, 1480, 2210], [0.045, 0.025, 0.012], [1.0, 0.35, 0.15], rng, 0.002)
        ev.add(lp(y, 2500), t, 0.22 * rng.uniform(0.6, 1.0), pan=-0.45)
        t += 1.45 * rng.uniform(0.7, 1.35)
    ev_buf = loop_wrap(reverb(ev.buf, 0.45, 0.25, 3000, 103), n)
    return bed + ev_buf


def snow_hush():
    """下雪：世界一下子静了。远处的城压成一层很低的嗡，偶尔一点风，雪落在衣服上的沙沙几乎听不见。"""
    rng = rng_for("snow_hush")
    dur, k = 16.0, 3.0
    nk = sec(dur + k)
    hum = hp(lp(colored(nk, rng, -6), 260), 60) * 0.3 * (1 + 0.15 * lfo_noise(nk, 0.08, rng))
    g = 0.25 + 0.75 * (0.5 + 0.5 * lfo_noise(nk, 0.09, rng)) ** 3
    wind = moving_band(nk, rng, 300, 1200, 0.07, q=1.6) * 1.2 * g
    flakes = lp(bursts(nk, rng, 90, (0.002, 0.006), (1800, 4500), 2.0), 4000) * 0.15  # 雪片落在帽子上
    y = to_stereo(hum, 0.0) + to_stereo(wind, -0.35) + to_stereo(flakes, 0.25)
    y = y + to_stereo(hp(lp(colored(nk, rng, -6), 260), 60) * 0.15, 0.7)
    return loop_xfade(y, k)


def thunder(variant: int = 0):
    """远处的闷雷：很远，没有「咔嚓」，只有一阵一阵滚过去的低音。"""
    rng = rng_for("thunder%d" % variant)
    dur = (6.5, 8.0)[variant]
    n = sec(dur)
    tt = times(n)
    env = np.zeros(n)
    rolls = [(0.25, 1.0, 0.7), (1.3, 0.75, 1.1), (2.6, 0.55, 1.4), (4.0, 0.3, 1.6)] if variant == 0 else \
            [(0.4, 0.6, 0.8), (1.1, 1.0, 1.0), (2.9, 0.65, 1.5), (4.6, 0.4, 1.8), (6.0, 0.2, 1.5)]
    for t0, a, w in rolls:                                    # 一阵一阵：快起、慢落
        x = (tt - t0) / w
        env += a * np.where(x > 0, (np.minimum(x * 5, 1)) * np.exp(-x * 2.2), 0)
    env *= 0.8 + 0.2 * lfo_noise(n, 6, rng)
    y = lp(colored(n, rng, -6), 220) * env
    y += lp(colored(n, rng, -4), 600) * env ** 2 * 0.15         # 一点点中频，听得出是雷不是车
    y = hp(y, 32)
    return far(y, 0.85, 2.8, 105 + variant)


def snow_steps(variant: int = 0):
    """有人踩着雪走过去：咯吱、咯吱。雪越冷越「吱」。"""
    rng = rng_for("snow_steps%d" % variant)
    count, gap = (5, 0.56) if variant == 0 else (4, 0.68)
    mx = Mix(count * gap + 1.0)
    for i in range(count):
        d = sec(rng.uniform(0.14, 0.2))
        x = np.linspace(0, 1, d)
        env = np.sin(np.pi * x ** 0.7) ** 1.5
        crunch = bursts(d, rng, 900, (0.001, 0.004), (350, 2200), 1.4) * env * 6.0
        sq = sec(0.07)
        tq = times(sq)
        rate = rng.uniform(260, 380) * (1 + 0.3 * np.sin(np.pi * tq / 0.07))   # 粘一下滑一下的「吱」
        pulse = (np.sin(TAU * np.cumsum(rate) / SR) > 0.6).astype(float)
        squeak = reson(pulse - pulse.mean(), rng.uniform(950, 1250), 4.0) * np.hanning(sq) * 1.5
        step = np.zeros(d + sq)
        step[:d] += crunch
        step[sec(0.04):sec(0.04) + sq] += squeak
        g = 0.55 + 0.45 * np.sin(np.pi * (i + 0.5) / count)  # 走近、走远
        mx.add(lp(step, 3200), 0.05 + i * gap * rng.uniform(0.93, 1.07), g, pan=-0.5 + i / count)
    return far(mx.buf, 0.4, 0.9, 107 + variant)


def snow_fall(variant: int = 0):
    """树枝上的雪落下来：枝子一弹，噗的一团，后面细细地撒一阵。"""
    rng = rng_for("snow_fall%d" % variant)
    mx = Mix(2.6)
    if variant == 0:
        creak = modal(sec(0.08), [430, 980], [0.02, 0.012], [1.0, 0.4], rng, 0.002)
        mx.add(lp(creak, 1500), 0.02, 0.15)
    lumps = [(0.12, 1.0), (0.31, 0.45), (0.55, 0.25)] if variant == 0 else [(0.05, 0.8), (0.18, 0.7), (0.47, 0.3)]
    for t0, a in lumps:
        d = sec(0.25)
        tt = times(d)
        thump = lp(white(d, rng), 320) * np.exp(-tt / 0.06) * 3.0
        mx.add(thump, t0, a)
    d = sec(1.6)
    powder = bp(white(d, rng), 700, 3800) * np.exp(-times(d) / 0.45) * swell(d, 0.08, 0.6) * 0.35
    powder += lp(bursts(d, rng, 160, (0.002, 0.008), (600, 3000), 1.5), 4000) * np.exp(-times(d) / 0.5) * 2.0
    mx.add(powder, lumps[0][0] + 0.02, 1.0, pan=0.15)
    return far(mx.buf, 0.35, 1.0, 109 + variant)


def leaf_gust(variant: int = 0):
    """秋风：一阵风过来，树上的叶子哗啦啦，地上的干叶子跟着打着滚儿走一截。"""
    rng = rng_for("leaf_gust%d" % variant)
    dur = (4.8, 5.6)[variant]
    n = sec(dur)
    g = swell(n, (0.42, 0.55)[variant], 1.1)
    wind = moving_band(n, rng, 250, 1300, 0.5, q=1.4) * g * 1.0
    rustle = bursts(n, rng, 260, (0.003, 0.012), (800, 3800), 1.8) * g ** 1.5 * 5.0
    rustle = peak(lp(rustle, 4200), 3000, 0.9, -5.0)
    skit = np.zeros(n)                                         # 地上滚的叶子：一串小「嚓」，随风起落
    tumble = bursts(n, rng, 45, (0.004, 0.015), (500, 2400), 1.2) * np.clip(g * 1.4 - 0.3, 0, 1) * 4.0
    skit += tumble
    y = to_stereo(wind, -0.2) + to_stereo(rustle, 0.35) * 0.8 + to_stereo(skit, -0.45) * 0.7
    y = y + to_stereo(lp(bursts(n, rng, 180, (0.003, 0.01), (900, 3500), 1.8), 4000) * g ** 2 * 3.0, -0.6) * 0.5
    return far(y, 0.3, 1.1, 111 + variant)


LOOPS = {
    "air_day": air_day, "air_night": air_night, "crickets": crickets, "cicada": cicada, "river": river,
    "roof_wind": roof_wind, "sizzle": sizzle, "hallway": hallway_tone, "clock": clock,
    "radio": radio_xiangsheng, "school_din": school_din, "traffic": traffic_modern,
    "rain_light": lambda: rain(False), "rain_heavy": lambda: rain(True), "rain_in": rain_indoor, "snow_hush": snow_hush,
}


# ============================================================ 单发 ====

def _bell_strike(rng, pitch: float = 1.0, vel: float = 1.0) -> np.ndarray:
    """车铃的铃盖：几组成对的、略微不齐的泛音，所以会「嗡」地颤。"""
    fr, de, am = [], [], []
    for f, d, a in [(2140, 0.9, 1.0), (3420, 0.7, 0.8), (4870, 0.45, 0.55), (6400, 0.3, 0.35), (8250, 0.2, 0.2)]:
        for det in (1.0, 1.0045):
            fr.append(f * pitch * det)
            de.append(d)
            am.append(a * vel)
    y = modal(sec(1.6), fr, de, am, rng, 0.0015)
    y[: sec(0.004)] += bp(white(sec(0.004), rng), 1200, 2600) * 0.4 * vel
    return y


def bell(kind: str = "a", pitch: float = 1.0, seed: str = "bell") -> np.ndarray:
    """a 叮铃 / b 叮铃 叮铃 / c 转铃一长串。"""
    rng = rng_for(seed + kind)
    mx = Mix(2.6)
    if kind == "a":
        hits = [(0.0, 1.0), (0.13, 0.8)]
    elif kind == "b":
        hits = [(0.0, 1.0), (0.12, 0.8), (0.42, 0.95), (0.55, 0.75)]
    else:
        hits = [(t, 0.6 + 0.4 * np.sin(np.pi * t / 0.85)) for t in np.cumsum(np.r_[0, rng.uniform(0.045, 0.065, 15)])]
    for t, v in hits:
        mx.add(_bell_strike(rng, pitch, v), t, 0.5)
    return mx.mono()


def bell_duet():
    """同框：青的车铃响一声，梅的车铃高一个小三度应一声。"""
    mx = Mix(2.6)
    mx.add(bell("a", 1.0, "duet_q"), 0.0, 0.8, pan=-0.4)
    mx.add(bell("a", 1.189, "duet_m"), 0.48, 0.8, pan=0.4)
    return reverb(mx.buf, 0.9, 0.12, 5000, 41)


def pigeon_whistle(variant: int = 0):
    """鸽哨。一群鸽子带着哨子绕楼飞一圈：一组空心的长音，近了响，远了弱，带一点多普勒。"""
    rng = rng_for("whistle%d" % variant)
    d = 9.0 if variant == 0 else 13.0
    n = sec(d)
    tt = times(n)
    mx = Mix(d + 1)
    tones = [523, 659, 784, 1047, 1319, 1568] if variant == 0 else [440, 587, 698, 880, 1175]
    passes = 1 if variant == 0 else 2
    for f in tones:
        f *= rng.uniform(0.985, 1.015)
        circ = TAU * passes * tt / d + rng.uniform(-0.25, 0.25)
        near = (0.5 - 0.5 * np.cos(circ)) ** 1.5              # 绕到近处
        dop = cents(22.0 * np.sin(circ) + 6 * lfo_noise(n, 0.8, rng))
        ph = TAU * np.cumsum(f * dop) / SR
        tone = np.sin(ph) + 0.18 * np.sin(2 * ph + 1) + 0.06 * np.sin(3 * ph)
        air = reson(white(n, rng), f, 45) * 2.5              # 吹过葫芦口的气
        y = (tone * 1.1 + air * 0.7) * near * (0.75 + 0.25 * lfo_noise(n, 2.5, rng))
        mx.add(y, 0, rng.uniform(0.5, 1.0), pan=float(np.clip(rng.uniform(-0.7, 0.7), -1, 1)))
    wings = bursts(n, rng, 10, (0.02, 0.05), (200, 1400)) * (0.5 - 0.5 * np.cos(TAU * passes * tt / d)) ** 3
    mx.add(wings, 0, 0.5)
    return far(fade(mx.buf[:n], 1.5, 2.0), 0.35 if variant == 0 else 0.6, 1.4, 43)


def pigeon_coo():
    rng = rng_for("coo")
    mx = Mix(2.4)
    t = 0.05
    for i in range(3):
        d = sec(0.42)
        tt = times(d)
        f = 330 + 55 * np.sin(np.pi * tt / 0.42) - 30 * tt
        trill = 0.6 + 0.4 * np.sin(TAU * 26 * tt)
        y = np.sin(TAU * np.cumsum(f) / SR) * trill * swell(d, 0.4)
        y += 0.2 * np.sin(2 * TAU * np.cumsum(f) / SR) * swell(d, 0.4)
        mx.add(lp(y, 1200), t, 0.8 - 0.1 * i)
        t += 0.55
    return far(mx.buf, 0.2, 0.5, 45)


def wing_flap():
    """扑棱棱——鸽子起飞。"""
    rng = rng_for("flap")
    mx = Mix(1.8)
    t = 0.0
    gap = 0.11
    for i in range(13):
        d = sec(0.05)
        y = bp(white(d, rng), 180, 1800) * np.hanning(d)
        mx.add(y, t, 0.5 + 0.5 * np.sin(np.pi * i / 13), pan=-0.5 + i / 13.0)
        t += gap
        gap = max(0.06, gap * 0.93)
    return far(mx.buf, 0.15, 0.6, 47)


def sparrows(variant: int = 0):
    rng = rng_for("sparrow%d" % variant)
    mx = Mix(2.6)
    t = 0.05
    for i in range(int(rng.integers(4, 9))):
        d = sec(rng.uniform(0.03, 0.07))
        tt = times(d)
        f0 = rng.uniform(3200, 5200)
        f = f0 * (1.0 + 0.35 * np.exp(-tt / 0.012) - 0.12 * tt / (d / SR))
        ph = TAU * np.cumsum(f) / SR
        y = (np.sin(ph) + 0.3 * np.sin(2 * ph)) * np.hanning(d)
        mx.add(y, t, rng.uniform(0.5, 1.0), pan=rng.uniform(-0.3, 0.3) + 0.4 * (variant - 0.5))
        t += rng.uniform(0.07, 0.4)
    return far(mx.buf, 0.25, 0.6, 49)


def spatula(variant: int = 0):
    """谁家炒菜的锅铲声。隔着一道门。"""
    rng = rng_for("spatula%d" % variant)
    mx = Mix(2.6)
    pattern = [0.0, 0.22, 0.38, 0.75, 0.9, 1.3] if variant == 0 else [0.0, 0.3, 0.45, 0.6, 1.1]
    for t in pattern:
        base = rng.uniform(0.9, 1.1)
        clang = modal(sec(0.4), [820 * base, 1370 * base, 2210 * base, 3150 * base, 4480 * base],
                      [0.11, 0.09, 0.06, 0.04, 0.03], [1.0, 0.8, 0.7, 0.5, 0.3], rng, 0.003)
        scrape = bp(white(sec(0.12), rng), 1800, 5200) * np.hanning(sec(0.12)) * 0.5
        mx.add(clang, t, rng.uniform(0.5, 1.0))
        mx.add(scrape, t + 0.03, 0.6)
    siz = hp(white(sec(2.0), rng), 2500) * swell(sec(2.0), 0.15, 1.0) * 0.12
    mx.add(siz, 0.0, 1.0)
    return far(mx.buf, 0.6, 1.5, 51)


def keys():
    rng = rng_for("keys")
    mx = Mix(1.4)
    for i in range(9):
        f = rng.uniform(3800, 7800)
        y = modal(sec(0.25), [f, f * 1.47, f * 2.09], [0.06, 0.04, 0.02], [1.0, 0.6, 0.3], rng, 0.001)
        mx.add(y, 0.02 + abs(rng.normal(0.25, 0.18)), rng.uniform(0.3, 1.0), pan=rng.uniform(-0.2, 0.2))
    return far(mx.buf, 0.3, 1.4, 53)


def door(close: bool = True, distance: float = 0.5):
    rng = rng_for("door%d" % close)
    mx = Mix(1.6)
    if close:
        thump = modal(sec(0.35), [78, 142, 233, 410], [0.09, 0.06, 0.04, 0.02], [1.0, 0.8, 0.5, 0.3], rng, 0.004)
        mx.add(lp(thump, 900), 0.05, 1.0)
        latch = modal(sec(0.08), [1850, 2900, 4300], [0.012, 0.008, 0.005], [1.0, 0.6, 0.4], rng, 0.001)
        mx.add(latch, 0.075, 0.35)
    else:
        latch = modal(sec(0.08), [1700, 2750, 4100], [0.012, 0.008, 0.005], [1.0, 0.6, 0.4], rng, 0.001)
        mx.add(latch, 0.02, 0.4)
        d = sec(0.55)
        tt = times(d)
        f = 310 + 190 * (tt / 0.55) ** 0.7 + 25 * lfo_noise(d, 20, rng)
        ph = TAU * np.cumsum(f) / SR
        creak = (np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.33 * np.sin(3 * ph) + 0.2 * np.sin(5 * ph))
        creak *= (0.5 + 0.5 * np.sign(np.sin(TAU * np.cumsum(38 + 30 * tt) / SR))) * swell(d, 0.35, 0.8)
        mx.add(bp(creak, 400, 3500), 0.09, 0.22)
    return far(mx.buf, distance, 1.5, 55)


def ship_horn():
    """海河上的船笛。低，长，从很远的地方来。"""
    rng = rng_for("horn")
    d = sec(3.4)
    tt = times(d)
    env = np.minimum(1.0, tt / 0.35) * np.minimum(1.0, (3.4 - tt) / 0.9)
    y = np.zeros(d)
    for f, a in [(146.0, 1.0), (185.0, 0.75)]:
        ph = TAU * f * tt * (1 + 0.002 * np.sin(TAU * 0.4 * tt))
        for k in range(1, 9):
            y += a * np.sin(k * ph + rng.uniform(0, TAU)) / k ** 1.1
    y = softclip(y * env * 0.5, 1.5)
    return echo(far(y, 0.7, 2.6, 57), 0.9, 0.4, 0.25, 900, 3)


def water_plop():
    rng = rng_for("plop")
    mx = Mix(1.2)
    for i, t in enumerate([0.02, 0.09]):
        d = sec(0.12)
        tt = times(d)
        f0 = 420 - 120 * i
        y = np.sin(TAU * (f0 * tt + f0 * 5 * tt * tt)) * np.exp(-tt / 0.035)
        mx.add(fade(y, 0.002, 0.01), t, 0.8 - 0.3 * i)
    splash = bp(white(sec(0.4), rng), 1500, 6000) * np.exp(-times(sec(0.4)) / 0.09) * 0.25
    mx.add(splash, 0.03, 1.0)
    return far(mx.buf, 0.25, 0.5, 59)


def kuaiban(variant: int = 0):
    """顾家有人在练快板。呱 = 大板，嘀 = 节子。"""
    rng = rng_for("kuaiban%d" % variant)
    pat = ["X.x.X.x.X.xxX...", "x.X.x.X.xxX.X.X."] if variant == 0 else ["X.xxX.xxX.x.X.x.", "xxX.xxX.X.x.X..."]
    step = 60.0 / 132 / 4
    mx = Mix(6)
    t = 0.05
    for row in pat:
        for i, c in enumerate(row):
            if c == "X":
                mx.add(inst.clapper(True, rng.uniform(0.75, 1.0), i), t + rng.uniform(0, 0.006), 1.0)
            elif c == "x":
                mx.add(inst.clapper(False, rng.uniform(0.6, 0.9), i), t + rng.uniform(0, 0.006), 0.9)
            t += step
    return far(mx.buf, 0.5, 1.0, 61)


def iron_clappers():
    """磨剪子的手里那串铁片（惊闺）。哗啷——哗啷——"""
    rng = rng_for("jinggui")
    mx = Mix(3.2)
    for shake in range(3):
        t0 = 0.05 + shake * 0.85
        for j in range(5):
            base = rng.uniform(0.85, 1.2)
            y = modal(sec(0.5), [640 * base, 1520 * base, 2480 * base, 3900 * base, 5200 * base],
                      [0.16, 0.12, 0.09, 0.05, 0.03], [1.0, 0.9, 0.7, 0.5, 0.3], rng, 0.002)
            mx.add(y, t0 + j * rng.uniform(0.035, 0.06), rng.uniform(0.5, 1.0))
    return far(mx.buf, 0.55, 1.1, 63)


def popcorn_bang():
    """爆米花，「砰」的一声，在楼和楼之间弹两下。"""
    rng = rng_for("popcorn")
    d = sec(0.7)
    tt = times(d)
    boom = np.sin(TAU * np.cumsum(55 + 90 * np.exp(-tt / 0.03)) / SR) * np.exp(-tt / 0.16)
    crack = lp(white(d, rng), 2600) * np.exp(-tt / 0.05)
    hiss = bp(white(sec(1.4), rng), 1500, 6000) * np.exp(-times(sec(1.4)) / 0.4) * 0.15
    mx = Mix(2.2)
    mx.add(boom + crack * 0.8, 0.02, 1.0)
    mx.add(hiss, 0.06, 1.0)
    return echo(far(mx.buf, 0.55, 1.6, 65), 0.21, 0.5, 0.35, 1500, 4)


def school_bell(short: bool = False):
    """电铃：小锤子一秒打二十多下。"""
    rng = rng_for("school_bell%d" % short)
    dur = 1.1 if short else 2.6
    mx = Mix(dur + 1.5)
    t = 0.02
    while t < dur:
        y = modal(sec(0.5), [1180, 2390, 3160, 4420, 5870, 7350], [0.22, 0.18, 0.12, 0.09, 0.06, 0.04],
                  [0.7, 1.0, 0.8, 0.7, 0.5, 0.3], rng, 0.001)
        mx.add(y, t, rng.uniform(0.8, 1.0))
        t += 1.0 / 23.0
    return far(softclip(mx.buf * 0.25, 1.2), 0.3 if short else 0.5, 1.2, 67)


def pump():
    """打气筒。"""
    rng = rng_for("pump")
    mx = Mix(2.8)
    for i in range(4):
        t0 = 0.05 + i * 0.62
        d = sec(0.3)
        x = np.linspace(0, 1, d)
        push = bp(white(d, rng), 500 + 900 * x.mean(), 3200) * np.sin(np.pi * x) ** 0.7 * (0.6 + 0.4 * x)
        push = reson(push, 900 + 180 * i, 3.0, 1.5) + push * 0.5   # 胎越打越鼓，音越高
        d2 = sec(0.2)
        pull = bp(white(d2, rng), 1500, 5000) * np.hanning(d2) * 0.25
        mx.add(push, t0, 1.0)
        mx.add(pull, t0 + 0.36, 1.0)
        mx.add(modal(sec(0.05), [1500, 2600], [0.01, 0.006], [1, 0.5], rng), t0 + 0.3, 0.3)
    return far(mx.buf, 0.2, 0.5, 69)


def ratchet():
    """飞轮空转：哒哒哒哒……越来越慢。"""
    rng = rng_for("ratchet")
    mx = Mix(2.6)
    t, gap = 0.03, 0.028
    while t < 2.2:
        y = modal(sec(0.03), [3100 * rng.uniform(0.97, 1.03), 4700, 6900], [0.006, 0.004, 0.003], [1.0, 0.6, 0.4], rng, 0.0008)
        mx.add(y, t, 0.5 + 0.5 * np.exp(-t))
        t += gap
        gap *= 1.045
    return far(mx.buf, 0.2, 0.5, 71)


def file_rasp():
    """补胎之前拿锉把胎皮打毛。"""
    rng = rng_for("rasp")
    mx = Mix(1.8)
    for i in range(4):
        d = sec(0.24)
        tt = times(d)
        y = bp(white(d, rng), 1800, 5200) * (0.5 + 0.5 * np.sign(np.sin(TAU * 210 * tt))) * np.sin(np.pi * tt / 0.24)
        mx.add(y, 0.05 + i * 0.34, 0.8 if i % 2 == 0 else 0.55)
    return far(mx.buf, 0.2, 0.5, 73)


def hammer_taps():
    rng = rng_for("hammer")
    mx = Mix(1.8)
    for i, t in enumerate([0.03, 0.33, 0.52]):
        y = modal(sec(0.7), [1240, 2910, 4380, 6120, 520], [0.25, 0.18, 0.1, 0.06, 0.05], [1.0, 0.7, 0.5, 0.3, 0.4], rng, 0.002)
        mx.add(y, t, 0.7 + 0.3 * (i == 0))
    return far(mx.buf, 0.25, 0.6, 75)


def erhu_phrase(variant: int = 0):
    """车铺的二胡响了一声。拉的就是这个游戏的主题——这是个扣子，到老年它会变成配乐本身。"""
    spb = 60.0 / 66
    if variant == 0:
        seq = [(3, 1), (5, 1), (6, 2.2)]                      # 小皮球——
    elif variant == 1:
        seq = [(5, 1), (3, 1), (2, 2.4)]                      # 架脚踢——
    else:
        seq = [(6, .5), (5, .5), (3, .5), (2, .5), (1, 2.6)]  # 6 5 3 2 1
    notes, t = [(0.1, 0.07, 62 + {1: 0, 2: 2, 3: 4, 5: 7, 6: 9}[seq[0][0]] - 2, 0.6)], 0.17
    for deg, beats in seq:
        notes.append((t, beats * spb, 62 + {1: 0, 2: 2, 3: 4, 5: 7, 6: 9}[deg], 0.8))
        t += beats * spb
    y = inst.sustained_line(notes, t + 0.6, "erhu", seed=90 + variant, level=0.6, glide_scale=1.3)
    return far(y, 0.4, 0.9, 77)


def beeper():
    """会嘀嘀响的小玩意儿。"""
    mx = Mix(1.4)
    for i in range(3):
        for j in range(2):
            d = sec(0.07)
            tt = times(d)
            y = np.sign(np.sin(TAU * 2730 * tt)) * 0.5 + np.sin(TAU * 2730 * tt)
            mx.add(fade(lp(y, 6000), 0.002, 0.004), 0.03 + i * 0.36 + j * 0.11, 0.6)
    return far(mx.buf, 0.2, 0.4, 79)


def keyboard():
    """网吧的键盘声。"""
    rng = rng_for("keyboard")
    mx = Mix(2.4)
    t = 0.03
    while t < 2.0:
        f = rng.uniform(1400, 2600)
        y = modal(sec(0.04), [f, f * 1.9, 320], [0.006, 0.004, 0.012], [1.0, 0.5, 0.7], rng, 0.001)
        mx.add(y, t, rng.uniform(0.5, 1.0), pan=rng.uniform(-0.3, 0.3))
        t += rng.choice([0.07, 0.09, 0.12, 0.16, 0.3], p=[0.3, 0.3, 0.2, 0.12, 0.08])
    return far(mx.buf, 0.45, 0.6, 81)


def pile_driver():
    """对岸在打桩。咚——咚——"""
    rng = rng_for("pile")
    mx = Mix(7.5)
    for i in range(5):
        d = sec(0.5)
        tt = times(d)
        thud = np.sin(TAU * np.cumsum(48 + 60 * np.exp(-tt / 0.02)) / SR) * np.exp(-tt / 0.13)
        clank = modal(d, [410, 980, 1630], [0.08, 0.05, 0.03], [1.0, 0.6, 0.4], rng, 0.003) * 0.5
        mx.add(thud + clank, 0.05 + i * 1.25, 0.9)
    return echo(far(mx.buf, 0.75, 2.2, 83), 0.33, 0.45, 0.3, 800, 3)


def gust():
    rng = rng_for("gust")
    n = sec(4.5)
    y = moving_band(n, rng, 300, 1800, 0.5) * swell(n, 0.4, 1.2)
    return to_stereo(y, -0.2) + to_stereo(moving_band(n, rng, 600, 2600, 0.6) * swell(n, 0.55, 1.5) * 0.5, 0.4)


def egg_sizzle():
    """鏊子上磕一个蛋。"""
    rng = rng_for("egg")
    mx = Mix(2.6)
    for t in (0.03, 0.16):
        mx.add(modal(sec(0.06), [2500, 4100, 6200], [0.008, 0.006, 0.004], [1.0, 0.7, 0.4], rng, 0.001), t, 0.5)
    d = sec(2.0)
    siz = hp(white(d, rng), 3000) * (0.5 + 0.5 * np.abs(lfo_noise(d, 18, rng))) * np.exp(-times(d) / 0.6)
    siz += bursts(d, rng, 220, (0.001, 0.004), (2500, 9000), 2.0) * np.exp(-times(d) / 0.5) * 4
    mx.add(fade(siz, 0.03, 0.2), 0.3, 0.35)
    return far(mx.buf, 0.1, 0.4, 85)


def batter_scrape():
    """竹蜻蜓把面糊摊开：唰——唰——"""
    rng = rng_for("scrape")
    mx = Mix(1.8)
    for i in range(2):
        d = sec(0.55)
        x = np.linspace(0, 1, d)
        y = moving_band(d, rng, 1500, 4500, 3.0, q=2.5) * np.sin(np.pi * x) ** 0.8
        mx.add(y, 0.03 + i * 0.7, 0.8, pan=-0.3 + 0.6 * i)
    return far(mx.buf, 0.1, 0.4, 87)


def teahouse_crowd(clap: bool):
    """茶社里隔着门传出来的一阵笑，或者一阵巴掌。"""
    rng = rng_for("tea_clap" if clap else "tea_laugh")
    y = lp(applause(2.2, rng), 4500) * 0.5 if clap else laughter(2.4, rng, 9)
    return far(y, 0.45, 0.9, 97)


def bowl_clink():
    rng = rng_for("bowl")
    mx = Mix(1.4)
    for t, p in [(0.03, 1.0), (0.21, 1.12), (0.5, 0.94)]:
        y = modal(sec(0.5), [2080 * p, 4650 * p, 7100 * p, 9800 * p], [0.13, 0.09, 0.05, 0.03], [1.0, 0.6, 0.35, 0.2], rng, 0.001)
        mx.add(y, t, rng.uniform(0.5, 1.0))
    return far(mx.buf, 0.15, 0.4, 89)


SHOTS = {
    "bell_a": lambda: far(bell("a"), 0.3, 0.8, 91), "bell_b": lambda: far(bell("b", 1.06), 0.35, 0.8, 92),
    "bell_c": lambda: far(bell("c", 0.94), 0.3, 0.8, 93),
    "whistle_a": lambda: pigeon_whistle(0), "whistle_b": lambda: pigeon_whistle(1),
    "coo": pigeon_coo, "flap": wing_flap, "sparrow_a": lambda: sparrows(0), "sparrow_b": lambda: sparrows(1),
    "spatula_a": lambda: spatula(0), "spatula_b": lambda: spatula(1), "keys": keys,
    "door_far": lambda: door(True, 0.6), "horn": ship_horn, "plop": water_plop,
    "kuaiban_a": lambda: kuaiban(0), "kuaiban_b": lambda: kuaiban(1), "iron": iron_clappers, "popcorn": popcorn_bang,
    "school_bell": school_bell, "pump": pump, "ratchet": ratchet, "rasp": file_rasp, "hammer": hammer_taps,
    "erhu_a": lambda: erhu_phrase(0), "erhu_b": lambda: erhu_phrase(1), "erhu_c": lambda: erhu_phrase(2),
    "beeper": beeper, "keyboard": keyboard, "pile": pile_driver, "gust": gust,
    "egg": egg_sizzle, "scrape": batter_scrape, "bowl": bowl_clink,
    "tea_laugh": lambda: teahouse_crowd(False), "tea_clap": lambda: teahouse_crowd(True),
    "thunder_a": lambda: thunder(0), "thunder_b": lambda: thunder(1),
    "snow_step_a": lambda: snow_steps(0), "snow_step_b": lambda: snow_steps(1),
    "snow_fall_a": lambda: snow_fall(0), "snow_fall_b": lambda: snow_fall(1),
    "leaf_a": lambda: leaf_gust(0), "leaf_b": lambda: leaf_gust(1),
}


def render_loop(name: str) -> np.ndarray:
    return level(LOOPS[name](), LOOP_LUFS, -3.0)


def render_shot(name: str) -> np.ndarray:
    return level(trim(to_stereo(SHOTS[name]()), -55, 0.15), None, SHOT_PEAK)
