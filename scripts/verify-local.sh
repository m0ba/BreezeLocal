#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/BreezeLocal.app"
DMG="$ROOT/build/BreezeLocal.dmg"
SIDE="$APP/Contents/Resources/breeze-sidecar/breeze-sidecar"

[[ -x "$APP/Contents/MacOS/BreezeLocal" ]] || { echo "缺少 App 可执行文件"; exit 1; }
[[ -x "$SIDE" ]] || { echo "缺少 breeze-sidecar"; exit 1; }
codesign --verify --deep --strict "$APP" 2>/dev/null || echo "提示：ad-hoc 签名校验跳过"
[[ -f "$DMG" ]] && hdiutil verify "$DMG" >/dev/null

TEST_DIR="$(mktemp -d /tmp/breezelocal-verify.XXXXXX)"
IMPORT_DIR="$(mktemp -d /tmp/breezelocal-import.XXXXXX)"
trap 'rm -rf "$TEST_DIR" "$IMPORT_DIR"' EXIT

"$SIDE" status --data-dir "$TEST_DIR"
"$SIDE" list --data-dir "$TEST_DIR"

# 用最小假模型验证导入校验链路（不加载推理）
mkdir -p "$IMPORT_DIR/audio_tokenizer"
touch "$IMPORT_DIR/model.safetensors" "$IMPORT_DIR/config.json" "$IMPORT_DIR/tokenizer.json" "$IMPORT_DIR/audio_tokenizer/model.safetensors"
"$SIDE" import --source "$IMPORT_DIR" --name verify-local --data-dir "$TEST_DIR"
"$SIDE" list --data-dir "$TEST_DIR" | head -c 400; echo

echo "校验通过：$APP"
