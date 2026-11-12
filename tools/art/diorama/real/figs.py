#!/usr/bin/env python3
"""把主角的身材（spec）和几帧姿势（frame）从 pose3d/poses.py 导出成 JSON，给 real.js 用（场景里摆小人、导 glb）。

    python3 tools/art/diorama/real/figs.py      # → tools/art/diorama/real/out/figs.json

figs.json：{ "<design>": { "<role>_<stage>": { spec, design, frames: { stand, walk_a, walk_b } } } }
design：a = 甲（大头 Q 版，现行），b = 乙（绘本修长，约 1:5）。
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "pose3d"))
import figures  # noqa: E402
import poses  # noqa: E402

PICK = {"stand": (1, 0), "walk_a": (0, 2), "walk_b": (0, 5)}


def main():
    out = {}
    for dk in ("a", "b"):
        D = figures.DESIGNS[dk]
        out[dk] = {}
        for role in poses.ROLES:
            for stage in ("child", "teen", "young", "middle", "old"):
                b = poses.body(role, stage, D)
                cells = {(r, c): fr for r, c, fr in poses.base_cells(b)}
                out[dk][f"{role}_{stage}"] = dict(spec=poses.figure_spec(b), design=figures.js_design(D),
                                                  frames={k: cells[v] for k, v in PICK.items()})
    os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
    p = os.path.join(HERE, "out", "figs.json")
    json.dump(out, open(p, "w"), ensure_ascii=False)
    print("✓", p)


if __name__ == "__main__":
    main()
