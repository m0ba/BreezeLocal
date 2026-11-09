#!/usr/bin/env python3
"""从 CHANGELOG.md 抽出指定版本的小节，拼成 Release 说明。"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHANGELOG = ROOT / "CHANGELOG.md"


def section(version: str) -> str:
    text = CHANGELOG.read_text(encoding="utf-8")
    pattern = re.compile(rf"^## \[{re.escape(version)}\][^\n]*\n(.*?)(?=^## \[|\Z)", re.M | re.S)
    match = pattern.search(text)
    if not match:
        return "_本次没有单独条目，详见提交记录。_\n"
    body = match.group(1).strip()
    # 变更条目里的 ### 降一级，避免和发布说明的二级标题打架
    body = "\n".join(("####" + line[3:]) if line.startswith("### ") else line for line in body.splitlines())
    return body + "\n"


def main() -> int:
    version = sys.argv[1] if len(sys.argv) > 1 else "0.0.0"
    body = f"""## BreezeLocal v{version}

在 Apple Silicon Mac 上本地跑 Breeze TTS 2：模型下载、推理、MCP 服务全部不出本机。

### 本次更新
{section(version)}
### 下载说明

| 文件 | 平台 | 说明 |
| --- | --- | --- |
| `BreezeLocal-{version}.dmg` | macOS 14+ / Apple Silicon | 拖进「应用程序」即可；未签名，首次打开若被拦，执行 `xattr -cr /Applications/BreezeLocal.app` |
| `BreezeLocal-Windows-Setup-{version}.zip` | Windows 10/11 | **Web 控制台** + 官方 API 一键启动脚本（需要 NVIDIA 显卡）；不是原生 App 的安装包 |

模型不随包分发，首次打开后在「添加模型」里选 8bit（约 4.6 GB）下载，国内建议走魔搭通道。

### 许可

- App 代码：MIT
- Breeze TTS 2 权重：BreezeBlue Research and Non-Commercial License，**仅限研究与非商用**

完整变更见 [CHANGELOG.md](CHANGELOG.md)。
"""
    print(body)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
