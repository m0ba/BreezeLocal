#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_VERSION="${1:-0.1.0}"
BUILD_NUMBER="${2:-1}"

BIN_DIR="$(swift build -c release --disable-sandbox --arch arm64 --show-bin-path)"
APP="$ROOT/build/BreezeLocal.app"

# 不直接删旧 .app（大量文件删除可能被安全策略拦），移到 /tmp 备份
if [[ -d "$APP" ]]; then
  mv "$APP" "/tmp/breezelocal-app-old-$(date +%s)"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/BreezeLocal" "$APP/Contents/MacOS/BreezeLocal"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
[[ -f "$ROOT/Resources/AppIcon.icns" ]] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
[[ -f "$ROOT/THIRD_PARTY_LICENSES.md" ]] && cp "$ROOT/THIRD_PARTY_LICENSES.md" "$APP/Contents/Resources/THIRD_PARTY_LICENSES.md"
cp -R "$ROOT/sidecar/dist/breeze-sidecar" "$APP/Contents/Resources/breeze-sidecar"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

chmod +x "$APP/Contents/MacOS/BreezeLocal"
chmod +x "$APP/Contents/Resources/breeze-sidecar/breeze-sidecar"

# 本地测试用 ad-hoc 签名，不是公证
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
xattr -cr "$APP" >/dev/null 2>&1 || true

echo "已组装：$APP"
