# 下载 Breeze TTS 2 权重（Windows）
param(
    [switch]$Mirror  # 国内网络加这个参数，走 hf-mirror.com
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$modelDir = Join-Path $root "models"
New-Item -ItemType Directory -Force -Path $modelDir | Out-Null

if ($Mirror) {
    $env:HF_ENDPOINT = "https://hf-mirror.com"
    Write-Host "使用镜像：$env:HF_ENDPOINT" -ForegroundColor Yellow
}

if (-not (Get-Command hf -ErrorAction SilentlyContinue)) {
    Write-Host "安装 huggingface_hub..." -ForegroundColor Cyan
    python -m pip install -U "huggingface_hub[cli]"
}

function Invoke-Download($repo, $include, $target) {
    $dest = Join-Path $modelDir $target
    Write-Host "→ $repo => $dest" -ForegroundColor Cyan
    if ($include) {
        hf download $repo --include $include --local-dir $dest
    } else {
        hf download $repo --local-dir $dest
    }
}

Write-Host "=== Breeze TTS 2 权重下载 ===" -ForegroundColor Cyan
Write-Host "1) ComfyUI（推荐 int8-hybrid，约 5-7 GB）"
Write-Host "2) llama.cpp / Breeze-TTS-2.cpp（Q8_0，约 3.6 GB）"
Write-Host "3) llama.cpp 低配（Q4_K，约 2.5 GB）"
Write-Host "4) 官方 PyTorch（约 7.7 GB，需要 NVIDIA 显卡）"
$choice = Read-Host "选择 1-4"

switch ($choice) {
    "1" { Invoke-Download "drbaph/Breeze-TTS-2-comfyui" $null "comfyui" }
    "2" { Invoke-Download "HoppouAI/Breeze-TTS-2.cpp" "*q8_0.gguf" "gguf-q8" }
    "3" { Invoke-Download "HoppouAI/Breeze-TTS-2.cpp" "*q4_k.gguf" "gguf-q4" }
    "4" { Invoke-Download "BreezeBlue/Breeze-TTS-2" $null "breeze-tts-2" }
    default { Write-Host "没有这个选项，退出。" -ForegroundColor Red; exit 1 }
}

Write-Host ""
Write-Host "完成。权重在：$modelDir" -ForegroundColor Green
Write-Host "接下来按 README.md 的对应路线部署。"
Read-Host "按回车结束"
