# AuroraFox — локальный AI для Windows и Android

AuroraFox — локальное AI-приложение на Godot 4.7.1 с современным чат-интерфейсом, памятью, файлами, голосом, компьютерным зрением, агентными инструментами, песочницами и контролируемым самоулучшением.

Главное правило проекта: по возможности использовать локальные и бесплатные компоненты. Облачный AI не требуется для основной архитектуры.

## Платформы

### Windows x86_64

Основной полнофункциональный режим:

- Godot 4.7.1;
- Ollama для локальных LLM;
- `qwen3:8b` — основной агент;
- `qwen3-coder:30b` — программирование;
- `qwen3-vl:8b` — зрение/GUI;
- локальная память, база знаний, история и опыт;
- Python voice/computer services;
- управление мышью/клавиатурой и чтение Windows UI Automation;
- локальная песочница;
- Docker/Podman-песочница при наличии;
- сеть внутри контейнера отключена по умолчанию;
- снимки workspace и rollback;
- тесты/компиляция перед признанием результата рабочим.

### Android arm64

Мобильная версия использует тот же AgentCore и UI-логику, но другой локальный runtime:

- Godot 4.7.1 + Gradle Android export;
- responsive/touch UI;
- private app storage Android;
- `AuroraFoxRuntime` Godot Android plugin;
- локальный `llama.cpp` JNI runtime;
- GGUF-модель хранится в `user://models/aurorafox-main.gguf`;
- первый запуск предлагает скачать подходящую локальную модель;
- Qwen3 1.7B Q4 для более слабых устройств;
- Qwen3 4B Q4 для устройств с большим объёмом RAM;
- SHA-256 проверка модели после загрузки;
- WASM-песочница для переносимых экспериментальных модулей;
- отдельный Android `isolatedProcess` сервис заложен в плагин для дальнейшего усиления изоляции.

После установки GGUF сама генерация ответов выполняется локально на устройстве. Первая загрузка модели требует интернета, если GGUF не скопирован на устройство вручную.

## Интерфейс

- собственный дизайн AuroraFox;
- фон и UI-атлас из `assets/`;
- новый чат;
- история чатов;
- поиск;
- удаление/переключение;
- автоматическое сохранение;
- несколько вложений;
- drag/file picker архитектура;
- Enter — отправить, Shift+Enter — новая строка;
- Android: сворачиваемый sidebar и touch-friendly controls.

## Агентное ядро

`AgentCore` использует не одну роль, а команду специалистов:

- planner;
- researcher;
- critic;
- computer operator;
- file analyst;
- tester;
- verifier;
- knowledge curator;
- Code Architect / Code Specialist.

Сложная задача проходит цепочку:

`задача → похожий опыт → специалисты → общий план → критик плана → песочница/инструменты → тесты → self-check → verifier → ответ → сохранение навыка`.

## Работа с кодом

AuroraFox имеет расширяемый реестр языков и не привязан к одному стеку. В реестре уже предусмотрены Python, GDScript, JavaScript, TypeScript, C, C++, C#, Java, Kotlin, Rust, Go, PHP, Ruby, Lua, Swift, Dart, SQL, Bash, PowerShell, R, Julia, Elixir, Erlang, Haskell, OCaml, Zig, Nim, Fortran, COBOL, Pascal, Assembly и другие.

Правило кодового режима:

1. определить язык, проект и зависимости;
2. понять назначение, состояние и поток данных;
3. создать отдельный workspace;
4. работать с копиями;
5. создать snapshot перед крупным изменением;
6. выполнить код в подходящей среде;
7. запустить тест/компиляцию/static check;
8. при ухудшении выполнить rollback;
9. только после проверки переносить результат в реальную среду.

Поддержка языка в реестре не означает, что компилятор этого языка автоматически установлен на каждом устройстве. Windows может использовать локально установленные инструменты или контейнерный профиль. Android на текущем этапе исполняет экспериментальный код через WASM runtime.

## Песочницы

Основной API:

- `workspace_create`;
- `workspace_status`;
- `workspace_tree`;
- `workspace_write`;
- `workspace_read`;
- `workspace_snapshot`;
- `workspace_rollback`;
- `workspace_exec`;
- `workspace_test`.

### Windows sandbox

`computer/computer_service.py` хранит реальный workspace и выполняет команды в той же папке, в которую агент пишет файлы.

При наличии Podman/Docker предпочтителен контейнер:

- `--network none`;
- read-only root filesystem;
- только текущий workspace монтируется writable;
- memory/CPU/PID limits;
- no-new-privileges;
- временная файловая система `/tmp` ограничена.

Без контейнера используется разрешённый список локальных инструментов.

### Android sandbox

Android уже изолирует AuroraFox на уровне UID/private app storage. Дополнительно экспериментальные исполняемые модули проходят через WASM runtime и не получают Android shell/API автоматически.

На текущем этапе Android runtime выполняет **предварительно скомпилированные WASM-модули**. Полноценные встроенные компиляторы/интерпретаторы для всех языков на телефоне ещё не считаются готовыми.

## Локальные модели Android

`LocalModelManager` поддерживает:

- streamed download прямо в файл, без загрузки всей модели в RAM;
- выбор профиля по RAM/storage;
- проверку свободного места;
- SHA-256 verification;
- ручную установку локального GGUF;
- активацию модели только после успешной проверки.

Активная модель:

`user://models/aurorafox-main.gguf`

## Голос

### Windows

Уже подключены:

- русский TTS через локальный voice service;
- Whisper-compatible STT;
- микрофон в Godot;
- автоматическое чтение ответов.

### Android

В Android plugin уже есть интерфейс локального STT, а официальный `whisper.cpp` исходник загружается сборочным setup-скриптом. Полный JNI-adapter для Android STT и отдельный качественный русский Android TTS ещё требуется довести и проверить на реальном устройстве. Эти функции не должны считаться готовыми до runtime-теста.

## Компьютерный агент

На Windows:

- screenshot;
- Qwen3-VL vision;
- UI Automation;
- mouse move/click/right click/double click;
- keyboard/type/hotkeys;
- scroll;
- цикл `вижу → действую → снова вижу → проверяю`;
- PyAutoGUI fail-safe.

Это позволяет строить навыки для обычных GUI-задач и визуальных игр, но успех каждой конкретной задачи должен подтверждаться наблюдаемым состоянием экрана.

Android не получает эквивалентный глобальный доступ к чужим приложениям автоматически: мобильная ОС имеет другую модель разрешений и изоляции.

## Память и обучение на опыте

AuroraFox хранит:

- историю диалогов;
- долговременную память;
- базу знаний;
- навыки;
- успешные стратегии;
- ошибки;
- контрольные точки;
- confidence;
- идеи улучшений.

`DreamCycle` анализирует повторяющиеся ошибки и предлагает улучшения, но не переписывает рабочее ядро бесконтрольно.

## Основные файлы

- `scripts/main.gd` — UI;
- `scripts/agent_core.gd` — главный агент;
- `scripts/specialist_team.gd` — команда специалистов;
- `scripts/code_specialist.gd` — Code Architect;
- `scripts/code_language_registry.gd` — языки;
- `scripts/memory_store.gd` — память;
- `scripts/experience_store.gd` — навыки/опыт;
- `scripts/cognition_layer.gd` — planning/self-check;
- `scripts/dream_cycle.gd` — предложения улучшений;
- `scripts/tool_registry.gd` — инструменты;
- `scripts/sandbox_manager.gd` — единый sandbox API;
- `scripts/sandbox_tool_bridge.gd` — sandbox tools для AgentCore;
- `computer/computer_service.py` — Windows GUI + sandbox service;
- `scripts/android_local_runtime.gd` — Godot bridge к Android runtime;
- `android_plugin/` — Android native plugin;
- `scripts/local_model_manager.gd` — локальные мобильные GGUF;
- `scripts/android_first_run.gd` — установка модели при первом запуске;
- `scripts/mobile_ui_adapter.gd` — адаптация UI для телефона.

## Сборка Windows

Требуются Godot 4.7.1 export templates. Затем:

```powershell
powershell -ExecutionPolicy Bypass -File .\build\build_windows.ps1
```

Результат должен появиться в:

`build/windows/AuroraFox.exe`

## Сборка Android

Нужны:

- Godot 4.7.1 + Android export templates;
- Android SDK/NDK;
- Java/Gradle;
- переменная `ANDROID_HOME` или `ANDROID_SDK_ROOT`.

Сборка:

```powershell
powershell -ExecutionPolicy Bypass -File .\build\build_android.ps1
```

Скрипт:

1. получает исходники локальных native runtimes;
2. собирает `AuroraFoxRuntime` AAR;
3. копирует AAR в Godot addon;
4. устанавливает Gradle build template;
5. экспортирует Android preset.

Ожидаемый результат:

`build/android/AuroraFox.apk`

## Что ещё обязательно проверить перед релизом

- headless parse/test всех GDScript на Godot 4.7.1;
- реальную Windows сборку;
- Docker/Podman sandbox integration test;
- Android Gradle/NDK build;
- запуск llama.cpp GGUF на реальном arm64 телефоне;
- производительность 1.7B/4B моделей;
- Android WASM runtime;
- Android voice STT/TTS;
- Android permissions/lifecycle/background behavior;
- installer/update pipeline;
- лицензии всех моделей перед публичной/коммерческой поставкой.
