# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_all

datas = []
binaries = []
hiddenimports = []

for package in [
    "mlx",
    "mlx_audio",
    "mlx_lm",
    "transformers",
    "tokenizers",
    "sentencepiece",
    "soundfile",
    "numpy",
    "scipy",
    "fastmcp",
    "mcp",
    "uvicorn",
    "starlette",
    "sse_starlette",
    "anyio",
    "httpx",
    "pydantic",
    "huggingface_hub",
]:
    try:
        package_datas, package_binaries, package_hidden = collect_all(package)
        datas += package_datas
        binaries += package_binaries
        hiddenimports += package_hidden
    except Exception:
        pass


def _is_runtime_file(entry):
    """丢掉文档/示例/测试文件，只保留运行时真正需要的东西。

    这些文件在打包时既没用，又容易触发沙箱的文件读取策略。
    """
    src = entry[0] if isinstance(entry, (tuple, list)) else entry
    low = str(src).lower()
    if low.endswith((".md", ".markdown", ".rst", ".txt")) and "licenses" not in low:
        return False
    return not ("/contrib/" in low or "/tests/" in low or "/test/" in low)


datas = [item for item in datas if _is_runtime_file(item)]
binaries = [item for item in binaries if _is_runtime_file(item)]
hiddenimports = [
    m for m in hiddenimports
    if ".tests" not in m and ".test_" not in m and not m.endswith(".test")
]

a = Analysis(
    ["breeze_sidecar.py"],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        "torch", "torchaudio", "tensorflow", "jax",
        "pytest", "_pytest", "matplotlib", "IPython", "notebook",
        "tkinter", "PyQt5", "PySide6",
    ],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="breeze-sidecar",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch="arm64",
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="breeze-sidecar",
)
