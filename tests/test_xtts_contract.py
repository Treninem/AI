from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_xtts_optional_dependencies_are_pinned():
    requirements = read("voice/requirements_xtts.txt")
    assert "coqui-tts==0.27.5" in requirements
    assert "torchcodec==0.9.1" in requirements


def test_xtts_engine_resolves_portable_speaker_reference():
    engine = read("voice/python/tts_engine.py")
    assert "VOICE_ROOT = Path(__file__).resolve().parents[1]" in engine
    assert 'from TTS.api import TTS' in engine
    assert 'tts_models/multilingual/multi-dataset/xtts_v2' in engine
    assert "path = VOICE_ROOT / path" in engine
    assert "speaker_wav=str(speaker)" in engine


def test_voice_installer_can_enable_and_validate_xtts():
    installer = read("voice/install_voice.ps1")
    assert "[switch]$EnableXtts" in installer
    assert "$XttsSpeakerWav" in installer
    assert "requirements_xtts.txt" in installer
    assert "XTTS_IMPORT_OK" in installer
    assert "XTTS_MODEL_READY" in installer
    assert "models/xtts_speaker.wav" in installer


def test_default_config_keeps_voice_cloning_opt_in():
    config = json.loads(read("voice/config/voice_config.json"))
    xtts = config["xtts"]
    assert xtts["model"] == "tts_models/multilingual/multi-dataset/xtts_v2"
    assert xtts["enabled"] is False
    assert xtts["speaker_wav"] == ""
