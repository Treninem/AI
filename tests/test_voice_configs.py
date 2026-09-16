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
    assert cfg["silero"]["speaker"] == "kseniya"
    assert set(cfg["wake"]["words"]) >= {"fox", "фокс", "лиса"}
    assert float(cfg["mechanical_amount"]) == 0.0
    assert 0.0 <= float(cfg["emotionality"]) <= 0.65
    assert cfg["cache_limit_mb"] > 0
    assert float(cfg["speed"]) == 1.0
    assert float(cfg["pitch"]) == 1.0


def test_quality_processor_settings_are_safe_and_preserve_native_timbre_by_default():
    processor = load("voice_config.json")["processor"]
    assert int(processor["profile_revision"]) >= 2
    assert processor["prosody_dsp"] is False
    assert processor["compression"] is False
    assert float(processor["highpass_hz"]) == 0.0
    assert float(processor["mechanical_max"]) == 0.0
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


def test_godot_voice_defaults_match_neutral_dsp_and_android_does_not_retime_playback():
    manager = (ROOT / "voice" / "voice_manager.gd").read_text(encoding="utf-8")
    queue = (ROOT / "voice" / "speech_queue.gd").read_text(encoding="utf-8")
    assert '"speed": 1.0' in manager
    assert '"pitch": 1.0' in manager
    assert 'settings.get("speed", 1.0)' in manager
    assert 'settings.get("pitch", 1.0)' in manager
    assert "requested * 1.055" not in queue
    playback = queue.split("func _playback_pitch", 1)[1].split("func _prefetch_next", 1)[0]
    assert "return 1.0" in playback
    assert "pitch_scale" in playback


def test_speech_queue_forced_split_uses_natural_boundaries():
    queue = (ROOT / "voice" / "speech_queue.gd").read_text(encoding="utf-8")
    assert "MAX_SPEECH_CHUNK_CHARS := 220" in queue
    assert "func _natural_prefix" in queue
    assert 'for marker in [", ", "; ", ": ", " — ", " – "]' in queue
    assert 'cut = window.rfind(" ")' in queue
    assert "buf.length() >= 260" not in queue


def test_direct_voice_server_scales_emotion_and_invalidates_profile_cache():
    server = (ROOT / "voice" / "python" / "aurora_voice_server.py").read_text(encoding="utf-8")
    assert "power = float(np.clip(intensity * emotionality, 0.0, 1.0))" in server
    assert "base_speed * (1.0 + (profile_speed - 1.0) * power)" in server
    assert "base_pitch * (1.0 + (profile_pitch - 1.0) * power) - 1.0" in server
    assert "base_mech + (profile_mech - base_mech) * power" in server
    assert '"voice_defaults": {' in server
    assert '"emotions": EMOTIONS' in server
    assert '"processor": CONFIG.get("processor", {})' in server


def test_all_required_emotions_exist_and_are_bounded():
    emotions = load("emotions.json")
    required = {"neutral","happy","excited","thinking","focused","serious","warning","sad","confused","sleepy","playful","success","error"}
    assert required.issubset(emotions)
    for name, profile in emotions.items():
        assert 0.75 <= float(profile["speed"]) <= 1.20, name
        assert 0.90 <= float(profile["pitch"]) <= 1.12, name
        assert float(profile["mechanical"]) == 0.0, name
        assert 0.0 <= float(profile["paw_glow"]) <= 1.0, name


def test_personality_categories_are_populated():
    personality = load("personality.json")
    for category in ["greeting", "thinking", "success", "error", "warning", "joke", "startup", "shutdown", "notification", "wake_response", "confused"]:
        assert category in personality
        assert len(personality[category]) >= 1
        for item in personality[category]:
            assert item["text"].strip()
            assert float(item.get("weight", 1.0)) > 0
