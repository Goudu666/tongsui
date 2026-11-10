#!/usr/bin/env bash
# 把游戏各界面截成 PNG（1080×1920）。用法：bash tools/shots/run.sh <输出目录>
#   GODOT=/path/to/godot   默认找 PATH 里的 godot
#   RES=1080x2400          换一种屏幕比例（默认 1080x1920）
# 没有显示器的机器（CI、云端）自动套一层 xvfb。
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$(mkdir -p "${1:-$root/shots}" && cd "${1:-$root/shots}" && pwd)"
godot="${GODOT:-godot}"
cmd=("$godot" --path "$root/client" --rendering-driver opengl3 --resolution "${RES:-1080x1920}" \
  --script "$root/tools/shots/shots.gd" -- "--out=$out")
if [[ -z "${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null; then
  xvfb-run -a -s "-screen 0 1200x2600x24" "${cmd[@]}"
else
  "${cmd[@]}"
fi
echo "✓ $out"
