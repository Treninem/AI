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

Нельзя создавать отдельный `CHAT_LOG`, `WORK_LOG`, `CODEX_LOG`, `WORK_COORDINATION`, `DEVELOPMENT_LOG` или другой конкурирующий журнал. Частые записи всех исполнителей делаются здесь. Разрешены технические документы подсистем, но они не заменяют этот журнал и не используются как параллельная очередь работ.

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

**AuroraFox НЕ является оболочкой над Ollama, OpenAI API, облачной LLM или другим AI-клиентом. Основой интеллекта является только собственный AuroraFox Core, его собственные локальные данные, память, знания, агенты и инструменты.**

Обязательное поведение:

- собственная локальная модель/runtime AuroraFox — primary и product default;
- базовый чат, рассуждение, планирование, критика, решения, генерация текста/кода, локальная память и Core Knowledge работают без Ollama, внешних AI API, облачных моделей и remote inference;
- AuroraFox сохраняет опыт в собственной памяти/Core Knowledge/skills/errors/checkpoints;
- AuroraFox может исследовать разрешённые интернет-источники, но интернет является источником **данных**, а не удалённым мозгом;
- до сохранения автономно найденного web-контента в долговременное знание должен существовать локальный quality/provenance gate; collector не должен обходить curator;
- локальные пользовательские документы не должны автоматически становиться автономно собранным Core knowledge без явного knowledge/import flow;
- AuroraFox выполняет разрешённые действия через AgentCore/Computer Agent/file/workspace/sandbox tooling и проверяет результат;
- голос имеет local baseline STT/TTS;
- документы разбираются local baseline там, где формат поддержан; cloud OCR/AI не становится обязательным;
- controlled self-improvement: candidate → source/safety contract → baseline → candidate tests → deterministic comparison → local comparative review → independent verification/promotion;
- safety gates, master stop, rollback, updater trust, privacy и sandbox не могут быть отключены самоизменением;
- Ollama/сторонние модели/AI API — только optional compatibility/enhancement/tool;
- результаты сайтов, документов, внешних моделей и кода являются untrusted input/data и не получают системные полномочия.

**Критерий регрессии:** если удалить/выключить Ollama, внешние AI/API и отключить интернет, AuroraFox должна запускать собственный Core, отвечать локально, использовать локальную память/знания, планировать локальные задачи и использовать поддерживаемые локальные инструменты.

### 1.2. Остальные обязательные требования

- установка даёт рабочий AI-чат без отдельного LLM-клиента;
- собственный AuroraFox Core и необходимые веса поставляются с приложением;
- Windows и Android используют local inference;
- локальные память/знания/skills/checkpoints не зависят от внешнего AI;
- пользователь может загружать поддерживаемые базы и документы произвольного имени;
- большие базы обрабатываются потоково;
- voice/files/Computer Agent/Work/API не должны ломать основной chat при своей недоступности;
- updates проверяют целостность и поддерживают безопасный migration/rollback contract;
- V1.2→V1.3 имеет repair bridge; V1.3+ использует постоянную подписанную цепочку;
- все решения/проверки/планы ведутся только здесь.

## 2. Текущий baseline

- Repository: `Treninem/AI`
- Branch: `main`
- Версия: **V1.3.0.0**
- Android `versionCode`: **100005**
- Godot: **4.7.1**
- Package baseline: `69f54cc06720a1300b7e7ac1d997ceb1c1b3c2e9`.
- Self-reliance code baseline: `bb348adeb27c5bfa9ebba9a82e07d11d71ae632c`.
- Journal consolidation commit: `932f2d5da41923b7e4277aefb794fc4f2c50c058`.

Проверки:

- Core/Voice `35067895081` на `bb348ade...` — SUCCESS;
- Agent Sync `35067895155` — SUCCESS;
- Evolution `35067895168` — SUCCESS;
- journal-only Core/Voice `35068214336` на `932f2d5d...` — SUCCESS;
- Android `35067895031` от предыдущего code-head выполнялся при последней проверке и не считается завершённым результатом до final status.

Ранее на package baseline были зелёными Windows Package `35056954657`, Android APK `35056954676`, Core/Voice `35056954746`, Agent Sync `35056954716`, Core Bootstrap `35056954771`, Evolution `35056954686`.

## 3. Самостоятельное AuroraFox Core

`AuroraBundledCoreModel`:

- `res://models/aurorafox-core.gguf`;
- Windows `core_runtime/engine/aurorafox-core.gguf`;
- bytes `1282439264`;
- SHA-256 `d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5`.

Windows использует packaged `llama-server.exe` и verified bundled weights. Android копирует bundled GGUF в private storage через temp + size/magic/SHA validation и использует native llama.cpp plugin path.

Normal path:

- `AIClient.chat()` → `AuroraCoreRuntime.chat_local_only()`;
- AgentCore/CognitionLayer/self-improvement используют normal `AIClient.chat()`;
- `chat_with_compatibility()` — отдельный explicit legacy/developer API;
- `runtime_info`: `self_primary=true`, `external_ai_required=false`, `normal_chat_external_fallback=false`, `operational_without_ollama=true`;
- включённый compatibility switch не меняет normal path;
- Android external/Ollama fallback отсутствует;
- bootstrap больше не предлагает normal user выбирать/скачивать внешнюю модель.

## 4. Core Knowledge / файлы / большие базы

Реализованы arbitrary filenames; JSON/JSONL/CSV/text/code/data; DOCX/ODT/RTF/EPUB; rich document path для PDF/XLS/XLSX/ODS/PPTX; Android PDF text layer; streaming large JSONL/CSV/text; monolithic JSON streaming; source registry/fingerprint/aliases/revisions; duplicate suppression; source transaction rollback; untrusted import boundary.

Оставшийся пробел: image-only/scanned PDF нуждается в полноценном local OCR baseline.

## 5. Память / локальное обучение

Local semantic/vector retrieval:

- provider `aurorafox_local_vector`;
- `network_required=false`;
- `external_runtime_required=false`;
- `ollama_required=false`;
- local lexical fallback.

Offline integration smoke проверяет AgentCore → local planning → local tool → local memory при включённом legacy compatibility switch и запрещает уход в compatibility runtime.

## 6. Controlled self-improvement

Реализованы mutation/tournament; allowlisted targets; protected updater/API/runtime/models/workflows; public functions/signals/base contracts; dangerous primitive limits; source growth limit; deterministic baseline/candidate suites; no-regression comparison до qualitative review; local Core proposal/review; independent verification/promotion; разделение candidate submission и release authority; защищённые master stop/rollback.

P0-аудит внешней модели закрыт: normal self-improvement proposal/evaluation не требует external AI.

## 7. Autonomous research — текущий аудит

### Уже правильно

`LearningCurator`:

- оценивает source/metadata/title/summary;
- имеет minimum promotion score;
- fingerprint/seen dedupe;
- отклоняет `local_documents` из automatic Core Knowledge flow;
- импортирует promoted web item через `AIClient.import_knowledge_text()`;
- ставит `scope=core_knowledge`, `kind=research_knowledge`, `untrusted_external=true`, `source_url`, `quality_score`, timestamp;
- knowledge text содержит `[UNTRUSTED_EXTERNAL_RESEARCH_DATA]`.

### Найденный дефект 2026-09-16

`ResearchCollector.collect()` сейчас до события `research_completed` вызывает `_learn(item)` для **всех** собранных items и пишет их в `MemoryStore`. Это происходит **до** curator quality/dedupe gate. Следствия:

- низкокачественный web result может попасть в долговременную память, даже если curator потом его отвергнет;
- `local_documents` автоматически записываются в memory как autonomous research, хотя curator специально запрещает их automatic promotion в Core Knowledge;
- существуют две конкурирующие линии learning (`ResearchCollector._learn` и `LearningCurator`), поэтому quality gate не является authority.

**Выбранное исправление:** collector должен только собирать/нормализовать/provenance/log items. Любая долговременная automatic learning promotion должна проходить через curator. Для local documents автоматический promotion должен оставаться запрещённым; явный user Knowledge Base flow остаётся отдельным.

После этого этапа добавить regression smoke, который доказывает: rejected/duplicate/local-document items не появляются в autonomous long-term memory/Core Knowledge, promoted web item получает provenance/hash/quality metadata.

## 8. Update/signing

Windows V1.0–V1.2: one-time Repair/Bridge к V1.3. Windows V1.3+: signed automatic chain. Android in-place update требует стабильные package ID + certificate.

Production release signing identities — owner-controlled boundary. Private signing keys запрещено коммитить/выдавать клиентскому Core. Это намеренная граница доверия, а не external AI dependency.

## 9. Голос / Computer Agent / Work / API

Сохраняются local STT/TTS/VAD/wake/barge-in; Computer Agent screenshot/UI automation/vision fallback + sandbox; Work/projects; API bridge/privacy; Windows sidecars; Android native plugin paths; snapshot/rollback/runtime extensions.

Online tools не заменяют AgentCore. Отказ voice/files/computer/API/online enhancement не должен ломать основной local chat.

## 10. Консолидированная история

### 2026-09-15 — local-first migration

Aurora Core primary; Ollama optional; local model quarantine/failover; расширенный Knowledge; streaming; registry/rollback; local semantic memory; self-improvement benchmarks; promotion separated from release authority; Android local document paths.

### 2026-09-16 — updater/signing

Историческая V1.2 проверена; обнаружен отсутствующий trust root; сделан Windows V1.2→V1.3 repair; contract исправлен на repair-through-V1.2 / signed-floor-V1.3; permanent signing identity tooling усилен.

### 2026-09-16 — bundled Core

Bundled Core weights + Windows engine + Android asset/native path; normal model setup wizard удалён; settings не требуют model management; warmup/race fixed; package CI проверял большие artifacts.

### 2026-09-16 — единый журнал

Создан `PROJECT_MASTER_LOG.md`; root `AGENTS.md` требует read/claim/write; конкурирующие journals удалены; CI запрещает их возврат; README приведён к V1.3/bundled Core.

### 2026-09-16 — self-reliance hardening

Ключевые commits:

- `b7a02fc1...` public local-only inference API;
- `6f4c0cdd...` primary chat local-only;
- `85aff8f0...` local-only + untrusted web contracts;
- `7a7a99b9...` self-reliance smoke;
- `8db4bda9...` CI smoke;
- `fc497667...` parser regression fix;
- `1869d35f...` bootstrap normal vs explicit compatibility;
- `d054d18c...` no user external model setup;
- `d6e1165c...` self-improvement benchmark authority contract;
- `3691868c...` full offline chat/planning/local-tool/memory smoke;
- `ae78e012...` offline smoke in CI;
- `bb348ade...` correct execution-order contract;
- `932f2d5d...` consolidated current master journal.

## 11. Уже соответствует самостоятельности / оставшиеся задачи

### DONE

- bundled local Core Windows/Android;
- normal chat/AgentCore/planning/self-improvement local-only;
- compatibility isolated;
- no mandatory Ollama/remote AI;
- local memory/Knowledge/semantic retrieval;
- large-file import;
- local voice baseline;
- sandbox/snapshot/rollback;
- deterministic controlled self-improvement;
- web marked untrusted/provenance at curator stage;
- offline integration smoke;
- package bootstrap without external model setup.

### TODO

1. [ACTIVE] Research collector → curator single authoritative promotion path; stronger provenance/dedupe/evidence handling.
2. Local OCR for image-only/scanned PDF.
3. Voice quality/latency improvements.
4. Benchmark-driven Core intelligence/memory/planning quality.
5. Real Windows/Android device regressions.
6. Owner signing bootstrap + production release end-to-end verification.

## 12. Внешние границы, не являющиеся зависимостью интеллекта

- owner-controlled production signing secrets;
- сеть только для задач, реально требующих сеть;
- Android signing lineage enforced by OS;
- качество конкретной bundled модели требует дальнейших benchmarks.

## 13. План продолжения по приоритету

### P0 — self-reliance

- [DONE] single master journal + AGENTS;
- [DONE] local-only normal path;
- [DONE] offline integration smoke;
- [DONE] exact-head Core/Voice green;
- [DONE] self-improvement local proposal/review + deterministic authority.

### P0 — autonomous research quality

- [ACTIVE] убрать обход curator через `ResearchCollector._learn`;
- [ACTIVE] single promotion authority = `LearningCurator`;
- [ACTIVE] усилить content fingerprint/canonical URL/provenance/evidence metadata;
- [ACTIVE] regression smoke для rejected/duplicate/local-document vs promoted web item;
- [NEXT] contradiction/corroboration model для нескольких независимых источников.

### P1 — release readiness

- [WAITING OWNER BOUNDARY] production update key + Android release identity;
- после bootstrap owner identity проверить signed release/update end-to-end.

### P2 — качество

- local OCR;
- device tests;
- voice quality;
- Work UX;
- large knowledge performance;
- Core benchmarks.

## 14. Активные работы и занятые файлы

### CLAIM `CHAT_MAIN-2026-09-16-RESEARCH-QUALITY`

- Статус: **ACTIVE**
- Started from HEAD: `932f2d5da41923b7e4277aefb794fc4f2c50c058`
- Режим: Chat
- Цель: сделать `LearningCurator` единственным authority для автоматического долговременного web-learning; collector только собирает/логирует данные; закрыть automatic local-document leakage и добавить regression tests.
- Файлы/подсистема: `agent/research_collector.gd`, `agent/learning_curator.gd`, относящиеся `tests/*research*`/`tests/autonomy_learning_smoke.gd`, `.github/workflows/voice-ci.yml` только если нужен запуск нового smoke, `docs/PROJECT_MASTER_LOG.md`.
- Не пересекается с завершённым `CHAT_MAIN-2026-09-16-MASTER-CORE`; перед каждой записью сверять свежий HEAD и не перетирать новые параллельные изменения.
- Инженерная причина: сейчас `ResearchCollector._learn()` пишет данные в memory до curator gate, поэтому rejected content уже оказывается выученным. Gate должен быть единственной точкой automatic promotion.
- Следующий шаг: внести минимальный совместимый refactor, затем deterministic GDScript smoke и Core CI.

### CLAIM `CHAT-2026-09-16-VOICE-QUALITY`

- Статус: **ACTIVE**
- Started from HEAD: `4a013aa31142443192ab5bcd52cf1e00950e5467`
- Режим: Chat
- Цель: улучшить естественность, разборчивость и задержку локальной русской озвучки AuroraFox без превращения внешнего TTS/STT в обязательную зависимость.
- Файлы/подсистема: `voice/python/tts_engine.py`, `voice/python/processor.py`, `voice/config/voice_config.json`, `voice/config/emotions.json` при необходимости, `tests/test_voice_text.py`, `tests/test_voice_configs.py`, `tests/test_xtts_contract.py` при необходимости, `voice/README.md`, `docs/PROJECT_MASTER_LOG.md` только для интеграции статуса CLAIM.
- Не пересекается с `CHAT_MAIN-2026-09-16-RESEARCH-QUALITY`: research files и `.github/workflows/voice-ci.yml` не трогаются; master log всегда обновляется только поверх свежего HEAD с сохранением чужого CLAIM.
- Инженерная причина: текущий Silero baseline не использует переданные `emotion/intensity/speed`, а постпроцессор связывает темп и высоту через простой ресемплинг, что ухудшает естественность; конфигурация `breathing_pauses` заявлена, но фактически не реализована.
- Следующий шаг: проверить server call path и текущие voice tests, затем внести совместимый local-only DSP/text-prosody refactor и прогнать unit/voice CI.

### CLAIM `CHAT_MAIN-2026-09-16-MASTER-CORE`

- Статус: **DONE**
- Started from HEAD: `69f54cc06720a1300b7e7ac1d997ceb1c1b3c2e9`
- Integrated through: `bb348adeb27c5bfa9ebba9a82e07d11d71ae632c`
- Journal close commit: `932f2d5da41923b7e4277aefb794fc4f2c50c058`
- Результат: единый журнал + strict self-reliance + compatibility isolation + offline proof + self-improvement audit.
- Checks: Core/Voice `35067895081` SUCCESS; Agent Sync `35067895155` SUCCESS; Evolution `35067895168` SUCCESS; journal Core/Voice `35068214336` SUCCESS.
- Пути освобождены, кроме путей, занятых новым research claim выше.

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

## 15. Последняя запись завершённого этапа

### 2026-09-16 — Chat — self-reliance hardening

- Base HEAD: `69f54cc...`.
- Integrated code HEAD: `bb348ade...`.
- Journal: `932f2d5d...`.
- Сделано: local-only normal path, compatibility isolation, full offline autonomy smoke, deterministic self-improvement authority, bundled bootstrap contract.
- Инженерная причина: independence должна проверяться реальным execution path, а не только флагами.
- Проверки: Core/Voice `35067895081` SUCCESS; Agent Sync `35067895155` SUCCESS; Evolution `35067895168` SUCCESS; master-only CI `35068214336` SUCCESS.
- Следующий шаг: текущий ACTIVE research-quality claim.

## 16. Формат записи завершённого этапа

```text
### <date-time> — <mode> — <stage>
- Base HEAD: ...
- Commits: ...
- Сделано: ...
- Инженерная причина: ...
- Проверки: ...
- Ограничения/риски: ...
- Следующий шаг: ...
- Освобождённые файлы: ...
```

---

Последнее правило: **если разговор/Work/Codex остановился, следующий исполнитель не восстанавливает план по догадкам — он читает этот файл, актуальный Git HEAD и CI, затем создаёт новый CLAIM и продолжает с первого незавершённого пункта, не повторяя уже выполненную параллельную работу.**
