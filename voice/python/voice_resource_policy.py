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

    @classmethod
    def from_environment(cls, config, environment=None):
        environment = os.environ if environment is None else environment
        cache_mb = nonnegative_integer(config.get("cache_limit_mb", 512), "cache_limit_mb")
        defaults = {"tts_input_chars": config.get("tts_input_max_chars", 16000), "cache_bytes": cache_mb * 1024 * 1024, "mic_queue_chunks": config.get("mic_queue_chunks", 128), "path_chars": config.get("path_max_chars", 4096)}
        fields = {}
        for name, default in defaults.items():
            variable = "AURORAFOX_VOICE_" + name.upper()
            fields[name] = nonnegative_integer(environment.get(variable, default), variable)
        return cls(**fields)
