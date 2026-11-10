#!/usr/bin/env bash
# 同岁 · 一键部署（Ubuntu 24.04 / Debian 12，2 核 2 GB 就够）
#
#   curl -fsSL https://raw.githubusercontent.com/Goudu666/tongsui/main/deploy/install.sh | sudo bash -s -- --domain tongsui.example.com
#   或者 git clone 之后：sudo bash deploy/install.sh [--domain 域名] [--email 邮箱]
#
# 可以反复运行：已有的 deploy/.env 密钥不会被覆盖，只会补上缺的。
# 详见 docs/DEPLOY.md
set -euo pipefail

REPO_URL="${TONGSUI_REPO_URL:-https://github.com/Goudu666/tongsui.git}"
BRANCH="${TONGSUI_BRANCH:-main}"
INSTALL_DIR="${TONGSUI_DIR:-/opt/tongsui}"

usage() {
	cat <<'EOF'
用法：sudo bash deploy/install.sh [选项]

  --domain 域名      客户端连接的域名（先加 A 记录指向本机）。
                     不填就用 <公网IP>.sslip.io，免买域名也能拿到正式 HTTPS 证书
  --email 邮箱       Let's Encrypt 通知邮箱（可选）
  --module 文件      用现成的 index.js（比如 GitHub Actions 的 server-module 产物），不在本机构建
  --no-system        只管 Docker 里的服务：不装 Docker、不动防火墙 / fail2ban / 定时备份 / swap，
                     也不要求 root（CI 冒烟用，等同 TONGSUI_DRY_SYSTEM=1）
  -h, --help         显示帮助

环境变量：TONGSUI_DIR（默认 /opt/tongsui）、TONGSUI_BRANCH（默认 main）、
          TONGSUI_NODE_IMAGE、TONGSUI_DOCKER_RUN_ARGS（见 deploy/lib.sh）
EOF
}

# ---------- 参数 ----------
DOMAIN_ARG='' EMAIL_ARG='' MODULE_ARG=''
NO_SYSTEM="${TONGSUI_DRY_SYSTEM:-0}"
ORIG_ARGS=("$@")
parse_args() {
	while (($#)); do
		case $1 in
		--domain) DOMAIN_ARG=${2:?--domain 后面要跟域名}; shift 2 ;;
		--domain=*) DOMAIN_ARG=${1#*=}; shift ;;
		--email) EMAIL_ARG=${2:?--email 后面要跟邮箱}; shift 2 ;;
		--email=*) EMAIL_ARG=${1#*=}; shift ;;
		--module) MODULE_ARG=${2:?--module 后面要跟 index.js 路径}; shift 2 ;;
		--module=*) MODULE_ARG=${1#*=}; shift ;;
		--no-system) NO_SYSTEM=1; shift ;;
		-h | --help) usage; exit 0 ;;
		*) echo "不认识的参数：$1（--help 看用法）" >&2; exit 2 ;;
		esac
	done
	[[ $NO_SYSTEM == 1 ]] || NO_SYSTEM=0
	if [[ -n $DOMAIN_ARG && ! $DOMAIN_ARG =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
		echo "域名格式不对：$DOMAIN_ARG（只填域名，不要带 https:// 或端口）" >&2
		exit 2
	fi
	if [[ -n $EMAIL_ARG && ! $EMAIL_ARG =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]]; then
		echo "邮箱格式不对：$EMAIL_ARG" >&2
		exit 2
	fi
	if [[ -n $MODULE_ARG ]]; then
		MODULE_ARG="$(realpath -m "$MODULE_ARG")"
	fi
}

need_root() {
	if [[ $NO_SYSTEM == 0 && $EUID -ne 0 ]]; then
		echo "请用 root 运行：sudo bash $0 ..." >&2
		exit 1
	fi
}

export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
apt_install() {
	# 新机器开机时 unattended-upgrades 可能占着 apt 锁，等它最多 5 分钟
	apt-get -o DPkg::Lock::Timeout=300 -qq update </dev/null
	apt-get -o DPkg::Lock::Timeout=300 -y -qq install --no-install-recommends "$@" </dev/null >/dev/null
}

# 从 curl | bash 运行时还没有仓库：先 clone 到 /opt/tongsui，再用仓库里的脚本重新执行
bootstrap_repo() {
	local self="${BASH_SOURCE[0]:-}" dir=''
	if [[ -n $self && -f $self ]]; then
		dir="$(cd "$(dirname "$self")" && pwd)"
		if [[ -f $dir/docker-compose.yml && -f $dir/lib.sh ]]; then
			return 0
		fi
	fi
	need_root
	echo "==> 准备代码：$INSTALL_DIR"
	if ! command -v git >/dev/null || ! command -v curl >/dev/null; then
		command -v apt-get >/dev/null || { echo "只支持 Ubuntu / Debian（apt）" >&2; exit 1; }
		apt_install git curl ca-certificates
	fi
	if [[ -d $INSTALL_DIR/.git ]]; then
		git -c safe.directory="$INSTALL_DIR" -C "$INSTALL_DIR" fetch -q origin "$BRANCH"
		git -c safe.directory="$INSTALL_DIR" -C "$INSTALL_DIR" merge -q --ff-only "origin/$BRANCH" ||
			echo "    ! $INSTALL_DIR 有本地改动，没法快进更新，先用现有代码继续" >&2
	elif [[ -e $INSTALL_DIR ]]; then
		echo "$INSTALL_DIR 已存在但不是 git 仓库，请先移走它" >&2
		exit 1
	else
		git clone -q --depth 1 -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
	fi
	exec bash "$INSTALL_DIR/deploy/install.sh" "${ORIG_ARGS[@]}"
}

# ---------- 系统准备 ----------
prepare_system() {
	step "系统准备"
	command -v apt-get >/dev/null || die "只支持 Ubuntu / Debian（apt）"
	local pkgs=()
	for p in curl git ca-certificates cron; do
		dpkg -s "$p" >/dev/null 2>&1 || pkgs+=("$p")
	done
	((${#pkgs[@]} == 0)) || { info "安装 ${pkgs[*]}"; apt_install "${pkgs[@]}"; }
	systemctl enable --now cron >/dev/null 2>&1 || true

	if ! command -v docker >/dev/null; then
		info "安装 Docker（get.docker.com 官方脚本）"
		local tmp
		tmp="$(mktemp)"
		curl -fsSL https://get.docker.com -o "$tmp"
		sh "$tmp" </dev/null >/dev/null
		rm -f "$tmp"
	fi
	systemctl enable --now docker >/dev/null 2>&1 || true
	if ! docker compose version >/dev/null 2>&1; then
		info "安装 docker compose 插件"
		apt_install docker-compose-plugin || die "装不上 docker compose 插件，请参考 https://docs.docker.com/engine/install/"
	fi
	ok "$(docker --version)，$(docker compose version --short 2>/dev/null | sed 's/^/compose /')"

	# 2 GB 内存没有 swap 时，构建 / 高峰期容易被 OOM，补一个 1 GB 的 swap 文件
	if [[ -z "$(swapon --noheadings 2>/dev/null)" && ! -e /swapfile ]] &&
		(($(awk '/MemTotal/ {print $2}' /proc/meminfo) < 3500000)); then
		if { fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none; } &&
			chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile; then
			grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
			ok "已添加 1 GB swap"
		else
			rm -f /swapfile
			warn "加 swap 失败（有些 VPS 不允许），跳过"
		fi
	fi
}

# ---------- 防火墙与加固 ----------
setup_firewall() {
	step "防火墙（ufw）"
	command -v ufw >/dev/null || apt_install ufw
	# 先放行当前在用的 SSH 端口，免得把自己关在外面
	local ports=(22) p
	while read -r p; do [[ -n $p ]] && ports+=("$p"); done < <(sshd -T 2>/dev/null | awk '$1 == "port" {print $2}')
	if [[ -n ${SSH_CONNECTION:-} ]]; then ports+=("$(awk '{print $4}' <<<"$SSH_CONNECTION")"); fi
	for p in $(printf '%s\n' "${ports[@]}" | sort -un); do
		ufw allow "$p/tcp" comment 'ssh' >/dev/null
	done
	ufw allow 80/tcp comment 'http (证书申请)' >/dev/null
	ufw allow 443/tcp comment 'https' >/dev/null
	ufw allow 443/udp comment 'http3' >/dev/null
	ufw --force enable >/dev/null
	ok "已放行 SSH($(printf '%s\n' "${ports[@]}" | sort -un | paste -sd,)) / 80 / 443，其余入站拒绝"
	info "7350 / 7351 只绑 127.0.0.1；Docker 映射的端口会绕过 ufw，所以只映射了 80 / 443"
	info "别忘了云厂商控制台的「安全组 / 防火墙」也要放行 22、80、443"
}

setup_hardening() {
	step "基础加固"
	apt_install unattended-upgrades fail2ban python3-systemd
	cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
	ok "自动安装安全更新（unattended-upgrades）"
	# Debian 12 没有 /var/log/auth.log，统一读 systemd 日志
	cat >/etc/fail2ban/jail.d/tongsui-sshd.local <<'EOF'
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF
	if systemctl enable fail2ban >/dev/null 2>&1 && systemctl restart fail2ban; then
		ok "fail2ban 已保护 SSH（10 分钟输错 5 次封 1 小时）"
	else
		warn "fail2ban 没起来，不影响游戏服务：journalctl -u fail2ban 看原因"
	fi
	if sshd -T 2>/dev/null | grep -qi '^passwordauthentication yes'; then
		warn "SSH 还允许密码登录。建议配好密钥后在 /etc/ssh/sshd_config 设 PasswordAuthentication no（脚本不会替你改）"
	fi
}

setup_backup_cron() {
	step "每日备份"
	cat >/etc/cron.d/tongsui-backup <<EOF
# 同岁：每天 04:30（服务器时区）备份 PostgreSQL，保留 14 天。由 install.sh 生成
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
30 4 * * * root $DEPLOY_DIR/backup.sh >>/var/log/tongsui-backup.log 2>&1
EOF
	chmod 644 /etc/cron.d/tongsui-backup
	ok "/etc/cron.d/tongsui-backup → /opt/tongsui-backups（日志 /var/log/tongsui-backup.log）"
}

# ---------- 配置 ----------
detect_public_ip() {
	local ip url
	for url in https://api.ipify.org https://ifconfig.me/ip https://ipv4.icanhazip.com https://4.ipw.cn; do
		ip="$(curl -4 -fsS --max-time 6 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
		if [[ $ip =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
			echo "$ip"
			return 0
		fi
	done
	return 1
}

pgdata_exists() {
	docker volume inspect "${COMPOSE_PROJECT_NAME:-tongsui}_pgdata" >/dev/null 2>&1
}

setup_env() {
	step "配置 deploy/.env"
	local created=0 key val
	umask 077
	if [[ ! -f $ENV_FILE ]]; then
		: >"$ENV_FILE"
		created=1
		{
			echo "# 同岁线上配置，由 install.sh 于 $(date '+%F %T') 生成。不要提交，不要发给别人。"
			echo "# 改完执行 sudo bash deploy/update.sh --no-pull 生效"
		} >>"$ENV_FILE"
	fi
	chmod 600 "$ENV_FILE"

	# 空的或还是 change-me 示例值的才生成；已有密钥一律不动
	for key in POSTGRES_PASSWORD NAKAMA_SERVER_KEY NAKAMA_CONSOLE_PASSWORD \
		NAKAMA_SESSION_ENCRYPTION_KEY NAKAMA_SESSION_REFRESH_ENCRYPTION_KEY \
		NAKAMA_RUNTIME_HTTP_KEY NAKAMA_CONSOLE_SIGNING_KEY; do
		val="$(env_get "$key")"
		if [[ -n $val && $val != change-me* ]]; then
			continue
		fi
		if [[ $key == POSTGRES_PASSWORD && -n $val ]] && pgdata_exists; then
			warn "POSTGRES_PASSWORD 还是示例值，但数据库已经用它初始化了，先不改（要改得进 psql 改密码）"
			continue
		fi
		env_set "$key" "$(rand_hex 24)"
		info "生成 $key"
	done
	[[ -n "$(env_get NAKAMA_CONSOLE_USER)" ]] || env_set NAKAMA_CONSOLE_USER admin

	# 域名：参数 > .env 里已有的 > 公网 IP.sslip.io
	local domain
	domain="$(env_get DOMAIN)"
	if [[ -n $DOMAIN_ARG ]]; then
		domain=$DOMAIN_ARG
	elif [[ -z $domain || $domain == tongsui.example.com ]]; then
		local ip
		ip="$(detect_public_ip)" || die "没查到本机公网 IPv4，请用 --domain 指定域名"
		domain="${ip//./-}.sslip.io"
		info "没给 --domain，使用 $domain（sslip.io 会把它解析成 $ip）"
	fi
	env_set DOMAIN "$domain"
	if [[ -n $EMAIL_ARG ]]; then
		env_set ACME_EMAIL "$EMAIL_ARG"
	elif ! grep -q '^ACME_EMAIL=' "$ENV_FILE"; then
		env_set ACME_EMAIL ''
	fi
	umask 022
	DOMAIN="$domain"
	if ((created)); then ok "已生成 $ENV_FILE（权限 600）"; else ok "沿用已有 $ENV_FILE"; fi
	ok "域名：$DOMAIN"

	# 域名解析到别处时提前提醒（证书会申请失败）
	case $DOMAIN in localhost | *.localhost | *.sslip.io) return 0 ;; esac
	local resolved myip
	resolved="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk 'NR == 1 {print $1}' || true)"
	if [[ -z $resolved ]]; then
		warn "$DOMAIN 还解析不到。请在域名商加 A 记录指向本机公网 IP；解析生效前证书申请不了"
	elif myip="$(detect_public_ip)" && [[ $resolved != "$myip" ]]; then
		warn "$DOMAIN 解析到 $resolved，但本机公网 IP 是 $myip，证书可能申请失败"
	fi
}

prepare_module() {
	step "服务端模块"
	if [[ -n $MODULE_ARG ]]; then
		use_module "$MODULE_ARG"
	else
		build_module
	fi
}

# ---------- 启动与检查 ----------
start_stack() {
	step "启动服务（postgres + nakama + caddy）"
	local was_running
	was_running="$(dc ps -q --status running nakama 2>/dev/null || true)"
	dc up -d --remove-orphans --quiet-pull
	if [[ -n $was_running ]]; then
		info "Nakama 之前就在跑，重启一下加载新模块"
		dc restart nakama >/dev/null
		dc exec -T caddy caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1 || true
	fi
	wait_nakama 180 || die "Nakama 没起来，看上面的日志；也可以 docker compose -f $COMPOSE_FILE logs nakama"
	check_module_loaded || die "服务端模块没加载成功"
}

HTTPS_STATE=0
verify_https() {
	step "检查 https://$DOMAIN/healthcheck"
	local rc=0
	# 第一次申请证书要几十秒，最多等 2 分钟
	check_https "$DOMAIN" 24 || rc=$?
	HTTPS_STATE=$rc
	case $rc in
	0) ok "公网 HTTPS 正常，证书有效" ;;
	1)
		case $DOMAIN in
		localhost | *.localhost | 127.*) ok "本机 HTTPS 正常（localhost 用的是 Caddy 自签证书，只适合测试）" ;;
		*)
			warn "本机 443 能通，但正式证书还没拿到或 DNS 还没生效。常见原因："
			warn "  1) 云厂商安全组没放行 80 / 443（Let's Encrypt 要从公网访问 80 端口）"
			warn "  2) 域名 A 记录还没生效（刚加的等几分钟，或者 ping $DOMAIN 看看）"
			warn "  看 Caddy 日志：docker compose -f $COMPOSE_FILE logs caddy | grep -i -E 'error|challenge'"
			warn "  修好后什么都不用重启，Caddy 会自己重试；再运行一次本脚本也行"
			;;
		esac
		;;
	*)
		dc logs --tail 30 caddy >&2 || true
		die "本机 443 都不通，Caddy 可能没起来（端口 80/443 被别的程序占了？ss -ltnp | grep -E ':(80|443) '）"
		;;
	esac
}

write_client_json() {
	local key
	key="$(env_get NAKAMA_SERVER_KEY)"
	printf '{"host": "%s", "port": 443, "scheme": "https", "server_key": "%s"}\n' "$DOMAIN" "$key" >"$CLIENT_JSON"
	chmod 644 "$CLIENT_JSON"
}

print_summary() {
	local key line='════════════════════════════════════════════════════════════════'
	key="$(env_get NAKAMA_SERVER_KEY)"
	cat <<EOF

$_c_g$line$_c_0
  ${_c_b}同岁服务器已上线$_c_0

  地址        https://$DOMAIN   （端口 443，WebSocket 走 wss://$DOMAIN/ws）
  host        $DOMAIN
  port        443
  scheme      https
  server_key  $key

  客户端配置（已写入 $CLIENT_JSON）：

  $_c_b$(cat "$CLIENT_JSON")$_c_0

  下一步：把上面这行 JSON 原样粘到 GitHub 仓库
    Settings → Secrets and variables → Actions → Variables → New repository variable
    名字填 TONGSUI_SERVER，然后重新运行 Actions，下载新的 APK 两个人各装一个。
    （装了 gh 的话：gh variable set TONGSUI_SERVER < $CLIENT_JSON）

  管理控制台：ssh -L 7351:127.0.0.1:7351 你的服务器，然后浏览器开 http://127.0.0.1:7351
              账号 $(env_get NAKAMA_CONSOLE_USER)，密码见 $ENV_FILE 的 NAKAMA_CONSOLE_PASSWORD
  更新服务端：sudo bash $DEPLOY_DIR/update.sh
  手动备份：  sudo bash $DEPLOY_DIR/backup.sh
$_c_g$line$_c_0
EOF
	if [[ $HTTPS_STATE != 0 ]]; then
		case $DOMAIN in
		localhost | *.localhost | 127.*) ;;
		*) warn "注意：公网证书还没就绪（见上面的提示），好了之后客户端才能连上" ;;
		esac
	fi
}

main() {
	parse_args "$@"
	bootstrap_repo
	# shellcheck source-path=SCRIPTDIR source=lib.sh
	source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
	need_root
	if [[ $NO_SYSTEM == 1 ]]; then
		info "--no-system：跳过 Docker 安装 / 防火墙 / 加固 / 定时备份"
		docker compose version >/dev/null 2>&1 || die "需要 docker 和 docker compose"
	else
		prepare_system
	fi
	setup_env
	prepare_module
	if [[ $NO_SYSTEM == 0 ]]; then
		setup_firewall
		setup_hardening
	fi
	start_stack
	verify_https
	[[ $NO_SYSTEM == 1 ]] || setup_backup_cron
	write_client_json
	print_summary
}

main "$@"
