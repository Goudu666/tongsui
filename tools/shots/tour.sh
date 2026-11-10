#!/usr/bin/env bash
# 十一张侧视图巡拍（美术前后对比）。用法：bash tools/shots/tour.sh <输出目录> [--only=street,river] [--clean]
#   GODOT=/path/to/godot   默认找 PATH 里的 godot
#   RES=2400x1080          换屏幕比例
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$(mkdir -p "${1:-$root/tour}" && cd "${1:-$root/tour}" && pwd)"
shift || true
godot="${GODOT:-godot}"
cmd=("$godot" --path "$root/client" --rendering-driver opengl3 --resolution "${RES:-1920x1080}" \
  --script "$root/tools/shots/scenes_tour.gd" -- "--out=$out" "$@")
if [[ -z "${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null; then
  xvfb-run -a -s "-screen 0 2600x1300x24" "${cmd[@]}"
else
  "${cmd[@]}"
fi
echo "✓ $out"
