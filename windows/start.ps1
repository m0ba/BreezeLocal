# BreezeLocal Web for Windows —— 一键拉起官方 Breeze TTS 2 API + 本地控制台
param(
    [switch]$SkipInstall,          # 已经装好依赖，跳过 pip
    [switch]$NoBrowser,
    [int]$Port = 7860,
    [int]$WebPort = 8787,
    [string]$ModelDir = "",
    [switch]$DryRun                 # 只检查环境，不启动
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = Join-Path $root "breeze-tts"
$venvDir = Join-Path $root ".venv"
$py = Join-Path $venvDir "Scripts\python.exe"

function Say($msg, $color = "Cyan") { Write-Host $msg -ForegroundColor $color }

Say "=== BreezeLocal Web (Windows) ==="

# 1. Python
$sysPython = Get-Command python -ErrorAction SilentlyContinue
if (-not $sysPython) {
    Say "没找到 python。请先安装 Python 3.10+：https://www.python.org/downloads/ （勾选 Add to PATH）" "Red"
    exit 1
}
$ver = (& python --version) 2>&1
Say "[1/5] $ver"

# 2. 虚拟环境
if (-not (Test-Path $py)) {
    Say "[2/5] 创建虚拟环境 .venv ..."
    & python -m venv $venvDir
} else {
    Say "[2/5] 已有虚拟环境"
}

# 3. 官方仓库
if (-not (Test-Path (Join-Path $repoDir "requirements.txt"))) {
    Say "[3/5] 克隆官方仓库 breeze-tts ..."
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Say "需要 git，请先安装：https://git-scm.com/download/win" "Red"
        exit 1
    }
    & git clone --depth 1 https://github.com/breezeblue-ai/breeze-tts.git $repoDir
} else {
    Say "[3/5] 官方仓库已存在"
}

# 4. 依赖
if (-not $SkipInstall) {
    Say "[4/5] 安装依赖（首次约 3-6 GB，取决于 CUDA 版本）..."
    & $py -m pip install --upgrade pip
    & $py -m pip install -r (Join-Path $repoDir "requirements.txt")
} else {
    Say "[4/5] 跳过依赖安装（-SkipInstall）"
}

# 5. 模型
if ([string]::IsNullOrWhiteSpace($ModelDir)) {
    $ModelDir = Join-Path (Split-Path -Parent $root) "models\Breeze-TTS-2"
}
if (-not (Test-Path (Join-Path $ModelDir "config.json"))) {
    Say "[5/5] 下载模型到 $ModelDir（约 7.7 GB）..."
    & $py -m pip install -U "huggingface_hub[cli]"
    & $py -m huggingface_hub.commands.huggingface_cli download BreezeBlue/Breeze-TTS-2 --local-dir $ModelDir
} else {
    Say "[5/5] 模型已存在：$ModelDir"
}

if ($DryRun) {
    Say "DryRun 完成，环境看起来没问题。去掉 -DryRun 再运行一次即可启动。" "Green"
    exit 0
}

# 启动 API（新窗口，方便看日志）
Say "启动官方 API（端口 $Port）..."
$apiArgs = "-m breeze_infer.api `"$ModelDir`" --host 127.0.0.1 --port $Port"
Start-Process -FilePath $py -ArgumentList $apiArgs -WorkingDirectory $repoDir -WindowStyle Normal

# 静态页服务
Say "启动控制台（端口 $WebPort）..."
Start-Process -FilePath $py -ArgumentList "-m http.server $WebPort --directory `"$root\web`"" -WindowStyle Hidden

Start-Sleep -Seconds 2
if (-not $NoBrowser) { Start-Process "http://127.0.0.1:$WebPort" }

Say ""
Say "控制台：http://127.0.0.1:$WebPort" "Green"
Say "API：  http://127.0.0.1:$Port  （首次加载模型 10-30 秒）"
Say "关掉 API 窗口即停止服务。"
