from __future__ import annotations

from abc import ABC, abstractmethod
import html
import os
from pathlib import Path
import re
import numpy as np
import torch
from silero import silero_tts


VOICE_ROOT = Path(__file__).resolve().parents[1]
_DLL_DIRECTORY_HANDLES: list[object] = []


def _configure_local_ffmpeg() -> Path | None:
    """Expose AuroraFox's verified shared FFmpeg build to TorchCodec on Windows.

    Python 3.8+ on Windows no longer relies on PATH alone for dependent DLL
    resolution. Keep the os.add_dll_directory handle alive for the process and
    also prepend PATH for ffmpeg.exe / child-process discovery.
    """
    candidates: list[Path] = []
    configured = os.getenv("AURORAFOX_FFMPEG_BIN", "").strip()
    if configured:
        candidates.append(Path(configured).expanduser())
    candidates.append(VOICE_ROOT / "runtime" / "ffmpeg" / "bin")

    for candidate in candidates:
        try:
            resolved = candidate.resolve()
        except OSError:
            resolved = candidate
        if not resolved.is_dir():
            continue
        ffmpeg_exe = resolved / ("ffmpeg.exe" if os.name == "nt" else "ffmpeg")
        if not ffmpeg_exe.is_file():
            continue
        if os.name == "nt" and hasattr(os, "add_dll_directory"):
            try:
                _DLL_DIRECTORY_HANDLES.append(os.add_dll_directory(str(resolved)))
            except OSError:
                continue
        path_value = os.environ.get("PATH", "")
        parts = [part for part in path_value.split(os.pathsep) if part]
        if str(resolved).lower() not in {part.lower() for part in parts}:
            os.environ["PATH"] = str(resolved) + os.pathsep + path_value
        os.environ["AURORAFOX_FFMPEG_BIN"] = str(resolved)
        return resolved
    return None


LOCAL_FFMPEG_BIN = _configure_local_ffmpeg()


class TTSEngine(ABC):
    name = "base"

    @abstractmethod
    def available(self) -> bool: ...

    @abstractmethod
    def synthesize(self, text: str, emotion: str = "neutral", intensity: float = 0.5,
                   speed: float = 1.0) -> tuple[np.ndarray, int]: ...


class SileroEngine(TTSEngine):
    name = "silero"

    # These discrete model-native profiles are intentionally narrow. They were
    # accepted by acoustic A/B on the configured kseniya voice. High/fast pitch
    # presets are deliberately absent because measured candidates regressed MOS.
    _NATIVE_PROSODY = {
        "sleepy": {"min_intensity": 0.45, "rate": "slow", "pitch": "medium", "break_ms": 110},
        "playful": {"min_intensity": 0.55, "rate": None, "pitch": None, "break_ms": 70},
        "serious": {"min_intensity": 0.55, "rate": "slow", "pitch": "medium", "break_ms": 0},
    }

    def __init__(self, config: dict, device: str):
        self.config = config
        self.device = torch.device(device)
        self.model = None

    def available(self) -> bool:
        return True

    def _load(self):
        if self.model is None:
            model, _ = silero_tts(language="ru", speaker=self.config.get("model", "v5_5_ru"))
            model.to(self.device)
            self.model = model
        return self.model

    @staticmethod
    def _insert_first_sentence_break(escaped: str, break_ms: int) -> str:
        if break_ms <= 0:
            return escaped
        match = re.match(r"^(.*?[.!?])\s+(.+)$", escaped)
        if not match:
            return escaped
        return f'{match.group(1)}<break time="{break_ms}ms"/>{match.group(2)}'

    def _native_ssml(self, text: str, emotion: str, intensity: float) -> str | None:
        profile = self._NATIVE_PROSODY.get(str(emotion).strip().lower())
        if profile is None:
            return None
        try:
            power = max(0.0, min(1.0, float(intensity)))
        except (TypeError, ValueError):
            power = 0.0
        if power < float(profile["min_intensity"]):
            return None

        # User/model text is data, never markup authority. Escaping happens
        # before AuroraFox adds its own allowlisted SSML controls.
        body = html.escape(str(text), quote=False)
        body = self._insert_first_sentence_break(body, int(profile["break_ms"]))
        attrs: list[str] = []
        if profile["rate"]:
            attrs.append(f'rate="{profile["rate"]}"')
        if profile["pitch"]:
            attrs.append(f'pitch="{profile["pitch"]}"')
        if attrs:
            body = f'<prosody {" ".join(attrs)}>{body}</prosody>'
        return f"<speak>{body}</speak>"

    def synthesize(self, text: str, emotion: str = "neutral", intensity: float = 0.5,
                   speed: float = 1.0) -> tuple[np.ndarray, int]:
        sr = int(self.config.get("sample_rate", 48000))
        model = self._load()
        speaker = self.config.get("speaker", "xenia")
        ssml = self._native_ssml(text, emotion, intensity)
        if ssml is None:
            audio = model.apply_tts(text=text, speaker=speaker, sample_rate=sr)
        else:
            audio = model.apply_tts(ssml_text=ssml, speaker=speaker, sample_rate=sr)
        if isinstance(audio, torch.Tensor):
            audio = audio.detach().cpu().numpy()
        return np.asarray(audio, dtype=np.float32), sr


class XTTSVoiceEngine(TTSEngine):
    name = "xtts"

    def __init__(self, config: dict, device: str):
        self.config = config
        self.device = device
        self.model = None
        self.import_error = ""
        try:
            from TTS.api import TTS  # coqui-tts keeps the TTS import namespace
            self._tts_cls = TTS
        except Exception as exc:
            self._tts_cls = None
            self.import_error = str(exc)

    def _speaker_path(self) -> Path | None:
        raw = str(self.config.get("speaker_wav", "")).strip()
        if not raw:
            return None
        path = Path(raw).expanduser()
        if not path.is_absolute():
            path = VOICE_ROOT / path
        try:
            return path.resolve()
        except OSError:
            return path

    def available(self) -> bool:
        wav = self._speaker_path()
        ffmpeg_ok = True
        if os.name == "nt":
            ffmpeg_ok = LOCAL_FFMPEG_BIN is not None
        return bool(
            self.config.get("enabled", False)
            and self._tts_cls is not None
            and wav is not None
            and wav.is_file()
            and ffmpeg_ok
        )

    def diagnostics(self) -> dict:
        wav = self._speaker_path()
        return {
            "enabled": bool(self.config.get("enabled", False)),
            "tts_imported": self._tts_cls is not None,
            "import_error": self.import_error,
            "speaker_wav": str(wav) if wav is not None else "",
            "speaker_exists": bool(wav is not None and wav.is_file()),
            "ffmpeg_bin": str(LOCAL_FFMPEG_BIN) if LOCAL_FFMPEG_BIN is not None else "",
            "ffmpeg_ready": bool(LOCAL_FFMPEG_BIN is not None or os.name != "nt"),
        }

    def _load(self):
        if self.model is None:
            if self._tts_cls is None:
                raise RuntimeError("coqui-tts is not installed or failed to import: " + self.import_error)
            if os.name == "nt" and LOCAL_FFMPEG_BIN is None:
                raise RuntimeError("AuroraFox local shared FFmpeg runtime is not prepared")
            self.model = self._tts_cls(
                self.config.get("model", "tts_models/multilingual/multi-dataset/xtts_v2")
            ).to(self.device)
        return self.model

    def synthesize(self, text: str, emotion: str = "neutral", intensity: float = 0.5,
                   speed: float = 1.0) -> tuple[np.ndarray, int]:
        if not self.available():
            raise RuntimeError("XTTS backend is unavailable: " + str(self.diagnostics()))
        speaker = self._speaker_path()
        assert speaker is not None
        wav = self._load().tts(
            text=text,
            speaker_wav=str(speaker),
            language=self.config.get("language", "ru"),
            speed=max(0.5, min(float(speed), 2.0)),
        )
        return np.asarray(wav, dtype=np.float32), 24000


class EngineRouter:
    def __init__(self, config: dict, device: str):
        self.config = config
        self.engines = {
            "silero": SileroEngine(config.get("silero", {}), device),
            "xtts": XTTSVoiceEngine(config.get("xtts", {}), device),
        }

    def choose(self, requested: str = "auto") -> TTSEngine:
        quality = str(self.config.get("quality", "balanced"))
        if requested == "xtts" or (requested == "auto" and quality == "quality"):
            if self.engines["xtts"].available():
                return self.engines["xtts"]
        return self.engines["silero"]

    def synthesize(self, text: str, emotion: str, intensity: float, speed: float, requested: str = "auto"):
        first = self.choose(requested)
        try:
            # XTTS has its own speed control, while Silero uses only the narrow
            # acoustically-approved native SSML profiles above. Shared processor
            # remains responsible for neutral normalization/limiting.
            synthesis_speed = 1.0 if first.name == "xtts" else speed
            audio, sr = first.synthesize(text, emotion, intensity, synthesis_speed)
            return audio, sr, first.name, None
        except Exception as exc:
            if first.name != "silero":
                fallback = self.engines["silero"]
                audio, sr = fallback.synthesize(text, emotion, intensity, speed)
                return audio, sr, fallback.name, str(exc)
            raise

    def diagnostics(self) -> dict:
        xtts = self.engines["xtts"]
        return {
            "silero_available": self.engines["silero"].available(),
            "xtts_available": xtts.available(),
            "xtts": xtts.diagnostics() if isinstance(xtts, XTTSVoiceEngine) else {},
            "prosody_authority": "silero_native_ssml+shared_processor",
            "silero_native_prosody": True,
        }
