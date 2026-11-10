"""《同岁》的配乐：一个主题，五个人生阶段，四条分轨。

主题只有 16 小节，D 宫五声。节奏的骨头取自楼下跳皮筋的口诀「小皮球，架脚踢，
马兰开花二十一」：三下一停，三下一停，四个快的接三个慢的。

两位玩家各有一条旋律线，写成相声里的一逗一捧：
  第 1~4 小节   青抛两小节，梅接两小节
  第 5~8 小节   同上，换一种说法
  第 9~12 小节  反过来，梅抛，青接
  第 13~16 小节 一人一小节 → 一人半小节（青往上走，梅往下走）→ 落在同一个音上
一个人听，只有半边话；两个人走近了，话才不掉在地上。

分轨（同一阶段的四个文件一样长，引擎里同步播放，各自调音量）：
  bed   伴奏，一直在
  qing  青的旋律（拨的乐器）
  mei   梅的旋律（吟的乐器）
  he    「合」：五声旋律里没有的那两个音（4 和 7）藏在这条和声里，
        只有两人同框而且默契够了才听得见
"""
from __future__ import annotations

import numpy as np

from . import inst
from .dsp import (Mix, colored, db, echo, fade, level, loop_wrap, lp, lufs, peak_db, reverb, sec, to_stereo, trim, warp)

KEY = 62  # D4
_DEG = {1: 0, 2: 2, 3: 4, 4: 5, 5: 7, 6: 9, 7: 11}
BARS = 16
BEATS = BARS * 4


def P(deg: int, octave: int = 0) -> int:
    return KEY + _DEG[deg] + 12 * octave


# ------------------------------------------------------------ 主题 ----
# (拍, 时值, 级, 八度)。一小节 4 拍。

Q_FULL = [
    (0, 1, 3, 0), (1, 1, 5, 0), (2, 1.5, 6, 0),                                  # 小皮球
    (4, 1, 5, 0), (5, 1, 3, 0), (6, 1.5, 2, 0),                                  # 架脚踢
    (16, 1, 5, 0), (17, 1, 6, 0), (18, 1.5, 1, 1),
    (20, 1, 6, 0), (21, 1, 5, 0), (22, 1.5, 3, 0),
    (40, 2, 6, 0), (42, 1, 5, 0), (43, 1, 3, 0),                                 # 接梅的话
    (44, 3, 5, 0),
    (48, 1, 3, 0), (49, 1, 5, 0), (50, 1.5, 6, 0),
    (56, .5, 3, 0), (56.5, .5, 5, 0), (57, .5, 6, 0), (57.5, .5, 1, 1),          # 往上
    (60, 3.5, 1, 0),                                                             # 合
]
M_FULL = [
    (8, .5, 3, 0), (8.5, .5, 5, 0), (9, .5, 6, 0), (9.5, .5, 1, 1), (10, 1, 6, 0), (11, 1, 5, 0),  # 马兰开花二十一
    (12, 2.5, 3, 0),
    (24, .5, 5, 0), (24.5, .5, 6, 0), (25, .5, 5, 0), (25.5, .5, 3, 0), (26, 1, 2, 0), (27, 1, 3, 0),
    (28, 1, 1, 0), (29, 1, 6, -1), (30, 2, 5, -1),
    (32, 2, 1, 1), (34, 1, 6, 0), (35, 1, 1, 1),                                 # 梅先开口
    (36, 3, 2, 1),
    (52, 1, 5, 0), (53, 1, 3, 0), (54, 1.5, 2, 0),
    (58, .5, 6, 0), (58.5, .5, 5, 0), (59, .5, 3, 0), (59.5, .5, 2, 0),          # 往下
    (60, 3.5, 1, 0),                                                             # 合
]
# 老年：只剩骨头。童年的声音密，老年的声音稀。
Q_SPARSE = [
    (0, 2, 3, 0), (2, 2, 6, 0),
    (4, 2, 5, 0), (6, 2, 2, 0),
    (16, 2, 5, 0), (18, 2, 1, 1),
    (20, 2, 6, 0), (22, 2, 3, 0),
    (40, 2, 6, 0), (42, 2, 3, 0),
    (44, 3.5, 5, 0),
    (48, 2, 3, 0), (50, 2, 6, 0),
    (56, 1, 3, 0), (57, 1, 6, 0),
    (60, 4, 1, 0),
]
M_SPARSE = [
    (8, 1, 3, 0), (9, 1.5, 6, 0), (11, 1, 5, 0),
    (12, 3, 3, 0),
    (24, 1, 5, 0), (25, 1, 3, 0), (26, 2, 2, 0),
    (28, 1, 1, 0), (29, 1, 6, -1), (30, 2, 5, -1),
    (32, 3, 1, 1), (35, 1, 6, 0),
    (36, 3.5, 2, 1),
    (52, 2, 5, 0), (54, 2, 2, 0),
    (58, 1, 5, 0), (59, 1, 2, 0),
    (60, 4, 1, 0),
]

# 和弦：低音，三个内声部（低→高），「合」的两个音
CHORD = {
    "D": (38, [57, 62, 66], [62, 66]),
    "Bm7": (47, [57, 62, 66], [62, 69]),
    "Gmaj7": (43, [59, 62, 66], [59, 66]),
    "F#m7": (42, [57, 61, 64], [61, 64]),
    "A7sus4": (45, [55, 62, 64], [62, 67]),
    "G": (43, [55, 59, 62], [59, 67]),
    "D/F#": (42, [57, 62, 66], [57, 66]),
    "Em7": (40, [55, 59, 62], [62, 67]),
    "Dadd9": (38, [57, 64, 66], [64, 69]),
}
PROG = [
    [("D", 4)], [("Bm7", 4)], [("Gmaj7", 4)], [("F#m7", 2), ("A7sus4", 2)],
    [("D", 4)], [("Bm7", 4)], [("Gmaj7", 4)], [("A7sus4", 4)],
    [("G", 4)], [("D/F#", 4)], [("Em7", 4)], [("A7sus4", 4)],
    [("D", 4)], [("Bm7", 4)], [("Gmaj7", 2), ("A7sus4", 2)], [("Dadd9", 4)],
]


def chords():
    """展开成 (起拍, 拍数, 名字)。"""
    out = []
    for bar, row in enumerate(PROG):
        b = bar * 4.0
        for name, beats in row:
            out.append((b, float(beats), name))
            b += beats
    return out


# ------------------------------------------------------------ 阶段 ----

STAGES = {
    "child": dict(bpm=96, q=("music_box", 1), m=("recorder", 1), rt=1.3, wet=0.24, sparse=False),
    "teen": dict(bpm=84, q=("guitar", 0), m=("harmonica", 0), rt=1.5, wet=0.2, sparse=False),
    "young": dict(bpm=100, q=("egtr", 0), m=("lead", 0), rt=1.8, wet=0.2, sparse=False),
    "middle": dict(bpm=72, q=("piano", 0), m=("cello", -1), rt=2.4, wet=0.28, sparse=False),
    "old": dict(bpm=63, q=("sanxian", -1), m=("erhu", 0), rt=2.9, wet=0.32, sparse=True),
}
PAN_Q, PAN_M = -0.28, 0.28
TARGET_LUFS = -20.0  # 四条分轨全开时的响度
BALANCE = {"bed": 0.0, "qing": 3.0, "mei": 2.0, "he": -8.0}  # 各轨相对伴奏的响度（dB）
STAGE_BALANCE = {"old": {"bed": -7.0, "he": -13.0}, "middle": {"bed": -1.5}}


class Clock:
    def __init__(self, bpm: float, bars=(0, BARS)):
        self.spb = 60.0 / bpm
        self.lo, self.hi = bars[0] * 4.0, bars[1] * 4.0

    def has(self, beat: float) -> bool:
        return self.lo <= beat < self.hi

    def t(self, beat: float) -> float:
        return (beat - self.lo) * self.spb

    @property
    def length(self) -> float:
        return (self.hi - self.lo) * self.spb


def _jit(rng, amount=0.006):
    return float(rng.uniform(-amount, amount))


# ---- 青：拨 ----

def voice_q(stage: str, ck: Clock, line=None) -> Mix:
    cfg = STAGES[stage]
    name, octv = cfg["q"]
    notes = line if line is not None else (Q_SPARSE if cfg["sparse"] else Q_FULL)
    rng = np.random.default_rng(11)
    mx = Mix(ck.length + 1.0)
    first_of_phrase = True
    prev_end = -99.0
    for beat, dur, deg, o in notes:
        if not ck.has(beat):
            continue
        m = P(deg, o + octv)
        t, d = ck.t(beat) + abs(_jit(rng)), dur * ck.spb
        vel = 0.72 + 0.12 * (deg in (6, 1)) + float(rng.uniform(-0.05, 0.05))
        first_of_phrase = beat - prev_end > 0.6
        prev_end = beat + dur
        if name == "music_box":
            mx.add(inst.music_box(m, d, round(vel, 2)), t, 0.5)
            if dur >= 1.5:  # 长音上面再点一个高八度，像梳齿多拨了一下
                mx.add(inst.music_box(m + 12, d * 0.5, 0.4), t + 0.5 * ck.spb, 0.3)
        elif name == "guitar":
            mx.add(inst.guitar(m, d * 1.15, round(vel, 2)), t, 0.95)
        elif name == "egtr":
            mx.add(inst.egtr(m, d * 1.25, round(vel, 2)), t, 0.9)
        elif name == "piano":
            mx.add(inst.piano(m, d * 1.5, round(vel * 0.9, 2)), t, 1.25)
            if dur >= 2:
                mx.add(inst.piano(m - 12, d * 1.5, 0.45), t + 0.012, 0.8)
        elif name == "sanxian":
            mx.add(inst.sanxian(m, d * 1.1, round(vel, 2), 2.0 if first_of_phrase else 0.0), t, 1.0)
            if first_of_phrase:  # 空弦垫一下
                mx.add(inst.sanxian(P(1, -2), d * 1.5, 0.5), max(0.0, t - 0.03), 0.45)
    return mx


# ---- 梅：吟 ----

def voice_m(stage: str, ck: Clock, line=None) -> np.ndarray:
    cfg = STAGES[stage]
    name, octv = cfg["m"]
    notes = line if line is not None else (M_SPARSE if cfg["sparse"] else M_FULL)
    seq = []
    prev_end = -99.0
    for beat, dur, deg, o in notes:
        if not ck.has(beat):
            continue
        m = P(deg, o + octv)
        t, d = ck.t(beat), dur * ck.spb
        vel = 0.74 + 0.1 * (dur >= 2) + 0.06 * (deg in (1, 2) and o == 1)
        first = beat - prev_end > 0.6
        prev_end = beat + dur
        if name == "recorder":
            seq.append((t, d * 0.9, m, vel))  # 吐音，音和音之间断开
        elif name == "erhu":
            if first and d > 0.5:  # 从下面滑上去
                seq.append((t, 0.07, m - 2, vel * 0.8))
                seq.append((t + 0.07, d - 0.07, m, vel))
            else:
                seq.append((t, d, m, vel))
        else:
            seq.append((t, d, m, vel))
    total = ck.length + 1.2
    if name == "harmonica":
        return inst.harmonica_line(seq, total, seed=21, level=0.62)
    if name == "erhu":
        return inst.sustained_line(seq, total, "erhu", seed=22, level=0.6, glide_scale=1.25)
    if name == "cello":
        return inst.sustained_line(seq, total, "cello", seed=23, level=0.7)
    if name == "lead":
        return inst.sustained_line(seq, total, "lead", seed=24, level=0.5)
    return inst.sustained_line(seq, total, "recorder", seed=25, level=0.55)


# ---- 合 ----

def voice_he(ck: Clock, model: str = "pad") -> np.ndarray:
    total = ck.length + 2.0
    lines = [[], []]
    for b, beats, name in chords():
        if not ck.has(b):
            continue
        for i, m in enumerate(CHORD[name][2]):
            lines[i].append((ck.t(b), beats * ck.spb, m, 0.7))
    out = np.zeros(sec(total))
    for i, ln in enumerate(lines):
        out += inst.ensemble_line(ln, total, model, seed=40 + i, level=0.5, voices=3, spread=8.0)
    return out


# ---- 伴奏 ----

def bed(stage: str, ck: Clock) -> Mix:
    rng = np.random.default_rng({"child": 1, "teen": 2, "young": 3, "middle": 4, "old": 5}[stage])
    mx = Mix(ck.length + 1.0)
    spb = ck.spb
    ch = [(b, beats, name) for b, beats, name in chords() if ck.has(b)]

    if stage == "child":
        for b, beats, name in ch:
            root, tones, _ = CHORD[name]
            pat = [tones[0], tones[2], tones[1], tones[2]]
            for i in range(int(beats * 2)):
                acc = 0.62 if i % 4 == 0 else (0.5 if i % 2 == 0 else 0.4)
                mx.add(inst.kalimba(pat[i % 4], 0.45, round(acc + float(rng.uniform(-0.04, 0.04)), 2)),
                       ck.t(b + i * 0.5) + abs(_jit(rng, 0.004)), 0.5, pan=0.18 * (1 if i % 2 else -1))
            mx.add(inst.bass(root, beats * spb * 0.9, 0.6), ck.t(b), 0.55)
        for bar in range(int(ck.lo / 4), int(ck.hi / 4)):
            for beat in (1, 3):  # 皮筋落地的那一下
                mx.add(inst.shaker(0.5, bar * 4 + beat), ck.t(bar * 4 + beat), 0.5, pan=0.3)
            if bar % 4 == 0:
                mx.add(inst.triangle(0.5), ck.t(bar * 4), 0.6, pan=-0.35)

    elif stage == "teen":
        for b, beats, name in ch:
            root, tones, _ = CHORD[name]
            pat = [root + 12, tones[1], tones[2], tones[1], tones[0], tones[1], tones[2], tones[1]]
            for i in range(int(beats * 2)):
                v = 0.62 if i == 0 else 0.46 + float(rng.uniform(-0.05, 0.05))
                mx.add(inst.guitar(pat[i % 8], 1.4 * spb, round(v, 2), True), ck.t(b + i * 0.5) + abs(_jit(rng, 0.007)),
                       1.0, pan=-0.12)
            mx.add(inst.bass(root, beats * spb * 0.95, 0.6), ck.t(b), 0.5)
        hiss = lp(colored(sec(ck.length), rng, -1.0), 7000) * db(-58)  # 随身听的底噪
        mx.add(fade(hiss, 0.3, 0.3), 0.0)

    elif stage == "young":
        for b, beats, name in ch:
            root, tones, he = CHORD[name]
            voicing = tones + [he[1] if he[1] not in tones else tones[0] + 12]
            hits = [(0.0, 1.4), (1.5, 1.6)] if beats >= 4 else [(0.0, 1.6)]
            for off, d in hits:
                for j, m in enumerate(voicing):
                    mx.add(inst.epiano(m, d * spb, 0.55), ck.t(b + off) + j * 0.006, 0.6, pan=0.25 * (j - 1.5) / 1.5)
            mx.add(inst.bass(root, 1.3 * spb, 0.75, False), ck.t(b), 0.6)
            if beats >= 4:
                mx.add(inst.bass(root, 0.4 * spb, 0.55, False), ck.t(b + 1.5), 0.55)
                mx.add(inst.bass(root + 7, 0.9 * spb, 0.6, False), ck.t(b + 2), 0.55)
                mx.add(inst.bass(root + 12, 0.4 * spb, 0.5, False), ck.t(b + 3.5), 0.5)
            else:
                mx.add(inst.bass(root + 7, 0.4 * spb, 0.5, False), ck.t(b + 1.5), 0.5)
        for bar in range(int(ck.lo / 4), int(ck.hi / 4)):
            b0 = bar * 4
            quiet = 8 <= bar < 12  # B 段把鼓撤掉，喘口气
            for i in range(8):
                mx.add(inst.hat(0.45 if i % 2 == 0 else 0.26, bar * 8 + i), ck.t(b0 + i * 0.5), 0.5 if not quiet else 0.3, pan=0.3)
            if quiet:
                continue
            mx.add(inst.kick(0.75), ck.t(b0), 0.5)
            mx.add(inst.kick(0.6), ck.t(b0 + 2.5), 0.45)
            mx.add(inst.rim(0.6, bar), ck.t(b0 + 1), 0.55, pan=-0.2)
            mx.add(inst.rim(0.65, bar + 50), ck.t(b0 + 3), 0.55, pan=-0.2)

    elif stage == "middle":
        total = ck.length + 2.0
        lines = [[], [], []]
        for b, beats, name in ch:
            root, tones, _ = CHORD[name]
            for i, m in enumerate(tones):
                lines[i].append((ck.t(b), beats * spb, m, 0.65))
            mx.add(inst.piano(root, 2.2 * spb, 0.5), ck.t(b), 1.2, pan=-0.15)
            if beats >= 4:
                mx.add(inst.piano(root + 7, 1.6 * spb, 0.4), ck.t(b + 1) + abs(_jit(rng)), 1.0, pan=-0.1)
                mx.add(inst.piano(root + 12, 2.0 * spb, 0.42), ck.t(b + 2) + abs(_jit(rng)), 1.0, pan=-0.05)
        for i, ln in enumerate(lines):
            y = inst.ensemble_line(ln, total, "pad", seed=60 + i, level=0.5, voices=3, spread=10.0)
            mx.add(y, 0.0, 0.5, pan=(-0.4, 0.0, 0.4)[i])

    elif stage == "old":
        total = ck.length + 2.0
        low, high = [], []
        for b, beats, name in ch:
            bar = int(b // 4)
            pair = (43, 50) if bar in (8, 9) else ((45, 52) if bar in (10, 11) else (38, 45))  # 平时就是 D 和 A 两个音
            low.append((ck.t(b), beats * spb, pair[0], 0.6))
            high.append((ck.t(b), beats * spb, pair[1], 0.5))
        for i, ln in enumerate((low, high)):
            y = inst.ensemble_line(ln, total, "organ", seed=70 + i, level=0.5, voices=2, spread=6.0)
            mx.add(y, 0.0, 0.42, pan=-0.2 + 0.4 * i)
        for bar in range(int(ck.lo / 4), int(ck.hi / 4)):
            if bar % 8 == 0:
                mx.add(inst.triangle(0.35), ck.t(bar * 4), 0.4, pan=0.3)
    return mx


# ------------------------------------------------------------ 成品 ----

def _space(x, stage: str, seed: int, extra_wet: float = 0.0):
    cfg = STAGES[stage]
    return reverb(x, rt60=cfg["rt"], wet=cfg["wet"] + extra_wet, bright=4500, seed=seed)


def arrange(stage: str, bpm: float | None = None, bars=(0, BARS), lines=None) -> dict:
    """渲染一个阶段的四条分轨（带混响，未折回循环）。lines 可以替换两条旋律（做默契乐句用）。"""
    cfg = STAGES[stage]
    ck = Clock(bpm or cfg["bpm"], bars)
    q = voice_q(stage, ck, None if lines is None else lines[0]).buf.mean(axis=1)
    m = voice_m(stage, ck, None if lines is None else lines[1])
    if cfg["q"][0] == "egtr":
        q = echo(q, 0.75 * ck.spb, 0.4, 0.22, 2600, 3).mean(axis=1)
    if cfg["m"][0] == "lead":
        m = echo(m, 0.75 * ck.spb, 0.4, 0.2, 2400, 3).mean(axis=1)
    stems = {
        "bed": _space(bed(stage, ck).buf, stage, 3),
        "qing": _space(to_stereo(q, PAN_Q), stage, 5, 0.04),
        "mei": _space(to_stereo(m, PAN_M), stage, 9, 0.04),
        "he": _space(voice_he(ck, "organ" if stage == "old" else "pad") * 0.55, stage, 13, 0.08),
    }
    return dict(stems=stems, length=ck.length, spb=ck.spb)


def stage_loops(stage: str) -> dict:
    """可循环的四条分轨 + 元数据。四条用同一个增益，全开时落在目标响度上。"""
    a = arrange(stage)
    n = sec(a["length"])
    stems = {k: loop_wrap(v, n) for k, v in a["stems"].items()}
    if stage == "teen":  # 磁带的抖晃，四条一起抖
        stems = {k: warp(v, 4.0, (29, 263), a["length"]) for k, v in stems.items()}
    # 平衡：两条旋律各比伴奏响一点，「合」垫在最底下。按各轨自己出声的部分量响度。
    rel = dict(BALANCE, **STAGE_BALANCE.get(stage, {}))
    base = lufs(np.concatenate([stems["bed"], stems["bed"]]))
    for k in ("qing", "mei", "he"):
        stems[k] = stems[k] * db(base + rel[k] - rel["bed"] - lufs(np.concatenate([stems[k], stems[k]])))
    full = sum(stems.values())
    g = db(TARGET_LUFS - lufs(np.concatenate([full, full])))
    over = peak_db(full * g) + 2.0
    if over > 0:
        g *= db(-over)
    stems = {k: v * g for k, v in stems.items()}
    return dict(stems=stems, length=n / 44100.0, bpm=STAGES[stage]["bpm"], bar=4 * a["spb"])


# ---- 默契乐句：不循环的小段，叠在配乐上面 ----

CALL_Q = [(0, 1, 3, 0), (1, 1, 5, 0), (2, 2, 6, 0)]            # 小皮球——
CALL_M = [(0, 1, 5, 0), (1, 1, 3, 0), (2, 2, 2, 0)]            # 架脚踢——
RUN_UP = [(0, .5, 3, 0), (.5, .5, 5, 0), (1, .5, 6, 0), (1.5, .5, 1, 1)]
RUN_DOWN = [(0, .5, 6, 0), (.5, .5, 5, 0), (1, .5, 3, 0), (1.5, .5, 2, 0)]


def _shift(line, beats):
    return [(b + beats, d, deg, o) for b, d, deg, o in line]


def stinger(stage: str, kind: str) -> np.ndarray:
    cfg = STAGES[stage]
    bpm = min(cfg["bpm"], 88)  # 快的阶段也别抢
    ck = Clock(bpm, (0, 3))
    spb = ck.spb
    if kind == "call_qing":
        q = voice_q(stage, ck, CALL_Q).buf
        return level(trim(_space(to_stereo(q.mean(axis=1), PAN_Q), stage, 5, 0.06)), TARGET_LUFS + 2, -3)
    if kind == "call_mei":
        m = voice_m(stage, ck, CALL_M)
        return level(trim(_space(to_stereo(m, PAN_M), stage, 9, 0.06)), TARGET_LUFS + 2, -3)
    mx = Mix(ck.length + 1.0)
    if kind == "resonance":
        # 青往上，梅接着往下，落在同一个音上；底下把和弦托开
        q = voice_q(stage, ck, RUN_UP + [(4, 4, 1, 0)]).buf.mean(axis=1)
        m = voice_m(stage, ck, _shift(RUN_DOWN, 2) + [(4, 4, 1, 0)])
        mx.add(q, 0, 1.0, PAN_Q)
        mx.add(m, 0, 1.0, PAN_M)
        t0 = ck.t(4)
        for j, mm in enumerate([50, 57, 64, 66, 69, 74, 78]):
            mx.add(inst.kalimba(mm, 1.0, 0.55), t0 + j * 0.07, 0.4, pan=-0.4 + 0.13 * j)
        mx.add(inst.music_box(P(1, 2), 1.0, 0.5), t0 + 0.55, 0.3, pan=0.2)
        mx.add(inst.music_box(P(5, 2), 1.0, 0.45), t0 + 0.75, 0.28, pan=-0.2)
        pad = inst.ensemble_line([(t0, 3.5 * spb, 62, 0.7), ], ck.length + 1.0, "pad", 81) + \
            inst.ensemble_line([(t0, 3.5 * spb, 66, 0.6)], ck.length + 1.0, "pad", 82) + \
            inst.ensemble_line([(t0, 3.5 * spb, 57, 0.6)], ck.length + 1.0, "pad", 83)
        mx.add(pad, 0, 0.5)
        mx.add(inst.bass(38, 3.0 * spb, 0.7), t0, 0.6)
    elif kind == "mismatch":
        # 两个人同时开口，梅晚了十六分之一拍（套印没对准），一个往上走一个往下走，最后隔着九度各停各的；
        # 低音从底下垫一个 G，把这点别扭接住，不让话掉地上
        q = voice_q(stage, ck, RUN_UP + [(2.0, 4.5, 2, 1)]).buf.mean(axis=1)
        m = voice_m(stage, ck, _shift(RUN_DOWN[:3], 0.25) + [(1.75, 4.75, 1, 0)])
        mx.add(q, 0, 1.0, PAN_Q)
        mx.add(m, 0, 1.0, PAN_M)
        mx.add(inst.woodblock(0.6, 0.9, 3), ck.t(2.25), 0.5, pan=0.1)
        t0 = ck.t(3.5)
        mx.add(inst.bass(43, 3.0 * spb, 0.7), t0, 0.7)
        pad = inst.ensemble_line([(t0, 3.0 * spb, 59, 0.6)], ck.length + 1.0, "pad", 84) + \
            inst.ensemble_line([(t0, 3.0 * spb, 66, 0.5)], ck.length + 1.0, "pad", 85)
        mx.add(pad, 0, 0.45)
    y = _space(mx.buf, stage, 17, 0.06)
    return level(trim(y), TARGET_LUFS + 3, -2)


# ---- 标题、投胎、一生 ----

def title_loop() -> dict:
    """标题：八音盒一个人把两个人的话都说了。慢，像回忆。"""
    ck = Clock(76)
    mx = Mix(ck.length + 2)
    rng = np.random.default_rng(5)
    for beat, dur, deg, o in Q_FULL:
        mx.add(inst.music_box(P(deg, o + 1), dur * ck.spb, 0.8), ck.t(beat) + abs(_jit(rng, 0.012)), 0.5, pan=-0.2)
    for beat, dur, deg, o in M_FULL:
        if beat >= 60:
            continue
        mx.add(inst.music_box(P(deg, o), dur * ck.spb, 0.6), ck.t(beat) + abs(_jit(rng, 0.012)), 0.42, pan=0.2)
    for b, beats, name in chords():
        root, tones, _ = CHORD[name]
        mx.add(inst.music_box(root + 24, beats * ck.spb, 0.5), ck.t(b), 0.3)
    he = voice_he(ck) * 0.45
    y = reverb(mx.buf, 2.2, 0.3, 4200, 3) + 0.0
    hw = reverb(he, 2.2, 0.35, 4200, 13)
    n = sec(ck.length)
    out = loop_wrap(y, n) + loop_wrap(hw, n)
    return dict(audio=level(out, -23.0, -3), length=ck.length)


def roll_loop() -> dict:
    """投胎：悬着的八小节，没有旋律，等一个结果。"""
    ck = Clock(92, (0, 8))
    mx = Mix(ck.length + 1)
    rng = np.random.default_rng(9)
    prog = ["Dadd9", "Dadd9", "Gmaj7", "Gmaj7", "Bm7", "Bm7", "A7sus4", "A7sus4"]
    for bar, name in enumerate(prog):
        root, tones, he = CHORD[name]
        pat = [tones[0], tones[2], he[1], tones[2], tones[1], tones[2], he[1], tones[1]]
        for i in range(8):
            if rng.uniform() < 0.12 and i % 2 == 1:
                continue
            mx.add(inst.kalimba(pat[i], 0.4, round(0.5 + 0.12 * (i % 4 == 0), 2)), ck.t(bar * 4 + i * 0.5), 0.5,
                   pan=0.25 * np.sin(i * 1.3))
        mx.add(inst.bass(root, 3.5 * ck.spb, 0.55), ck.t(bar * 4), 0.5)
        mx.add(inst.shaker(0.4, bar), ck.t(bar * 4 + 1), 0.4, pan=0.3)
        mx.add(inst.shaker(0.4, bar + 30), ck.t(bar * 4 + 3), 0.4, pan=0.3)
        if bar % 2 == 0:
            mx.add(inst.music_box(tones[2] + 24, 1.0, 0.5), ck.t(bar * 4 + 2.5), 0.22, pan=-0.3)
    n = sec(ck.length)
    return dict(audio=level(loop_wrap(reverb(mx.buf, 1.4, 0.22, 4500, 3), n), -22.0, -3), length=ck.length)


def ending() -> dict:
    """一生：同一个主题从头到尾走一遍，每四小节老一个阶段，最后八音盒一个人收尾。不循环。"""
    bpm = 74
    order = [("child", (0, 4)), ("teen", (4, 8)), ("young", (8, 12)), ("middle", (12, 14)), ("old", (14, 16))]
    spb = 60.0 / bpm
    mx = Mix(16 * 4 * spb + 12)
    for stage, bars in order:
        a = arrange(stage, bpm, bars)
        g = {"child": 0.0, "teen": 2.0, "young": 0.0, "middle": 3.0, "old": 3.0}[stage]
        for k, v in a["stems"].items():
            w = 1.0 if k != "he" else (0.5 if bars[0] >= 8 else 0.0)
            mx.add(v, bars[0] * 4 * spb, db(g) * w)
    # 最后那个合音之后，八音盒把「小皮球」再说一遍，越说越慢
    t = 16 * 4 * spb + 1.2
    coda = Mix(9)
    for i, (deg, gap) in enumerate([(3, 0.0), (5, 1.0), (6, 2.25)]):
        coda.add(inst.music_box(P(deg, 1), 2.0, 0.7 - 0.08 * i), gap, 0.5)
    mx.add(reverb(coda.buf, 2.6, 0.35, 4200, 3), t)
    y = trim(mx.buf, -62, 1.5)
    return dict(audio=level(y, -20.0, -2), length=len(y) / 44100.0)
