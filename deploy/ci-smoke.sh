#!/usr/bin/env bash
# 同岁 · 部署冒烟测试（CI 和本地都能跑，不需要 root，需要 docker 且 80/443/7350/7351 空闲）
#
#   bash deploy/ci-smoke.sh                                # 在容器里构建模块
#   bash deploy/ci-smoke.sh --module server/build/index.js # 用已构建好的模块
#
# 做的事：install.sh --no-system --domain localhost 起整套 prod（含 Caddy，localhost 用自签证书）
#   → 经 443 测健康检查、设备登录、RPC、控制台路径被挡、7350/7351 只绑 127.0.0.1
#   → 测 backup.sh / restore.sh / update.sh --no-pull
#   → 最后删掉容器和数据卷，恢复原来的 deploy/.env。
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# 单独的项目名，不碰本地开发用的 tongsui 数据卷
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-tongsui-smoke}"
BASE="https://localhost"
WORK="$(mktemp -d)"
failed=1

for f in "$ENV_FILE" "$CLIENT_JSON"; do
	[[ -e $f ]] && mv "$f" "$f.smoke-bak"
done

cleanup() {
	if ((failed)); then
		echo "---- 冒烟失败，最近日志 ----" >&2
		dc logs --tail 80 >&2 || true
	fi
	dc down -v --remove-orphans >/dev/null 2>&1 || true
	rm -rf "$WORK"
	rm -f "$ENV_FILE" "$CLIENT_JSON"
	for f in "$ENV_FILE" "$CLIENT_JSON"; do
		[[ -e $f.smoke-bak ]] && mv "$f.smoke-bak" "$f"
	done
	return 0
}
trap cleanup EXIT

# 只用 curl + sed，不依赖 jq
json_field() { sed -nE "s/.*\"$1\" *: *\"([^\"]*)\".*/\1/p"; }

step "1. install.sh --no-system --domain localhost"
bash "$DEPLOY_DIR/install.sh" --no-system --domain localhost "$@"

SERVER_KEY="$(env_get NAKAMA_SERVER_KEY)"
[[ ${#SERVER_KEY} -ge 32 ]] || die "NAKAMA_SERVER_KEY 没有生成随机值"
for k in POSTGRES_PASSWORD NAKAMA_CONSOLE_PASSWORD NAKAMA_SESSION_ENCRYPTION_KEY \
	NAKAMA_SESSION_REFRESH_ENCRYPTION_KEY NAKAMA_RUNTIME_HTTP_KEY NAKAMA_CONSOLE_SIGNING_KEY; do
	[[ "$(env_get "$k")" =~ ^[0-9a-f]{48}$ ]] || die "$k 不是随机值"
done
[[ "$(stat -c %a "$ENV_FILE")" == 600 ]] || die ".env 权限不是 600"
grep -q "\"server_key\": \"$SERVER_KEY\"" "$CLIENT_JSON" || die "client-server.json 不对"
ok "密钥都是随机值；client-server.json：$(cat "$CLIENT_JSON")"

step "2. 再跑一次 install.sh（幂等，密钥不变）"
before="$(sha256sum "$ENV_FILE")"
bash "$DEPLOY_DIR/install.sh" --no-system --domain localhost --module "$MODULE_FILE" >/dev/null
[[ "$(sha256sum "$ENV_FILE")" == "$before" ]] || die "第二次运行改动了 .env"
ok ".env 没变"

step "3. 经 Caddy（443）调用"
code="$(curl -ks -o /dev/null -w '%{http_code}' "$BASE/healthcheck")"
[[ $code == 200 ]] || die "healthcheck 返回 $code"
ok "GET /healthcheck → 200"

curl -ks -D - -o /dev/null "$BASE/healthcheck" | grep -qi '^strict-transport-security' || die "缺少 HSTS 头"
ok "安全响应头在"

code="$(curl -ks -o /dev/null -w '%{http_code}' -u defaultkey: -H 'Content-Type: application/json' \
	-d '{"id":"test-device-000001"}' "$BASE/v2/account/authenticate/device?create=true")"
[[ $code == 401 ]] || die "默认 server key 居然能登录（$code）"
ok "defaultkey 被拒绝（401）"

auth="$(curl -kfsS -u "$SERVER_KEY:" -H 'Content-Type: application/json' \
	-d '{"id":"test-device-000001"}' "$BASE/v2/account/authenticate/device?create=true")"
TOKEN="$(json_field token <<<"$auth")"
[[ -n $TOKEN ]] || die "设备登录没拿到 token：$auth"
ok "设备登录成功（token ${#TOKEN} 字节）"

rpc="$(curl -kfsS -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
	-d '"{\"name\":\"smoke\"}"' "$BASE/v2/rpc/lifeline_create" || true)"
if [[ -n $rpc ]]; then ok "RPC lifeline_create：$rpc"; else warn "RPC lifeline_create 调用失败（服务端可能改名了，不算部署问题）"; fi

code="$(curl -ks -o /dev/null -w '%{http_code}' "$BASE/v2/console/authenticate")"
[[ $code == 404 ]] || die "/v2/console 没被挡住（$code）"
ok "控制台路径经 443 访问 → 404"

ports="$(docker port "$(dc ps -q nakama)")"
if grep -v '127.0.0.1' <<<"$ports" | grep -q .; then die "Nakama 端口对外暴露了：$ports"; fi
[[ -z "$(docker port "$(dc ps -q postgres)")" ]] || die "postgres 映射了端口"
ok "7350/7351 只绑 127.0.0.1，postgres 无端口映射"

step "4. backup.sh → restore.sh"
export TONGSUI_BACKUP_DIR="$WORK/backups"
mkdir -p "$TONGSUI_BACKUP_DIR"
old="$TONGSUI_BACKUP_DIR/tongsui-20000101-000000.sql.gz"
echo old | gzip >"$old" && touch -d '20 days ago' "$old"
dump="$(bash "$DEPLOY_DIR/backup.sh" | tail -1)"
[[ -s $dump ]] || die "没生成备份"
[[ ! -e $old ]] || die "超过 14 天的旧备份没被清理"
ok "备份：$(basename "$dump") $(du -h "$dump" | cut -f1)，旧备份已清理"
# 恢复前删掉这个用户，恢复后应该还在
dc exec -T postgres psql -U postgres -d nakama -qc "DELETE FROM users WHERE id IN (SELECT user_id FROM user_device WHERE id = 'test-device-000001');" >/dev/null
bash "$DEPLOY_DIR/restore.sh" "$dump" --yes
n="$(dc exec -T postgres psql -U postgres -d nakama -tAc "SELECT count(*) FROM user_device WHERE id = 'test-device-000001';")"
[[ $n == 1 ]] || die "恢复后找不到测试设备（$n）"
auth="$(curl -kfsS -u "$SERVER_KEY:" -H 'Content-Type: application/json' \
	-d '{"id":"test-device-000001"}' "$BASE/v2/account/authenticate/device?create=false")"
[[ -n "$(json_field token <<<"$auth")" ]] || die "恢复后登录失败"
ok "恢复后旧账号能登录"

step "5. update.sh --no-pull"
bash "$DEPLOY_DIR/update.sh" --no-pull --no-backup --module "$MODULE_FILE"
code="$(curl -ks -o /dev/null -w '%{http_code}' "$BASE/healthcheck")"
[[ $code == 200 ]] || die "更新后 healthcheck 返回 $code"
ok "更新后 healthcheck → 200"

failed=0
step "冒烟全部通过 ✓"
