from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VOICE_PY = ROOT / "voice" / "python"
sys.path.insert(0, str(VOICE_PY))

from emotion_parser import detect_emotion
from personality import AuroraPersonality
from processor import prepare_for_speech, split_for_streaming


def test_prepare_for_speech_hides_code_url_and_emoji():
    src = "Готово 🦊\n```python\nprint('secret code')\n```\nПодробнее: https://example.com/x"
    spoken = prepare_for_speech(src)
    assert "print" not in spoken
    assert "https://" not in spoken
    assert "🦊" not in spoken
    assert "Код я показала" in spoken
    assert "ссылка в сообщении" in spoken


def test_streaming_split_is_sentence_based():
    chunks = split_for_streaming("Первая фраза готова. Вторая тоже готова! А это третья?")
    assert len(chunks) >= 2
    assert all(chunk.strip() for chunk in chunks)


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
