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
- AuroraFox сохраняет опыт в собственной памяти/Core Knowledge/skills/checkpoints;
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
- исторические V1.2/V1.3 с неполной trust-chain должны иметь one-time Repair/Bridge на новый подписанный floor; после signed floor обновления обязаны работать автоматически;
- все решения/проверки/планы ведутся только здесь.

### 1.3. ЖЁСТКОЕ ПРАВИЛО ВЕРСИОНИРОВАНИЯ

AuroraFox использует формат `MAJOR.MINOR.PATCH.BUILD` (`A.B.C.D`). Нельзя выпускать функционально изменённый продукт под тем же номером, что уже был собран/передан пользователям.

- `MAJOR` (`A`) — несовместимая архитектурная миграция или крупная смена продукта/данных/API, требующая осознанного перехода.
- `MINOR` (`B`) — крупная новая возможность, самостоятельный крупный блок, заметная переработка нескольких подсистем или новый release floor.
- `PATCH` (`C`) — завершённое улучшение/переработка существующего блока: UI, голос, память, knowledge, updater, Core quality, Computer Agent и т.п., если совместимость сохраняется.
- `BUILD` (`D`) — точечный исправленный дефект/hotfix/packaging fix без изменения общего пользовательского контракта.

Обязательный процесс:

1. При начале изменения исполнитель записывает в CLAIM предполагаемый уровень bump, но **не меняет каноническую версию заранее**.
2. Сначала код/ресурсы проходят относящиеся к ним unit/smoke/integration/package/device/release-gates.
3. Блок считается принятым только когда relevant tests зелёные и для изменённого блока нет известного P0/P1 дефекта, делающего новую реализацию хуже/неработоспособной.
4. Только после этого выполняется version bump отдельным завершающим этапом и синхронизируются `project/version.json`, `project.godot`, Android `versionCode`, installer/update metadata, CHANGELOG и release manifest/contracts.
5. После bump обязательны повторные version-sync + package/update/release tests. Если они красные, новая версия не считается готовой.
6. Если в одном релизе накопилось несколько законченных изменений, применяется **наибольший** требуемый bump. Не нужно искусственно повышать номер после каждого внутреннего commit, но нельзя отдать/опубликовать изменённый бинарник под старым номером.
7. Любое функциональное изменение после уже опубликованного normal release обязательно ведёт к версии строго выше опубликованной.
8. Android `versionCode` увеличивается для каждого installable Android release и никогда не уменьшается/не повторяется.
9. Слова «идеально/готово» в журнале означают проверяемый acceptance gate: все относящиеся тесты зелёные и нет известного блокирующего дефекта; абсолютное отсутствие будущих улучшений не подразумевается.

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

Windows V1.2 имеет опубликованный one-time Repair Bridge. Исторические V1.2/V1.3 binaries были собраны до корректного закрепления `release_public.pub`, поэтому они не могут безопасно начать signed auto-update задним числом только публикацией `update.json`. Для них требуется one-time repair на новый signed floor. После нового signed floor updater обязан автоматически видеть все последующие версии через стабильный `releases/latest/download/update.json` + `update.sig`.

Production release signing identities — owner-controlled boundary. Private signing keys запрещено коммитить/выдавать клиентскому Core. Это намеренная граница доверия, а не external AI dependency.

## 9. Голос / Computer Agent / Work / API

Сохраняются local STT/TTS/VAD/wake/barge-in; Computer Agent screenshot/UI automation/vision fallback + sandbox; Work/projects; API bridge/privacy; Windows sidecars; Android native plugin paths; snapshot/rollback/runtime extensions.

Online tools не заменяют AgentCore. Отказ voice/files/computer/API/online enhancement не должен ломать основной local chat.

## 10. Консолидированная история

### 2026-09-15 — local-first migration

Aurora Core primary; Ollama optional; local model quarantine/failover; расширенный Knowledge; streaming; registry/rollback; local semantic memory; self-improvement benchmarks; promotion separated from release authority; Android local document paths.

### 2026-09-16 — updater/signing

Историческая V1.2 проверена; обнаружен отсутствующий trust root; сделан Windows V1.2→V1.3 repair; contract исправлен на repair-through-V1.2; дальнейший аудит показал, что историческая V1.3 также не содержит закреплённого trust root, поэтому новый signed floor должен быть выше V1.3.

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
7. Repair historical V1.3 onto the new signed update floor, then verify latest-update detection end-to-end.

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

### P0 — updater/versioning repair

- [ACTIVE] historical V1.3 one-time repair path на новый signed floor;
- [ACTIVE] закрепить permanent public update trust root в приложении;
- [ACTIVE] CI contract: normal latest release обязан содержать `update.json`, `update.sig`, platform assets и версию выше клиента;
- [ACTIVE] versioning policy + automated version-discipline contract;
- [NEXT] после зелёных gates поднять версию по правилу максимального требуемого bump и пересобрать Windows/Android.

### P1 — release readiness

- [WAITING OWNER BOUNDARY] private production update key secret + Android release identity;
- после bootstrap owner identity проверить signed release/update end-to-end.

### P2 — качество

- local OCR;
- device tests;
- voice quality;
- Work UX;
- large knowledge performance;
- Core benchmarks.

## 14. Активные работы и занятые файлы

### CLAIM `CHAT-2026-09-16-UPDATER-VERSIONING`

- Статус: **ACTIVE**
- Started from HEAD: `e7760a71d484d6a3d5c5578e90b152e79850b878`
- Режим: Chat
- Цель: исправить update visibility/repair для исторических V1.2/V1.3, создать новый signed update floor, закрепить permanent trust root, автоматизировать проверку `latest`-manifest и жёсткое versioning policy.
- Предполагаемый bump после зелёных acceptance-gates: **MINOR** (новый signed release floor + крупный updater/release contract), то есть следующий normal release должен быть не ниже `V1.4.0.0`; каноническая версия меняется только после тестов.
- Файлы/подсистема: `update/update_manager.gd`, `update/manifest.template.json`, `update/release_public.pub`, `.github/workflows/release.yml`, `.github/workflows/windows-package-ci.yml`/repair workflow при необходимости, `build/*release*`, `project/version.json`, `project.godot`, `export_presets.cfg`, `CHANGELOG.md`, `tests/update*`, `tests/version_sync_test.ps1`, новые version/release contracts, `AGENTS.md`, `docs/PROJECT_MASTER_LOG.md`.
- Не пересекается с UI claim: `update/update_overlay.gd` остаётся за UI lane; с research/voice/server claims их файлы не трогаются. Перед каждой записью сверять свежий `main` и интегрировать параллельные изменения.
- Инженерная причина: normal `latest` release отсутствует, а historical V1.3 использует RSA updater, но не содержит pinned `release_public.pub`; поэтому публикация одного `update.json` не может исправить уже установленный бинарник. Нужен one-time repair на новый signed floor и permanent version/release discipline.
- Acceptance: V1.2 repair остаётся рабочим; V1.3 repair проверен in-place на Windows с сохранением `user://`; новый floor содержит pinned public key; updater contract на floor видит версию выше себя и отклоняет неверную подпись/hash; release workflow обязан формировать `latest` assets; version bump выполняется только после зелёных Core/Windows/Android/update/release gates.

### CLAIM `CHAT-2026-09-16-UI-POLISH`

- Статус: **ACTIVE**
- Started from HEAD: `edbc35f07a7fc140e8127c078ea7185365070aec`
- Режим: Chat
- Цель: полностью привести Windows/Android UI AuroraFox к устойчивой адаптивной компоновке без наложений, съезжающих элементов, непонятных/дублирующих кнопок и примитивного визуального оформления; аватар/`fox_logo.svg` по прямому указанию владельца не изменять до получения нового эталона.
- Файлы/подсистема: `scripts/main.gd`, `scripts/main_compat.gd`, `scripts/mobile_ui_adapter.gd`, `scripts/desktop_visual_theme.gd`, `scripts/settings_overlay.gd`, `scripts/settings_visual_fix.gd`, `scripts/voice_overlay.gd`, `scripts/voice_overlay_compat.gd`, `scripts/computer_overlay.gd`, `scripts/computer_overlay_compat.gd`, `scripts/knowledge_base_overlay.gd`, `scripts/self_improvement_overlay.gd`, `work/work_overlay.gd`, `update/update_overlay.gd`, `api/settings_overlay.gd`, `assets/ui/icon_*.svg` кроме `fox_logo.svg`, `tests/desktop_ui_smoke.gd`, `docs/PROJECT_MASTER_LOG.md`.
- Не пересекается с `CHAT_MAIN-2026-09-16-RESEARCH-QUALITY` и `CHAT-2026-09-16-VOICE-QUALITY`: research/voice-python файлы и `.github/workflows/voice-ci.yml` не трогаются; журнал всегда обновляется только поверх свежего HEAD с сохранением чужого CLAIM.
- Инженерная причина: текущий UI собирается несколькими независимыми overlay-скриптами с фиксированными popup-размерами и отдельными абсолютными/floating controls; это создаёт реальные риски overflow/overlap на 960px и Android, а часть функций дублируется или имеет слишком неясные подписи. Нужны единые responsive rules, компактные action surfaces и regression checks.
- План проверки: до интеграции в `main` использовать отдельную UI-ветку, расширить `desktop_ui_smoke.gd` проверками геометрии/сигналов/понятности элементов и принимать этап только после чистого Godot parse + UI smoke + соответствующих GitHub Actions.

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

### CLAIM `CHAT-2026-09-16-SERVER-DB`

- Статус: **ACTIVE**
- Started from HEAD: `996adb626416df2529f78f339dd9a6acf9c72b01`
- Режим: Chat
- Цель: довести серверный контур AuroraFox и постоянное хранилище до транзакционного production-ready baseline: единая SQLite БД без внешней СУБД, безопасная миграция существующих JSON/JSONL, конкурентная запись, integrity/readiness, резервное копирование и rollback-safe обновление REG.RU.
- Предполагаемый bump после зелёных acceptance-gates: **MINOR** из-за нового account/guest/device-sync server contract; каноническую версию этот lane не меняет, итоговый bump выполняет release/versioning этап.
- Файлы/подсистема: `api/database.py`, `api/auth.py`, `api/account_store.py`, `api/sync_store.py`, `api/conversation_store.py`, `api/learning_store.py`, `api/learning_sync.py`, `api/server.py`, `api/backup_service.py`, `api/core_candidate_queue.py`, `tests/test_api_gateway.py`, `tests/test_api_database.py`, `tests/test_api_accounts_sync.py`, `tests/test_api_account_network.py`, `tests/test_api_account_restore.py`, `tests/test_api_schema_migrations.py`, `tests/test_api_privacy_contract.py`, `tests/test_backup_service.py`, `tests/test_deployment_contract.py`, `deploy/reg_ru/install.sh`, `deploy/reg_ru/update.sh`, `.github/workflows/api-ci.yml`, `docs/PROJECT_MASTER_LOG.md`.
- Не пересекается с: `CHAT-2026-09-16-UI-POLISH`, `CHAT_MAIN-2026-09-16-RESEARCH-QUALITY`, `CHAT-2026-09-16-VOICE-QUALITY`, `CHAT-2026-09-16-UPDATER-VERSIONING`, `CHAT-2026-09-16-CORE-BENCHMARKS`, `CHAT-2026-09-16-LOCAL-OCR`; их занятые paths не изменять.
- Инженерная причина: flat JSON/JSONL stores имеют race/scale/corruption-риск при параллельном FastAPI access и не дают единый transactional integrity contract. Python `sqlite3` встроен, не создаёт внешней runtime-зависимости; personal data требует отдельного principal/device/session/sync trust boundary и не должно автоматически попадать в shared Core learning.
- План проверки: миграция legacy stores → SQLite с идемпотентностью; WAL/busy-timeout/foreign keys/integrity checks; rollback mirrors; account/guest isolation; refresh rotation/replay/revoke; guest migration; persistent sync/conflicts; `/ready`; backup/restore; REG.RU pre-update snapshot; API/deployment/backup tests + exact-head API CI.

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
- Сделано: local-only normal path, compatibility isolation, full offline chat/planning/local-tool/memory smoke, deterministic self-improvement authority, bundled bootstrap contract.
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

## 17. Work — координация и аудит, 2026-09-16

### CLAIM `WORK-2026-09-16-CANDIDATE-QUEUE-AUDIT`

- Статус: **DONE — локальные проверки; ожидает CI/интеграции**
- Started from HEAD: `9376c2cbf9bbfb823c74550a52e35e53d2497768`
- Режим: Work
- Цель: проверить persistent candidate queue, изоляцию submissions и целостность артефактов; согласовать следующие задачи активных чатов без повторения их изменений.
- Файлы: `api/core_candidate_queue.py`, `tests/test_core_candidate_queue.py`, `docs/PROJECT_MASTER_LOG.md`; исходное полное ТЗ `docs/AURORAFOX_FULL_SPECIFICATION_RU.md` как технический документ, не второй журнал.
- Не пересекается с активными UI/research/voice/server DB CLAIM. Не менять их файлы, release authority и normal local Core.
- Решение: прежний локальный `afd1522` создан на старой архитектуре; не переносить выбор Ollama/provider или параллельные журналы в новый main. Account foundation требует отдельного согласования с SERVER-DB, а не слепого merge.
- Проверка: относящиеся Python-тесты, реальный SQLite restart/concurrency/integrity; результаты записать здесь.
- Результат: кандидатная очередь использует файловые bundles, не SQLite; исправлены owner/base/target проверки duplicate, повторная проверка persistent manifest при materialization, reserved dot IDs, опасное пересечение destination с очередью, межпроцессная сериализация mutations и fsync данных.
- Проверено на актуализированной ветке: 26 tests passed (candidate queue/promotion/master journal), включая 6 настоящих процессов с лимитом 2 и сохранение destination при отклонении испорченного manifest.
- Общий Python-прогон на исходном 9376c2c: **117 passed, 1 failed**. `tests/test_autonomous_evolution_contract.py::test_autonomous_research_is_promoted_to_long_term_knowledge` требует `memory.learn(` в collector, хотя актуальный collector уже делегирует curator. Не исправлять повторным обходом curator: RESEARCH-QUALITY должен обновить контракт под единственную точку promotion и повторить общий набор.
- Commits локального этапа: `b6b6393`, merge свежего main `4ebcec0` через `02f6f3a`; чужие CLAIM сохранены при разрешении конфликта только в общем журнале.
- Непроверено: Windows-ветка file lock, реальный full-model inference, native UI/голос, production VPS; это не итоговая приёмка AuroraFox.
- Следующий шаг: CI ограниченного PR; RESEARCH-QUALITY закрывает найденный устаревший test contract, SERVER-DB согласует дальнейшую account migration. Очередь corrupt records пока требует явного integrity/status gate вместо молчаливого пропуска.
- Файлы освобождены после этого пакета; account/provider правки старого `afd1522` не опубликованы и не должны слепо интегрироваться.

### Следующие задания активным чатам от владельца — 2026-09-16

Это задания в общем журнале, а не утверждение, что исполнители уже их прочитали.
Каждый сохраняет свою текущую задачу до завершённого проверенного пакета.

| Исполнитель | Следующая задача | Обязательный результат |
|---|---|---|
| UI-POLISH, PR #27 | Закончить адаптивность и навигацию, затем визуальную приёмку Windows/Android: вход/гость, чат, память, файлы, проекты, настройки, ошибки; согласовать правильную лису с текущим владельческим эталоном. | Настоящие кадры обоих клиентов, проверенные клики, отсутствие наложений и заглушек; размеры экранов и CI SHA. |
| RESEARCH-QUALITY | Закрыть обход curator, затем добавить corroboration/contradiction и устойчивую очередь вопросов о пробелах. | Rejected/duplicate/local-document не попадают в automatic knowledge; promoted item имеет URL/hash/quality; перезапуск сохраняет очередь. |
| VOICE-QUALITY | После DSP исправлений создать реальные утренний/ночной/игривый/серьёзный русские образцы женского голоса и проверить локальную озвучку обеих платформ. | WAV/измерения задержки и отсутствие clipping; честно отметить прослушивание и непроверенный Android путь. |
| SERVER-DB | Закончить миграцию/backup/ready, затем аккаунты и personal isolation, rotation/replay/revoke, transactional guest migration и persistent device sync. | Два аккаунта и два гостя изолированы; реальные network/SQLite/restart/conflict/restore tests; не смешивать общий Core и личную память. |
| MASTER-CORE, следующий свободный этап | Проверить настоящий bundled Core без Ollama/интернета на Windows/Android; затем quality benchmarks и полные 3–10 кандидатов. | Реальные ответы/планирование/инструменты/память, одинаковые тесты кандидатов, rejected regression не меняет stable; fixture не выдавать за качество LLM. |
| WORK, текущий этап | Проверить кандидатную серверную очередь и долговечность, закрыть конкретные дефекты; затем согласовать ограниченные изменения PR #25 с SERVER-DB. | Тесты на текущем main и точная запись результата; старую ветку не сливать с конфликтами и устаревшим runtime. |

Общее правило приёмки: «готово» — только с проверяемым результатом. Сам себя
похвалил в журнале — ещё не прошёл gate 🙂. Экономить токены: один пакет чтения,
один связанный набор правок, относящиеся тесты; повторять только при выявленном дефекте.


### CLAIM `CHAT-2026-09-16-UPDATER-VERSIONING`

- Статус: **ACTIVE**
- Started from HEAD: `e7760a71d484d6a3d5c5578e90b152e79850b878`
- Режим: Chat
- Цель: исправить update visibility/repair для исторических V1.2/V1.3, создать новый signed update floor, закрепить permanent trust root, автоматизировать проверку `latest`-manifest и жёсткое versioning policy.
- Предполагаемый bump после зелёных acceptance-gates: **MINOR** (новый signed release floor + крупный updater/release contract), то есть следующий normal release должен быть не ниже `V1.4.0.0`; каноническая версия меняется только после тестов.
- Файлы/подсистема: `update/update_manager.gd`, `update/manifest.template.json`, `update/release_public.pub`, `.github/workflows/release.yml`, `.github/workflows/windows-package-ci.yml`/repair workflow при необходимости, `build/*release*`, `project/version.json`, `project.godot`, `export_presets.cfg`, `CHANGELOG.md`, `tests/update*`, `tests/version_sync_test.ps1`, новые version/release contracts, `AGENTS.md`, `docs/PROJECT_MASTER_LOG.md`.
- Не пересекается с UI claim: `update/update_overlay.gd` остаётся за UI lane; с research/voice/server claims их файлы не трогаются. Перед каждой записью сверять свежий `main` и интегрировать параллельные изменения.
- Инженерная причина: normal `latest` release отсутствует, а historical V1.3 использует RSA updater, но не содержит pinned `release_public.pub`; поэтому публикация одного `update.json` не может исправить уже установленный бинарник. Нужен one-time repair на новый signed floor и permanent version/release discipline.
- Acceptance: V1.2 repair остаётся рабочим; V1.3 repair проверен in-place на Windows с сохранением `user://`; новый floor содержит pinned public key; updater contract на floor видит версию выше себя и отклоняет неверную подпись/hash; release workflow обязан формировать `latest` assets; version bump выполняется только после зелёных Core/Windows/Android/update/release gates.


Код: draft [PR #29](https://github.com/Treninem/AI/pull/29), commit `13b5a948363688eb0b38429330e127a9a52ea7a4`. Эта запись публикует только координацию; код и полный текст 56 пунктов ТЗ находятся в PR до CI/интеграции.

## 18. Core Quality / Performance Benchmark & Regression Gate — active lane

### CLAIM `CHAT-2026-09-16-CORE-BENCHMARKS`

- Статус: **ACTIVE**
- Started from HEAD: `0179f4d3e0f0dc3f6bda1edb84006e8363f50613`
- Режим: Chat
- Цель: создать воспроизводимый измеримый offline benchmark/regression gate для bundled AuroraFox Core: фактическая полезность, normal-path self-reliance, качество, память/knowledge/planning/tool-selection, устойчивость и производительность без Ollama/remote AI/интернета.
- Предполагаемый bump после зелёных acceptance-gates: **PATCH** (Core quality/regression infrastructure); публичную/каноническую версию этот lane не меняет — финальный общий release bump остаётся за release/integration этапом.
- Файлы/подсистема: новые `benchmarks/core/**`, новые benchmark-specific `tests/*core_benchmark*`, новый isolated CI workflow `.github/workflows/core-benchmarks.yml`; production `core_runtime/`, AgentCore, memory/Core Knowledge/planning меняются только если benchmark воспроизводимо выявит orchestration/context/retrieval дефект и конкретные файлы не заняты другим ACTIVE CLAIM.
- Не пересекается с: `CHAT-2026-09-16-UPDATER-VERSIONING`, `CHAT-2026-09-16-UI-POLISH`, `CHAT_MAIN-2026-09-16-RESEARCH-QUALITY`, `CHAT-2026-09-16-VOICE-QUALITY`, `CHAT-2026-09-16-SERVER-DB`; их заявленные файлы не изменять.
- Инвариант normal path: benchmark запрещает Ollama/OpenAI/другие AI API/remote inference/network fallback и должен отдельно доказать, что даже при включённом legacy compatibility switch normal `AIClient.chat()` остаётся на bundled AuroraFox Core/runtime.
- Acceptance: machine-readable JSON report; deterministic/semantic quality checks отдельно от performance; cold/warm latency, throughput-equivalent, peak RSS/RAM, timeout/hang detection и repeatability; relative performance regression rules вместо хрупких CI absolute timings; воспроизводимые failing cases не маскируются внешней моделью.

## 19. Local OCR for Core Knowledge — active lane

### CLAIM `CHAT-2026-09-16-LOCAL-OCR`

- Статус: **ACTIVE**
- Started from HEAD: `2dca22523f3ce2eb7a8dab8d5908998e1742df70`
- Режим: Chat
- Цель: встроить production-ready полностью локальный OCR для image-only/scanned и mixed PDF, а также изображений, в существующий File Intelligence → Knowledge/Core Knowledge import flow на Windows и Android без Ollama/remote AI/cloud OCR.
- Предполагаемый bump после зелёных acceptance-gates: **PATCH** (закрытие существующего Knowledge/document OCR gap); каноническая версия и Android versionCode этим lane не меняются — финальный bump делает общий release/integration этап.
- Файлы/подсистема: `file_intelligence/file_service.py`, `file_intelligence/requirements.txt`, `file_intelligence/install_files.ps1`, `file_intelligence/README.md`, `scripts/knowledge_document_importer.gd`, `scripts/file_intelligence_client.gd`, `scripts/knowledge_store.gd` только если нужен явный untrusted metadata contract, `android_plugin/plugin/src/main/java/com/aurorafox/runtime/AndroidFileRuntime.kt`, `android_plugin/plugin/build.gradle.kts`, `android_plugin/settings.gradle.kts`, Android Godot plugin dependency metadata только если требуется для packaging, новые OCR-specific tests (`tests/test_local_ocr.py`, `tests/local_ocr_knowledge_smoke.gd`, Android OCR contract tests), новый isolated `.github/workflows/local-ocr-ci.yml`, `docs/PROJECT_MASTER_LOG.md`.
- Не пересекается с: `CHAT-2026-09-16-UPDATER-VERSIONING`, `CHAT-2026-09-16-UI-POLISH`, `CHAT_MAIN-2026-09-16-RESEARCH-QUALITY`, `CHAT-2026-09-16-VOICE-QUALITY`, `CHAT-2026-09-16-SERVER-DB`, `CHAT-2026-09-16-CORE-BENCHMARKS`; их занятые файлы, workflow и benchmark paths не изменять.
- Инварианты: normal OCR не вызывает OpenAI/Gemini/Claude/Ollama/remote inference/network; text-layer PDF пропускает OCR на пригодных страницах; scanned/mixed PDF обрабатывается page-by-page с лимитами; ru+en; page/source metadata сохраняется; OCR content помечается untrusted document data и не получает executable/system authority; отсутствие OCR runtime даёт понятную деградацию без падения чата; baseline runtime/model assets должны быть внутри поставляемого приложения либо использовать локальный системный механизм, без обязательного runtime-download/setup wizard.
- Acceptance: regression/unit/integration tests для text/scanned/mixed/empty/large/corrupt/ru/en/oversize/missing-runtime/duplicate-reimport/untrusted boundary; Windows + Android package/contract gates; relevant tests зелёные до закрытия CLAIM.

## 20. Voice Quality — coordinator acceptance checkpoint, 2026-09-16

### `CHAT-2026-09-16-VOICE-QUALITY` — checkpoint

- Статус: **ACTIVE — coordinator acceptance выполняется**.
- Base HEAD этого пакета: `bc2f5dfad86be9f8f9addaa4da5ebb09f7cf1d11`.
- Commits: `8f0ef307d08cf59418c8983f92a0b8cf3871bd2e` (`voice: benchmark persona samples and latency`), `c39df6fce6cae9624805b32084984e27d320ad2c` (`test: lock voice persona acoustic gate`).
- Предполагаемый bump voice-lane после зелёных acceptance-gates: **PATCH**; каноническую версию этот lane не меняет, итоговый агрегированный bump остаётся за release/versioning этапом.
- Сделано: acoustic benchmark расширен реальными русскими женскими сценариями `persona_morning`, `persona_night`, `persona_playful`, `persona_serious`; каждый сохраняет raw/final WAV и измеряет model-load, synthesis/processor/total wall time, real-time factor, UTMOS, TTS→Whisper intelligibility, peak/RMS, clipping/DC/hard-edge. Отдельный regression contract запрещает потерять эти четыре сценария и latency/clipping evidence.
- Инженерная причина: координатор требует не декларацию «голос улучшен», а воспроизводимые WAV и измерения. Абсолютный latency threshold в shared CI намеренно не введён: фиксируется RTF/wall-time, чтобы сравнивать регрессии без ложных падений из-за разных GitHub runners.
- Предыдущий доказанный baseline: acoustic run `35078865148` SUCCESS — raw UTMOS mean `3.5763`, Aurora `3.5893`, ASR similarity mean `0.9428`, clipping gate пройден; speaker sweep: `kseniya 3.5763` > `xenia 3.4666` > `baya 3.1718`.
- Текущие проверки: persona acoustic run `35081711227` на `8f0ef307...` — **QUEUED** на момент записи; exact test/Core run `35081841428` и Android APK run `35081841551` на `c39df6fc...` — **QUEUED**. CLAIM не закрывать до получения финальных статусов и артефактов.
- Ограничение/риск: Windows `prosody_dsp=false` оставлен намеренно, потому что ранний phase-vocoder/DSP regression заметно ухудшал UTMOS. Поэтому значения emotion `speed/pitch` нельзя считать доказанным изменением тембра/темпа Windows WAV; persona acceptance сейчас доказывает качество/разборчивость/latency/clipping, но субъективную различимость эмоциональной манеры нужно подтверждать прослушиванием или безопасной model/punctuation prosody без возврата роботизирующего DSP. Android имеет локальный Piper speed/silence shaping, но физический Android device listen ещё не доказан.
- Границы: UI/OCR/research/Core/updater/server файлы не изменялись; `.github/workflows/voice-ci.yml` не трогался.
- Следующий шаг: дождаться выполнения `35081711227`, забрать `persona_*_aurora.wav` и `report.json`, записать точные latency/RTF/clipping/UTMOS/ASR; затем проверить `35081841428` и `35081841551`. Если voice-specific gate красный — исправлять только voice-owned paths. Если зелёный — провести/зафиксировать доступную Windows listen-проверку и честно оставить physical Android device listen отдельным gate, если реального устройства в контуре нет.
- Файлы `voice/tools/acoustic_benchmark.py` и `tests/test_voice_configs.py` остаются занятыми этим ACTIVE CLAIM до завершения coordinator acceptance.

## 21. SERVER-DB — coordinator acceptance checkpoint, 2026-09-16

### `CHAT-2026-09-16-SERVER-DB` — checkpoint

- Статус: **ACTIVE — account/personal-sync baseline принят по exact-head API CI; продолжается production hardening**.
- Account/sync package commits: `726f2a6f`, `1c33e3f1`, `34f5e6ef`, `23c34782`, `abae7a02`, `e36acfb2`, `94c14c81`, `22e626bf`, `acd6c37f`, `47c826d2`, `12c49204`, `66600beb`, `50af5e6d`, `5ad72f3a`, `bc82d4dc`, `4193f566`, `1326a9e9`, `08591b08`.
- Сделано: SQLite schema поднята до v3 с additive migration; добавлены accounts/guests/devices/auth sessions/rotating refresh token families/account one-time tokens/revisioned sync entities/change cursor/conflicts. Passwords хэшируются `scrypt` + random salt; bearer/refresh/guest tokens в БД только как SHA-256 hashes. Refresh rotation одноразовая; replay сохраняет family revoke транзакционно; device revoke инвалидирует sessions.
- Personal isolation: account/guest bearer principals имеют стабильный server-side owner (`account:<id>` / `guest:<id>`); два аккаунта и два гостя могут использовать одинаковые conversation/entity IDs без пересечения. Personal scopes намеренно не содержат `memory.write`/`feedback`; normal account/guest chat не попадает в shared learning queue. Server normal `auto/agent` path больше не делает автоматический Ollama fallback; Ollama остаётся только explicit `mode=ollama` compatibility.
- Sync: push/pull cursor, per-entity revisions/checksum/tombstones, idempotent same-content writes, stale-write conflict preservation и explicit conflict resolution. Guest→account migration выполняется одной SQLite transaction: conversations/messages переносятся, collision conversation сохраняется под новым ID, unique sync data переносится, duplicate схлопывается, conflicting guest version сохраняется в `sync_conflicts`, guest/device revoke происходит только в той же successful transaction.
- Backup/restore: export backup очищает API keys, access/refresh/account one-time hashes, password hashes/salts и guest bearer hashes с `VACUUM`; root-only operational snapshot сохраняет полный auth state для точного rollback. Regression `test_api_account_restore.py` доказывает восстановление account access session + personal sync после snapshot restore.
- REG.RU: fresh install и updater теперь запускают account/sync/network/schema/privacy/restore gates до activation; updater по-прежнему делает root-only DB snapshot + sanitized owner backup до checkout, `/ready` + direct SQLite integrity после restart и code+DB rollback при failure.
- Проверки: API CI `35084280709` на `47c826d2...` — SUCCESS (python/windows/godot; network account test включён); API CI `35084594540` на `bc82d4dc...` — SUCCESS (включая restore test); exact deployment/account head API CI `35084740506` на `08591b08...` — **SUCCESS**: `python-api`, `windows-api`, `godot-api` все зелёные.
- Найденный и исправленный test-infra дефект: первый network run `35084112647` падал при collection из-за отсутствующего `httpx`; production code не падал. CI/install/update теперь явно ставят `httpx==0.28.1` для FastAPI network contract.
- Ограничения/риски: физический REG.RU host этим чатом не изменялся и не считается проверенным без доступного SSH/terminal connector. Email verification/reset one-time token storage реализован, но production delivery transport ещё не подключён; dev token exposure выключен по умолчанию. До полного server acceptance также нужен ingress request-body guard до полной JSON materialization и capacity/retention policy без удаления pending/private data.
- Следующий шаг по указанию главного координатора: **не трогать UI/voice/research/OCR/Core/updater-owned paths**; внутри SERVER-DB lane реализовать production email verification/reset delivery boundary без хранения raw long-lived secrets, затем early HTTP body limit/capacity gates; после этого проверить доступный публичный REG.RU `/health`/`/ready` и оставить физический SSH deployment owner/access boundary, если connector по-прежнему отсутствует.
