#!/usr/bin/env bash
# 同岁数据库在线备份：/opt/tongsui-backups/tongsui-<时间>.sql.gz，保留 14 天（TONGSUI_BACKUP_KEEP_DAYS 可改）
# 恢复：sudo /opt/tongsui/restore.sh 备份.sql.gz（要以 tongsui 身份导入，别直接 psql，见 restore.sh）
set -euo pipefail
dir=/opt/tongsui-backups
keep="${TONGSUI_BACKUP_KEEP_DAYS:-14}"
mkdir -p "$dir"
chmod 700 "$dir"
out="$dir/tongsui-$(date -u +%Y%m%d-%H%M%S).sql.gz"
tmp="$out.part"
sudo -u postgres pg_dump -d nakama --no-owner --clean --if-exists | gzip -6 >"$tmp"
gzip -t "$tmp"
mv "$tmp" "$out"
find "$dir" -name 'tongsui-*.sql.gz' -mtime +"$keep" -delete
echo "备份完成：$out（$(du -h "$out" | cut -f1)）"
