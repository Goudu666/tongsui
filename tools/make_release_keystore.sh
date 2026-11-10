#!/usr/bin/env bash
# 生成《同岁》的正式签名密钥（只需要做一次），并把它交给 GitHub Actions。
#
#   bash tools/make_release_keystore.sh            # 生成到 ~/tongsui-keys/
#   bash tools/make_release_keystore.sh --gh       # 生成后直接用 gh CLI 写入仓库 Secrets
#
# 为什么重要：安卓只允许「同一把钥匙签的包」覆盖安装。钥匙丢了，新版本只能卸载重装，
# 而卸载会清掉手机里的设备 ID ——在同岁里，这等于换了一个人，人生线就找不回来了。
# 所以：生成之后，把 ~/tongsui-keys 整个文件夹备份到网盘/U 盘，永远不要提交到 git。
set -euo pipefail

OUT="${TONGSUI_KEY_DIR:-$HOME/tongsui-keys}"
ALIAS="tongsui"
KS="$OUT/tongsui-release.keystore"
REPO="${TONGSUI_REPO:-Goudu666/tongsui}"
USE_GH=0
[[ "${1:-}" == "--gh" ]] && USE_GH=1

if [[ -f "$KS" ]]; then
  echo "已经有一把钥匙：$KS（不会覆盖）。"
  echo "要重新把它写进 GitHub，删掉这个判断或者手动设置 Secrets，见 docs/DEPLOY.md。"
  exit 1
fi
mkdir -p "$OUT" && chmod 700 "$OUT"
PASS="$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')"  # 32 位十六进制
DNAME="CN=Tongsui,O=Goudu,C=CN"

if command -v keytool >/dev/null 2>&1; then
  keytool -genkeypair -keystore "$KS" -storetype PKCS12 -storepass "$PASS" -keypass "$PASS" \
    -alias "$ALIAS" -keyalg RSA -keysize 4096 -validity 18250 -dname "$DNAME" >/dev/null
elif command -v openssl >/dev/null 2>&1; then
  # Mac 没装 Java 也行：用系统自带的 openssl 生成 PKCS12，apksigner 一样认
  tmp="$(mktemp -d)"
  openssl req -x509 -newkey rsa:4096 -nodes -days 18250 -subj "/CN=Tongsui/O=Goudu/C=CN" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
  openssl pkcs12 -export -name "$ALIAS" -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -out "$KS" -passout "pass:$PASS"
  rm -rf "$tmp"
else
  echo "需要 keytool（装个 JDK）或 openssl 才能生成钥匙。" >&2
  exit 1
fi

base64 <"$KS" | tr -d '\n' >"$OUT/ANDROID_KEYSTORE_BASE64.txt"
printf '%s' "$PASS" >"$OUT/ANDROID_KEYSTORE_PASSWORD.txt"
printf '%s' "$ALIAS" >"$OUT/ANDROID_KEY_ALIAS.txt"
chmod 600 "$OUT"/*

if [[ $USE_GH == 1 ]] && command -v gh >/dev/null 2>&1; then
  gh secret set ANDROID_KEYSTORE_BASE64 -R "$REPO" <"$OUT/ANDROID_KEYSTORE_BASE64.txt"
  gh secret set ANDROID_KEYSTORE_PASSWORD -R "$REPO" <"$OUT/ANDROID_KEYSTORE_PASSWORD.txt"
  gh secret set ANDROID_KEY_ALIAS -R "$REPO" <"$OUT/ANDROID_KEY_ALIAS.txt"
  echo "✓ 已写入 $REPO 的 Actions Secrets。重新跑一次 Actions，出来的就是正式签名的 APK。"
else
  cat <<MSG
✓ 钥匙生成好了：$KS

接下来去 GitHub 仓库 → Settings → Secrets and variables → Actions → New repository secret，
新建 3 个 Secret，值分别复制下面 3 个文件的全部内容：

  ANDROID_KEYSTORE_BASE64   ←  $OUT/ANDROID_KEYSTORE_BASE64.txt
  ANDROID_KEYSTORE_PASSWORD ←  $OUT/ANDROID_KEYSTORE_PASSWORD.txt
  ANDROID_KEY_ALIAS         ←  $OUT/ANDROID_KEY_ALIAS.txt

（Mac 上可以 pbcopy < 文件名 复制到剪贴板。装了 gh CLI 的话，加 --gh 参数自动写入。）
MSG
fi
echo
echo "‼ 请把 $OUT 备份到安全的地方。丢了这把钥匙，以后的新版本就没法覆盖安装了。"
