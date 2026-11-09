#!/usr/bin/env bash
# 清理 BreezeLocal 的开发产物。默认只删项目内的东西；
# 加 --all 才连 App 的正式数据目录一起删。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DATA="$HOME/Library/Application Support/BreezeLocal"

rm_path() {
  local p="$1"
  if [[ -e "$p" ]]; then
    local size
    size="$(du -sh "$p" 2>/dev/null | awk '{print $1}')"
    printf '  删除 %s (%s)\n' "${p/$HOME/~}" "$size"
    rm -rf "$p"
  fi
}

echo "清理项目内开发产物：$ROOT"
rm_path "$ROOT/.venv"
rm_path "$ROOT/.cache"
rm_path "$ROOT/data"
rm_path "$ROOT/models"
rm_path "$ROOT/build"
rm_path "$ROOT/sidecar/dist"
rm_path "$ROOT/sidecar/build"
rm_path "$ROOT/sidecar/__pycache__"
rm_path "$ROOT/logs"

if [[ "${1:-}" == "--all" ]]; then
  echo "清理 App 数据目录：$APP_DATA"
  rm_path "$APP_DATA"
fi

echo "完成。源码目录保留（可继续打包上传）。"
