#!/usr/bin/env bash
# 同岁 · 原生部署（在你的 Mac 上跑）：构建服务端模块 → 传到服务器 → sudo setup.sh
#   bash deploy/native/ship.sh            # 默认目标 ssh 别名 cakery（香港 34.92.141.255）
#   bash deploy/native/ship.sh 别的别名
# 第一次部署和以后更新都是这一条。改了剧情 / 规则只要再跑一次，手机不用重装（见 docs/TECH.md「版本」）。
#
# ⚠️ 别对 cakery 这台机器跑 deploy/ship.sh 或 deploy/install.sh：那套会装 Docker、开 ufw、让 Caddy 占 80/443，
#    会把 cakery 和 sing-box 弄坏。这台机器只用 deploy/native/。
set -euo pipefail

TARGET="${1:-cakery}"
NAKAMA_VERSION="3.41.0"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE="${TONGSUI_CACHE:-$HOME/.cache/tongsui}"
tarball="nakama-$NAKAMA_VERSION-linux-amd64.tar.gz"

cd "$REPO"
echo "==> 构建服务端模块"
npm ci --silent
npm run build --silent
[[ -s server/build/index.js ]] || { echo "server/build/index.js 没生成" >&2; exit 1; }

if [[ ! -f "$CACHE/$tarball" ]]; then
	echo "==> 下载 Nakama $NAKAMA_VERSION（官方 GitHub Release）"
	mkdir -p "$CACHE"
	gh release download "v$NAKAMA_VERSION" -R heroiclabs/nakama -p "$tarball" -D "$CACHE" --clobber
fi

echo "==> 上传到 $TARGET:~/tongsui-upload/"
ssh "$TARGET" 'rm -rf ~/tongsui-upload && mkdir -p ~/tongsui-upload'
scp -q deploy/native/{setup.sh,tongsui.service,nginx-tongsui.conf,backup.sh,restore.sh,tongsui-backup.service,tongsui-backup.timer} \
	server/build/index.js "$CACHE/$tarball" "$TARGET:tongsui-upload/"

echo "==> 在 $TARGET 上安装 / 更新"
ssh "$TARGET" 'sudo bash ~/tongsui-upload/setup.sh'
