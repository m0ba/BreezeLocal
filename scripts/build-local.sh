#!/usr/bin/env bash
# 一条命令出 .app 和 .dmg（本地测试用，不做签名/公证）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[[ "$(uname -m)" == "arm64" ]] || { echo "只支持 Apple Silicon" >&2; exit 1; }
command -v swift >/dev/null || { echo "需要 Swift 工具链" >&2; exit 1; }

if [[ ! -f "Resources/AppIcon.icns" ]]; then
  swift scripts/make-icon.swift
fi

APP_VERSION="${BREEZE_APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BREEZE_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"

"$ROOT/scripts/build-sidecar.sh"

swift build -c release --disable-sandbox --arch arm64
"$ROOT/scripts/assemble-app.sh" "$APP_VERSION" "$BUILD_NUMBER"
BREEZE_APP_VERSION="$APP_VERSION" "$ROOT/scripts/create-dmg.sh"

echo "完成：$ROOT/build/BreezeLocal-$APP_VERSION.dmg"
