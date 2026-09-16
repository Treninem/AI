from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
VOICE_PY = ROOT / "voice" / "python"
sys.path.insert(0, str(VOICE_PY))

from emotion_parser import detect_emotion
from personality import AuroraPersonality
from processor import AuroraVoiceProcessor, prepare_for_speech, split_for_streaming


def test_prepare_for_speech_hides_code_url_and_emoji():
    src = "Готово 🦊\n```python\nprint('secret code')\n```\nПодробнее: https://example.com/x"
    spoken = prepare_for_speech(src)
    assert "print" not in spoken
    assert "https://" not in spoken
    assert "🦊" not in spoken
    assert "Код я показала" in spoken
    assert "ссылка в сообщении" in spoken


def test_prepare_for_speech_verbalizes_minus_and_hides_paths():
    src = (
        "**Важно:** температура -5. "
        "[Документация](https://example.com/manual) лежит "
        r"C:\AuroraFox\voice\manual.txt и /opt/aurorafox/voice/model.bin"
    )
    spoken = prepare_for_speech(src)
    assert "минус пять" in spoken
    assert "-5" not in spoken
    assert "Документация" in spoken
    assert "example.com" not in spoken
    assert spoken.count("путь к файлу") == 2
    assert "**" not in spoken


def test_prepare_for_speech_verbalizes_integer_decimal_percent_and_version():
    spoken = prepare_for_speech("Температура 23 °C, давление 2,4 бара, прогресс 75%, версия 1.3.0.")
    assert "двадцать три градусов Цельсия" in spoken
    assert "две целых четыре десятых бара" in spoken
    assert "семьдесят пять процентов" in spoken
    assert "один точка три точка ноль" in spoken
    assert not any(ch.isdigit() for ch in spoken)


def test_streaming_split_is_sentence_based():
    chunks = split_for_streaming("Первая фраза готова. Вторая тоже готова! А это третья?")
    assert len(chunks) >= 2
    assert all(chunk.strip() for chunk in chunks)


def test_streaming_prefers_clause_boundaries_for_long_speech():
    src = (
        "Это длинная фраза, в которой есть несколько логических частей, "
        "и её нужно делить по естественным паузам, а не посреди слов, "
        "чтобы голос звучал аккуратно и естественно."
    )
    chunks = split_for_streaming(src, max_chars=80)
    assert len(chunks) >= 2
    assert all(0 < len(chunk) <= 80 for chunk in chunks)
    assert all(chunk[-1] in ",;:—–.!?…" for chunk in chunks[:-1])


def test_degraded_fallback_preserves_native_timbre_instead_of_resampling():
    processor = AuroraVoiceProcessor({
        "prosody_dsp": False,
        "highpass_hz": 0,
        "compression": False,
        "normalize": False,
        "limiter": False,
        "fade_ms": 0,
    })
    audio = np.sin(np.linspace(0.0, 20.0 * np.pi, 1000, dtype=np.float32))
    out = processor.process(
        audio,
        16000,
        mechanical_amount=0.0,
        pitch_shift=0.04,
        speed=1.10,
    )
    assert out.dtype == np.float32
    assert out.size == audio.size
    assert np.allclose(out, audio, atol=1e-6)
    assert np.isfinite(out).all()


def test_quality_dsp_contract_uses_separate_pitch_and_tempo_paths():
    source = (VOICE_PY / "processor.py").read_text(encoding="utf-8")
    assert "audio_functional.pitch_shift" in source
    assert "audio_functional.phase_vocoder" in source
    assert "_normalize_loudness" in source
    assert "_fade_edges" in source
    assert "tempo * pitch_factor" not in source
    assert "return x" in source


def test_emotion_success_warning_error():
    assert detect_emotion("Готово! Всё работает.")["emotion"] == "success"
    assert detect_emotion("Внимание. Температура слишком высокая.")["emotion"] == "warning"
    assert detect_emotion("Нашла ошибку, здесь не работает загрузчик.")["emotion"] == "error"


def test_personality_avoids_immediate_repeat(tmp_path: Path):
    data = {
        "wake_response": [
            {"text": "Да?", "weight": 1.0},
            {"text": "Я тут.", "weight": 1.0},
            {"text": "Слушаю.", "weight": 1.0},
            {"text": "Что такое?", "weight": 1.0},
        ]
    }
    path = tmp_path / "personality.json"
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    p = AuroraPersonality(path)
    values = [p.wake_response() for _ in range(8)]
    assert all(a != b for a, b in zip(values, values[1:]))
