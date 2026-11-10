#!/usr/bin/env bash
# 同岁 · 备份 PostgreSQL（所有账号和人生存档都在这里）
#
#   sudo bash deploy/backup.sh            # 备份到 /opt/tongsui-backups（非 root 时是 deploy/backups）
#   TONGSUI_BACKUP_DIR=/data/bak sudo bash deploy/backup.sh
#
# install.sh 会装一个每天 04:30 的定时任务（/etc/cron.d/tongsui-backup），默认保留 14 天
# （TONGSUI_BACKUP_KEEP_DAYS 可改）。服务不用停，pg_dump 是在线备份。
#
# 备份只放在本机，机器挂了也就没了。建议再同步一份到别处，例如：
#   rclone copy /opt/tongsui-backups 你的网盘:tongsui-backups      （rclone 支持阿里云盘 / OSS / COS / S3 等）
#   scp root@服务器:/opt/tongsui-backups/tongsui-*.sql.gz ./        （在自己电脑上拉下来）
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

if [[ $EUID -eq 0 ]]; then
	BACKUP_DIR="${TONGSUI_BACKUP_DIR:-/opt/tongsui-backups}"
else
	BACKUP_DIR="${TONGSUI_BACKUP_DIR:-$DEPLOY_DIR/backups}"
fi
KEEP_DAYS="${TONGSUI_BACKUP_KEEP_DAYS:-14}"

umask 077
mkdir -p "$BACKUP_DIR"
[[ -n "$(dc ps -q --status running postgres 2>/dev/null)" ]] || die "postgres 没在运行，没法备份（docker compose -f $COMPOSE_FILE ps 看看）"

# TONGSUI_BACKUP_TAG 会加在文件名后面（restore.sh / update.sh 用来区分自动备份）
stamp="tongsui-$(date +%Y%m%d-%H%M%S)${TONGSUI_BACKUP_TAG:+-$TONGSUI_BACKUP_TAG}"
name="$stamp.sql.gz"
for ((n = 2; ; n++)); do
	[[ -e $BACKUP_DIR/$name ]] || break
	name="$stamp-$n.sql.gz"
done
tmp="$BACKUP_DIR/.$name.partial"
trap 'rm -f "$tmp"' EXIT

echo "[$(date '+%F %T')] 备份到 $BACKUP_DIR/$name"
dc exec -T postgres pg_dump -U postgres -d nakama --no-owner --clean --if-exists | gzip -6 >"$tmp"
gzip -t "$tmp"
# 小于 1 KB 基本就是空的，宁可报错也别留一个假备份
(($(stat -c %s "$tmp") > 1024)) || die "备份文件太小，可能没导出成功"
mv "$tmp" "$BACKUP_DIR/$name"
trap - EXIT

find "$BACKUP_DIR" -maxdepth 1 -name 'tongsui-*.sql.gz' -type f -mtime +"$((KEEP_DAYS - 1))" -print -delete | sed 's/^/  删除旧备份 /'
echo "[$(date '+%F %T')] 完成：$(du -h "$BACKUP_DIR/$name" | cut -f1)，现有 $(find "$BACKUP_DIR" -maxdepth 1 -name 'tongsui-*.sql.gz' | wc -l) 份"
echo "$BACKUP_DIR/$name"
