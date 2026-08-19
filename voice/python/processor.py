from __future__ import annotations

import re
import numpy as np

CODE_BLOCK = re.compile(r"```.*?```", re.S)
INLINE_CODE = re.compile(r"`([^`]+)`")
URL = re.compile(r"https?://\S+")
MARKDOWN = re.compile(r"(^|\s)[#>*_~-]+")
EMOJI = re.compile("[\U0001F300-\U0001FAFF\u2600-\u27BF]", re.UNICODE)


def prepare_for_speech(text: str, read_code: bool = False) -> str:
    text = text or ""
    if not read_code:
        text = CODE_BLOCK.sub(" Код я показала в сообщении. ", text)
        text = INLINE_CODE.sub(lambda m: m.group(1) if len(m.group(1)) < 24 else "фрагмент кода", text)
    text = URL.sub("ссылка в сообщении", text)
    text = EMOJI.sub("", text)
    text = MARKDOWN.sub(" ", text)
    text = re.sub(r"\[(.*?)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"[{}\[\]]", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def _split_long_spoken_chunk(text: str, max_chars: int) -> list[str]:
    if len(text) <= max_chars:
        return [text]

    out: list[str] = []
    buf = ""
    for word in text.split():
        candidate = f"{buf} {word}".strip()
        if buf and len(candidate) > max_chars:
            out.append(buf)
            buf = word
        else:
            buf = candidate
    if buf:
        out.append(buf)
    return out


def split_for_streaming(text: str, max_chars: int = 240) -> list[str]:
    text = prepare_for_speech(text)
    if not text:
        return []

    max_chars = max(24, int(max_chars))
    sentences = [part.strip() for part in re.split(r"(?<=[.!?…])\s+", text) if part.strip()]
    out: list[str] = []
    for sentence in sentences:
        out.extend(_split_long_spoken_chunk(sentence, max_chars))
    return out


class AuroraVoiceProcessor:
    def __init__(self, config: dict):
        self.config = config

    def process(self, audio, sample_rate: int, emotion: str = "neutral", intensity: float = 0.5,
                mechanical_amount: float = 0.05, pitch_shift: float = 0.0, speed: float = 1.0):
        x = np.asarray(audio, dtype=np.float32).reshape(-1)
        if x.size == 0:
            return x
        x = self._highpass(x, sample_rate, float(self.config.get("highpass_hz", 58)))
        if self.config.get("compression", True):
            x = self._compress(x)
        mech = float(np.clip(mechanical_amount, 0.0, 0.12))
        if mech > 0:
            x = self._mechanical_layer(x, sample_rate, mech)
        ratio = max(0.85, min(1.18, speed * (1.0 + pitch_shift)))
        if abs(ratio - 1.0) > 0.005:
            idx = np.linspace(0, x.size - 1, max(1, int(x.size / ratio)))
            x = np.interp(idx, np.arange(x.size), x).astype(np.float32)
        if self.config.get("normalize", True):
            peak = float(np.max(np.abs(x))) if x.size else 0.0
            if peak > 1e-6:
                x = x * min(0.96 / peak, 4.0)
        if self.config.get("limiter", True):
            x = np.tanh(x * 1.12) / np.tanh(1.12)
        return np.clip(x, -1.0, 1.0).astype(np.float32)

    @staticmethod
    def _compress(x: np.ndarray) -> np.ndarray:
        threshold = 0.32
        a = np.abs(x)
        gain = np.ones_like(a)
        over = a > threshold
        gain[over] = (threshold + (a[over] - threshold) / 3.2) / np.maximum(a[over], 1e-6)
        return x * gain

    @staticmethod
    def _highpass(x: np.ndarray, sr: int, hz: float) -> np.ndarray:
        if hz <= 0 or x.size < 2:
            return x
        rc = 1.0 / (2.0 * np.pi * hz)
        dt = 1.0 / float(sr)
        alpha = rc / (rc + dt)
        y = np.empty_like(x)
        y[0] = x[0]
        for i in range(1, x.size):
            y[i] = alpha * (y[i - 1] + x[i] - x[i - 1])
        return y

    def _mechanical_layer(self, x: np.ndarray, sr: int, amount: float) -> np.ndarray:
        freq = float(self.config.get("mechanical_frequency_hz", 1830))
        t = np.arange(x.size, dtype=np.float32) / float(sr)
        carrier = 0.5 + 0.5 * np.sin(2.0 * np.pi * freq * t)
        detail = np.concatenate(([0.0], np.diff(x)))
        return x * (1.0 - amount * 0.35) + detail * carrier * amount


def amplitude_envelope(audio, points: int = 80) -> list[float]:
    x = np.abs(np.asarray(audio, dtype=np.float32).reshape(-1))
    if x.size == 0:
        return []
    step = max(1, x.size // points)
    vals = [float(np.sqrt(np.mean(np.square(x[i:i+step])))) for i in range(0, x.size, step)]
    peak = max(vals) if vals else 1.0
    return [min(1.0, v / max(peak, 1e-6)) for v in vals[:points]]
