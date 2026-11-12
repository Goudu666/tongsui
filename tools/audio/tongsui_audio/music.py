"""《同岁》的配乐：一个主题，五个人生阶段，八条分轨。

主题只有 16 小节，D 宫五声。节奏的骨头取自楼下跳皮筋的口诀「小皮球，架脚踢，
马兰开花二十一」：三下一停，三下一停，四个快的接三个慢的。

两位玩家各有一条旋律线，写成相声里的一逗一捧：
  第 1~4 小节   青抛两小节，梅接两小节
  第 5~8 小节   同上，换一种说法
  第 9~12 小节  反过来，梅抛，青接
  第 13~16 小节 一人一小节 → 一人半小节（青往上走，梅往下走）→ 落在同一个音上
一个人听，只有半边话；两个人走近了，话才不掉在地上。

分轨（同一阶段的八个文件采样数完全相同，引擎里同步播放，各自调音量）：
  bed     伴奏，一直在
  qing    青的旋律（拨的乐器）              ← A 曲
  mei     梅的旋律（吟的乐器）
  qing_b  青的 B 曲：同一套和弦、同一长度，主题的变奏  ← B 曲，和 A 轮换着放
  mei_b   梅的 B 曲
  he      「合」：五声旋律里没有的那两个音（4 和 7）藏在这条和声里，
          只有两人同框而且默契够了才听得见
  morn    早上 / 下雪：亮、稀、高音点
  eve     傍晚 / 晚上 / 下雨：暖、低、长音，一条柔的副旋律，晚上拿它当摇篮曲的底
"""
from __future__ import annotations

import numpy as np

from . import inst
from .dsp import (Mix, colored, db, echo, fade, hp, level, loop_wrap, lp, lufs, peak, peak_db, reverb, sec, to_stereo,
                  trim, warp)

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
    (12, 2.5, 3, 0),
    (24, 1, 5, 0), (25, 1, 3, 0), (26, 2, 2, 0),
    (28, 1, 1, 0), (29, 1, 6, -1), (30, 2, 5, -1),
    (32, 3, 1, 1), (35, 1, 6, 0),
    (36, 3.5, 2, 1),
    (52, 2, 5, 0), (54, 2, 2, 0),
    (58, 1, 5, 0), (59, 1, 2, 0),
    (60, 4, 1, 0),
]

# ------------------------------------------------------------ B 曲 ----
# 第二支曲子：同一套和弦，同一长度，谁先说谁后说也不变（青抛梅接，第 9 小节起梅抛青接，最后落在同一个音上），
# 说法换了。五个阶段各有性格：
#   童年  俏    附点、蹦跳，「小皮球」倒过来唱（6 5 3），一句一个小拐弯
#   少年  抒情  主题放慢一倍（扩充），长音多，一口气连着说
#   青年  切分  抢半拍进来、拖到下一小节，最后两个人一起抢在第四拍后半落下
#   中年  宽    音少、跨度大、每句落在长音上
#   老年  稀    只剩骨头，一小节一两个音（QB_SPARSE / MB_SPARSE）

QB_CHILD = [
    (0, .75, 6, 0), (.75, .25, 5, 0), (1, 1, 3, 0), (2.5, .5, 5, 0), (3, .5, 6, 0),   # 球皮小——倒过来
    (4, .75, 1, 1), (4.75, .25, 6, 0), (5, 1, 5, 0), (6, 1.5, 3, 0),
    (16, .5, 5, 0), (16.5, .5, 6, 0), (17, .5, 1, 1), (17.5, .5, 2, 1), (18, 1.5, 1, 1),
    (20, .75, 6, 0), (20.75, .25, 1, 1), (21, 1, 6, 0), (22, 1.5, 5, 0),
    (40, .5, 6, 0), (40.5, .5, 1, 1), (41, 1, 2, 1), (42, .5, 1, 1), (42.5, .5, 6, 0), (43, 1, 5, 0),
    (44, .75, 6, 0), (44.75, .25, 1, 1), (45, 2.5, 5, 0),
    (48, .5, 3, 0), (48.5, .5, 5, 0), (49, .5, 6, 0), (49.5, .5, 5, 0), (50, 1.5, 3, 0),
    (56, .5, 2, 0), (56.5, .5, 3, 0), (57, .5, 5, 0), (57.5, .5, 6, 0),
    (60, 3, 1, 0),
]
MB_CHILD = [
    (8, .5, 6, 0), (8.5, .5, 5, 0), (9, .5, 3, 0), (9.5, .5, 2, 0), (10, 1, 3, 0), (11, 1, 5, 0),
    (12, .75, 6, 0), (12.75, .25, 5, 0), (13, 1, 3, 0), (14, 2, 5, 0),
    (24, .5, 3, 0), (24.5, .5, 2, 0), (25, .5, 3, 0), (25.5, .5, 5, 0), (26, 1, 6, 0), (27, 1, 5, 0),
    (28, .5, 5, 0), (28.5, .5, 6, 0), (29, .5, 1, 1), (29.5, .5, 6, 0), (30, 2, 5, 0),
    (32, .75, 1, 1), (32.75, .25, 2, 1), (33, 1, 1, 1), (34, .5, 6, 0), (34.5, .5, 5, 0), (35, 1, 6, 0),
    (36, .5, 1, 1), (36.5, .5, 6, 0), (37, 2.5, 5, 0),
    (52, .5, 6, 0), (52.5, .5, 5, 0), (53, 1, 3, 0), (54, 1.5, 5, 0),
    (58, .5, 5, 0), (58.5, .5, 3, 0), (59, .5, 2, 0), (59.5, .5, 3, 0),
    (60, 3, 1, 0),
]
QB_TEEN = [
    (0, 1.5, 3, 0), (1.5, .5, 5, 0), (2, 2, 6, 0),
    (4, 1.5, 5, 0), (5.5, .5, 3, 0), (6, 2, 2, 0),
    (16, 1.5, 5, 0), (17.5, .5, 6, 0), (18, 2, 1, 1),
    (20, 1.5, 2, 1), (21.5, .5, 1, 1), (22, 2, 6, 0),
    (40, 2, 1, 1), (42, 1, 6, 0), (43, 1, 5, 0),
    (44, 2, 6, 0), (46, 2, 5, 0),
    (48, 1.5, 3, 0), (49.5, .5, 5, 0), (50, 2, 6, 0),
    (56, 1, 3, 0), (57, 1, 5, 0),
    (60, 4, 1, 0),
]
MB_TEEN = [
    (8, 2, 6, 0), (10, 1, 5, 0), (11, 1, 3, 0),
    (12, 2, 3, 0), (14, 2, 2, 0),
    (24, 1.5, 5, 0), (25.5, .5, 6, 0), (26, 2, 1, 1),
    (28, 1, 6, 0), (29, 1, 5, 0), (30, 2, 2, 0),
    (32, 3, 6, 0), (35, 1, 1, 1),
    (36, 1.5, 2, 1), (37.5, .5, 1, 1), (38, 2, 6, 0),
    (52, 1.5, 5, 0), (53.5, .5, 3, 0), (54, 2, 2, 0),
    (58, 1, 5, 0), (59, 1, 2, 0),
    (60, 4, 1, 0),
]
QB_YOUNG = [
    (0, .5, 3, 0), (.5, .5, 5, 0), (1.5, 1.5, 6, 0), (3.5, 1, 5, 0),            # 抢半拍
    (4.5, .5, 3, 0), (5.5, 2, 2, 0),
    (16, .5, 5, 0), (16.5, .5, 6, 0), (17.5, 1.5, 1, 1), (19.5, 1, 6, 0),
    (20.5, .5, 5, 0), (21.5, 2, 3, 0),
    (40, .5, 2, 1), (40.5, 1, 1, 1), (41.5, 1.5, 6, 0), (43.5, 3, 5, 0),
    (48, .5, 3, 0), (48.5, .5, 5, 0), (49.5, 1.5, 6, 0),
    (56.5, .5, 3, 0), (57, .5, 5, 0), (57.5, .5, 6, 0),
    (59.5, 4, 1, 0),                                                             # 两个人一起抢着落下
]
MB_YOUNG = [
    (8, .5, 6, 0), (8.5, .5, 5, 0), (9, .5, 6, 0), (9.5, 1, 1, 1), (10.5, 1, 6, 0), (11.5, 1.5, 5, 0),
    (13, .5, 3, 0), (13.5, 2.5, 2, 0),
    (24, .5, 5, 0), (24.5, .5, 3, 0), (25, .5, 5, 0), (25.5, 1, 6, 0), (26.5, 1, 5, 0), (27.5, 1.5, 2, 0),
    (29, .5, 1, 0), (29.5, 2.5, 6, -1),
    (32, .5, 1, 1), (32.5, 1, 6, 0), (33.5, 1, 1, 1), (34.5, 1.5, 2, 1),
    (36.5, .5, 1, 1), (37, .5, 6, 0), (37.5, 2.5, 5, 0),
    (52.5, .5, 5, 0), (53, .5, 3, 0), (53.5, 2, 2, 0),
    (58, .5, 5, 0), (58.5, .5, 3, 0), (59, .5, 2, 0),
    (59.5, 4, 1, 0),
]
QB_MIDDLE = [
    (0, 1, 3, 0), (1, 3, 6, 0),
    (4, 1, 5, 0), (5, 3, 2, 0),
    (16, 1, 5, 0), (17, 3, 2, 1),
    (20, 1, 1, 1), (21, 3, 6, 0),
    (40, 2, 6, 0), (42, 2, 3, 0),
    (44, 4, 5, 0),
    (48, 1, 3, 0), (49, 3, 6, 0),
    (56, 1, 5, 0), (57, 1, 6, 0),
    (60, 4, 1, 0),
]
MB_MIDDLE = [
    (8, 1, 6, 0), (9, 3, 1, 1),
    (12, 2, 6, 0), (14, 2, 5, 0),
    (24, 1, 5, 0), (25, 3, 3, 0),
    (28, 2, 2, 0), (30, 2, 5, -1),
    (32, 1, 6, 0), (33, 3, 1, 1),
    (36, 2, 3, 1), (38, 2, 2, 1),
    (52, 1, 5, 0), (53, 3, 2, 0),
    (58, 2, 5, 0),
    (60, 4, 1, 0),
]
QB_SPARSE = [
    (0, 2, 6, 0), (2, 2, 5, 0),
    (4, 4, 3, 0),
    (16, 2, 6, 0), (18, 2, 1, 1),
    (20, 4, 5, 0),
    (40, 2, 1, 1), (42, 2, 6, 0),
    (44, 4, 5, 0),
    (48, 2, 6, 0), (50, 2, 5, 0),
    (56, 2, 3, 0),
    (60, 4, 1, 0),
]
MB_SPARSE = [
    (8, 2, 5, 0), (10, 2, 6, 0),
    (12, 2, 3, 0), (14, 2, 2, 0),
    (24, 2, 3, 0), (26, 2, 5, 0),
    (28, 4, 6, -1),
    (32, 3, 2, 1), (35, 1, 1, 1),
    (36, 4, 6, 0),
    (52, 2, 3, 0), (54, 2, 2, 0),
    (58, 2, 2, 0),
    (60, 4, 1, 0),
]
B_LINES = {
    "child": (QB_CHILD, MB_CHILD),
    "teen": (QB_TEEN, MB_TEEN),
    "young": (QB_YOUNG, MB_YOUNG),
    "middle": (QB_MIDDLE, MB_MIDDLE),
    "old": (QB_SPARSE, MB_SPARSE),
}

# 傍晚那一层的副旋律：一个和弦一两个音，只走和弦里的五声音，像哄孩子睡觉时哼的。老年会再拆稀。
EVE_LINE = [
    (0, 3, 3, 0), (3, 1, 5, 0),
    (4, 3.5, 3, 0),
    (8, 2, 1, 0), (10, 2, 6, -1),
    (12, 2, 2, 0), (14, 1.5, 1, 0),
    (16, 3, 5, -1), (19, 1, 3, 0),
    (20, 3.5, 5, 0),
    (24, 2, 3, 0), (26, 2, 1, 0),
    (28, 3.5, 2, 0),
    (32, 4, 6, -1),
    (36, 2, 5, -1), (38, 1.5, 3, 0),
    (40, 4, 2, 0),
    (44, 2, 1, 0), (46, 1.5, 2, 0),
    (48, 4, 3, 0),
    (52, 2, 1, 0), (54, 2, 6, -1),
    (56, 2, 6, -1), (58, 2, 5, -1),
    (60, 3.5, 5, -1),
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


def chord_at(beat: float) -> str:
    for b, beats, name in chords():
        if b <= beat % BEATS < b + beats:
            return name
    return "D"


# ---- 哪些音不打架 ----
PENTA = {0, 2, 4, 7, 9}  # D 宫五声，相对 D 的半音数


def safe_pcs(name: str) -> set:
    """和弦里本来就有的五声音（相对 D 的半音数）。早上、傍晚那两层只用这些：垫着、挂着也不会磨。"""
    root, tones, he = CHORD[name]
    return {(m - KEY) % 12 for m in [root] + tones + he} & PENTA


# 旋律可以用全部五声音，只躲两处：F#m7 上的 D（小六度，磨），A7sus4 上长时间的 F#（和 sus 的 G 只差半音）
_AVOID = {"F#m7": {0}, "A7sus4": {4}}


def clashes(line, strict: bool = False):
    """查一条谱子：不在五声里的音，或者在和弦上挂了超过半拍的「磨」音。strict=True 时只许 safe_pcs。
    返回 [(拍, 级, 和弦), ...]，空表就是干净的。"""
    bad = []
    for beat, dur, deg, o in line:
        pc = (P(deg, o) - KEY) % 12
        if pc not in PENTA:
            bad.append((beat, deg, "非五声"))
            continue
        for b, beats, name in chords():
            ov = min(beat + dur, b + beats) - max(beat, b)
            if ov <= 0:
                continue
            if strict and pc not in safe_pcs(name):
                bad.append((beat, deg, name))
            elif not strict and ov > 0.5 and pc in _AVOID.get(name, ()):
                bad.append((beat, deg, name))
    return bad


# ------------------------------------------------------------ 阶段 ----

STAGES = {
    # 11-12 画面定成像素：童年的青是芯片（小时候的游戏机），青年的梅是芯片主旋律，少年早上有掌机的小铃，
    # 中年一点电子音都没有，老年早上童年那串芯片小铃又回来了
    "child": dict(bpm=96, q=("chip", 1), m=("recorder", 1), rt=1.3, wet=0.24, sparse=False),
    "teen": dict(bpm=84, q=("guitar", 0), m=("harmonica", 0), rt=1.5, wet=0.2, sparse=False),
    "young": dict(bpm=100, q=("egtr", 0), m=("pulse", 0), rt=1.8, wet=0.2, sparse=False),
    "middle": dict(bpm=72, q=("piano", 0), m=("cello", -1), rt=2.4, wet=0.28, sparse=False),
    # 老年 11-12 换掉了三弦、二胡、D-A 空五度长音（太像水墨）：颤音琴 + 单簧管，伴奏是暖垫和尼龙吉他，混响也短一点
    "old": dict(bpm=63, q=("vibes", 0), m=("clarinet", 0), rt=2.1, wet=0.25, sparse=True),
}
# 早上那一层：乐器、音区（MIDI 上下限）、每小节在第几拍点一下（按小节轮着用）、「泛音」长音垫多少
MORN = {
    "child": dict(inst="glock", lo=81, hi=93, pat=[[0, 1.5, 3], [.5, 2], [0, 2, 2.5], [1, 3]], glass=0.10),
    "teen": dict(inst="chip_blip", lo=74, hi=83, pat=[[0, 2.5], [1.5], [0, 3], [2]], glass=0.12),
    "young": dict(inst="chip_blip", lo=74, hi=86, pat=[[.5, 2.5], [1.5, 3.5], [0, 1.5], [2.5]], glass=0.10),
    "middle": dict(inst="celesta", lo=74, hi=88, pat=[[0, 1, 2], [3], [.5, 2], []], glass=0.12),
    "old": dict(inst="chip_blip", lo=74, hi=83, pat=[[0], [], [2], []], glass=0.08),  # 童年的那串芯片小铃回来了
}
# 傍晚那一层：副旋律的乐器和八度、底下的长音垫、远近（0 贴着，越大越远）
EVE = {
    "child": dict(lead="ocarina", oct=0, pad="strings", far=0.0),
    "teen": dict(lead="melodica", oct=0, pad="strings", far=0.25),
    "young": dict(lead="harmonica", oct=0, pad="warm", far=0.6),
    "middle": dict(lead="viola", oct=0, pad="strings", far=0.0),
    "old": dict(lead="flugel", oct=0, pad="warm", far=0.2, sparse=True),
}
PAN_Q, PAN_M = -0.28, 0.28
TARGET_LUFS = -20.0  # 四条原分轨（bed qing mei he）全开时的响度
# 各轨相对伴奏的响度（dB），按各轨自己出声的部分量。B 曲和 A 曲一样响；morn 浮在上面但比伴奏轻；
# eve 和伴奏差不多（傍晚伴奏退、它进，晚上伴奏撤了靠它托着两条旋律）。
BALANCE = {"bed": 0.0, "qing": 3.0, "mei": 2.0, "he": -8.0, "qing_b": 3.0, "mei_b": 2.0, "morn": -6.0, "eve": -1.5}
STAGE_BALANCE = {"old": {"bed": -3.0, "he": -11.0, "morn": -9.0, "eve": -4.0}, "middle": {"bed": -1.5, "eve": -2.5}}
STEM_KEYS = ("bed", "qing", "mei", "he", "qing_b", "mei_b", "morn", "eve")
# 伴奏在 250 Hz 附近挖一点（dB）：那一段几件乐器的基音和混响都挤在一起，是「浑」的来源
BED_DIP = {"child": -2.5, "teen": -4.5, "young": -2.0, "middle": -3.5, "old": -2.5}
# 旋律里低的那件（中年大提琴、青年合成主音）在 200 Hz 附近也让一点，不跟伴奏挤
MEL_DIP = {"young": -2.0, "middle": -2.0}
# 一遍主题里的大起伏（每小节 dB）：前两句慢慢起来，第 9~12 小节换梅先说的时候收一点，最后一句最满再落下。
# 首尾接得上，循环点不跳。
ARC_DB = [-1.0, -0.5, 0.0, -0.5, 0.0, 0.5, 1.0, 0.0, -1.5, -1.0, -0.5, -1.0, 0.0, 1.0, 1.5, 0.5]


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


BED_ARC = 1.4  # 伴奏跟着大起伏走得最多（原来一整遍几乎一样响，短时响度只差 1~2 dB）


def _arc(beat: float, amount: float = BED_ARC) -> float:
    """这一拍所在小节的大起伏，换成倍数。"""
    return db(ARC_DB[int(beat // 4) % BARS] * amount)


def _feel(notes, rng):
    """像人那样说一句话：往一句里最高的那个音使点劲，句尾轻一点，强拍稍重；
    一句的第一个音晚一丁点（换气），其余的前后差几毫秒。全用固定种子，所以每次生成一样。
    返回 [(音, 力度增减, 时间增减秒), ...]。"""
    out, cur, prev_end = [], [], -99.0
    phrases = []
    for n in notes:
        if cur and n[0] - prev_end > 0.6:
            phrases.append(cur)
            cur = []
        cur.append(n)
        prev_end = n[0] + n[1]
    if cur:
        phrases.append(cur)
    for ph in phrases:
        k = len(ph)
        pk = max(range(k), key=lambda i: (P(ph[i][2], ph[i][3]), -i))
        for i, n in enumerate(ph):
            shape = 1.0 - abs(i - pk) / max(1, k - 1) if k > 1 else 0.5
            dv = 0.06 * shape + 0.025 * (n[0] % 4 == 0) + float(rng.uniform(-0.035, 0.035))
            if i == k - 1 and k > 2 and n[1] < 2:
                dv -= 0.035
            dt = float(rng.uniform(0.002, 0.009)) if i == 0 else float(rng.uniform(-0.004, 0.004))
            out.append((n, dv, dt))
    return out


# ---- 青：拨 ----

def voice_q(stage: str, ck: Clock, line=None, seed: int = 11) -> Mix:
    cfg = STAGES[stage]
    name, octv = cfg["q"]
    notes = line if line is not None else (Q_SPARSE if cfg["sparse"] else Q_FULL)
    rng = np.random.default_rng(seed)
    mx = Mix(ck.length + 1.0)
    prev_end = -99.0
    for (beat, dur, deg, o), dv, dt in _feel(notes, rng):
        if not ck.has(beat):
            continue
        m = P(deg, o + octv)
        t, d = max(0.0, ck.t(beat) + dt), dur * ck.spb
        vel = round(float(np.clip((0.7 + 0.1 * (deg in (6, 1)) + dv) * _arc(beat, 0.6), 0.35, 1.0)), 2)
        first_of_phrase = beat - prev_end > 0.6
        prev_end = beat + dur
        if name == "chip":
            mx.add(inst.chip(m, d * 0.92, vel, 0.25), t, 0.55)
            if dur >= 1.5:  # 长音后面跟一个轻的回音，老游戏没有混响，只有这种「假回声」
                mx.add(inst.chip(m, d * 0.4, round(vel * 0.4, 2), 0.25), t + 0.75 * ck.spb, 0.3)
        elif name == "music_box":
            mx.add(inst.music_box(m, d, vel), t, 0.5)
            if dur >= 1.5:  # 长音上面再点一个高八度，像梳齿多拨了一下
                mx.add(inst.music_box(m + 12, d * 0.5, 0.4), t + 0.5 * ck.spb, 0.3)
        elif name == "guitar":
            mx.add(inst.guitar(m, d * 1.15, vel), t, 0.95)
        elif name == "egtr":
            mx.add(inst.egtr(m, d * 1.25, vel), t, 0.9)
        elif name == "piano":
            mx.add(inst.piano(m, d * 1.5, round(vel * 0.9, 2)), t, 1.25)
            if dur >= 2:
                mx.add(inst.piano(m - 12, d * 1.5, 0.45), t + 0.012, 0.8)
        elif name == "vibes":
            mx.add(inst.vibes(m, d * 1.6, round(vel * 0.9, 2)), t, 1.0)
            if dur >= 2:  # 长音下面轻轻带一个低八度，像左手顺手按了一下
                mx.add(inst.vibes(m - 12, d * 1.2, 0.4), t + 0.02, 0.45)
    return mx


# ---- 梅：吟 ----

def voice_m(stage: str, ck: Clock, line=None, seed: int = 0) -> np.ndarray:
    cfg = STAGES[stage]
    name, octv = cfg["m"]
    notes = line if line is not None else (M_SPARSE if cfg["sparse"] else M_FULL)
    rng = np.random.default_rng(31 + seed)
    seq = []
    prev_end = -99.0
    for (beat, dur, deg, o), dv, dt in _feel(notes, rng):
        if not ck.has(beat):
            continue
        m = P(deg, o + octv)
        t, d = max(0.0, ck.t(beat) + dt * 1.5), dur * ck.spb
        vel = 0.72 + 0.1 * (dur >= 2) + 0.06 * (deg in (1, 2) and o == 1) + 0.8 * dv
        vel = float(np.clip(vel * _arc(beat, 0.5), 0.4, 1.0))
        first = beat - prev_end > 0.6
        prev_end = beat + dur
        if name == "recorder":
            seq.append((t, d * float(rng.uniform(0.84, 0.92)), m, vel))  # 吐音，音和音之间断开，断多少每次不一样
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
        return inst.harmonica_line(seq, total, seed=21 + seed, level=0.62)
    if name == "erhu":
        return inst.sustained_line(seq, total, "erhu", seed=22 + seed, level=0.6, glide_scale=1.25)
    if name == "clarinet":
        return inst.sustained_line(seq, total, "clarinet", seed=26 + seed, level=0.62)
    if name == "cello":
        return inst.sustained_line(seq, total, "cello", seed=23 + seed, level=0.7)
    if name == "lead":
        return inst.sustained_line(seq, total, "lead", seed=24 + seed, level=0.5)
    if name == "pulse":
        return inst.ensemble_line(seq, total, "pulse", seed=27 + seed, level=0.5, voices=2, spread=6.0)
    return inst.sustained_line(seq, total, "recorder", seed=25 + seed, level=0.55)


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

    def at(beat, amount=0.004):  # 不全在格子上
        return max(0.0, ck.t(beat) + _jit(rng, amount))

    if stage == "child":
        for b, beats, name in ch:
            root, tones, _ = CHORD[name]
            ag = _arc(b)
            pat = [tones[0], tones[2], tones[1], tones[2]]
            if int(b // 4) % 4 == 3:  # 每句最后一小节倒着拨，不让耳朵记住一个死循环
                pat = [tones[2], tones[1], tones[0], tones[1]]
            n8 = int(beats * 2)
            for i in range(n8):
                if i % 2 == 1 and i < n8 - 1 and rng.uniform() < 0.1:
                    continue  # 偶尔漏拨一下
                acc = 0.62 if i % 4 == 0 else (0.5 if i % 2 == 0 else 0.4)
                mx.add(inst.kalimba(pat[i % 4], 0.45, round(acc + float(rng.uniform(-0.05, 0.05)), 2)),
                       at(b + i * 0.5), 0.5 * ag, pan=0.18 * (1 if i % 2 else -1))
            mx.add(inst.tri_bass(root + 12, beats * spb * 0.9, 0.6), ck.t(b), 0.6 * ag)
        for bar in range(int(ck.lo / 4), int(ck.hi / 4)):
            for beat in (1, 3):  # 皮筋落地的那一下（芯片的噪声鼓）
                mx.add(inst.chip_noise("hat", 0.6 * float(rng.uniform(0.85, 1.1)), bar * 4 + beat),
                       at(bar * 4 + beat, 0.006), 0.8 * _arc(bar * 4), pan=0.3)
            if bar % 4 == 0:
                mx.add(inst.triangle(0.5), ck.t(bar * 4), 0.6, pan=-0.35)

    elif stage == "teen":
        for b, beats, name in ch:
            root, tones, _ = CHORD[name]
            ag = _arc(b)
            pat = [root + 12, tones[1], tones[2], tones[1], tones[0], tones[1], tones[2], tones[1]]
            if int(b // 4) % 4 == 3:
                pat = [root + 12, tones[2], tones[1], tones[0], tones[1], tones[2], tones[1], tones[0]]
            for i in range(int(beats * 2)):
                v = 0.62 if i == 0 else 0.46 + float(rng.uniform(-0.06, 0.06))
                mx.add(inst.guitar(pat[i % 8], 1.4 * spb, round(v, 2), True), at(b + i * 0.5, 0.008),
                       1.0 * ag, pan=-0.12)
            mx.add(inst.bass(root, beats * spb * 0.95, 0.6), ck.t(b), 0.5 * ag)
        hiss = lp(colored(sec(ck.length), rng, -1.0), 7000) * db(-58)  # 随身听的底噪
        mx.add(fade(hiss, 0.3, 0.3), 0.0)

    elif stage == "young":
        for b, beats, name in ch:
            root, tones, he = CHORD[name]
            ag = _arc(b)
            voicing = tones + [he[1] if he[1] not in tones else tones[0] + 12]
            # 电钢的节奏型每四小节换一种（第 9~12 小节鼓撤了，就按住不动），不让一句话说四遍一模一样
            hits = YOUNG_COMP[int(b // 4) // 4 % 4] if beats >= 4 else [(0.0, 1.6)]
            for off, d in hits:
                spread = float(rng.uniform(0.004, 0.011))  # 手指按下去有先有后
                v = round(0.55 + float(rng.uniform(-0.05, 0.04)), 2)
                for j, m in enumerate(voicing):
                    mx.add(inst.epiano(m, d * spb, v), ck.t(b + off) + j * spread, 0.6 * ag, pan=0.25 * (j - 1.5) / 1.5)
            mx.add(inst.bass(root, 1.3 * spb, 0.75, False), ck.t(b), 0.6 * ag)
            if beats >= 4:
                mx.add(inst.bass(root, 0.4 * spb, 0.55, False), ck.t(b + 1.5), 0.55 * ag)
                mx.add(inst.bass(root + 7, 0.9 * spb, 0.6, False), ck.t(b + 2), 0.55 * ag)
                mx.add(inst.bass(root + 12, 0.4 * spb, 0.5, False), ck.t(b + 3.5), 0.5 * ag)
            else:
                mx.add(inst.bass(root + 7, 0.4 * spb, 0.5, False), ck.t(b + 1.5), 0.5 * ag)
        for bar in range(int(ck.lo / 4), int(ck.hi / 4)):
            b0 = bar * 4
            ag = _arc(b0)
            quiet = 8 <= bar < 12  # B 段把鼓撤掉，喘口气
            for i in range(8):
                v = (0.45 if i % 2 == 0 else 0.26) * float(rng.uniform(0.8, 1.15))
                mx.add(inst.chip_noise("hat", v, bar * 8 + i), at(b0 + i * 0.5), (0.9 if not quiet else 0.55) * ag, pan=0.3)
            if quiet:
                continue
            mx.add(inst.kick(0.75), ck.t(b0), 0.5 * ag)
            mx.add(inst.kick(0.6), ck.t(b0 + 2.5), 0.45 * ag)
            mx.add(inst.rim(0.6, bar), at(b0 + 1), 0.55 * ag, pan=-0.2)
            mx.add(inst.rim(0.65, bar + 50), at(b0 + 3), 0.55 * ag, pan=-0.2)
            if bar % 4 == 3:  # 句尾带一下轻的，像鼓手换句
                mx.add(inst.rim(0.3, bar + 90), at(b0 + 3.75), 0.4 * ag, pan=-0.2)

    elif stage == "middle":
        total = ck.length + 2.0
        lines = [[], [], []]
        for b, beats, name in ch:
            root, tones, _ = CHORD[name]
            ag = _arc(b)
            for i, m in enumerate(tones):
                lines[i].append((ck.t(b), beats * spb, m, 0.65 * ag))
            mx.add(inst.piano(root, 2.2 * spb, 0.5), ck.t(b), 1.2 * ag, pan=-0.15)
            if beats >= 4:
                mx.add(inst.piano(root + 7, 1.6 * spb, 0.4), at(b + 1, 0.006), 1.0 * ag, pan=-0.1)
                mx.add(inst.piano(root + 12, 2.0 * spb, 0.42), at(b + 2, 0.006), 1.0 * ag, pan=-0.05)
        for i, ln in enumerate(lines):
            y = inst.ensemble_line(ln, total, "pad", seed=60 + i, level=0.5, voices=3, spread=10.0)
            mx.add(y, 0.0, 0.4, pan=(-0.4, 0.0, 0.4)[i])

    elif stage == "old":
        # 暖垫按真的和弦走，尼龙吉他一小节拨四下（少年那把吉他，慢下来了），底下一点唱片的沙沙声
        total = ck.length + 2.0
        lines = [[], [], []]
        for b, beats, name in ch:
            root, tones, _ = CHORD[name]
            ag = _arc(b)
            for i, m in enumerate(tones):
                lines[i].append((ck.t(b), beats * spb, m, 0.6 * ag))
            pat = [root, tones[0], tones[1], tones[2]]
            for i in range(int(beats)):
                if i == 3 and rng.uniform() < 0.3:
                    continue
                v = 0.5 if i == 0 else 0.38 + float(rng.uniform(-0.05, 0.05))
                mx.add(inst.guitar(pat[i % 4] + (12 if i else 0), 1.8 * spb, round(v, 2), True), at(b + i, 0.01),
                       0.9 * ag, pan=-0.15)
        for i, ln in enumerate(lines):
            y = inst.ensemble_line(ln, total, "warm", seed=70 + i, level=0.5, voices=2, spread=7.0)
            mx.add(y, 0.0, 0.4, pan=(-0.35, 0.0, 0.35)[i])
        crackle = np.zeros(sec(ck.length))
        pops = rng.integers(0, len(crackle), int(ck.length * 9))
        crackle[pops] = rng.uniform(-1, 1, len(pops)) * rng.uniform(0.2, 1.0, len(pops)) ** 3
        crackle = lp(hp(crackle, 900), 6000) * db(-30) + lp(colored(len(crackle), rng, -1.0), 3500) * db(-62)
        mx.add(fade(crackle, 0.3, 0.3), 0.0)
    return mx


YOUNG_COMP = [
    [(0.0, 1.4), (1.5, 1.6)],
    [(0.0, 1.0), (1.5, 0.5), (2.5, 1.4)],
    [(0.0, 3.6)],
    [(0.0, 1.4), (1.5, 1.0), (3.5, 0.5)],
]


# ---- 早上：亮、稀、高 ----

def morn(stage: str, ck: Clock) -> Mix:
    """高音区一下一下地点，只用和弦里本来就有的五声音；底下挂一层很轻的「泛音」长音。"""
    cfg = MORN[stage]
    rng = np.random.default_rng(500 + list(STAGES).index(stage))
    hit = getattr(inst, cfg["inst"])
    mx = Mix(ck.length + 1.0)
    prev = None
    for bar in range(int(ck.lo / 4), int(ck.hi / 4)):
        offs = cfg["pat"][bar % len(cfg["pat"])]
        if bar == BARS - 1:
            offs = [0]  # 最后一小节两条旋律落在一起，上面只留一个点
        for off in offs:
            beat = bar * 4 + off
            pcs = safe_pcs(chord_at(beat))
            cand = [m for m in range(cfg["lo"], cfg["hi"] + 1) if (m - KEY) % 12 in pcs]
            if prev is None or prev not in cand:
                i = int(rng.integers(len(cand)))
            else:  # 往旁边走一两步，大多往下（像雪花往下落）
                j = cand.index(prev)
                step = int(rng.choice([-2, -1, -1, 1, 2]))
                i = int(np.clip(j + step, 0, len(cand) - 1))
                if i == j:
                    i = j - 1 if j > 0 else j + 1
            m = cand[i]
            prev = m
            vel = round(float(np.clip(rng.uniform(0.42, 0.6) * _arc(beat, 0.6), 0.3, 0.8)), 2)
            mx.add(hit(m, vel), max(0.0, ck.t(beat) + _jit(rng, 0.005)), 0.6,
                   pan=float(np.clip((m - (cfg["lo"] + cfg["hi"]) / 2) / 14.0, -0.5, 0.5)))
    # 「泛音」：两三个和弦音在很高的地方挂着，像早上的光
    total = ck.length + 2.0
    lines = [[], []]
    for b, beats, name in chords():
        if not ck.has(b):
            continue
        top = sorted(m for m in range(86, 99) if (m - KEY) % 12 in safe_pcs(name))[:2]
        for i, m in enumerate(top):
            lines[i].append((ck.t(b), beats * ck.spb, m, 0.6))
    for i, ln in enumerate(lines):
        y = inst.ensemble_line(ln, total, "glass", seed=520 + i, level=0.5, voices=2, spread=5.0)
        mx.add(y, 0.0, cfg["glass"], pan=-0.3 + 0.6 * i)
    return mx


# ---- 傍晚：暖、低、长 ----

def _thin(line):
    """拆稀：一小节只留第一个音，拉长到下一个留下的音。"""
    keep = []
    for beat, dur, deg, o in line:
        if keep and int(keep[-1][0] // 4) == int(beat // 4):
            continue
        keep.append([beat, dur, deg, o])
    for i in range(len(keep) - 1):
        keep[i][1] = min(4.0, keep[i + 1][0] - keep[i][0]) - 0.5
        if clashes([tuple(keep[i])], strict=True):  # 拉长以后碰到下一个和弦里没有的音，就在换和弦前收住
            keep[i][1] = next(bb + nb for bb, nb, _ in chords() if bb <= keep[i][0] < bb + nb) - keep[i][0]
    return [tuple(n) for n in keep]


def eve(stage: str, ck: Clock) -> np.ndarray:
    """低音弦乐（或暖垫）托着，上面一条柔的副旋律。只用和弦里本来就有的五声音。返回立体声。"""
    cfg = EVE[stage]
    rng = np.random.default_rng(600 + list(STAGES).index(stage))
    total = ck.length + 2.0
    spb = ck.spb
    # 垫：根音 + 往上八度附近的两个和弦音，开放排列，暖但不糊
    pads = [[], [], []]
    for b, beats, name in chords():
        if not ck.has(b):
            continue
        root = CHORD[name][0]
        pcs = safe_pcs(name)
        ups = [m for m in range(root + 12, root + 24) if (m - KEY) % 12 in pcs]
        voice = [root, ups[0], next((m for m in ups if m - ups[0] >= 3), ups[-1])]
        ag = _arc(b, 0.8)
        for i, m in enumerate(voice):
            pads[i].append((ck.t(b), beats * spb, m, (0.5, 0.62, 0.55)[i] * ag))
    out = np.zeros((sec(total), 2))
    for i, ln in enumerate(pads):
        y = inst.ensemble_line(ln, total, cfg["pad"], seed=610 + i, level=0.5, voices=3, spread=9.0)
        out += to_stereo(y, (0.0, -0.35, 0.35)[i]) * (0.45, 0.34, 0.32)[i]
    # 副旋律
    line = _thin(EVE_LINE) if cfg.get("sparse") else EVE_LINE
    seq = []
    for (beat, dur, deg, o), dv, dt in _feel(line, rng):
        if not ck.has(beat):
            continue
        vel = float(np.clip((0.62 + 0.8 * dv) * _arc(beat, 0.6), 0.4, 0.9))
        seq.append((max(0.0, ck.t(beat) + dt * 2), dur * spb, P(deg, o + cfg["oct"]), vel))
    if cfg["lead"] == "harmonica":
        lead = inst.sustained_line(seq, total, "harmonica", seed=630, level=0.5)
    else:
        lead = inst.sustained_line(seq, total, cfg["lead"], seed=630, level=0.55)
    if cfg["far"] > 0:  # 远处的：高频先没了
        lead = lp(lead, 5000 - 5000 * cfg["far"], 4)
    out += to_stereo(lead, 0.12) * 0.9
    out = hp(out, 45)
    return peak(out, 260, 0.9, -2.0)


# ------------------------------------------------------------ 成品 ----

def _space(x, stage: str, seed: int, extra_wet: float = 0.0):
    cfg = STAGES[stage]
    return reverb(x, rt60=cfg["rt"], wet=cfg["wet"] + extra_wet, bright=4500, seed=seed, low_cut=160.0)


def _narrow(x, width: float):
    """收窄立体声：side 乘 width。垫在后面的层不用那么宽，给两条旋律让出左右，也省一点码率。"""
    mid, side = (x[:, 0] + x[:, 1]) * 0.5, (x[:, 0] - x[:, 1]) * 0.5 * width
    return np.stack([mid + side, mid - side], axis=1)


def arrange(stage: str, bpm: float | None = None, bars=(0, BARS), lines=None, extra: bool = False) -> dict:
    """渲染一个阶段的分轨（带混响，未折回循环）。lines 可以替换两条旋律（做默契乐句用）。
    extra=True 时连 B 曲和早上 / 傍晚两层一起做（循环用）；默认只做原来那四条（一生那一页用）。"""
    cfg = STAGES[stage]
    ck = Clock(bpm or cfg["bpm"], bars)

    def melody(qline, mline, seed):
        q = voice_q(stage, ck, qline, seed=11 + seed).buf.mean(axis=1)
        m = voice_m(stage, ck, mline, seed=seed)
        if cfg["q"][0] == "egtr":
            q = echo(q, 0.75 * ck.spb, 0.4, 0.22, 2600, 3).mean(axis=1)
        if cfg["m"][0] in ("lead", "pulse"):
            m = echo(m, 0.75 * ck.spb, 0.4, 0.2, 2400, 3).mean(axis=1)
        if stage in MEL_DIP:
            m = peak(m, 210, 0.8, MEL_DIP[stage])
        return _space(to_stereo(q, PAN_Q), stage, 5, 0.04), _space(to_stereo(m, PAN_M), stage, 9, 0.04)

    qa, ma = melody(None if lines is None else lines[0], None if lines is None else lines[1], 0)
    b = bed(stage, ck).buf
    if BED_DIP[stage]:
        b = peak(b, 250, 0.9, BED_DIP[stage])
    stems = {
        "bed": _space(b, stage, 3),
        "qing": qa,
        "mei": ma,
        "he": _space(voice_he(ck, "pad") * 0.55, stage, 13, 0.08),
    }
    if extra:
        qb, mb = melody(*B_LINES[stage], 100)
        stems["qing_b"], stems["mei_b"] = qb, mb
        stems["morn"] = _narrow(_space(morn(stage, ck).buf, stage, 19, 0.12), 0.6)
        # 傍晚那层 8 kHz 以上本来就没东西，剩下的混响噪声切掉（暖，也省码率）
        stems["eve"] = _narrow(lp(_space(eve(stage, ck), stage, 23, 0.06 + 0.2 * EVE[stage]["far"]), 8000, 4), 0.5)
    return dict(stems=stems, length=ck.length, spb=ck.spb)


def stage_loops(stage: str) -> dict:
    """可循环的八条分轨 + 元数据。全部用同一个增益：四条原分轨全开时落在目标响度上，
    新加的四条按 BALANCE 相对伴奏摆好。同一阶段每条的采样数完全相同。"""
    a = arrange(stage, extra=True)
    n = sec(a["length"])
    stems = {k: loop_wrap(a["stems"][k], n) for k in STEM_KEYS}
    if stage == "teen":  # 磁带的抖晃，全部一起抖
        stems = {k: warp(v, 4.0, (29, 263), a["length"]) for k, v in stems.items()}
    # 平衡：两条旋律各比伴奏响一点，「合」垫在最底下。按各轨自己出声的部分量响度。
    rel = dict(BALANCE, **STAGE_BALANCE.get(stage, {}))
    base = lufs(np.concatenate([stems["bed"], stems["bed"]]))
    for k in STEM_KEYS[1:]:
        stems[k] = stems[k] * db(base + rel[k] - rel["bed"] - lufs(np.concatenate([stems[k], stems[k]])))
    full = stems["bed"] + stems["qing"] + stems["mei"] + stems["he"]
    g = db(TARGET_LUFS - lufs(np.concatenate([full, full])))
    # 峰值按最满的组合算（A 或 B 曲 + 两层全开），哪种组合都不削波
    worst = max(peak_db(stems["bed"] + stems[q] + stems[m] + stems["he"] + stems["morn"] + stems["eve"])
                for q, m in (("qing", "mei"), ("qing_b", "mei_b")))
    over = worst + 20 * np.log10(g) + 2.0
    if over > 0:
        g *= db(-over)
    stems = {k: v * g for k, v in stems.items()}
    if len({len(v) for v in stems.values()}) != 1:  # 差一个采样都会越放越错位
        raise ValueError("%s 的分轨不一样长：%s" % (stage, {k: len(v) for k, v in stems.items()}))
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
    """标题：芯片说青的半边，八音盒接梅的半边。慢，像回忆。"""
    ck = Clock(76)
    mx = Mix(ck.length + 2)
    rng = np.random.default_rng(5)
    for beat, dur, deg, o in Q_FULL:  # 青那半边是芯片（像素画面的声音），梅那半边还是八音盒
        mx.add(inst.chip(P(deg, o + 1), dur * ck.spb * 0.9, 0.7, 0.25), ck.t(beat) + abs(_jit(rng, 0.012)), 0.5, pan=-0.2)
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
        mx.add(inst.tri_bass(root + 12, 3.5 * ck.spb, 0.55), ck.t(bar * 4), 0.55)
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
    # 最后那个合音之后，童年那把芯片把「小皮球」再说一遍，越说越慢
    t = 16 * 4 * spb + 1.2
    coda = Mix(9)
    for i, (deg, gap) in enumerate([(3, 0.0), (5, 1.0), (6, 2.25)]):
        coda.add(inst.chip(P(deg, 1), 0.8 + 0.4 * i, 0.65 - 0.08 * i, 0.25), gap, 0.5)
    mx.add(reverb(coda.buf, 2.6, 0.35, 4200, 3), t)
    y = trim(mx.buf, -62, 1.5)
    return dict(audio=level(y, -20.0, -2), length=len(y) / 44100.0)
