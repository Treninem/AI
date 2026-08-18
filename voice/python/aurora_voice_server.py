from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import os
import queue
import threading
import time
from difflib import SequenceMatcher
from pathlib import Path

import numpy as np
import sounddevice as sd
import soundfile as sf
import torch
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import Response
from pydantic import BaseModel, Field
from silero_vad import VADIterator, load_silero_vad
from transformers import pipeline
from vosk import KaldiRecognizer, Model

from emotion_parser import detect_emotion
from personality import AuroraPersonality
from processor import AuroraVoiceProcessor, amplitude_envelope, prepare_for_speech
from tts_engine import EngineRouter

ROOT = Path(__file__).resolve().parents[1]
CONFIG_DIR = ROOT / "config"
USER_DIR = Path(os.getenv("AURORAFOX_USER_DIR", str(ROOT))).resolve()
CACHE_DIR = USER_DIR / "voice_cache"
LOG_DIR = USER_DIR / "logs"
CACHE_DIR.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)

CONFIG = json.loads((CONFIG_DIR / "voice_config.json").read_text(encoding="utf-8"))
EMOTIONS = json.loads((CONFIG_DIR / "emotions.json").read_text(encoding="utf-8"))
PERSONALITY = AuroraPersonality(CONFIG_DIR / "personality.json")

logging.basicConfig(
    filename=LOG_DIR / "aurora_voice.log",
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    encoding="utf-8",
)
log = logging.getLogger("aurora_voice")

HOST = os.getenv("AURORAFOX_VOICE_HOST", "127.0.0.1")
PORT = int(os.getenv("AURORAFOX_VOICE_PORT", "8765"))
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

app = FastAPI(title="AuroraFox Voice", version="1.1.0")
processor = AuroraVoiceProcessor(CONFIG.get("processor", {}))
router = EngineRouter(CONFIG, DEVICE)
_stt_pipe = None


class SayRequest(BaseModel):
    text: str = Field(min_length=1, max_length=16000)
    emotion: str = "auto"
    intensity: float = Field(default=0.5, ge=0.0, le=1.0)
    speed: float | None = None
    pitch: float | None = None
    mechanical_amount: float | None = None
    backend: str = "auto"
    read_code: bool = False


class PathRequest(BaseModel):
    path: str = Field(min_length=1, max_length=4096)


class ModeRequest(BaseModel):
    mode: str
    device: int | None = None
    sensitivity: float = Field(default=0.5, ge=0.0, le=1.0)
    noise_suppression: bool = True


class TTSStateRequest(BaseModel):
    playing: bool
    text: str = ""


class EventHub:
    def __init__(self):
        self.clients: set[WebSocket] = set()
        self.loop: asyncio.AbstractEventLoop | None = None

    async def add(self, ws: WebSocket):
        await ws.accept()
        self.clients.add(ws)
        self.loop = asyncio.get_running_loop()

    def emit(self, event: str, **data):
        payload = {"event": event, "time": time.time(), **data}
        if not self.loop or not self.clients:
            return
        asyncio.run_coroutine_threadsafe(self._broadcast(payload), self.loop)

    async def _broadcast(self, payload: dict):
        dead = []
        for ws in list(self.clients):
            try:
                await ws.send_json(payload)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.clients.discard(ws)


hub = EventHub()


def get_stt():
    global _stt_pipe
    if _stt_pipe is None:
        model = CONFIG.get("stt", {}).get("model", "openai/whisper-large-v3-turbo")
        dtype = torch.float16 if DEVICE == "cuda" else torch.float32
        log.info("loading STT model=%s device=%s", model, DEVICE)
        _stt_pipe = pipeline(
            "automatic-speech-recognition",
            model=model,
            torch_dtype=dtype,
            device=0 if DEVICE == "cuda" else -1,
        )
    return _stt_pipe


def transcribe_array(audio: np.ndarray, sr: int = 16000) -> str:
    result = get_stt()(
        {"array": audio.astype(np.float32), "sampling_rate": sr},
        generate_kwargs={"language": "ru", "task": "transcribe"},
    )
    return str(result.get("text", "")).strip()


def transcribe_path(path: str) -> str:
    p = Path(path).expanduser().resolve()
    if not p.is_file():
        raise HTTPException(404, "Audio file not found")
    audio, sr = sf.read(p, dtype="float32", always_2d=False)
    if np.ndim(audio) > 1:
        audio = np.mean(audio, axis=1)
    if sr != 16000:
        idx = np.linspace(0, len(audio) - 1, max(1, int(len(audio) * 16000 / sr)))
        audio = np.interp(idx, np.arange(len(audio)), audio).astype(np.float32)
    return transcribe_array(audio, 16000)


def cache_key(req: SayRequest, clean: str, engine: str) -> str:
    payload = json.dumps(
        {
            "text": clean,
            "engine": engine,
            "emotion": req.emotion,
            "intensity": req.intensity,
            "speed": req.speed,
            "pitch": req.pitch,
            "mechanical": req.mechanical_amount,
            "processor": CONFIG.get("processor", {}),
        },
        ensure_ascii=False,
        sort_keys=True,
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def trim_cache():
    limit = int(CONFIG.get("cache_limit_mb", 512)) * 1024 * 1024
    files = sorted(CACHE_DIR.glob("*.wav"), key=lambda p: p.stat().st_mtime)
    total = sum(p.stat().st_size for p in files)
    while files and total > limit:
        p = files.pop(0)
        total -= p.stat().st_size
        p.unlink(missing_ok=True)
        p.with_suffix(".json").unlink(missing_ok=True)


def synthesize(req: SayRequest) -> dict:
    clean = prepare_for_speech(req.text, req.read_code)
    if not clean:
        raise HTTPException(400, "Nothing suitable for speech")
    emo = detect_emotion(req.text) if req.emotion == "auto" else {"emotion": req.emotion, "intensity": req.intensity}
    emotion = emo["emotion"] if emo["emotion"] in EMOTIONS else "neutral"
    intensity = float(req.intensity if req.emotion != "auto" else emo["intensity"])
    profile = EMOTIONS.get(emotion, EMOTIONS["neutral"])
    base_speed = float(CONFIG.get("speed", 1.04))
    speed = float(req.speed if req.speed is not None else base_speed * profile.get("speed", 1.0))
    pitch = float(
        req.pitch
        if req.pitch is not None
        else float(CONFIG.get("pitch", 1.02)) * profile.get("pitch", 1.0) - 1.0
    )
    mech = float(
        req.mechanical_amount
        if req.mechanical_amount is not None
        else profile.get("mechanical", CONFIG.get("mechanical_amount", 0.035))
    )
    selected = router.choose(req.backend).name
    key = cache_key(req, clean, selected)
    wav_path = CACHE_DIR / f"{key}.wav"
    meta_path = CACHE_DIR / f"{key}.json"
    if wav_path.is_file() and meta_path.is_file():
        os.utime(wav_path, None)
        return json.loads(meta_path.read_text(encoding="utf-8")) | {"cached": True}
    try:
        audio, sr, engine, fallback = router.synthesize(clean, emotion, intensity, speed, req.backend)
        audio = processor.process(audio, sr, emotion, intensity, mech, pitch, speed)
        sf.write(wav_path, audio, sr, subtype="PCM_16")
        meta = {
            "ok": True,
            "path": str(wav_path),
            "emotion": emotion,
            "intensity": intensity,
            "engine": engine,
            "fallback_error": fallback,
            "sample_rate": sr,
            "duration": float(len(audio) / sr),
            "amplitude": amplitude_envelope(audio),
            "cached": False,
            "spoken_text": clean,
        }
        meta_path.write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
        trim_cache()
        if fallback:
            log.warning("TTS fallback: %s", fallback)
        return meta
    except Exception as exc:
        log.exception("TTS generation failed")
        raise HTTPException(500, f"TTS failed: {exc}") from exc


def _normalized_words(text: str) -> str:
    return " ".join("".join(ch.lower() if ch.isalnum() else " " for ch in (text or "")).split())


def _echo_similarity(recognized: str, spoken: str) -> float:
    a = _normalized_words(recognized)
    b = _normalized_words(spoken)
    if not a or not b:
        return 0.0
    if a in b or b in a:
        return min(1.0, min(len(a), len(b)) / max(4.0, float(max(len(a), len(b)))) + 0.35)
    return SequenceMatcher(None, a, b).ratio()


class MicMonitor:
    def __init__(self):
        self.mode = "off"
        self.device = None
        self.sensitivity = 0.5
        self.noise_suppression = True
        self.q: queue.Queue[np.ndarray] = queue.Queue(maxsize=128)
        self.stream = None
        self.thread = None
        self.stop_event = threading.Event()
        self.tts_playing = False
        self.last_tts_text = ""
        self.ignore_wake_until = 0.0
        self.conversation_until = 0.0
        self.noise_floor = 0.006
        self.vad_model = None
        self.vad = None
        self.vosk_model = None

    def start(self, mode: str, device=None, sensitivity: float = 0.5, noise_suppression: bool = True):
        self.stop()
        self.mode = mode
        self.device = device
        self.sensitivity = float(np.clip(sensitivity, 0.0, 1.0))
        self.noise_suppression = bool(noise_suppression)
        if mode in {"off", "push_to_talk"}:
            return
        try:
            base_threshold = float(CONFIG["vad"]["threshold"])
            threshold = float(np.clip(base_threshold + (0.5 - self.sensitivity) * 0.22, 0.35, 0.78))
            self.vad_model = load_silero_vad(onnx=True)
            self.vad = VADIterator(
                self.vad_model,
                threshold=threshold,
                sampling_rate=16000,
                min_silence_duration_ms=int(CONFIG["vad"]["min_silence_ms"]),
            )
            vosk_path = (ROOT.parent / CONFIG["wake"]["vosk_model"]).resolve()
            if vosk_path.is_dir():
                self.vosk_model = Model(str(vosk_path))
            self.stop_event.clear()
            self.stream = sd.InputStream(
                samplerate=16000,
                channels=1,
                dtype="float32",
                blocksize=512,
                device=device,
                callback=self._callback,
            )
            self.stream.start()
            self.thread = threading.Thread(target=self._worker, daemon=True, name="AuroraVoiceMic")
            self.thread.start()
            log.info("microphone monitor started mode=%s device=%s threshold=%.3f", mode, device, threshold)
        except Exception:
            log.exception("microphone monitor failed")
            hub.emit("microphone_error", message="Не удалось запустить микрофон")

    def stop(self):
        self.stop_event.set()
        if self.stream:
            try:
                self.stream.stop()
                self.stream.close()
            except Exception:
                pass
        self.stream = None
        self.thread = None
        while not self.q.empty():
            try:
                self.q.get_nowait()
            except queue.Empty:
                break

    def set_tts_state(self, playing: bool, text: str = ""):
        self.tts_playing = bool(playing)
        if text:
            self.last_tts_text = text
        if not playing:
            # Prevent the end of AuroraFox's own acoustic output from being treated as wake audio.
            self.ignore_wake_until = time.time() + 1.15

    def _callback(self, indata, frames, timing, status):
        if status:
            log.debug("audio status %s", status)
        try:
            self.q.put_nowait(np.asarray(indata[:, 0], dtype=np.float32).copy())
        except queue.Full:
            pass

    def _soft_noise_gate(self, chunk: np.ndarray) -> np.ndarray:
        if not self.noise_suppression:
            return chunk
        gate = max(0.0025, self.noise_floor * 1.35)
        magnitude = np.abs(chunk)
        gain = np.clip((magnitude - gate * 0.35) / max(gate * 1.7, 1e-5), 0.18, 1.0)
        return (chunk * gain).astype(np.float32)

    def _wake_text(self, audio: np.ndarray) -> str:
        if self.vosk_model is None:
            return ""
        grammar = json.dumps(["лиса", "фокс", "fox", "эй лиса", "эй фокс", "[unk]"], ensure_ascii=False)
        rec = KaldiRecognizer(self.vosk_model, 16000, grammar)
        pcm = np.clip(audio * 32767.0, -32768, 32767).astype(np.int16).tobytes()
        rec.AcceptWaveform(pcm)
        data = json.loads(rec.FinalResult())
        return str(data.get("text", "")).lower().strip()

    def _worker(self):
        chunks: list[np.ndarray] = []
        started = False
        started_during_tts = False
        start_time = 0.0
        max_rms = 0.0
        while not self.stop_event.is_set():
            try:
                raw = self.q.get(timeout=0.2)
            except queue.Empty:
                continue
            raw_rms = float(np.sqrt(np.mean(np.square(raw))))
            if not started and not self.tts_playing:
                self.noise_floor = self.noise_floor * 0.995 + min(raw_rms, 0.03) * 0.005
            chunk = self._soft_noise_gate(raw)
            event = self.vad(torch.from_numpy(chunk), return_seconds=False) if self.vad else None
            if event and "start" in event:
                started = True
                started_during_tts = self.tts_playing
                start_time = time.time()
                max_rms = raw_rms
                chunks = [chunk]
                hub.emit("user_speech_started", rms=raw_rms)
            elif started:
                chunks.append(chunk)
                max_rms = max(max_rms, raw_rms)

            if not (event and "end" in event and started):
                continue

            audio = np.concatenate(chunks) if chunks else np.zeros(0, dtype=np.float32)
            duration_ms = float(len(audio) / 16.0)
            started = False
            chunks = []
            hub.emit("user_speech_finished", duration=float(len(audio) / 16000))
            if len(audio) < int(16000 * 0.20):
                continue

            now = time.time()
            # Any segment that began while AuroraFox was speaking is never allowed into wake-word logic.
            # It can become a barge-in only after STT proves it differs from AuroraFox's own sentence.
            if started_during_tts:
                limit = max(
                    float(CONFIG["vad"]["barge_in_rms"]),
                    self.noise_floor * float(CONFIG["vad"]["noise_multiplier"]),
                )
                if duration_ms >= float(CONFIG["vad"]["barge_in_min_ms"]) and max_rms >= limit:
                    try:
                        text = transcribe_array(audio)
                        similarity = _echo_similarity(text, self.last_tts_text)
                        if text and similarity < 0.62:
                            self.conversation_until = now + float(CONFIG["wake"]["conversation_window_sec"])
                            hub.emit("barge_in", rms=max_rms, echo_similarity=similarity)
                            hub.emit("transcript", text=text)
                        else:
                            log.info("suppressed probable self-echo similarity=%.3f", similarity)
                    except Exception:
                        log.exception("barge-in STT failed")
                started_during_tts = False
                continue

            if self.mode == "wake_word" and now > self.conversation_until:
                if now <= self.ignore_wake_until:
                    continue
                wake = self._wake_text(audio)
                words = CONFIG["wake"]["words"]
                if any(w in wake.split() for w in words) or "эй фокс" in wake or "эй лиса" in wake:
                    self.conversation_until = now + float(CONFIG["wake"]["conversation_window_sec"])
                    hub.emit("wake_detected", text=wake)
                continue

            if self.mode == "continuous" or now <= self.conversation_until:
                try:
                    text = transcribe_array(audio)
                    if text:
                        # Final echo guard also protects the conversational window after a spoken wake response.
                        similarity = _echo_similarity(text, self.last_tts_text) if now <= self.ignore_wake_until else 0.0
                        if similarity >= 0.68:
                            log.info("suppressed conversational self-echo similarity=%.3f", similarity)
                            continue
                        self.conversation_until = time.time() + float(CONFIG["wake"]["conversation_window_sec"])
                        hub.emit("transcript", text=text)
                except Exception as exc:
                    log.exception("continuous STT failed")
                    hub.emit("stt_error", message=str(exc))


mic = MicMonitor()


@app.on_event("startup")
async def startup():
    log.info("backend start device=%s", DEVICE)


@app.on_event("shutdown")
async def shutdown_event():
    mic.stop()
    log.info("backend stop")


@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await hub.add(ws)
    await ws.send_json({"event": "backend_ready", "device": DEVICE})
    try:
        while True:
            data = await ws.receive_json()
            cmd = data.get("command")
            if cmd == "set_mode":
                mic.start(
                    str(data.get("mode", "off")),
                    data.get("device"),
                    float(data.get("sensitivity", 0.5)),
                    bool(data.get("noise_suppression", True)),
                )
            elif cmd == "tts_state":
                mic.set_tts_state(bool(data.get("playing", False)), str(data.get("text", "")))
            elif cmd == "ping":
                await ws.send_json({"event": "pong", "time": time.time()})
    except WebSocketDisconnect:
        hub.clients.discard(ws)


@app.get("/health")
def health():
    return {
        "ok": True,
        "device": DEVICE,
        "backend": "AuroraVoice",
        "mode": mic.mode,
        "tts": {name: eng.available() for name, eng in router.engines.items()},
        "vad": mic.vad_model is not None,
        "wake_model": mic.vosk_model is not None,
        "stt_loaded": _stt_pipe is not None,
    }


@app.get("/devices")
def devices():
    result = []
    for i, d in enumerate(sd.query_devices()):
        if int(d.get("max_input_channels", 0)) > 0:
            result.append({"id": i, "name": str(d.get("name", i)), "channels": int(d.get("max_input_channels", 0))})
    return {"ok": True, "devices": result}


@app.post("/mode")
def set_mode(req: ModeRequest):
    mic.start(req.mode, req.device, req.sensitivity, req.noise_suppression)
    return {"ok": True, "mode": mic.mode}


@app.post("/tts_state")
def tts_state(req: TTSStateRequest):
    mic.set_tts_state(req.playing, req.text)
    return {"ok": True}


@app.post("/say")
def say(req: SayRequest):
    return synthesize(req)


@app.post("/tts")
def legacy_tts(req: SayRequest):
    meta = synthesize(req)
    return Response(content=Path(meta["path"]).read_bytes(), media_type="audio/wav")


@app.post("/stt_path")
def stt_path(req: PathRequest):
    try:
        return {"ok": True, "text": transcribe_path(req.path), "language": "ru"}
    finally:
        p = Path(req.path)
        if "aurorafox_voice_input" in p.name:
            try:
                p.unlink(missing_ok=True)
            except Exception:
                pass


@app.get("/emotion")
def emotion(text: str):
    return {"ok": True, **detect_emotion(text)}


@app.get("/phrase/{category}")
def phrase(category: str):
    return {"ok": True, "text": PERSONALITY.choose(category)}


@app.post("/cache/clear")
def clear_cache():
    for p in CACHE_DIR.glob("*"):
        if p.is_file():
            p.unlink(missing_ok=True)
    return {"ok": True}


@app.post("/shutdown")
def shutdown():
    def die():
        time.sleep(0.15)
        os._exit(0)
    threading.Thread(target=die, daemon=True).start()
    return {"ok": True}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=HOST, port=PORT, log_level="warning")
