#!/usr/bin/env bash
# 在你自己的电脑（Mac / Linux）上一条命令部署或更新服务器。仓库是私有的也没关系：
# 代码从你电脑打包，经 SSH 传过去，服务器不需要 GitHub 权限。
#
#   bash deploy/ship.sh root@服务器IP                         # 第一次：完整安装；之后：备份 → 更新 → 重启
#   bash deploy/ship.sh root@服务器IP --domain tongsui.你的域名  # 后面的参数原样交给 install.sh
#
# 装了 gh CLI（并且 gh auth login 过）的话，最后会顺手把服务器地址写进仓库变量 TONGSUI_SERVER，
# 下次 Actions 出的 APK 就默认连这台服务器。
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:-}"
[[ -n $TARGET && $TARGET != -* ]] || { sed -n '2,9p' "$0"; exit 1; }
shift
REMOTE_DIR="${TONGSUI_DIR:-/opt/tongsui}"
REPO="${TONGSUI_REPO:-Goudu666/tongsui}"
SSH=(ssh -o ServerAliveInterval=30 -o StrictHostKeyChecking=accept-new "$TARGET")

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "请在 tongsui 仓库里运行" >&2; exit 1; }
if ! git diff --quiet HEAD -- server deploy content 2>/dev/null; then
  echo "! 注意：server/ deploy/ content/ 有未提交的改动，会一起传上去"
fi

echo "==> 打包代码（$(git rev-parse --short HEAD)）→ $TARGET:$REMOTE_DIR"
# 只传 git 管理的文件；服务器上的 deploy/.env、备份、证书都不会被覆盖
git ls-files -z | COPYFILE_DISABLE=1 tar --null -T - -czf - |
  "${SSH[@]}" "sudo mkdir -p '$REMOTE_DIR' && sudo tar -xzf - -C '$REMOTE_DIR' --no-same-owner --warning=no-unknown-keyword && echo '    已传到 $REMOTE_DIR'"

ARGS=""
for a in "$@"; do ARGS+=" $(printf '%q' "$a")"; done
if "${SSH[@]}" "test -f '$REMOTE_DIR/deploy/.env'"; then
  if [[ $# -gt 0 ]]; then
    echo "==> 重新运行安装（带参数$ARGS）"
    "${SSH[@]}" -t "sudo bash '$REMOTE_DIR/deploy/install.sh'$ARGS"
  else
    echo "==> 更新：备份 → 重新构建模块 → 重启 → 健康检查"
    "${SSH[@]}" -t "sudo bash '$REMOTE_DIR/deploy/update.sh' --no-pull"
  fi
else
  echo "==> 第一次安装"
  "${SSH[@]}" -t "sudo bash '$REMOTE_DIR/deploy/install.sh'$ARGS"
fi

JSON="$("${SSH[@]}" "sudo cat '$REMOTE_DIR/deploy/client-server.json' 2>/dev/null" || true)"
if [[ -z $JSON ]]; then
  echo "没读到 $REMOTE_DIR/deploy/client-server.json，看看上面安装有没有报错" >&2
  exit 1
fi
echo
echo "客户端配置：$JSON"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  current="$(gh variable get TONGSUI_SERVER -R "$REPO" 2>/dev/null || true)"
  if [[ $current != "$JSON" ]]; then
    gh variable set TONGSUI_SERVER -R "$REPO" --body "$JSON"
    echo "✓ 已写入 $REPO 的仓库变量 TONGSUI_SERVER。到 Actions → build → Run workflow 出新 APK。"
  else
    echo "✓ 仓库变量 TONGSUI_SERVER 已经是这个值，不用改"
  fi
else
  echo "把上面这行 JSON 填到 GitHub 仓库 Settings → Secrets and variables → Actions → Variables → TONGSUI_SERVER"
fi
