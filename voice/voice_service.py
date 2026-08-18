from __future__ import annotations

import io
import os
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel, Field
from silero import silero_tts
from transformers import pipeline

HOST = os.getenv("AURORAFOX_VOICE_HOST", "127.0.0.1")
PORT = int(os.getenv("AURORAFOX_VOICE_PORT", "8765"))
TTS_MODEL = os.getenv("AURORAFOX_TTS_MODEL", "v5_5_ru")
TTS_SPEAKER = os.getenv("AURORAFOX_TTS_SPEAKER", "xenia")
SAMPLE_RATE = int(os.getenv("AURORAFOX_TTS_SAMPLE_RATE", "48000"))
STT_MODEL = os.getenv("AURORAFOX_STT_MODEL", "openai/whisper-large-v3-turbo")

app = FastAPI(title="AuroraFox Voice", version="0.2.0")

_tts_model = None
_stt_pipe = None
_device = "cuda" if torch.cuda.is_available() else "cpu"


class TTSRequest(BaseModel):
    text: str = Field(min_length=1, max_length=12000)
    speaker: str = TTS_SPEAKER
    sample_rate: int = SAMPLE_RATE


class STTPathRequest(BaseModel):
    path: str = Field(min_length=1, max_length=4096)


def get_tts_model():
    global _tts_model
    if _tts_model is None:
        model, _ = silero_tts(language="ru", speaker=TTS_MODEL)
        model.to(torch.device(_device))
        _tts_model = model
    return _tts_model


def get_stt_pipe():
    global _stt_pipe
    if _stt_pipe is None:
        dtype = torch.float16 if _device == "cuda" else torch.float32
        _stt_pipe = pipeline(
            "automatic-speech-recognition",
            model=STT_MODEL,
            torch_dtype=dtype,
            device=0 if _device == "cuda" else -1,
        )
    return _stt_pipe


def transcribe_path(path: str) -> str:
    audio_path = Path(path).expanduser().resolve()
    if not audio_path.is_file():
        raise HTTPException(status_code=404, detail="Audio file not found")
    if audio_path.suffix.lower() not in {".wav", ".mp3", ".ogg", ".flac", ".m4a", ".webm"}:
        raise HTTPException(status_code=400, detail="Unsupported audio format")
    recognizer = get_stt_pipe()
    result = recognizer(
        str(audio_path),
        generate_kwargs={"language": "ru", "task": "transcribe"},
    )
    return str(result.get("text", "")).strip()


@app.get("/health")
def health():
    return {
        "ok": True,
        "device": _device,
        "tts_model": TTS_MODEL,
        "tts_speaker": TTS_SPEAKER,
        "stt_model": STT_MODEL,
        "tts_loaded": _tts_model is not None,
        "stt_loaded": _stt_pipe is not None,
    }


@app.post("/tts")
def tts(req: TTSRequest):
    try:
        model = get_tts_model()
        audio = model.apply_tts(
            text=req.text,
            speaker=req.speaker,
            sample_rate=req.sample_rate,
        )
        if isinstance(audio, torch.Tensor):
            audio = audio.detach().cpu().numpy()
        audio = np.asarray(audio, dtype=np.float32)
        buf = io.BytesIO()
        sf.write(buf, audio, req.sample_rate, format="WAV", subtype="PCM_16")
        return Response(content=buf.getvalue(), media_type="audio/wav")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"TTS failed: {exc}") from exc


@app.post("/stt")
async def stt(file: UploadFile = File(...)):
    suffix = Path(file.filename or "speech.wav").suffix or ".wav"
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty audio file")

    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp.write(data)
            temp_path = tmp.name
        text = transcribe_path(temp_path)
        return {"ok": True, "text": text, "language": "ru"}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"STT failed: {exc}") from exc
    finally:
        if temp_path and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except OSError:
                pass


@app.post("/stt_path")
def stt_path(req: STTPathRequest):
    try:
        return {"ok": True, "text": transcribe_path(req.path), "language": "ru"}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"STT failed: {exc}") from exc


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host=HOST, port=PORT)
