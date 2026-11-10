#!/usr/bin/env bash
# 侧视横版演示视频（1280×720，30 帧，约 30 秒）。用法：bash tools/shots/side_reel.sh <输出.mp4>
#   GODOT=/path/to/godot   默认找 PATH 里的 godot；需要 ffmpeg
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${1:-$root/side_reel.mp4}"
tmp="$(mktemp -d)"
godot="${GODOT:-godot}"
cmd=("$godot" --path "$root/client" --rendering-driver opengl3 --resolution "${RES:-1280x720}" \
  --write-movie "$tmp/reel.avi" --fixed-fps 30 --script "$root/tools/shots/side_reel.gd")
if [[ -z "${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null; then
  xvfb-run -a -s "-screen 0 2000x1200x24" "${cmd[@]}"
else
  "${cmd[@]}"
fi
ffmpeg -y -loglevel error -i "$tmp/reel.avi" -an -c:v libx264 -pix_fmt yuv420p -crf 30 -preset slow -movflags +faststart "$out"
rm -rf "$tmp"
echo "✓ $out"
