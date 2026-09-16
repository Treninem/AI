from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANDROID_VOICE = ROOT / "android_plugin/plugin/src/main/java/com/aurorafox/runtime/AndroidVoiceRuntime.kt"


def source() -> str:
    return ANDROID_VOICE.read_text(encoding="utf-8")


def test_android_voice_prepares_spoken_text_locally():
    text = source()
    assert "val spokenText = prepareSpeechText(text)" in text
    assert "engine.generateWithConfig(spokenText, generation)" in text
    assert 'put("source_text", text)' in text
    assert 'put("spoken_text", spokenText)' in text
    assert "speakNumberToken" in text
    assert "integerToRussian" in text
    assert "градусов Цельсия" in text
    assert "процентов" in text


def test_android_decimal_speech_uses_natural_russian_forms():
    text = source()
    assert '"целая"' in text
    assert '"целых"' in text
    assert '"десятая"' in text
    assert '"десятых"' in text
    assert '"сотая"' in text
    assert '"сотых"' in text
    assert '"тысячная"' in text
    assert '"тысячных"' in text
    assert "integerToRussian(integerValue, feminine = true)" in text
    assert "integerToRussian(fractionalValue, feminine = true)" in text


def test_android_voice_avoids_robotic_playback_ranges():
    text = source()
    assert "speed.coerceIn(0.92f, 1.08f)" in text
    assert "val silenceScale = 0.20f + (targetSilence - 0.20f) * power" in text
    assert "piper-denis-v3" in text
    assert "pitch" not in text.lower()


def test_android_voice_remains_offline_native_piper():
    text = source()
    assert "OfflineTts" in text
    assert "sherpa-onnx-piper-denis" in text
    assert "http://" not in text
    assert "https://" not in text
