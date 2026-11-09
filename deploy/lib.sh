# shellcheck shell=bash
# 部署脚本共用的小工具，被 install.sh / update.sh / backup.sh / restore.sh / ci-smoke.sh source。
# 不要直接运行。

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$DEPLOY_DIR")"
COMPOSE_FILE="$DEPLOY_DIR/docker-compose.yml"
ENV_FILE="$DEPLOY_DIR/.env"
CLIENT_JSON="$DEPLOY_DIR/client-server.json"
MODULE_FILE="$REPO_DIR/server/build/index.js"
export DEPLOY_DIR REPO_DIR COMPOSE_FILE ENV_FILE CLIENT_JSON MODULE_FILE

if [[ -t 1 ]]; then
	_c_g=$'\e[32m' _c_y=$'\e[33m' _c_r=$'\e[31m' _c_b=$'\e[1m' _c_0=$'\e[0m'
else
	_c_g='' _c_y='' _c_r='' _c_b='' _c_0=''
fi
step() { printf '\n%s==> %s%s\n' "$_c_b" "$*" "$_c_0"; }
info() { printf '    %s\n' "$*"; }
ok() { printf '    %s✓ %s%s\n' "$_c_g" "$*" "$_c_0"; }
warn() { printf '    %s! %s%s\n' "$_c_y" "$*" "$_c_0" >&2; }
die() {
	printf '\n%s✗ %s%s\n' "$_c_r" "$*" "$_c_0" >&2
	exit 1
}

# 线上一律带 prod profile（多了 Caddy）；项目名可用 COMPOSE_PROJECT_NAME 覆盖（CI 冒烟用）
dc() { docker compose -f "$COMPOSE_FILE" --profile prod "$@"; }

# 读 .env 里的某个值（没有就输出空）
env_get() {
	[[ -f $ENV_FILE ]] || return 0
	awk -v k="$1" 'index($0, k "=") == 1 { v = substr($0, length(k) + 2) } END { gsub(/^["'\'']|["'\'']$/, "", v); print v }' "$ENV_FILE"
}

# 写 .env 里的某个值（有就替换，没有就追加），保留其他行和注释
env_set() {
	local key=$1 val=$2 tmp
	tmp="$(mktemp "$ENV_FILE.XXXXXX")"
	if [[ -f $ENV_FILE ]] && grep -q "^$key=" "$ENV_FILE"; then
		K="$key" V="$val" awk 'index($0, ENVIRON["K"] "=") == 1 { print ENVIRON["K"] "=" ENVIRON["V"]; next } { print }' "$ENV_FILE" >"$tmp"
	else
		{ [[ -f $ENV_FILE ]] && cat "$ENV_FILE"; printf '%s=%s\n' "$key" "$val"; } >"$tmp"
	fi
	chmod 600 "$tmp"
	mv "$tmp" "$ENV_FILE"
}

# 只含 0-9a-f 的随机串，放进数据库连接串、命令行都安全
rand_hex() { od -vAn -N"${1:-24}" -tx1 /dev/urandom | tr -d ' \n'; }

# 在 Node 容器里构建服务端模块，宿主机不用装 Node。
#   TONGSUI_NODE_IMAGE      换构建镜像（默认 node:22-alpine）
#   TONGSUI_DOCKER_RUN_ARGS 给 docker run 的额外参数，比如走代理：--network host -e HTTPS_PROXY
build_module() {
	local image="${TONGSUI_NODE_IMAGE:-node:22-alpine}" owner extra=()
	owner="$(stat -c %u:%g "$REPO_DIR")"
	if [[ -n ${TONGSUI_DOCKER_RUN_ARGS:-} ]]; then
		read -r -a extra <<<"$TONGSUI_DOCKER_RUN_ARGS"
	fi
	info "用 $image 构建 server/build/index.js（第一次要下载依赖，约 1 分钟）"
	# nakama-runtime 是 GitHub 依赖：npm 优先下 tarball，失败才会用 git，所以顺手装上 git 兜底
	docker run --rm "${extra[@]}" -e OWNER="$owner" -v "$REPO_DIR:/src" -w /src "$image" sh -ec '
		command -v git >/dev/null 2>&1 || apk add --no-cache git >/dev/null 2>&1 || true
		if command -v git >/dev/null 2>&1; then
			git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
			git config --global --add safe.directory "*"
		fi
		npm ci --no-audit --no-fund --loglevel=error
		npm run server:build --silent
		chown -R "$OWNER" node_modules server/node_modules server/build
	' || die "服务端模块构建失败。也可以从 GitHub Actions 下载 server-module 产物，用 --module 路径/index.js 指定"
	[[ -s $MODULE_FILE ]] || die "构建完了却没找到 $MODULE_FILE"
	ok "模块已构建：$(du -h "$MODULE_FILE" | cut -f1)"
}

# 用现成的 index.js（比如 CI 产物）代替构建
use_module() {
	local src=$1
	[[ -s $src ]] || die "找不到模块文件：$src"
	mkdir -p "$(dirname "$MODULE_FILE")"
	if [[ "$(realpath "$src")" != "$(realpath -m "$MODULE_FILE")" ]]; then
		cp "$src" "$MODULE_FILE"
	fi
	chmod 644 "$MODULE_FILE"
	ok "使用现成模块：$src"
}

# 等 Nakama 健康（默认 180 秒）
wait_nakama() {
	local timeout=${1:-180} cid status=''
	for ((i = 0; i < timeout; i += 3)); do
		cid="$(dc ps -q nakama 2>/dev/null || true)"
		if [[ -n $cid ]]; then
			status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || true)"
			[[ $status == healthy ]] && { ok "Nakama 健康"; return 0; }
		fi
		sleep 3
	done
	warn "Nakama 在 ${timeout}s 内没变健康（状态：${status:-无}），最近日志："
	dc logs --tail 40 nakama >&2 || true
	return 1
}

# 日志里有「server module loaded」才算服务端逻辑真的加载了
check_module_loaded() {
	local line
	for _ in 1 2 3 4 5; do
		line="$(dc logs nakama 2>&1 | grep 'server module loaded' | tail -1 || true)"
		[[ -n $line ]] && { ok "模块已加载：$(sed -E 's/.*"msg":"([^"]*)".*/\1/' <<<"$line")"; return 0; }
		sleep 2
	done
	warn "Nakama 日志里没看到 server module loaded，最近日志："
	dc logs --tail 40 nakama >&2 || true
	return 1
}

# 检查 https://域名/healthcheck
#   返回 0：公网证书 OK；1：本机 443 通但证书 / DNS 还没好；2：本机 443 也不通
check_https() {
	local domain=$1 tries=${2:-1}
	local local_only=0
	case $domain in localhost | *.localhost | 127.*) local_only=1 ;; esac
	for ((i = 0; i < tries; i++)); do
		if ((local_only == 0)) && curl -fsS --max-time 8 -o /dev/null "https://$domain/healthcheck" 2>/dev/null; then
			return 0
		fi
		if ((local_only)) && curl -kfsS --max-time 8 -o /dev/null --resolve "$domain:443:127.0.0.1" "https://$domain/healthcheck" 2>/dev/null; then
			return 1
		fi
		((i + 1 < tries)) && sleep 5
	done
	if curl -kfsS --max-time 8 -o /dev/null --resolve "$domain:443:127.0.0.1" "https://$domain/healthcheck" 2>/dev/null; then
		return 1
	fi
	return 2
}
