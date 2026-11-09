#!/usr/bin/env python3
"""BreezeLocal sidecar: model manager + TTS runtime + local MCP server.

This file is intentionally dependency-light at import time so that `list`,
`status` and `remove` stay fast; MLX is only imported when actually generating.

Machine protocol (stdout, one JSON object per line):
    {"type": "status",   "message": "..."}
    {"type": "progress", "bytes": 123, "total": 456}
    {"type": "done",     "model": {...}}
    {"type": "done",     "result": {...}}
    {"type": "error",    "message": "..."}
"""

from __future__ import annotations

import argparse
import json
import os
import queue
import shutil
import statistics
import sys
import threading
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from pydantic import BaseModel

APP_NAME = "BreezeLocal"
DEFAULT_DATA_DIR = Path.home() / "Library" / "Application Support" / APP_NAME
INDEX_NAME = "installed.json"
DEFAULT_MODEL = "mlx-community/Breeze-TTS-2-mlx-8bit"
SAMPLE_RATE = 24_000
MODELSCOPE_FILES = "https://modelscope.cn/api/v1/models/{repo}/repo/files?Revision=master&Recursive=True"
MODELSCOPE_FILE = "https://modelscope.cn/api/v1/models/{repo}/repo?Revision=master&FilePath={path}"
DEFAULT_TEXT = "你好，这里是 BreezeLocal。今天天气不错，我们开始工作吧。"
MCP_PREFIXES = ("mcp-", "design-", "clone-")
MCP_KEEP = int(os.environ.get("BREEZE_MCP_KEEP", "5"))


class SpeechRequest(BaseModel):
    """HTTP 合成入参。定义在模块级，FastAPI 才能正确识别为 body。"""

    text: str
    voice: str | None = None
    instruct: str | None = None
    ref_audio: str | None = None
    ref_text: str | None = None
    cfg_scale: float | None = None
    max_tokens: int = 1500
    temperature: float = 0.9
    seed: int | None = None


# --------------------------------------------------------------------------- #
# 基础工具
# --------------------------------------------------------------------------- #


def emit(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def fail(message: str) -> "SystemExit":
    emit({"type": "error", "message": message})
    return SystemExit(message)


def safe_name(source: str) -> str:
    return (
        source.replace("https://", "")
        .replace("http://", "")
        .replace("huggingface.co/", "")
        .replace("hf.co/", "")
        .replace("modelscope.cn/models/", "")
        .replace("/", "--")
        .replace(":", "--")
        .replace(" ", "-")
        .strip("-")
    )


def ensure_layout(data_dir: Path) -> None:
    for rel in ["models", "outputs", "cache/huggingface", "cache/xdg", "cache/uv", "logs", "tmp"]:
        (data_dir / rel).mkdir(parents=True, exist_ok=True)
    os.environ["HF_HOME"] = str(data_dir / "cache/huggingface")
    os.environ["HF_HUB_CACHE"] = str(data_dir / "cache/huggingface/hub")
    os.environ["XDG_CACHE_HOME"] = str(data_dir / "cache/xdg")
    os.environ["TMPDIR"] = str(data_dir / "tmp")
    os.environ["UV_CACHE_DIR"] = str(data_dir / "cache/uv")
    os.environ["TOKENIZERS_PARALLELISM"] = "false"


def dir_size(path: Path) -> int:
    total = 0
    if not path.exists():
        return 0
    for item in path.rglob("*"):
        if item.is_file():
            try:
                total += item.stat().st_size
            except OSError:
                pass
    return total


def index_path(data_dir: Path) -> Path:
    return data_dir / INDEX_NAME


def load_index(data_dir: Path) -> dict[str, Any]:
    path = index_path(data_dir)
    if not path.exists():
        return {"models": []}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {"models": []}


def save_index(data_dir: Path, data: dict[str, Any]) -> None:
    index_path(data_dir).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def record_for(model_id: str, source: str, path: Path, channel: str) -> dict[str, Any]:
    return {
        "id": model_id,
        "name": model_id.split("/")[-1],
        "path": str(path.resolve()),
        "source": source,
        "channel": channel,
        "sizeBytes": dir_size(path),
        "installedAt": datetime.now(timezone.utc).isoformat(),
    }


def upsert_record(data_dir: Path, record: dict[str, Any]) -> None:
    index = load_index(data_dir)
    models = [m for m in index.get("models", []) if m.get("id") != record["id"]]
    models.append(record)
    index["models"] = models
    save_index(data_dir, index)


def resolve_model(data_dir: Path, model: str) -> Path:
    direct = Path(model).expanduser()
    if direct.exists():
        return direct
    for item in load_index(data_dir).get("models", []):
        if model in {item.get("id"), item.get("name"), safe_name(item.get("source", ""))}:
            path = Path(item["path"])
            if path.exists():
                return path
    candidate = data_dir / "models" / safe_name(model)
    if candidate.exists():
        return candidate
    raise fail(f"找不到模型：{model}")


# --------------------------------------------------------------------------- #
# 下载：三条通道
# --------------------------------------------------------------------------- #


def progress_thread(target: Path, total: int) -> threading.Event:
    stop = threading.Event()

    def worker() -> None:
        while not stop.is_set():
            emit({"type": "progress", "bytes": dir_size(target), "total": total})
            time.sleep(0.8)

    threading.Thread(target=worker, daemon=True).start()
    return stop


def hf_total(repo_id: str) -> int:
    try:
        from huggingface_hub import HfApi

        info = HfApi().model_info(repo_id=repo_id, files_metadata=True)
        return sum(int(item.size or 0) for item in info.siblings)
    except Exception:
        return 0


def download_hf(repo_id: str, target: Path, mirror: bool) -> None:
    if mirror:
        os.environ["HF_ENDPOINT"] = "https://hf-mirror.com"
    from huggingface_hub import snapshot_download

    total = hf_total(repo_id)
    stop = progress_thread(target, total)
    try:
        snapshot_download(repo_id=repo_id, local_dir=str(target))
    finally:
        stop.set()


def modelscope_file_list(repo_id: str) -> list[dict[str, Any]]:
    url = MODELSCOPE_FILES.format(repo=repo_id)
    with urllib.request.urlopen(url, timeout=30) as resp:
        payload = json.load(resp)
    files = (payload.get("Data") or {}).get("Files") or []
    return [f for f in files if (f.get("Size") or 0) > 0]


def download_modelscope(repo_id: str, target: Path) -> None:
    files = modelscope_file_list(repo_id)
    if not files:
        raise fail(f"魔搭仓库为空或不存在：{repo_id}")
    total = sum(int(f.get("Size") or 0) for f in files)
    stop = progress_thread(target, total)
    try:
        for item in files:
            rel = item.get("Path") or ""
            if not rel:
                continue
            dest = target / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            size = int(item.get("Size") or 0)
            if dest.exists() and dest.stat().st_size == size:
                continue
            url = MODELSCOPE_FILE.format(repo=repo_id, path=urllib.parse.quote(rel))
            tmp = dest.with_suffix(dest.suffix + ".part")
            req = urllib.request.Request(url)
            if tmp.exists() and 0 < tmp.stat().st_size < size:
                req.add_header("Range", f"bytes={tmp.stat().st_size}-")
            try:
                with urllib.request.urlopen(req, timeout=60) as resp, open(tmp, "ab") as fh:
                    while True:
                        chunk = resp.read(1024 * 256)
                        if not chunk:
                            break
                        fh.write(chunk)
            except urllib.error.HTTPError as exc:  # noqa: PERF203
                raise fail(f"下载失败 {rel}：HTTP {exc.code}") from exc
            if tmp.stat().st_size != size:
                raise fail(f"文件大小不符 {rel}：{tmp.stat().st_size} != {size}")
            tmp.replace(dest)
    finally:
        stop.set()


def validate_model_dir(path: Path) -> list[str]:
    issues: list[str] = []
    if not any(path.glob("*.safetensors")):
        issues.append("缺少 *.safetensors 权重")
    if not (path / "config.json").exists():
        issues.append("缺少 config.json")
    if not (path / "tokenizer.json").exists() and not (path / "tokenizer_config.json").exists():
        issues.append("缺少 tokenizer")
    if not (path / "audio_tokenizer" / "model.safetensors").exists():
        issues.append("缺少 audio_tokenizer/model.safetensors")
    return issues


def download_model(source: str, data_dir: Path, channel: str) -> None:
    ensure_layout(data_dir)
    target = data_dir / "models" / safe_name(source)
    target.mkdir(parents=True, exist_ok=True)
    if (target / "config.json").exists() and not validate_model_dir(target):
        record = record_for(source, source, target, channel)
        upsert_record(data_dir, record)
        emit({"type": "done", "model": record})
        return

    emit({"type": "status", "message": f"下载 {source}（{channel}）"})
    if channel == "modelscope":
        download_modelscope(source, target)
    else:
        download_hf(source, target, mirror=(channel == "mirror"))

    issues = validate_model_dir(target)
    if issues:
        raise fail("下载完成但校验失败：" + "；".join(issues))
    record = record_for(source, source, target, channel)
    upsert_record(data_dir, record)
    emit({"type": "done", "model": record})


# --------------------------------------------------------------------------- #
# 模型管理
# --------------------------------------------------------------------------- #


def list_models(data_dir: Path) -> None:
    ensure_layout(data_dir)
    index = load_index(data_dir)
    valid = []
    for item in index.get("models", []):
        raw = Path(item["path"]).expanduser()
        path = raw if raw.is_absolute() else (Path.cwd() / raw)
        if path.exists():
            item["path"] = str(path.resolve())
            item["sizeBytes"] = dir_size(path)
            valid.append(item)
    if valid != index.get("models"):
        index["models"] = valid
        save_index(data_dir, index)
    print(json.dumps({"models": valid}, ensure_ascii=False), flush=True)


def remove_model(model: str, data_dir: Path) -> None:
    ensure_layout(data_dir)
    index = load_index(data_dir)
    match = next(
        (m for m in index.get("models", []) if model in {m.get("id"), m.get("name")}), None
    )
    if match:
        shutil.rmtree(Path(match["path"]), ignore_errors=True)
        index["models"] = [m for m in index.get("models", []) if m.get("id") != match["id"]]
        save_index(data_dir, index)
    else:
        candidate = data_dir / "models" / safe_name(model)
        if not candidate.exists():
            raise fail(f"找不到模型：{model}")
        shutil.rmtree(candidate)
    emit({"type": "done", "model": model})


def clone_or_copy(source: Path, target: Path) -> None:
    if target.exists():
        shutil.rmtree(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    if sys.platform == "darwin":
        import subprocess

        if subprocess.run(["/usr/bin/ditto", "--clone", str(source), str(target)]).returncode == 0:
            return
    shutil.copytree(source, target)


def import_model(source: str, data_dir: Path, name: str | None) -> None:
    ensure_layout(data_dir)
    source_path = Path(source).expanduser().resolve()
    if not source_path.is_dir():
        raise fail(f"目录不存在：{source_path}")
    issues = validate_model_dir(source_path)
    if issues:
        raise fail("模型校验失败：" + "；".join(issues))
    model_name = (name or source_path.name).strip() or source_path.name
    target = data_dir / "models" / safe_name(f"local/{model_name}")
    emit({"type": "status", "message": f"导入 {source_path.name}"})
    clone_or_copy(source_path, target)
    record = record_for(f"local/{model_name}", f"local:{source_path}", target, "local")
    upsert_record(data_dir, record)
    emit({"type": "done", "model": record})


def clean_cache(data_dir: Path) -> None:
    ensure_layout(data_dir)
    freed = 0
    for rel in ["cache/huggingface", "cache/xdg", "cache/uv", "tmp"]:
        target = data_dir / rel
        freed += dir_size(target)
        shutil.rmtree(target, ignore_errors=True)
    ensure_layout(data_dir)
    emit({"type": "done", "message": "缓存已清理", "bytesFreed": freed})


def status(data_dir: Path) -> None:
    ensure_layout(data_dir)
    print(
        json.dumps(
            {
                "dataDir": str(data_dir),
                "models": len(load_index(data_dir).get("models", [])),
                "python": sys.version.split()[0],
            },
            ensure_ascii=False,
        ),
        flush=True,
    )


# --------------------------------------------------------------------------- #
# 推理
# --------------------------------------------------------------------------- #

_MODEL_CACHE: dict[str, Any] = {}
_MODEL_LOCK = threading.RLock()


class InferenceWorker:
    """单线程推理队列。

    MLX 的 GPU stream 是线程绑定的：模型在哪个线程加载，就必须在同一个线程里
    推理，否则会抛 `There is no Stream(gpu, 0) in current thread`。
    FastAPI 的同步端点跑在线程池里，所以所有推理都集中投递到这个专属线程。
    """

    def __init__(self) -> None:
        self._queue: "queue.Queue[tuple[Any, dict[str, Any]]]" = queue.Queue()
        self._thread = threading.Thread(target=self._loop, name="breeze-infer", daemon=True)
        self._thread.start()

    def _loop(self) -> None:
        while True:
            fn, box = self._queue.get()
            try:
                box["result"] = fn()
            except BaseException as exc:  # noqa: BLE001
                box["error"] = exc
            finally:
                box["event"].set()

    def run(self, fn, timeout: float | None = None):
        box: dict[str, Any] = {"event": threading.Event()}
        self._queue.put((fn, box))
        if not box["event"].wait(timeout):
            raise TimeoutError("推理超时")
        if "error" in box:
            raise box["error"]
        return box.get("result")


def load_model(model_path: Path, lazy: bool = False):
    key = str(model_path)
    with _MODEL_LOCK:
        if key not in _MODEL_CACHE:
            from mlx_audio.tts import load as mlx_load

            _MODEL_CACHE[key] = mlx_load(str(model_path), lazy=lazy)
        return _MODEL_CACHE[key]


def peak_memory_gb() -> float:
    try:
        import mlx.core as mx

        if hasattr(mx, "get_peak_memory"):
            return round(mx.get_peak_memory() / 1e9, 2)
        return round(mx.metal.get_peak_memory() / 1e9, 2)
    except Exception:
        return 0.0


def synthesize(
    model,
    text: str,
    voice: str | None = None,
    instruct: str | None = None,
    ref_audio: str | None = None,
    ref_text: str | None = None,
    cfg_scale: float | None = None,
    max_tokens: int = 1500,
    temperature: float = 0.9,
    seed: int | None = None,
    stream: bool = True,
) -> dict[str, Any]:
    import numpy as np

    started = time.perf_counter()
    first_chunk_at: float | None = None
    pieces = []
    for chunk in model.generate(
        text=text,
        voice=voice,
        instruct=instruct,
        ref_audio=ref_audio,
        ref_text=ref_text,
        cfg_scale=cfg_scale,
        max_tokens=max_tokens,
        temperature=temperature,
        seed=seed,
        stream=stream,
        streaming_interval=1.0,
    ):
        if first_chunk_at is None:
            first_chunk_at = time.perf_counter() - started
        pieces.append(np.array(chunk.audio))
    if not pieces:
        raise fail("模型没有输出音频")
    audio = np.concatenate(pieces) if len(pieces) > 1 else pieces[0]
    elapsed = time.perf_counter() - started
    duration = len(audio) / SAMPLE_RATE
    return {
        "audio": audio,
        "duration": round(duration, 3),
        "elapsed": round(elapsed, 3),
        "ttfa": round(first_chunk_at or elapsed, 3),
        "rtf": round(elapsed / max(duration, 1e-6), 3),
    }


def write_wav(path: Path, audio) -> None:
    import soundfile as sf

    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(path), audio, SAMPLE_RATE, subtype="PCM_16")


def speak(args: argparse.Namespace, data_dir: Path) -> None:
    ensure_layout(data_dir)
    model_path = resolve_model(data_dir, args.model)
    t0 = time.perf_counter()
    emit({"type": "status", "message": "加载模型…"})
    model = load_model(model_path)
    load_seconds = round(time.perf_counter() - t0, 3)
    emit({"type": "status", "message": f"模型就绪（{load_seconds}s），开始合成"})

    result = synthesize(
        model,
        text=args.text,
        voice=args.voice,
        instruct=args.instruct,
        ref_audio=args.ref_audio,
        ref_text=args.ref_text,
        cfg_scale=args.cfg_scale,
        max_tokens=args.max_tokens,
        temperature=args.temperature,
        seed=args.seed,
    )
    out = Path(args.out).expanduser() if args.out else data_dir / "outputs" / f"breeze-{int(time.time())}.wav"
    write_wav(out, result.pop("audio"))
    result.update(
        {
            "path": str(out),
            "loadSeconds": load_seconds,
            "peakMemoryGB": peak_memory_gb(),
            "chars": len(args.text),
        }
    )
    emit({"type": "done", "result": result})


def check(args: argparse.Namespace, data_dir: Path) -> None:
    ensure_layout(data_dir)
    model_path = resolve_model(data_dir, args.model)
    emit({"type": "status", "message": "加载模型…"})
    t0 = time.perf_counter()
    model = load_model(model_path)
    load_seconds = round(time.perf_counter() - t0, 3)

    cases = [
        ("中文短句", "你好，这是本地语音合成的测试。", None),
        ("中文情感", "[笑] 今天真是太开心了，我们出去走走吧。", "轻快、明亮，带一点笑意"),
        ("英文", "Local speech synthesis keeps every word on this Mac.", None),
    ]
    samples = []
    for name, text, instruct in cases:
        emit({"type": "status", "message": f"测速 {name}"})
        r = synthesize(model, text=text, instruct=instruct, cfg_scale=4 if instruct else None)
        samples.append({"name": name, "chars": len(text), "ttfa": r["ttfa"], "elapsed": r["elapsed"], "rtf": r["rtf"]})

    values = sorted(s["elapsed"] for s in samples)
    emit(
        {
            "type": "done",
            "result": {
                "ok": True,
                "model": args.model,
                "loadSeconds": load_seconds,
                "peakMemoryGB": peak_memory_gb(),
                "p50": round(statistics.median(values), 3),
                "min": round(values[0], 3),
                "max": round(values[-1], 3),
                "samples": samples,
            },
        }
    )


# --------------------------------------------------------------------------- #
# 常驻服务：HTTP + MCP
# --------------------------------------------------------------------------- #


def serve_model(args: argparse.Namespace, data_dir: Path) -> None:
    ensure_layout(data_dir)
    model_path = resolve_model(data_dir, args.model)

    from fastapi import FastAPI, HTTPException
    from fastapi.responses import JSONResponse, Response
    from fastmcp import FastMCP
    from pydantic import BaseModel

    state: dict[str, Any] = {"model": None, "loadSeconds": None}
    worker = InferenceWorker()

    def _ensure_model():
        with _MODEL_LOCK:
            if state["model"] is None:
                started = time.perf_counter()
                state["model"] = load_model(model_path)
                state["loadSeconds"] = round(time.perf_counter() - started, 3)
            return state["model"]

    def run_infer(fn):
        """在专属推理线程里执行 fn(model)，保证 MLX stream 线程一致。"""
        return worker.run(lambda: fn(_ensure_model()))

    if not args.no_preload:
        emit({"type": "status", "message": "预热模型…"})
        worker.run(_ensure_model)
        emit({"type": "status", "message": "模型已加载"})

    mcp = FastMCP("BreezeLocal")

    @mcp.tool
    def breeze_speak(text: str, voice: str | None = None, instruct: str | None = None, cfg_scale: float | None = None) -> dict[str, Any]:
        """Synthesize speech on this Mac and return the absolute path of the WAV file."""
        try:
            result = run_infer(
                lambda model: synthesize(model, text=text, voice=voice, instruct=instruct, cfg_scale=cfg_scale)
            )
        except BaseException as exc:  # noqa: BLE001
            return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}
        out = data_dir / "outputs" / f"mcp-{int(time.time()*1000)}.wav"
        write_wav(out, result.pop("audio"))
        prune_mcp_outputs(data_dir / "outputs")
        return {"ok": True, "path": str(out), **result}

    @mcp.tool
    def breeze_design(text: str, description: str, cfg_scale: float = 4.0) -> dict[str, Any]:
        """Create a voice from a natural-language description (no reference audio)."""
        result = run_infer(
            lambda model: synthesize(model, text=text, instruct=description, cfg_scale=cfg_scale)
        )
        out = data_dir / "outputs" / f"design-{int(time.time()*1000)}.wav"
        write_wav(out, result.pop("audio"))
        prune_mcp_outputs(data_dir / "outputs")
        return {"ok": True, "path": str(out), **result}

    @mcp.tool
    def breeze_clone(text: str, ref_audio: str, ref_text: str, instruct: str | None = None, cfg_scale: float | None = None) -> dict[str, Any]:
        """Clone a speaker from a local reference WAV and its exact transcript."""
        result = run_infer(
            lambda model: synthesize(
                model,
                text=text,
                ref_audio=ref_audio,
                ref_text=ref_text,
                instruct=instruct,
                cfg_scale=cfg_scale if cfg_scale is not None else 4.0,
            )
        )
        out = data_dir / "outputs" / f"clone-{int(time.time()*1000)}.wav"
        write_wav(out, result.pop("audio"))
        prune_mcp_outputs(data_dir / "outputs")
        return {"ok": True, "path": str(out), **result}

    @mcp.tool
    def breeze_status() -> dict[str, Any]:
        """Report the loaded model, sample rate and peak memory of this local TTS service."""
        return {
            "ok": True,
            "model": args.model,
            "modelPath": str(model_path),
            "loaded": state["model"] is not None,
            "loadSeconds": state["loadSeconds"],
            "sampleRate": SAMPLE_RATE,
            "voices": [f"S{i}" for i in range(10)],
            "peakMemoryGB": peak_memory_gb(),
        }

    mcp_app = mcp.http_app(path="/mcp")
    api = FastAPI(title="BreezeLocal", lifespan=mcp_app.lifespan)

    @api.get("/health")
    def health() -> dict[str, Any]:
        return {
            "ok": True,
            "model": args.model,
            "loaded": state["model"] is not None,
            "loadSeconds": state["loadSeconds"],
            "sampleRate": SAMPLE_RATE,
        }

    @api.post("/v1/audio/speech")
    def speech(req: SpeechRequest) -> Response:
        if not req.text.strip():
            raise HTTPException(status_code=400, detail="text 不能为空")
        result = run_infer(
            lambda model: synthesize(
                model,
                text=req.text,
                voice=req.voice,
                instruct=req.instruct,
                ref_audio=req.ref_audio,
                ref_text=req.ref_text,
                cfg_scale=req.cfg_scale,
                max_tokens=req.max_tokens,
                temperature=req.temperature,
                seed=req.seed,
            )
        )
        audio = result.pop("audio")
        buf = _wav_bytes(audio)
        return Response(
            content=buf,
            media_type="audio/wav",
            headers={
                "X-Audio-Duration": str(result["duration"]),
                "X-Audio-RTF": str(result["rtf"]),
                "X-Audio-TTFA": str(result["ttfa"]),
            },
        )

    @api.get("/v1/models")
    def models() -> JSONResponse:
        return JSONResponse({"object": "list", "data": [{"id": args.model, "object": "model"}]})

    api.mount("/", mcp_app)

    emit({"type": "status", "message": f"服务已启动 http://127.0.0.1:{args.port}"})
    import uvicorn

    uvicorn.run(api, host=args.host, port=args.port, log_level="warning")


def prune_mcp_outputs(outputs_dir: Path, keep: int = MCP_KEEP) -> None:
    """MCP 生成的临时音频只保留最近 keep 条，避免语音机器人把磁盘写满。"""
    if keep <= 0:
        return
    try:
        files = [
            p for p in outputs_dir.iterdir()
            if p.suffix.lower() == ".wav" and p.name.startswith(MCP_PREFIXES)
        ]
    except FileNotFoundError:
        return
    files.sort(key=lambda p: p.stat().st_mtime)
    for old in files[:-keep]:
        try:
            old.unlink()
        except OSError:
            pass


def _wav_bytes(audio) -> bytes:
    import io

    import soundfile as sf

    buf = io.BytesIO()
    sf.write(buf, audio, SAMPLE_RATE, format="WAV", subtype="PCM_16")
    return buf.getvalue()


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="breeze-sidecar")
    sub = p.add_subparsers(dest="command", required=True)

    for name in ["list", "status", "clean-cache"]:
        cmd = sub.add_parser(name)
        cmd.add_argument("--data-dir", default=str(DEFAULT_DATA_DIR))

    download = sub.add_parser("download")
    download.add_argument("--model", required=True)
    download.add_argument("--channel", choices=["hf", "mirror", "modelscope"], default="hf")
    download.add_argument("--data-dir", default=str(DEFAULT_DATA_DIR))

    remove = sub.add_parser("remove")
    remove.add_argument("--model", required=True)
    remove.add_argument("--data-dir", default=str(DEFAULT_DATA_DIR))

    import_cmd = sub.add_parser("import")
    import_cmd.add_argument("--source", required=True)
    import_cmd.add_argument("--name", default=None)
    import_cmd.add_argument("--data-dir", default=str(DEFAULT_DATA_DIR))

    check = sub.add_parser("check")
    check.add_argument("--model", required=True)
    check.add_argument("--data-dir", default=str(DEFAULT_DATA_DIR))

    speak = sub.add_parser("speak")
    speak.add_argument("--model", required=True)
    speak.add_argument("--text", default=DEFAULT_TEXT)
    speak.add_argument("--voice", default=None)
    speak.add_argument("--instruct", default=None)
    speak.add_argument("--ref-audio", default=None)
    speak.add_argument("--ref-text", default=None)
    speak.add_argument("--cfg-scale", type=float, default=None)
    speak.add_argument("--max-tokens", type=int, default=1500)
    speak.add_argument("--temperature", type=float, default=0.9)
    speak.add_argument("--seed", type=int, default=None)
    speak.add_argument("--out", default=None)
    speak.add_argument("--data-dir", default=str(DEFAULT_DATA_DIR))

    serve = sub.add_parser("serve")
    serve.add_argument("--model", required=True)
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8743)
    serve.add_argument("--no-preload", action="store_true")
    serve.add_argument("--data-dir", default=str(DEFAULT_DATA_DIR))
    return p


def main() -> int:
    args = parser().parse_args()
    data_dir = Path(args.data_dir).expanduser().resolve()
    try:
        if args.command == "list":
            list_models(data_dir)
        elif args.command == "status":
            status(data_dir)
        elif args.command == "download":
            download_model(args.model, data_dir, args.channel)
        elif args.command == "remove":
            remove_model(args.model, data_dir)
        elif args.command == "import":
            import_model(args.source, data_dir, args.name)
        elif args.command == "check":
            check(args, data_dir)
        elif args.command == "speak":
            speak(args, data_dir)
        elif args.command == "clean-cache":
            clean_cache(data_dir)
        elif args.command == "serve":
            serve_model(args, data_dir)
    except SystemExit as exc:
        if str(exc):
            emit({"type": "error", "message": str(exc)})
        return 1
    except Exception as exc:  # noqa: BLE001
        emit({"type": "error", "message": f"{type(exc).__name__}: {exc}"})
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
