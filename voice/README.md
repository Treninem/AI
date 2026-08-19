# AuroraFox Voice

`AuroraVoice` — встроенная локальная подсистема Voice + Personality + Emotion + Avatar Reaction + Wake Word. Она подключена к существующему Chat/AgentCore, а не является отдельной демонстрацией.

## Поток

`microphone → VAD/wake/STT → AgentCore → response → personality/emotion → speech preparation → TTS → audio processing → Godot AudioStream → avatar reactions`

Personality влияет на подачу/голос/анимацию, но не заменяет и не переписывает фактический ответ AgentCore.

## Windows

Локальный backend: `voice/python/aurora_voice_server.py`, `127.0.0.1:8765`, WebSocket + HTTP.

Основные компоненты:

- Silero VAD;
- Vosk small RU для локального ограниченного wake-word распознавания;
- Whisper `large-v3-turbo` для полноценного русского STT;
- Silero `v5_5_ru` как базовый локальный TTS;
- необязательный advanced TTS backend через общий интерфейс;
- GPU при доступности, CPU fallback;
- локальный кэш;
- backend supervisor/reconnect;
- скрытый запуск без консольного окна в production runtime.

Silero `v5_5_ru` рассматривается как non-commercial fallback. Перед коммерческим распространением необходимо выбрать TTS/model dataset с подходящей лицензией либо получить необходимые права.

## Android

Python на телефоне не требуется. `AuroraFoxRuntime` предоставляет native local speech:

- sherpa-onnx runtime;
- русский Piper fallback TTS;
- multilingual Whisper tiny STT;
- Godot microphone capture;
- локальный VAD/conversation segmentation;
- wake recognition `Fox / Фокс / Лиса`;
- barge-in и self-echo guard.

Android voice assets подготавливаются `android_plugin/setup_native.ps1` и упаковываются в Android plugin/AAB/APK build.

## Wake / разговор

Режимы:

- off;
- wake word;
- continuous conversation;
- push-to-talk.

Основные обращения:

- `Fox`;
- `Фокс`;
- `Лиса`;
- варианты `Эй, Fox` / `Эй, Лиса`.

После wake-word открывается короткое conversational window, поэтому следующую фразу можно говорить без повторного обращения.

## Barge-in

Когда пользователь начинает говорить во время TTS:

1. речь AuroraFox приглушается;
2. VAD/STT проверяют реальную пользовательскую фразу;
3. self-echo сравнивается с текущим TTS;
4. если это собственное эхо — реплика не попадает в AgentCore;
5. если это пользователь — текущая озвучка прерывается и новая фраза отправляется в чат.

## Personality / Emotion

Фразы хранятся в `voice/config/personality.json`, профили эмоций — в `voice/config/emotions.json`.

Поддерживаются состояния:

`neutral, happy, excited, thinking, focused, serious, warning, sad, confused, sleepy, playful, success, error`.

Эмоция влияет на voice profile и avatar state. Характерные шутки/лисий стиль имеют низкую частоту и не должны мешать техническим ответам.

## Speech preparation

Перед TTS текст адаптируется для речи:

- удаляется Markdown;
- emoji используются как emotion hint, но не проговариваются;
- длинный код автоматически не зачитывается;
- URL/пути/служебная разметка сокращаются до понятной голосовой формы;
- длинный ответ режется на предложения;
- следующая часть синтезируется параллельно воспроизведению текущей.

## Avatar signals

Voice Manager выдаёт:

- `speech_started`;
- `speech_finished`;
- `speech_amplitude(value)`;
- `emotion_changed(emotion, intensity)`;
- `listening_started/finished`;
- `thinking_started/finished`.

Амплитуда реального TTS используется для lip-sync. Отдельный avatar controller управляет глазами, ушами, хвостом, ртом и реакцией механической лапы.

## Установка Windows voice runtime

```powershell
./voice/install_voice.ps1
```

Первый запуск AuroraFox также имеет собственный Voice Setup Wizard с реальными этапами подготовки, а не декоративным прогрессом.

## Логи и приватность

Лог: `user://logs/aurora_voice.log`.

В лог пишутся запуск/остановка backend, model/fallback/audio/microphone errors. Сырой звук пользователя постоянно не сохраняется; временный speech buffer удаляется после обработки.

## Проверки

- `tests/test_voice_text.py`;
- `tests/test_voice_configs.py`;
- `tests/voice_smoke.gd`;
- `.github/workflows/voice-ci.yml`.

Наличие этих тестов не означает, что конкретный микрофон/Android-устройство уже физически проверены: аппаратный runtime-test выполняется отдельно на целевой платформе.
