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
6. Делать изменения крупным законченным этапом, затем запускать относящиеся к нему тесты/CI.
7. После этапа обновить **этот же файл**: commit SHA, что сделано, инженерную причину решения, проверки/run IDs, известные ограничения, следующий шаг и какие файлы освобождены.
8. При завершении своей работы оставить точный продолжительный план так, чтобы другой Chat/Work/Codex мог сразу продолжить без восстановления контекста из разговора.

Нельзя создавать отдельный `CHAT_LOG`, `WORK_LOG`, `CODEX_LOG`, `WORK_COORDINATION` или другой конкурирующий журнал. Частые записи всех исполнителей делаются здесь. Разрешены технические документы подсистем (`update/README.md`, `voice/README.md`, design docs и т. п.), но они не заменяют этот журнал и не используются как параллельная очередь работ.

### Что писать в журнал

Записывается **краткое инженерное обоснование**: проблема, выбранное решение, почему оно безопаснее/надёжнее альтернатив, фактические тесты и оставшиеся риски. Не требуется и не должна сохраняться скрытая внутренняя цепочка рассуждений модели; для продолжения работы достаточно проверяемого инженерного rationale.

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

AuroraFox — существующий локальный AI-помощник на Godot 4.7.1 для Windows и Android. Проект **не создаётся заново**.

### 1.1. ЖЁСТКИЙ АРХИТЕКТУРНЫЙ ИНВАРИАНТ: AuroraFox зависит и полагается только на себя

Это требование владельца проекта имеет приоритет при выборе архитектуры.

**AuroraFox НЕ является оболочкой над Ollama, OpenAI API, облачной LLM или другим AI-клиентом. Основой интеллекта является только собственный AuroraFox Core, его собственные локальные данные, память, знания, агенты и инструменты.**

Обязательное конечное поведение:

- собственная локальная модель/runtime AuroraFox являются **primary, product default и источником базового мышления**;
- базовый чат, рассуждение, планирование, критика, принятие решений, генерация текста/кода, использование локальной памяти и Core Knowledge должны работать при полном отсутствии Ollama, внешних AI API, облачных моделей и удалённого inference;
- AuroraFox должна сама накапливать опыт в собственной памяти/Core Knowledge/skills/errors/checkpoints; удалённый сервис не может быть единственным местом, где хранится или существует «обучение»;
- AuroraFox должна сама учиться на разрешённых пользователем локальных данных и на результатах разрешённого исследования интернета, классифицировать/проверять материал и сохранять полезное локально;
- AuroraFox должна сама искать решение задачи: определить нехватку информации, сформировать план исследования, при разрешении использовать интернет/сайты, проверить найденное своим Core и применить результат через собственные инструменты;
- интернет и сайты — это **источники информации и поверхности действий**, а не внешний мозг. Без интернета должны перестать работать только задачи, которым реально нужен интернет; локальное мышление и локальные функции продолжают работать;
- AuroraFox должна сама выполнять разрешённые действия через AgentCore/Computer Agent/file/workspace/sandbox tooling и фактически проверять результат;
- AuroraFox должна сама говорить и слушать через локальный baseline STT/TTS/voice runtime. Внешний speech service допустим только как необязательное улучшение и не должен быть единственным способом базового голоса;
- AuroraFox должна сама читать поддерживаемые документы/данные локальными парсерами/runtime. Для форматов, где локальная поддержка ещё неполна, это считается задачей развития, а не основанием сделать облачный AI обязательным;
- AuroraFox должна сама генерировать ответы, код, планы, структуры и другие поддерживаемые результаты своим Core. Внешняя модель может дать дополнительную идею/вариант, но не обязана присутствовать;
- AuroraFox должна сама улучшать собственные знания, навыки и разрешённые части Core через существующий controlled self-improvement pipeline: candidate → sandbox/baseline → tests/regression/safety → independent verification → promotion;
- самостоятельность **не означает** право отключать safety gates: master stop, rollback, allowlists, независимый verifier, updater trust, privacy и sandbox остаются вне права произвольного самоизменения;
- Ollama, сторонние модели и внешние AI/API **разрешены только как optional compatibility/enhancement/tool**. Они выключаемы/удаляемы без потери базовой работоспособности AuroraFox;
- внешний AI никогда не должен становиться судьёй качества self-improvement, единственным генератором candidate, обязательным planner/researcher или единственным источником ответа;
- результаты сайтов, документов, внешних моделей и загруженного кода являются **untrusted input/data**. Они не получают системные полномочия, не могут отменить правила и не исполняются автоматически;
- если новая функция требует внешнего AI для normal path, её нужно либо переделать с локальным baseline, либо оставить как optional enhancement. Делать её новой основой Core запрещено.

**Критерий регрессии:** если удалить/выключить Ollama, внешние AI/API и отключить интернет, AuroraFox должна по-прежнему запускать собственный Core, отвечать локально, использовать локальную память/знания, планировать локальные задачи, работать с поддерживаемыми локальными файлами и сохранять/оценивать собственный опыт. Потеря этих возможностей считается архитектурным дефектом.

### 1.2. Остальные обязательные требования продукта

- пользователь устанавливает AuroraFox и сразу получает рабочий AI-чат;
- нормальному пользователю не требуется устанавливать Ollama, отдельный LLM-клиент, Python для AI-инференса, вручную выбирать/скачивать GGUF или видеть мастер выбора модели;
- собственный **AuroraFox Core** и необходимые веса поставляются вместе с приложением;
- Windows и Android используют local inference path;
- локальные память, Core Knowledge, навыки, ошибки, checkpoints и история работают без внешнего AI-провайдера;
- пользователь может загружать базы/документы с произвольным именем и поддерживаемыми форматами; структура определяется импортёром, данные не получают системных полномочий;
- большие базы, включая порядка 150+ MB, обрабатываются потоково там, где это необходимо;
- голос, файлы, Computer Agent, Work/projects, API и остальные подсистемы не должны ломать основной чат при своей недоступности;
- обновления Windows/Android должны быть безопасными, проверять целостность и поддерживать rollback там, где платформа позволяет;
- историческая V1.2.0.0 должна иметь понятный восстановительный путь к V1.3, после V1.3 должна использоваться постоянная подписанная цепочка обновлений;
- все изменения, решения, проверки и дальнейший план ведутся только в этом master-журнале.

## 2. Текущий baseline

- Repository: `Treninem/AI`
- Branch: `main`
- Версия приложения: **V1.3.0.0**
- Android `versionCode`: **100005**
- Godot: **4.7.1**
- Проверенный продуктовый baseline до master/self-reliance hardening: `69f54cc06720a1300b7e7ac1d997ceb1c1b3c2e9`
- Commit message baseline: `core: wait for concurrent bundled Core warmup instead of failing chat`

### Exact-head CI для `69f54cc...`

- Windows Package CI `35056954657` — **success**: bundled Windows Core, build, embedded runtime/Core checks, exported executable smoke, installer, V1.2→V1.3 bridge, silent install/launch, portable/repair artifacts.
- Android APK Artifact `35056954676` — **success**: build, sign/validate, install/launch Android 35, artifact upload.
- Core / Voice CI `35056954746` — **success**.
- Agent Sync CI `35056954716` — **success**.
- Core Bootstrap E2E `35056954771` — **success**.
- Evolution Progress `35056954686` — **success**; scheduled `35058694903` — success.

### Exact-head artifacts

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

### External compatibility isolation

После self-reliance hardening `scripts/ai_client.gd` больше не называет стороннюю `qwen3:8b` product `DEFAULT_MODEL`.

- сторонняя модель называется только `LEGACY_OLLAMA_DEFAULT_MODEL`;
- endpoint называется `LEGACY_OLLAMA_DEFAULT_URL`/compatibility URL;
- `model_source` как двусмысленный product marker удалён;
- `runtime_info()` явно отдаёт `self_primary=true`, `external_ai_required=false`, `operational_without_ollama=true`;
- `allow_ollama_fallback=false` остаётся default;
- local Core выполняется раньше любого compatibility path.

**Инженерная причина:** даже выключенный fallback не должен семантически выглядеть как «главная модель по умолчанию». Код должен отражать тот же trust/dependency contract, что и ТЗ.

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

## 5. Память / локальное обучение

Реализован локальный semantic/vector retrieval без обязательного сетевого runtime и без Ollama. Локальная память и knowledge context подмешиваются к собственному Core отдельно от системных полномочий. Сохранён lexical fallback.

Требование дальнейшего развития: обучение должно расширять **собственные** memory/knowledge/skills/evaluation datasets AuroraFox и оставаться доступным офлайн. Веб-исследование может добавлять проверенные сведения, но не переносит «мозг» системы во внешний сервис.

Персональная память не используется как материал для публичной передачи между чужими клиентами.

## 6. Controlled self-improvement / evolution

Реализовано и должно сохраняться:

- mutation/tournament flow;
- allowlisted Core targets;
- protected updater/API/addons/runtime/models/workflows;
- проверка public functions/signals/base contracts;
- запрет увеличения опасных process/network primitives в candidate;
- ограничение source growth;
- baseline и candidate проходят одинаковые детерминированные Godot suites;
- compile-only недостаточен;
- comparative review — дополнительный сигнал, но не замена детерминированным gates;
- независимый verifier/promotion workflow;
- клиент не получает GitHub/release signing authority;
- candidate submission имеет отдельные scopes и не выполняет присланный код автоматически;
- user master stop / rollback не входят в область автономного переписывания.

Следующий архитектурный критерий: candidate generation/review не должен требовать внешнюю AI-модель. Внешняя модель допустима только как дополнительный advisory input; собственный Core должен иметь локальный путь proposal/evaluation.

## 7. Обновления и историческая V1.2

### Исправленный контракт

Старое предположение «V1.0+ всегда может напрямую обновиться» признано неверным после проверки исторического V1.2 source. Актуальная граница:

- **Windows V1.0–V1.2:** one-time Repair/Bridge к V1.3 из-за отсутствовавшего в V1.2 embedded trust root;
- **Windows V1.3+:** подписанная автоматическая цепочка после инициализации постоянного RSA trust root;
- **Android:** in-place update требует того же package ID и signing certificate. Исторические CI/test APK с одноразовыми keystore нельзя задним числом перевести в другую signing lineage.

### Windows Repair

Repair реализован и реально проверен CI: исторический V1.2 fixture, пользовательский sentinel, V1.3 поверх, сохранение sentinel, `previous=1.2.0.0 → current=1.3.0.0`, запуск новой программы.

Ранее проверенный repair binary: `AuroraFox-V1.2-to-V1.3.0.0-Repair-Windows.exe`, SHA-256 `e2c2b0aa690a0a96f636e069e8fbc5fcd6379b22c37ce886b3feed8f4d9f70e2`.

### Production signing — owner-controlled boundary

Production signed update trust root/Android release identity должны оставаться owner-controlled. Приватные signing keys запрещено коммитить или отдавать клиентскому AI. После owner bootstrap постоянная identity должна сохраняться для всех следующих релизов.

Это намеренное исключение из «сама всё делает»: приложение не должно само владеть секретом, которым оно подтверждает собственную подлинность.

## 8. Голос / Computer Agent / Work / API / Internet

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

## 9. Консолидированная история важных этапов

### 2026-09-15 — local-first migration

- собственный Aurora Core стал primary;
- Ollama перестал быть обязательным;
- local model failure получил quarantine/backoff и local failover;
- Core Knowledge расширен на много форматов и большие базы;
- source registry и transaction rollback;
- local semantic memory;
- self-improvement получил baseline/candidate benchmark gates;
- candidate promotion отделён от release authority;
- Windows/API/Android packaging усилен реальными smoke tests;
- Android offline PDF extraction добавлен в native path.

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
- Windows/Android CI проверяют реальные большие пакеты и runtime launch.

### 2026-09-16 — единый журнал и self-reliance hardening

- создан единственный `docs/PROJECT_MASTER_LOG.md`;
- создан root `AGENTS.md` с обязательным read/claim/write протоколом;
- старые `DEVELOPMENT_LOG.md`, `WORK_COORDINATION.md`, `workstreams/CHAT_MAIN.md` удалены после консолидации;
- CI contract запрещает возврат нескольких параллельных project journals;
- README приведён к V1.3/bundled Core;
- self-reliance закреплён в `AGENTS.md`, README, master ТЗ и regression test;
- `AIClient` переименовал внешний default в `LEGACY_OLLAMA_DEFAULT_*` и явно сообщает `self_primary=true`, `external_ai_required=false`.

Commits этого self-reliance этапа на момент записи:
- `e0a99c859f5f6b5c6cb3fc8d013e0f91fdac0fdc` — hard architecture invariant в `AGENTS.md`;
- `aa906e808ebc9bf8db56807cfdadf01ad572a07d` — code semantics/self-primary runtime info;
- `14ff37ee67bccd4b2752fdfd3d2d60694f5c7e0b` — regression contract;
- `63d721a16fe14f08eb08641786d40020e81373eb` — README self-primary contract.

## 10. Что уже соответствует самостоятельности / что ещё довести

### Уже реализовано и проверялось

- bundled local Core model/runtime Windows/Android;
- отсутствие обязательного Ollama;
- local memory/Core Knowledge;
- local large-file knowledge import;
- local semantic retrieval;
- local STT/TTS baseline;
- AgentCore/planning/tooling architecture;
- sandbox/workspace/snapshot/rollback;
- controlled self-improvement gates;
- Computer Agent и file/tool bridges;
- offline basic operation path.

### Нужно продолжить до полного выполнения ТЗ

1. Усилить **полностью локальный self-improvement proposal/evaluation path**, чтобы candidate generation/review не имели обязательной внешней AI-зависимости.
2. Усилить autonomous research loop: сама определяет информационный пробел → безопасно исследует разрешённые сайты → provenance/dedupe/quality → локально сохраняет знания → использует их без внешнего AI.
3. Довести local document understanding для image-only/scanned PDF через локальный OCR, не делая cloud OCR обязательным.
4. Расширять локальные speech/voice quality paths без превращения внешнего TTS/STT в requirement.
5. Добавить explicit offline/self-reliance integration smoke: при недоступных внешних AI/Ollama/network Core chat/memory/planning/local tools остаются рабочими.
6. Продолжать измеримое улучшение качества собственной модели/памяти/планирования через benchmark/evaluation datasets и controlled promotion.
7. Реальные device regressions Windows/Android.

## 11. Известные внешние границы, которые не являются зависимостью интеллекта

1. Production release signing identities создаются/хранятся владельцем; клиентскому Core нельзя давать private release-signing authority.
2. Конкретная online-задача естественно требует сети; отсутствие сети должно ломать только эту задачу, не само мышление.
3. Android historical test APK с другим certificate нельзя обновить поверх другой signing lineage — системное правило Android.
4. Quality конкретной bundled модели требует дальнейших benchmarks; сам факт bundled inference уже проверен, но это не означает, что качество нельзя/не нужно улучшать.

## 12. План продолжения по приоритету

### P0 — self-reliance contract

- [DONE] один master-журнал и root `AGENTS.md`;
- [DONE] удалены конкурирующие project journals;
- [DONE] README V1.3/bundled Core;
- [DONE] standalone Core regression test;
- [DONE] внешний legacy model больше не называется product `DEFAULT_MODEL`;
- [IN PROGRESS] получить полностью green exact-head CI после hardening и исправить любое падение;
- [NEXT] offline/self-reliance integration smoke без external AI/Ollama/network.

### P0 — самостоятельное обучение/улучшение

- [NEXT] проверить текущий `core_improvement_pipeline` на скрытую обязательность внешней модели при candidate generation/comparative review;
- [NEXT] дать собственному Core локальный proposal/review path и детерминированные benchmark gates как authority;
- [NEXT] autonomous research должен использовать web как data source, а не remote reasoning dependency.

### P1 — release readiness

- после owner signing bootstrap проверить readiness;
- выпустить signed V1.3 release существующим workflow;
- проверить V1.3→следующая версия end-to-end signed update.

### P2 — качество

- device tests;
- voice latency/quality;
- Work/projects UX;
- local OCR image-only PDF;
- performance/memory large knowledge;
- benchmark-driven улучшение Core intelligence.

## 13. Активные работы и занятые файлы

### CLAIM `CHAT_MAIN-2026-09-16-MASTER-CORE`

- Статус: **ACTIVE**
- Started from HEAD: `69f54cc06720a1300b7e7ac1d997ceb1c1b3c2e9`
- Последний integrated parallel baseline перед self-reliance edits: `54985afc87f5ffdf7d2d39c93442b0bf2d22d06a`.
- Режим: Chat
- Цель: единый журнал + жёсткий self-primary/self-reliant Core contract + CI защита.
- Временно занято:
  - `docs/PROJECT_MASTER_LOG.md`
  - `AGENTS.md`
  - `README.md`
  - `scripts/ai_client.gd`
  - `tests/test_standalone_core_contract.py`
  - `.github/workflows/voice-ci.yml` только для project/self-reliance contracts.
- Параллельные updater/autonomy изменения, появившиеся в `main`, не перетираются и должны интегрироваться через latest HEAD.

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

## 14. Формат записи завершённого этапа

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

Последнее правило: **если разговор/Work/Codex остановился, следующий исполнитель не восстанавливает план по догадкам — он читает этот файл, актуальный Git HEAD и CI, затем продолжает с первого незавершённого пункта, не повторяя уже выполненную параллельную работу.**
