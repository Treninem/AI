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
- sandbox/permission boundaries Computer Agent и исполняемых расширений.

## 1. Главная цель / единое ТЗ

AuroraFox — существующий локальный AI-помощник на Godot 4.7.1 для Windows и Android. Проект **не создаётся заново**. Требуемое конечное поведение:

- пользователь устанавливает AuroraFox и сразу получает рабочий AI-чат;
- нормальному пользователю не требуется устанавливать Ollama, отдельный LLM-клиент, Python для AI-инференса, вручную выбирать/скачивать GGUF или видеть мастер выбора модели;
- собственный **AuroraFox Core** и необходимые веса поставляются вместе с приложением;
- Ollama допустим только как явно включаемый compatibility fallback и никогда не определяет работоспособность продукта;
- Windows и Android используют локальный inference path;
- локальные память, Core Knowledge, навыки, ошибки, checkpoints и история работают без внешнего AI-провайдера;
- пользователь может загружать базы/документы с произвольным именем и поддерживаемыми форматами; структура определяется импортёром, данные не получают системных полномочий;
- большие базы, включая порядка 150+ MB, обрабатываются потоково там, где это необходимо;
- голос, файлы, Computer Agent, Work/projects, API и остальные подсистемы не должны ломать основной чат при своей недоступности;
- self-improvement остаётся контролируемым: candidate → sandbox/baseline tests → regression/safety gates → независимая проверка → только затем promotion; владелец сохраняет stop/rollback;
- обновления Windows/Android должны быть безопасными, проверять целостность и поддерживать rollback там, где платформа позволяет;
- историческая V1.2.0.0 должна иметь понятный восстановительный путь к V1.3, после V1.3 должна использоваться постоянная подписанная цепочка обновлений;
- все изменения, решения, проверки и дальнейший план ведутся только в этом master-журнале.

## 2. Текущий baseline

- Repository: `Treninem/AI`
- Branch: `main`
- Версия приложения: **V1.3.0.0**
- Android `versionCode`: **100005**
- Godot: **4.7.1**
- Проверенный продуктовый baseline перед созданием master-журнала: `69f54cc06720a1300b7e7ac1d997ceb1c1b3c2e9`
- Commit message baseline: `core: wait for concurrent bundled Core warmup instead of failing chat`

### Exact-head CI для `69f54cc...`

- Windows Package CI `35056954657` — **success**.
  - подготовка полного bundled Windows Core;
  - сборка Windows;
  - проверка встроенных runtime assets + Core;
  - smoke exported executable;
  - Inno Setup installer;
  - реальный V1.2→V1.3 bridge smoke;
  - silent install + launch установленного приложения;
  - portable ZIP / repair installer / hashes;
  - artifact upload;
  - `publish-v12-repair` — success, постоянный repair release опубликован/обновлён.
- Android APK Artifact `35056954676` — **success**.
  - build;
  - test-sign/validation;
  - установка и запуск на Android 35 emulator;
  - artifact upload.
- Core / Voice CI `35056954746` — **success**.
- Agent Sync CI `35056954716` — **success**.
- Core Bootstrap E2E `35056954771` — **success**.
- Evolution Progress `35056954686` — **success**; scheduled `35058694903` — success.

### Exact-head artifacts

- Windows artifact `10432490547`, `AuroraFox-Windows`, workflow artifact archive ~3.94 GB, digest `sha256:13d476ded52a4bd52ab348c1d2d726c539fe5236048f9a1bd30f0af87ba85c45`.
- Android artifact `10431601276`, `AuroraFox-V1.3.0.0-Android-Test`, workflow artifact archive ~1.57 GB, digest `sha256:4bc7d8b93def057432a52f7d03bdbf5e530d4510f9b9964a5ddda9efa3b00deb`.

## 3. Самостоятельное AuroraFox Core — текущее состояние

### Bundled Core weights

`AuroraBundledCoreModel` является продуктовым источником внутреннего Core:

- bundled resource: `res://models/aurorafox-core.gguf`;
- Windows packaged path: `core_runtime/engine/aurorafox-core.gguf`;
- expected bytes: `1282439264`;
- expected SHA-256: `d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5`.

Windows использует проверенный файл из каталога установленного приложения. Android копирует встроенный asset в private storage через temp-файл, проверяет размер, GGUF magic и SHA-256 и только затем активирует его.

**Причина:** приложение должно быть готово после установки, а повреждённая/неполная модель не должна тихо приниматься как рабочая.

### Windows inference

`DesktopLocalRuntime` запускает поставляемый `llama-server.exe` локально на `127.0.0.1:8766`, alias `AuroraFox-Core`. Первый чат присоединяется к уже идущему background warmup вместо ошибки `already starting`. Последний baseline commit `69f54cc...` именно устранил этот race.

**Причина:** warmup должен ускорять первый ответ, а не создавать отдельную точку отказа при одновременном сообщении пользователя.

### Android inference

Android использует собственный native Godot plugin/runtime с llama.cpp path. Android никогда не использует Ollama fallback. APK CI ставит и запускает фактический большой APK на Android 35 emulator.

### Ollama

Ollama остаётся только compatibility adapter:

- `allow_ollama_fallback` по умолчанию `false`;
- local Core всегда пробуется первым;
- Android compatibility path отключён;
- `AIClient.is_available()` оценивает собственный Core, а не наличие Ollama;
- `operational_without_ollama=true`.

Это не считается внешней зависимостью основного продукта. Удалять compatibility adapter необязательно, пока он остаётся выключенным по умолчанию и не влияет на нормальный запуск.

## 4. Core Knowledge / файлы / большие базы

Реализовано:

- импорт произвольных имён файлов;
- JSON, JSONL, NDJSON, CSV/TSV, text/code/data и дополнительные форматы;
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

**Причина архитектуры:** память процесса должна зависеть от размера текущей записи/чанка, а не всей базы; при этом повторный импорт и rollback не должны копировать сотни мегабайт без необходимости.

## 5. Память

Реализован локальный semantic/vector retrieval без обязательного сетевого runtime и без Ollama. Локальная память и knowledge контекст подмешиваются к Core отдельно от системных полномочий.

Сохранён lexical fallback на случай отсутствия/перестроения векторного индекса. Персональная память не используется как материал для публичной передачи между чужими клиентами.

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

**Причина:** самоулучшение должно улучшать измеримый результат, но не иметь возможности самоотключить проверяющий контур.

## 7. Обновления и историческая V1.2

### Исправленный контракт

Старое предположение «V1.0+ всегда может напрямую обновиться» признано неверным после проверки исторического V1.2 source. Актуальная граница:

- **Windows V1.0–V1.2:** one-time Repair/Bridge к V1.3 из-за отсутствовавшего в V1.2 embedded trust root;
- **Windows V1.3+:** подписанная автоматическая цепочка после инициализации постоянного RSA trust root;
- **Android:** in-place update требует того же package ID и того же signing certificate. Исторические CI/test APK с одноразовыми keystore нельзя задним числом перевести в другую signing lineage.

### Что было найдено в V1.2

V1.2 уже запрашивала `update.json`, `update.sig` и ожидала `res://update/release_public.pub`, но соответствующего public key в историческом commit не было. Публикация unsigned release не используется как обход — это ослабило бы supply-chain безопасность.

### Windows Repair

Repair реализован и реально проверен CI:

- устанавливается исторический V1.2 fixture с тем же AppId;
- создаётся sentinel в `%APPDATA%/Godot/app_userdata/AuroraFox`;
- V1.3 ставится поверх;
- sentinel сохраняется;
- bridge marker фиксирует `previous=1.2.0.0` и `current=1.3.0.0`;
- новая программа запускается.

Ранее проверенный repair binary:
`AuroraFox-V1.2-to-V1.3.0.0-Repair-Windows.exe`, SHA-256 `e2c2b0aa690a0a96f636e069e8fbc5fcd6379b22c37ce886b3feed8f4d9f70e2`.

Текущий Windows workflow дополнительно имеет успешный `publish-v12-repair` job.

### Production signing — внешний owner-controlled boundary

На момент создания master-журнала в `main` отсутствуют:

- `update/release_public.pub`;
- `update/release_identity.json`.

Следовательно, production signed update trust root ещё не инициализирован владельцем. Код и readiness tooling уже предусмотрены, но **нельзя** подменять постоянную identity временным приватным ключом в репозитории.

Один раз на доверенном ПК владельца необходимо выполнить `build/setup_release_signing.ps1`, безопасно сохранить приватный RSA key и Android keystore вне Git, записать GitHub Actions secrets и commit-нуть только публичные pins (`release_public.pub`, `release_identity.json`). После этого один и тот же signing identity должен сохраняться для будущих релизов.

Это единственный нормальный внешний шаг, который намеренно не может быть «самостоятельно» выполнен пользовательским AI-клиентом: приложение не должно само владеть ключом, которым оно подтверждает собственные обновления.

## 8. Голос / Computer Agent / Work / API

Существующие подсистемы сохраняются:

- local STT/TTS/VAD/wake word/barge-in;
- Computer Agent с screenshot/UI automation/vision fallback и sandbox/workspace boundary;
- Work/projects storage/workflows;
- API Gateway, local Core bridge, privacy contracts;
- Windows sidecar services;
- Android native plugin paths;
- snapshot/rollback и bounded runtime extensions.

Правило продукта: отказ второстепенного voice/file/computer/API модуля не должен превращаться в отказ основного локального чата.

## 9. Важные выполненные инженерные этапы (консолидированная история)

### 2026-09-15 — local-first migration

- собственный Aurora Core стал primary;
- Ollama перестал быть обязательным;
- local model failure получает quarantine/backoff и local failover;
- Core Knowledge расширен на много форматов и большие базы;
- source registry и transaction rollback;
- local semantic memory;
- self-improvement получил baseline/candidate benchmark gates;
- candidate promotion отделён от release authority;
- Windows/API/Android packaging усилен реальными smoke tests;
- Android offline PDF extraction добавлен в native path.

### 2026-09-16 — updater repair и permanent identity contract

- историческая V1.2 проверена по исходному коду;
- найден отсутствующий trust root;
- сделан и проверен Windows repair V1.2→V1.3;
- updater contract исправлен на repair-through-V1.2 / signed-floor-V1.3;
- CI перестал утверждать ложный legacy direct-update;
- release signing tooling усилен permanent identity fingerprints;
- production Android build должен соответствовать закреплённому signing certificate.

### 2026-09-16 — complete bundled Core

Параллельная разработка после updater repair довела обычную установку до bundled Core:

- `AuroraBundledCoreModel`;
- встроенные weights;
- bundled Windows `llama-server.exe`;
- Android bundled Core asset;
- model setup wizard удалён из normal user scene;
- Settings не требуют model-management для обычного пользователя;
- Windows startup warmup;
- первый чат присоединяется к concurrent warmup;
- Windows и Android CI проверяют реальные большие пакеты и runtime launch.

Exact-head `69f54cc...` прошёл все основные product workflows, перечисленные в разделе 2.

## 10. Известные ограничения / то, что нельзя честно назвать завершённым без внешнего владельца

1. **Production signing initialization:** RSA update trust root + постоянный Android keystore должны быть один раз созданы/сохранены владельцем и записаны в GitHub Secrets. Приватные ключи запрещено коммитить.
2. **Android historical test APK:** если установлен старый V1.2 test APK с ephemeral CI certificate, Android не разрешит обновить его APK с другим certificate поверх. Это правило Android, а не ошибка V1.3 кода.
3. Реальное поведение качества конкретной встроенной модели зависит от её возможностей; наличие bundled inference проверено, но CI launch smoke не доказывает качество ответов на все пользовательские задачи.
4. Production device matrix всегда можно расширять: разные Windows CPU/GPU и Android устройства требуют дальнейших device regressions, хотя базовый Windows install/launch и Android 35 emulator уже зелёные.

## 11. План продолжения по приоритету

### P0 — единый журнал и защита от параллельных конфликтов

- [IN PROGRESS] создать этот единый master-журнал;
- [IN PROGRESS] создать root `AGENTS.md`, который заставляет Chat/Work/Codex читать/писать только сюда;
- [IN PROGRESS] удалить старые `docs/DEVELOPMENT_LOG.md`, `docs/WORK_COORDINATION.md`, `docs/workstreams/CHAT_MAIN.md` после переноса актуального содержания;
- [PLANNED] добавить CI contract, запрещающий возврат нескольких журналов и проверяющий ссылки из README/AGENTS.

### P0 — самостоятельный Core contract

- [PLANNED] добавить отдельный regression test, который проверяет bundled model/engine path, отсутствие normal model wizard, local-first default и `allow_ollama_fallback=false`;
- [PLANNED] подключить его к Core/Voice CI;
- [PLANNED] исправлять любой красный exact-head CI до green.

### P1 — документация продукта

- [PLANNED] исправить устаревший README (`0.4.0`, `Ollama/local LLM`) на V1.3.0.0 и bundled AuroraFox Core;
- [PLANNED] README должен указывать этот master-log как обязательную точку входа для разработчиков/агентов.

### P1 — release readiness

- после owner signing bootstrap: проверить `build/bridge_release_readiness.ps1`;
- выпустить signed V1.3 release через существующий workflow;
- проверить `update.json` + `update.sig` + Windows ZIP + production-signed Android APK;
- проверить V1.3→следующая версия обновлением, чтобы trust chain была подтверждена end-to-end.

### P2 — дальнейшее качество

- реальные device tests на дополнительных Windows/Android устройствах;
- voice latency/quality;
- Work/projects UX;
- File Intelligence/OCR для image-only PDF;
- performance profiling memory/large knowledge;
- улучшение Core intelligence только через существующие candidate benchmark/promotion gates.

## 12. Активные работы и занятые файлы

### CLAIM `CHAT_MAIN-2026-09-16-MASTER-CORE`

- Статус: **ACTIVE**
- Started from HEAD: `69f54cc06720a1300b7e7ac1d997ceb1c1b3c2e9`
- Режим: Chat
- Цель: объединить журналы, закрепить обязательную координацию всех режимов, исправить README и добавить CI contracts самостоятельного Core.
- Временно занято:
  - `docs/PROJECT_MASTER_LOG.md`
  - `AGENTS.md`
  - `README.md`
  - старые journal files только для миграции/удаления;
  - новый master-journal/standalone-core test;
  - `.github/workflows/voice-ci.yml` только для подключения этих contracts.
- Остальные подсистемы можно разрабатывать параллельно только после чтения этого файла и добавления отдельного CLAIM ниже.

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

## 13. Формат записи завершённого этапа

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
