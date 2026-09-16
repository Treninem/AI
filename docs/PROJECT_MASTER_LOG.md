# AuroraFox — PROJECT MASTER LOG

> **ЕДИНЫЙ КАНОНИЧЕСКИЙ ЖУРНАЛ ПРОЕКТА.**
>
> Этот файл обязателен для чтения и обновления всеми режимами разработки: обычный ChatGPT-чат, Work, Codex, локальные/серверные агенты и любой другой процесс, который меняет `Treninem/AI`.
>
> Других параллельных журналов разработки/координации быть не должно. Репозиторий и результаты CI являются окончательным техническим источником истины; этот файл является единым источником координации, решений, выполненного ТЗ и плана продолжения.

## 0. Обязательный протокол для Chat / Work / Codex / агентов

Перед **любой** записью в репозиторий исполнитель обязан:

1. Получить актуальный HEAD ветки `main` и не работать по старой копии.
2. Полностью прочитать этот `docs/PROJECT_MASTER_LOG.md`.
3. Проверить раздел **Активные работы и занятые файлы**.
4. До изменения кода записать в этот файл свою рабочую заявку: кто/режим, цель, подсистема, предполагаемые файлы и исходный HEAD.
5. Если нужный файл уже занят другим активным исполнителем, не перетирать его. Нужно либо взять другую независимую задачу, либо сначала интегрировать уже сделанные изменения с актуального `main`.
6. Не делать параллельно ту же задачу, которую уже выполняет другой Chat/Work/Codex/Agent. Перед каждым крупным этапом повторно сверять свежий HEAD и новые commits.
7. Делать изменения крупным законченным этапом, затем запускать относящиеся к нему тесты/CI.
8. После этапа обновить **этот же файл**: commit SHA, что сделано, краткое инженерное обоснование, проверки/run IDs, известные ограничения, следующий шаг и какие файлы освобождены.
9. При завершении своей работы оставить точный продолжительный план так, чтобы другой Chat/Work/Codex мог сразу продолжить без восстановления контекста из разговора.

Нельзя создавать отдельный `CHAT_LOG`, `WORK_LOG`, `CODEX_LOG`, `WORK_COORDINATION`, `DEVELOPMENT_LOG` или другой конкурирующий журнал. Частые записи всех исполнителей делаются здесь. Разрешены технические документы подсистем (`update/README.md`, `voice/README.md`, design docs и т. п.), но они не заменяют этот журнал и не используются как параллельная очередь работ.

### Что писать в журнал

Записывается **краткое проверяемое инженерное обоснование**: проблема, выбранное решение, почему оно безопаснее/надёжнее альтернатив, фактические тесты и оставшиеся риски. Не требуется и не должна сохраняться скрытая внутренняя цепочка рассуждений модели; для продолжения работы достаточно инженерного rationale, исходных требований, commits, тестов и точного плана.

### Неприкосновенные границы

Ни Chat, ни Work, ни Codex, ни автономное улучшение не должны ослаблять без отдельного явного решения владельца и полноценной миграции:

- пользовательский master stop / выключение автономии;
- snapshot/rollback и восстановление предыдущих версий;
- allowlist целей самоизменения Core;
- независимую проверку candidate перед продвижением;
- подпись обновлений и закреплённую trust identity;
- Android signing continuity;
- разделение Core candidate submission и release authority;
- локальную приватность персональной памяти;
- запрет автоматического исполнения кода/инструкций из импортированных документов;
- sandbox/permission boundaries Computer Agent и исполняемых расширений;
- **самостоятельность AuroraFox Core и запрет превращать внешний AI/model/service в обязательную основу интеллекта.**

## 1. Главная цель / единое ТЗ

AuroraFox — существующий локальный AI-помощник на Godot 4.7.1 для Windows и Android. Проект **не создаётся заново**. Новые этапы интегрируются в существующую архитектуру, память, Core Knowledge, автономию, controlled self-improvement, updater, Windows/Android clients, API, tests и release pipeline.

### 1.1. ЖЁСТКИЙ АРХИТЕКТУРНЫЙ ИНВАРИАНТ: AuroraFox зависит и полагается только на себя

Это требование владельца проекта имеет приоритет при выборе архитектуры.

**AuroraFox НЕ является оболочкой над Ollama, OpenAI API, облачной LLM или другим AI-клиентом. Основой интеллекта является только собственный AuroraFox Core, его собственные локальные данные, память, знания, агенты и инструменты.**

Обязательное конечное поведение:

- собственная локальная модель/runtime AuroraFox являются **primary, product default и источником базового мышления**;
- базовый чат, рассуждение, планирование, критика, принятие решений, генерация текста/кода, использование локальной памяти и Core Knowledge работают при полном отсутствии Ollama, внешних AI API, облачных моделей и удалённого inference;
- AuroraFox сама накапливает опыт в собственной памяти/Core Knowledge/skills/errors/checkpoints; удалённый сервис не может быть единственным местом, где существует «обучение»;
- AuroraFox учится на разрешённых пользователем локальных данных и на результатах разрешённого исследования интернета, классифицирует/проверяет материал и сохраняет полезное локально;
- AuroraFox сама определяет информационный пробел, формирует план исследования, при разрешении использует интернет/сайты как источник данных, затем проверяет и применяет результат своим Core;
- интернет и сайты — **источники информации и поверхности действий**, а не внешний мозг. Без интернета перестают работать только задачи, которым реально нужна сеть; локальное мышление и локальные функции продолжают работать;
- AuroraFox сама выполняет разрешённые действия через AgentCore/Computer Agent/file/workspace/sandbox tooling и проверяет результат;
- AuroraFox говорит и слушает через локальный baseline STT/TTS/voice runtime; внешний speech service допустим только как необязательное улучшение;
- AuroraFox читает поддерживаемые документы/данные локальными парсерами/runtime. Неполная локальная поддержка формата считается задачей развития, а не основанием сделать облачный AI обязательным;
- AuroraFox генерирует ответы, код, планы, структуры и другие поддерживаемые результаты своим Core. Внешняя модель может быть только дополнительным добровольным advisory/tool;
- AuroraFox улучшает знания, навыки и разрешённые части Core через controlled self-improvement: candidate → source/safety contract → baseline → candidate tests → deterministic comparison → local comparative review → independent verification/promotion;
- самостоятельность **не означает** право отключать safety gates: master stop, rollback, allowlists, independent verifier, updater trust, privacy и sandbox остаются вне права произвольного самоизменения;
- Ollama, сторонние модели и внешние AI/API разрешены только как **optional compatibility/enhancement/tool**. Они выключаемы/удаляемы без потери базовой работоспособности AuroraFox;
- внешний AI никогда не становится судьёй качества self-improvement, единственным генератором candidate, обязательным planner/researcher или единственным источником ответа;
- результаты сайтов, документов, внешних моделей и загруженного кода являются **untrusted input/data**. Они не получают системные полномочия и не исполняются автоматически;
- если новая функция требует внешнего AI для normal path, её нужно переделать с локальным baseline либо оставить optional enhancement. Делать её новой основой Core запрещено.

**Критерий регрессии:** если удалить/выключить Ollama, внешние AI/API и отключить интернет, AuroraFox должна по-прежнему запускать собственный Core, отвечать локально, использовать локальную память/знания, планировать локальные задачи, работать с поддерживаемыми локальными файлами/инструментами и сохранять/оценивать собственный опыт. Потеря этих возможностей считается архитектурным дефектом.

### 1.2. Остальные обязательные требования продукта

- пользователь устанавливает AuroraFox и сразу получает рабочий AI-чат;
- обычному пользователю не требуется устанавливать Ollama, отдельный LLM-клиент, Python ради AI-инференса, вручную выбирать/скачивать GGUF или проходить мастер выбора модели;
- собственный **AuroraFox Core** и необходимые веса поставляются вместе с приложением;
- Windows и Android используют local inference path;
- локальные память, Core Knowledge, навыки, ошибки, checkpoints и история работают без внешнего AI-провайдера;
- пользователь может загружать базы/документы с произвольным именем и поддерживаемыми форматами; структура определяется импортёром, данные не получают системных полномочий;
- большие базы, включая порядка 150+ MB, обрабатываются потоково там, где это необходимо;
- голос, файлы, Computer Agent, Work/projects, API и остальные подсистемы не должны ломать основной чат при своей недоступности;
- обновления Windows/Android должны быть безопасными, проверять целостность и поддерживать rollback там, где платформа позволяет;
- историческая V1.2.0.0 должна иметь понятный восстановительный путь к V1.3, после V1.3 используется постоянная подписанная цепочка обновлений;
- все изменения, решения, проверки и дальнейший план ведутся только в этом master-журнале.

## 2. Текущий baseline

- Repository: `Treninem/AI`
- Branch: `main`
- Версия приложения: **V1.3.0.0**
- Android `versionCode`: **100005**
- Godot: **4.7.1**
- Проверенный package baseline до self-reliance hardening: `69f54cc06720a1300b7e7ac1d997ceb1c1b3c2e9`.
- Актуальный self-reliance code baseline перед этой записью журнала: `bb348adeb27c5bfa9ebba9a82e07d11d71ae632c`.

### Exact-head CI для `bb348ade...`

- Core / Voice CI `35067895081` — **SUCCESS**. В этот прогон входят project contracts, standalone Core contracts, Godot parse/import, self-reliance isolation smoke и полный offline autonomy smoke (chat + planning + local tool + local memory), а также остальные Core/voice/knowledge/update smoke tests.
- Agent Sync CI `35067895155` — **SUCCESS**.
- Evolution Progress `35067895168` — **SUCCESS**.
- Android APK Artifact `35067895031` на момент записи ещё выполнялся; его статус нельзя считать результатом до завершения.

### Ранее проверенные package artifacts

Для baseline `69f54cc...` были зелёными Windows Package CI `35056954657`, Android APK Artifact `35056954676`, Core/Voice `35056954746`, Agent Sync `35056954716`, Core Bootstrap E2E `35056954771`, Evolution `35056954686`.

- Windows artifact `10432490547`, `AuroraFox-Windows`, archive ~3.94 GB, digest `sha256:13d476ded52a4bd52ab348c1d2d726c539fe5236048f9a1bd30f0af87ba85c45`.
- Android artifact `10431601276`, `AuroraFox-V1.3.0.0-Android-Test`, archive ~1.57 GB, digest `sha256:4bc7d8b93def057432a52f7d03bdbf5e530d4510f9b9964a5ddda9efa3b00deb`.

## 3. Самостоятельное AuroraFox Core — текущее состояние

### Bundled Core weights/runtime

`AuroraBundledCoreModel` является продуктовым источником внутреннего Core:

- bundled resource: `res://models/aurorafox-core.gguf`;
- Windows packaged path: `core_runtime/engine/aurorafox-core.gguf`;
- expected bytes: `1282439264`;
- expected SHA-256: `d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5`.

Windows использует проверенный файл из установленного приложения и bundled `llama-server.exe`. Android копирует встроенный asset в private storage через temp-файл, проверяет размер, GGUF magic и SHA-256 и только затем активирует его.

`DesktopLocalRuntime` запускает internal Core только на `127.0.0.1:8766`, alias `AuroraFox-Core`. Первый чат присоединяется к background warmup вместо ошибки `already starting`.

Android использует собственный native Godot plugin/runtime с llama.cpp path. Android Ollama fallback не использует.

`models/install_models.ps1` больше не предлагает обычному пользователю скачать/импортировать стороннюю модель: bootstrap сообщает `bundled_core_required=true`, `external_ai_required=false`, а веса принадлежат packaged AuroraFox Core.

### Normal intelligence path и compatibility isolation

- `AIClient.chat()` вызывает только публичный `AuroraCoreRuntime.chat_local_only()`;
- normal product chat, AgentCore, CognitionLayer и controlled self-improvement используют именно `AIClient.chat()`;
- `chat_with_compatibility()` является отдельным явным API для legacy/developer compatibility;
- `LEGACY_OLLAMA_DEFAULT_MODEL`/`LEGACY_OLLAMA_DEFAULT_URL` не являются product default;
- `runtime_info()` явно сообщает `self_primary=true`, `external_ai_required=false`, `normal_chat_external_fallback=false`, `operational_without_ollama=true`;
- даже включённый compatibility switch не даёт normal chat права перейти на внешний AI;
- Android compatibility fallback запрещён.

**Инженерная причина:** optional compatibility может существовать, но не должна быть скрытой резервной «мозговой» зависимостью. Разделение API делает нарушение видимым и тестируемым.

## 4. Core Knowledge / файлы / большие базы

Реализовано:

- импорт произвольных имён файлов;
- JSON, JSONL, NDJSON, CSV/TSV, text/code/data;
- встроенные DOCX, ODT, RTF, EPUB extractors;
- rich-document File Intelligence path для PDF/XLS/XLSX/ODS/PPTX и т. п.;
- Android offline PDF text-layer extraction;
- большие JSONL/CSV/text — streaming;
- большие monolithic JSON — dependency-free streaming reader;
- поиск по knowledge JSONL без обязательной загрузки всей базы в память;
- source registry: fingerprint, aliases, revisions;
- byte-identical renamed files не дублируют знания;
- source-scoped transaction rollback восстанавливает предыдущую ревизию после частично неудачного импорта;
- импортированный код/инструкции остаются untrusted knowledge и не получают право исполнения.

**Причина архитектуры:** память процесса должна зависеть от размера текущей записи/чанка, а не всей базы; повторный импорт и rollback не должны копировать сотни мегабайт без необходимости.

Оставшийся качественный пробел: image-only/scanned PDF должен получить полноценный локальный OCR baseline без обязательного cloud OCR.

## 5. Память / локальное обучение

Реализован локальный semantic/vector retrieval без обязательного сетевого runtime и без Ollama. Semantic backend сообщает:

- provider `aurorafox_local_vector`;
- `network_required=false`;
- `external_runtime_required=false`;
- `ollama_required=false`;
- lexical fallback остаётся локальным.

Локальная память и knowledge context подмешиваются к собственному Core отдельно от системных полномочий. Персональная память не используется как материал для публичной передачи между чужими клиентами.

Новый offline integration smoke проверяет не только декларации, но и фактическую связку AgentCore → local planning → local tool → local memory при включённом legacy compatibility switch; внешний compatibility runtime при этом не вызывается.

## 6. Controlled self-improvement / evolution

Реализовано и закреплено тестами:

- mutation/tournament flow;
- allowlisted Core targets;
- protected updater/API/addons/runtime/models/workflows;
- проверка public functions/signals/base contracts;
- запрет увеличения опасных process/network primitives в candidate;
- ограничение source growth;
- baseline и candidate проходят одинаковые детерминированные Godot suites;
- compile-only недостаточен;
- deterministic comparison обязан пройти **до** qualitative comparative review;
- candidate generation (`_propose`) и comparative review используют normal `AIClient.chat()`, то есть собственный local-only AuroraFox Core;
- `chat_with_compatibility()` в pipeline отсутствует;
- локальный comparative reviewer может дополнительно отклонить candidate, но не может разрешить проваленные source/baseline/candidate/no-regression gates;
- independent verifier/promotion workflow сохраняется;
- клиент не получает GitHub/release signing authority;
- candidate submission имеет отдельные scopes и не выполняет присланный код автоматически;
- user master stop / rollback не входят в область автономного переписывания.

**P0-аудит обязательности внешней модели закрыт:** текущий controlled self-improvement proposal/evaluation normal path не требует внешнего AI.

## 7. Autonomous research / интернет как данные

Текущий контракт `LearningCurator`:

- веб-результат импортируется через собственный local Core Knowledge;
- материал помечается `untrusted_external=true`;
- сохраняются provenance/source URL и hash;
- данные маркируются `[UNTRUSTED_EXTERNAL_RESEARCH_DATA]`;
- найденный текст не получает системных полномочий и не является remote reasoning authority.

**Закрыто на уровне архитектурного контракта:** web — источник данных, а не внешний мозг.

**Следующий качественный этап:** усилить loop «обнаружить пробел → выбрать несколько разрешённых источников → provenance/dedupe → quality/evidence scoring → противоречия → локальное сохранение → повторное offline использование». Это улучшение качества исследования, а не исправление зависимости Core.

## 8. Обновления и историческая V1.2

### Исправленный контракт

Старое предположение «V1.0+ всегда может напрямую обновиться» признано неверным после проверки исторического V1.2 source. Актуальная граница:

- **Windows V1.0–V1.2:** one-time Repair/Bridge к V1.3 из-за отсутствовавшего в V1.2 embedded trust root;
- **Windows V1.3+:** подписанная автоматическая цепочка после инициализации постоянного RSA trust root;
- **Android:** in-place update требует того же package ID и signing certificate. Исторические CI/test APK с одноразовыми keystore нельзя задним числом перевести в другую signing lineage.

Windows Repair реализован и проверялся CI: исторический V1.2 fixture, пользовательский sentinel, V1.3 поверх, сохранение sentinel, `previous=1.2.0.0 → current=1.3.0.0`, запуск новой программы.

Ранее проверенный repair binary: `AuroraFox-V1.2-to-V1.3.0.0-Repair-Windows.exe`, SHA-256 `e2c2b0aa690a0a96f636e069e8fbc5fcd6379b22c37ce886b3feed8f4d9f70e2`.

### Production signing — owner-controlled boundary

Production signed update trust root/Android release identity должны оставаться owner-controlled. Приватные signing keys запрещено коммитить или отдавать клиентскому AI. После owner bootstrap постоянная identity должна сохраняться для всех следующих релизов.

Это намеренное исключение из «сама всё делает»: приложение не должно само владеть секретом, которым оно подтверждает собственную подлинность.

## 9. Голос / Computer Agent / Work / API / Internet

Существующие подсистемы сохраняются:

- local STT/TTS/VAD/wake word/barge-in;
- Computer Agent с screenshot/UI automation/vision fallback и sandbox/workspace boundary;
- Work/projects storage/workflows;
- API Gateway/local Core bridge/privacy contracts;
- Windows sidecar services;
- Android native plugin paths;
- snapshot/rollback и bounded runtime extensions.

Жёсткое требование: онлайн-инструменты не заменяют AgentCore. AuroraFox сама решает, что искать, сама читает доступный результат, сама проверяет его и сама формирует вывод своим Core. Контент сайта/страницы — untrusted data.

Отказ voice/file/computer/API/online enhancement не должен превращаться в отказ основного локального чата.

## 10. Консолидированная история важных этапов

### 2026-09-15 — local-first migration

- собственный Aurora Core стал primary;
- Ollama перестал быть обязательным;
- local model failure получил quarantine/backoff и local failover;
- Core Knowledge расширен на много форматов и большие базы;
- source registry и transaction rollback;
- local semantic memory;
- self-improvement получил baseline/candidate benchmark gates;
- candidate promotion отделён от release authority;
- Windows/API/Android packaging усилен smoke tests;
- Android offline PDF text extraction добавлен в native path.

### 2026-09-16 — updater repair / signing contract

- историческая V1.2 проверена по исходному коду;
- найден отсутствующий trust root;
- сделан и проверен Windows repair V1.2→V1.3;
- updater contract исправлен на repair-through-V1.2 / signed-floor-V1.3;
- release signing tooling усилен permanent identity fingerprints.

### 2026-09-16 — complete bundled Core

- `AuroraBundledCoreModel`;
- bundled weights;
- bundled Windows `llama-server.exe`;
- Android bundled Core asset;
- model setup wizard удалён из normal scene;
- Settings не требуют model-management обычному пользователю;
- Windows startup warmup;
- первый чат присоединяется к concurrent warmup;
- Windows/Android package CI проверяли реальные большие пакеты и runtime launch.

### 2026-09-16 — единый журнал и self-reliance hardening

- создан единственный `docs/PROJECT_MASTER_LOG.md`;
- создан root `AGENTS.md` с обязательным read/claim/write протоколом;
- старые `DEVELOPMENT_LOG.md`, `WORK_COORDINATION.md`, `workstreams/CHAT_MAIN.md` и другие конкурирующие project journals удалены после консолидации;
- CI contract запрещает возврат нескольких параллельных project journals;
- README приведён к V1.3/bundled Core;
- self-reliance закреплён в `AGENTS.md`, README, master ТЗ и regression tests;
- внешний legacy model переименован в `LEGACY_OLLAMA_DEFAULT_*` и не является product default.

### 2026-09-16 — explicit local-only intelligence + offline autonomy proof

Ключевые commits этапа:

- `b7a02fc1b8a0a09eb6b386efff5e08abf555a333` — публичный local-only inference API;
- `6f4c0cdd403aac28ceb766e5cc7ea685e632cf97` — primary chat переведён на public local-only Core API;
- `85aff8f07b4f5ebc44e3bab07364b558755c2e80` — regression contract для local-only Core и untrusted web learning;
- `7a7a99b90b2eaa903dbefb0957a384d582a6ea72` — runtime self-reliance isolation smoke;
- `8db4bda97694a157e3409afe01c9dc1a0802cdd4` — smoke подключён в CI;
- `fc497667929083b3c0de0700e3ede9c54e005af7` — исправлен синтаксический дефект compatibility HTTP error dictionary, найденный CI;
- `1869d35f2f0a9b4cf6d2ed05d80e11505ded509b` — bootstrap E2E разделяет normal Core и explicit compatibility outage;
- `d054d18cda268a17c6c9971ebf0d478694215154` — bootstrap больше не предлагает пользователю стороннюю модель;
- `d6e1165ca146e43bf8a0ec7d02cd956e4e3a4639` — regression contract закрепляет local self-improvement и deterministic benchmark authority;
- `3691868c1a77998a82f30b732d20b8514423c0e0` — полный offline autonomy smoke: chat/planning/local tool/local memory;
- `ae78e0123448c26fd165fd749ed6bd92abfe1e68` — offline autonomy smoke включён в Core CI;
- `bb348adeb27c5bfa9ebba9a82e07d11d71ae632c` — static ordering test исправлен так, чтобы проверять реальный execution order pipeline, а не расположение helper-функций в файле.

Отдельно: run `35067858611` был красным только из-за слишком грубой статической проверки порядка helper definitions; Godot `offline_autonomy_smoke.gd` в этом же run был **SUCCESS**. После исправления test design exact-head Core/Voice run `35067895081` стал **SUCCESS**.

## 11. Что уже соответствует самостоятельности / что ещё довести

### Уже реализовано и защищено regression tests

- bundled local Core model/runtime Windows/Android;
- normal `AIClient.chat()` local-only;
- AgentCore/planning/self-improvement идут через собственный Core;
- external compatibility вынесена в отдельный явный API;
- отсутствие обязательного Ollama/remote AI;
- local memory/Core Knowledge;
- local large-file knowledge import;
- local semantic retrieval;
- local STT/TTS baseline;
- sandbox/workspace/snapshot/rollback;
- controlled self-improvement deterministic gates;
- self-improvement proposal/review не требуют external AI;
- web research сохраняется как untrusted local data с provenance;
- Computer Agent и file/tool bridges;
- explicit offline integration smoke для chat + planning + local tool + local memory;
- package bootstrap не просит normal user выбирать/скачивать внешнюю модель.

### Оставшиеся задачи развития

1. Усилить autonomous research quality loop: информационный пробел → несколько источников → provenance/dedupe → evidence/quality → противоречия → локальное знание → offline reuse.
2. Довести local document understanding для image-only/scanned PDF через локальный OCR, не делая cloud OCR обязательным.
3. Расширять локальные speech/voice quality/latency paths без превращения внешнего TTS/STT в requirement.
4. Продолжать измеримое улучшение качества собственной модели/памяти/планирования через benchmark/evaluation datasets и controlled promotion.
5. Реальные device regressions Windows/Android на release candidates.
6. После owner signing bootstrap проверить production release readiness и V1.3→следующая версия signed update end-to-end.

Эти задачи не означают, что Core сейчас зависит от стороннего AI: это дальнейшее качество, форматы, device coverage и production identity.

## 12. Известные внешние границы, которые не являются зависимостью интеллекта

1. Production release signing identities создаются/хранятся владельцем; клиентскому Core нельзя давать private release-signing authority.
2. Конкретная online-задача естественно требует сети; отсутствие сети должно ломать только эту задачу, не само мышление.
3. Android historical test APK с другим certificate нельзя обновить поверх другой signing lineage — системное правило Android.
4. Quality конкретной bundled модели требует дальнейших benchmarks; сам факт bundled local inference и independence уже защищены, но это не означает, что качество нельзя улучшать.

## 13. План продолжения по приоритету

### P0 — self-reliance contract

- [DONE] один master-журнал и root `AGENTS.md`;
- [DONE] удалены конкурирующие project journals;
- [DONE] README V1.3/bundled Core;
- [DONE] standalone Core regression test;
- [DONE] внешний legacy model больше не называется product `DEFAULT_MODEL`;
- [DONE] normal `chat()` изолирован от compatibility API;
- [DONE] full offline integration smoke без external AI/Ollama/network dependency для Core path;
- [DONE] green exact-head Core/Voice CI `35067895081` на `bb348ade...`;
- [DONE] Agent Sync CI `35067895155` на `bb348ade...`.

### P0 — самостоятельное обучение/улучшение

- [DONE] проверен `core_improvement_pipeline` на скрытую обязательность внешней модели;
- [DONE] proposal/review идут через собственный local-only Core path;
- [DONE] deterministic baseline/candidate/no-regression gates являются authority до qualitative review;
- [DONE] regression test защищает порядок execution gates;
- [DONE] autonomous research использует web как untrusted data source, а не remote reasoning dependency;
- [NEXT] усилить evidence quality/dedupe/contradiction handling autonomous research loop.

### P1 — release readiness

- [WAITING OWNER BOUNDARY] production update key + Android release signing identity не должны генерироваться/храниться клиентским Core;
- после owner signing bootstrap проверить readiness;
- выпустить signed V1.3 release существующим workflow;
- проверить V1.3→следующая версия end-to-end signed update.

### P2 — качество

- real device tests;
- voice latency/quality;
- Work/projects UX;
- local OCR image-only PDF;
- performance/memory large knowledge;
- benchmark-driven улучшение Core intelligence.

## 14. Активные работы и занятые файлы

На момент этой записи **активных CLAIM от завершённого Chat self-reliance этапа нет**. Следующий исполнитель обязан сначала получить свежий HEAD: другой режим мог начать работу после этой записи.

### CLAIM `CHAT_MAIN-2026-09-16-MASTER-CORE`

- Статус: **DONE**
- Started from HEAD: `69f54cc06720a1300b7e7ac1d997ceb1c1b3c2e9`
- Integrated through code HEAD: `bb348adeb27c5bfa9ebba9a82e07d11d71ae632c`
- Режим: Chat + интеграция совместимых параллельных commits с main.
- Цель: единый журнал + жёсткий self-primary/self-reliant Core contract + explicit compatibility isolation + CI защита + offline integration proof + self-improvement audit.
- Результат: цель этапа выполнена; занятые пути освобождены.
- Проверки: Core/Voice `35067895081` SUCCESS; Agent Sync `35067895155` SUCCESS; Evolution `35067895168` SUCCESS; Android `35067895031` ещё выполнялся в момент записи.
- Следующий шаг: новый исполнитель делает отдельный CLAIM на autonomous research quality loop либо другой незанятый пункт из раздела 13.

### Шаблон новой заявки

```text
### CLAIM <MODE>-<DATE>-<SHORT-ID>
- Статус: ACTIVE
- Started from HEAD: <sha>
- Режим: Chat | Work | Codex | Agent
- Цель: <одна связная задача>
- Файлы/подсистема: <paths>
- Не пересекается с: <active claims>
```

При завершении изменить `ACTIVE` на `DONE`, добавить commits/tests/results/next step и освободить пути.

## 15. Запись завершённого этапа — 2026-09-16 — Chat — self-reliance hardening

- Base HEAD: `69f54cc06720a1300b7e7ac1d997ceb1c1b3c2e9`.
- Integrated code HEAD: `bb348adeb27c5bfa9ebba9a82e07d11d71ae632c`.
- Сделано: normal inference отделён от compatibility; full offline autonomy smoke добавлен; self-improvement local proposal/review и deterministic authority закреплены regression contract; model bootstrap не требует стороннего AI/model setup; web learning остаётся untrusted local knowledge.
- Инженерная причина: самостоятельность должна проверяться не только флагами, но и реальным normal execution path. Поэтому compatibility вынесена в explicit API, а CI запускает связный offline AgentCore сценарий и статические dependency contracts.
- Проверки: Core/Voice `35067895081` SUCCESS; Agent Sync `35067895155` SUCCESS; Evolution `35067895168` SUCCESS. Предыдущий run `35067858611` выявил дефект самой статической проверки; Godot offline smoke там прошёл, test design исправлен commit `bb348ade...`.
- Ограничения/риски: качество bundled модели продолжает требовать benchmark-driven улучшения; scanned/image-only PDF нуждается в local OCR; production signing остаётся owner-controlled; Android current artifact run на момент этой записи ещё не завершился.
- Следующий шаг: autonomous research quality/evidence loop, затем local OCR/device/release quality по разделу 13.
- Освобождённые файлы: `docs/PROJECT_MASTER_LOG.md`, `AGENTS.md`, `README.md`, `scripts/ai_client.gd`, `tests/test_standalone_core_contract.py`, `tests/self_reliance_smoke.gd`, `tests/offline_autonomy_smoke.gd`, `.github/workflows/voice-ci.yml`.

## 16. Формат записи завершённого этапа

```text
### <UTC/local date-time> — <mode> — <stage>
- Base HEAD: ...
- Commits: ...
- Сделано: ...
- Инженерная причина: ...
- Проверки: workflow/run IDs, тесты, artifacts/hashes
- Ограничения/риски: ...
- Следующий шаг: ...
- Освобождённые файлы: ...
```

---

Последнее правило: **если разговор/Work/Codex остановился, следующий исполнитель не восстанавливает план по догадкам — он читает этот файл, актуальный Git HEAD и CI, затем создаёт новый CLAIM и продолжает с первого незавершённого пункта, не повторяя уже выполненную параллельную работу.**
