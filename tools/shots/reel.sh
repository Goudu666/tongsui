#!/usr/bin/env bash
# 录一段约 30 秒的演示视频（横屏 960×540，30 帧）。用法：bash tools/shots/reel.sh <输出.mp4>
#   GODOT=/path/to/godot   默认找 PATH 里的 godot；需要 ffmpeg
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${1:-$root/reel.mp4}"
tmp="$(mktemp -d)"
godot="${GODOT:-godot}"
cmd=("$godot" --path "$root/client" --rendering-driver opengl3 --resolution 960x540 \
  --write-movie "$tmp/reel.avi" --fixed-fps 30 --script "$root/tools/shots/reel.gd")
if [[ -z "${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null; then
  xvfb-run -a -s "-screen 0 2000x1200x24" "${cmd[@]}"
else
  "${cmd[@]}"
fi
ffmpeg -y -loglevel error -i "$tmp/reel.avi" -an -c:v libx264 -pix_fmt yuv420p -crf 25 -movflags +faststart "$out"
rm -rf "$tmp"
echo "✓ $out"
