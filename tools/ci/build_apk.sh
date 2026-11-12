#!/usr/bin/env bash
# 出一个能直接装的《同岁》APK。在 barichello/godot-ci:4.7.2 容器里跑（CI 和本地 docker 都行）：
#   docker run --rm -v "$PWD":/w -w /w barichello/godot-ci:4.7.2 bash tools/ci/build_apk.sh
#
# 步骤：拉 nakama-godot 插件 + 霞鹜文楷 → 裁字体 → 写入服务器地址 → 版本号 → 导入资源
#       → 无头冒烟测试 → 导出并签名 → 校验签名
#
# 环境变量（都可以不填）：
#   TONGSUI_SERVER            服务器 JSON，如 {"host":"x.sslip.io","port":443,"scheme":"https","server_key":"..."}
#                             不填就连本机 127.0.0.1:7350（玩家仍可在游戏里「服务器设置」改）
#   VERSION_NAME / VERSION_CODE   默认 0.1.0 / 1。安卓要求 VERSION_CODE 只增不减才能覆盖安装
#   ANDROID_KEYSTORE_BASE64 / ANDROID_KEYSTORE_PASSWORD / ANDROID_KEY_ALIAS
#                             正式签名（tools/make_release_keystore.sh 生成）。不填就用仓库里公开的调试签名
#   OUT_DIR                   默认 build/
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"
GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
VERSION_NAME="${VERSION_NAME:-0.1.0}"
VERSION_CODE="${VERSION_CODE:-1}"
OUT_DIR="${OUT_DIR:-$ROOT/build}"
mkdir -p "$OUT_DIR"
step() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }

step "导出模板与编辑器设置"
# GitHub 的 container job 里 HOME=/github/home，镜像把模板和设置放在 /root 下
if [[ "$HOME" != "/root" ]]; then
  mkdir -p ~/.local/share/godot/export_templates ~/.config
  cp -rn /root/.config/godot ~/.config/ 2>/dev/null || true
  cp -rn "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable" ~/.local/share/godot/export_templates/ 2>/dev/null || true
fi
ls ~/.local/share/godot/export_templates/

step "依赖：curl（下载字体）、python3-fonttools（裁字体）"
if ! command -v curl >/dev/null || ! python3 -c 'import fontTools' 2>/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq && apt-get install -y -qq --no-install-recommends curl ca-certificates python3-fonttools >/dev/null
fi

step "nakama-godot 插件 + 寒蝉全圆体、霞鹜文楷"
if [[ ! -d client/addons/com.heroiclabs.nakama || ! -f client/fonts/LXGWWenKai-Regular.ttf || ! -f client/fonts/ChillRoundF.ttf ]]; then
  bash tools/fetch_addons.sh
else
  echo "已存在，跳过下载"
fi
grep -q '^Nakama=' client/project.godot || { echo "project.godot 没注册 Nakama autoload" >&2; exit 1; }
python3 tools/subset_font.py

step "服务器地址"
if [[ -n "${TONGSUI_SERVER:-}" ]]; then
  TONGSUI_SERVER="$TONGSUI_SERVER" python3 - <<'PY'
import json, os, sys
try:
    cfg = json.loads(os.environ["TONGSUI_SERVER"])
except json.JSONDecodeError as e:
    sys.exit(f"TONGSUI_SERVER 不是合法 JSON：{e}")
missing = [k for k in ("host", "server_key") if not cfg.get(k)]
if missing:
    sys.exit(f"TONGSUI_SERVER 缺少字段：{missing}")
cfg.setdefault("scheme", "https")
cfg.setdefault("port", 443 if cfg["scheme"] == "https" else 7350)
out = {k: cfg[k] for k in ("host", "port", "scheme", "server_key")}
open("client/data/server.json", "w").write(json.dumps(out, ensure_ascii=False, indent=2))
print(f"打包进 APK：{out['scheme']}://{out['host']}:{out['port']}")
PY
else
  rm -f client/data/server.json
  echo "没有设置仓库变量 TONGSUI_SERVER：APK 默认连 127.0.0.1:7350，装好后在「联机 → 服务器设置」里填地址"
fi

step "版本 ${VERSION_NAME}（code ${VERSION_CODE}）"
sed -i -E "s|^version/code=.*|version/code=${VERSION_CODE}|; s|^version/name=.*|version/name=\"${VERSION_NAME}\"|" client/export_presets.cfg
sed -i -E "s|^config/version=.*|config/version=\"${VERSION_NAME}\"|" client/project.godot
grep -E '^version/(code|name)=' client/export_presets.cfg

step "导入资源"
timeout 600 godot --headless --editor --quit --path client >"$OUT_DIR/import.log" 2>&1 || true
if grep -E "SCRIPT ERROR|Parse Error|Failed to load script" "$OUT_DIR/import.log"; then
  echo "导入时脚本报错，见上面" >&2
  exit 1
fi

step "无头冒烟测试"
set +e
timeout 120 godot --headless --path client res://tests/smoke.tscn 2>&1 | grep -v -e fontconfig -e "Nakama : DEBUG" | tee "$OUT_DIR/smoke.log"
smoke=${PIPESTATUS[0]}
set -e
if [[ $smoke -ne 0 ]] || grep -qE "SCRIPT ERROR|Parse Error|Failed to load script|Invalid call|Invalid access" "$OUT_DIR/smoke.log"; then
  echo "冒烟测试失败（退出码 $smoke）" >&2
  exit 1
fi

step "导出并签名"
if [[ -n "${ANDROID_KEYSTORE_BASE64:-}" ]]; then
  KS="$(mktemp -d)/release.keystore"
  printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 -d >"$KS"
  export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KS"
  export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${ANDROID_KEY_ALIAS:-tongsui}"
  export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${ANDROID_KEYSTORE_PASSWORD:?缺 ANDROID_KEYSTORE_PASSWORD}"
  SIGNING=release
  APK="$OUT_DIR/tongsui-${VERSION_NAME}.apk"
  godot --headless --path client --export-release "Android" "$APK" 2>&1 | grep -vE "^ADDING:|fontconfig" || true
  rm -f "$KS"
else
  export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$ROOT/tools/ci/debug.keystore"
  export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
  export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
  SIGNING=debug
  APK="$OUT_DIR/tongsui-${VERSION_NAME}-debug.apk"
  godot --headless --path client --export-debug "Android" "$APK" 2>&1 | grep -vE "^ADDING:|fontconfig" || true
fi
[[ -s "$APK" ]] || { echo "没有导出 APK" >&2; exit 1; }
rm -f "$APK.idsig"

step "校验"
BT="$(ls -d /usr/lib/android-sdk/build-tools/* 2>/dev/null | sort -V | tail -1)"
"$BT/apksigner" verify --print-certs "$APK" | tee "$OUT_DIR/signature.txt"
"$BT/aapt" dump badging "$APK" | grep -E "^package:|^application-label:|^sdkVersion|^targetSdkVersion" || true
SIZE="$(du -h "$APK" | cut -f1)"
CERT="$(grep -m1 'SHA-256' "$OUT_DIR/signature.txt" | sed 's/.*: //')"

echo
echo "✓ $APK（$SIZE，$SIGNING 签名）"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "apk=$APK"
    echo "apk_name=$(basename "$APK")"
    echo "signing=$SIGNING"
  } >>"$GITHUB_OUTPUT"
fi
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  SERVER_LINE="$( [[ -f client/data/server.json ]] && python3 -c 'import json;c=json.load(open("client/data/server.json"));print(f"{c["scheme"]}://{c["host"]}:{c["port"]}")' || echo '未内置（默认 127.0.0.1:7350，游戏里可改）')"
  cat >>"$GITHUB_STEP_SUMMARY" <<MD
## 📦 同岁 ${VERSION_NAME}

| | |
| --- | --- |
| 文件 | \`$(basename "$APK")\`（${SIZE}） |
| 版本 | ${VERSION_NAME}（versionCode ${VERSION_CODE}） |
| 签名 | **${SIGNING}** · \`${CERT}\` |
| 服务器 | ${SERVER_LINE} |

在本页底部 **Artifacts** 下载，解压后把 APK 发到手机安装。
$( [[ $SIGNING == debug ]] && echo '> ⚠️ 这是调试签名。正式给 TA 装之前，先按 docs/DEPLOY.md 配好正式签名，否则以后要卸载重装、丢存档。' )
MD
fi
