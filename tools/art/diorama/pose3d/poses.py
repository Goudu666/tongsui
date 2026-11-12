#!/usr/bin/env python3
"""微缩模型小人的姿势：直接借 tools/art/actors.py、actor_acts.py 的骨架和二十套动作，算成 JSON 交给 three.js 搭人。

做法：拿一个「记账的画笔」去跑 actors.draw_person ——
  · 人身上的线条一概不记（3D 那边自己搭身子），只要它算出来的关节 J（髋、肩、脖子、头、两手、两肘）；
  · 腿按同一套 leg_points 再算一遍（膝、踝、脚跟、脚尖）；
  · 道具（本子、碗、球、车轱辘、风筝…）是在 hook 里画的：hook 期间画笔记下每一笔（形状、线、点、色块）和它在哪一层
    （back 身后、far 远侧手、body 身前、front 最前），3D 那边挤成小方块、管子、小球。
所以每一帧和墨线版、像素版是同一个意思，引擎那边的帧号不用动。

坐标：世界像素，x 向右（人朝右），y 向下，脚底在 (0, 0)。
"""
from __future__ import annotations

import copy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.dirname(os.path.dirname(HERE))  # tools/art
sys.path.insert(0, ART)
import actors  # noqa: E402
import actor_acts  # noqa: E402

STAGES = actors.STAGES
ROLES = actors.ROLES


# ----------------------------------------------------------------------
# 记账的画笔
# ----------------------------------------------------------------------

class Recorder:
    """和 actors.Painter 一样的接口；只在 hook 里记账。"""

    def __init__(self):
        self.ox = self.oy = 0.0
        self.xf = None
        self.rec = None      # 正在记的层（None = 不记）
        self.ops = []

    def _pts(self, pts):
        return [[round(x, 2), round(y, 2)] for x, y in pts]

    def _push(self, **op):
        if self.rec is not None:
            op["layer"] = self.rec
            op["i"] = len(self.ops)
            self.ops.append(op)

    def shape(self, pts, spec, line=actors.OUTLINE, line_color="ink"):
        self._push(t="shape", pts=self._pts(pts), spec=list(spec) if spec else None)

    def limb(self, pts, width, spec, line=actors.OUTLINE):
        self._push(t="line", pts=self._pts(pts), w=width, spec=list(spec) if spec else None)

    def line(self, pts, w=actors.OUTLINE, color="ink", density=None, closed=False):
        pts = list(pts)
        if closed:
            pts = pts + [pts[0]]
        self._push(t="line", pts=self._pts(pts), w=w, spec=[color, density])

    def dot(self, x, y, r, color="ink", density=None):
        self._push(t="dot", c=[round(x, 2), round(y, 2)], r=r, spec=[color, density])

    def blot(self, pts, color, density=None, flat=False):
        self._push(t="blot", pts=self._pts(pts), spec=[color, density])

    # draw_person / _head 里直接调的底层方法：一概不记
    def _fill(self, *a, **k):
        pass

    def _clear(self, *a, **k):
        pass

    def _paint(self, *a, **k):
        pass


def _noop(*a, **k):
    pass


# _head、_face 画的是 2D 的脸：3D 那边自己画，这里跳过省时间
actors._head = lambda p, b, hx, hy, r, blink, tilt, expr=None: None
actors._paper_band = _noop
actors._stripe = _noop


# ----------------------------------------------------------------------
# 体型：在 actors.build 上按「设计」改头身比
# ----------------------------------------------------------------------

def _foot_travel(b):
    """走一圈里近脚的脚踝相对髋前后走多远（量步幅用）。"""
    xs = []
    for i in range(32):
        ph = i / 32
        th = actors.periodic(actors.THIGH, ph) * b["stride"] + b.get("knee_bend", 0) * 0.4
        kn = actors.periodic(actors.KNEE, ph) * (0.6 + 0.4 * b["stride"]) + b.get("knee_bend", 0)
        _k, ankle, _h, _t = actors.leg_points((0, 0), th, kn, 0, b)
        xs.append(ankle[0])
    return max(xs) - min(xs)


def body(role, stage, design):
    """design：dict(head={stage: 倍数}, leg={stage: 倍数}, limb=倍数, …)。总身高不变（引擎按 HEIGHT 放气泡、名字）。"""
    return body_from(actors.build(role, stage), design)


def body_from(b, design):
    """同 body，从现成的体型改（街坊：tools/art/folks.py 的 look() 出来的）。"""
    stage = b["stage"]
    base_travel = _foot_travel(b)
    hk = design.get("head", {}).get(stage, 1.0)
    lk = design.get("leg", {}).get(stage, 1.0)
    old_head = b["head"]
    b["head"] = old_head * hk
    extra = (b["head"] - old_head) * 2 * 0.92  # 头大出来的那截（头中心在脖子上 0.92r）
    # 腿先按设计缩放，剩下的从躯干里扣
    leg0 = b["leg"]
    b["leg"] = leg0 * lk
    for k in ("thigh", "shin", "ankle"):
        b[k] *= lk
    b["torso"] = b["torso"] - extra - (b["leg"] - leg0)
    b["neck"] *= design.get("neck", 1.0)
    b["torso"] += b["neck"] / design.get("neck", 1.0) - b["neck"]
    b["torso"] = max(b["torso"], b["H"] * 0.17)
    for k in ("upper", "fore"):
        b[k] *= design.get("arm", {}).get(stage, 1.0)
    # 腿短了步子也短：把摆腿的幅度放大，走一整步还是前进那么多，脚不打滑
    b["stride"] *= base_travel / max(1e-6, _foot_travel(b))
    b["design"] = design.get("name", "")
    return b


# ----------------------------------------------------------------------
# 一帧
# ----------------------------------------------------------------------

def _legs(b, pose, hip):
    out = {}
    for leg in pose["legs"]:
        knee, ankle, heel, toe = actors.leg_points(hip, leg["thigh"], leg["knee"], leg["pitch"], b)
        out[leg["side"]] = dict(knee=knee, ankle=ankle, heel=heel, toe=toe)
    return out


def _r(v):
    if isinstance(v, (list, tuple)):
        return [_r(x) for x in v]
    if isinstance(v, float):
        return round(v, 2)
    return v


def frame(b, pose=None, blink=False, busy=None, wave=None, sit=False, expr=None, hook=None, seat=44.0, **_):
    """跑一遍 draw_person，收关节和道具。"""
    rec = Recorder()

    def wrapped(p, layer, J):
        if hook is None:
            return
        p.rec = layer
        hook(p, layer, J)
        p.rec = None

    pose = copy.deepcopy(pose)
    J = actors.draw_person(rec, b, pose, 0.0, 0.0, blink=blink, busy=busy, wave=wave, sit=sit, expr=expr, hook=wrapped, seat=seat)
    hip = J["hip"]
    legs = _legs(b, pose, hip)
    lean = pose["lean"]
    sh = J["shoulder"]
    hx, hy, hr = J["head"]
    f = dict(
        hip=hip, shoulder=sh, neck=J["neck"], head=[hx, hy], lean=lean, tilt=pose.get("tilt", 0.0),
        hand_near=J["hand_near"], hand_far=J["hand_far"], elbow_near=J["elbow_near"], elbow_far=J["elbow_far"],
        sh_near=(sh[0] + 1, sh[1] + 4), sh_far=(sh[0] - 3, sh[1] + 4),
        legs=legs, sit=bool(sit), seat=seat, expr=("blink" if blink and not expr else expr),
        busy=busy is not None, wave=wave is not None,
        cane=bool(b.get("cane")) and not pose.get("no_cane") and busy is None and wave is None,
        props=rec.ops,
    )
    return _r(f)


def sleep_frame(b, k):
    """躺着睡：3D 那边按这几个数搭被窝。"""
    return dict(sleep=True, k=k, breathe=round(1.5 * math.sin(k * math.pi), 3), expr="sleep", props=[])


# ----------------------------------------------------------------------
# 一张表的全部格子（顺序、意思同 actors.sheet_for / act_sheet_for）
# ----------------------------------------------------------------------

def base_cells(b):
    cells = []
    for i in range(8):
        cells.append((0, i, frame(b, actors.pose_walk(b, i / 8.0))))
    for i in range(4):
        br = math.sin(i / 4.0 * math.tau)
        cells.append((1, i, frame(b, actors.pose_stand(b, br), blink=(i == 3))))
    for i in range(4):
        pose = actors.pose_stand(b, 0.4 * math.sin(i / 4.0 * math.tau))
        pose["lean"] += 4
        cells.append((1, 4 + i, frame(b, pose, busy=i / 4.0)))
    for i in range(2):
        cells.append((2, i, sit_frame(b, i)))
    for i in range(2):
        cells.append((2, 2 + i, sleep_frame(b, i)))
    for i in range(4):
        cells.append((2, 4 + i, frame(b, actors.pose_stand(b, 0.3), wave=i / 4.0, expr="happy" if i in (1, 2) else None)))
    for j, (_name, fn) in enumerate(actor_acts.EMOTES):
        for i in range(4):
            cells.append((3 + j // 2, (j % 2) * 4 + i, frame(b, **fn(b, i / 4.0))))
    return cells


def sit_frame(b, k):
    """同 actors.draw_sit。"""
    swing = math.sin(k * math.pi) * (10 if b["stage"] == "child" else 2)
    th = 90 - 4
    reach = 44.0 - b["ankle"] - 2
    if b["shin"] >= reach:
        kd = th - math.degrees(math.acos(min(1.0, reach / b["shin"])))
    else:
        kd = th - 8
    legs = [dict(side="near", thigh=th, knee=kd + swing, pitch=0), dict(side="far", thigh=th - 3, knee=kd - swing * 0.5 + 6, pitch=0)]
    arms = [dict(side="near", shoulder=28, elbow=48), dict(side="far", shoulder=22, elbow=50)]
    pose = dict(legs=legs, arms=arms, lean=b["lean"] + 3, bob=0.0)
    return frame(b, pose, sit=True)


def act_cells(b):
    cells = []
    for j, (_name, fn) in enumerate(actor_acts.ACTS):
        for i in range(4):
            cells.append((j // 2, (j % 2) * 4 + i, frame(b, **fn(b, i / 4.0))))
    return cells


def figure_spec(b):
    """3D 那边要的体型数（关节以外的：粗细、头多大、穿什么）。"""
    keep = ("role", "stage", "H", "head", "leg", "thigh", "shin", "ankle", "neck", "torso", "waist", "chest", "upper", "fore",
            "limb", "shin_w", "foot", "skirt", "long_coat", "stripes", "stripe", "bag", "cane", "belly", "hair", "knee_bend")
    s = {k: b.get(k) for k in keep}
    s["coat"] = bool(b.get("coat"))
    s["cardigan"] = bool(b.get("cardigan"))
    s["shirt"] = list(b["shirt"]) if b.get("shirt") else None
    return _r(s)


if __name__ == "__main__":
    import json
    b = body("qing", "teen", {})
    print(json.dumps(figure_spec(b), ensure_ascii=False))
    print(json.dumps(base_cells(b)[0], ensure_ascii=False)[:600])
    print(len(act_cells(b)), json.dumps(act_cells(b)[16])[:800])
