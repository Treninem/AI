# AuroraFox — локальный AI для Windows и Android

AuroraFox — локальный AI-помощник на Godot 4.7.1 с собственным чат-интерфейсом, памятью, файлами, голосовой личностью, компьютерным агентом, песочницами, специализированными внутренними агентами и системой безопасных обновлений.

Основной принцип проекта: локальная работа и бесплатные/open-source компоненты там, где это возможно. Ошибка необязательного модуля не должна закрывать чат или ломать основное AI-ядро.

## Текущая версия

`0.4.0`

Версия хранится в `project.godot`; Android `version/name` синхронизирован в `export_presets.cfg`.

## Платформы

### Windows x86_64

- Godot 4.7.1;
- Ollama/local LLM;
- отдельная кодовая модель и vision-модель;
- локальная история, память, опыт и база знаний;
- голосовой backend;
- управление экраном/мышью/клавиатурой через Computer Agent;
- UI Automation + vision fallback;
- локальные и контейнерные sandbox/workspace;
- snapshot/rollback;
- встроенная система обновлений;
- Inno Setup для первоначальной установки.

### Android arm64

- тот же основной AgentCore/UI-поток;
- Godot Android plugin `AuroraFoxRuntime`;
- локальный llama.cpp/GGUF runtime;
- локальный Android STT/TTS через native speech runtime;
- Godot microphone capture + VAD/conversation logic;
- Android private storage;
- WASM sandbox для переносимого экспериментального кода;
- встроенная загрузка APK-обновления с SHA-256;
- передача проверенного APK штатному Android Package Installer.

Android не обходит системное подтверждение установки новой APK. Все APK-релизы должны использовать один и тот же постоянный release signing key.

## Чат

- новый чат;
- история диалогов;
- поиск;
- удаление и продолжение старых чатов;
- локальное сохранение;
- вложения;
- основной AI Core остаётся единственным источником ответа;
- голос и personality работают поверх ответа, а не заменяют интеллект.

## Голосовая личность

`AuroraVoice` подключён как autoload.

Система включает:

- локальный русский TTS;
- локальный STT;
- VAD;
- wake words `Fox / Фокс / Лиса`;
- разговорное окно после пробуждения;
- barge-in: пользователь может начать говорить во время ответа;
- защита от активации собственным TTS;
- очередь озвучки по предложениям;
- personality phrases без постоянного повторения одной реплики;
- emotion parser;
- разные speed/pitch/mechanical параметры по эмоции;
- очистку Markdown/code/URL для голосовой версии;
- голосовой cache;
- локальные voice logs без хранения сырой записи пользователя;
- быстрый mute;
- voice settings;
- avatar signals: speaking/listening/thinking/emotion/amplitude.

На Windows голос использует локальный Python backend. На Android голос подключён к native plugin, без необходимости Python на телефоне.

Подробности: `voice/README.md`.

## Аватар

Голосовой контроллер уже отдаёт реальные состояния:

- `AI_IDLE`;
- `AI_WORKING`;
- `AI_READING`;
- `AI_CODING`;
- `AI_SEARCHING`;
- `AI_SPEAKING`;
- `AI_LISTENING`;
- `AI_SUCCESS`;
- `AI_ERROR`.

Lip-sync использует амплитуду реального синтезированного звука. Текущий кодовый avatar view имеет независимые рот/глаза/уши/хвост/механическую лапу. При появлении финального слоёного/ригованного арта контроллер можно подключить к нему без замены Voice Manager.

## Агентное ядро

В сложных задачах AuroraFox может маршрутизировать работу между специализированными ролями:

- planner;
- researcher;
- critic;
- computer operator;
- file analyst;
- tester;
- verifier;
- knowledge curator;
- Code Architect / Code Specialist.

Цикл сложной задачи:

`задача → поиск опыта → план → специалисты → критика плана → инструменты/sandbox → тесты → verifier → ответ → сохранение навыка`.

## Код и песочницы

Кодовый слой не ограничен одним языком. Реестр содержит основные системные, web, mobile, scripting и scientific языки и может расширяться без переписывания AgentCore.

Правило кодового режима:

1. определить язык/окружение;
2. понять существующий проект;
3. создать отдельный workspace;
4. snapshot до существенного изменения;
5. изменить копию;
6. выполнить подходящий test/lint/compile/run;
7. проверить результат;
8. rollback при регрессии;
9. только потом считать изменение рабочим.

Windows может использовать локальный allowlist инструментов или Docker/Podman. Android не получает глобальный shell телефона: экспериментальный исполняемый код ограничивается app sandbox/WASM runtime.

## Computer Agent

Windows Computer Agent предоставляет:

- screenshot;
- vision-модель;
- Windows UI Automation;
- move/click/double-click/right-click;
- mouse down/up;
- scroll;
- keyboard/type/hotkeys;
- повторный визуальный контроль после действия;
- PyAutoGUI fail-safe;
- sandbox/workspace API.

Это техническая база для задач вроде работы с обычными программами и визуальными играми. Успех конкретной задачи должен подтверждаться фактическим состоянием экрана, а не заявлением модели.

## Память и опыт

AuroraFox хранит отдельно:

- историю чатов;
- долговременную память;
- знания;
- успешные навыки;
- ошибки;
- confidence;
- контрольные точки;
- идеи улучшений.

`DreamCycle` анализирует накопленные слабые места и создаёт предложения улучшений, но не применяет произвольное изменение ядра без проверки.

## Автоматические обновления

`AuroraUpdate` — отдельный autoload. Stable-релизы берутся из GitHub Releases.

Путь:

`latest update.json → сравнение версии → platform asset → download → SHA-256 → platform installer`.

### Windows update

- обновление скачивается как `AuroraFox-Windows.zip`;
- проверяется SHA-256;
- helper работает отдельно от приложения;
- завершает sidecar-процессы из каталога AuroraFox;
- хранит старую версию как rollback;
- переключает каталоги;
- сохраняет тяжёлые локальные models/runtime;
- запускает новую версию с health marker;
- при неуспешном старте возвращает предыдущую версию.

### Android update

- APK скачивается в приватное хранилище;
- проверяется SHA-256;
- native plugin выдаёт APK Android через read-only content URI;
- далее работает штатный Package Installer Android;
- при необходимости AuroraFox открывает системную страницу разрешения установки из этого источника.

Подробности: `update/README.md`.

## Релизы

`.github/workflows/release.yml` предназначен для tag-релизов `v*` и формирует:

- `AuroraFox_Setup_Windows.exe` — первоначальный Windows installer;
- `AuroraFox-Windows.zip` — пакет встроенного Windows updater;
- `AuroraFox-Android.apk` — Android installer/update package;
- `update.json` — version/URL/SHA-256 manifest.

Android требует постоянную release-подпись. Локальный помощник:

```powershell
./build/create_android_signing_key.ps1
```

Он создаёт ключ только в `build/private/`, который исключён из Git. Для GitHub Actions затем нужны repository secrets:

- `AURORA_ANDROID_KEYSTORE_BASE64`
- `AURORA_ANDROID_KEYSTORE_USER`
- `AURORA_ANDROID_KEYSTORE_PASSWORD`

Ключ и пароль нужно сохранить отдельно: потерянный Android signing key нельзя просто заменить, не сломав цепочку обновления уже установленного приложения.

## Локальная сборка

Windows:

```powershell
./build/build_windows.ps1
```

Android:

```powershell
./build/build_android.ps1
```

Для Android нужны JDK/Android SDK/NDK/Gradle и постоянный signing key для release-сборки.

## Проверки

Core CI выполняет:

- Python compile/tests для voice;
- headless import/parse проекта в Godot 4.7.1;
- voice GDScript smoke test;
- updater GDScript smoke test.

В репозитории реализована сборочная и обновляющая инфраструктура, но **реальный Windows installer и Android APK нельзя считать проверенными на устройстве, пока соответствующие release jobs и platform runtime-tests фактически не завершились успешно**.
