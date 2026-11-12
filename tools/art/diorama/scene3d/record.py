#!/usr/bin/env python3
"""把孔版老画法（tools/art/scenes.py）录成一份「显示列表」，给 3D 那边搭模型用。

老画法画什么、画在哪一律不改；这里把 Pen / Sheet 的每一笔换成一条记录：
  {k: fill|line|ring|dot|text|clear|bricks, p: 点, c: 版, d: 浓度, w: 线宽, t: [所在的画法函数，外到内], a: 最外层道具的参数}
一张图从头画到尾（纸开得和整张图一样宽，scenes.visible 不会把画不到的地方跳掉），出 JSON。

    python3 tools/art/diorama/scene3d/record.py street --out /tmp/street.json
"""
from __future__ import annotations

import argparse
import functools
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, ART)

import riso  # noqa: E402
import scenes  # noqa: E402

REC: list | None = None
STACK: list = []      # 正在画的画法函数（外到内），每层 [名字, 编号, 参数]
_N = [0]


def _r(v):
    return round(float(v), 1)


def _pts(pts):
    return [[_r(x), _r(y)] for x, y in pts]


def emit(k, pts=None, **kw):
    if REC is None:
        return
    o = {"k": k}
    if pts is not None:
        o["p"] = _pts(pts)
    if STACK:
        o["t"] = [s[0] for s in STACK]
        o["g"] = [s[1] for s in STACK]
    o.update({a: (_r(b) if isinstance(b, float) else b) for a, b in kw.items() if b is not None})
    REC.append(o)


# ---------------------------------------------------------------- 画笔换成记录
def _pen_line(self, pts, w=3.0, amp=0.9, cap="round", density=None, dash=None):
    emit("line", pts, c=self.color, d=self.density if density is None else density, w=w, dash=1 if dash else None)
    return self


def _pen_poly(self, pts, w=3.0, fill=False, stroke=True, amp=0.9, density=None, fill_density=None):
    pts = [tuple(p) for p in pts]
    if fill:
        emit("fill", pts, c=self.color, d=self.density if (fill_density if fill_density is not None else density) is None
             else (fill_density if fill_density is not None else density))
    if stroke:
        emit("ring", pts, c=self.color, d=self.density if density is None else density, w=w, filled=1 if fill else None)
    return self


def _pen_dot(self, x, y, r=2.0, density=None):
    emit("dot", [(x, y)], c=self.color, d=self.density if density is None else density, w=r)
    return self


def _pen_hatch(self, pts, angle=45.0, gap=10.0, w=1.6, amp=0.5, density=None):
    emit("hatch", [tuple(p) for p in pts], c=self.color, d=self.density if density is None else density)
    return self


def _pen_bricks(self, x, y, w, h, bw=34.0, bh=12.0, lw=1.4, density=None, seed=None):
    emit("bricks", riso.rect_pts(x, y, w, h), c=self.color, bw=bw, bh=bh)
    return self


def _sheet_text(self, color, tint, s, x, y, size, anchor="mm", density=1.0, vertical=False):
    emit("text", [(x, y)], c=color, d=density, s=s, size=size, anchor=anchor, v=1 if vertical else None)


def _sheet_clear(self, pts, colors=None, layers=("solid", "tint")):
    emit("clear", [tuple(p) for p in pts], only=list(colors) if colors else None)


def _fline(g, color, pts, lw=1.4, d=1.0, tint=False):
    emit("line", pts, c=color, d=d, w=lw, faint=1)


def _fbricks(g, x, y, w, h, bw=30.0, bh=11.0, lw=0.9, d=0.32, seed=1):
    emit("bricks", riso.rect_pts(x, y, w, h), bw=bw, bh=bh)


def _fhatch(g, color, x, y, w, h, angle=45.0, gap=9.0, lw=1.2, d=1.0, tint=False):
    emit("hatch", riso.rect_pts(x, y, w, h), c=color, d=d)


def _ftint(g, color, pts, d):
    emit("fill", pts, c=color, d=d)


def _knock(g, color, text, x, y, size, vertical=False, layer="solid"):
    # 招牌上「挖出来」的字：字是纸色
    emit("text", [(x, y)], c="paper", d=1.0, s=text, size=size, v=1 if vertical else None, knock=color)


def _solid(g, pts):
    emit("solid", pts)


def _wrap(name, fn):
    @functools.wraps(fn)
    def inner(*a, **kw):
        _N[0] += 1
        args = []
        for v in a[1:]:
            if isinstance(v, (int, float, str, bool)) or v is None:
                args.append(v)
            elif isinstance(v, (list, tuple)) and all(isinstance(t, (int, float, str)) for t in v):
                args.append(list(v))
            else:
                args.append(None)
        kws = {k: v for k, v in kw.items() if isinstance(v, (int, float, str, bool)) or v is None}
        STACK.append([name, _N[0]])
        if REC is not None:
            REC.append({"k": "call", "n": name, "id": _N[0], "a": args, "kw": kws, "t": [s[0] for s in STACK[:-1]], "g": [s[1] for s in STACK[:-1]]})
        try:
            return fn(*a, **kw)
        finally:
            STACK.pop()
    return inner


# 这些是「画一样东西」的函数：录下来，3D 那边按名字认东西（门、窗、桌子……），不认识的按平面铺
SKIP_WRAP = {"load_scenes", "layer_note", "mark", "visible", "fline", "fbricks", "fhatch", "ftint", "knock", "solid",
             "render", "save_png", "collect_anchors", "build", "main", "relief", "annulus", "_ctx"}


def enable():
    riso.Pen.line = _pen_line
    riso.Pen.poly = _pen_poly
    riso.Pen.dot = _pen_dot
    riso.Pen.hatch = _pen_hatch
    riso.Pen.bricks = _pen_bricks
    riso.Sheet.text = _sheet_text
    riso.Sheet.clear = _sheet_clear
    scenes.OSheet.clear = _sheet_clear
    scenes.fline = _fline
    scenes.fbricks = _fbricks
    scenes.fhatch = _fhatch
    scenes.ftint = _ftint
    scenes.knock = _knock
    scenes.solid = _solid
    import types
    for name, fn in list(vars(scenes).items()):
        if isinstance(fn, types.FunctionType) and fn.__module__ == scenes.__name__ and name not in SKIP_WRAP:
            setattr(scenes, name, _wrap(name, fn))
    # DRAW 里存的是包之前的函数，重新指一下
    for k, fn in list(scenes.DRAW.items()):
        scenes.DRAW[k] = getattr(scenes, fn.__name__)


def record(sid):
    global REC
    sc = scenes.load_scenes()[sid]
    REC = []
    # 纸开得和整张图一样大（倍率很小，cairo 的面几乎不占地方），visible() 就不会跳过任何东西
    g = scenes.OSheet(sc["width"] + 200, scenes.BOTTOM - scenes.TOP + 200, 0.02, origin=(-100, scenes.TOP - 100))
    scenes.DRAW[sid](g, sc)
    out, REC = REC, None
    anchors = scenes.collect_anchors(sc)
    return {"id": sid, "width": sc["width"], "floors": sc["floors"], "top": scenes.TOP, "bottom": scenes.BOTTOM,
            "spots": sc["spots"], "exits": sc["exits"], "anchors": anchors, "ops": out}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    enable()
    ids = a.ids or list(scenes.DRAW)
    for sid in ids:
        d = record(sid)
        path = a.out or os.path.join(HERE, "out", f"{sid}.json")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(d, f, ensure_ascii=False, separators=(",", ":"))
        kinds = {}
        for o in d["ops"]:
            kinds[o["k"]] = kinds.get(o["k"], 0) + 1
        print(sid, len(d["ops"]), kinds, path)


if __name__ == "__main__":
    main()
