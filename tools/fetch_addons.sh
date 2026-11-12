#!/usr/bin/env bash
# 拉取客户端依赖：寒蝉全圆体（界面字）+ 霞鹜文楷（缺字时的退路）（可选，美术用）；--update-nakama 升级随仓库提交的 nakama-godot 插件
# 用法：bash tools/fetch_addons.sh [--no-font] [--update-nakama]
set -euo pipefail
cd "$(dirname "$0")/../client"

NAKAMA_GODOT_TAG="v3.4.0"
WENKAI_TAG="v1.522"
# 寒蝉全圆体 v3.000（OFL 1.1，github.com/Warren2060/ChillRound）：取 npm 上原样打包的那份（只有一个 ttf），校验和钉死
CHILL_ROUND_TGZ="https://registry.npmjs.org/@fontpkg/chill-round-f/-/chill-round-f-3.0.0.tgz"
CHILL_ROUND_SHA256="a8f0d23626e9aad41916b91153e0e7319959ee9b5b55dfcb0a16cf0bd3a32bce"

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
  echo "→ 寒蝉全圆体 3.000（约 6 MB，界面字）"
  tmp="$(mktemp -d)"
  curl -fL --progress-bar -o "$tmp/chill.tgz" "$CHILL_ROUND_TGZ"
  echo "${CHILL_ROUND_SHA256}  $tmp/chill.tgz" | sha256sum -c --quiet -
  tar -xzf "$tmp/chill.tgz" -C "$tmp" package/ChillRoundF.ttf
  mv "$tmp/package/ChillRoundF.ttf" fonts/ChillRoundF.ttf
  rm -rf "$tmp"
fi
echo "✓ 完成。用 Godot 4.7.2 打开 client/project.godot 让它导入一次资源。"
