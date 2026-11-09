#!/usr/bin/env bash
# 用项目内的 .venv 把 sidecar 打成独立可执行目录（不写系统目录）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v uv >/dev/null || { echo "需要 uv（已随 WorkBuddy 环境提供）" >&2; exit 1; }
[[ "$(uname -m)" == "arm64" ]] || { echo "只支持 Apple Silicon" >&2; exit 1; }

export UV_CACHE_DIR="$ROOT/.cache/uv"
export PYINSTALLER_CONFIG_DIR="$ROOT/.cache/pyinstaller"
# 清掉外部注入的 sitecustomize（会拦截 PyInstaller 的文件拷贝）
unset PYTHONPATH
if [[ ! -x ".venv/bin/python" ]]; then
  uv venv --python 3.12 .venv
fi
uv pip install --python .venv/bin/python -r sidecar/requirements.txt pyinstaller

(
  cd sidecar
  "$ROOT/.venv/bin/pyinstaller" --clean --noconfirm breeze_sidecar.spec
)

echo "sidecar 产物：$ROOT/sidecar/dist/breeze-sidecar"
du -sh "$ROOT/sidecar/dist/breeze-sidecar"
