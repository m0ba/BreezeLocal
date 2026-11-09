# BreezeLocal · Windows 使用说明

> **重要**：BreezeLocal 是 **macOS 原生 App**（SwiftUI + MLX），Windows 上没有同款界面。
> 这个包里提供的是「环境检查 + 模型下载 + 部署路线」三件套，帮你在 Windows 上把 Breeze TTS 2 跑起来。

## 三条路线，按你的显卡选

| 路线 | 适合 | 显存 / 内存 | 推荐权重 |
| --- | --- | --- | --- |
| **ComfyUI**（推荐给做图的） | 已经在用 ComfyUI，想要节点化配音 | 8–12 GB 显存 | `drbaph/Breeze-TTS-2-comfyui` 的 int8-hybrid |
| **llama.cpp / Breeze-TTS-2.cpp** | 没独显、想轻量跑 | 4 GB 内存起 | `HoppouAI/Breeze-TTS-2.cpp` 的 Q8_0（音质好）或 Q4_K（最省） |
| **官方 PyTorch** | 要改代码、做研究 | 12 GB 显存（eager） | `BreezeBlue/Breeze-TTS-2` |

## 步骤

1. 右键 `check-env.ps1` → 使用 PowerShell 运行，确认 Python / 显卡 / 磁盘空间。
2. 右键 `download-model.ps1` → 使用 PowerShell 运行，按菜单选路线，权重会下到 `.\models`。
3. 按下面「部署」一节接入。

如果 PowerShell 提示禁止运行脚本，先执行一次：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## 部署

### ComfyUI

1. 装 `ComfyUI-Breeze-TTS-2` 节点包（ComfyUI Manager 里搜 Breeze）。
2. 把下载的权重放进 `ComfyUI/models/breeze/`（或节点设置里指向 `.\models\...`）。
3. 参考节点包自带的 workflow，选择 int8-hybrid 权重。

### llama.cpp / Breeze-TTS-2.cpp

1. 拉取 `Breeze-TTS-2.cpp` 项目并按其 README 编译（需要 CMake + MSVC）。
2. 用下载好的 `*q8_0.gguf` 作为模型参数启动。

### 官方 PyTorch

```powershell
git clone https://github.com/breezeblue-ai/breeze-tts.git
cd breeze-tts
python -m pip install -r requirements.txt
python infer.py ..\models\Breeze-TTS-2 --text "你好，这是 Windows 本地的测试。" --output out.wav
```

## 许可

模型权重受 **BreezeBlue Research and Non-Commercial License** 约束，仅限研究与**非商用**。
商用需向 BreezeBlue / RESONIA 取得书面授权。
