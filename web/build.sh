#!/usr/bin/env bash
# 出网页单机版：Godot 网页导出 + 页面里的单机服务器（web/local.js）。打开 index.html 就能从投胎过到结局，对门由电脑陪着。
#   bash web/build.sh [输出目录，默认 build/web]
#   GODOT=/path/to/godot   默认找 PATH 里的 godot（4.7.2，要装好 Web 导出模板）
# 本地试玩：cd build/web && python3 -m http.server 8060，浏览器开 http://localhost:8060
# 不需要跨源隔离头（导出的是不带线程的版本），任何静态托管都能放。
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/build/web}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
godot="${GODOT:-godot}"
cd "$root"

echo "▶ 内容和服务器"
npm run --silent content
npm run --silent server:build >/dev/null

echo "▶ 字体（裁成游戏里用得到的字；网页上没有系统字体可回退，裁掉的字会是方块）"
if [[ ! -f client/fonts/LXGWWenKai-Regular.ttf ]]; then bash tools/fetch_addons.sh; fi
python3 tools/subset_font.py

echo "▶ Godot 导入 + 网页导出"
"$godot" --headless --path client --import >/dev/null 2>&1 || true
rm -f "$out"/index.*
"$godot" --headless --path client --export-release "Web" "$out/index.html" 2>&1 | grep -E "ERROR|SCRIPT ERROR" || true
test -f "$out/index.wasm" || { echo "导出失败：没有 index.wasm（Web 导出模板装了吗？）" >&2; exit 1; }

echo "▶ 单机服务器"
node web/build.mjs "$out"
# 正常托管不分块：parts.js 留空（发到单文件有上限的地方时，web/split.mjs 会改写它）
echo "window.TONGSUI_PARTS = null;" > "$out/parts.js"
du -sh "$out"/* | sort -h | tail -6
echo "✓ $out"
