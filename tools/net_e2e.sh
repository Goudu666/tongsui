#!/usr/bin/env bash
# 两个无头 Godot 客户端连本地 Nakama 一起玩一遍（见 client/tests/net_e2e.gd）。
# 先起服务器：npm run server:build && docker compose -f deploy/docker-compose.yml up -d
# 用法：GODOT=/path/to/godot bash tools/net_e2e.sh [--server=http://127.0.0.1:7350]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
CLIENT="${CLIENT_DIR:-client}"  # 不想在仓库里生成 .godot/.uid，就把 client 拷一份，用 CLIENT_DIR 指过去
code="$(mktemp -u /tmp/tongsui-e2e-code.XXXX)"
run="$(date +%s)"
"$GODOT" --headless --editor --quit --path "$CLIENT" >/dev/null 2>&1 || true  # 第一次要导入资源
"$GODOT" --headless --path "$CLIENT" res://tests/net_e2e.tscn -- --device="e2e-q-$run" --bot=qing --codefile="$code" "$@" > /tmp/tongsui-e2e-qing.log 2>&1 &
q=$!
"$GODOT" --headless --path "$CLIENT" res://tests/net_e2e.tscn -- --device="e2e-m-$run" --bot=mei --codefile="$code" "$@" > /tmp/tongsui-e2e-mei.log 2>&1 &
m=$!
ok=0
wait $q || ok=1
wait $m || ok=1
grep -h '^\[' /tmp/tongsui-e2e-qing.log /tmp/tongsui-e2e-mei.log | sort -t'[' -k2 || true
grep -hE "SCRIPT ERROR|Parse Error|ERROR:" /tmp/tongsui-e2e-qing.log /tmp/tongsui-e2e-mei.log | head -20 || true
[ $ok -eq 0 ] && echo "✓ 两个 Godot 客户端联机通过" || { echo "✗ 失败，日志：/tmp/tongsui-e2e-{qing,mei}.log"; exit 1; }
