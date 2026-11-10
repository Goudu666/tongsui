#!/usr/bin/env bash
# 同岁 · 从备份恢复数据库（会覆盖当前所有存档！）
#
#   sudo bash deploy/restore.sh /opt/tongsui-backups/tongsui-20260101-043000.sql.gz
#   加 --yes 跳过确认（脚本 / CI 用）
#
# 恢复前会先自动备份一次当前数据库，后悔了还能再恢复回来。
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

file='' yes=0
for a in "$@"; do
	case $a in
	-y | --yes) yes=1 ;;
	-h | --help) sed -n '2,7p' "$0"; exit 0 ;;
	*) file=$a ;;
	esac
done
[[ -n $file ]] || die "用法：sudo bash deploy/restore.sh 备份文件.sql.gz [--yes]"
[[ -f $file ]] || die "找不到备份文件：$file"
gzip -t "$file" || die "备份文件损坏：$file"
[[ -n "$(dc ps -q --status running postgres 2>/dev/null)" ]] || die "postgres 没在运行，先 docker compose -f $COMPOSE_FILE --profile prod up -d postgres"

if ((yes == 0)); then
	echo "即将用 $file 覆盖当前数据库，所有账号和存档会回到备份时的样子。"
	answer=''
	if { exec 3</dev/tty; } 2>/dev/null; then
		read -r -p "确定请输入 yes：" answer <&3 || true
		exec 3<&-
	fi
	[[ $answer == yes ]] || die "已取消"
fi

step "先备份当前数据库"
TONGSUI_BACKUP_TAG=pre-restore bash "$DEPLOY_DIR/backup.sh"

step "停 Nakama，恢复数据"
dc stop nakama >/dev/null
# 重建空库再导入，避免残留表
dc exec -T postgres psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q \
	-c 'DROP DATABASE IF EXISTS nakama WITH (FORCE);' -c 'CREATE DATABASE nakama;'
gzip -dc "$file" | dc exec -T postgres psql -U postgres -d nakama -v ON_ERROR_STOP=1 -q >/dev/null
ok "数据已导入"

step "启动 Nakama"
dc up -d nakama >/dev/null 2>&1
wait_nakama 180 || die "Nakama 没起来"
check_module_loaded || true
ok "恢复完成"
