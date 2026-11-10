#!/usr/bin/env bash
# 把游戏各界面截成 PNG（横屏 1920×1080）。用法：bash tools/shots/run.sh <输出目录>
#   GODOT=/path/to/godot   默认找 PATH 里的 godot
#   RES=2400x1080          换一种屏幕比例（默认 1920x1080；2400x1080 是 20:9 的长屏手机）
#   NOTCH=96               假装左右各有这么宽的刘海 / 圆角（界面坐标），看安全边距
# 没有显示器的机器（CI、云端）自动套一层 xvfb。
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$(mkdir -p "${1:-$root/shots}" && cd "${1:-$root/shots}" && pwd)"
godot="${GODOT:-godot}"
cmd=("$godot" --path "$root/client" --rendering-driver opengl3 --resolution "${RES:-1920x1080}" \
  --script "$root/tools/shots/shots.gd" -- "--out=$out" "--notch=${NOTCH:-0}")
if [[ -z "${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null; then
  xvfb-run -a -s "-screen 0 2600x1300x24" "${cmd[@]}"
else
  "${cmd[@]}"
fi
echo "✓ $out"
