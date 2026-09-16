from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "voice" / "config"


def load(name: str):
    return json.loads((CONFIG / name).read_text(encoding="utf-8"))


def test_voice_config_has_required_local_paths():
    cfg = load("voice_config.json")
    assert cfg["backend"] in {"auto", "silero", "xtts"}
    assert cfg["language"] == "ru"
    assert set(cfg["wake"]["words"]) >= {"fox", "фокс", "лиса"}
    assert 0.0 <= cfg["mechanical_amount"] <= 0.10
    assert cfg["cache_limit_mb"] > 0
    assert 0.95 <= float(cfg["speed"]) <= 1.05
    assert 0.95 <= float(cfg["pitch"]) <= 1.05


def test_quality_processor_settings_are_safe_and_bounded():
    processor = load("voice_config.json")["processor"]
    assert processor["prosody_dsp"] is True
    assert 0.75 <= float(processor["speed_min"]) < 1.0
    assert 1.0 < float(processor["speed_max"]) <= 1.30
    assert 0.85 <= float(processor["pitch_min"]) < 1.0
    assert 1.0 < float(processor["pitch_max"]) <= 1.20
    assert 256 <= int(processor["stft_n_fft"]) <= 2048
    assert 64 <= int(processor["stft_hop_length"]) < int(processor["stft_n_fft"])
    assert -30.0 <= float(processor["target_rms_dbfs"]) <= -12.0
    assert -18.0 <= float(processor["min_gain_db"]) <= 0.0
    assert 0.0 <= float(processor["max_gain_db"]) <= 12.0
    assert 0.80 <= float(processor["peak_ceiling"]) <= 1.0
    assert 0.0 <= float(processor["fade_ms"]) <= 20.0
    assert 0.0 <= float(processor["mechanical_max"]) <= 0.10


def test_all_required_emotions_exist_and_are_bounded():
    emotions = load("emotions.json")
    required = {"neutral","happy","excited","thinking","focused","serious","warning","sad","confused","sleepy","playful","success","error"}
    assert required.issubset(emotions)
    for name, profile in emotions.items():
        assert 0.75 <= float(profile["speed"]) <= 1.20, name
        assert 0.90 <= float(profile["pitch"]) <= 1.12, name
        assert 0.0 <= float(profile["mechanical"]) <= 0.10, name
        assert 0.0 <= float(profile["paw_glow"]) <= 1.0, name


def test_personality_categories_are_populated():
    personality = load("personality.json")
    for category in ["greeting", "thinking", "success", "error", "warning", "joke", "startup", "shutdown", "notification", "wake_response", "confused"]:
        assert category in personality
        assert len(personality[category]) >= 1
        for item in personality[category]:
            assert item["text"].strip()
            assert float(item.get("weight", 1.0)) > 0
