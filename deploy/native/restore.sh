#!/usr/bin/env bash
# 同岁数据库恢复（原生部署）：sudo /opt/tongsui/restore.sh /opt/tongsui-backups/tongsui-<时间>.sql.gz
# 先停服、恢复前再备份一次当前库，整份在一个事务里导入（中途出错就整份不算，库保持原样），再起服。
# 以 tongsui 身份导入：备份是 --no-owner 的，直接用 postgres 导入会让表都归 postgres，Nakama 读不了自己的表。
set -euo pipefail
file="${1:-}"
[[ $EUID -eq 0 ]] || { echo "要用 sudo 运行" >&2; exit 1; }
[[ -f "$file" ]] || { echo "用法：sudo $0 /opt/tongsui-backups/tongsui-<时间>.sql.gz" >&2; ls -1t /opt/tongsui-backups/ 2>/dev/null | head -5 >&2; exit 1; }
gzip -t "$file"
/opt/tongsui/backup.sh # 万一恢复错了份，还能回到现在
systemctl stop tongsui
trap 'systemctl start tongsui' EXIT
{ echo 'SET ROLE tongsui;'; gunzip -c "$file"; } | sudo -u postgres psql -q -d nakama -v ON_ERROR_STOP=1 --single-transaction >/dev/null
echo "已恢复：$file"
