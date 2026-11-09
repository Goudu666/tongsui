#!/usr/bin/env bash
# 拉取客户端依赖：nakama-godot 插件（联机用）+ 霞鹜文楷字体（可选，美术用）
# 用法：bash tools/fetch_addons.sh [--no-font]
set -euo pipefail
cd "$(dirname "$0")/../client"

NAKAMA_GODOT_TAG="v3.4.0"
WENKAI_TAG="v1.522"

echo "→ nakama-godot ${NAKAMA_GODOT_TAG}"
tmp="$(mktemp -d)"
git clone -q --depth 1 --branch "$NAKAMA_GODOT_TAG" https://github.com/heroiclabs/nakama-godot "$tmp/ng"
mkdir -p addons
rm -rf addons/com.heroiclabs.nakama
cp -r "$tmp/ng/addons/com.heroiclabs.nakama" addons/
rm -rf "$tmp"

# 注册 autoload（插件不在时不能写进 project.godot，否则同屏模式也会启动报错）
if ! grep -q '^Nakama=' project.godot; then
  if grep -q '^\[autoload\]' project.godot; then
    sed -i.bak '/^\[autoload\]/a Nakama="*res://addons/com.heroiclabs.nakama/Nakama.gd"' project.godot && rm -f project.godot.bak
  else
    printf '\n[autoload]\n\nNakama="*res://addons/com.heroiclabs.nakama/Nakama.gd"\n' >> project.godot
  fi
  echo "  已在 project.godot 注册 autoload Nakama（不要提交这一行，或者确认团队都装了插件再提交）"
fi

if [[ "${1:-}" != "--no-font" ]]; then
  echo "→ 霞鹜文楷 ${WENKAI_TAG}（约 25 MB，正式打包前建议用 pyftsubset 裁成常用字）"
  mkdir -p fonts
  curl -fL --progress-bar -o fonts/LXGWWenKai-Regular.ttf \
    "https://github.com/lxgw/LxgwWenKai/releases/download/${WENKAI_TAG}/LXGWWenKai-Regular.ttf"
fi
echo "✓ 完成。用 Godot 4.7.2 打开 client/project.godot 让它导入一次资源。"
