"""Trusted local Voice startup budgets; zero disables only its own ceiling."""
from dataclasses import dataclass
import os


def nonnegative_integer(value, name: str) -> int:
    raw = str(value).strip()
    if not raw.isdecimal():
        raise ValueError(f"{name} must be a nonnegative integer")
    return int(raw)


@dataclass(frozen=True)
class VoiceResourceLimits:
    tts_input_chars: int
    cache_bytes: int
    mic_queue_chunks: int
    path_chars: int = 4096
    stft_n_fft: int = 1024
    stft_hop_length: int = 256

    @classmethod
    def from_environment(cls, config, environment=None):
        environment = os.environ if environment is None else environment
        cache_mb = nonnegative_integer(config.get("cache_limit_mb", 512), "cache_limit_mb")
        processor = config.get("processor", {})
        defaults = {"tts_input_chars": config.get("tts_input_max_chars", 16000), "cache_bytes": cache_mb * 1024 * 1024, "mic_queue_chunks": config.get("mic_queue_chunks", 128), "path_chars": config.get("path_max_chars", 4096), "stft_n_fft": processor.get("stft_n_fft", 1024), "stft_hop_length": processor.get("stft_hop_length", 256)}
        fields = {}
        for name, default in defaults.items():
            variable = "AURORAFOX_VOICE_" + name.upper()
            fields[name] = nonnegative_integer(environment.get(variable, default), variable)
        fft, hop = fields["stft_n_fft"], fields["stft_hop_length"]
        if fft < 2 or fft & (fft - 1) or hop < 1 or hop > fft // 2:
            raise ValueError("Voice STFT requires power-of-two FFT >= 2 and hop in [1, FFT/2]")
        return cls(**fields)
