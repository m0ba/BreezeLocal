# BreezeLocal 可用模型清单

> 数据来源：Hugging Face API（`?blobs=true`，逐文件求和）与 ModelScope API，实测于 2026-11-09。
> 权重许可：**BreezeBlue Research and Non-Commercial License —— 仅限研究与非商用**。代码 Apache-2.0。

## 一、Mac 能用的（MLX 版，mlx-audio 推理）

这是 BreezeLocal 唯一会用的路线：Apple Silicon 原生，走 Metal，无需 CUDA。

| 档位 | 仓库 | 体积 | 峰值内存（估） | 适用机器 | 下载 |
|---|---|---:|---:|---|---|
| **8bit（推荐）** | `mlx-community/Breeze-TTS-2-mlx-8bit` | **4.60 GB** | 约 6–8 GB | 16GB 起步，音质≈bf16 | [HF](https://huggingface.co/mlx-community/Breeze-TTS-2-mlx-8bit) · [魔搭](https://modelscope.cn/models/mlx-community/Breeze-TTS-2-mlx-8bit) · [HF镜像](https://hf-mirror.com/mlx-community/Breeze-TTS-2-mlx-8bit) |
| **4bit（轻量）** | `mlx-community/Breeze-TTS-2-mlx-4bit` | **3.04 GB** | 约 4–5 GB | 8GB 也能跑，速度最快 | [HF](https://huggingface.co/mlx-community/Breeze-TTS-2-mlx-4bit) · [魔搭](https://modelscope.cn/models/mlx-community/Breeze-TTS-2-mlx-4bit) · [HF镜像](https://hf-mirror.com/mlx-community/Breeze-TTS-2-mlx-4bit) |
| **bf16（原精度）** | `mlx-community/Breeze-TTS-2-mlx` | **7.63 GB** | 约 11–12 GB | 32GB 内存才建议 | [HF](https://huggingface.co/mlx-community/Breeze-TTS-2-mlx) · [魔搭](https://modelscope.cn/models/mlx-community/Breeze-TTS-2-mlx) · [HF镜像](https://hf-mirror.com/mlx-community/Breeze-TTS-2-mlx) |

三个仓库内容一致（`model.safetensors` + `audio_tokenizer/` + tokenizer + config），只是量化精度不同。
魔搭上的 mlx 仓库与 HF 同名、同体积（实测 4,602,696,685 / 3,042,733,605 / 7,625,568,686 字节），是官方组织同步，国内可直连。

## 二、Mac 用不上的（列出来避免你下错）

| 仓库 | 体积 | 为什么不能用 |
|---|---:|---|
| `BreezeBlue/Breeze-TTS-2`（官方 PyTorch 原版） | 7.68 GB | 官方要求 Linux + CUDA 显卡，Mac 无对应算子；只作转换来源 |
| `HoppouAI/Breeze-TTS-2.cpp`（GGUF：q4_k 2.54 / q6_k 3.07 / q8_0 3.57 / f16 6.28 GB） | 24.6 GB 全量 | llama.cpp 路线，Mac 端还没有成熟的 Breeze 前端 |
| `cstr/breeze-tts-2-GGUF`（q4_k 2.21 / q8_0 3.43 / f16 5.71 GB） | 11.4 GB | 同上 |
| `smcleod/Breeze-TTS-2-int8` | 5.94 GB | PyTorch INT8，Mac 无 MLX 对应加载器 |
| `mesmertech/Breeze-TTS-2-int4-hqq-g64` | 5.18 GB | 同上 |
| `LunaFox/Breeze-TTS-2-mlx-4bit` | 3.04 GB | 与 mlx-community 4bit 同源的个人复制，无更新保障，不建议 |

## 三、三条下载通道（App 内会全部提供）

**1. 魔搭 ModelScope（国内首选，直连快）**
```bash
modelscope download --model mlx-community/Breeze-TTS-2-mlx-8bit \
  --local_dir ./models/Breeze-TTS-2-mlx-8bit
```

**2. Hugging Face 镜像（国内备用，免登录）**
```bash
HF_ENDPOINT=https://hf-mirror.com hf download mlx-community/Breeze-TTS-2-mlx-8bit \
  --local-dir ./models/Breeze-TTS-2-mlx-8bit
```

**3. Hugging Face 官方（国外首选）**
```bash
hf download mlx-community/Breeze-TTS-2-mlx-8bit \
  --local-dir ./models/Breeze-TTS-2-mlx-8bit
```

App 里的实现：模型卡上三个按钮（魔搭 / HF 镜像 / HF 官方），点了就把对应仓库 ID + 通道传给 sidecar 的 `download` 子命令（内部设 `HF_ENDPOINT` 或改用 `modelscope` 源），显示进度、可取消、可断点续传。

## 四、给 16GB M4 的建议

- **默认 8bit**：4.6GB，音质基本等于 bf16，16GB 内存留足余量。
- 想更快 / 内存吃紧：**4bit**，3.0GB，速度约快 1.5–2 倍，音质有轻微损失（需实测盲听）。
- bf16 在 16GB 机器上会被系统压缩内存，长句容易卡；App 内会对 <24GB 的机器默认隐藏或置灰。

## 五、测试计划（等你选定后执行）

每个档位跑同一组用例，记录 4 个数：

| 指标 | 怎么测 |
|---|---|
| 模型加载耗时 | 冷启动 `load()` 到可用的秒数 |
| 首字延迟 TTFA | 请求到第一块音频的毫秒数 |
| 300 字中文耗时 / RTF | 固定文案，跑 3 次取中位数 |
| 峰值内存 | `mx.metal.get_peak_memory()` |

建议至少测 **8bit** 和 **4bit** 两档，才能决定 App 的默认档位。
