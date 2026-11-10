#!/usr/bin/env bash
# 客户端单测：不需要服务器，跑 client/tests/unit_*.gd（插值缓冲、服务器时钟、地址解析、内容仓库……）。
# 新加的单测文件按 unit_xxx.gd 命名、extends SceneTree、失败时 quit(1)，这里会自动跑到。
#   GODOT=/path/to/godot bash tools/ci/client_unit.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
CLIENT="${CLIENT_DIR:-client}"  # 不想在仓库里生成 .godot/.uid，就把 client 拷一份，用 CLIENT_DIR 指过去

timeout 300 "$GODOT" --headless --editor --quit --path "$CLIENT" >/dev/null 2>&1 || true  # 第一次要导入资源
status=0
for f in "$CLIENT"/tests/unit_*.gd; do
  name="$(basename "$f")"
  log="$(mktemp)"
  if timeout 120 "$GODOT" --headless --path "$CLIENT" -s "res://tests/$name" >"$log" 2>&1 \
     && ! grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$log"; then
    grep -E "^✓" "$log" || echo "✓ $name"
  else
    echo "✗ $name"
    cat "$log"
    status=1
  fi
done
exit $status
