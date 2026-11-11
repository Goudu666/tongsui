#!/usr/bin/env bash
# 「人物活起来」演示视频（1280×720，30 帧，约 45 秒，镜头推近 2 倍看细节）。用法：bash tools/shots/life_reel.sh <输出.mp4>
#   GODOT=/path/to/godot   默认找 PATH 里的 godot；需要 ffmpeg。ZOOM=1 换回游戏里的取景
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${1:-$root/life_reel.mp4}"
tmp="$(mktemp -d)"
godot="${GODOT:-godot}"
cmd=("$godot" --path "$root/client" --rendering-driver opengl3 --resolution "${RES:-1280x720}" \
  --write-movie "$tmp/reel.avi" --fixed-fps 30 --script "$root/tools/shots/life.gd" -- --movie "--zoom=${ZOOM:-2}" "--out=$tmp")
if [[ -z "${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null; then
  xvfb-run -a -s "-screen 0 2000x1200x24" "${cmd[@]}"
else
  "${cmd[@]}"
fi
ffmpeg -y -loglevel error -i "$tmp/reel.avi" -an -c:v libx264 -pix_fmt yuv420p -crf 28 -preset slow -movflags +faststart "$out"
rm -rf "$tmp"
echo "✓ $out"
