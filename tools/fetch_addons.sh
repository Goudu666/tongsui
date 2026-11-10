#!/usr/bin/env bash
# 拉取客户端依赖：霞鹜文楷字体（可选，美术用）；--update-nakama 升级随仓库提交的 nakama-godot 插件
# 用法：bash tools/fetch_addons.sh [--no-font] [--update-nakama]
set -euo pipefail
cd "$(dirname "$0")/../client"

NAKAMA_GODOT_TAG="v3.4.0"
WENKAI_TAG="v1.522"

# nakama-godot 插件已经随仓库提交（client/addons/com.heroiclabs.nakama，Apache-2.0，去掉了用不到的 Satori），
# CI 导出的 APK 直接带着它，两台手机装上就能联机。只有升级插件版本时才需要：bash tools/fetch_addons.sh --update-nakama
if [[ " $* " == *" --update-nakama "* ]]; then
  echo "→ nakama-godot ${NAKAMA_GODOT_TAG}"
  tmp="$(mktemp -d)"
  git clone -q --depth 1 --branch "$NAKAMA_GODOT_TAG" https://github.com/heroiclabs/nakama-godot "$tmp/ng"
  rm -rf addons/com.heroiclabs.nakama
  cp -r "$tmp/ng/addons/com.heroiclabs.nakama" addons/
  cp "$tmp/ng/LICENSE" addons/com.heroiclabs.nakama/LICENSE
  rm -rf addons/com.heroiclabs.nakama/Satori addons/com.heroiclabs.nakama/Satori.gd* addons/com.heroiclabs.nakama/dotnet-utils "$tmp"
fi

if [[ " $* " != *" --no-font "* ]]; then
  echo "→ 霞鹜文楷 ${WENKAI_TAG}（约 25 MB，正式打包前建议用 pyftsubset 裁成常用字）"
  mkdir -p fonts
  curl -fL --progress-bar -o fonts/LXGWWenKai-Regular.ttf \
    "https://github.com/lxgw/LxgwWenKai/releases/download/${WENKAI_TAG}/LXGWWenKai-Regular.ttf"
fi
echo "✓ 完成。用 Godot 4.7.2 打开 client/project.godot 让它导入一次资源。"
