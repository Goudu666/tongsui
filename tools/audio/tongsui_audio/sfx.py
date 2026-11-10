"""界面、行动、脚步和几个仪式性的声音。

界面音的材料只用三样：纸、木头、印泥——和画面的孔版套色是一家。
没有「叮」「咻」这类电子提示音。
"""
from __future__ import annotations

import numpy as np

from . import amb, inst
from .dsp import (SR, TAU, Mix, bp, bursts, db, fade, far, hp, level, lfo_noise, lp, modal, moving_band, reson, reverb,
                  rng_for, sec, softclip, swell, times, to_stereo, trim, white)
from .music import P


def tap():
    """按钮：木头戳子落在纸上。"""
    rng = rng_for("tap")
    y = modal(sec(0.12), [410, 965, 1720], [0.035, 0.02, 0.01], [1.0, 0.5, 0.25], rng, 0.0015)
    y[: sec(0.02)] += lp(white(sec(0.02), rng), 2500) * np.linspace(1, 0, sec(0.02)) ** 2 * 0.3
    return y


def page():
    """换页：一张纸抽出来。"""
    rng = rng_for("page")
    d = sec(0.24)
    x = np.linspace(0, 1, d)
    y = moving_band(d, rng, 1800, 6500, 6.0, q=1.5) * np.sin(np.pi * x ** 0.6) ** 1.5
    return y + bursts(d, rng, 60, (0.002, 0.006), (2500, 8000)) * np.sin(np.pi * x) * 2


def toast():
    """提示：小木鱼一样的一下。"""
    rng = rng_for("toast")
    return modal(sec(0.3), [742, 1505, 2310], [0.07, 0.035, 0.015], [1.0, 0.35, 0.15], rng, 0.001)


def error():
    """不行：闷闷的两下，往下走。"""
    rng = rng_for("error")
    mx = Mix(0.5)
    for i, f in enumerate([300, 236]):
        mx.add(modal(sec(0.2), [f, f * 2.3, f * 3.9], [0.05, 0.02, 0.01], [1.0, 0.4, 0.2], rng, 0.002), 0.01 + i * 0.13, 0.9 - 0.2 * i)
    return mx.mono()


def key_tick():
    rng = rng_for("type")
    return modal(sec(0.05), [1650, 2900], [0.008, 0.005], [1.0, 0.5], rng, 0.001) * 0.6


def shake():
    """重新投胎：摇签筒。哗——哗——哗，掉出来一根。"""
    rng = rng_for("shake")
    mx = Mix(1.6)
    for i in range(3):
        d = sec(0.22)
        g = np.zeros(d)
        for _ in range(26):
            at = int(rng.integers(0, d - sec(0.02)))
            f = rng.uniform(1500, 3600)
            c = modal(sec(0.02), [f, f * 1.6], [0.004, 0.003], [1.0, 0.5], rng, 0.0008)
            g[at:at + len(c)] += c * rng.uniform(0.3, 1.0)
        mx.add(g * np.hanning(d) ** 0.5, 0.02 + i * 0.27, 0.8, pan=-0.2 + 0.2 * i)
    stick = modal(sec(0.15), [1250, 2140, 3350], [0.03, 0.02, 0.01], [1.0, 0.6, 0.3], rng, 0.001)
    mx.add(stick, 0.95, 0.9, pan=0.15)
    mx.add(stick * 0.4, 1.06, 0.9, pan=0.2)
    return reverb(mx.buf, 0.4, 0.1, 5000, 23)


def xingmu():
    """事件开场：醒木。说书的、说相声的，开口之前拍这一下。"""
    rng = rng_for("xingmu")
    y = modal(sec(0.5), [318, 742, 1630, 2890, 4400], [0.07, 0.045, 0.025, 0.012, 0.006], [1.0, 0.9, 0.7, 0.5, 0.3], rng, 0.002)
    y[: sec(0.006)] += white(sec(0.006), rng) * np.linspace(1, 0, sec(0.006)) * 0.9
    table = modal(sec(0.5), [96, 171], [0.1, 0.06], [0.7, 0.4])
    return reverb(softclip((y + table) * 1.3, 1.2), 0.7, 0.16, 4000, 25)


def stamp():
    """做了选择：盖章。"""
    rng = rng_for("stamp")
    thud = modal(sec(0.2), [128, 262, 540], [0.05, 0.03, 0.015], [1.0, 0.6, 0.3], rng, 0.003)
    paper = bp(white(sec(0.06), rng), 1500, 5000) * np.linspace(1, 0, sec(0.06)) ** 2 * 0.2
    thud[: len(paper)] += paper
    return thud


def cord():
    """拉线开关：咔、哒。"""
    rng = rng_for("cord")
    mx = Mix(0.5)
    mx.add(modal(sec(0.06), [3150, 4900, 1400], [0.008, 0.005, 0.012], [1.0, 0.6, 0.5], rng, 0.001), 0.01, 0.8)
    mx.add(modal(sec(0.09), [1820, 2950, 760], [0.012, 0.007, 0.02], [1.0, 0.6, 0.6], rng, 0.001), 0.075, 1.0)
    return reverb(mx.buf, 0.35, 0.1, 4000, 27)


def coin():
    """钢镚儿落在桌上。"""
    rng = rng_for("coin")
    mx = Mix(1.0)
    t, gap, v = 0.01, 0.13, 1.0
    for i in range(5):
        y = modal(sec(0.3), [5230, 7910, 11200, 3120], [0.07, 0.05, 0.03, 0.02], [1.0, 0.7, 0.4, 0.3], rng, 0.0008)
        mx.add(y, t, v)
        t += gap
        gap *= 0.6
        v *= 0.65
    return mx.mono()


def knock():
    """开门喊一声之前：笃、笃笃。"""
    rng = rng_for("knock")
    mx = Mix(1.2)
    for i, t in enumerate([0.02, 0.32, 0.47]):
        y = modal(sec(0.25), [182, 415, 890, 1650], [0.05, 0.035, 0.02, 0.01], [1.0, 0.8, 0.5, 0.25], rng, 0.003)
        mx.add(y, t, 1.0 if i != 1 else 0.85)
    return reverb(mx.buf, 1.3, 0.22, 3200, 29)


def eat():
    """吃饭：筷子碰碗。"""
    return amb.bowl_clink()


def study():
    """写作业：铅笔在本上走。"""
    rng = rng_for("study")
    mx = Mix(1.6)
    t = 0.03
    for i in range(7):
        d = sec(rng.uniform(0.08, 0.2))
        y = bp(white(d, rng), 2200, 7000) * np.hanning(d) ** 0.6 * (0.6 + 0.4 * np.abs(lfo_noise(d, 60, rng)))
        mx.add(y, t, rng.uniform(0.5, 0.9))
        t += d / SR + rng.uniform(0.02, 0.09)
    return mx.mono()


def wash():
    """洗澡：搪瓷盆「当」一声，热水倒进去。"""
    rng = rng_for("wash")
    mx = Mix(2.4)
    mx.add(modal(sec(0.9), [905, 2280, 3710, 5400], [0.3, 0.2, 0.12, 0.07], [1.0, 0.7, 0.4, 0.2], rng, 0.002), 0.02, 0.5)
    d = sec(1.8)
    x = np.linspace(0, 1, d)
    pour = bp(white(d, rng), 400, 5000) * swell(d, 0.3, 0.7) * (0.6 + 0.4 * np.abs(lfo_noise(d, 25, rng)))
    mx.add(pour, 0.25, 0.35)
    for i in range(22):
        bd = sec(rng.uniform(0.02, 0.05))
        tt = times(bd)
        f0 = rng.uniform(350, 700) * (1 + 0.8 * i / 22)   # 水越满，咕嘟声越高
        b = np.sin(TAU * (f0 * tt + 4 * f0 * tt * tt)) * np.exp(-tt / (bd / SR * 0.4))
        mx.add(fade(b, 0.001, 0.004), 0.3 + rng.uniform(0, 1.5), rng.uniform(0.15, 0.4), pan=rng.uniform(-0.3, 0.3))
    return reverb(mx.buf, 0.5, 0.12, 5000, 31)


def rope():
    """跳皮筋：脚落地的节奏就是主题的节奏——小皮球，架脚踢。"""
    rng = rng_for("rope")
    mx = Mix(2.6)
    step = 0.26
    for i, on in enumerate([1, 1, 1, 0, 1, 1, 1, 0]):
        if not on:
            continue
        t = 0.03 + i * step
        hop = lp(white(sec(0.05), rng), 900) * np.exp(-times(sec(0.05)) / 0.012) + \
            bp(white(sec(0.05), rng), 1500, 4500) * np.exp(-times(sec(0.05)) / 0.008) * 0.4
        mx.add(hop, t, 0.8 if i % 4 != 2 else 1.0)
        d = sec(0.12)
        tt = times(d)
        twang = np.sin(TAU * np.cumsum(175 - 55 * tt / 0.12) / SR) * np.exp(-tt / 0.035)  # 皮筋「嘣」一下
        mx.add(twang, t + 0.02, 0.35)
    return far(mx.buf, 0.1, 0.5, 33)


def kite():
    """放风筝：纸在风里抖。"""
    rng = rng_for("kite")
    n = sec(2.4)
    g = swell(n, 0.4, 0.8)
    flut = bursts(n, rng, 22, (0.015, 0.04), (700, 3600)) * g * 3
    wind = moving_band(n, rng, 400, 2000, 0.8) * g * 0.6
    return to_stereo(flut, 0.2) + to_stereo(wind, -0.2)


def wrench():
    """帮爷爷修车：扳手的棘轮，末了敲一下。"""
    rng = rng_for("wrench")
    mx = Mix(1.8)
    for i in range(7):
        y = modal(sec(0.04), [2700 * rng.uniform(0.96, 1.04), 4300, 6100], [0.008, 0.005, 0.003], [1.0, 0.6, 0.3], rng, 0.001)
        mx.add(y, 0.03 + i * 0.085, 0.7)
    y = modal(sec(0.6), [1310, 2980, 4500, 560], [0.2, 0.13, 0.07, 0.05], [1.0, 0.6, 0.4, 0.4], rng, 0.002)
    mx.add(y, 0.78, 0.9)
    return far(mx.buf, 0.1, 0.5, 35)


def teacup():
    """喝茶听一段：盖碗的盖子在碗沿上刮两下，扣回去。"""
    rng = rng_for("teacup")
    mx = Mix(1.6)
    for t, d in [(0.02, 0.16), (0.26, 0.2)]:
        n = sec(d)
        mx.add(bp(white(n, rng), 3200, 8200) * np.sin(np.pi * np.linspace(0, 1, n)) ** 2 * 0.25, t, 0.6, pan=-0.1)
    for t, p, g in [(0.56, 1.0, 0.9), (0.63, 1.31, 0.4)]:
        y = modal(sec(0.6), [1650 * p, 3720 * p, 6100 * p, 8900 * p], [0.16, 0.1, 0.05, 0.03], [1.0, 0.55, 0.3, 0.15], rng, 0.001)
        mx.add(y, t, g, pan=0.1)
    return reverb(mx.buf, 0.7, 0.14, 5000, 43)


def on_stage():
    """上台来一段：醒木一拍，台下稀稀拉拉一阵掌声。"""
    rng = rng_for("on_stage")
    mx = Mix(2.6)
    mx.add(xingmu(), 0.0, 0.9)
    mx.add(lp(amb.applause(1.7, rng), 5000), 0.55, 0.2)
    return reverb(mx.buf, 0.9, 0.18, 4500, 45)


def fishing():
    """跟大爷钓鱼：甩一竿，漂落在水上。"""
    rng = rng_for("fishing")
    mx = Mix(2.0)
    n = sec(0.34)
    mx.add(moving_band(n, rng, 900, 4200, 5.0, q=2.0) * np.sin(np.pi * np.linspace(0, 1, n)) ** 2, 0.02, 0.5, pan=-0.2)
    mx.add(amb.water_plop(), 0.8, 0.7, pan=0.2)
    return mx.buf


def step(surface: str, i: int):
    """脚步。indoor：水泥地，闷，带一点鞋底；outdoor：土路柏油，沙沙的。"""
    rng = rng_for("step_%s_%d" % (surface, i))
    d = sec(0.16)
    tt = times(d)
    if surface == "indoor":
        y = modal(d, [118 * rng.uniform(0.9, 1.1), 265, 520], [0.03, 0.02, 0.012], [1.0, 0.6, 0.3], rng, 0.003)
        y += bp(white(d, rng), 1500, 4200) * np.exp(-tt / 0.012) * 0.18
    else:
        y = lp(white(d, rng), 500) * np.exp(-tt / 0.02) * 0.9
        y += bp(white(d, rng), 1200, 6000) * np.exp(-tt / rng.uniform(0.025, 0.045)) * (0.5 + 0.5 * np.abs(lfo_noise(d, 80, rng))) * 0.6
    return fade(y, 0.001, 0.03)


def door_open():
    return amb.door(False, 0.25)


def door_close():
    return amb.door(True, 0.3)


def birth():
    """就这样，出生吧：八音盒上弦，然后头三个音。"""
    rng = rng_for("birth")
    mx = Mix(4.5)
    t, gap = 0.03, 0.12
    for i in range(8):
        y = modal(sec(0.05), [2100 * rng.uniform(0.95, 1.05), 3600, 880], [0.008, 0.005, 0.015], [1.0, 0.5, 0.5], rng, 0.001)
        mx.add(y, t, 0.5 + 0.04 * i, pan=-0.2)
        t += gap
        gap *= 0.9
    t += 0.25
    for i, deg in enumerate([3, 5, 6]):
        mx.add(inst.music_box(P(deg, 1), 1.2, 0.8), t + i * 0.42, 0.5, pan=0.1)
    mx.add(inst.music_box(P(6, 2), 1.0, 0.4), t + 2 * 0.42 + 0.21, 0.3, pan=0.25)
    return reverb(mx.buf, 1.6, 0.26, 4500, 37)


def day_end():
    """一天结束：拉灯，八音盒慢慢地「5 3 1」。"""
    mx = Mix(4.5)
    mx.add(to_stereo(cord().mean(axis=1)), 0.0, 0.8)
    for i, (deg, o, gap) in enumerate([(5, 1, 0.0), (3, 1, 0.62), (1, 1, 1.35)]):
        mx.add(inst.music_box(P(deg, o), 1.6, 0.7 - 0.06 * i), 0.55 + gap, 0.5, pan=-0.1 + 0.1 * i)
    return reverb(mx.buf, 2.0, 0.3, 4000, 39)


def death():
    """一声磬。然后什么都没有。"""
    rng = rng_for("death")
    fr, de, am = [], [], []
    for f, d, a in [(221.0, 5.5, 1.0), (608.0, 3.6, 0.6), (1164.0, 2.4, 0.4), (1870.0, 1.5, 0.25), (2710.0, 0.9, 0.15)]:
        for det in (1.0, 1.0032):
            fr.append(f * det)
            de.append(d)
            am.append(a)
    y = modal(sec(8.0), fr, de, am, rng, 0.004)
    y[: sec(0.03)] += lp(white(sec(0.03), rng), 800) * np.linspace(1, 0, sec(0.03)) ** 2 * 0.6
    return reverb(y * 0.3, 3.2, 0.35, 3500, 41)


def online():
    """TA 上线了：对门的门开了。"""
    return door_open()


def offline():
    return door_close()


UI = {
    "tap": tap, "page": page, "toast": toast, "error": error, "type": key_tick, "shake": shake, "xingmu": xingmu,
    "stamp": stamp, "cord": cord, "coin": coin, "birth": birth, "day_end": day_end, "death": death,
    "door_open": door_open, "door_close": door_close, "bell_duet": amb.bell_duet,
}
ACTIONS = {
    "eat": eat, "eat_out": amb.egg_sizzle, "sleep": cord, "study": study, "wash": wash, "knock": knock,
    "play_roof": amb.wing_flap, "play_river": kite, "play_alley": rope, "work": wrench,
    "school": lambda: amb.school_bell(True), "listen": teacup, "perform": on_stage, "fish": fishing,
}
STEPS = {"step_%s_%d" % (s, i): (lambda s=s, i=i: step(s, i)) for s in ("indoor", "outdoor") for i in range(4)}

PEAKS = {"tap": -8, "page": -12, "toast": -10, "type": -16, "error": -8, "stamp": -6, "coin": -10}


def render(name: str) -> np.ndarray:
    table = {**UI, **{"act_" + k: v for k, v in ACTIONS.items()}, **STEPS}
    y = trim(to_stereo(table[name]()), -58, 0.12)
    base = name if name in PEAKS else ("step" if name.startswith("step") else "")
    return level(y, None, PEAKS.get(base, -9.0 if base == "step" else -4.0))


def names():
    return list(UI) + ["act_" + k for k in ACTIONS] + list(STEPS)
