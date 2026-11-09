# 第三方许可

BreezeLocal 的 App 代码采用 MIT License。

## 模型

**Breeze TTS 2**（`BreezeBlue/Breeze-TTS-2` 及 `mlx-community/Breeze-TTS-2-mlx*` 转换版）

- 推理代码：Apache-2.0
- **模型权重、衍生模型、自托管输出：BreezeBlue Research and Non-Commercial License，仅限研究与非商用。**
- 商用需向 RESONIA, INC.（BreezeBlue）取得书面授权，或使用其托管 API。
- 本项目不内置权重，模型由用户自行下载并保存在本机。

## 运行时依赖

| 组件 | 版本 | 许可 |
|---|---|---|
| mlx-audio | 0.6.4 | MIT |
| mlx | 0.32.4 | MIT |
| transformers | 5.22.2 | Apache-2.0 |
| fastmcp | 4.1.6 | Apache-2.0 |
| fastapi | 0.162.2 | MIT |
| uvicorn | 0.54.0 | BSD-3-Clause |
| soundfile | 0.14.0 | BSD-3-Clause |
| Python | 3.12.14 | PSF-2.0 |

## 参考

工程结构参考 [Laya Local](https://github.com/m0ba/laya-local-app)（MIT）：SwiftUI 外壳 + PyInstaller sidecar + 本地模型管理 + MCP 的模式。
