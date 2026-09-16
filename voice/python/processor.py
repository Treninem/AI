from __future__ import annotations

import math
import re
import numpy as np

try:
    import torch
    from torchaudio import functional as audio_functional
except Exception:  # lightweight CI and degraded local runtime keep a clean native-voice fallback
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
VERSION_NUMBER = re.compile(r"(?<!\w)-?\d+(?:\.\d+){2,}(?!\w)")
MEASURE_TOKEN = re.compile(r"(?<!\w)(-?\d+)(?:([.,])(\d+))?\s*(°\s*[cс]|%)(?!\w)", re.I)
NUMBER_TOKEN = re.compile(r"(?<!\w)(-?\d+)(?:([.,])(\d+))?(?!\w)")

_ONES_M = ("", "один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять")
_ONES_F = ("", "одна", "две", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять")
_TEENS = (
    "десять", "одиннадцать", "двенадцать", "тринадцать", "четырнадцать",
    "пятнадцать", "шестнадцать", "семнадцать", "восемнадцать", "девятнадцать",
)
_TENS = ("", "", "двадцать", "тридцать", "сорок", "пятьдесят", "шестьдесят", "семьдесят", "восемьдесят", "девяносто")
_HUNDREDS = ("", "сто", "двести", "триста", "четыреста", "пятьсот", "шестьсот", "семьсот", "восемьсот", "девятьсот")
_SCALES = (
    (1_000_000_000_000, ("триллион", "триллиона", "триллионов"), False),
    (1_000_000_000, ("миллиард", "миллиарда", "миллиардов"), False),
    (1_000_000, ("миллион", "миллиона", "миллионов"), False),
    (1_000, ("тысяча", "тысячи", "тысяч"), True),
)
_DIGIT_WORDS = ("ноль", "один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять")


def _plural_form(value: int, forms: tuple[str, str, str]) -> str:
    value = abs(int(value))
    last_two = value % 100
    if 11 <= last_two <= 14:
        return forms[2]
    last = value % 10
    if last == 1:
        return forms[0]
    if 2 <= last <= 4:
        return forms[1]
    return forms[2]


def _triad_to_words(value: int, feminine: bool = False) -> list[str]:
    value = int(value) % 1000
    if value == 0:
        return []
    out: list[str] = []
    hundreds = value // 100
    if hundreds:
        out.append(_HUNDREDS[hundreds])
    remainder = value % 100
    if 10 <= remainder <= 19:
        out.append(_TEENS[remainder - 10])
        return out
    tens = remainder // 10
    if tens:
        out.append(_TENS[tens])
    ones = remainder % 10
    if ones:
        out.append((_ONES_F if feminine else _ONES_M)[ones])
    return out


def _integer_to_words(value: int, feminine_units: bool = False) -> str:
    value = int(value)
    if value == 0:
        return "ноль"
    sign = "минус " if value < 0 else ""
    number = abs(value)
    if number >= 1_000_000_000_000_000:
        # Huge IDs are clearer when read digit by digit than when a TTS engine guesses them.
        digits = " ".join(_DIGIT_WORDS[int(ch)] for ch in str(number))
        return sign + digits

    out: list[str] = []
    for scale, forms, feminine in _SCALES:
        group = number // scale
        if group:
            out.extend(_triad_to_words(group, feminine=feminine))
            out.append(_plural_form(group, forms))
            number %= scale
    out.extend(_triad_to_words(number, feminine=feminine_units))
    return sign + " ".join(out)


def _decimal_to_words(integer_text: str, fraction_text: str) -> str:
    integer_value = int(integer_text)
    fraction_digits = fraction_text[:6].rstrip("0")
    if not fraction_digits:
        return _integer_to_words(integer_value)
    fraction_value = int(fraction_digits)
    if len(fraction_digits) <= 3:
        integer_words = _integer_to_words(integer_value, feminine_units=True)
        whole_form = "целая" if abs(integer_value) % 10 == 1 and abs(integer_value) % 100 != 11 else "целых"
        numerator = _integer_to_words(fraction_value, feminine_units=True)
        denominator_forms = {
            1: ("десятая", "десятых", "десятых"),
            2: ("сотая", "сотых", "сотых"),
            3: ("тысячная", "тысячных", "тысячных"),
        }[len(fraction_digits)]
        denominator = _plural_form(fraction_value, denominator_forms)
        return f"{integer_words} {whole_form} {numerator} {denominator}"

    sign = "минус " if integer_value < 0 else ""
    base = _integer_to_words(abs(integer_value))
    fractional = " ".join(_DIGIT_WORDS[int(ch)] for ch in fraction_digits)
    return f"{sign}{base} запятая {fractional}"


def _version_to_words(match: re.Match[str]) -> str:
    token = match.group(0)
    sign = "минус " if token.startswith("-") else ""
    if token.startswith("-"):
        token = token[1:]
    parts = [_integer_to_words(int(part)) for part in token.split(".")]
    return sign + " точка ".join(parts)


def _number_to_words(match: re.Match[str]) -> str:
    integer_text = match.group(1)
    fraction_text = match.group(3)
    if fraction_text is not None:
        return _decimal_to_words(integer_text, fraction_text)
    return _integer_to_words(int(integer_text))


def _measure_to_words(match: re.Match[str]) -> str:
    integer_text = match.group(1)
    fraction_text = match.group(3)
    unit = match.group(4).replace(" ", "").lower()
    integer_value = int(integer_text)
    has_fraction = bool(fraction_text and any(ch != "0" for ch in fraction_text))
    spoken_value = (
        _decimal_to_words(integer_text, fraction_text)
        if fraction_text is not None
        else _integer_to_words(integer_value)
    )
    if unit == "%":
        suffix = "процента" if has_fraction else _plural_form(integer_value, ("процент", "процента", "процентов"))
    else:
        suffix = "градуса Цельсия" if has_fraction else _plural_form(
            integer_value,
            ("градус Цельсия", "градуса Цельсия", "градусов Цельсия"),
        )
    return f"{spoken_value} {suffix}"


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

    # Remove formatting before verbalizing values. Unit-aware values must be
    # converted before the generic number pass so Russian morphology is correct.
    text = LINE_MARKUP.sub("", text)
    text = INLINE_MARKUP.sub("", text)
    text = re.sub(r"[{}\[\]]", " ", text)
    text = text.replace("|", ", ")
    text = MEASURE_TOKEN.sub(_measure_to_words, text)
    text = VERSION_NUMBER.sub(_version_to_words, text)
    text = NUMBER_TOKEN.sub(_number_to_words, text)

    # Give local TTS punctuation it can turn into natural short/long pauses.
    text = re.sub(r"\n{2,}", ". ", text)
    text = re.sub(r"\n", ", ", text)
    text = re.sub(r"\s*([,;:!?…])\s*", r"\1 ", text)
    text = re.sub(r"\s*\.\s*", ". ", text)
    text = re.sub(r"\.\s*,", ".", text)
    text = re.sub(r",\s*\.", ".", text)
    text = re.sub(r"\s+", " ", text).strip(" ,")
    return text


def _as_continuation(part: str, max_chars: int) -> str:
    """Mark a forced chunk split as continuation so TTS does not use sentence-final intonation."""
    clean = part.strip()
    if not clean or clean[-1] in ",;:—–.!?…":
        return clean
    if len(clean) < max_chars:
        return clean + ","
    if len(clean) >= 2:
        return clean[:-1].rstrip() + ","
    return clean


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
            out.append(_as_continuation(part, max_chars))
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
                mechanical_amount: float = 0.0, pitch_shift: float = 0.0, speed: float = 1.0):
        x = np.asarray(audio, dtype=np.float32).reshape(-1)
        if x.size == 0:
            return x

        x = self._highpass(x, sample_rate, float(self.config.get("highpass_hz", 45)))

        if self.config.get("compression", False):
            x = self._compress(x)

        pitch_factor = float(np.clip(
            1.0 + float(pitch_shift),
            float(self.config.get("pitch_min", 0.96)),
            float(self.config.get("pitch_max", 1.05)),
        ))
        tempo = float(np.clip(
            float(speed),
            float(self.config.get("speed_min", 0.90)),
            float(self.config.get("speed_max", 1.08)),
        ))
        x = self._apply_prosody(x, sample_rate, pitch_factor, tempo)

        mech = float(np.clip(mechanical_amount, 0.0, float(self.config.get("mechanical_max", 0.02))))
        if mech > 0:
            x = self._mechanical_layer(x, sample_rate, mech)

        if self.config.get("normalize", True):
            x = self._normalize_loudness(x)

        if self.config.get("limiter", True):
            ceiling = float(self.config.get("peak_ceiling", 0.96))
            peak = float(np.max(np.abs(x))) if x.size else 0.0
            if peak > ceiling > 0:
                x = x * (ceiling / peak)

        x = self._fade_edges(x, sample_rate, float(self.config.get("fade_ms", 5.0)))
        return np.clip(x, -1.0, 1.0).astype(np.float32)

    def _apply_prosody(self, x: np.ndarray, sr: int, pitch_factor: float, tempo: float) -> np.ndarray:
        if bool(self.config.get("prosody_dsp", True)) and torch is not None and audio_functional is not None:
            try:
                y = x
                # Tiny pitch shifts are more likely to add phase coloration than useful emotion.
                if abs(pitch_factor - 1.0) > 0.008:
                    y = self._pitch_shift(y, sr, pitch_factor)
                if abs(tempo - 1.0) > 0.008:
                    y = self._time_stretch(y, sr, tempo)
                return y
            except Exception:
                # Naturalness is more important than forcing an effect. A degraded
                # runtime keeps the model's native waveform instead of coupling
                # pitch and tempo through cheap resampling.
                return x
        return x

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
            return x

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
    def _compress(x: np.ndarray) -> np.ndarray:
        # Gentle safety compression only. It is disabled by default because the
        # neural TTS output already has controlled dynamics and over-compression
        # makes speech sound synthetic.
        threshold = 0.48
        a = np.abs(x)
        gain = np.ones_like(a)
        over = a > threshold
        gain[over] = (threshold + (a[over] - threshold) / 5.0) / np.maximum(a[over], 1e-6)
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

        target_dbfs = float(self.config.get("target_rms_dbfs", -20.0))
        target = 10.0 ** (target_dbfs / 20.0)
        gain = target / rms
        min_gain = 10.0 ** (float(self.config.get("min_gain_db", -6.0)) / 20.0)
        max_gain = 10.0 ** (float(self.config.get("max_gain_db", 4.0)) / 20.0)
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
        return x * (1.0 - amount * 0.20) + detail * carrier * amount


def amplitude_envelope(audio, points: int = 80) -> list[float]:
    x = np.abs(np.asarray(audio, dtype=np.float32).reshape(-1))
    if x.size == 0:
        return []
    step = max(1, x.size // points)
    vals = [float(np.sqrt(np.mean(np.square(x[i:i+step])))) for i in range(0, x.size, step)]
    peak = max(vals) if vals else 1.0
    return [min(1.0, v / max(peak, 1e-6)) for v in vals[:points]]
