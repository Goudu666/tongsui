#!/usr/bin/env bash
# 同岁 · 原生部署（服务器端）：PostgreSQL + Nakama 二进制 + systemd + nginx 8080
# 由 deploy/native/ship.sh 从 Mac 上传到服务器 ~/tongsui-upload/ 后执行：sudo bash ~/tongsui-upload/setup.sh
#
# 适用于已经跑着别的服务的机器（比如香港那台 cakery 机器）：
#   - 不装 Docker、不动 ufw/iptables、不碰 80/443 和别的 nginx server，只新增 /etc/nginx/sites-available/tongsui（8080）
#   - Nakama 全部端口只绑 127.0.0.1，公网只经 nginx 8080
#   - 可以放心重复运行：密钥只在第一次生成，以后只换模块 / 二进制，再重启检查
#
# 上传目录里要有：setup.sh tongsui.service nginx-tongsui.conf backup.sh tongsui-backup.{service,timer}
#                 index.js（服务端模块）nakama-<版本>-linux-amd64.tar.gz
set -euo pipefail

NAKAMA_VERSION="3.41.0"
PUBLIC_PORT="${TONGSUI_PUBLIC_PORT:-8080}"
SRC="$(cd "$(dirname "$0")" && pwd)"
ROOT=/opt/tongsui
SECRETS="$ROOT/secrets.env"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m错误：%s\033[0m\n' "$*" >&2; exit 1; }
rand_hex() { od -vAn -N"${1:-24}" -tx1 /dev/urandom | tr -d ' \n'; }

[[ $EUID -eq 0 ]] || die "要用 sudo 运行"
[[ -f "$SRC/index.js" ]] || die "$SRC/index.js 不存在（服务端模块）"

step "PostgreSQL"
if ! command -v psql >/dev/null || ! systemctl list-unit-files postgresql.service >/dev/null 2>&1; then
	# 只装 postgresql，不 upgrade；needrestart 设成只列出不重启，免得 apt 顺手重启 cakery / sing-box / nginx
	export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l
	apt-get update -q
	apt-get install -y -q --no-install-recommends postgresql
fi
systemctl enable --now postgresql >/dev/null
# 只听本机（Ubuntu 默认就是 localhost，这里确认一下）
sudo -u postgres psql -tAc "SHOW listen_addresses" | grep -qx 'localhost' || die "PostgreSQL listen_addresses 不是 localhost，先检查"

step "用户和目录"
id tongsui >/dev/null 2>&1 || useradd --system --home-dir "$ROOT" --shell /usr/sbin/nologin tongsui
install -d -m 755 -o root -g root "$ROOT" "$ROOT/bin" "$ROOT/modules"
install -d -m 750 -o tongsui -g tongsui "$ROOT/data"

step "Nakama $NAKAMA_VERSION"
if [[ ! -x "$ROOT/bin/nakama" ]] || ! "$ROOT/bin/nakama" --version 2>/dev/null | grep -q "$NAKAMA_VERSION"; then
	tarball="$SRC/nakama-$NAKAMA_VERSION-linux-amd64.tar.gz"
	[[ -f "$tarball" ]] || die "缺 $tarball"
	tmp="$(mktemp -d)"
	tar -xzf "$tarball" -C "$tmp" nakama
	install -m 755 -o root -g root "$tmp/nakama" "$ROOT/bin/nakama"
	rm -rf "$tmp"
fi
"$ROOT/bin/nakama" --version

step "密钥（只在第一次生成）"
if [[ ! -f "$SECRETS" ]]; then
	umask 077
	cat >"$SECRETS" <<EOF
DB_PASSWORD=$(rand_hex 24)
SERVER_KEY=$(rand_hex 16)
SESSION_ENCRYPTION_KEY=$(rand_hex 32)
SESSION_REFRESH_ENCRYPTION_KEY=$(rand_hex 32)
RUNTIME_HTTP_KEY=$(rand_hex 24)
CONSOLE_USER=admin
CONSOLE_PASSWORD=$(rand_hex 16)
CONSOLE_SIGNING_KEY=$(rand_hex 32)
EOF
	umask 022
	echo "已生成 $SECRETS"
fi
chmod 600 "$SECRETS"
chown root:root "$SECRETS"
# shellcheck disable=SC1090
source "$SECRETS"

step "数据库 nakama / 角色 tongsui"
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='tongsui'" | grep -q 1; then
	sudo -u postgres psql -q -c "CREATE ROLE tongsui LOGIN PASSWORD '$DB_PASSWORD'"
else
	sudo -u postgres psql -q -c "ALTER ROLE tongsui PASSWORD '$DB_PASSWORD'"
fi
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='nakama'" | grep -q 1; then
	sudo -u postgres createdb -O tongsui nakama
fi

step "Nakama 配置 $ROOT/config.yml"
umask 027
cat >"$ROOT/config.yml" <<EOF
# setup.sh 每次按 secrets.env 重写，别手改（改 setup.sh 或 secrets.env）
name: tongsui-1
data_dir: $ROOT/data
logger:
  level: INFO
  stdout: true
  file: ""
database:
  address:
    - tongsui:$DB_PASSWORD@127.0.0.1:5432/nakama
socket:
  address: 127.0.0.1
  port: 7350
  server_key: $SERVER_KEY
  max_message_size_bytes: 65536
session:
  token_expiry_sec: 604800
  refresh_token_expiry_sec: 2592000
  encryption_key: $SESSION_ENCRYPTION_KEY
  refresh_encryption_key: $SESSION_REFRESH_ENCRYPTION_KEY
runtime:
  path: $ROOT/modules
  js_entrypoint: index.js
  http_key: $RUNTIME_HTTP_KEY
console:
  address: 127.0.0.1
  port: 7351
  username: $CONSOLE_USER
  password: $CONSOLE_PASSWORD
  signing_key: $CONSOLE_SIGNING_KEY
match:
  input_queue_size: 128
  call_queue_size: 128
EOF
umask 022
chown root:tongsui "$ROOT/config.yml"
chmod 640 "$ROOT/config.yml"

step "服务端模块"
install -m 644 -o root -g root "$SRC/index.js" "$ROOT/modules/index.js"

step "systemd：tongsui.service + 每日备份"
install -m 644 "$SRC/tongsui.service" /etc/systemd/system/tongsui.service
install -m 755 "$SRC/backup.sh" "$ROOT/backup.sh"
install -m 644 "$SRC/tongsui-backup.service" /etc/systemd/system/tongsui-backup.service
install -m 644 "$SRC/tongsui-backup.timer" /etc/systemd/system/tongsui-backup.timer
systemctl daemon-reload
systemctl enable tongsui.service tongsui-backup.timer >/dev/null
systemctl start tongsui-backup.timer
# 已经在跑时先备份一次再换模块
if systemctl is-active --quiet tongsui; then
	"$ROOT/backup.sh" || die "更新前备份失败，没有重启"
fi
since="$(date '+%Y-%m-%d %H:%M:%S')"
systemctl restart tongsui

step "等 Nakama 起来"
for _ in $(seq 1 30); do
	curl -fsS --max-time 3 -o /dev/null http://127.0.0.1:7350/healthcheck 2>/dev/null && break
	sleep 1
done
curl -fsS --max-time 3 -o /dev/null http://127.0.0.1:7350/healthcheck || {
	journalctl -u tongsui --since "$since" --no-pager | tail -40
	die "Nakama 30 秒内没起来"
}
journalctl -u tongsui --since "$since" --no-pager | grep -q 'server module loaded' || {
	journalctl -u tongsui --since "$since" --no-pager | tail -40
	die "日志里没有 server module loaded"
}
journalctl -u tongsui --since "$since" --no-pager | grep -o '同岁 server module loaded[^"]*' | tail -1

step "nginx :$PUBLIC_PORT → 127.0.0.1:7350"
conf=/etc/nginx/sites-available/tongsui
if ! cmp -s "$SRC/nginx-tongsui.conf" "$conf" || [[ ! -L /etc/nginx/sites-enabled/tongsui ]]; then
	[[ -f "$conf" ]] && cp -a "$conf" "$conf.bak"
	install -m 644 "$SRC/nginx-tongsui.conf" "$conf"
	ln -sfn "$conf" /etc/nginx/sites-enabled/tongsui
	if ! nginx -t; then
		# 配置有错：撤回，nginx 保持原样（没 reload 过，正在跑的不受影响）
		if [[ -f "$conf.bak" ]]; then mv "$conf.bak" "$conf"; else rm -f "$conf" /etc/nginx/sites-enabled/tongsui; fi
		die "nginx -t 没过，已撤回 tongsui 的配置"
	fi
	# reload 不 restart：cakery 正连着的 WebSocket 不断
	systemctl reload nginx
	rm -f "$conf.bak"
fi
for _ in $(seq 1 10); do
	curl -fsS --max-time 3 -o /dev/null "http://127.0.0.1:$PUBLIC_PORT/healthcheck" 2>/dev/null && break
	sleep 1
done
curl -fsS --max-time 3 -o /dev/null "http://127.0.0.1:$PUBLIC_PORT/healthcheck" || die "nginx :$PUBLIC_PORT 到 Nakama 不通"

step "监听端口（Nakama 应该全在 127.0.0.1）"
ss -ltnp | grep -E ':(7349|7350|7351|'"$PUBLIC_PORT"')\b' || true
if ss -ltn | awk '{print $4}' | grep -E ':(7349|7350|7351)$' | grep -vqE '^(127\.0\.0\.1|\[::1\]):'; then
	die "Nakama 有端口没绑在 127.0.0.1 上"
fi

ip="$(curl -fsS --max-time 5 -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip 2>/dev/null || curl -fsS --max-time 5 https://api.ipify.org)"
json="{\"host\": \"$ip\", \"port\": $PUBLIC_PORT, \"scheme\": \"http\", \"server_key\": \"$SERVER_KEY\"}"
echo "$json" >"$ROOT/client-server.json"
chmod 644 "$ROOT/client-server.json"

step "完成"
echo "客户端配置（仓库变量 TONGSUI_SERVER）：$json"
echo "控制台：ssh -L 7351:127.0.0.1:7351 cakery，浏览器开 http://127.0.0.1:7351（账号密码：sudo grep CONSOLE $SECRETS）"
