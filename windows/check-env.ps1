# 检查 Windows 是否具备跑 Breeze TTS 2 的条件
$ErrorActionPreference = "Continue"

Write-Host "=== BreezeLocal Windows 环境检查 ===" -ForegroundColor Cyan

# Python
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) {
    $ver = (& python --version) 2>&1
    Write-Host "[OK] Python: $ver"
} else {
    Write-Host "[缺少] 没找到 python，去 https://www.python.org/downloads/ 装 3.10+（勾选 Add to PATH）" -ForegroundColor Yellow
}

# hf 命令
$hf = Get-Command hf -ErrorAction SilentlyContinue
if ($hf) {
    Write-Host "[OK] huggingface-cli(hf) 已安装"
} else {
    Write-Host "[提示] 没有 hf 命令，下载脚本会自动执行: pip install -U huggingface_hub" -ForegroundColor Yellow
}

# 显卡
$nvidia = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($nvidia) {
    Write-Host "[OK] 检测到 NVIDIA 显卡："
    & nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
} else {
    Write-Host "[提示] 没有 nvidia-smi：无独显也能跑 GGUF（llama.cpp 路线）" -ForegroundColor Yellow
}

# 磁盘
$drive = Get-PSDrive -Name C
$freeGB = [math]::Round($drive.Free / 1GB, 1)
Write-Host "C 盘剩余：$freeGB GB（建议至少 15 GB）"

Write-Host ""
Write-Host "下一步：右键 download-model.ps1 → 使用 PowerShell 运行" -ForegroundColor Cyan
Read-Host "按回车结束"
