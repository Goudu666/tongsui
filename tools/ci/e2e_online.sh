#!/usr/bin/env bash
# 端到端联机测试：真 PostgreSQL + 真 Nakama（加载 server/build/index.js）+ 两个真 Godot 客户端进程。
# 走一遍玩家会走的路：开人生线 → 对方输配对码加入 → 都进房间 → 重抽 → 确认投胎 → 收到实时世界。
#
#   npm run server:build && bash tools/fetch_addons.sh --no-font   # 先准备好模块和插件
#   bash tools/ci/e2e_online.sh
#
# 需要 docker。镜像：postgres:16-alpine、heroiclabs/nakama:3.41.0、barichello/godot-ci:4.7.2
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"
GODOT_IMAGE="${GODOT_IMAGE:-barichello/godot-ci:4.7.2}"
NET="tongsui-e2e-$$"
DIR="$(mktemp -d)"
chmod 777 "$DIR"

[[ -f server/build/index.js ]] || { echo "缺 server/build/index.js，先 npm run server:build" >&2; exit 1; }
[[ -d client/addons/com.heroiclabs.nakama ]] || { echo "缺 nakama-godot 插件，先 bash tools/fetch_addons.sh --no-font" >&2; exit 1; }

cleanup() {
  docker rm -f "$NET-host" "$NET-join" "$NET-nakama" "$NET-pg" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "$NET" >/dev/null
docker run -d --name "$NET-pg" --network "$NET" -e POSTGRES_DB=nakama -e POSTGRES_PASSWORD=e2e postgres:16-alpine >/dev/null
for _ in $(seq 1 30); do docker exec "$NET-pg" pg_isready -U postgres -d nakama >/dev/null 2>&1 && break; sleep 1; done

docker run -d --name "$NET-nakama" --network "$NET" \
  -v "$ROOT/server/build:/nakama/data/modules:ro" \
  -v "$ROOT/deploy/nakama/local.yml:/nakama/data/local.yml:ro" \
  --entrypoint /bin/sh heroiclabs/nakama:3.41.0 -ecx \
  "/nakama/nakama migrate up --database.address postgres:e2e@$NET-pg:5432/nakama && exec /nakama/nakama --config /nakama/data/local.yml --database.address postgres:e2e@$NET-pg:5432/nakama" >/dev/null
for _ in $(seq 1 60); do docker logs "$NET-nakama" 2>&1 | grep -q "Startup done" && break; sleep 1; done
docker logs "$NET-nakama" 2>&1 | grep -o '同岁 server module loaded[^"]*' || { docker logs "$NET-nakama" | tail -30; exit 1; }

echo "▶ 导入客户端资源"
docker run --rm -v "$ROOT:/w" -w /w "$GODOT_IMAGE" \
  sh -c 'timeout 300 godot --headless --editor --quit --path client >/dev/null 2>&1 || true'

echo "▶ 两个客户端开跑"
for who in host join; do
  docker run -d --name "$NET-$who" --network "$NET" -v "$ROOT:/w" -v "$DIR:/e2e" -w /w "$GODOT_IMAGE" \
    sh -c "timeout 90 godot --headless --path client res://tests/e2e_online.tscn -- \
      --device=e2e-$who-$$ --e2e=$who --e2e-dir=/e2e --server=http://$NET-nakama:7350" >/dev/null
done

status=0
for who in host join; do
  code="$(docker wait "$NET-$who")"
  echo "── 客户端 $who（退出码 $code）"
  docker logs "$NET-$who" 2>&1 | grep -E '^\[e2e|SCRIPT ERROR|ERROR' | grep -v fontconfig || true
  [[ "$code" == 0 ]] || status=1
done
if [[ $status -ne 0 ]]; then
  echo "── Nakama 日志"
  docker logs "$NET-nakama" 2>&1 | tail -40
  echo "✗ 端到端联机测试失败" >&2
  exit 1
fi
echo "✓ 端到端联机测试通过"
