#!/usr/bin/env bash
# 同岁 · 更新服务端：拉代码 → 备份 → 重新构建模块 → 重启 → 健康检查。存档不受影响。
#
#   sudo bash deploy/update.sh                     # 常规更新
#   sudo bash deploy/update.sh --module index.js   # 用 GitHub Actions 的 server-module 产物，不在本机构建
#   sudo bash deploy/update.sh --no-pull           # 不拉代码，只按当前代码 / .env 重启（改了 .env 后用这个）
#   加 --no-backup 跳过更新前的备份
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

pull=1 backup=1 module=''
args=("$@")
while (($#)); do
	case $1 in
	--no-pull) pull=0; shift ;;
	--no-backup) backup=0; shift ;;
	--module) module="$(realpath -m "${2:?--module 后面要跟 index.js 路径}")"; shift 2 ;;
	--module=*) module="$(realpath -m "${1#*=}")"; shift ;;
	-h | --help) sed -n '2,8p' "$0"; exit 0 ;;
	*) die "不认识的参数：$1" ;;
	esac
done
[[ -f $ENV_FILE ]] || die "没有 $ENV_FILE，第一次部署请用 install.sh"

if ((pull)) && [[ ! -d $REPO_DIR/.git ]]; then
	ok "这份代码是用 ship.sh 从电脑传上来的（没有 .git），跳过 git pull；要更新就在电脑上再跑一次 ship.sh"
	pull=0
fi
if ((pull)); then
	step "拉取最新代码"
	g() { git -c safe.directory="$REPO_DIR" -C "$REPO_DIR" "$@"; }
	if ! g diff --quiet || ! g diff --cached --quiet; then die "仓库里有未提交的改动（git -C $REPO_DIR status 看看），处理后再更新，或用 --no-pull"; fi
	before="$(g rev-parse HEAD)"
	g pull -q --ff-only || die "git pull 失败（网络问题，或者本地提交和远端分叉了）"
	after="$(g rev-parse HEAD)"
	if [[ $before == "$after" ]]; then
		ok "已经是最新：$(g log -1 --format='%h %s')"
	else
		ok "$(g log --oneline "$before..$after" | wc -l) 个新提交，现在是 $(g log -1 --format='%h %s')"
		# 用新版本的脚本继续（脚本本身可能也更新了）
		exec bash "$DEPLOY_DIR/update.sh" --no-pull "${args[@]}"
	fi
fi

if ((backup)); then
	step "更新前先备份"
	if [[ -n "$(dc ps -q --status running postgres 2>/dev/null)" ]]; then
		TONGSUI_BACKUP_TAG=pre-update bash "$DEPLOY_DIR/backup.sh"
	else
		warn "postgres 没在运行，跳过备份"
	fi
fi

step "服务端模块"
if [[ -n $module ]]; then use_module "$module"; else build_module; fi

step "重启服务"
dc up -d --remove-orphans --quiet-pull
dc restart nakama >/dev/null
dc exec -T caddy caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1 || dc restart caddy >/dev/null
wait_nakama 180 || die "Nakama 没起来，看上面的日志。可以用 restore.sh 回滚数据，或 git checkout 旧版本后再跑 --no-pull"
check_module_loaded || die "服务端模块没加载成功"

domain="$(env_get DOMAIN)"
step "检查 https://$domain/healthcheck"
rc=0
check_https "$domain" 12 || rc=$?
case $rc in
0) ok "公网 HTTPS 正常" ;;
1)
	case $domain in
	localhost | *.localhost | 127.*) ok "本机 HTTPS 正常（localhost 自签证书）" ;;
	*) warn "本机 443 通，但公网证书 / DNS 有问题，见 docs/DEPLOY.md 排错" ;;
	esac
	;;
*) die "443 不通，docker compose -f $COMPOSE_FILE logs caddy 看看" ;;
esac
ok "更新完成"
