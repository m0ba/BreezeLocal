# BreezeLocal Web · Windows

BreezeLocal 的原生界面是 macOS 专属（SwiftUI + MLX）。这个包给 Windows 提供的是 **Web 控制台 + 官方推理后端**：浏览器里操作，声音在你自己机器上生成。

> 需要 **NVIDIA 显卡**（官方 eager 推理约 7.7 GB 显存）。没有独显请走文末的 llama.cpp 路线。

## 快速开始

1. 装 [Python 3.10+](https://www.python.org/downloads/)（安装时勾选 **Add to PATH**）和 [Git](https://git-scm.com/download/win)
2. 右键 `start.ps1` → **使用 PowerShell 运行**
3. 首次会自动：建 `.venv` → 克隆官方仓库 → 装依赖 → 下载 7.7 GB 权重 → 启动 API 和网页
4. 浏览器打开 `http://127.0.0.1:8787`，点「检查后端」，然后生成

> 如果提示脚本被禁止：
> ```powershell
> Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
> ```

## 参数

```powershell
.\start.ps1 -DryRun            # 只检查环境，不启动
.\start.ps1 -SkipInstall       # 依赖已装好，跳过 pip
.\start.ps1 -Port 7860 -WebPort 8787
.\start.ps1 -ModelDir D:\models\Breeze-TTS-2
.\start.ps1 -NoBrowser
```

## 它做了什么

```
start.ps1
├─ .venv\                        Python 虚拟环境（不动系统 Python）
├─ breeze-tts\                   官方仓库（python -m breeze_infer.api）
├─ ..\models\Breeze-TTS-2\       官方权重（约 7.7 GB）
└─ web\index.html                控制台（纯静态，浏览器直接开）
```

控制台调用官方接口 `POST /v1/audio/speech`（multipart：`text` / `instruction` / `cfg_scale`），返回 24 kHz 单声道 PCM，页面里会包成 WAV 播放。

## 没有 NVIDIA 显卡？

用 GGUF + llama.cpp：

```powershell
# 需要先在 ComfyUI 或 llama.cpp 里加载 Breeze-TTS-2.cpp 的 gguf
hf download HoppouAI/Breeze-TTS-2.cpp --include "*q8_0.gguf" --local-dir .\models\gguf
```

或者在 ComfyUI 里装 `ComfyUI-Breeze-TTS-2` 节点，权重用 `drbaph/Breeze-TTS-2-comfyui` 的 int8-hybrid。

## 常见问题

- **生成很慢**：官方 RTF 在消费级显卡上通常 1–3，长文请分段。
- **CUDA 版本不对**：按官方仓库 `requirements.txt` 装；显存不足时先关掉其他占用显卡的程序。
- **端口被占用**：`.\start.ps1 -Port 7861 -WebPort 8788`，并改 `web/index.html` 里 `const API = ...`。
- **模型下载失败**：设 `$env:HF_ENDPOINT="https://hf-mirror.com"` 再运行。

## 许可

模型权重受 **BreezeBlue Research and Non-Commercial License** 约束，仅限研究与**非商用**。商用需向 BreezeBlue / RESONIA 取得书面授权。
