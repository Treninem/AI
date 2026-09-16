# AuroraFox — локальный AI для Windows и Android

AuroraFox — локальный AI-помощник на Godot 4.7.1 с собственным чат-интерфейсом, памятью, Core Knowledge, файлами, голосом, Computer Agent, Work/projects, песочницами, контролируемым самоулучшением и системой безопасных обновлений.

Главный продуктовый принцип: **обычный пользователь устанавливает AuroraFox и получает рабочий локальный AI без обязательной установки Ollama, отдельного LLM-клиента, отдельного inference engine или ручного выбора/скачивания GGUF.** AuroraFox Core и необходимые веса поставляются вместе с приложением.

## Жёсткий принцип самостоятельности

AuroraFox — не оболочка над Ollama, OpenAI API, облачной моделью или другим AI-клиентом. **Основой интеллекта является только собственный AuroraFox Core.**

Это означает:

- собственная модель/runtime являются primary и product default;
- память, Core Knowledge, навыки, история, планирование, критика, принятие решений и локальная генерация должны работать без внешнего AI;
- AuroraFox должна уметь локально читать поддерживаемые файлы, говорить/слушать через локальный baseline и сохранять полученный опыт у себя;
- автономное обучение на разрешённых данных должно пополнять собственные знания/память/навыки, а не делать удалённый сервис единственным носителем обучения;
- контролируемое самоулучшение должно уметь предлагать, тестировать и проверять улучшения собственного Core, сохраняя master stop, allowlist, sandbox, независимую проверку и rollback;
- интернет и сайты должны использоваться как источники информации и поверхности действий через собственный AgentCore/Computer Agent. Интернет может быть нужен конкретной онлайн-задаче, но не базовому мышлению AuroraFox;
- Ollama и любые внешние AI/API разрешены только как **необязательные дополнительные инструменты**. Их отключение, удаление или недоступность не должны делать AuroraFox неспособной думать, отвечать, пользоваться локальной памятью или улучшать собственные проверяемые компоненты;
- результаты внешних моделей, сайтов, документов и загруженного кода считаются входными данными/подсказками и не получают права управлять Core или обходить проверки.

Изменение, которое делает внешний AI/model/service необходимым для нормальной работы интеллекта AuroraFox, считается архитектурной регрессией.

## Обязательное правило разработки

Перед любыми изменениями ChatGPT Chat, Work, Codex и другие агенты обязаны прочитать `AGENTS.md` и полностью прочитать/обновить единый журнал:

`docs/PROJECT_MASTER_LOG.md`

Отдельные параллельные журналы разработки не создаются. Активные задачи, занятые файлы, решения, проверки, commits и план продолжения ведутся только там.

## Текущая версия

**V1.3.0.0**

- canonical metadata: `project/version.json`;
- Android `versionCode`: `100005`;
- Godot: `4.7.1`.

## Самостоятельный AuroraFox Core

### Windows x86_64

Windows-пакет включает:

- AuroraFox application;
- локальный `llama-server.exe` как внутренний AuroraFox Core Engine;
- встроенные AuroraFox Core GGUF weights;
- локальную память/Core Knowledge;
- voice/file/computer/API sidecars;
- transactional updater и rollback helper.

`DesktopLocalRuntime` поднимает внутренний Core только на localhost (`127.0.0.1`) и прогревает его перед первым запросом. Если пользователь отправляет сообщение во время фонового warmup, запрос присоединяется к уже идущей подготовке вместо запуска конкурирующего сервера.

### Android arm64

Android APK содержит:

- Godot application;
- native `AuroraFoxRuntime` plugin;
- встроенный llama.cpp inference path;
- AuroraFox Core weights внутри APK;
- локальный STT/TTS runtime;
- private app storage и local file intelligence.

При первом запуске bundled Core asset переносится во внутреннее хранилище приложения через временный файл и проверяется по размеру, GGUF header и SHA-256 перед активацией. Пользователь не выбирает модель и не проходит model setup wizard.

### Ollama и внешние AI

Ollama **не является зависимостью AuroraFox**:

- compatibility fallback выключен по умолчанию;
- локальный Core всегда primary;
- Android Ollama path не использует;
- отсутствие/ошибка Ollama не делает AuroraFox недоступным;
- legacy Ollama model/URL в коде явно маркируются как compatibility-only и не являются product default;
- внешние AI API не должны становиться обязательным путём для chat/planning/learning/self-improvement.

Compatibility adapter оставлен только для дополнительных/старых сценариев и не должен превращаться в обязательный runtime.

## Чат и AgentCore

Основной поток:

`сообщение → локальный контекст/память/Core Knowledge → AgentCore/планирование при необходимости → AuroraFox Core → ответ → локальное сохранение опыта`

Для сложных задач доступны роли planner, researcher, critic, file analyst, computer operator, tester, verifier, knowledge curator и code specialist. Сложная задача должна проходить фактическую проверку результата, а не считаться выполненной только по заявлению модели.

## Память и Core Knowledge

AuroraFox раздельно хранит:

- историю чатов;
- долговременную память;
- Core Knowledge;
- навыки/успешные решения;
- ошибки и confidence;
- checkpoints;
- идеи улучшений.

Локальный semantic/vector retrieval не требует внешнего AI-провайдера. Lexical fallback сохраняется для деградационного режима.

### Импорт пользовательских знаний

Поддерживаются произвольные имена файлов и несколько классов форматов, включая JSON/JSONL/NDJSON, CSV/TSV, text/code/data, DOCX/ODT/RTF/EPUB и rich-document extraction для PDF/таблиц/презентаций. Android умеет локально извлекать text-layer PDF.

Большие JSONL/CSV/text и большие monolithic JSON импортируются потоково. Source registry использует fingerprints, aliases и revisions. Byte-identical renamed files не должны создавать дубликаты. Неудачный re-import использует source-scoped transaction rollback.

Содержимое документов и загруженный код считаются **данными**, а не командами с системными полномочиями, и не исполняются автоматически.

## Controlled self-improvement

AuroraFox должна развивать собственные знания/навыки и может создавать варианты улучшений своего ядра, но не имеет права безусловно переписывать production Core.

Контур:

`локальный опыт/исследование → candidate → source contract → sandbox/workspace → baseline tests → candidate tests → regression/safety gates → independent verification → controlled promotion`

Защищены:

- user master stop;
- rollback;
- updater/release trust;
- candidate verifier;
- API/release credentials;
- protected paths вне узкого Core allowlist.

Самоулучшение не должно иметь возможность удалить собственные ограничения/проверки. Внешняя модель может быть дополнительным источником идеи, но не судьёй и не обязательным генератором улучшения.

## Голос

`AuroraVoice` предоставляет локальные STT/TTS, VAD, wake word (`Fox / Фокс / Лиса`), conversational window, barge-in, emotion/personality layer и avatar state signals. Голос является интерфейсом поверх собственного Core и не заменяет интеллект отдельным сетевым провайдером.

Windows использует локальный управляемый voice backend, Android — native speech/runtime path.

## Computer Agent, интернет и sandbox

Windows Computer Agent поддерживает screenshot, UI Automation, mouse/keyboard, vision fallback и повторный визуальный контроль. Кодовые эксперименты выполняются в workspace/sandbox с snapshot/test/rollback. Android не получает глобальный shell устройства; исполняемые эксперименты ограничены app sandbox/runtime boundaries.

Интернет/сайты являются инструментом исследования и выполнения задач. AuroraFox должна сама формировать план, выбирать нужную информацию, проверять результат и сохранять полезное локально. Контент сайта не становится системной инструкцией и не может автоматически расширить полномочия агента.

## Work / проекты

Work mode хранит проекты и задачи отдельно от обычных чатов и использует те же Core/memory/file boundaries. Отказ дополнительного Work/voice/file/computer/online модуля не должен закрывать базовый локальный чат.

## Обновления

`AuroraUpdate` использует GitHub Releases как stable distribution channel, но доверяет пакету только после проверки предусмотренной цепочки подписи/хэша.

### Windows

Новые Windows-пакеты обновляются полным ZIP replacement через отдельный helper:

- package SHA-256 verification;
- staging;
- backup предыдущего приложения;
- switch;
- post-update health marker;
- rollback при неуспешном запуске.

### Историческая V1.2.0.0

У V1.2 был дефект trust bootstrap: updater ожидал embedded `release_public.pub`, которого в исторической сборке не было. Поэтому безопасно заставить уже установленную V1.2 принять новый signed manifest задним числом невозможно.

Поддерживаемый путь Windows:

**V1.0–V1.2 → one-time V1.2-to-V1.3 Repair/Bridge → V1.3+ signed update chain.**

Repair path покрыт реальным CI: исторический fixture устанавливается, пользовательский sentinel сохраняется, V1.3 ставится поверх, bridge marker проверяется, новая программа запускается.

### Android

Android update сохраняет package `com.aurorafox.ai` и требует одну постоянную signing identity. Старые CI/test APK, созданные с одноразовым keystore, не могут быть обновлены поверх APK с другим certificate — это системное правило Android.

### Production signing

Private update key и Android release keystore **никогда не коммитятся**. Они один раз создаются/сохраняются владельцем и передаются GitHub Actions через secrets. Публичные identity pins могут храниться в репозитории.

One-time owner setup:

```powershell
./build/setup_release_signing.ps1
```

До инициализации постоянной identity нельзя подменять production channel временными ключами.

Подробный актуальный статус и следующий шаг всегда находятся в `docs/PROJECT_MASTER_LOG.md`.

## Локальная сборка

Windows:

```powershell
./build/build_windows.ps1
```

Android production path:

```powershell
./build/build_android.ps1
```

Сборочные helpers проверяют bundled Core contract; release Android build дополнительно требует постоянную signing identity.

## CI / проверка

Основные workflow включают:

- Core / Voice CI — Python contracts + Godot 4.7.1 import/smokes;
- Windows Package CI — подготовка bundled Core, сборка, embedded-Core checks, installer, V1.2 repair, silent install/launch;
- Android APK Artifact — native build, bundled app packaging, APK validation, install/launch on Android 35 emulator;
- Core Bootstrap E2E;
- Agent Sync CI;
- специализированные API/File Intelligence/memory/promotion tests.

На проверенном V1.3 baseline `69f54cc06720a1300b7e7ac1d997ceb1c1b3c2e9` основные Windows, Android, Core/Voice, Agent Sync и Core Bootstrap workflows завершены успешно. Новые изменения после baseline считаются проверенными только после соответствующего нового CI.

## Правило продолжения разработки

Если один Chat/Work/Codex закончил или прервал работу, следующий исполнитель не начинает аудит с нуля и не повторяет ту же задачу. Он:

1. читает `AGENTS.md`;
2. читает `docs/PROJECT_MASTER_LOG.md`;
3. получает latest `main`;
4. проверяет текущие ACTIVE claims и CI;
5. продолжает первый незавершённый пункт либо берёт независимую задачу;
6. записывает результат обратно в тот же master-log.
