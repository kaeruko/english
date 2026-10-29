from __future__ import annotations

import hashlib
import json
import os
import re
import tempfile
import threading
import uuid
from pathlib import Path
from typing import Any
from urllib.parse import unquote

from fastapi import BackgroundTasks, FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles


ROOT = Path(__file__).resolve().parent
STATIC_DIR = ROOT / "static"
CACHE_DIR = ROOT / ".cache"
CACHE_DIR.mkdir(exist_ok=True)

MODEL_SIZE = os.environ.get("ENGLISH_REPLAY_MODEL", "base.en")
MAX_UPLOAD_BYTES = 500 * 1024 * 1024

app = FastAPI(title="English Replay Windows Preview")
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

_jobs: dict[str, dict[str, Any]] = {}
_jobs_lock = threading.Lock()
_model: Any | None = None
_model_lock = threading.Lock()


def _update_job(job_id: str, **values: Any) -> None:
    with _jobs_lock:
        if job_id in _jobs:
            _jobs[job_id].update(values)


def _get_job(job_id: str) -> dict[str, Any]:
    with _jobs_lock:
        job = _jobs.get(job_id)
        if job is None:
            raise KeyError(job_id)
        return dict(job)


def sanitize_filename(value: str) -> str:
    decoded = unquote(value or "audio.mp3")
    name = Path(decoded).name
    cleaned = re.sub(r"[^A-Za-z0-9._ -]", "_", name).strip(" .")
    return cleaned[:120] or "audio.mp3"


def _patch_pyav_compatibility(av_module: Any) -> None:
    """Make faster-whisper 1.2.x compatible with PyAV 19 and newer."""
    try:
        major_version = int(str(av_module.__version__).split(".", 1)[0])
    except (AttributeError, TypeError, ValueError):
        return

    current_open = av_module.open
    if major_version < 19 or getattr(current_open, "_english_replay_compat", False):
        return

    def compatible_open(*args: Any, **kwargs: Any) -> Any:
        kwargs.pop("metadata_errors", None)
        return current_open(*args, **kwargs)

    compatible_open._english_replay_compat = True  # type: ignore[attr-defined]
    av_module.open = compatible_open


def _load_model(job_id: str) -> Any:
    global _model
    with _model_lock:
        if _model is not None:
            return _model

        _update_job(
            job_id,
            status="loading_model",
            message=f"英語モデル（{MODEL_SIZE}）を準備しています。初回はダウンロードします…",
        )
        try:
            import av
            from faster_whisper import WhisperModel
        except ImportError as error:
            raise RuntimeError(
                "faster-whisperがインストールされていません。"
                "start_windows_preview.cmdから起動してください。"
            ) from error

        _patch_pyav_compatibility(av)

        cpu_threads = max(1, min(8, (os.cpu_count() or 4) - 1))
        _model = WhisperModel(
            MODEL_SIZE,
            device="cpu",
            compute_type="int8",
            cpu_threads=cpu_threads,
            num_workers=1,
        )
        return _model


def _word_payload(word: Any) -> dict[str, Any]:
    start = max(0.0, float(word.start or 0.0))
    end = max(start, float(word.end or start))
    return {
        "id": str(uuid.uuid4()),
        "text": str(word.word),
        "startTime": start,
        "endTime": end,
    }


def _segment_payload(segment: Any) -> dict[str, Any]:
    words = [_word_payload(word) for word in (segment.words or [])]
    start = max(0.0, float(segment.start or 0.0))
    end = max(start, float(segment.end or start))

    if not words:
        words = [
            {
                "id": str(uuid.uuid4()),
                "text": str(segment.text).strip(),
                "startTime": start,
                "endTime": end,
            }
        ]

    return {
        "id": str(uuid.uuid4()),
        "text": str(segment.text).strip(),
        "startTime": start,
        "endTime": end,
        "words": words,
    }


def _run_transcription(
    job_id: str,
    audio_path: Path,
    cache_path: Path,
    original_name: str,
) -> None:
    try:
        model = _load_model(job_id)
        _update_job(job_id, status="transcribing", message="英語を文字起こししています…", progress=0.01)

        generated_segments, info = model.transcribe(
            str(audio_path),
            language="en",
            beam_size=5,
            word_timestamps=True,
            vad_filter=True,
            condition_on_previous_text=True,
        )

        duration = max(0.0, float(info.duration or 0.0))
        segments: list[dict[str, Any]] = []
        for segment in generated_segments:
            payload = _segment_payload(segment)
            if payload["text"]:
                segments.append(payload)
            if duration > 0:
                progress = min(0.99, payload["endTime"] / duration)
                _update_job(job_id, progress=progress)

        if not segments:
            raise RuntimeError("音声から英語字幕を検出できませんでした。")

        result = {
            "title": Path(original_name).stem,
            "language": getattr(info, "language", "en"),
            "duration": duration,
            "model": MODEL_SIZE,
            "segments": segments,
        }
        cache_path.write_text(
            json.dumps(result, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        _update_job(
            job_id,
            status="done",
            message="文字起こしが完了しました。",
            progress=1.0,
            result=result,
        )
    except Exception as error:  # The UI needs a readable error from native libraries too.
        _update_job(
            job_id,
            status="error",
            message="文字起こしに失敗しました。",
            error=f"{type(error).__name__}: {error}",
        )
    finally:
        audio_path.unlink(missing_ok=True)


@app.get("/")
async def index() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/health")
async def health() -> dict[str, Any]:
    return {"ok": True, "model": MODEL_SIZE, "modelLoaded": _model is not None}


@app.post("/api/jobs")
async def create_job(request: Request, background_tasks: BackgroundTasks) -> dict[str, Any]:
    original_name = sanitize_filename(request.headers.get("x-filename", "audio.mp3"))
    suffix = Path(original_name).suffix or ".mp3"
    digest = hashlib.sha256()
    total_bytes = 0

    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temporary_file:
        temporary_path = Path(temporary_file.name)
        try:
            async for chunk in request.stream():
                total_bytes += len(chunk)
                if total_bytes > MAX_UPLOAD_BYTES:
                    raise HTTPException(status_code=413, detail="音声ファイルは500MBまでです。")
                digest.update(chunk)
                temporary_file.write(chunk)
        except Exception:
            temporary_path.unlink(missing_ok=True)
            raise

    if total_bytes == 0:
        temporary_path.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail="音声ファイルが空です。")

    cache_path = CACHE_DIR / f"{digest.hexdigest()}-{MODEL_SIZE}.json"
    job_id = str(uuid.uuid4())

    if cache_path.exists():
        result = json.loads(cache_path.read_text(encoding="utf-8"))
        temporary_path.unlink(missing_ok=True)
        with _jobs_lock:
            _jobs[job_id] = {
                "id": job_id,
                "status": "done",
                "message": "保存済みの字幕を読み込みました。",
                "progress": 1.0,
                "result": result,
            }
        return {"id": job_id, "cached": True}

    with _jobs_lock:
        _jobs[job_id] = {
            "id": job_id,
            "status": "queued",
            "message": "文字起こしを開始します…",
            "progress": 0.0,
        }

    background_tasks.add_task(
        _run_transcription,
        job_id,
        temporary_path,
        cache_path,
        original_name,
    )
    return {"id": job_id, "cached": False}


@app.get("/api/jobs/{job_id}")
async def get_job(job_id: str) -> dict[str, Any]:
    try:
        return _get_job(job_id)
    except KeyError as error:
        raise HTTPException(status_code=404, detail="処理が見つかりません。") from error
