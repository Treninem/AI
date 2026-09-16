from __future__ import annotations

import math
import re
import numpy as np

try:
    import torch
    from torchaudio import functional as audio_functional
except Exception:  # lightweight CI and degraded local runtime keep a NumPy fallback
    torch = None
    audio_functional = None

CODE_BLOCK = re.compile(r"```.*?```", re.S)
INLINE_CODE = re.compile(r"`([^`]+)`")
MARKDOWN_LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")
URL = re.compile(r"https?://[^\s)]+")
WINDOWS_PATH = re.compile(r"(?i)\b[a-z]:\\(?:[^\\\s]+\\)*[^\\\s]+")
UNIX_PATH = re.compile(r"(?<!\w)/(?:[^/\s]+/)+[^/\s]+")
LINE_MARKUP = re.compile(r"(?m)^[ \t]{0,3}(?:#{1,6}\s+|>\s*|[-+*]\s+)")
INLINE_MARKUP = re.compile(r"[*_~]{1,3}")
EMOJI = re.compile("[\U0001F300-\U0001FAFF\u2600-\u27BF]", re.UNICODE)


def prepare_for_speech(text: str, read_code: bool = False) -> str:
    text = (text or "").replace("\r\n", "\n").replace("\r", "\n")
    if not read_code:
        text = CODE_BLOCK.sub(" Код я показала в сообщении. ", text)
        text = INLINE_CODE.sub(lambda m: m.group(1) if len(m.group(1)) < 24 else "фрагмент кода", text)

    # Keep the human-readable Markdown label; never make the voice spell a URL.
    text = MARKDOWN_LINK.sub(lambda m: m.group(1), text)
    text = URL.sub("ссылка в сообщении", text)
    text = WINDOWS_PATH.sub("путь к файлу", text)
    text = UNIX_PATH.sub("путь к файлу", text)
    text = EMOJI.sub("", text)

    # Remove formatting without eating a real minus sign such as "-5".
    text = LINE_MARKUP.sub("", text)
    text = INLINE_MARKUP.sub("", text)
    text = re.sub(r"[{}\[\]]", " ", text)
    text = text.replace("|", ", ")

    # Give local TTS punctuation it can turn into natural short/long pauses.
    text = re.sub(r"\n{2,}", ". ", text)
    text = re.sub(r"\n", ", ", text)
    text = re.sub(r"\s*([,;:!?…])\s*", r"\1 ", text)
    text = re.sub(r"\s*\.\s*", ". ", text)
    text = re.sub(r"\.\s*,", ".", text)
    text = re.sub(r",\s*\.", ".", text)
    text = re.sub(r"\s+", " ", text).strip(" ,")
    return text


def _split_long_spoken_chunk(text: str, max_chars: int) -> list[str]:
    text = text.strip()
    if len(text) <= max_chars:
        return [text] if text else []

    out: list[str] = []
    remaining = text
    preferred_floor = max(24, int(max_chars * 0.45))
    while len(remaining) > max_chars:
        window = remaining[: max_chars + 1]
        preferred = max(
            window.rfind(", "),
            window.rfind("; "),
            window.rfind(": "),
            window.rfind(" — "),
            window.rfind(" – "),
        )
        if preferred >= preferred_floor:
            cut = min(max_chars, preferred + 1)
        else:
            cut = window.rfind(" ")
            if cut < 1:
                cut = max_chars
        part = remaining[:cut].strip()
        if part:
            out.append(part)
        remaining = remaining[cut:].strip()
    if remaining:
        out.append(remaining)
    return out


def split_for_streaming(text: str, max_chars: int = 220) -> list[str]:
    text = prepare_for_speech(text)
    if not text:
        return []

    max_chars = max(48, int(max_chars))
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

        pitch_factor = float(np.clip(
            1.0 + float(pitch_shift),
            float(self.config.get("pitch_min", 0.90)),
            float(self.config.get("pitch_max", 1.12)),
        ))
        tempo = float(np.clip(
            float(speed),
            float(self.config.get("speed_min", 0.82)),
            float(self.config.get("speed_max", 1.18)),
        ))
        x = self._apply_prosody(x, sample_rate, pitch_factor, tempo)

        mech = float(np.clip(mechanical_amount, 0.0, float(self.config.get("mechanical_max", 0.08))))
        if mech > 0:
            x = self._mechanical_layer(x, sample_rate, mech)

        if self.config.get("normalize", True):
            x = self._normalize_loudness(x)

        if self.config.get("limiter", True):
            ceiling = float(self.config.get("peak_ceiling", 0.96))
            peak = float(np.max(np.abs(x))) if x.size else 0.0
            if peak > ceiling > 0:
                x = x * (ceiling / peak)

        x = self._fade_edges(x, sample_rate, float(self.config.get("fade_ms", 6.0)))
        return np.clip(x, -1.0, 1.0).astype(np.float32)

    def _apply_prosody(self, x: np.ndarray, sr: int, pitch_factor: float, tempo: float) -> np.ndarray:
        if bool(self.config.get("prosody_dsp", True)) and torch is not None and audio_functional is not None:
            try:
                y = x
                if abs(pitch_factor - 1.0) > 0.003:
                    y = self._pitch_shift(y, sr, pitch_factor)
                if abs(tempo - 1.0) > 0.003:
                    y = self._time_stretch(y, sr, tempo)
                return y
            except Exception:
                # Voice must remain usable even if an accelerated DSP op is unavailable
                # on a particular Torch/Torchaudio build.
                pass
        return self._fallback_resample(x, tempo * pitch_factor)

    def _pitch_shift(self, x: np.ndarray, sr: int, factor: float) -> np.ndarray:
        assert torch is not None and audio_functional is not None
        n_fft, hop = self._stft_sizes(x.size)
        if x.size < max(32, n_fft):
            return x
        n_steps = 12.0 * math.log2(max(factor, 1e-6))
        with torch.inference_mode():
            wave = torch.from_numpy(np.ascontiguousarray(x))
            shifted = audio_functional.pitch_shift(
                wave,
                sr,
                n_steps=n_steps,
                n_fft=n_fft,
                hop_length=hop,
            )
        return shifted.detach().cpu().numpy().astype(np.float32, copy=False)

    def _time_stretch(self, x: np.ndarray, sr: int, rate: float) -> np.ndarray:
        del sr  # STFT timing is expressed in samples; sample rate stays unchanged.
        assert torch is not None and audio_functional is not None
        n_fft, hop = self._stft_sizes(x.size)
        if x.size < max(32, n_fft * 2):
            return self._fallback_resample(x, rate)

        target = max(1, int(round(x.size / rate)))
        with torch.inference_mode():
            wave = torch.from_numpy(np.ascontiguousarray(x))
            window = torch.hann_window(n_fft, dtype=wave.dtype, device=wave.device)
            spec = torch.stft(
                wave,
                n_fft=n_fft,
                hop_length=hop,
                win_length=n_fft,
                window=window,
                center=True,
                return_complex=True,
            )
            phase_advance = torch.linspace(
                0,
                math.pi * hop,
                spec.shape[-2],
                dtype=spec.real.dtype,
                device=spec.device,
            )[..., None]
            stretched = audio_functional.phase_vocoder(spec, rate=rate, phase_advance=phase_advance)
            wave_out = torch.istft(
                stretched,
                n_fft=n_fft,
                hop_length=hop,
                win_length=n_fft,
                window=window,
                center=True,
                length=target,
            )
        return wave_out.detach().cpu().numpy().astype(np.float32, copy=False)

    def _stft_sizes(self, sample_count: int) -> tuple[int, int]:
        requested = int(self.config.get("stft_n_fft", 1024))
        n_fft = max(256, min(2048, requested))
        if sample_count > 0:
            while n_fft > 256 and n_fft > sample_count:
                n_fft //= 2
        hop = int(self.config.get("stft_hop_length", n_fft // 4))
        hop = max(64, min(n_fft // 2, hop))
        return n_fft, hop

    @staticmethod
    def _fallback_resample(x: np.ndarray, ratio: float) -> np.ndarray:
        ratio = float(np.clip(ratio, 0.75, 1.30))
        if abs(ratio - 1.0) <= 0.003 or x.size < 2:
            return x
        target = max(1, int(round(x.size / ratio)))
        idx = np.linspace(0, x.size - 1, target)
        return np.interp(idx, np.arange(x.size), x).astype(np.float32)

    @staticmethod
    def _compress(x: np.ndarray) -> np.ndarray:
        threshold = 0.32
        a = np.abs(x)
        gain = np.ones_like(a)
        over = a > threshold
        gain[over] = (threshold + (a[over] - threshold) / 3.2) / np.maximum(a[over], 1e-6)
        return x * gain

    def _highpass(self, x: np.ndarray, sr: int, hz: float) -> np.ndarray:
        if hz <= 0 or x.size < 2:
            return x
        if torch is not None and audio_functional is not None:
            try:
                with torch.inference_mode():
                    wave = torch.from_numpy(np.ascontiguousarray(x))
                    filtered = audio_functional.highpass_biquad(wave, sr, hz)
                return filtered.detach().cpu().numpy().astype(np.float32, copy=False)
            except Exception:
                pass

        rc = 1.0 / (2.0 * np.pi * hz)
        dt = 1.0 / float(sr)
        alpha = rc / (rc + dt)
        y = np.empty_like(x)
        y[0] = x[0]
        for i in range(1, x.size):
            y[i] = alpha * (y[i - 1] + x[i] - x[i - 1])
        return y

    def _normalize_loudness(self, x: np.ndarray) -> np.ndarray:
        if x.size == 0:
            return x
        rms = float(np.sqrt(np.mean(np.square(x), dtype=np.float64)))
        if rms <= 1e-7:
            return x

        target_dbfs = float(self.config.get("target_rms_dbfs", -19.0))
        target = 10.0 ** (target_dbfs / 20.0)
        gain = target / rms
        min_gain = 10.0 ** (float(self.config.get("min_gain_db", -8.0)) / 20.0)
        max_gain = 10.0 ** (float(self.config.get("max_gain_db", 6.0)) / 20.0)
        gain = float(np.clip(gain, min_gain, max_gain))
        return (x * gain).astype(np.float32, copy=False)

    @staticmethod
    def _fade_edges(x: np.ndarray, sr: int, fade_ms: float) -> np.ndarray:
        if x.size < 4 or fade_ms <= 0:
            return x
        samples = min(x.size // 2, max(1, int(round(sr * fade_ms / 1000.0))))
        if samples < 2:
            return x
        y = x.copy()
        phase = np.linspace(0.0, np.pi / 2.0, samples, dtype=np.float32)
        ramp = np.square(np.sin(phase))
        y[:samples] *= ramp
        y[-samples:] *= ramp[::-1]
        return y

    def _mechanical_layer(self, x: np.ndarray, sr: int, amount: float) -> np.ndarray:
        freq = float(self.config.get("mechanical_frequency_hz", 1830))
        t = np.arange(x.size, dtype=np.float32) / float(sr)
        carrier = 0.5 + 0.5 * np.sin(2.0 * np.pi * freq * t)
        detail = np.concatenate(([0.0], np.diff(x))).astype(np.float32, copy=False)
        if detail.size >= 3:
            detail[1:-1] = 0.25 * detail[:-2] + 0.50 * detail[1:-1] + 0.25 * detail[2:]
        return x * (1.0 - amount * 0.28) + detail * carrier * amount


def amplitude_envelope(audio, points: int = 80) -> list[float]:
    x = np.abs(np.asarray(audio, dtype=np.float32).reshape(-1))
    if x.size == 0:
        return []
    step = max(1, x.size // points)
    vals = [float(np.sqrt(np.mean(np.square(x[i:i+step])))) for i in range(0, x.size, step)]
    peak = max(vals) if vals else 1.0
    return [min(1.0, v / max(peak, 1e-6)) for v in vals[:points]]
