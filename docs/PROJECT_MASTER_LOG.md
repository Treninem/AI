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

## 22. Integration / Regression / Release Readiness Gate — active lane

### CLAIM `CHAT-2026-09-16-INTEGRATION-GATE`

- Статус: **ACTIVE**
- Started from HEAD: `6fd0539e8ee849487d9eb22b1615d4ab54ae4c20`
- Режим: Chat
- Цель: независимый cross-subsystem integration/regression/release-readiness gate для свежего `main`: рано находить несовместимости между Core/AgentCore/Knowledge/Research/Voice/OCR/API/accounts/UI/updater/package/safety lanes, не дублируя их реализацию.
- Предполагаемый bump после зелёных acceptance-gates: **BUILD**, если изменения остаются только integration/CI/test infrastructure; каноническую версию и Android versionCode этот lane не меняет. Если найденный product fix требует большего bump, он маршрутизируется владельцу production CLAIM.
- Собственные файлы/подсистема: только новые `tests/integration_*`, `tests/release_readiness_*`, `tests/cross_subsystem_*`, новый `.github/workflows/integration-gate.yml` при отсутствии конфликта, integration scripts и `docs/PROJECT_MASTER_LOG.md`.
- Не изменять production-файлы и workflow, занятые `CHAT-2026-09-16-UPDATER-VERSIONING`, `CHAT-2026-09-16-UI-POLISH`, `CHAT_MAIN-2026-09-16-RESEARCH-QUALITY`, `CHAT-2026-09-16-VOICE-QUALITY`, `CHAT-2026-09-16-SERVER-DB`, `CHAT-2026-09-16-CORE-BENCHMARKS`, `CHAT-2026-09-16-LOCAL-OCR`.
- Главный gate: normal AuroraFox path должен оставаться полностью работоспособным без Ollama/OpenAI/Gemini/Claude/remote inference/Internet и использовать bundled AuroraFox Core; external AI не может стать обязательным fallback.
- Acceptance: offline Core; Knowledge/OCR after integration; collector→curator authority; Account A/B + Guest A/B isolation; Windows package; Android APK + bundled runtime/model/OCR; updater/version contract; UI integration smoke; master stop/snapshot/rollback/privacy/sandbox/candidate verification gates; Core benchmark without blocking regression; CI failures routed by exact CLAIM-ID with job/test/SHA evidence; physical-device tests reported honestly if unavailable.

## 23. Large Knowledge / Memory Performance & Stress — active lane

### CLAIM `CHAT-2026-09-16-LARGE-KNOWLEDGE-PERF`

- Статус: **ACTIVE**
- Started from HEAD: `41acd5781d34719c9b257990b40f976e3dd04eb0`
- Режим: Chat
- Цель: довести измеримый production-readiness contract для больших локальных Knowledge/Memory datasets: import/streaming, search/retrieval, deduplication, source removal, restart, transaction/rollback, concurrency и memory/disk scaling на Windows и Android без Ollama/remote AI/интернета.
- Предполагаемый bump после зелёных acceptance-gates: **PATCH**; каноническую версию и Android versionCode этот lane не меняет, финальный общий bump выполняет release/integration этап.
- Собственные свободные файлы/подсистема: новые `benchmarks/knowledge/**`, новые `tests/*knowledge_performance*`, `tests/*knowledge_stress*`, isolated `.github/workflows/knowledge-performance.yml`, `scripts/knowledge_import_transaction.gd`, `scripts/knowledge_source_registry.gd`, `scripts/memory_store.gd` только для benchmark-proven performance follow-up, `docs/PROJECT_MASTER_LOG.md`.
- Не изменять production-файлы и тесты/workflows, занятые `CHAT-2026-09-16-LOCAL-OCR`, `CHAT-2026-09-16-CORE-BENCHMARKS`, `CHAT-2026-09-16-INTEGRATION-GATE`, `CHAT-2026-09-16-SERVER-DB`, `CHAT-2026-09-16-UI-POLISH`, `CHAT_MAIN-2026-09-16-RESEARCH-QUALITY`, `CHAT-2026-09-16-VOICE-QUALITY`, `CHAT-2026-09-16-UPDATER-VERSIONING`.
- Особая граница: `scripts/knowledge_store.gd`, `scripts/knowledge_document_importer.gd`, `scripts/file_intelligence_client.gd`, OCR/File Intelligence и Android document/OCR paths принадлежат `CHAT-2026-09-16-LOCAL-OCR` до освобождения; найденные bottleneck в них фиксировать воспроизводимым benchmark/report и передавать владельцу через `PERFORMANCE-BLOCKER`, не править самостоятельно.
- Performance-follow-up ownership extension: после двух независимых standard Linux CI подтверждено накопительное N→2N near-4x scaling; `scripts/knowledge_import_transaction.gd`, `scripts/knowledge_source_registry.gd`, `scripts/memory_store.gd` свободны от других ACTIVE CLAIM и зарезервированы этим lane для адресных исправлений после соответствующего benchmark evidence. `scripts/knowledge_store.gd` по-прежнему не трогать до освобождения `LOCAL-OCR`.
- Acceptance: детерминированно генерируемые datasets без огромных Git fixtures; machine-readable JSON report с dataset/record/chunk counts, duration/throughput, peak RSS, DB/index size, search p50/p95/p99, restart/removal/rollback, duplicate/error counts и runtime identity; N/2N/4N scaling; correctness gates для restart/dedup/source removal/failure rollback; self-reliance flags `network_required=false`, `external_runtime_required=false`, `ollama_required=false`; Android-appropriate bounded-memory contract с честной отметкой, если physical device недоступен.

## 24. Work / Computer Agent Reliability & Recovery — active lane

### CLAIM `CHAT-2026-09-16-WORK-COMPUTER-RELIABILITY`

- Статус: **ACTIVE**
- Started from HEAD: `406f77695420818e874f99c64012be70fa0bf713`
- Режим: Chat
- Цель: довести Work и Computer Agent до production-ready lifecycle/recovery/safety baseline: детерминированные task states, restart/corruption recovery, idempotency/cancellation/retry policy, bounded Computer actions, capability/failure contracts, sandbox/master-stop/privacy boundaries и local-only normal path.
- Предполагаемый bump после зелёных acceptance-gates: **PATCH**; каноническую версию и Android versionCode этот lane не меняет — итоговый bump выполняет общий release/integration этап.
- Собственные файлы/подсистема: `work/work_manager.gd`, `work/work_store.gd`, `computer/computer_service.py`, `computer/install_computer.ps1`, `computer/requirements.txt`, `scripts/computer_client.gd`, новые `tests/work_reliability_*`, `tests/computer_agent_*`, `tests/work_computer_e2e_*`, новый `.github/workflows/work-computer-reliability.yml`, `docs/PROJECT_MASTER_LOG.md`.
- UI-граница: `work/work_overlay.gd`, `scripts/computer_overlay.gd`, `scripts/computer_overlay_compat.gd` и прочие UI-owned paths принадлежат `CHAT-2026-09-16-UI-POLISH` и этим lane не изменяются. UI-блокеры адресуются владельцу через `FROM/TO/TYPE/EVIDENCE/ACTION`.
- Общие safety/Core production paths (`scripts/agent_core.gd`, `scripts/tool_registry.gd`, autonomy/sandbox bridges) не изменять без воспроизводимого дефекта, повторной проверки свежего master log, свободы конкретного файла и доказанной необходимости; перед такой правкой сначала расширить эту запись evidence/ownership.
- Архитектурный инвариант: normal Work/Computer path = bundled AuroraFox Core + local planning + local Work state + local tools/Computer primitives. Ollama/OpenAI/Gemini/Claude/remote inference не обязательны и не являются normal Computer planner; интернет используется только конкретной задачей, которой нужна сеть.
- Acceptance: create/save/execute/progress/complete/restart/load; pause/resume/cancel/retry/failed/interrupted/partial; atomic resilient store + migration/dedup; invalid transitions rejected; safe/unsafe retry distinction; no blind destructive replay after uncertain result; Computer unavailable/timeout/malformed/permission/screenshot/platform failures не ломают chat; bounded calls; path traversal/symlink/command-injection/master-stop/untrusted-authority/privacy regressions; concurrency/stress; Windows contracts зелёные; Android Work + explicit unsupported Computer capability зелёный; physical Windows/Android gates отмечаются отдельно, если устройства недоступны; нет известного P0/P1 в собственном scope.

## 25. Integration Gate — routed findings and checkpoint, 2026-09-16
FROM: CHAT-2026-09-16-INTEGRATION-GATE
TO: CHAT-2026-09-16-UPDATER-VERSIONING
TYPE: BLOCKER
EVIDENCE: Integration Gate run `35087135629` on PR #32 merge SHA `54d7892d54d26a23a6d3e260cc294b130f1a6dbc`: all split candidate verification/safety/trust, API resilience, master-log and Large Knowledge contract/comparison steps were green, while `Updater repair and signed-floor compatibility contract` failed in `tests/test_core_candidate_promotion.py::test_signed_release_enforces_v12_repair_and_v13_signed_update_floor` with `AttributeError` because `test_update_backward_compat.test_manifest_template_is_legacy_readable_but_does_not_claim_legacy_direct_update` no longer exists. The updater claim also currently points to draft PR #29, but current PR #29 is `Harden candidate queue isolation and integrity; coordinate active work`, so that PR reference is stale/mismatched.
ACTION: Reconcile the release-compat bridge in `tests/test_core_candidate_promotion.py` with the current V1.2/V1.3 repair + V1.4 signed-floor compatibility contract and current function names, correct the updater CLAIM's branch/PR/commit reference, then rerun Core/Voice and Integration Gate. Do not weaken signature, pinned trust-root, repair-floor or version-discipline requirements.

FROM: CHAT-2026-09-16-INTEGRATION-GATE
TO: CHAT-2026-09-16-UI-POLISH
TYPE: NEXT
EVIDENCE: UI draft PR #27 head `f5eed5e30dfdd1657d1b864fc273ea83041bdc9e` adds a real visual acceptance matrix, but its own `.github/workflows/ui-visual-ci.yml` manifest check explicitly requires `known_missing_client_surfaces == {'login_guest', 'user_memory_management'}`. The coordinator acceptance table requires Windows/Android entry as login/guest plus memory management, while SERVER-DB already has account/guest isolation contracts.
ACTION: Implement and visually/structurally verify Windows + Android login and explicit guest entry/session UI plus user-memory management against the current SERVER-DB contract; extend UI smoke/capture evidence and preserve Account A/B + Guest A/B isolation. Coordinate API semantics with `CHAT-2026-09-16-SERVER-DB`; do not duplicate server implementation.

- Integration branch: `chat-2026-09-16-integration-gate`; draft PR #32.
- Gate branch synced without force to main through `62a59ed1af050c9a459e0556fd0ea1aabfef5411`; branch merge head before this journal checkpoint: `2add2f9d0ea49dd13e75be280114c5455fcb84bf`.
- Own gate changes remain limited to `.github/workflows/integration-gate.yml` and `tests/integration_release_readiness_contract.py`: aggregate same-SHA offline Core/Research lifecycle/Account isolation/Knowledge correctness + comparison + N/2N/4N scaling blockers/Voice diagnostics/API/candidate safety/Godot UI-Work smokes; independently owned OCR/Core-benchmark/Work-Computer artifacts are watched and become mandatory when they land.
- Previous run `35087135629` proved Godot cross-subsystem green and localized the updater blocker; the old Research failure in that run was an Integration Gate assertion drift, not a Research product regression, and the gate contract was updated to follow the current provenance-key contract.
- Physical Windows/Android devices and human visual/listen acceptance are still separate evidence boundaries and are not claimed by this CI gate.

## 26. Large Knowledge / Memory Performance — benchmark checkpoint, 2026-09-16

### `CHAT-2026-09-16-LARGE-KNOWLEDGE-PERF` — checkpoint

- Статус: **ACTIVE — correctness baseline green on Linux; reproducible performance blockers found; Windows benchmark portability revalidation in progress**.
- Base HEAD продолжения: `612c834b6e41747b3219675ce314b1a472502f20`; исходный CLAIM начат от `41acd5781d34719c9b257990b40f976e3dd04eb0`.
- Benchmark/CI commits этапа: `c887c02fcdbe89d3dd9dede9c07f19c5f0444d06` (machine-readable performance validator), `8cf55e08c9cacd65173ab51f8f48e916a14e8052` (persistent MemoryStore N/2N/4N), `f7369daa13b1215cf60528ca9802a7519de40d26` (Knowledge search N/2N/4N), `5e083c9ad29c65ecf34e297e0b1d316c2e103b87` (stress-gate unit contract), `5add40f16248db9c84517eecc3402fd78a500d2d` (CI relative blockers), `b1cc2d311fcd9eb334b40045686df00471f23a25` + `753cbfec1154159fed336c839246260c7fbeebbc` (portable benchmark-only Windows execution; production scripts unchanged).
- Проверки/correctness: Knowledge Performance run `35086858965`, standard-linux job `104763758491` на `406f7769...` — **SUCCESS**, artifact `10442019189`, digest `sha256:c16a5a8d62d0eb48934d41ca24fb8906891f9217b88c353ca98bf4421c3ab8ba`; повторный run `35087303702`, standard-linux job `104768474785` на `612c834b...` — **SUCCESS**, artifact `10443391589`, digest `sha256:1560964f727c26efafba836658e6f4f5cb39614bd79cf32b18c684b964801ac5`. Hard correctness в обоих: import/search correctness, dedupe, A+B+C source removal, rollback, process restart, concurrent import, Unicode/long path и self-reliance пройдены.
- Reproducible scaling blocker: первый standard run 8→16→32 sources по 32 KiB = `192.191 → 658.727 → 2402.870 ms`, ratios `3.427× / 3.648×`; независимый повтор = `295.399 → 1134.908 → 4412.655 ms`, ratios `3.842× / 3.888×`. Это воспроизводимый near-quadratic cumulative import path, не runner-noise.
- 10 MiB evidence: JSONL import ~`4.7–5.7 s`, CSV ~`4.8–5.8 s`, TXT ~`2.9 s`, streaming monolithic JSON ~`9.2–11.4 s`; search correctness остаётся зелёным, но p95 на 10 MiB обычно ~`0.8–1.2 s`, long-query до ~`1.8–3.0 s`. Absolute CI latency пока информационная; relative scaling gate теперь отдельный.
- Rollback evidence: malformed ~10 MiB import откатывает прежнее валидное состояние/fingerprint и не оставляет partial source; в первом standard run rollback ~`8.93 s`. Dedupe repeat/same-bytes renamed alias не раздувает chunks; changed source создаёт revision 2. Concurrent 1 MiB+1 MiB import в измеренном Linux run завершился без corruption. Local semantic MemoryStore 250 records: write ~`1.18 s`, local index ~`72 ms`, search ~`15 ms`, restart ~`8 ms`, provider `aurorafox_local_vector`, `network_required=false`, `external_runtime_required=false`, `ollama_required=false`.
- Memory/RAM: 10 MiB cases показывают raw process peak порядка `115–119 MiB`, но это включает базовый Godot process; новый `run_memory_scaling.py` измеряет baseline-adjusted RSS и write/index N/2N/4N, чтобы не выдавать raw RSS/dataset ratio за streaming leak.
- Android: machine-readable contract фиксирует bounded/incremental/private-storage/no-mandatory-external-service требования и `physical_device_proof=false`; desktop CI **не** считается Android device proof.
- Windows: run `35087303702`, smoke-windows job `104768475000` упал до сценариев с benchmark-only parse `Could not resolve external class member "import_file"` на fresh Windows Godot. Production project/editor parse был green. Для устранения test-infra расхождения добавлен portable runtime copy с Variant-typed preloaded script handles (`b1cc2d31...`, workflow `753cbfec...`); новый exact run должен подтвердить Windows, прежде чем считать Windows доказанным.

FROM: CHAT-2026-09-16-LARGE-KNOWLEDGE-PERF
TO: CHAT-2026-09-16-LOCAL-OCR
TYPE: PERFORMANCE-BLOCKER
EVIDENCE: Knowledge Performance standard-linux `35086858965/104763758491` artifact `10442019189` и повтор `35087303702/104768474785` artifact `10443391589`: 16→32 small-source import ratios `3.648×` и `3.888×`; 10 MiB JSONL/CSV search p95 около секунды. Static audit показывает в OCR-owned `scripts/knowledge_store.gd` unconditional source filtering before new imports и record/chunk append с repeated file open/close; этот lane файл не меняет.
ACTION: В рамках `LOCAL-OCR` при следующем безопасном изменении `scripts/knowledge_store.gd` убрать лишний full-store source rewrite для заведомо нового source и ввести безопасный batch/session append для streaming records/chunks без ослабления transaction rollback/untrusted metadata/dedupe. Затем rerun тот же 8/16/32 benchmark + dedupe/removal/rollback; не маскировать увеличением timeout.

FROM: CHAT-2026-09-16-LARGE-KNOWLEDGE-PERF
TO: CHAT-2026-09-16-UI-POLISH
TYPE: PERFORMANCE-BLOCKER
EVIDENCE: те же standard Linux artifacts: один 10 MiB direct import занимает примерно `2.9–11.4 s` до возврата; `scripts/knowledge_base_overlay.gd` вызывает direct `learn_from_file()` внутри `_import_one()` синхронно и делает `process_frame` только после завершения файла. На крупном source это потенциальный main-thread freeze; полноценный storage-level cancel не доказан.
ACTION: Сохранить responsive UI/progress на large import и сделать cancel/error path явным и безопасным; не менять Knowledge transaction semantics. Проверить UI profiler/smoke на искусственном крупном source после интеграции storage fixes.

- Новые hard/relative gates: absolute hosted-runner timing остаётся informational; CI теперь может падать на hard correctness/self-reliance и на воспроизводимый `suspected_quadratic`/MemoryStore quadratic-write/search superlinear N→2N finding вместо расширения timeout.
- Следующий шаг этого lane: проверить exact Knowledge Performance run после `753cbfec...`; забрать MemoryStore 125/250/500 и search 1/2/4 MiB reports. Если MemoryStore подтверждает near-quadratic write, исправить только теперь claimed свободный `scripts/memory_store.gd`; затем адресно оптимизировать свободные `knowledge_import_transaction.gd`/registry paths, сохраняя rollback/restart/dedupe correctness. `scripts/knowledge_store.gd` не трогать до освобождения `LOCAL-OCR`. После исправлений повторить comparable N/2N/4N, Windows smoke и 100/250 MiB memory pressure; физический Android stress остаётся отдельным честным gate.
- Освобождённые файлы: нет; benchmark/test/workflow paths и три performance-follow-up production paths остаются занятыми этим ACTIVE CLAIM до завершения acceptance.

## 27. Integration Gate — Knowledge alias removal correctness blocker, 2026-09-16
FROM: CHAT-2026-09-16-INTEGRATION-GATE
TO: CHAT-2026-09-16-LARGE-KNOWLEDGE-PERF
TYPE: BLOCKER
EVIDENCE: Knowledge Performance run `35104043312`, Linux smoke job `104820545932` on exact main `dd759df6727aafb7decb32055b79cdd29d1a6333`, and follow-up run `35104450053`, Linux smoke job `104822834774` after main `053e6b77c91bffd18969f6890dd3ec724f095dab`, both reproduce `benchmarks/knowledge/dedupe_alias_removal_probe.gd` with return code 3 after successful Godot project parse. Fresh artifact `10449956878` reports `alias_detached=true` but `canonical_survived=false`, `canonical_registry_after=false`, `post_remove_searchable=false`; remove result reports `removed=128`, `structured_removed=128` while deleting only the alias path. The intended contract is `removing an alias/copy must not delete the canonical shared knowledge`.
ACTION: Fix alias/canonical ownership and source-removal semantics within `CHAT-2026-09-16-LARGE-KNOWLEDGE-PERF` owned/free paths so removing a renamed duplicate only detaches that alias and preserves the canonical registry entry plus searchable canonical records. Do not weaken/remove the probe. If the root cause requires OCR-owned `scripts/knowledge_store.gd`, coordinate an explicit handoff with `CHAT-2026-09-16-LOCAL-OCR` instead of editing the claimed file. Rerun the alias probe plus dedupe/source-removal/rollback/restart correctness and Integration Gate on the same SHA.

- Integration Gate draft PR #32 remains limited to `.github/workflows/integration-gate.yml` and `tests/integration_release_readiness_contract.py`; current branch head at this checkpoint is `26bdd07ccc1a4c085ecfabc75a8dc1b514c93240`.
- Gate now executes landed Research collector privacy contract/smoke and the Knowledge alias-removal safety probe. Godot follow-up smokes, headless UI regression and diagnostics artifact upload use `if: always()` so one subsystem failure cannot hide later integration evidence.
- Existing updater BLOCKER remains independently reproducible on main Core/Voice run `35104043311`: `tests/test_core_candidate_promotion.py::test_signed_release_enforces_v12_repair_and_v13_signed_update_floor` still calls an obsolete update-compat test function; ownership remains `CHAT-2026-09-16-UPDATER-VERSIONING` and its production files are untouched.
- Windows Knowledge smoke failure on `dd759df...` is the already-known benchmark portability class-resolution issue documented by the Large Knowledge lane, not a new routed product blocker; no duplicate address record was added.
- Physical Windows/Android device tests and human visual/listen acceptance remain separate gates and are not inferred from CI.

## 28. Integration Gate — Work/Computer UI contract blocker, 2026-09-16

FROM: CHAT-2026-09-16-INTEGRATION-GATE
TO: CHAT-2026-09-16-UI-POLISH
TYPE: BLOCKER
EVIDENCE: Draft Work/Computer PR #40 head `23a0c26c1a8c1125ee997d4c8bf912080e575fb1` changes `scripts/computer_client.gd` so `plan()` and `run()` intentionally return `local_core_planning_required`; planning authority moves to bundled AuroraFox Core/AgentCore -> ToolRegistry primitives and Computer control is guarded by `ComputerClient.set_computer_control_enabled(...)`. Current main `scripts/computer_overlay.gd` blob `a9090613b07aa973dff43ffb1e27b10b93fcb6a6` still implements `execute_goal()` via `await computer.run(...)`, `preview_next_action()` via `await computer.plan(...)`, and its UI toggle changes only local `enabled`. Merging PR #40 with that overlay unchanged would make the visible high-level Computer goal/preview flow fail by contract and would not propagate the user permission toggle into the hardened ComputerClient.
ACTION: In the UI-owned `scripts/computer_overlay.gd`/compat surface, route high-level Computer goals through bundled AuroraFox Core/AgentCore -> ToolRegistry Computer primitives instead of `ComputerClient.run()/plan()`, wire the user Computer toggle to `ComputerClient.set_computer_control_enabled(enabled)` with default-OFF/master-stop behavior preserved, and extend UI smoke for enable/disable + high-level goal routing. Coordinate against `CHAT-2026-09-16-WORK-COMPUTER-RELIABILITY` PR #40; do not restore service-side planning or add any external-AI planner. Do not merge the Work/Computer contract into release-ready main until this cross-lane interface is reconciled and same-SHA Work/UI integration is green.

## 29. Integration Gate — CodeSpecialist self-reliance/startup blocker, 2026-09-16

FROM: CHAT-2026-09-16-INTEGRATION-GATE
TO: CHAT-2026-09-16-CORE-BENCHMARKS
TYPE: BLOCKER
EVIDENCE: UI PR #27 Work Mode run `35110015157`, job `104840973538`, merge SHA `ac3037dfe17a0d5f0bc0be7511f7b2a54b26570b`: project parse and WorkStore smoke pass, then `tests/work_mode_smoke.gd` fails at `CodeSpecialist.setup` with `Invalid access to property or key 'base_url' on a base object of type 'Node (AIClient)'`; the UI branch does not modify `scripts/code_specialist.gd`. Fresh main `04452ca738f7d39ef3da58f2179fe4a0a46e5d8a` still uses `scripts/code_specialist.gd` blob `811a5117543ad7300e74ca82a33e5ee3632fcb0f`, where `setup()` reads removed `ai_client.base_url` and normal `_chat_code()` creates a direct `HTTPRequest` to the Ollama `/api/chat` path using `qwen3-coder:30b` before falling back to `general_ai.chat()`. Integration PR #32 commit `a2fc9876235679c774a570aec74eadba04107037` adds `test_code_specialist_normal_path_is_bundled_core_only()` to lock this startup and self-reliance regression.
ACTION: In the currently unclaimed `scripts/code_specialist.gd` path, remove the stale `AIClient.base_url` dependency and make normal CodeSpecialist analyze/review/explain generation delegate to `AIClient.chat()` / bundled AuroraFox Core. Any Ollama/provider-specific behavior must remain behind an explicit compatibility-only API and never precede the normal Core path. Extend the Core benchmark/smoke evidence for code-specialist behavior offline, then rerun Work Mode, Core/Voice, real-Core benchmark and Integration Gate on the same SHA. Do not restore a mandatory external coder model or remote/provider fallback.

## 30. Integration Gate — Knowledge alias removal blocker resolved, 2026-09-16

FROM: CHAT-2026-09-16-INTEGRATION-GATE
TO: CHAT-2026-09-16-LARGE-KNOWLEDGE-PERF
TYPE: READY
EVIDENCE: Knowledge Performance run `35105876229` on exact main `35275e4c3a6b5cc7b3fa67f0aaebef84e43a903e` (`fix: detach knowledge aliases without deleting canonical source`): contract job `104826816228` SUCCESS; Linux smoke job `104835749250` SUCCESS including `Reproduce dedupe alias removal safety`; standard Linux job `104835749257` SUCCESS. This is the same production fix and same deterministic alias-removal probe that previously reproduced canonical data loss in section 27. The workflow's overall conclusion remains failure only because separate Windows smoke job `104835749449` failed its bounded Windows benchmark; that does not invalidate the Linux runtime proof for alias/canonical removal semantics and remains an independent Large Knowledge portability gate.
ACTION: Section 27 alias-removal correctness blocker is closed. Preserve the deterministic alias-removal probe in Knowledge Performance and Integration Gate, and keep Windows portability, interrupted-recovery, registry-scaling and remaining performance gates active independently. Re-run the alias probe again on the final release candidate SHA before release readiness is declared.

## 31. Large Knowledge / Memory Performance — durability and scaling checkpoint, 2026-09-16

### `CHAT-2026-09-16-LARGE-KNOWLEDGE-PERF` — checkpoint
- Статус: **ACTIVE — Linux correctness/scaling baseline подтверждён; durability hardening интегрирован; Windows/record-dedupe/registry-only/100–250 MiB exact runtime evidence ожидается**.
- Каноническая версия остаётся **V1.3.0.0**; предполагаемый итоговый bump lane — **PATCH** только после зелёных acceptance-gates. Этот checkpoint версию и Android `versionCode` не меняет.
- Последний доказанный exact Linux baseline: Knowledge Performance run `35105876229` на `35275e4c3a6b5cc7b3fa67f0aaebef84e43a903e`; contract `104826816228` SUCCESS, smoke-linux `104835749250` SUCCESS, standard-linux `104835749257` SUCCESS. Standard artifact `10453990990`, digest `sha256:1cfe0f08f35ef4605e9b5c7c1679ac09409140d0aefae795146b4a4254c9d88b`.
- Alias/canonical correctness: Integration Gate section 30 перевёл прежний blocker в **READY** на том же exact Linux runtime; alias-removal probe сохраняется обязательным regression-gate.
- Текущий many-source baseline после уже внесённых performance fixes: 8→16→32 sources по 32 KiB = `134.868 → 410.054 → 1370.210 ms`, ratios `3.040× / 3.342×`. Формальный `>=3.5×` quadratic blocker на этом run не сработал, но накопительный путь остаётся тяжёлым; добавлен отдельный registry-only 16/32/64 gate, чтобы не приписывать весь остаток `KnowledgeStore` без измерения.
- Persistent MemoryStore scaling на этом artifact: 125→250 durable write `1.971×`, 250→500 `2.024×`; semantic index/flush также около 2×. Ранее найденный MemoryStore quadratic-write blocker **закрыт измерением**, не только static code review.
- Knowledge search N/2N/4N: 1→2 MiB selected p95 `1.971×`, 2→4 MiB `2.027×`; superlinear blocker не воспроизведён. Absolute hosted-runner latency остаётся informational и не превращена в хрупкий fixed threshold.
- 10 MiB format baseline на этом run: JSONL `5553.733 ms` (~`1.801 MiB/s`), CSV `5726.309 ms` (~`1.746 MiB/s`), TXT `2911.180 ms` (~`3.435 MiB/s`), streaming monolithic JSON `11377.462 ms` (~`0.879 MiB/s`). Malformed ~10 MiB rollback восстановил committed state за `8372.334 ms`. Concurrent import и self-reliant semantic memory прошли.
- Durability hardening commits: `1787ac73e93c566e3f5da7058a964b0bbc793560` — retry-safe import recovery/durable phases; `28920d7a3f8d30baeec35da81b604b5a56222c1c` — crash-safe `sources.json` replacement; `c437cdcded27886868c77dca9a0a8116d4d699ef` + `e177b5564f9a44b26c6737b683d5ee0fd9b20a78` — same-isolated-profile Windows warm-up для generic/interrupted probes.
- Canonical source removal теперь также transaction-scoped без изменения OCR-owned `scripts/knowledge_store.gd`: `84c4235ec9a592593fb1bd892bd47d49cd983892` + `c7e8568b7634e09e81489771e8a1e9f277b23081` добавляют real process-kill removal probe/runner; `ec3f0937308b11de2983a59284472da6b4c795f2` добавляет `KnowledgeImportTransaction.remove_source()` с snapshot → Store remove → registry remove → durable commit marker / rollback; `83dde9ae4b38700219d645d09892240640cdd9c1` переводит canonical `KnowledgeManager.remove_source()` на этот transaction; `fac6a648765a70baa89cb7bbdf885a08bb7f789b` фиксирует contract; `2781b303cb2e0e0a2cda84eed2c3a922e043eabe` включает interrupted-removal gate в Linux+Windows smoke.
- Record dedupe / registry isolation: `7bbac6da522f01f868a5237b48f2b3c2959648bd` добавляет same-source/cross-source shared-record lifecycle probe; `5d57b1a3f105f2d6d6f046be12adb39e2463b343` + `d03c64987ed3238c81b2df760bf0d0356cd190bf` добавляют registry-only scaling; `792c49d8cef2b0c6f25a61d032077d3879ffccd9`, `eb1de38a5e462955f409a2f7cde49a474f462ae5`, `d2065b210cbed79b167f72f7f97d4f88f4a82f86`, `9dee5e9d555eea39f6019f69ba28082bf454c9d8` включают relative blocker, workflow wiring и regression contracts.
- **Не считать пройденными до artifact:** exact-head Knowledge run `35117014347` на `2781b303...` в момент checkpoint всё ещё QUEUED; therefore transactional removal process-kill, current Windows portability, current record-level dedupe и registry-only scaling ещё не имеют runtime verdict. `[knowledge-large]` run `35112699152` также остаётся QUEUED; 100/250 MiB memory-pressure acceptance ещё не доказан.
- Static audit OCR-owned `scripts/knowledge_store.gd` показывает потенциальный record-dedupe риск: structured identity включает `record_path`, а normalized `_append()` не делает persisted-ID check. Это **не объявляется runtime blocker без probe artifact**. Файл не изменялся этим lane; `CHAT-2026-09-16-LOCAL-OCR` остаётся владельцем.
- Android: machine-readable bounded/private/local-only contract сохраняется; `physical_device_proof=false`. Desktop/Linux/Windows CI не выдаётся за Android device proof.
- Следующий шаг: первым делом забрать `35117014347` и `35112699152`. Если record-dedupe probe падает — передать точный `PERFORMANCE-BLOCKER` владельцу `CHAT-2026-09-16-LOCAL-OCR` с run/job/artifact и требованием content-based within-source dedupe без потери provenance/shared-source removal. Если registry-only doubling `>=3.5×` — исправить свободный registry path и повторить 16/32/64. Если interrupted-removal падает — исправлять только transaction/manager/recovery path. После этого закрыть Windows current-runtime proof и 100/250 MiB stress; OCR 100-page scanned/mixed stress добавлять только после интеграции `LOCAL-OCR`.
- Освобождённые файлы: нет; `benchmarks/knowledge/**`, related Knowledge performance/stress tests/workflow, `scripts/knowledge_import_transaction.gd`, `scripts/knowledge_source_registry.gd` и performance-follow-up `scripts/memory_store.gd` остаются в ACTIVE CLAIM. `scripts/knowledge_store.gd` по-прежнему не трогать до освобождения `LOCAL-OCR`.

## 32. Large Knowledge / Memory Performance — Wave-B resilience preparation, 2026-09-16

### `CHAT-2026-09-16-LARGE-KNOWLEDGE-PERF` — checkpoint

- Статус: **ACTIVE — benchmark/CI-only Wave-B пакет собран; runtime gate удерживается координатором до завершения UI Wave A**.
- Base HEAD подготовки: `ab2103acf6667eb3812f969b4c926902a37ccece`; перед этой записью свежий `main` проверен до `1e9503537493b9cdd29d164005d3a12c3b59e17f`. Изменения между ними не затрагивают Knowledge-owned paths этого пакета.
- Branch: `chat-knowledge-races-v2-20260916`; draft PR #64 существует, но **временно CLOSED без merge** по явному coordinator CI wave control. Coordinator comment `5702362208`: продолжать эту же ветку, не создавать replacement PR, закончить consolidated race/scaling/failure-injection batch и переоткрыть **тот же PR #64** только после сигнала Wave B.
- Commits текущего пакета: `886ae50eaabf889c8822d6d87c4642bcee441f92` — deterministic duplicate-import + search/remove race proof; `d11b9f59e72f85e6f659b9948f3d3379339d87ba` + `e5562e6f6f9135cce7466047e280703803abaffe` — consolidated resilience runner; `180680bfd125ba7b463cf799d2c93dca47f983f0` — isolated Windows profile warm-up для registry scaling; `1ee5beb6d641b305b135f81b2aa865c186c68e88`, `242a4d83dcb6a05a3aba8868a219216b9cbfb5d4`, `4c43a503b23df85bca23e4c8734961ea97fb3265` — regression contracts; `e1ba76e35f96d2cd3bb25bd0ca4100c4f55c680f` + `5d3719421aeaf77e48155e1c2c6360ed3d3cdae4` — isolated Linux/Windows resilience workflow.
- Consolidated batch одним machine-readable JSON объединяет: concurrent byte-identical import; search + canonical remove race; record-level/shared-source dedupe; alias-preservation; legacy pre-registry rollback; registry write-failure rollback; truncated registry temp rejection; real process-kill interrupted import recovery; real process-kill interrupted removal recovery; registry N→2N→4N scaling. Self-reliance contract фиксирует `network_required=false`, `external_runtime_required=false`, `ollama_required=false`; absolute hosted-runner timings остаются informational, registry quadratic finding является relative blocker.
- Windows benchmark infrastructure дополнительно выровнена с существующим portable contract: `run_registry_scaling.py` теперь прогревает тот же isolated Windows Godot profile до запуска probe, чтобы ранее известный fresh-profile class-resolution дефект не выдавался за production scaling regression.
- Production code этим пакетом **не изменялся**. В частности, OCR-owned `scripts/knowledge_store.gd` не трогался. Static audit показывает, что duplicate-import сериализуется `KnowledgeImportTransaction` static mutex; потенциальный Windows search/remove риск остаётся на стыке открытого reader и file replacement в OCR-owned Store и не объявляется blocker без runtime artifact.
- Старый auxiliary run `35133333541` на раннем head `1a6e2b8b...` остался QUEUED после coordinator closure и **не считается green/runtime evidence**. Новый consolidated batch ещё не запускался из-за Wave-A CI control.
- Каноническая версия остаётся **V1.3.0.0**; intended lane bump по-прежнему **PATCH только после acceptance**, Android `versionCode` не менялся.

PROGRESS_COMPLETE: 82%
PROGRESS_REMAINING: 18%

DONE:
- Доказанный Linux baseline, alias correctness, near-linear MemoryStore/search scaling и прежние durability fixes остаются валидным baseline section 31.
- На текущей Wave-B ветке собран единый race/scaling/failure-injection пакет, отдельный Linux/Windows workflow и machine-readable aggregate verdict; production-файлы не затронуты.
- Добавлены duplicate-import и search/remove concurrency proofs, Windows isolated-profile warm-up для registry scaling и fail-closed regression contracts.
- Coordinator wave-control соблюдён: новый replacement PR после закрытия #64 не создавался, #64 не переоткрывался самовольно.
REMAINING:
- После coordinator Wave-B signal переоткрыть **тот же PR #64** и получить exact Linux + Windows artifacts для consolidated resilience batch.
- Если runtime выявит дефект в `knowledge_import_transaction.gd`/registry — исправить в этом CLAIM и повторить exact batch; если root cause потребует `scripts/knowledge_store.gd`, оформить точный `PERFORMANCE-BLOCKER` в `CHAT-2026-09-16-LOCAL-OCR`, не менять занятый файл.
- После same-SHA green resilience evidence интегрировать пакет без ослабления relative gates и запустить существующий `[knowledge-large]` main stress path для 100/250 MiB memory-pressure evidence.
- Записать финальные run/job/artifact/digest, timings/RSS и Android physical-device limitation; только после этого закрывать CLAIM/освобождать пути.

BLOCKERS:
- `COORDINATOR CI WAVE CONTROL`: PR #64 временно закрыт до завершения UI Wave A; evidence — PR #64 comment `5702362208`. Это scheduling blocker, не code failure.
- Runtime verdict нового consolidated batch отсутствует по той же причине. `35133333541` остаётся queued и не является доказательством прохождения.
- Потенциальный cross-lane blocker в OCR-owned `scripts/knowledge_store.gd` объявлять только если search/remove или record-dedupe probe воспроизведёт его на runtime.

NEXT:
- Сохранять `chat-knowledge-races-v2-20260916` без нового PR и синхронизировать только при релевантном Knowledge overlap. На coordinator Wave-B signal переоткрыть PR #64, выполнить consolidated Linux/Windows batch, разобрать JSON artifacts и либо исправить доказанный owned-path defect, либо выписать точный OCR `PERFORMANCE-BLOCKER`; после green same-SHA evidence запустить 100/250 MiB stress gate.

- Освобождённые файлы: нет; CLAIM остаётся ACTIVE до runtime/large-stress acceptance.

## 33. Voice Quality — Android female local TTS candidate, 2026-09-16

### `CHAT-2026-09-16-VOICE-QUALITY` — ownership extension

- Статус: **ACTIVE — coordinator acceptance; Android female TTS candidate isolated before integration**.
- Fresh main checked through: `b6cdcaa76f51649ffa1f0302fc987ee05b17e423`; existing voice coordinator acceptance remains under the same CLAIM and intended bump remains **PATCH** only after relevant green gates.
- Ownership extension for this substage: `android_plugin/plugin/src/main/java/com/aurorafox/runtime/AndroidVoiceRuntime.kt`, `android_plugin/setup_native.ps1`, `tests/test_android_contract.py`, plus already claimed voice acceptance files. `android_plugin/plugin/build.gradle.kts`, `android_plugin/settings.gradle.kts`, `AndroidFileRuntime.kt` and OCR/package metadata remain owned by `CHAT-2026-09-16-LOCAL-OCR` and must not be modified by VOICE-QUALITY.
- Evidence/blocker: current Android local TTS packages `vits-piper-ru_RU-denis-medium` and reports `sherpa-onnx-piper-denis`; this is a male voice and therefore does not satisfy the coordinator requirement for Russian female voice evidence on both platforms. Current Android package/install/launch proof validates the local Piper path but not that requirement.
- Candidate selection: Piper `ru_RU-irina-medium` is not accepted for a distributable AuroraFox baseline because its upstream model metadata leaves the dataset/license status unclear. Supertonic 3 is evaluated instead as a fully local ONNX candidate. The existing pinned `sherpa-onnx 1.13.4` already contains `OfflineTtsSupertonicModelConfig`, so this candidate does **not** require touching OCR-owned Gradle/settings or changing the sherpa version.
- Speaker mapping is deterministic in sherpa v1.13.4: its `generate_voices_bin.py` sorts `*.json` filenames before packing them, so `F1..F5` are `sid 0..4` and `M1..M5` are `sid 5..9`. The current Supertonic 3 int8 model payload is about 145 MiB and supports Russian via generation `extra["lang"] = "ru"`; exact packaged size/RSS/startup/RTF remain acceptance measurements rather than assumptions.
- Licensing/supply boundary: the Supertonic model card states an OpenRAIL-M model license while the sherpa mirror also carries upstream code/license material. Candidate testing may proceed, but a release must preserve the applicable upstream model license/notice and must not silently download a required TTS model at normal runtime. Model assets must be bundled/staged by the build, with integrity validation added before acceptance.
- Acceptance for this substage: create a separate branch from fresh `main`; stage the Supertonic int8 assets without OCR Gradle/settings changes; synthesize the same Russian persona/number/unit phrases with **all F1–F5** on Android/emulator-capable tooling; record duration/RTF, peak/clipping, ASR round-trip and package/model footprint; select a female speaker from measured evidence, not by name alone; then require Android voice contract + APK build/sign/install/launch and a real TTS invocation that produces a WAV. Physical-device human listening remains an explicit separate gate if no real Android device is available.
- Next step: create the isolated Android female-voice candidate branch from the freshest main, change only the newly reserved Android voice files/tests, and reject the candidate if it materially регресes intelligibility, clipping, latency/memory/package limits or local-only operation.

## 34. Integration Gate — release-train delta and routed status, 2026-09-16

- Fresh release-train code checkpoint: `cc44cce8f1d3ccc97a5d4ef3bba9cc9c6efb7b4b` (`test: tighten integration updater and branding gates`) on parent `5bca4a1353ff66731073515533414ab1d0369e15`. Integration-owned changes only: `.github/workflows/integration-gate.yml` and new `tests/test_release_branding_contract.py`; production UI/Core/updater files and canonical version were not modified.
- Integration workflow stale updater selector was corrected to `test_signed_release_enforces_v12_v13_repair_and_v14_signed_update_floor`, matching updater fix commit `99b2c144dbeb675caafb527ad528f5db18a32b50` and current `tests/test_core_candidate_promotion.py`.
- Owner-approved immutable branding source masters are now release-gated by Git blob identity: `assets/ui/aurorafox_avatar_master.png` = `89ff783b171733f88b5153acd24c6a28fb2953dd`; `assets/ui/aurorafox_background_master.png` = `ed17e933244b7ce0f520b28897c0ca1ad50a5347`. The contract also requires runtime use of those paths and forbids active legacy `fox_logo.svg` / `aurora_background.svg` substitution.
- Exact-head Integration Gate run `35147689311` on `cc44cce8...` remains **PENDING** with no jobs at this checkpoint; it is explicitly not green evidence. Exact-head Updater Repair Validation run `35147697509` remains **QUEUED**. Per coordinator NO-QUEUE policy no duplicate rerun was started.
- Current `scripts/code_specialist.gd` after `6cfa3316e6837a175cecdd79fd0ecc4b0e4ca393` no longer reads `AIClient.base_url` or directly calls Ollama in the normal path; `_chat_code()` delegates to `general_ai.chat()`. This is static fix evidence only; section 29 is not closed until runtime/real-Core proof is green.

FROM: CHAT-2026-09-16-INTEGRATION-GATE
TO: CHAT-2026-09-16-UI-POLISH
TYPE: BLOCKER
EVIDENCE: Exact main checkpoint `cc44cce8f1d3ccc97a5d4ef3bba9cc9c6efb7b4b` contains byte-exact owner masters above, while active runtime `scripts/main.gd` still preloads `res://assets/ui/aurora_background.svg` and `res://assets/ui/fox_logo.svg`. Integration commit `cc44cce8...` adds `tests/test_release_branding_contract.py` and the `Owner-approved branding identity contract` step so this mismatch cannot silently ship. Run `35147689311` is still pending, therefore this blocker is based on deterministic source/runtime mismatch, not a claimed CI failure.
ACTION: In UI-owned runtime/package surfaces, make Windows and Android use `assets/ui/aurorafox_avatar_master.png` and `assets/ui/aurorafox_background_master.png` as the active canonical branding without modifying their source bytes; remove legacy `fox_logo.svg` / `aurora_background.svg` from active runtime substitution. If any derived platform asset is unavoidable, prove exact-pixel identity from the canonical master and keep the master bytes unchanged. Extend UI/package smoke/capture evidence and rerun Integration Gate on the same resulting SHA.

FROM: CHAT-2026-09-16-INTEGRATION-GATE
TO: CHAT-2026-09-16-UPDATER-VERSIONING
TYPE: NEXT
EVIDENCE: Updater bridge selector drift from section 25 is statically reconciled by updater commit `99b2c144dbeb675caafb527ad528f5db18a32b50` plus integration commit `cc44cce8f1d3ccc97a5d4ef3bba9cc9c6efb7b4b`; current composite function name and Integration workflow selector both target the V1.2/V1.3 repair + V1.4 signed-floor contract. Exact-head Integration run `35147689311` is PENDING and Updater Repair Validation `35147697509` is QUEUED, so runtime acceptance is not yet proven.
ACTION: Do not reopen the stale function-name fix. Keep section 25 runtime blocker open only until an exact-head updater compatibility step plus repair/signing validation is green; preserve V1.2/V1.3 repair, pinned trust root and V1.4 signed floor without weakening signing/version discipline.

FROM: CHAT-2026-09-16-INTEGRATION-GATE
TO: CHAT-2026-09-16-CORE-BENCHMARKS
TYPE: NEXT
EVIDENCE: CodeSpecialist production fix `6cfa3316e6837a175cecdd79fd0ecc4b0e4ca393` removes the stale `AIClient.base_url` access and direct normal-path Ollama `/api/chat` call; current `scripts/code_specialist.gd::_chat_code()` delegates to `general_ai.chat()`. Exact runtime Work Mode / real bundled-Core CodeSpecialist proof after this fix has not yet been accepted by Integration Gate.
ACTION: Preserve the bundled-Core-only CodeSpecialist path, add/retain a real bundled-Core CodeSpecialist smoke/benchmark, and close section 29 only with same-SHA runtime evidence that setup + analyze/review/explain work without Ollama/remote AI.

FROM: CHAT-2026-09-16-INTEGRATION-GATE
TO: CHAT_MAIN-2026-09-16-RESEARCH-QUALITY
TYPE: READY
EVIDENCE: AuroraFox Research Quality CI run `35112565080` on exact SHA `adb5ae35b19b2e5412b565133c820d3be7d1437c` completed SUCCESS. The landed Integration Gate retains Research evidence-lifecycle, collector-privacy and source-resilience contracts/smokes so future cross-subsystem regression remains covered.
ACTION: Coordinator-authorized Research source-resilience acceptance is satisfied. Mark the Research lane DONE/free its production/test paths unless a newer coordinator assignment exists; preserve collector→curator single-authority, provenance/privacy and source-resilience coverage in the final release candidate gate.

PROGRESS_COMPLETE: 66%
PROGRESS_REMAINING: 34%

DONE:
- Integration workflow/test infrastructure is on main and its stale updater selector is corrected.
- Byte-exact canonical branding release contract is on main and routes the current runtime mismatch to UI ownership.
- Research Quality source-resilience gate has exact successful run evidence and is routed READY.
- Updater and CodeSpecialist old findings are separated into static-fix vs runtime-acceptance status rather than being falsely marked green.

REMAINING:
- Obtain a non-pending exact-head Integration Gate run after queue wave execution and triage each step independently.
- Obtain exact updater repair/signing validation before closing section 25.
- Obtain real bundled-Core CodeSpecialist runtime evidence before closing section 29.
- Recheck UI branding/login-guest/memory/Work-Computer fixes after UI lane lands, then Windows/Android package/device boundaries and final release matrix.

BLOCKERS:
- UI canonical branding mismatch is a current source/runtime release blocker.
- Integration run `35147689311` and updater repair run `35147697509` are queued/pending and therefore cannot be counted as green.
- Physical Windows/Android device + human visual/listening acceptance remains a separate evidence boundary.

NEXT:
- Follow coordinator CI wave control without duplicate reruns. On the next executable exact-main gate, inspect updater, branding, Research, Work/Computer, Core/CodeSpecialist, Account/Guest, OCR, Voice and package steps separately; route only reproducible failures to the exact owning CLAIM and do not change their production files.

## 35. Integration Gate — UI candidate regressions and handoff, 2026-09-16

- Integration-owned branding contract follow-up commit: `b19719bdb4b88cbafbd07310ed34330c6c80660e` (`test: validate branding through active UI runtime`). The gate still pins both owner-master Git blobs byte-for-byte, but now validates the actual product entrypoint `main.tscn -> scripts/main_compat.gd` and permits legacy base placeholders only when the active compatibility layer replaces/removes them before final UI rendering. This avoids a false failure for the UI candidate architecture without weakening owner-art identity.
- Exact-main Integration Gate run `35148889897` on `b19719bd...` is **PENDING**; no manual duplicate rerun was started under coordinator NO-QUEUE policy.
- UI PR #27 remains draft at head `987f5bd0e23b4895daae60f7fa26fa28c2023c5b`, `mergeable=false`, and is still based on pre-integration main `5bca4a1353ff66731073515533414ab1d0369e15`; it must be reconciled non-force before merge.

FROM: CHAT-2026-09-16-INTEGRATION-GATE
TO: CHAT-2026-09-16-UI-POLISH
TYPE: BLOCKER
EVIDENCE: UI Visual CI run `35147641336`, job `104967664697`, on UI PR #27 head `987f5bd0e23b4895daae60f7fa26fa28c2023c5b`: `Parse UI project headlessly` succeeded, then `Run headless layout interaction smoke` failed with exit code `66` and the exact assertion `Portrait owner background is not right-biased`. All downstream owner-art/navigation/render-matrix steps were skipped. The candidate `scripts/main_compat.gd::_owner_background_texture()` derives its crop from `get_viewport_rect().size`; the portrait smoke observed a crop with no positive rightward X offset.
ACTION: Fix the UI-owned owner-background crop so portrait/narrow rendering derives from the effective target viewport/content-scale after resize and produces the intended right-biased focal region while retaining the immutable `aurorafox_background_master.png` bytes and neutral rendering. Re-run `desktop_ui_smoke.gd`, owner-art smoke, pointer/navigation and render matrix on the same candidate SHA before calling UI Wave A ready.

FROM: CHAT-2026-09-16-INTEGRATION-GATE
TO: CHAT-2026-09-16-UI-POLISH
TYPE: REGRESSION
EVIDENCE: UI PR #27 head `987f5bd0e23b4895daae60f7fa26fa28c2023c5b` has unique non-UI patches against current main that delete SERVER-DB-owned resilience behavior: `api/account_store.py::revoke_account_token`, the `_deliver_account_token` SMTP-failure revocation path in `api/server.py`, and the regressions `test_smtp_failure_revokes_issued_token_and_immediate_resend_is_not_cooldown_blocked` plus `test_undelivered_account_token_revoke_allows_immediate_retry_inside_cooldown`. These paths are explicitly owned by `CHAT-2026-09-16-SERVER-DB`; removing them would reintroduce an undelivered-token cooldown/retry defect unrelated to UI work.
ACTION: Re-sync/reconcile PR #27 non-force with fresh `main` and preserve the current SERVER-DB token revoke/retry implementation plus both regression tests. Any intentional server semantic change must be coordinated with `CHAT-2026-09-16-SERVER-DB`; otherwise eliminate эти API/test diffs from the UI branch. Require API CI + UI Visual CI + Integration Gate on one same SHA before merge.

FROM: CHAT-2026-09-16-INTEGRATION-GATE
TO: CHAT-2026-09-16-UI-POLISH
TYPE: NEXT
EVIDENCE: The current PR #27 `scripts/computer_overlay.gd` patch statically addresses section 28: the visible Computer toggle propagates through `set_computer_control_enabled(enabled)`, high-level goal execution delegates to `AgentCore.run_task()`, preview delegates to local `AIClient.chat()`, and the overlay no longer calls `ComputerClient.run()` / `plan()` as a service-side planner. This preserves bundled AuroraFox Core as planning authority, but same-SHA Work/UI runtime evidence is still queued/not accepted.
ACTION: Preserve this local-Core/default-OFF permission architecture while fixing the remaining UI blockers. Close section 28 only after the reconciled PR SHA has green Work Mode + UI Visual + Integration evidence proving enable/disable, high-level goal routing and no service-side/external-AI planning regression.

PROGRESS_COMPLETE: 68%
PROGRESS_REMAINING: 32%

DONE:
- Integration-owned branding gate is corrected for the actual `main_compat.gd` runtime architecture without relaxing immutable owner-master identity.
- UI Visual failure is localized to the portrait/right-biased owner-background crop with exact run/job/assertion evidence.
- Cross-lane SERVER-DB regression inside UI PR #27 is identified at concrete production functions and test names before merge.
- Work/Computer UI candidate is statically reconciled with bundled-Core planning authority and process-wide permission semantics; runtime acceptance remains separate.

REMAINING:
- UI lane must fix portrait crop and remove/reconcile accidental SERVER-DB diffs, then produce one same-SHA green UI/API/Work/Integration set.
- Exact-main Integration Gate `35148889897` must execute and be triaged step-by-step.
- Updater repair/signing and CodeSpecialist bundled-Core runtime acceptance remain open until green exact evidence.
- Windows/Android package plus physical-device/human visual/listening boundaries remain before final release readiness.

BLOCKERS:
- `CHAT-2026-09-16-UI-POLISH`: UI Visual run `35147641336/104967664697` fails portrait owner-background focal crop.
- `CHAT-2026-09-16-UI-POLISH` cross-lane regression: PR #27 currently deletes SERVER-DB token-delivery revoke/retry safety code/tests.
- Exact-main Integration Gate `35148889897` is pending, not green evidence.
- Physical Windows/Android device and human visual/listening acceptance remain external evidence boundaries.

NEXT:
- Do not merge or manually rerun the stale UI candidate. Let `CHAT-2026-09-16-UI-POLISH` reconcile the two routed blockers against fresh main; then inspect the next UI head's API/UI/Work exact-SHA results and feed only the reconciled candidate into the release-train Integration Gate. Preserve coordinator Wave-A/Wave-B queue control.

## 36. Coordinator continuity and fresh executor-chat handoff, 2026-09-17

- Coordinator decision: **the current coordinator chat remains the single main AuroraFox coordinator. No replacement coordinator chat will be created.** Merge authority, release-train sequencing, cross-lane arbitration, final version bump decision and final Windows/Android release acceptance remain with this coordinator.
- Fresh verified `main` before this coordination update: `047fe827c5dfee6aad967767d4d1a46f6487228b` (`server: satisfy explicit SMTP security contract`). `AGENTS.md` and the full canonical master log were reread before this write.
- Reason for rollover: old executor conversations are approaching maximum conversation length. The owner will stop using those old conversations and create fresh executor chats. This is a **chat-session rollover**, not permission to discard their branches, commits, PRs, artifacts or unresolved defects.
- Target operating set: **10 concurrent chats total = this coordinator + 9 fresh executor chats.** Creating an additional coordinator is explicitly unnecessary.
- Old executor chats are retired as active human/chat sessions after the rollover. Their old CLAIM names remain historical evidence and their occupied production paths remain protected until a fresh replacement executor explicitly performs TAKEOVER/RECONCILE in this master log. No fresh executor may assume an old claim is free merely because the old conversation is no longer used.
- A replacement executor MUST start from fresh `main`, read `AGENTS.md`, read this full master log, inspect current open PRs/heads/workflow runs, identify the old lane it replaces, and create a new takeover CLAIM before changing implementation. The takeover entry must state the old CLAIM/PR/branch/head being inherited and whether it will continue, reconcile or supersede that candidate. No blind merge of stale branches.
- Canonical version and Android `versionCode` are unchanged by this coordination-only update. Intended bump: **NONE**.

### Fresh executor topology

1. `CHAT-2026-09-17-UI-VISUAL` — UI/UX/Visual for Windows + Android: responsive layout, navigation, owner-approved art, account/guest/memory surfaces, Work/Computer UI integration, accessibility and visual regression. Inherits/reconciles `CHAT-2026-09-16-UI-POLISH` / PR #27 and any sync-only UI PRs; must preserve Server-owned fixes while reconciling.
2. `CHAT-2026-09-17-VOICE-AUDIO` — local Voice/STT/TTS/audio quality on Windows + Android, female-voice acceptance, prosody, latency, cache/interruption and package assets. Inherits/reconciles `CHAT-2026-09-16-VOICE-QUALITY` / PR #34 and related voice candidate work.
3. `CHAT-2026-09-17-CORE-CODER` — bundled AuroraFox Core intelligence, SpecialistTeam, CodeSpecialist, real offline benchmarks, Windows/Android local inference, quality/performance and candidate comparison. Inherits/reconciles `CHAT-2026-09-16-CORE-BENCHMARKS` / PR #30 and section 29 runtime acceptance.
4. `CHAT-2026-09-17-WORK-COMPUTER-AGENT` — Work lifecycle/store, Computer Agent primitives, Agent reliability/autonomy-state durability, permission/master-stop/sandbox/rollback/idempotency/recovery. Inherits/reconciles `CHAT-2026-09-16-WORK-COMPUTER-RELIABILITY` / PR #40 and autonomy durability candidate PR #72 where relevant; must not take UI-owned overlays without handoff.
5. `CHAT-2026-09-17-KNOWLEDGE-MEMORY-OCR` — unified Knowledge/Memory/document/OCR ownership to remove the former KnowledgeStore handoff bottleneck: local OCR, import/streaming, dedupe/provenance/aliases/removal/recovery, large-scale performance/stress on Windows/Android. Inherits/reconciles both `CHAT-2026-09-16-LOCAL-OCR` / PR #66 (and prior OCR candidate history) and `CHAT-2026-09-16-LARGE-KNOWLEDGE-PERF` / PR #64. This fresh lane must explicitly reconcile overlapping Store/transaction ownership before editing.
6. `CHAT-2026-09-17-SERVER-API-DB` — Server/API/SQLite/account/auth/guest/device sync/mail/request limits/privacy/deployment/rollback. Inherits current `CHAT-2026-09-16-SERVER-DB` state and must start from the current server-updated main, not stale PR #25 history.
7. `CHAT-2026-09-17-PLATFORM-RELEASE` — Windows + Android packaging/export/install/launch, Android signing continuity, updater/signatures/trust-root/repair bridge, deterministic build supply chain and release artifacts. Inherits/reconciles `CHAT-2026-09-16-UPDATER-VERSIONING` and current package workflows. Final canonical version bump remains coordinator-authorized only after global acceptance.
8. `CHAT-2026-09-17-RESEARCH-SELF-IMPROVEMENT` — Research collector/curator, provenance/corroboration/retraction/privacy, controlled self-improvement/candidate queue/tournament/promotion safety. Inherits accepted Research Quality evidence including run `35112565080`; must not redo already green work and should continue from the first remaining research/self-improvement gap.
9. `CHAT-2026-09-17-INTEGRATION-REGRESSION` — independent same-SHA integration/regression/release-readiness gate. It owns integration tests/workflow and failure classification, not other lanes' production code. Old probe PR #69 is stale and must never be treated as the final merge candidate; build fresh integration evidence from current main plus current accepted candidate heads.

### Coordinator rules for the fresh topology

- This coordinator continuously checks all nine executors, current `main`, open PR heads and exact-head CI. Idle/finished executors are reassigned to an independent bottleneck, integration evidence or final release regression instead of waiting.
- Production ownership overlaps are intentionally minimized: UI+Visual together; Core+Coder together; Knowledge+Memory+OCR together; Work+Computer+Agent reliability together; Platform+Updater together. This replaces the less efficient old split where OCR/Knowledge and package/updater repeatedly blocked each other.
- Fresh executors must preserve useful old work. A new branch from current `main` may cherry-pick/reimplement only verified relevant deltas from old PRs; stale unrelated diffs must not be carried forward.
- A lane may be called READY only with exact commit SHA + relevant green tests/workflow run IDs/artifacts and no known P0/P1 blocker in its scope. Static source inspection is not runtime proof.
- Final merge order is not predetermined. The coordinator chooses it from current overlap, CI and dependency evidence; no executor self-merges a red or stale integration candidate.

PROGRESS_COMPLETE: 100%
PROGRESS_REMAINING: 0%

DONE:
- Fresh 10-chat operating topology is defined: one continuing coordinator plus nine replacement executor roles.
- Old chat sessions are explicitly retired without discarding their Git/CI evidence, and takeover/reconciliation rules preserve file ownership until a replacement claim is recorded.
- Coordinator/release authority and no-extra-coordinator rule are explicit.
- No production code, product version or Android versionCode was changed by this coordination update.

REMAINING:
- Coordination rollover itself: none. Product acceptance work remains in the nine executor lanes and coordinator release train.

BLOCKERS:
- none for the chat-topology rollover. Individual product blockers remain documented in the preceding lane sections and current GitHub CI.

NEXT:
- Owner creates the nine fresh executor chats using their assigned prompts. Each replacement chat immediately fetches current `main`, reads `AGENTS.md` + this journal, creates its takeover/reconcile CLAIM, inspects its inherited PR/branch/run evidence and resumes from the first unaccepted item. Coordinator then tracks their new CLAIMs and prevents duplicate/stale work.

## 37. Coordinator topology correction — seven fresh executors, 2026-09-17

- This section **supersedes only the executor-count/topology instructions in section 36**. All historical Git/CI/PR evidence and the takeover/reconcile safety rules from section 36 remain valid.
- Coordinator remains this current chat. No replacement coordinator is created.
- Final operating set is **8 chats total = this coordinator + 7 fresh executor chats**. This consolidation is chosen to reduce ownership handoffs and duplicated CI while retaining independent parallel work.
- Old executor conversations are retired as active sessions, but their branches, PRs, commits, artifacts, failures and useful work are not discarded. Old production ownership remains protected until the corresponding new executor writes an explicit TAKEOVER/RECONCILE claim from fresh `main`.
- Canonical product version and Android `versionCode` remain unchanged. This is coordination-only; intended bump **NONE**.

### Final seven executor lanes

1. `CHAT-2026-09-17-UI-VISUAL-UX` — UI + UX + Visual for Windows/Android. Takes over/reconciles old UI-POLISH / PR #27 and UI sync candidates. Owns responsive layout, navigation, canonical owner artwork integration, account/guest/memory surfaces, Work/Computer presentation, accessibility and visual regression. Must preserve Server-owned semantics while reconciling stale UI diffs.
2. `CHAT-2026-09-17-CORE-CODER-RESEARCH` — bundled AuroraFox Core + CodeSpecialist/SpecialistTeam + real offline benchmarks + Research/Self-Improvement. Takes over/reconciles CORE-BENCHMARKS / PR #30, CodeSpecialist runtime acceptance, accepted Research Quality evidence (including run `35112565080`), and remaining candidate-queue/tournament/promotion/corroboration work. Already-green research work must not be redone. External AI remains optional/non-authoritative.
3. `CHAT-2026-09-17-VOICE-AUDIO` — local Voice/STT/TTS/audio for Windows/Android. Takes over/reconciles VOICE-QUALITY / PR #34 and Android female-voice candidate work. Owns voice quality, prosody, latency, interruption/cache/device degradation and acoustic/package evidence.
4. `CHAT-2026-09-17-WORK-COMPUTER-AUTONOMY` — Work + Computer Agent + Agent/Autonomy reliability. Takes over/reconciles WORK-COMPUTER-RELIABILITY / PR #40 and autonomy-state durability / PR #72 where applicable. Owns lifecycle/recovery/idempotency/concurrency, Computer primitives, sandbox/master-stop/permission/rollback and autonomy-state durability. UI overlays remain with UI lane unless explicitly handed off.
5. `CHAT-2026-09-17-KNOWLEDGE-MEMORY-OCR` — unified Knowledge + Memory + OCR/document intelligence. Takes over/reconciles LOCAL-OCR / PR #66 and LARGE-KNOWLEDGE-PERF / PR #64, intentionally removing the former `knowledge_store.gd` ownership bottleneck. Owns local OCR, streaming import, dedupe/provenance/aliases/removal/recovery, large-data stress/performance, bounded memory and Windows/Android document paths.
6. `CHAT-2026-09-17-SERVER-API-DB` — Server + API + accounts/auth/guest/device sync + SQLite + mail + privacy + deployment/rollback. Takes over current SERVER-DB state and starts from current server-updated `main`; stale PR #25 is historical input only, never a blind merge source.
7. `CHAT-2026-09-17-PLATFORM-UPDATER-INTEGRATION` — Windows/Android packaging + installer/APK + signing continuity + updater/repair/trust-root + deterministic build supply chain + same-SHA integration/regression/release-readiness. This consolidates the former PLATFORM/UPDATER and separate INTEGRATION lanes because their current work is tightly coupled at package/release gates. It inherits UPDATER-VERSIONING, integration-gate history and current package workflows. Old probe PR #69 remains stale and must never be merged as a final candidate. This executor may classify product failures but must route production fixes to the owning lane rather than silently taking its files. Final merge/version bump/release authority stays with the coordinator.

### Consolidated rollover rules

- Section 36 roles `RESEARCH-SELF-IMPROVEMENT` and `INTEGRATION-REGRESSION` are **not separate fresh chats anymore**: Research/Self-Improvement is absorbed into `CORE-CODER-RESEARCH`; Integration/Regression is absorbed into `PLATFORM-UPDATER-INTEGRATION`.
- All seven fresh executors must first fetch current `main`, read `AGENTS.md` and the complete master log, inspect inherited PR/branch/head/workflow evidence, and write an explicit takeover/reconcile CLAIM before touching implementation.
- A fresh executor must continue from the first unaccepted item, not restart already-proven work. Stale unrelated diffs are excluded; verified useful deltas may be reconciled onto fresh `main` non-force.
- Exact-head evidence remains mandatory: commit SHA + relevant tests/workflow run IDs/artifacts. Static inspection alone is not runtime proof.
- Finished/blocked executors do not idle: after releasing owned files they help an independent bottleneck, regression or release evidence without editing another active lane's occupied production files.

PROGRESS_COMPLETE: 100%
PROGRESS_REMAINING: 0%

DONE:
- Final rollover topology corrected to one continuing coordinator + seven fresh executor chats.
- Research is consolidated with Core/Coder; Integration is consolidated with Platform/Updater; OCR and Large Knowledge remain consolidated.
- Old work/PR/CI evidence is preserved through explicit takeover/reconcile instead of being discarded.
- No production code or public version metadata changed.

REMAINING:
- Coordination topology: none. Product work continues under the seven fresh takeover claims.

BLOCKERS:
- none for this coordination correction; subsystem blockers remain those proven by current Git/CI evidence.

NEXT:
- Owner opens exactly seven fresh executor chats. Each uses the assigned standalone prompt, writes its new takeover/reconcile CLAIM, then begins real work from current `main`. Coordinator tracks all seven and performs merge/release arbitration.

## 38. Mandatory blocked/waiting escalation through coordinator, 2026-09-17

This section is a **mandatory coordination rule** for all seven executor lanes and supersedes any older habit of silently waiting on another lane, a queued check, ownership conflict or unknown next step.

### Executor rule

If an executor chat reaches **any state that prevents useful forward progress**, it MUST report the condition in this `docs/PROJECT_MASTER_LOG.md` immediately instead of waiting indefinitely, starting duplicate work or crossing another lane's ownership boundary. This includes, but is not limited to:

- a failing test/workflow that belongs to another lane;
- waiting for another lane's code, API, artifact or merge;
- ownership/file conflict;
- stale/incompatible branch or PR state;
- CI queue/scheduling blocker that prevents the next required gate;
- missing external/device/credential/access boundary;
- architectural decision requiring coordinator arbitration;
- uncertainty about whether a candidate can be merged;
- any other condition where the executor has no safe independent next action inside its own scope.

The executor records a `COORDINATOR-BLOCKER` entry using this minimum format:

```text
COORDINATOR-BLOCKER:
FROM: <current CLAIM>
STATUS: BLOCKED | WAITING | OWNERSHIP-CONFLICT | CI-BLOCKED | DECISION-REQUIRED
CURRENT_SHA: <exact branch/head SHA>
BLOCKED_ON: <claim/pr/run/job/file/external boundary>
EVIDENCE: <exact failing test/workflow/run/job/artifact/diff or factual reason>
ALREADY_TRIED: <only factual attempts already made>
SAFE_PARALLEL_WORK: <independent work that can still continue, or NONE>
NEEDS_COORDINATOR: <specific decision/routing needed>
```

After writing the escalation, the executor MUST NOT silently take another active lane's production files or weaken/remove a failing acceptance test merely to continue. If `SAFE_PARALLEL_WORK` exists, it should continue that independent work while waiting for coordinator routing. If none exists, it waits for the coordinator decision recorded in this journal rather than inventing a new ownership scope.

### Coordinator rule

The coordinator continuously reads these `COORDINATOR-BLOCKER` entries and resolves them through the same journal. For each unresolved escalation the coordinator must verify the available Git/CI evidence and write a `COORDINATOR-DECISION` entry with:

```text
COORDINATOR-DECISION:
FOR: <blocked CLAIM>
DECISION: CONTINUE | REROUTE | HANDOFF | MERGE-FIRST | REBASE/RECONCILE | WAIT-EXTERNAL | DROP-STALE | SPLIT-WORK | OTHER
OWNER: <claim responsible for next action>
ACTION: <exact next safe action>
DEPENDENCY: <what must become true before the original lane resumes, or NONE>
EVIDENCE: <SHA/run/job/diff/contract supporting the decision>
PARALLEL_ACTION: <what the blocked lane should do meanwhile, or NONE>
```

The coordinator is responsible for preventing queue deadlocks: if a dependency can be removed by changing merge order, reconciling a stale candidate, routing a defect to its true owner, splitting an independent test wave, or moving an idle/finished executor to an unowned bottleneck, the coordinator does so and recordsывает that decision here.

### No-idle / no-deadlock rule

- No executor should remain in an undefined `waiting` state without a journal escalation and coordinator decision.
- A red aggregate Integration gate does not force unrelated green lanes to stop when the failing subsystem has been identified and isolated by exact evidence.
- A finished executor releases its files and may be reassigned by the coordinator to independent regression, evidence collection, packaging or another unowned bottleneck.
- A blocked executor may continue only explicitly safe parallel work; it must not duplicate the blocker owner's implementation.
- Every blocker must have an owner, evidence, a coordinator decision and a next action. `Ждём`, `непонятно кто делает`, `проверим потом` are not valid terminal states.
- Final merge, final version bump and release authority remain coordinator-only.

PROGRESS_COMPLETE: 100%
PROGRESS_REMAINING: 0%

DONE:
- Mandatory executor→coordinator escalation protocol is defined for blockers, waits, ownership conflicts, CI scheduling and architecture/merge decisions.
- Mandatory coordinator→executor decision protocol is defined in the same canonical journal.
- No-idle/no-deadlock behavior is explicit: executors continue safe independent work where possible and do not cross ownership boundaries while blocked.
- This coordination-only change does not modify production code, canonical product version or Android versionCode.

REMAINING:
- Product lanes continue normally under section 37; every new blocker/wait condition must now use this section 38 protocol.

BLOCKERS:
- none for this coordination rule.

NEXT:
- Coordinator continues monitoring all seven lanes. On the first `COORDINATOR-BLOCKER` entry, verify its exact evidence, publish a `COORDINATOR-DECISION` here, reroute ownership/merge order/CI as needed, and keep all independent lanes moving.

## 39. Work / Computer / Autonomy — TAKEOVER/RECONCILE, 2026-09-17

### CLAIM `CHAT-2026-09-17-WORK-COMPUTER-AUTONOMY`

- Статус: **ACTIVE — TAKEOVER/RECONCILE**.
- Fresh baseline: `b574546cc133a7bd9aa6b24e65414ca3328949d7`; branch head before this claim: `f4eaca0229c8767ddb371ee8da59fe30fb49af4a`.
- Режим: Chat. Intended bump after acceptance: **PATCH**; version/versionCode/final merge/release remain coordinator-only.
- Inherits `CHAT-2026-09-16-WORK-COMPUTER-RELIABILITY` / draft PR #40, verified head `f4ad58377752020823900fea107914af49021349`: Work lifecycle/recovery, atomic WorkStore, safe/unsafe retry + uncertain-result protection, bounded local Computer primitives, default-OFF/master-stop, sandbox/idempotency/privacy, tests. Old exact-head evidence: Work Computer Reliability `35147796178` SUCCESS; Work Mode `35147796111` SUCCESS; Windows Package `35147796213` SUCCESS; Android APK `35147795977` SUCCESS; Agent Sync `35147796112` SUCCESS; Core/Voice `35147796205` SUCCESS.
- Inherits PR #72 head `3434f70ba32f74462c4b9f5216cf26cd5ddb2afa`, already merged into main as `5479a05e36aa8888fdeb96bbf9b9bac397b7780f`: temp/backup atomic autonomy-state save, interrupted/corrupt recovery, legacy schema, fail-closed autonomy boot. Exact-head evidence: Agent Sync `35150755820` SUCCESS; Core/Voice `35150755870` SUCCESS; Windows Package `35150755901` SUCCESS; Android APK `35150755919` SUCCESS. Windows artifact `10469683226` digest `sha256:965ecd3670ca26bfc2ea478c1135deeda01c13ae87c3166ca90350ca26d05eaf`; Android artifact `10469586976` digest `sha256:fa9c968aa8b54e2ad7e8770f8a6c25b60e5d8231b1d0863441fc15fb17431ca4`.
- Current reconcile candidate `af652c3e76254eb3f7981907a9adf8c8b82c7d91` was produced concurrently from fresh main and merged into this branch as `f4eaca0229c8767ddb371ee8da59fe30fb49af4a`; it is **not accepted by assertion alone**. Audit already found five unrelated stale workflow diffs (`agent-sync-ci.yml`, `android-apk-artifact.yml`, `release-identity-ci.yml`, `voice-ci.yml`, `windows-package-ci.yml`); those must be removed before candidate acceptance.
- Owned scope: `work/work_manager.gd`, `work/work_store.gd`, `computer/computer_service.py`, `computer/install_computer.ps1`, `computer/requirements.txt`, `scripts/computer_client.gd`, Work/Computer reliability tests and `.github/workflows/work-computer-reliability.yml`; `scripts/agent_core.gd`, `scripts/tool_registry.gd`, `scripts/sandbox_manager.gd`, `agent/autonomous_coordinator.gd` only with runtime evidence/rechecked ownership.
- UI boundary: do not edit `scripts/computer_overlay.gd`, `scripts/computer_overlay_compat.gd`, `work/work_overlay.gd`; UI contract defects route to `CHAT-2026-09-17-UI-VISUAL-UX`.
- Architecture invariant: high-level goal = bundled AuroraFox Core / AgentCore → ToolRegistry → bounded Computer primitives. `ComputerClient.plan()` / `run()` and sidecar service are not planners; no mandatory external AI/model.

PROGRESS_COMPLETE: 35%
PROGRESS_REMAINING: 65%

DONE:
- Fresh main/AGENTS/full master log, old claims, PR #40/#72 exact heads/diffs/CI/artifacts audited.
- PR #72 is already integrated and preserved; no reimplementation.
- PR #40 useful work identified, and stale unrelated workflow contamination in current reconcile candidate is explicitly identified before acceptance.

REMAINING:
- Remove unrelated workflow diffs; verify resulting diff contains only owned/relevant Work/Computer safety changes plus this journal entry.
- Create/open a draft takeover PR; obtain same-SHA Work Computer Reliability + Work Mode CI and inspect exact failure-injection results.
- Extend any missing runtime gates for state corruption/both-corrupt/fail-closed, concurrency, service crash/timeout/malformed/permission/screenshot/idempotency/destructive uncertain replay, Windows supported capability and Android graceful unsupported Computer.

BLOCKERS:
- none preventing safe owned-scope cleanup/testing now. UI runtime acceptance remains cross-lane and will be routed, not edited here.

NEXT:
- Restore the five unrelated workflows from fresh main, verify net diff, then trigger draft-PR CI and classify failures by exact run/job/test before further implementation.

## 40. Unified executor takeover of all unfinished lanes — 2026-09-17

### CLAIM `CHAT-2026-09-17-UNIFIED-EXECUTION-TAKEOVER`

- Статус: **ACTIVE — OWNER-DIRECTED TAKEOVER/RECONCILE ALL EXECUTOR LANES**.
- Started from exact fresh `main`: `54fa827854320adf864d578ad3831e9e375a9e3f` (`Merge Platform/Updater/Integration CI hardening`).
- Режим: Chat.
- Owner instruction: the other executor conversations can no longer be continued by the owner. This chat therefore takes direct implementation responsibility for every unfinished item previously assigned to the seven executor lanes in section 37.
- This takeover **does not discard or invalidate** their branches, PRs, commits, workflow runs, artifacts, accepted tests or historical failure evidence. Existing work is inherited and reconciled from exact Git facts; already accepted green work is not reimplemented without a new regression.
- This takeover supersedes executor-to-executor production ownership boundaries for unfinished work: UI/UX/Visual, Core/Coder/Research/Self-Improvement, Voice/Audio, Work/Computer/Autonomy, Knowledge/Memory/OCR, Server/API/DB, Platform/Updater/Integration/Packaging may now be changed by this unified executor after fresh-main reconciliation and exact evidence. Safety/trust boundaries in sections 0–1 remain unchanged.
- Higher-level coordinator/leader authority is **not** taken over: final merge arbitration, canonical public version/versionCode bump, production signing/release and final Windows/Android release acceptance remain coordinator/leader decisions unless the owner explicitly changes that authority later.
- Aggregated intended release bump remains **at least MINOR** because the existing release train includes a new signed update floor and broad accepted server/product changes; canonical `V1.3.0.0` and Android `versionCode=100005` are not changed by this takeover entry and remain test-first/version-last.
- First execution rule: audit current open PRs and current exact-head Actions, preserve useful deltas, drop stale/unrelated diffs, and work from the first unaccepted reproducible blocker rather than replaying historical work.

### Leader report / acknowledgement request

LEADER-NOTIFY:
FROM: `CHAT-2026-09-17-UNIFIED-EXECUTION-TAKEOVER`
TO: current AuroraFox coordinator/leader
TYPE: OWNER-DIRECTED EXECUTION TAKEOVER
CURRENT_MAIN: `54fa827854320adf864d578ad3831e9e375a9e3f`
REPORT: By direct owner instruction, this chat has taken responsibility for all unfinished implementation/testing tasks previously delegated to the seven executor chats. Their Git/CI work remains inherited evidence; final merge/version/release authority remains with the coordinator/leader.
ACK_REQUEST: In the coordinator/leader's **next owner-facing response**, explicitly confirm that this takeover report was received from the journal. Do not claim acknowledgement before the coordinator/leader actually reads this entry.

PROGRESS_COMPLETE: 55%
PROGRESS_REMAINING: 45%

DONE:
- Fresh `main` `54fa827854320adf864d578ad3831e9e375a9e3f` verified immediately before takeover.
- Root `AGENTS.md` and the complete canonical master log through section 39 were reread before this write.
- All previous executor work is formally inherited instead of being abandoned; existing exact SHAs/PRs/runs/artifacts remain evidence.
- Unified implementation ownership is recorded while coordinator/leader merge/version/release authority and all safety/trust invariants remain intact.
- Leader notification and explicit next-response acknowledgement request are recorded in the canonical journal.

REMAINING:
- Enumerate every current open PR/head and exact workflow status against fresh main; classify stale, mergeable, red and already-green candidates.
- Reconcile/fix current runtime blockers across Core, Android/platform, Knowledge/OCR, Server/API, UI, Voice and Work/Computer in evidence-driven batches.
- Produce a single same-SHA integrated candidate with all required local/offline, safety, updater, API, UI, package and platform gates green.
- Complete available Windows/Android install/launch/package evidence and report external physical-device/owner-signing boundaries honestly where inaccessible.
- Hand the exact candidate SHA/runs/artifacts/checksums to the coordinator/leader for final version bump/signing/release decision.

BLOCKERS:
- No repository/code blocker prevents unified work now.
- Owner-controlled production signing secrets and any unavailable physical Windows/Android device remain external acceptance boundaries; they do not block code/CI hardening.

NEXT:
- Inspect current open PRs and exact-head Actions; begin with the highest-severity reproducible current blocker on top of `54fa827...`, preserving all already-green subsystem evidence and avoiding duplicate heavy CI.

## 41. Unified execution checkpoint — journal-first discipline and current exact evidence, 2026-09-17

### `CHAT-2026-09-17-UNIFIED-EXECUTION-TAKEOVER` — checkpoint

- Owner explicitly reaffirmed that the canonical `docs/PROJECT_MASTER_LOG.md` must be read and updated around every meaningful implementation stage. From this checkpoint onward the unified executor treats a PR comment as supplemental evidence only; it does not replace this journal.
- Fresh `main` before this journal write: `9ca5fafd1f65038d855d00e1e1e0db876938d17f` (`docs: unify executor takeover under current chat`), parent `54fa827854320adf864d578ad3831e9e375a9e3f`.
- Platform/Integration infrastructure was merged as `54fa827854320adf864d578ad3831e9e375a9e3f`: Integration now installs `httpx==0.28.1` and uses current durability/readiness contracts, so missing-httpx/stale-meta false reds are no longer accepted as product failures.
- Knowledge/Memory/OCR active PR #82 exact head `693126d033057eb8382160c8e16f51faf5548176` is mergeable. Its reconciled candidate carries local Windows Tesseract `rus+eng` packaging, Android PDFBox+Tesseract export, Android NDK pin `28.1.13356709` and the corrected Android OCR contract. Integration run `35191781320`: `godot-cross-subsystem` SUCCESS; alias removal, record/shared-source dedupe, legacy rollback, registry write-failure rollback, truncated-temp rejection, interrupted reimport and interrupted canonical removal all SUCCESS. The cross-subsystem aggregate remained red only on UI branding. Heavy 100/250 MiB and genuine >=1 GiB Knowledge Pack acceptance remain open and therefore this lane is not 100% ready.
- Work/Computer active PR #86 exact head `4d5007d7b7f933f3ee3a4b47c88edfad2f223500` is mergeable and non-draft. Exact-head Work Mode `35191682282`, Work Computer Reliability `35191682119`, Agent Sync `35191682275`, Core/Voice `35191682234` and API CI `35191682195` are SUCCESS. Windows Package `35191682187` and Android APK `35191682264` were still running at the last exact check; do not call final same-SHA package acceptance until their final status is recorded.
- UI PR #84 was reconciled without importing its stale master-log delta; latest UI cleanup commit recorded by this unified executor is `4e72fd9075dd215bb1d8d114dc103e3a479c951f`. Prior UI Visual evidence remains accepted for its own old head, but final UI release acceptance still requires same-SHA rerun after backend/release-train reconciliation and does not substitute for physical-device tap/visual acceptance.
- Core/Coder/Research PR #78 was reconciled non-force onto the release train as merge commit `431c3be296b095e4e3318faa1c098bb918e86028`, then bounded-runtime/test hardening advanced the branch through `8d0cfe0ecf645781b47bdf1eef9a4ee110e30bba`, `a4a73fa275f5272853e43a73cb5a6ac441ca4e77` and exact head `738128444d8723ae69842a2fcad1c4a76c565d8c`. Historical run `35186317354` had timed out SpecialistTeam/CodeSpecialist after 360 seconds. On the new exact head, Core Benchmarks run `35192337079` proves the timeout blocker itself is resolved: gate-contract SUCCESS, verified bundled Core preparation SUCCESS, **real SpecialistTeam / CodeSpecialist offline smoke SUCCESS**, and the real bundled Core benchmark actually executed. The workflow remains FAILURE for a new genuine quality finding: benchmark runner reported `exit=2`, peak RSS `3817.29 MiB`, evaluator reported `quality=False performance=True relative=False`; artifact `10484628030`, digest `sha256:b3c4bd35a66b70b3197357d9aa5eaba26bc966b110d7c8ed7a8a021a64e58640`. This is now a quality/debug blocker rather than an infrastructure-timeout blocker and must be fixed from the artifact evidence without weakening the quality gate. Core/Voice `35192336941`, Agent Sync `35192337036`, Core Bootstrap `35192336993`, Research Quality `35192336943` and Evolution Tournament `35192336994` are SUCCESS on the same branch head/PR merge context.
- Core Android remains independently red on exact head: Core Android Benchmark `35192336947` FAILURE and Core Android E2E `35192336879` FAILURE. These must be inspected by exact job/log before changing Android production/package code; historical duplicate `libc++_shared.so` packaging evidence is not assumed to be the current root cause.
- Voice candidate has prior exact local Supertonic F1–F5 acceptance evidence and remains open; it still needs a current same-SHA package/install/launch set before final merge acceptance. Server/API remains largely green by exact contract evidence but physical REG.RU deployment remains an access boundary.

PROGRESS_COMPLETE: 89%
PROGRESS_REMAINING: 11%

DONE:
- Unified ownership is active and journal-first execution discipline is explicitly reaffirmed.
- Platform/Integration false-red infrastructure is landed in main.
- Knowledge runtime correctness P0 is closed on PR #82 exact-head Integration runtime evidence; remaining Knowledge risk is heavy-scale/real-pack/platform acceptance, not the four former durability probes.
- Work/Computer own-scope reliability and network-response safety are green on current exact head; heavy package completion remains to be recorded.
- Core SpecialistTeam/CodeSpecialist real offline execution now passes; the previous 360-second timeout is no longer the blocker.
- Core benchmark now reaches real inference and exposes a genuine quality failure with a machine-readable artifact instead of failing before quality measurement.

REMAINING:
- Download/inspect Core artifact `10484628030`, identify the exact failing quality scenarios and fix the smallest real Core/Coder defect; rerun the same real-Core gate without weakening thresholds.
- Inspect current Core Android Benchmark/E2E failures separately and reconcile only their current root cause.
- Complete Knowledge 100/250 MiB stress plus the required genuine >=1 GiB `.afknowledge` production-pack gate and Windows/Android import/query evidence.
- Record final Windows/Android package results for Work/Computer and other candidates; reconcile UI/Voice onto the eventual integrated SHA and rerun exact acceptance.
- Build the final same-SHA release candidate; only then perform coordinator-authorized version/versionCode bump and owner-signing/release flow.

BLOCKERS:
- P0 current internal blocker: Core benchmark quality (`quality=False`) on real bundled inference, artifact `10484628030`.
- Core Android real-runtime acceptance remains red pending exact failure classification.
- Genuine >=1 GiB Knowledge Pack and physical-device/production-signing boundaries remain incomplete.

NEXT:
- Before the next code mutation, reread fresh `main` and this complete journal. Then inspect artifact `10484628030` and the two Core Android job logs; change only the reproduced root cause. After that implementation/test stage, append its exact SHA/run/result to this journal before moving to another lane.

## 42. Core/Android blocker classification — exact artifact/log evidence, 2026-09-17

### `CHAT-2026-09-17-UNIFIED-EXECUTION-TAKEOVER` — classification checkpoint

- Fresh canonical `main` was rechecked immediately before this journal write and remains `d06ac6088445edd9197dca0584b64245b920b58b` (`docs: record unified execution checkpoint`). The complete current journal blob `d2e59c1a81b7b293b9bd817ca72de7cd8592e264` was reread before classification.
- Core benchmark artifact `10484628030` from run `35192337079` was downloaded and inspected directly. `code-specialist-smoke.json` is green: all 8 operations passed on `aurora_core_desktop`, with no external AI requirement. In `core-benchmark-report.json` / raw report, **20 of 21 quality scenarios pass**. The sole failing scenario is `corrupted_input`: `passed=false`, runtime `aurora_core_desktop`, elapsed `5995.096 ms`, output excerpt exactly `IVORY-29`. The other scenarios — self-reliance/offline identity, RU/EN dialogue, instructions, multi-turn, local memory, Core Knowledge retrieval, planning, tool selection, text/code generation, explanation, reasoning, long context, compatibility isolation and repeatability — pass. Performance gate itself remains green; reported cold response `6331.216 ms`, warm median `8327.302 ms`, peak RSS about `3817.29 MiB`; no benchmark timeout.
- This narrows the real desktop product-quality blocker to context/retrieval isolation around malformed input. `IVORY-29` is evidence that the corrupted-input request received unrelated retained Knowledge/context content from an earlier scenario rather than demonstrating a generic model crash. The acceptance threshold is **not** weakened; the next code step must first inspect the exact benchmark scenario and AIClient/context orchestration and decide whether the defect is benchmark state leakage or production retrieval behavior.
- Core Android E2E run `35192336879` was inspected by exact job log. Verified bundled Core preparation, Android plugin build, APK export, temporary CI signing and install all succeeded. The job failed **before launching the AuroraFox benchmark**: after `cmd connectivity airplane-mode enable`, `settings put global airplane_mode_on 1`, Wi-Fi/data disable, the script read `settings get global airplane_mode_on` as an empty string (`airplane_mode=`) and `test "$state" = '1'` exited 1. Therefore this run does **not** prove an Android Core inference failure; it proves the offline-device-state CI assertion is not valid on this API-35 emulator configuration. The offline requirement itself remains mandatory and must be re-proven with a reliable connectivity/network-blocked assertion, not deleted.
- Core Android Benchmark run `35192336947`, failing job `105107868118`, was also inspected. The production Android runtime/plugin build completed successfully before the emulator stage. Inside `reactivecircus/android-emulator-runner`, the script assigns `apk='benchmarks/core/android_probe/app/build/outputs/apk/debug/app-debug.apk'` and then later executes `adb install -r "$apk"`; the action wrapper executes script lines in separate shell invocations, so `$apk` is empty and adb exits with `filename doesn't end .apk or .apex:`. The app/Core benchmark is never reached. This is a workflow shell-scope defect, not current evidence of Android model/runtime failure.
- Toolchain reproducibility issue found while inspecting the same Android logs: workflow provisioning explicitly installs/exports NDK `28.1.13356709`, while Gradle later requests and auto-installs NDK `27.0.12077973`. This mismatch is not the immediate failure above, but deterministic Android supply-chain acceptance is incomplete until workflow and Gradle use one pinned NDK version.

PROGRESS_COMPLETE: 90%
PROGRESS_REMAINING: 10%

DONE:
- Previous generic `Core quality=False` blocker is reduced to one exact failing scenario with output evidence; CodeSpecialist/SpecialistTeam are independently confirmed green.
- Both exact-head Android Core failures are classified as pre-runtime CI/workflow defects; neither current red run reached Android Core inference.
- Android build/export/sign/install success is separated from Android inference acceptance instead of falsely treating the whole red run as product failure.
- Deterministic NDK mismatch is recorded as an independent platform reproducibility issue.

REMAINING:
- Inspect `corrupted_input` benchmark source and the AIClient/Knowledge/context path that produced `IVORY-29`; fix the smallest reproduced isolation defect without changing expected quality semantics.
- Fix Android Benchmark emulator script variable scope so the built probe APK is actually installed/launched and the real benchmark report is collected.
- Replace the fragile API-35 `airplane_mode_on` property assertion with a reliable offline proof while preserving the mandatory no-network normal-path gate.
- Unify Android Gradle/workflow NDK pin, then rerun both Android Core gates and the desktop real-Core benchmark on the resulting exact branch SHA.

BLOCKERS:
- Product P0 remains only the reproduced desktop `corrupted_input` context/retrieval isolation failure until source inspection says otherwise.
- Android Core runtime acceptance is **unproven**, not product-red: current jobs stop before inference.

NEXT:
- Reread fresh `main` and this journal, then inspect the exact Core benchmark scenario, AIClient/context builder and the two Android workflow files. Make only evidence-backed minimal fixes, run the affected exact gates, and write the resulting commit SHA/run IDs/results back into this journal before moving to Knowledge/Work/UI/Voice.

## 43. Work final engineer — owner-directed TAKEOVER/RECONCILE, 2026-09-17

### CLAIM `WORK-2026-09-17-FINAL-RELEASE`

- Status: **ACTIVE — OWNER-DIRECTED TAKEOVER/RECONCILE**.
- Starting main: `031aebaad16fc25a39dfc45c58f96fadb658cac2`; inherited draft PR #92 / `chat-2026-09-17-unified-finalization` exact head `30d054bb9a9419e63430ced1d841c8931068d79d`.
- AGENTS.md and full canonical log read. Acknowledge section 40 LEADER-NOTIFY: prior unified executor takeover received; useful code/evidence is preserved.
- Owner appoints this session final engineer with integration/release responsibility. Reconciles unfinished section 40–42 claims and historical seven-lane claims; does not assume their percentages are verified.
- Intended accumulated release bump: MINOR / V1.4.0.0, test first/version last. No canonical bump now.
- First owned batch: `benchmarks/core/run_android_godot_e2e.sh`, Android APK/E2E workflows, relevant runner tests, this journal. Other production files only after reproduced defect and updated claim.
- Current exact candidate: 24 workflows completed, 22 SUCCESS, Android APK `35253859322` FAILURE (job `105312532029`: logcat collection exit 255 after install/monkey success), Android Core E2E `35253859198` FAILURE (job `105312896359`: no collected report after 1200 s).
- Source evidence: E2E builds --export-release, then attempts run-as against a non-debuggable package and suppresses errors; it also stops on the first report file although the app writes status=running before inference. Both are evidence collection defects, not proof of product inference success. Preserve actual release runtime and require completed report.
- Knowledge 1GiB workflow `35253859168` is a synthetic JSONL stress test. It cannot establish genuine >=1GiB production knowledge pack/provenance/licenses or Android import acceptance.

PROGRESS_COMPLETE: 0%
PROGRESS_REMAINING: 100%
DONE:
- Fresh main, complete instructions/log, open PR and exact candidate workflow conclusions checked; clone at exact candidate available.
REMAINING:
- Full component audit from files/logs/artifacts; repair Android evidence collection, run relevant tests and exact CI; genuine pack and device/signing acceptance; final version and release gates.
BLOCKERS:
- Android release-runtime E2E remains unproven. No physical Windows/Android device or production signing availability verified.
NEXT:
- Fix release APK report collection using root on the disposable API35 emulator, wait for completed status, retain partial report/filtered app diagnostics and reject missing mandatory scenarios. Test runner lifecycle with adb simulation before real CI.


## 44. Final engineer audit and first Android evidence batch — 2026-09-17

CLAIM: `WORK-2026-09-17-FINAL-RELEASE` — ACTIVE.
Starting main: `031aebaad16fc25a39dfc45c58f96fadb658cac2`.
Audited candidate: `30d054bb9a9419e63430ced1d841c8931068d79d` (PR #92); many workflows actually check out PR merge `8b11b2f29daa4b24af187eedcd996c97dbe92d45`, while explicit-head Knowledge/chat gates check out `30d054bb...`. These identities must not be conflated. New implementation commit: `8c61086b7ef9dfba3631b53a3e3624ba321d737f`.

### Coordination / repository facts

- Full main AGENTS/master log read before implementation; section 40 takeover notification acknowledged in section 43.
- Only open PR found: #92, draft, mergeable, 108 files / 128 commits at the audited head. It is NOT accepted for merge.
- Branch search paginated: 123 branch names returned. Old/superseded candidates include PR #64 race/scaling history, #66 OCR, #78 Core, #82 Knowledge, #84 UI, #86 Work and numerous temporary/sync branches. Names alone do not prove obsolete/redundant commits; none deleted, none blindly merged.
- No open GitHub issues returned; unresolved work is in canonical log and release gates, not necessarily GitHub issues.
- Releases API returned only `repair-v1.2-windows`, prerelease (2026-09-16). No normal V1.4 release/update asset set was returned.
- Source canonical version remains V1.3.0.0 / Android code 100005. Pinned update floor is 1.4.0.0. Permanent public identity exists, private signing availability not inspected/assumed.

### Component audit

Percentages below are conservative evidence coverage, not a guarantee of quality equivalence to commercial assistants: 20 points each for inspected source/contract, green automated gate, relevant observed runtime evidence, complete platform/package evidence, final V1.4 device/release acceptance. Missing proofs never count as a pass. No component has final acceptance. SHA for rows is audited candidate `30d054bb...` / workflow checkout `8b11b2f...` as above unless explicitly noted.

| COMPONENT | % | CURRENT STATUS / PROOF / TEST RESULT | WHAT IS MISSING |
|---|---:|---|---|
| Core | 60 | Windows real Core benchmark 35253859144 / job 105312715775 SUCCESS: SpecialistTeam/CodeSpecialist offline gate OK, benchmark exit 0, quality=True performance=True; peak RSS 4100.37 MiB. Android native probe 35253859334 / 105312834106 SUCCESS without INTERNET, llama.cpp / verified weights; cold 218780.915 ms, warm median 182518.543 ms, PSS 1311.397 MiB. | Full Godot AIClient Android E2E red; real physical Android benchmark and usability/performance acceptance; packaged final V1.4 benchmark. No proof of ChatGPT/Claude-level capability from this small suite. |
| Knowledge | 60 | Knowledge Performance 35253859283 SUCCESS; source streaming/transaction/registry paths inspected. Exact-head synthetic 1GiB stress 35253859168 / 105312675022 SUCCESS: 1073742199 dataset bytes, peak RSS 901017600 bytes, restart_ok=true, no external runtime. | Genuine >=1GiB bootstrap pack, sharded manifest/hashes/provenance/licenses and Windows/Android import/query proof. Stress generator uses repeated filler/x.repeat(700); cannot satisfy genuine pack requirement. Export and final packaged device acceptance not independently proven. |
| Memory | 40 | memory_store/local semantic contracts, Semantic Memory CI 35253859240 SUCCESS, Knowledge Performance SUCCESS. | Full report contents/real Android restart/search/export/restore at production scale, final device acceptance. |
| OCR | 40 | Local Tesseract rus+eng Windows packaging and PDFBox+Tesseract4Android source/dependency/bounds/cancel contracts inspected; Windows package and Android Plugin CI 35253859261 SUCCESS. | Android installed APK real scanned/mixed ru/en OCR and large-PDF runtime; final offline-device proof; independent OCR report inspection. |
| Voice | 40 | Android Voice 35253859478 proves asset layout and Kotlin compile only. Supertonic Acceptance 35253859172 SUCCESS with evidence artifact 10511768376. | Windows package CI AND release.yml both use -SkipVoiceSetup. This package proof does not guarantee bundled Windows voice backend/models, local STT/TTS invocation on installed package or offline voice. Android installed voice invocation and human listening still missing. |
| UI | 60 | UI Visual 35253859237 / 105312822181 SUCCESS: structural/portrait/owner-art/keyboard/loading/offline/error/cancel/pointer/render-matrix steps all green. Actual runtime main_compat surfaces inspected. | Independently view captured frames and test physical Android keyboard/taps/orientation; installed signed V1.4 UI acceptance. |
| Work Agent | 40 | Work Mode 35253859280 and Work Computer Reliability 35253859599 SUCCESS; WorkStore failure/concurrency smokes present. | Inspect exact runtime failure-injection outputs, installed Windows/Android Work lifecycle/restart and final release acceptance. |
| Computer Agent | 40 | Reliability 35253859599 SUCCESS; bounded local primitives/default-OFF permission integration in client/overlay, new source paths retained. | Real installed Windows screenshot/actions/master-stop test; Android explicit unsupported behavior/device proof, final acceptance. |
| Android | 40 | Build/export/test-sign/install succeeded in failed APK/E2E jobs; API35 native no-INTERNET probe succeeds. APK workflow fails logcat collection (exit255), E2E suppresses run-as failure and never collects report. | New runner CI; full normal-path Core/Voice/Knowledge/OCR installed behavior, physical device, permanent signing continuity, signed V1.4 versionCode increase. |
| Windows | 60 | Windows Package 35253859209 / 105312824372 SUCCESS: EXE smoke, installer, silent install/uninstall, installed model hash, V1.2/V1.3 bridge steps. | Offline installed voice/Computer/File functionality beyond 3-frame headless startup, final signed-floor/update/package V1.4 acceptance. |
| API | 40 | API CI 35253859249 SUCCESS; account/guest/privacy/SQLite/request/mail contracts present and inherited. | Inspect full exact test reports; real production deployment/ingress/account delivery and final candidate regression evidence. |
| Server | 20 | REG.RU deploy/install/update/rollback scripts and local readiness contracts exist; API CI green is not deployed-host evidence. | Authenticated host deployment, /ready, DB backup/restore/rollback and production mail transport proof. No host access verified in this session. |
| Updater | 40 | Release Identity 35253859409 SUCCESS; pinned public cert/key/floor contracts and Windows V1.2/V1.3 repair smoke SUCCESS. | Actual signed V1.4 latest update.json + update.sig/assets, invalid-signature/hash rejection in installed floor and upgrade/repair/rollback end-to-end. |
| Installer | 60 | Windows package job builds Inno installer, performs silent install/model-integrity/app smoke/uninstall and historical bridges SUCCESS. | Final V1.4 installer with all voice dependencies/assets and full installed offline functionality, signed release/update linkage. |
| Release | 20 | Version/signing/release contracts present; source still V1.3, one repair prerelease only. | Final same-SHA all gates, genuine knowledge payload, devices/listening, version metadata/changelog bump, RC/full CI, then main merge and production release. |

Artifact metadata personally fetched (contents not downloaded through UTF-8-only connector): Windows artifact 10513160789 digest sha256:337b99ce3b50fe1d0ea162f92dec2a1684b7cd09ff33eb74d9993d9715146513; Core 10511848740 digest sha256:d338f4a47410999f98cafb4946ed055fc591fd724e605f1aeb0c0adeaa41d0bb; Android native 10512234902 digest sha256:27f48c6d05776bc1a162ed7bb823448a9adcb20717a7f693de8266f63d46d8ea; synthetic stress 10515131891 digest sha256:a173d67e0df4481cda703840194d05731fdc2bab6497068685ddf30ac93addb6. Logs for these four jobs read directly. Artifact existence/digest alone is not content/visual acceptance.

### ACTION / FILES / DIFF / TEST / RESULT / COMMIT

ACTION: repair Android release-report transport/lifecycle and fail-closed launch diagnostics.
FILES: benchmarks/core/run_android_godot_e2e.sh; benchmarks/core/run_android_apk_smoke.sh; tests/test_android_e2e_runner.py; tests/test_android_contract.py; .github/workflows/core-android-e2e.yml; .github/workflows/android-apk-artifact.yml.
DIFF: root only on disposable google_apis emulator reads release APK private report without making product debuggable; waits for completed status, preserves running report, detects early process exit, filters app diagnostics, required.issubset(rows) rejects missing mandatory scenarios even with extra rows. APK smoke executes in one Bash process with pipefail; retries logcat transport at most3 times with timeout30s, records stderr, still rejects persistent collection failure, empty PID, wrong version and app crash. Relevant CI runs new runner unit tests.
TEST: python -m unittest tests.test_android_e2e_runner -v; python tests/test_android_contract.py; direct invocation of both tests/test_core_android_e2e_contract.py functions; bash -n on both runners; git diff --check.
RESULT: 8 runtime lifecycle/fault-injection simulation tests PASS (3.013s), Android contract OK V1.3.0.0/code100005, 2 E2E contracts PASS; Bash syntax/diff checks PASS. Simulated adb tests are NOT Android inference/device proof. Real CI remains pending on new commit.
COMMIT: 8c61086b7ef9dfba3631b53a3e3624ba321d737f (non-force advance of existing PR #92; no replacement PR/main merge/version bump).

PROGRESS_COMPLETE: 40%
PROGRESS_REMAINING: 60%
Readiness uses 20 equally weighted release checkpoints for this audit, 8 confirmed automated boundaries: Windows Core; Android native Core; chat learning attachment smoke; Knowledge/Memory durability/scaling; synthetic1GiB stress/restart; research/evolution safety; Work/Computer contracts; API/account contracts. Remaining12: Android full normal-path E2E; installed APK launch; Windows installed offline voice/files/computer; installed Android voice/OCR/Knowledge; genuine knowledge corpus; sharded pack/provenance/licenses; real Windows/Android device benchmark; human UI/voice acceptance; deployed server/rollback/mail; final version/versionCode/metadata; same-SHA complete RC CI; production signing/update/release. Thus 40% is release acceptance coverage, not average table percentages or inherited 90% prose.
DONE:
- Current repository/PR/branches/releases and 24 workflow statuses audited; direct benchmark/stress/package logs and artifact metadata checked.
- First implementation batch committed with passing local fault-injection tests; new CI automatically follows PR update.
REMAINING:
- Twelve acceptance checkpoints above. Plain arbitrary-name TXT/PDF/documents are analyzed as chat attachments; auto-learning classification requires filename/manifest markers. The broad user-import requirement needs a concrete explicit chat import flow/test before acceptance; do not silently treat analysis as persistent Knowledge import.
BLOCKERS:
- Actual genuine corpus is not supplied/proven; current synthetic pack is filler.
- Current Windows CI/release packaging deliberately skips voice provisioning, so full offline voice acceptance is absent.
- Physical devices, human listening and authenticated production host/signing availability not verified.
NEXT:
- Inspect new exact candidate Android CI/job outputs before declaring runner repair accepted. If product fails, use preserved partial report/app log to fix reproduced cause. In parallel audit/fix Windows full offline voice packaging and explicit chat import coverage in a newly extended claim; genuine owner-supplied Library knowledge archive must be inspected for content/provenance rather than counted by ZIP size.
- Keep PR #92 draft until final acceptance; never bump/publish changed normal binaries as V1.3.


## 45. Knowledge archive byte audit; offline Windows voice packaging claim extension

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: ACTIVE, intended accumulated MINOR unchanged.
- Original user archive `AuroraFox_Knowledge_CUMULATIVE_2026_09_v14(1).zip` fetched and inspected as data only. ZIP SHA256 `e2564095ae05bc086143517cc2bf8195eefaba947f44d4b59427a359740ab11c`; 29 top-level entries, immediate expanded bytes 201126321; recursive 10 ZIP containers hold 899 JSONL files / 10125430370 leaf JSONL bytes, including historical duplication. This is not a claim of 10GB unique genuine knowledge.
- Manifests explicitly distinguish 4.22M physical rows and 72M logical Cartesian cases; sampled cases are synthetic_skill_case and resource_locator_url Google search templates, not source-document content. v14 truth metadata explicitly says schema PASS is not truth PASS. The archive does not prove >=1GiB genuine redistributable knowledge, production shard contract or Android import. Embedded Python scripts were not executed; no useful existing pack content discarded.
- New owned batch: build/build_windows.ps1, voice/build_backend.ps1, voice/python/aurora_voice_server.py, Windows package/release workflows, new installed offline voice smoke, relevant packaging tests and this journal. Reconciles previous VOICE/PLATFORM ownership under owner-appointed final engineer; no change to default voice quality or signing identities.
- Reproduced source blocker: both CI and release skip Windows voice provisioning. Secondary source blocker: frozen backend uses __file__ for config root despite builder staging config beside executable; resolve frozen root from executable. Stop accepting copied non-relocatable .venv as a complete portable release fallback.
- Required acceptance: full staged backend/models, installed package local TTS+STT real HTTP invocation with offline model flags and an outbound firewall rule for the executable, report/WAV retained. Keep subjective listening separate. Use ZIP64-capable packaging rather than Compress-Archive's large-file boundary for expanded voice payload.

PROGRESS_COMPLETE: 40%
PROGRESS_REMAINING: 60%
DONE: genuine archive vs synthetic stress evidence separated; source packaging omissions reproduced.
REMAINING: full Windows offline voice packaging/run acceptance and twelve release checkpoints.
BLOCKERS: genuine production corpus remains missing/unproven; devices/host/signing availability unverified.
NEXT: implement full portable voice packaging and installed offline smoke, then exact Windows CI; no version bump/merge/release.


## 46. WORK-2026-09-17-FINAL-RELEASE — Windows installed offline voice gate

ACTION: Removed SkipVoiceSetup from Windows package CI and production release. Packaging now refuses incomplete portable voice output. Corrected frozen backend configuration root and PowerShell UTF-8 BOM reading; PyInstaller installation uses bundled uv rather than assuming venv pip. Added installed TTS/STT acceptance with outbound firewall block, offline cache flags, health wait, WAV evidence and JSON report. ZIP packaging uses 7-Zip for large offline payloads.
FILES: .github/workflows/windows-package-ci.yml; .github/workflows/release.yml; build/build_windows.ps1; voice/build_backend.ps1; voice/python/aurora_voice_server.py; tests/windows_installed_voice_smoke.ps1; tests/test_windows_voice_package.py.
DIFF: Production packaging must contain portable voice backend; installed backend must synthesize Silero WAV and transcribe it locally. Firewall cleanup and environment restoration run in finally. Human listening is explicitly unverified.
TEST: python -m unittest tests.test_windows_voice_package tests.test_android_e2e_runner -v — 12 tests passed (2.897 seconds). Python compilation and git diff --check passed in local inspection. No PowerShell or Windows runtime exists in this Linux workspace; installed smoke requires real Windows CI.
RESULT: Source and regression tests verified. Full Windows package, firewall operation, installed voice model availability, performance, human quality and Android product execution remain pending. No version bump, main merge, RC or release authorized by test evidence yet.
COMMIT: 415b47a2ebf56f9ad365bdfaf98c718ee6a13e9d (implementation). This journal commit follows it; both published together to avoid canceling an intermediate CI run.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 40%. Component assessment remains section 44; new implementation does not earn runtime/release credit until same-SHA checks pass.


## 47. BEFORE ACTION — Windows package parse repair, 2026-09-18

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: ACTIVE; accumulated MINOR / V1.4.0.0 remains test-first/version-last.
TIME: 2026-09-18 (GitHub-only continuation).
TASK: repair exact Windows Package run `35280387297` before any further release work.
WHY: job `105400709410` failed in step 3 before packaging. The log proves Windows PowerShell 5.1 cannot parse a Cyrillic UTF-8-without-BOM literal in `tests/windows_installed_voice_smoke.ps1`; inspection of the emitted workflow script also shows a missing comma before that helper entry.
CURRENT STATE: PR #92 head `7f65d11c1b8fd4f2ff8aa6c1822b00c111d5be9e`; 19 workflows SUCCESS, Windows Package FAILURE, Android APK/Core/Knowledge heavy gates still running. No release/version bump.
EXPECTED RESULT: PowerShell helper parse step passes on Windows and the same workflow proceeds to real installed offline voice packaging/smoke.
RISKS: a parse-only fix may reveal a later genuine packaging/runtime failure; that result must be inspected rather than bypassed.

PROGRESS_COMPLETE: 40%
PROGRESS_REMAINING: 60%
DONE: exact failing run/job/step and two source causes classified from GitHub Actions logs.
REMAINING: minimal source repair, exact-head Windows rerun, then remaining same-SHA release gates.
BLOCKERS: Windows installed offline voice/package gate is red at parse stage; genuine Knowledge corpus and external device/host/signing boundaries remain.
NEXT: update only the workflow delimiter and non-ASCII PowerShell test literal, then inspect the new exact-head Windows result.


## 48. BEFORE ACTION — release-size voice baseline and Android launcher readiness, 2026-09-18

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: ACTIVE; accumulated MINOR / V1.4.0.0 remains test-first/version-last.
TIME: 2026-09-18 (GitHub-only continuation).
TASK: close two exact-head release blockers reproduced on `5ef78fc17397c653a883cebdb62759af186d1f21`.
WHY: Windows Package run `35283295294`, job `105409940361`, proves full offline voice is built but Inno Setup rejects the single installer above 4,200,000,000 bytes; Whisper large-v3-turbo is the dominant payload. Core Android E2E run `35283295232`, job `105410103687`, proves build/install/offline setup but launches immediately after `adb root`, before Package Manager again resolves the launcher.
CURRENT STATE: 21/24 same-SHA workflows SUCCESS; Android Core E2E FAILURE; Windows Package FAILURE; synthetic Knowledge 1GiB still running. No version bump or release.
EXPECTED RESULT: retain a useful Russian offline STT baseline with a single-file Windows installer below the platform limit, and make Android E2E wait for/launch the resolved activity after adbd restart.
RISKS: a smaller Whisper model trades some recognition quality for installability; objective installed TTS/STT smoke remains mandatory and subjective listening remains separate. Android launch readiness must not weaken offline or completed-report checks.

PROGRESS_COMPLETE: 40%
PROGRESS_REMAINING: 60%
DONE: exact Windows size failure and Android post-root launcher race classified from GitHub logs.
REMAINING: minimal implementation/contracts, exact-head Windows and Android reruns, then remaining release gates.
BLOCKERS: single-file installer limit and Android E2E launch race; genuine Knowledge corpus and external device/host/signing boundaries remain.
NEXT: switch packaged default STT to a smaller local Whisper baseline consistently, add package-size/config contracts, and wait for the resolved Android launcher before explicit start.

## 49. BEFORE/AFTER ACTION — handoff обычному чату для доведения до релиза, 2026-09-18

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: ACTIVE; accumulated MINOR / V1.4.0.0 остаётся test-first/version-last.
TIME: 2026-09-18 (только GitHub; локальный ПК пользователя не использовать).
BEFORE ACTION TASK: оставить самодостаточное задание следующему обычному чату на случай исчерпания контекста/токенов финального инженера.
REPOSITORY: `Treninem/AI`; draft PR #92; branch `chat-2026-09-17-unified-finalization`; audited product HEAD `4f0349612d36dab01cad1fb913154114d9adb49e`; base `main` at `031aebaad16fc25a39dfc45c58f96fadb658cac2`.
CURRENT EXACT-HEAD CI BEFORE THIS JOURNAL COMMIT: 24 workflows total; 15 SUCCESS; 9 IN_PROGRESS; 0 observed failures. Running: Android APK Artifact `35288500991`; Knowledge Performance `35288500891`; Android Plugin CI `35288500982`; Core Android Benchmark `35288501021`; Core Android E2E `35288501145`; Supertonic Acceptance Evidence `35288500775`; Core Benchmarks `35288500844`; Knowledge 1GiB Release Gate `35288500829`; Windows Package CI `35288500840`.
RECENT FIXES TO VERIFY, NOT ASSUME: commit `50edce32603396306fa998960706034b63269e79` changed packaged STT consistently to `openai/whisper-small` so the required single-file Windows installer can fit, and made Android E2E wait for the launcher after `adb root`; commit `4f0349612d36dab01cad1fb913154114d9adb49e` changed emulator installation to `adb install --no-incremental -r` after logs proved the incrementally streamed package disappeared across adbd restart.

### CONTINUATION TASK FOR THE NEXT NORMAL CHAT

1. Work only through GitHub/repository tools as the owner requested. Fetch fresh PR #92 head and `main`; read `AGENTS.md` and this entire canonical journal first. Continue this claim; do not create another journal and do not treat this recorded SHA or 40% as fresh truth.
2. Inspect workflows for the latest product SHA. Fix only failures reproduced there. Journal-only commits may start new runs, so distinguish the audited product SHA from the handoff commit and do not restart expensive jobs without an actionable reason.
3. Close Windows acceptance: prove one installable single-file installer below the Inno limit, portable offline voice contents, installed Silero TTS plus Whisper STT HTTP smoke with outbound network blocked, EXE/startup/bridges/update/silent install/uninstall, retained reports/WAVs. The `whisper-small` change earns no readiness until this passes.
4. Close Android acceptance: prove API 35 build/install/explicit launch after `adb root` using non-incremental install, normal offline product path, Voice/Knowledge/OCR, retained report/logcat/screenshots. Do not weaken completion assertions to make CI green.
5. Visually inspect actual Windows and Android render/screenshot artifacts: owner avatar/art, layout, button and tap targets, keyboard, scrolling and orientation. Structural green CI is not visual acceptance; do not replace the existing avatar without a reproduced reason.
6. Replace the synthetic 1GiB stress artifact with a genuinely useful, redistributable Knowledge pack only when real source material, provenance and licenses exist. Require manifest, shards and hashes plus Windows/Android import and query proof. The audited v14 archive contains synthetic/duplicated cases and is not proof. Never pad or relabel filler. If genuine data is unavailable, record the external blocker and ask the owner one precise question.
7. Verify production API/REG.RU readiness, database backup/restore and mail delivery when credentials/access exist. Treat physical devices, human voice listening, production signing keys/Android lineage and production host secrets as owner-controlled boundaries; never invent or expose credentials or private keys.
8. Only after every internal gate is green on one same product SHA: bump accumulated release identity to `V1.4.0.0` with Android `versionCode > 100005`; synchronize `project/version.json`, `project.godot`, `export_presets.cfg`, installer/update manifest, changelog and release notes; rerun version/package/update/release gates.
9. Keep PR #92 draft until genuine acceptance. Merge to `main`, tag and publish the GitHub release only after same-SHA gates are green and owner-controlled signing/deployment boundaries are satisfied or explicitly authorized. “Доводи до релиза” is the target, not permission to fabricate missing evidence.
10. After every meaningful batch append BEFORE/AFTER evidence here: exact commit, workflow/run/job, artifact and result; update DONE/REMAINING/BLOCKERS/NEXT and the readiness footer. Continue autonomously until a real external owner-only blocker remains; then stop and ask exactly one focused question.

AFTER ACTION: durable continuation instructions recorded in the canonical master log only; no product code changed by this action. The GitHub contents update that adds section 49 is the handoff commit; the next chat must record its resulting branch HEAD before further work.

PROGRESS_COMPLETE: 40%
PROGRESS_REMAINING: 60%
DONE: reproduced Windows installer-size and Android post-root package-loss causes repaired in product commits; exact-head CI launched; release continuation made self-contained.
REMAINING: consume exact CI results; close Windows/Android/runtime/visual/Knowledge/API acceptance; synchronize V1.4 identity; final same-SHA gates; merge/tag/release.
BLOCKERS: genuine production Knowledge corpus/provenance remains absent; physical-device, human-listening, production-host and signing evidence depend on owner-controlled access. In-progress workflows are not evidence of success.
NEXT: first inspect completion of Windows Package `35288500840` and Core Android E2E `35288501145`, then the other seven running jobs; act only on their exact logs/artifacts.

ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 40%

## 50. BEFORE ACTION — reconcile 95% claim and continue exact CI repair, 2026-09-18

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: ACTIVE; accumulated MINOR / V1.4.0.0 remains test-first/version-last.
TIME: 2026-09-18 (GitHub-only continuation).
OWNER QUESTION: why an earlier chat reported 95% while this finalization reports 40%.
ANSWER: 95% was a feature/lane-level estimate based on historical or branch-local completion. It was not backed by one unified releasable SHA passing Windows installer, Android runtime, visual, genuine Knowledge, production API, signing and deployment acceptance. The current 40% is the conservative release-readiness baseline defined by sections 43–49; incomplete, cancelled or external gates earn no credit. Do not average or inherit stale percentages.
AUDITED HEAD: `2b988eefdaa290b1f0dd5f23aa557474429ba8f5` (journal-only child of product fix `4f0349612d36dab01cad1fb913154114d9adb49e`).
CI SNAPSHOT: 21 SUCCESS; Core Android Benchmark run `35288786731` FAILURE; Core Android E2E run `35288786692` FAILURE; Windows Package CI run `35288786712` CANCELLED.
TASK: inspect exact job logs for both Android failures and distinguish infrastructure/cancellation from product failure; inspect the last uncancelled Windows product run before deciding whether to rerun or patch. Fix only reproduced causes, then append AFTER evidence.
EXPECTED RESULT: Android product gates pass without weakened assertions; Windows installed offline voice package completes; readiness changes only from verified same-SHA evidence.
RISKS: every journal commit retriggers PR workflows and may cancel expensive Windows work; prefer inspecting preserved runs and make the next code update atomic.

PROGRESS_COMPLETE: 40%
PROGRESS_REMAINING: 60%
DONE: conflicting percentage semantics reconciled against release acceptance.
REMAINING: classify exact Android/Windows results and repair verified blockers.
BLOCKERS: two Android gates red; current Windows run cancelled; external corpus/device/host/signing boundaries remain.
NEXT: fetch jobs, failing steps and logs for runs `35288786731`, `35288786692`, and the latest preserved Windows run.

ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 40%

## 51. AFTER ACTION — Android Java bridge dispatch and bounded exact-output inference, 2026-09-18

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: ACTIVE.
EVIDENCE: Core Android E2E run `35288786692`, job `105427103660`, installed and explicitly launched the offline APK, verified the 1,282,439,264-byte model and SHA `d2387ca2...`, but the report exposed only fallback capability values (`llama_cpp=false`, `isolated_service=false`) and stopped at `bundled_core_identity`. The release bridge found the Java singleton but rejected valid `@UsedByGodot` methods behind `Object.has_method()`. Godot's Android plugin contract requires exact Java method names and direct singleton invocation.
EVIDENCE: Core Android Benchmark run `35288786731`, job `105426996979`, loaded the APK/model and launched `MainActivity`, but three exact-output samples with a 48-token cap did not finish within 900 seconds on the API 35 x86_64 emulator.
ACTION: call the known, same-build Android Java plugin API directly after singleton discovery; retain null guards and exact method names. Reduce only the explicit terse/exact-output inference ceiling from 64/48 to 16 tokens; normal chat remains 384. Semantic expected-output assertions, offline guard, model identity and real llama.cpp execution remain mandatory.
FILES: `scripts/android_local_runtime.gd`; `benchmarks/core/android_probe/app/src/main/java/com/aurorafox/corebenchmark/MainActivity.kt`; `tests/test_android_contract.py`; `tests/test_core_android_benchmark_contract.py`; this journal.
TEST STATUS: source contracts added in the same atomic commit. Runtime acceptance is pending fresh exact-head Core Android E2E and Benchmark workflows; no readiness credit claimed yet.
WINDOWS: run `35288786712` was cancelled at the historical bridge step by a newer PR commit, not a product assertion. The next exact-head Windows Package run must finish before classification.

PROGRESS_COMPLETE: 40%
PROGRESS_REMAINING: 60%
DONE: exact Android runtime causes classified and minimally repaired without weakening offline/model/quality assertions.
REMAINING: verify both Android gates and complete the uninterrupted Windows installed offline voice/package run.
BLOCKERS: runtime CI proof pending; genuine corpus/device/host/signing boundaries unchanged.
NEXT: inspect workflows started by this atomic commit; if Android is green, inspect retained reports/artifacts and visual evidence, then let Windows finish without journal-only interruption.

ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 40%

## 52. BEFORE ACTION — sole final engineer continuation, 2026-09-18

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: ACTIVE — OWNER-DIRECTED SOLE EXECUTOR TAKEOVER/RECONCILE.
- Owner explicitly instructs this session to work alone and take unfinished tasks from other lanes. No subagents or reliance on another executor. Existing code and evidence are preserved.
- Fresh main `031aebaad16fc25a39dfc45c58f96fadb658cac2`; inherited PR #92 head `c5d9183433c985a1e834a46345db7a8fe7ccec5f`. Full main journal and candidate additions 43–51 read; section 40 notification acknowledged.
- Intended accumulated bump MINOR / V1.4.0.0, test first/version last.
- Exact current failures personally inspected: Core Benchmarks `35304140196` / `105472793773` fails an obsolete assertion expecting Android terse=64 while production=16; Windows runtime was skipped. Android normal-path E2E `35304140175` / `105472917764` reaches real offline inference but all answer scenarios return truncated `<think>` content. Android native probe `35304140103` / `105472867694` times out after 900s. APK `35304140172` / `105472800202` crashes during Godot import (dialog parenting errors followed by double free).
- Owned batch: Android production prompt formatter/NativeRuntime, native probe, related runtime/contracts/tests, build/build_android.ps1 and canonical journal. Reconciles previous Core/Platform ownership; no safety/signing/offline/expected-answer gates removed.
- Ownership extension for executable prompt regression coverage: plugin Gradle test dependency, CoreChatPromptTest and android-plugin-ci test task; `.gdignore` in native/probe source trees. Exported addon in `addons/AuroraFoxRuntime` stays visible to Godot.
- Scheduling ownership extension: windows-package-ci concurrency sets cancel-in-progress=false to preserve the current expensive run while the next atomic candidate queues. Sections 49–51 document previous cancelled Windows runs; no product gate/timeout is bypassed.
- Source cause: Android hand-written ChatML generation prefix omits Qwen3 non-thinking template suffix; reducing token budget alone truncates thinking before the answer. Need a shared production formatter used by plugin and probe, then real CI proof. Import crash requires source/log investigation before changing build behavior.

PROGRESS_COMPLETE: 40%
PROGRESS_REMAINING: 60%
DONE: fresh main/candidate/full journal and exact failing jobs inspected; sole ownership recorded.
REMAINING: reproduce and repair prompt/bounds/import failures, relevant local tests, exact-head runtime/package CI and remaining release checkpoints in section 44.
BLOCKERS: current Android runtime/package and Core gate failures; genuine corpus and physical-device/host/signing acceptance remain unproven.
NEXT: implement shared Qwen3 non-thinking prompt suffix and validate production/probe integration; inspect first import errors and reproduce import separately; publish one atomic batch to existing draft PR #92.

## 53. AFTER ACTION — mobile prompt and import batch, 2026-09-18

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: ACTIVE, sole executor.
ACTION: shared production CoreChatPrompt starts generation after an empty closed thinking block for the bundled Qwen3, aligned with desktop non-thinking default. Plugin and native benchmark both use it. Normal mobile chat remains 384 tokens; terse=16; expected-answer gates unchanged. Godot ignores native/probe build source trees while exported addon stays visible. Windows expensive workflow is no longer cancelled by each newer candidate.
FILES/DIFF: 13-file implementation in commit `8f0a2788eab3207e250efe6757bb1cf7a5816ac1`; includes prompt formatter, executable Kotlin regressions and Gradle/CI wiring, probe integration, stale terse assertion correction, source `.gdignore`, Android contract and scheduling/journal.
TEST: Python relevant gate/runner/package set 42 passed (3.75s); real Kotlin compiler 2.1.20 + JUnit 4.13.2: 3 passed (0.026s). Godot 4.7.1 headless import exit 0 with no parse errors. Planted native-tree CSV was not queued/imported (no sidecar), import exit 0. Android release contract PASS. Chat context `AURORA_CHAT_CONTEXT_SMOKE_OK`, self-reliance `SELF_RELIANCE_SMOKE_OK`; these smokes report resource-leak warnings on exit, not actual LLM quality/device proof. git diff --check PASS.
RESULT: local code/contract/formatter/import checks green. Android native/Godot inference and release APK CI remain required; no readiness gain from source changes alone. Current Windows run `35304140155` is preserved and still in progress at publication preparation.
COMMIT: locally verified implementation `8f0a2788eab3207e250efe6757bb1cf7a5816ac1`, local evidence commit `962ff71`. Shell Git push has no authenticated credential and failed before writing; publish the identical reviewed file contents through the authenticated GitHub connector as one fast-forward commit on PR #92. Remote publication SHA must be read back and recorded in the next checkpoint; local SHAs are not remote links. No replacement PR/version bump/main merge/release.

PROGRESS_COMPLETE: 40%
PROGRESS_REMAINING: 60%
DONE: three current failure causes repaired with local executable tests; independent local Core path preserved.
REMAINING: exact-head Android/Core/package CI, installed Voice/OCR/Knowledge, genuine pack/provenance, actual visual/listening/device/server/signing and final version/release checkpoints.
BLOCKERS: runtime/package acceptance pending; genuine production corpus and external device/host/signing evidence remain unproven.
NEXT: inspect workflows on the published journal head (product parent above); classify only new exact failures. Preserve current Windows evidence and distinguish its older SHA from new same-SHA acceptance. Keep PR draft.

ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 40%

## 54. Sole engineer visual evidence ownership extension

### BEFORE ACTION — visual evidence ownership extension, 2026-09-18

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: ACTIVE, sole executor; publication head `e6d2fd2f12d985a31868473bb1e5abc18123d7f2` verified through PR #92.
- Actual UI artifact `10530997398` / run `35304140134` downloaded and ZIP SHA-256 verified: `d0bb276217e10fbb5ed7a08b92030f8d81f08a94a47c1b4cbc72fbbb767f7b95`.
- Viewed desktop chat, 480px portrait chat/keyboard/account, 720px Knowledge and compact Work/Computer frames. Work compact header renders New project and Close as empty pills; their text exists but generic theme sets clip_text=true, so their minimum width collapses. This is a reproduced visual defect despite green structural CI.
- Owned next independent batch: work/work_overlay.gd, scripts/desktop_visual_theme.gd, tests/ui_work_computer_visual_capture.gd and this journal. Preserve runtime/lifecycle/master-stop and owner artwork. Add identifiable header actions, preserve their measured label widths and reject collapsed actions in render gate. Portrait capture is a desktop preview/simulated keyboard, not physical Android proof.
- Local work only while exact-head Android/Core CI runs; publish the next atomic batch after consuming current heavy results to avoid unnecessary cancellation.

### AFTER ACTION — Work action geometry and autonomy evidence, 2026-09-18

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: ACTIVE, sole executor.
OWNER REQUIREMENT: owner reaffirms that Core must operate independently without third-party means. Normal Core uses the bundled runtime/weights/local memory and knowledge; no required cloud inference, Ollama, external AI API or Internet. Existing optional compatibility must not become normal fallback.
ACTION: name the two Work header actions and preserve measured text width using the existing safe flow-button styling. Add geometry assertions to the render gate and extend owned `tests/desktop_ui_smoke.gd` with executable header checks.
PROOF: compact 960x640 production-scene probe before: New project 24px / label116px and Close24px / label69px, clip=true. After:146px and99px, clip=false. Permanent headless UI smoke rejects original theme with exit93 and `Work header action label collapsed: WorkNewProjectButton`; restored fixed theme passes `AURORA_DESKTOP_AND_MOBILE_UI_SMOKE_OK`. Owner-art smoke passes. Shutdown leak warnings remain (UI7 objects/2resources); not claimed resolved.
AUTONOMY: `tests/test_standalone_core_contract.py` 12 passed (0.05s); real Godot `OFFLINE_AUTONOMY_SMOKE_OK` (exit0, existing7objects/3resources shutdown warnings). Relevant safety/evolution/privacy22 and branding4 Python tests passed. These validate routing/contracts, not full inference or actual device acceptance.
VISUAL LIMIT: local Xvfb cannot establish a usable display in this execution environment; no updated local screenshot is claimed. Source geometry and prior downloaded artifact are actual evidence; new CI render remains required. Portable QA tools and the temporary xkbcomp symlink were cleaned up from system paths; no build dependency added.
CI CHECKPOINT: remote e6d2fd2 has18/24 successful workflows; Android Plugin compiled both AARs and executed `:plugin:testDebugUnitTest` successfully. Windows real SpecialistTeam/CodeSpecialist step is successful, full benchmark pending. Android native probe, normal-path E2E/APK, synthetic Knowledge1GiB and queued Windows package are still pending. Old Windows c5 run35304140155 is preserved, but cannot establish same-head acceptance.

PROGRESS_COMPLETE: 40%
PROGRESS_REMAINING: 60%
DONE: remote Android prompt/import repairs published and plugin compiled; actual collapsed Work actions repaired and proven by failing-before/passing-after regression; self-primary routing rechecked.
REMAINING: consume exact-head runtime/package results, publish reviewed Work UI batch, then new exact-head render/package/runtime evidence and section44 release checkpoints.
BLOCKERS: heavy runtime/package CI pending; genuine licensed1GiB corpus and physical-device/host/listening/signing acceptance unproven.
NEXT: preserve current heavy CI until reports are available; classify actual failures before next atomic PR92 update. Keep draft/no version bump/no main merge/no release.

### BEFORE ACTION — preserve all expensive in-flight evidence, 2026-09-18

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: ACTIVE, sole executor; ownership extends to concurrency scheduling in Core Benchmarks, Core Android Benchmark/E2E, Android APK and Knowledge1GiB workflows. The reviewed UI commit is local `df0344a`; not yet a remote publication.
REASON: these five workflows still cancel current real evidence on each newer PR commit. Preserve their running tests using cancel-in-progress=false, as already done for Windows Package; let the newest candidate queue. GitHub may replace an older pending candidate, which is scheduling and not a failed product assertion. No gate, expected output, offline guard, checkout SHA or timeout changes. This allows publishing the reviewed UI batch without discarding e6 runtime reports; it supersedes the previous plan to hold every change until all long jobs finish.

AFTER ACTION: five workflow YAMLs parse, concurrency=false verified;29 relevant Core/Android/Knowledge contract tests pass (0.08s), diff check passes. Android e6 APK export/import now succeeded and reached signing/install; native probe and normal-path inference are running. Publish UI+headless/render regressions+preserved CI scheduling+this journal atomically to existing draft PR92. Remote commit SHA must be read back; local df0344a is not a remote link. Same-head final evidence remains required and readiness40% unchanged.

PROGRESS_COMPLETE: 40%
PROGRESS_REMAINING: 60%
DONE: Work UI fix executable regression proven; heavy evidence scheduling preserved without changing product acceptance.
REMAINING: real Android inference reports and exported APK launch, uninterrupted Windows packaging/benchmarks, updated UI frames and final release checkpoints.
BLOCKERS: genuine useful licensed1GiB corpus, physical-device/host/listening/signing evidence and incomplete package/runtime gates.
NEXT: read back remote PR92 publication, inspect preserved e6 reports; inspect newest candidate CI as it finishes. No version bump/main merge/release.

ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 40%

## 55. BEFORE ACTION — exact candidate checkout for release evidence, 2026-09-18

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: ACTIVE, sole executor. Fresh main remains031aebaad16fc25a39dfc45c58f96fadb658cac2; PR92 publication5c7afcdda14f026d609404faa98cd3ed43603e90 verified by Git ref and shell fetch, all10 remote blobs match locally reviewed bytes.
OWNERSHIP EXTENSION: checkout SHA only in the24 CI workflows currently triggered for PR92; preserve already exact checkout/verification and leave promotion, release, updater workflow-run and unrelated/manual candidate workflows alone. Ordinary runtime/safety/signing/source assertions and timeouts remain.
REPRODUCTION: Windows e6 run35308554778 succeeds, artifact10532777456 digestda0a62dd581768c1bb95c310ed5c30698837ef5ccdb3b17f327ef067291db944 verified. Actual benchmark report git_sha8c0efb70d95bc0195d15418c01d7682446c58263 is a PR merge checkout, not associated candidate e6 head.21/21 local-quality scenarios and8/8 Coder operations pass with OS network guards active/Ollama absent; cold3293.713ms, warm median650.221ms, peak4468.85MiB. Hard performance limits pass; relative regression is not applied because no successful main baseline is available. This is genuine offline inference evidence but not exact-head final acceptance.
VISUAL PROOF: current Work UI run35309428195 succeeds; artifact10532497960 digest60ef63ab935a570a36dba820b0cf04d579aba43a3c7a41bc79f59c9edcf8c433 verified. Personally viewed compact960x640 and wide1440x900 frames: New project/Close labels are visible and fit. Head label is5c7, but its default checkout also needs explicit SHA enforcement before final same-SHA acceptance.
NEXT: explicitly checkout PR head (or event SHA for push/manual runs) and reject an actual HEAD mismatch in every missing PR92 gate checkout. No intelligence path change; preserve the running Android/Windows/Knowledge reports.

### AFTER ACTION — candidate checkout guard and Android inference proof

ACTION:21 workflows updated,40 missing checkouts now pin the exact candidate and immediately verify actual Git HEAD. Across24 candidate workflows all45 checkouts use the head/event SHA;5 existing exact guarded checkouts preserved. Other manual promotion/release/updater/candidate workflows untouched.
TEST:24 YAMLs parse; all45 checkout refs verified; all40 added guards use the same executable command. Running that actual command accepts the correct local Git HEAD (exit0) and rejects an intentionally wrong expected SHA (exit1).46 relevant Core/Android/Knowledge/release workflow contract tests pass (0.15s); diff check passes. Windows runner default Python executes the same cross-platform guard; remote jobs remain required.
ANDROID RESULT: preserved e6 normal-path E2E35308554897/job105485808921 succeeds with `AURORAFOX_ANDROID_NORMAL_PATH_GATE_OK`. Artifact10532951299 downloaded/digestb379a9a1f728f2f81d1f5c4ae86c621f46b8fa6d48fe9562db7ce8f06798949c verified; all required answer scenarios now return final answers, not truncated thinking: ANDROID-E2E-READY,63,ЛОКАЛЬНО,MOBILE-42,MOBILE-IVORY-29,ANDROID-COMPAT-LOCAL. Offline environment, bundled model integrity and aurora_core_android retained. Its artifact also identifies the old PR merge SHA8c0efb7; repeat on newly enforced head before exact-head final acceptance. e6 APK35308554793 installation/launch succeeded; native probe remains in progress.

PROGRESS_COMPLETE: 40%
PROGRESS_REMAINING: 60%
DONE: actual Android normal Core path repaired and proven offline; Windows21 scenarios/Coder8 operations and updated Work frames personally verified; final CI evidence checkout ambiguity repaired.
REMAINING: publish exact-checkout batch to existing PR92, inspect newest guards/frames/Android native and normal-path reports, finish Windows installed package/voice and remaining section44 gates.
BLOCKERS: pending package/runtime acceptance; genuine licensed1GiB corpus and physical-device/host/listening/signing evidence remain unproven. No main baseline for relative performance comparison yet.
NEXT: publish atomic CI+journal fast-forward; preserve in-flight expensive evidence and inspect reports by actual SHA. Keep draft, test first/version last.

ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 40%

## 56. BEFORE ACTION — native probe must measure production Release runtime

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: ACTIVE, sole executor. Exact-checkout publication23f5757e42b3dedff84a8cc4f249538d24aaf890 verified remotely and fetched locally; reviewed files match remote tree. Main unchanged.
OWNERSHIP: native probe app build variant, Core Android Benchmark workflow/runner, its contract test and canonical journal.
EVIDENCE: c5 native run35304140103/job105472867694 explicitly builds `:runtime:configureCMakeDebug`/`buildCMakeDebug` with `CMAKE_BUILD_TYPE=Debug`, then900s timeout without report. Artifact10531608631 logcat ZIP downloaded/digest4e5e44f6841c818a5c463efb8897bc5e2c31b8b399f3b001f33252bf6763732e verified. No app-specific kill/crash established; unrelated killed system processes must not be treated as AuroraFox OOM. e6 native probe still running while optimized production normal-path E2E is green.
CAUSE/BOUNDARY: benchmark currently links the unoptimized Debug native library, so it does not measure the production Release runtime. This is a confirmed build mismatch; its contribution to900s timeout is an inference until a new optimized run completes. Use a debuggable/test-signed benchmark app variant with only Release library fallback, preserving run-as/no-INTERNET/model/answer gates and900s timeout. Official Android build-variants documentation confirms initWith/debug and matchingFallbacks selection: https://developer.android.com/build/build-variants#resolve_matching_errors . No normal product runtime behavior change.

OWNERSHIP EXTENSION: probe MainActivity and report reader validate the selected runtime's generated BuildConfig (release/non-debug) at execution and in the report; fail rather than accidentally benchmark Debug again.

### AFTER ACTION — production native benchmark variant

ACTION: dedicated benchmark app variant inherits debug/test-signing/run-as configuration and falls back only to the production runtime Release library. Workflow and runner use assembleBenchmark/app-benchmark.apk. Runtime BuildConfig must identify release/non-debug before inference; report carries both fields and Python reader enforces them. Normal product library/build behavior,900s watchdog,16-token exact-output ceiling, all three semantic/model/no-INTERNET/performance assertions remain.
TEST:5 relevant Android probe/E2E/package contract tests passed (0.05s), runner bash syntax and diff checks pass; YAML parses. Full Gradle variant resolution/build and on-device inference pending new CI, not claimed locally executed. Current e6 Debug-native run still pending; normal-path optimized Android inference already green.

PROGRESS_COMPLETE: 40%
PROGRESS_REMAINING: 60%
DONE: production-vs-Debug benchmark mismatch corrected and hard release-variant checks added; all accepted offline Core/UI proofs preserved in sections54–55.
REMAINING: new Release-native probe and exact-head runtime/package/render reports; uninterrupted Windows package/installed offline voice; genuine corpus/device/host/listening/signing acceptance and final version/release checkpoints.
BLOCKERS: incomplete same-head real gates and section44 external acceptance boundaries. Genuine useful licensed1GiB corpus still unproven; synthetic capacity run is separate evidence.
NEXT: publish this atomic benchmark+journal fix to PR92 and inspect resulting exact-head guard/build reports. No version bump/main merge/release; sole engineer claim stays ACTIVE.

ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 40%

## 57. Sole engineer checkpoint — verified publication and native offline answers

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: ACTIVE, sole executor. Product-code publication73a71420e5fea775848bfcc8abd7b7111e4e039b verified by authenticated Git ref/shell fetch and empty local-to-remote tracked diff. Main remains031aebaad16fc25a39dfc45c58f96fadb658cac2. Owner instruction to work alone and keep Core autonomous remains binding.
EXACT-HEAD PROOF: source73a7142 UI Visual run35310112166/job105490211520 succeeds. Core Evolution run35310112270/job105490211826 succeeds and actual log prints `AURORA_CI_CHECKOUT_SHA=73a71420e5fea775848bfcc8abd7b7111e4e039b`, confirming remote guard execution. This checkpoint is evidence-only; source73a7142 and the subsequent journal-head are distinct SHAs. Final package/runtime acceptance still needs the final selected head.
NATIVE RESULT: preserved e6 native run35308554796/job105485744736 now succeeds. Artifact10533016809 downloaded/digest07d94f0db738bbfed3fab3c48228065fed47f52116a0cfd7f607e678ee5054b9 verified. Report status=completed, passed=true; all3 answers correct: ANDROID-LOCAL-READY,56,ЛОКАЛЬНО; llama.cpp, no INTERNET permission, remote_ai_allowed=false. Debug-native cold332915.049ms/warm median280467.932ms/PSS1151.193MiB; extremely slow compared with optimized normal-path cold32731.408ms/warm21375.532ms. It finishes near900s watchdog. Non-thinking prompt repair is proven semantically on both Android paths; do not claim the old timeout was caused only by Debug. New enforced Release-native variant performance/build remains pending.
WINDOWS: preserved c5 Windows Package35304140155/job105472767790 still at historical V1.2/V1.3 bridge step; exported executable, runtime asset checks and installer build already passed. This does not replace current-head installed offline voice/package acceptance. No current real report/quality assertions bypassed.

PROGRESS_COMPLETE: 40%
PROGRESS_REMAINING: 60%
DONE: sole ownership/full journal continued; Android normal/direct native local answers and Windows21 quality/Coder8 operations verified; Work labels visually fixed; exact-head CI guards published/proven; production Release-native benchmark configuration published.
REMAINING: final-head Release-native/normal-path benchmarks, Windows/Android packages and installed voice/OCR/Knowledge acceptance; section44 version/release checkpoints.
BLOCKERS: genuine useful licensed1GiB bootstrap corpus/provenance and physical-device/host/listening/signing evidence remain unproven; expensive real gates incomplete; no main relative benchmark baseline.
NEXT: inspect the newest PR92 CI by actual head and preserved report SHAs; repair only reproduced failures, finish all available gates. Keep draft/no version bump/no main merge/no release until acceptance. Evidence-only journal updates must not count as product acceptance.

ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 40%

## 58. BEFORE ACTION — verified readiness50% and actual report source identity

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: ACTIVE, sole executor. Fresh main031aebaad16fc25a39dfc45c58f96fadb658cac2 unchanged; current draft PR92 head03ae14bbf3c46414477b3e02630f32a08dd4af69. Previous full main/candidate journal reads remain valid; sections52–57 and section44 checkpoint rubric reconciled.
READINESS: section44 defines20 equally weighted acceptance checkpoints; existing8=40%. Add2 personally verified boundaries: Android full normal-path E2E and installed APK launch. Thus10/20=50%, not22/24 workflow success or commercial capability equivalence. Remaining10 checkpoints: installed Windows offline voice/files/computer; installed Android voice/OCR/Knowledge; genuine corpus; sharded provenance/licensed pack; real device benchmark; human UI/voice; server/mail/rollback; version metadata; complete same-head RC CI; production signing/update/release.
EVIDENCE:22/24 current workflows succeed. Android normal run35310302212/job105492349292 actual checkout guard03ae14b; artifact10534015382 ZIP digest e2a5f767d6079ce4017628141529e208c3472a416515be40194b04b4980658eb verified. All8 scenarios pass (offline guard, model identity, six answer/context/knowledge/compatibility scenarios); cold28532.807ms/warm19973.946ms, external network blocked, remote_ai_allowed=false.
APK ACCEPTANCE: run35310302214/job105491048635 guard03ae14b, installation/version check and `AURORA_ANDROID_EMULATOR_OK pid=2578`; com.aurorafox.ai/V1.3.0.0/code100005, no accepted release signing/device upgrade claim. It is test acceptance, not a published changed V1.3 binary.
NATIVE: Release probe35310302265/job105494782900 guard03ae14b; artifact10534265632 digest5a9d28acdc3157a9dc4c2af183cdfb00b10af39559d90e283da0a7fc632f868e verified; runtime_build_type=release/runtime_debug=false, no INTERNET, all3 answers pass. Cold70571.912ms/warm20634.164ms/PSS1138.409MiB; Debug previous warm280467.932ms. Actual optimized variant validated; not physical-device usability proof.
WINDOWS: Core35310302221/job105491720760 guard03ae14b; artifact10532889210 digestfab3eb5038182edfea8e8cc62638a813c8c88c909ad5eb7de9ee138c269995bd verified;21/21 quality and8/8 Coder operations, hard performance limits pass/no relative baseline. Windows Package35310302289/job105507674904 still Build installer; synthetic Knowledge1GiB35310302273/job105503429773 still real streaming import/restart. Neither pending checkpoint counted.
OWNED FIX: benchmarks/core report runners and three Core benchmark workflows/artifact names, related contract/runner tests and canonical journal. Windows runner wrongly prefers GITHUB_SHA (PR merge7381817) over actual checked-out03ae14b; Android artifact names also use event merge SHA, and Android JSON lacks source SHA. Bind evidence to actual Git HEAD without changing model/answers/offline/performance assertions. Current acceptance is supported by actual checkout guards and verified runtime contents, not misleading artifact labels.
OWNERSHIP EXTENSION: shared stdlib report_identity.py helper, real-Git regression test, Windows CodeSpecialist runner identity, and workflow expected-head/contract wiring. Reject conflicting existing report identity or a mismatched expected checkout instead of silently relabeling a foreign report. Local temporary-Git tests are metadata regression proof, not model inference.

PROGRESS_COMPLETE: 50%
PROGRESS_REMAINING: 50%
DONE: two more section44 checkpoints accepted from actual current-candidate execution and artifact contents.
REMAINING: remaining10 checkpoints and report source-identity repair; finish preserved Windows/Knowledge runs.
BLOCKERS: genuine useful licensed corpus/device/human/host/signing evidence and incomplete final package/runtime gates.
NEXT: repair report/artifact identity, add real Git mismatch regression, then inspect installed-package gates. Keep PR92 draft/version unchanged.

ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 50%

### AFTER ACTION — report identity repaired and tested

ACTION: shared stdlib-only helper reads actual Git HEAD, enforces the expected candidate, rejects conflicting existing report identity, and writes JSON atomically while preserving all runtime results. Windows normal/Coder and Android native/normal runners use it; three workflows label artifacts by candidate head and run identity regressions. No cloud/runtime dependency, model, answer, performance or offline guard change.
TEST:44 relevant Python tests passed in22.34s, including real temporary-Git repositories, poisoned event SHA, expected-head mismatch and foreign-report refusal. Both Android runners pass bash syntax; helper compiles; workflow YAML and diff checks pass. Windows PowerShell execution and new-source runtime CI remain pending, not locally claimed. Preserved current Windows installer and synthetic1GiB import are still running; do not cancel them or count them as accepted.
PROGRESS_COMPLETE: 50%
PROGRESS_REMAINING: 50%
DONE: report provenance repaired; actual Android normal-path/installed APK checkpoints accepted above.
REMAINING:10 release checkpoints, final selected-head CI and installed Windows acceptance.
BLOCKERS: useful licensed corpus/provenance, physical-device/human/server/signing acceptance remain unproven.
NEXT: publish this atomic correction in existing draft PR92 and inspect its actual-head checks; preserve long-running gates. No version bump/main merge/tag/release.

ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 50%

## 59. BEFORE ACTION — owner-directed branch reconciliation, Core refactor and continuation

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: ACTIVE, sole executor; owner explicitly asks to check/combine other chats and leave normal-chat continuation. Fresh main031aebaad16fc25a39dfc45c58f96fadb658cac2; candidate2e905df6ee656d7ff7071ff8918f3767b85a411d, only open PR92/draft. Intended accumulated MINOR/V1.4 unchanged.
BRANCH AUDIT: authenticated API pagination returns123 branches. Shell has124 remote refs including origin HEAD alias;52 refs are ancestors of candidate,72 are not. Non-ancestry alone is not missing implementation: squash/replay/historical alternatives must be reconciled by contents before import. Latest Core51bb186, Knowledge07cf2f5, Platform42fc32b, UI2006566, Voice-r2c18ac6d, Work hardeningf0918a6 and Work20be9b1 are actual ancestors, already combined in PR92. Server5ef7c90 has exactly one candidate-unreachable commit, journal-only takeover claim; api/deploy production files are identical except subsequently expanded API UI settings. No extra server implementation needs merging. Preserve old branches/evidence; never import stale versions/workflows/UI wholesale or claim all historical branches accepted.
REPRODUCED BLOCKER: current Windows Core35318393724/job105515111358 guard2e905df, real Coder reportfalse,7/8 operations pass. Verified artifact10535544194 ZIP SHA256b1180ae04a348ae5524586f9be761a7f7d33507f4e9d9c874231c3b6cdc1af5c: refactor preserves_sum=true/changes1/errorempty/local runtime/self_primary=true/no externalAI. Source accepts parsed refactor asok=true, and smoke additionally requires add_numbers; combined evidence narrows failure to missing original public function name. Actual returned code is not retained, so its replacement name/content cannot be asserted. This is independent of source-identity helper, reached before helper invocation.
OWNED NEXT FIX: scripts/code_specialist.gd, benchmarks/core/code_specialist_smoke.gd, new bounded refactor regression smoke, Core benchmark workflow wiring, canonical journal. Preserve original Python top-level public function names, allow one repair through same bundled Core, fail closed if still missing, retain exact benchmark output diagnostics. Do not weaken existing answer/addition/local/offline gates. Name checks are a limited structural contract, not proof of Python execution or all-language behavioral equivalence.
PROGRESS_COMPLETE: 50%
PROGRESS_REMAINING: 50%
DONE: current executor implementation ancestry confirmed; stale Server journal-only branch reconciled; current Coder failure personally inspected.
REMAINING: repair and rerun current Coder gate;10 remaining release checkpoints; self-contained updated handoff.
BLOCKERS: current Coder acceptance red; Windows package/synthetic import pending; corpus/device/human/host/signing unproven. Previously accepted Windows benchmark remains historical evidence and does not accept the current head.
NEXT: enforce bounded public-name preservation, run fault-injection smoke, publish with updated normal-chat instructions atomically. No main merge/version/tag/release while current mandatory gate red.

ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 50%

OWNERSHIP EXTENSION: benchmark-only Knowledge stage diagnostics in benchmarks/knowledge/knowledge_stress_benchmark.gd. Current synthetic1GiB run35310302273/job105503429773 failed after5400s; artifact10537705836 digestf20ecfb39514bc321ff79c9dd95860fafcf2f3278370b2110717b49e2c0848f9 personally downloaded/verified: timed_out=true/return-9/RSS900882432, logs contain only Godot banner. No phase/cause or valid imported bytes/restart proof established; dataset_bytes0 is missing final report, not proof of a zero-byte generated dataset. Add stage prints without changing import algorithms/data/time limits/assertions, so next long-run failure can be diagnosed. Nested platform_runtime_identity.git_sha still wrongly uses event merge7381817; actual checkout03ae is proved by guard, and this remaining metadata issue belongs to next Knowledge evidence repair.

### AFTER ACTION — bounded Core refactor repair

ACTION: public-name preservation is explicit in refactor prompt; a limited non-executing Python top-level definition check rejects lost public names, invokes the same own-Core client once for repair, then refuses a repeated loss. Existing JSON/change/no-op/offline/addition quality gates remain. Benchmark now retains returned_ok, expected function presence and a bounded code excerpt. New fault-injection smoke is wired before real Windows Core evaluation. Knowledge benchmark logs reset/generation/import/search/restart phases; timeout cause is still unresolved, not reported fixed.
TEST: new Godot4.7.1 regression passes; previous source2e905df fails the same new test with exit3 (rename was accepted without repair). Valid result uses1 call, repair2 calls, repeated-invalid result is refused after2 calls; async/private/non-Python boundaries checked.29 relevant Python tests pass in0.12s, workflow YAML parses, diff check passes. Godot exit0 has pre-existing7 ObjectDB/3 resource exit warnings; not claimed warning-free. Actual model inference/new-source Windows acceptance pending CI.

ADDITIONAL LOCAL PROOF:9MiB JSONL import and fresh-process restart both pass in portable harness, error_count0; new reset/generate/import/search/restart stage logs retained in temporary QA. This is small-scale correctness/diagnostic proof only, not1GiB timeout repair or production corpus acceptance.

## 60. Актуальная передача обычному чату — продолжать из GitHub, а не из обещаний

Эта запись заменяет устаревшие SHA/очередь из раздела49, но сохраняет требования AGENTS и все инженерные доказательства. Исходный проверенный кандидат этой партии:2e905df6ee656d7ff7071ff8918f3767b85a411d. Коммит с этой записью и исправлением CodeSpecialist публикуется атомарно поверх него в существующей ветке `chat-2026-09-17-unified-finalization`; его настоящий SHA следующий чат получает из PR92/ref, а не угадывает по тексту. Main031aebaad16fc25a39dfc45c58f96fadb658cac2, версия1.3.0.0/code100005; предполагаемый финальный MINOR1.4.0.0.

### Кто продолжает и чем

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: HANDOFF-READY / INCOMPLETE. На момент окончания ответа этот исполнитель не продолжает работу в фоне. Следующий обычный Chat/Codex/Work может сразу взять незавершённую работу на себя, записав TAKEOVER/RECONCILE здесь; связываться со старыми чатами и ждать их не нужно. Владелец требует одного исполнителя. Исторические ACTIVE-записи прежних lanes не означают, что их остановленные чаты сейчас работают; эта передача разрешает единый takeover, не отменяя safety/signing/privacy gates.

Обычный чат способен изменять проект только при реально доступном GitHub-инструменте с правом записи. Наличие ссылки/упоминания GitHub само по себе не даёт такого права. Сначала проверь доступ чтением PR92, свежего main и AGENTS; затем используй только реально доступные операции записи. Если shell отсутствует, выполняй acceptance через GitHub Actions после атомарного обновления ветки, не называя их локально пройденными. Если доступно только чтение или инструмента нет — честно назови отсутствующую возможность и попроси подключить GitHub/дать write-доступ; не изображай edits/CI/merge. Не публикуй токены/секреты/ключи.

При наличии shell и клона: `git fetch origin`, затем читай `AGENTS.md` и ВЕСЬ `docs/PROJECT_MASTER_LOG.md` из актуальных main и кандидата. Делай работу от настоящего PR head; локальная ветка Work могла иметь другие commit IDs при полностью совпадающих файлах, поэтому проверяй diff и SHA удалённой ветки. Scratch-путь этого сеанса не гарантирован следующему чату; восстановление веди из GitHub, а не ищи исчезнувшие временные файлы.

### Первые исполнимые действия следующего чата

1. Получи свежие `main`, PR92/head, список открытых PR и ВСЕ страницы branches. Запиши свою заявку с исходными SHA, файлами и предполагаемым bump ДО кода. Единственный журнал — этот файл. Если другой живой исполнитель уже добавил новые изменения, сохрани их и согласуй takeover по свежим фактам.
2. Проверь CI коммита с текущей записью. Из-за pull_request событие GITHUB_SHA может быть служебным merge SHA: реальное доказательство — `AURORA_CI_CHECKOUT_SHA=<head>` в job и содержимое отчёта. Core artifact/helper теперь используют actual head. Nested Knowledge identity ещё использует eventSHA; исправь metadata отдельно, не выдавая mergeSHA за source и не переписывая чужой отчёт без проверки.
3. Сначала закрой реальный CodeSpecialist сбой. Историческая ошибка35318393724/job105515111358/artifact10535544194:7/8, refactor missing public name; исправление этой партии имеет локальную regression proof, но требует успешного НОВОГО real-core-windows. Проверь все8 операций и21 quality scenarios, собственный Core, отсутствие Ollama/внешней сети, hashes/quality/performance. Не убирай add_numbers/a+b или hard gates. Если снова красный, теперь читай bounded returned code excerpt и precise error.
4. Разбери настоящий Knowledge timeout:35310302273/job105503429773/source03ae14b/artifact10537705836,5400s/-9/RSS900882432, phase ранее неизвестна. В новой партии появляются stage logs. Сначала установи reset/generate/import/search/restart, воспроизведи на небольшом и увеличенном объёме с замером; только после этого исправляй алгоритм. Не повышай timeout вместо доказательства, не ослабляй restart/integrity/RSS и не считай синтетический JSONL настоящим корпусом.
5. Сохрани длительную Windows-сборку35310302289/job105507674904/source03ae14b: installer уже прошёл, на последней проверке идёт исторический V1.2/V1.3 bridge. Новые Windows/Knowledge запускаются в очереди с cancel-in-progress=false. Не отменяй текущие дорогие проверки ради journal-only commit. Потребуются также окончательные same-head runs: установленный offline Silero TTS+Whisper-small STT, firewall block, WAV/JSON, файлы/Computer/master-stop, silent install/uninstall/bridges. Предыдущий результат не принимает новый head.
6. Android normal-path E2E и APK launch приняты как отдельные checkpoints раздел58 на03ae14b; Release-native report также лично проверен. Для нового финального head опять нужны native/normal/APK результаты, а установленный Voice/OCR/Knowledge и физическое устройство остаются непроверенными. Native E2E/не-thinking prompt не заменяют installed voice/OCR.
7. Работы актуальных прежних lanes уже находятся в PR92: Core51bb186, Knowledge07cf2f5, Platform42fc32b, UI2006566, Voice-r2c18ac6d, Workf0918a6/20be9b1 — ancestors. Server5ef7c90 отличается единственным journal-only claim, не новым implementation. Не делай дубликаты.72 других remote refs не являются ancestors; многие старые/squash/replay альтернативы, но универсальная patch-equivalence не доказана. Для нужной старой ветки сравни настоящий полезный delta/тесты с текущим кодом; не сливай старые versions/workflows/assets ради количества merges, не удаляй историю.
8. Закрой10 недостающих release checkpoints раздел58. Реальный полезный >=1GiB licensed/sharded pack/provenance отсутствует: v14 synthetic/duplicate archive не выполняет требование. Физические устройства, human voice/UI, REG.RU deployment/mail/rollback, signing lineage/ключи — отдельные фактические границы. Не предполагай, что они прошли.
9. Лишь после relevant gates и отсутствия P0/P1: финальный единый bump1.4.0.0/code>100005, sync JSON/Godot/export/installer/updater/changelog и новые package/update/release проверки. PR92 до этого draft; main merge/tag/production release не делать с красным обязательным gate. Владелец разрешил полезные слияния, а не ложную приёмку.
10. Каждую выполненную партию записывай BEFORE/AFTER здесь с actualSHA/run/job/artifact/hash/test output, DONE/REMAINING/BLOCKERS/NEXT. Доводи доступную работу самостоятельно. Реальный внешний blocker называй точно; pending/cancelled не равно pass, повторённый запуск не равно repair.

### Короткий запрос, который владелец может перенести в новый чат

«Продолжи AuroraFox из https://github.com/Treninem/AI. Работай один. Сначала получи актуальные main и PR92/head, полностью прочитай AGENTS.md и docs/PROJECT_MASTER_LOG.md, особенно последнюю передачу раздел60. Проверь настоящие инструменты чтения/записи GitHub. Запиши TAKEOVER до кода; продолжай с Core refactor CI и Knowledge timeout/Windows installed gate, без повторения уже интегрированных lanes. Сохраняй автономность собственного Core. Исправляй реальные failures, публикуй атомарные партии в текущем draft PR92 и записывай evidence в единственный журнал. Не обещай фоновой работы после остановки и не объявляй релиз без всех gates. Процент — только по фактическим acceptance checkpoints».

PROGRESS_COMPLETE: 50%
PROGRESS_REMAINING: 50%
DONE: актуальные executor branches сведены ранее и лично проверены по ancestry; Server journal-only остаток reconciled; bounded refactor repair и regression; диагностика Knowledge этапов; исполнимая передача обычному чату.
REMAINING:10 release checkpoints, новый текущий Core CI, разбор5400s Knowledge failure и installed Windows proof.
BLOCKERS: red Coder/Knowledge real gates до нового успешного запуска; genuine corpus/device/human/host/signing unproven. Полная эквивалентность72 исторических refs не установлена; они не заявлены слитыми/принятыми.
NEXT: получить настоящий новый PR92/head и результаты его Windows Core/Knowledge; читать новые refactor excerpts/stage logs, сохранить дорогую Windows-сборку.

ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 50%

## 61. BEFORE ACTION — resumed sole ownership, green Core/Knowledge and bounded Windows bridge

CLAIM `WORK-2026-09-17-FINAL-RELEASE`: ACTIVE — sole executor resumes section60 handoff. Fresh main031aebaad16fc25a39dfc45c58f96fadb658cac2/candidate96beca1eef36e022da33b51c40b3ffe1f5100352, PR92/draft; instructions/current canonical continuation reconciled. Accumulated intended MINOR/V1.4 remains version-last.
CURRENT FACTS:23/24 candidate workflowsSUCCESS; Windows Package35325857421/job105554749059 CANCELLED. Coder/realWindows35325857344/job105538675377 succeeds: actual checkout guard96beca1 and AURORA_REPORT_SOURCE_SHA96beca1, all owned regression/real-code/benchmark gates pass. Knowledge1GiB35325857519/job105543423201 succeeds with two cases/error_count0, no timeout increase; this is synthetic capacity, not genuine pack. Previous5400s failure is a runtime variability/performance risk, not asserted algorithmically solved by stage prints.
WINDOWS EVIDENCE: build/export/runtime/exe/installer steps pass, full installer compile2055.078s. Last visible bridge event is V1.2 fixture compile27.079s at10:25:37Z, then no per-operation output until cancelled12:42:18Z. Old03ae run35310302289 is alsoCANCELLED at bridge. Neither proves a failed assertion or exact blocked installer/app phase. Source uses unbounded Start-Process -Wait for fixture install/repair/app smoke/uninstall, losing phase diagnostics and potentially waiting for descendants after main exit. Do not call descendants the proven cause without a rerun.
OWNED NEXT BATCH: tests/windows_v12_bridge_smoke.ps1, tests/windows_v13_bridge_smoke.ps1, shared bounded process helper + real PowerShell helper smoke, Windows workflow helper parse/fast regression wiring and failure diagnostics artifact, relevant backwards-compatibility tests and canonical journal. Log explicit phase/installer logs; bound each child process, cleanup only its process tree, preserve every marker/trust/user-data/exitcode assertion. Let V1.3 reuse the already-built current installer when requested, retaining standalone compile fallback; this avoids confirmed redundant compression, not claimed the current hang cause.
PROGRESS_COMPLETE: 50%
PROGRESS_REMAINING: 50%
DONE: new Core/Knowledge real gates green; actual source guard/report identity executed remotely.
REMAINING: Windows installed/package acceptance,10 release checkpoints and remaining Knowledge report identity/performance boundaries.
BLOCKERS: Windows bridge phase unknown/unbounded, installed voice not reached; genuine corpus/device/human/host/signing absent.
NEXT: add bounded phase-level diagnostics and regression, reuse current installer for V1.3, publish coherent batch and inspect its real Windows result. No version/main merge/release.

ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 50%

OWNER STEERING/TAKEOVER: owner reiterates to audit/take all chats and authorizes deletion of unnecessary branches only after takeover. Full123-branch ancestry and branch-relative text-path/blob audit completed:51 ancestors/72 non-ancestors;54 unique older text paths absent at candidate. Absence is not acceptance evidence: deprecated parallel journals/fake release overlay/old workflows are excluded, and remaining useful source must be reconciled. Genuine missing feature found in file-intelligence-epub-rar-v1/a187628: current file_service lists EPUB as generic ZIP and RAR only warns, unlike old chapter/RAR analyzers. Extend ownership to file_intelligence/extended_formats.py, current file_service/requirements, meaningful EPUB/RAR regressions and relevant CI, preserving current OCR/limits/local autonomy. Audit catches unsafe old lstrip path normalization and unbounded EPUB member reads; do not import those defects or the stale launcher wrapper. Production-path takeover continues under sole claim; old spec/probes remain retained until reconciled.
BRANCH CLEANUP: no authenticated delete-ref operation exposed in current GitHub connector; shell push previously unauthenticated. Prepare only exact-SHA ancestor alias cleanup with preserved refs/evidence and available authenticated means; never say a branch was deleted until remote readback proves it. Owner authorization persists, no repeat permission required.

### BEFORE: разрешённое удаление доказанных временных веток

Владелец явно разрешил удалять ненужные ветки ПОСЛЕ переноса работ. CLAIM расширен на `.github/workflows/retire-verified-branches.yml` и `build/retire_verified_branches.py`: удалить только фиксированный список временных aliases ниже, чьи SHA лично проверены как ancestors кандидата96beca. Main, PR92, canonical lanes и72 ветки с непроверенным delta не удалять. Прямой GitHub DELETE-ref инструмент отсутствует, shell push не имеет авторизации; выполняется обычная авторизованная Actions-операция с job-scoped contents:write, без выдачи/печати токенов. Перед каждой операцией заново проверить protected/open-PR/head-SHA/ancestry; удаление только через compare-and-swap lease. До readback не писать «удалено».

- `chat-2026-09-17-work-computer-autonomy-please-stop` → `20be9b108c2de2e1d18cadb6cd2c75ba1e0e4d58`; ancestor, ожидает безопасного удаления.
- `tmp-ignore` → `031aebaad16fc25a39dfc45c58f96fadb658cac2`; ancestor, ожидает безопасного удаления.
- `tmp-main-for-voice-sync` → `031aebaad16fc25a39dfc45c58f96fadb658cac2`; ancestor, ожидает безопасного удаления.
- `tmp-main-for-voice-sync-2` → `031aebaad16fc25a39dfc45c58f96fadb658cac2`; ancestor, ожидает безопасного удаления.
- `tmp-main-for-voice-sync-final` → `031aebaad16fc25a39dfc45c58f96fadb658cac2`; ancestor, ожидает безопасного удаления.
- `tmp-never-use` → `c41a9996692d4588592ecf5735e2c72a10ceb9f2`; ancestor, ожидает безопасного удаления.

### AFTER: проверенная партия и полный реестр takeover

Локально36 passed (0.67s): `tests/test_extended_formats.py`, `test_file_intelligence.py`, `test_project_index.py`, `test_update_backward_compat.py`, `test_windows_voice_package.py`. Реальные EPUB ZIP/OPF/spine/nav и RAR3 CRC fixtures проверены, включая dispatch file_service, traversal rejection, bounds и запрет внешних процессов для RAR. Сжатый RAR перечисляется с явным предупреждением: полноценная распаковка сжатых entries НЕ заявлена. Старый launcher-wrapper не возвращён; новый модуль входит в Windows package file list. RAR parser — pure-Python rarfile4.2; собственный Core не получает внешнего inference dependency. YAML всех32 workflows и Python syntax проверены; diff whitespace clean. Реальный локальный bare Git доказал, что stale deletion lease сохраняет advanced ref, а точный lease удаляет только выбранный ref.

Windows bounded process helper имеет отдельную быструю реальную PowerShell regression в CI, phase markers и installer logs; timeout каждой фазы прекращает только её parent/owned descendants. Cleanup parent/dispose защищён вложенными finally. V1.3 reuse уже проверенного installer исключает вторую долгую компрессию, НЕ объявляется причиной старого зависания. Локального PowerShell нет: regression/package/voice подтверждение ждёт нового CI. Старые мостовые marker/user-data/hash/voice assertions сохранены.

На96beca лично прочитаны CI:23/24 success, Windows run35325857421/job105554749059 cancelled после180min; last output — V1.2 fixture compiler10:25:37Z, точная зависшая установка/app/uninstall неизвестна. Core Windows35325857344/job105538675377:8/8 Coder и21 quality scenarios green. Knowledge35325857519/job105543423201:2 cases,0 errors, ~88min synthetic1GiB; это НЕ настоящий licensed production pack. Предыдущая ошибка CodeSpecialist закрыта на96beca; final same-head verification для новой партии остаётся.

Ниже123 remote branches относительно96beca:51 ANCESTOR уже в истории,72 DELTA требуют reconcile. Для DELTA числа I/D/M — identical/different/missing text paths относительно текущего кандидата, а не обещание функциональной эквивалентности. Старые journals, fake progress overlay, обязательные Ollama/external-model dependencies не возвращать. Все незавершённые задачи беру на себя; следующие отсутствующие полезные части проверять по точному SHA, не ждать старые чаты. Canonical source: GitHub/PR92; локальный qa JSON не нужен следующему чату.

| Ветка | SHA | Проверка | I/D/M |
|---|---|---|---|
| `aurora-agent-sync-v1` | `f6f525a43bf015240db09d57ba6ab4805feb68ba` | DELTA | 2/2/0 |
| `aurora-api-gateway-v1` | `4cc9522b7685f8204188c17ce2a7fb6b3f773475` | DELTA | 4/14/1 |
| `aurora-api-gateway-v2` | `6ae0e75a43db4396db3e9fcc45c08ab13d633ed3` | DELTA | 4/14/0 |
| `aurora-pc-release-v1` | `78f7ffc6c9766933955f71296df381886f091c96` | DELTA | 0/3/0 |
| `aurora-ui-assets-v2` | `ed3b32962445c7957deca2f0732dbbdf794f4696` | DELTA | 0/3/1 |
| `autonomy-foundation-2026-08` | `b16d8cc0fb892c371fd798bd408acf883d2710a1` | DELTA | 0/6/12 |
| `bugfix-v1.1.1.1` | `0dd0fe12c198040db0d822330daff4f08504319e` | DELTA | 4/15/0 |
| `build-v1.0.0.0-android` | `5710fd5eb895a5737bcc4d68b9a9824641f94ce2` | DELTA | 0/0/0 |
| `build-v1.0.0.0-windows-installer` | `23d76b1504dc577353688da2ab5112997f87ff42` | DELTA | 0/0/1 |
| `chat-2026-09-16-integration-gate` | `c08aa335bce30978199ed3ea2727e64fa511095e` | DELTA | 0/2/0 |
| `chat-2026-09-16-large-knowledge-perf` | `4f3162bc5d08ccb2e29265e9d1400d78f8b5ee81` | DELTA | 0/2/3 |
| `chat-2026-09-16-local-ocr` | `38f03adb2bed9cdf5e0cd0c2caa485072ee7152b` | DELTA | 10/7/2 |
| `chat-2026-09-16-local-ocr-replay` | `9eaf9d08e49c7ff5928cdcac6d90eacc905cc5ca` | DELTA | 0/5/0 |
| `chat-2026-09-17-knowledge-memory-ocr` | `07cf2f54cf0fdf4ab6ff33d019986f14942db1b1` | ANCESTOR | — |
| `chat-2026-09-17-platform-integration` | `8feed40e3327b8ea02bb0ad6b1d23b17be7dd0a9` | ANCESTOR | — |
| `chat-2026-09-17-platform-integration-v2` | `42fc32b664005e007175c8542f49030bc7bb4a0b` | ANCESTOR | — |
| `chat-2026-09-17-server-api-db` | `5ef7c9002950a4b59c962888bd869cbc677dd9ef` | DELTA | 0/0/0 |
| `chat-2026-09-17-ui-visual` | `2006566710a5662bba9074c5cbb47c48988ae603` | ANCESTOR | — |
| `chat-2026-09-17-unified-execution` | `9ca5fafd1f65038d855d00e1e1e0db876938d17f` | ANCESTOR | — |
| `chat-2026-09-17-unified-finalization` | `96beca1eef36e022da33b51c40b3ffe1f5100352` | ANCESTOR | — |
| `chat-2026-09-17-voice-audio` | `7d6d074ec597b21ff0a0a906e3a04871cae2158a` | DELTA | 0/0/1 |
| `chat-2026-09-17-voice-audio-r2` | `c18ac6d29950fc277345734850aed1422bb86ae0` | ANCESTOR | — |
| `chat-2026-09-17-voice-main-sync` | `011a73e93e3869b0c6097edf4f36a79d00838e0b` | ANCESTOR | — |
| `chat-2026-09-17-voice-main-sync-2` | `011a73e93e3869b0c6097edf4f36a79d00838e0b` | ANCESTOR | — |
| `chat-2026-09-17-voice-main-sync-3` | `011a73e93e3869b0c6097edf4f36a79d00838e0b` | ANCESTOR | — |
| `chat-2026-09-17-work-computer-autonomy` | `20be9b108c2de2e1d18cadb6cd2c75ba1e0e4d58` | ANCESTOR | — |
| `chat-2026-09-17-work-computer-autonomy-123` | `20be9b108c2de2e1d18cadb6cd2c75ba1e0e4d58` | ANCESTOR | — |
| `chat-2026-09-17-work-computer-autonomy-actual` | `20be9b108c2de2e1d18cadb6cd2c75ba1e0e4d58` | ANCESTOR | — |
| `chat-2026-09-17-work-computer-autonomy-ci` | `20be9b108c2de2e1d18cadb6cd2c75ba1e0e4d58` | ANCESTOR | — |
| `chat-2026-09-17-work-computer-autonomy-draft` | `20be9b108c2de2e1d18cadb6cd2c75ba1e0e4d58` | ANCESTOR | — |
| `chat-2026-09-17-work-computer-autonomy-final` | `20be9b108c2de2e1d18cadb6cd2c75ba1e0e4d58` | ANCESTOR | — |
| `chat-2026-09-17-work-computer-autonomy-last` | `20be9b108c2de2e1d18cadb6cd2c75ba1e0e4d58` | ANCESTOR | — |
| `chat-2026-09-17-work-computer-autonomy-please-stop` | `20be9b108c2de2e1d18cadb6cd2c75ba1e0e4d58` | ANCESTOR | — |
| `chat-2026-09-17-work-computer-autonomy-pr` | `20be9b108c2de2e1d18cadb6cd2c75ba1e0e4d58` | ANCESTOR | — |
| `chat-2026-09-17-work-computer-autonomy-pr0` | `20be9b108c2de2e1d18cadb6cd2c75ba1e0e4d58` | ANCESTOR | — |
| `chat-2026-09-17-work-computer-autonomy-review` | `20be9b108c2de2e1d18cadb6cd2c75ba1e0e4d58` | ANCESTOR | — |
| `chat-2026-09-17-work-computer-autonomy-stop` | `20be9b108c2de2e1d18cadb6cd2c75ba1e0e4d58` | ANCESTOR | — |
| `chat-2026-09-17-work-computer-autonomy-x` | `20be9b108c2de2e1d18cadb6cd2c75ba1e0e4d58` | ANCESTOR | — |
| `chat-2026-09-17-work-computer-autonomy-z` | `20be9b108c2de2e1d18cadb6cd2c75ba1e0e4d58` | ANCESTOR | — |
| `chat-2026-09-17-work-computer-hardening` | `f0918a64c78e38262634991116a0051369590aad` | ANCESTOR | — |
| `chat-autonomy-state-durability-20260916` | `3434f70ba32f74462c4b9f5216cf26cd5ddb2afa` | ANCESTOR | — |
| `chat-knowledge-races-20260916` | `bfd9c23dbca44c31508f44e531407aa47560423d` | DELTA | 0/2/2 |
| `chat-knowledge-races-v2-20260916` | `1bc4003170e45394d181d6010453cb8560312784` | DELTA | 0/4/12 |
| `chat-large-knowledge-complete-scaling-gates` | `338e2f54070ccdb2cd463a2843556eeb93908cea` | DELTA | 0/2/0 |
| `chat-large-knowledge-complete-scaling-gates-v2` | `bdf79c211fab40a0431f50a92ee9f4df549a30fb` | DELTA | 0/2/0 |
| `chat-large-knowledge-concurrency-isolation` | `f62c18f4138f0710456376dffce78cf62b2fbc92` | DELTA | 1/1/0 |
| `chat-large-knowledge-concurrency-isolation-v2` | `afecd94e02482261fe13d513e7002541ea0245c7` | DELTA | 1/1/0 |
| `chat-large-knowledge-concurrency-isolation-v3` | `bc403203ec575a0f1188329ddb09bfd0f0587551` | DELTA | 1/1/0 |
| `chat-large-knowledge-data-safety` | `02b931a85044a7df88662614d45f22db7c4330a4` | DELTA | 0/4/1 |
| `chat-large-knowledge-data-safety-v2` | `d2294bacaaeff27f661ea75f73dd218687f6f4ba` | DELTA | 0/3/1 |
| `chat-large-knowledge-hard-gates` | `098fa166d6ff0e1bd34ab5b6c6fe8778c8e94cf6` | DELTA | 0/2/0 |
| `chat-large-knowledge-lost-registry-validation` | `899d6bb091db906354d86f3793a5e7194838ba74` | DELTA | 0/0/2 |
| `chat-large-knowledge-registry-recovery` | `2f8d4b4b7c22d1f01dadc0829ea8d1c9441ac1c7` | DELTA | 0/2/2 |
| `chat-large-knowledge-source-removal-gate` | `5c22e0ae195444e291792624a5533375f9ece070` | DELTA | 0/2/0 |
| `chat-large-knowledge-stress-evidence` | `8a2c95d01d0c5eaf1730d34dfa2c69be25225c57` | DELTA | 0/1/0 |
| `chat-voice-android-female-20260916` | `7e81c373e4190567b7b5370de257aad5b8b2972f` | ANCESTOR | — |
| `chat-work-computer-autonomy-20260917` | `0edb9262e0f6efeea3801f61d2cf667a97abd5cc` | DELTA | 7/1/0 |
| `chat-work-computer-autonomy-ci-trigger` | `20be9b108c2de2e1d18cadb6cd2c75ba1e0e4d58` | ANCESTOR | — |
| `chat-work-computer-reliability-20260916` | `a716b14e63a9c15453e1f2d214e26f33fb030dbc` | DELTA | 6/1/0 |
| `chat/core-benchmarks-20260916` | `1fcaa6c5f3210cd20411ee9449610d6b1eec4c93` | DELTA | 6/13/0 |
| `chat/core-benchmarks-20260916-sync-test` | `c41a9996692d4588592ecf5735e2c72a10ceb9f2` | ANCESTOR | — |
| `chat/core-benchmarks-clean-stage` | `9b051ac01f9bdbfc1055a6f2c16a321329264e0f` | DELTA | 6/13/0 |
| `chat/core-benchmarks-clean-stage2` | `cc44cce8f1d3ccc97a5d4ef3bba9cc9c6efb7b4b` | ANCESTOR | — |
| `chat/core-benchmarks-clean-stage3` | `cc44cce8f1d3ccc97a5d4ef3bba9cc9c6efb7b4b` | ANCESTOR | — |
| `chat/core-coder-research-20260917` | `51bb1860c17bc86c104d4b164367ca2d0f541649` | ANCESTOR | — |
| `chat/knowledge-record-dedup-probe-20260916` | `e0d2987947ed4d2261996527340fb7f42da18b82` | DELTA | 0/0/1 |
| `chat/large-knowledge-alias-safety-20260916` | `34ce75a02ea9f37cb3ccabc03fb0d014a502c29c` | DELTA | 0/4/0 |
| `chat/large-knowledge-consolidated-20260916` | `575575b46cf12a9234e5de04441ccb0481f75ded` | DELTA | 0/3/3 |
| `chat/large-knowledge-final-port-20260916` | `612c834b6e41747b3219675ce314b1a472502f20` | ANCESTOR | — |
| `chat/large-knowledge-hard-gates-port-20260916` | `612c834b6e41747b3219675ce314b1a472502f20` | ANCESTOR | — |
| `chat/large-knowledge-perf-continue-20260916` | `612c834b6e41747b3219675ce314b1a472502f20` | ANCESTOR | — |
| `chat/large-knowledge-perf-harness-20260916` | `a4c64e0f9f7bbc9394dc947f6d3aeb96596dcdf4` | DELTA | 0/2/2 |
| `chat/large-knowledge-record-dedup-port-20260916` | `612c834b6e41747b3219675ce314b1a472502f20` | ANCESTOR | — |
| `chat/large-knowledge-windows-bootstrap-20260916` | `a395070ac64fe154474159c2547b4ecb2a5b8e26` | DELTA | 0/2/0 |
| `chat/large-knowledge-windows-bootstrap-port-20260916` | `612c834b6e41747b3219675ce314b1a472502f20` | ANCESTOR | — |
| `chatgpt/aurorafox-kb-v7-server` | `aedb76d1ad2cbdaa5ac66700391e3f851bb48351` | DELTA | 2/0/0 |
| `coord/ci-scheduling-20260916` | `8507b8b8db10bb59276f6e8b6a50c65a6043c261` | DELTA | 0/5/0 |
| `coord/updater-contract-drift-20260916` | `22d95766482a095cee429f6f12cfdb0147cc0f42` | DELTA | 1/0/0 |
| `coord/work-ui-integration-20260916` | `218a5a83d1e7d0a90ad612415e6aae02fad28045` | DELTA | 13/4/0 |
| `desktop-ui-smoke-v1` | `364f40c678ca4f733c940597e1685680ab47ddb8` | DELTA | 0/2/0 |
| `diag/android-apk-stage-split` | `b8fb2f936d9e86235751efca235b2d9fe01691e0` | DELTA | 0/3/0 |
| `feat/premium-fox-adaptive-voice` | `961186474521a04c61b54ce3cce5ce1b3948412d` | ANCESTOR | — |
| `file-intelligence-epub-rar-v1` | `a187628b65ac8b4d60dd7a8d3c750d52a72de26d` | DELTA | 0/2/2 |
| `fix/android-apk-gate-timeout` | `cd3841372cfff7d97b42f701f77685233fcdbf6a` | DELTA | 5/16/0 |
| `fix/reg-ru-ssh-availability` | `08026f02cadf67cc07e63a1933ce214dfc4d9659` | DELTA | 0/2/0 |
| `fix/ui-polish-2026-09-16` | `5336e8388e745dbffa3e460e74296bde09c132ce` | DELTA | 15/8/0 |
| `fix/ui-visual-2026-09-17` | `8feed40e3327b8ea02bb0ad6b1d23b17be7dd0a9` | ANCESTOR | — |
| `main` | `031aebaad16fc25a39dfc45c58f96fadb658cac2` | ANCESTOR | — |
| `model-bootstrap-e2e/v1` | `f5a2ce0762ef008e18811880a8e6cf4e5edf4f01` | DELTA | 0/0/0 |
| `model-bootstrap-e2e/v2` | `924e8a2f7bca3b090934ab104a7b5a3984f8acce` | DELTA | 0/0/0 |
| `ocr-backup-437d` | `437d513523cb712f0cd2c08bab3a5908d8794625` | DELTA | 2/12/1 |
| `ocr-backup-old` | `5bf5676499dba42a4369de9a1704c1530ad36d43` | DELTA | 0/5/0 |
| `ocr-backup-pre-d2065b2` | `53e9f06712fe6318b1798954cdf69a5d4dc691e9` | DELTA | 4/11/1 |
| `ocr-noop-temp` | `9eaf9d08e49c7ff5928cdcac6d90eacc905cc5ca` | DELTA | 0/5/0 |
| `ocr-replay-temp` | `da44196223de58abb3126c045bf68bc0c9e68fd0` | ANCESTOR | — |
| `ocr-work-fresh` | `5436eec13e34236cf7b6482bc934dfebd8223d73` | ANCESTOR | — |
| `release-ci-validation` | `d9e717077dc9a667c0e616ce204b98c295b6c2c9` | DELTA | 8/23/1 |
| `release-v1.1.0.0` | `f138ded4d7901973a0d0b717df4e41fc70563b7d` | DELTA | 0/3/0 |
| `release/v1.4-integration` | `99b2c144dbeb675caafb527ad528f5db18a32b50` | ANCESTOR | — |
| `semantic-memory-v1` | `158f021bfcdf3afb5622687e8ac84f9be6543ea9` | DELTA | 0/5/0 |
| `sync-main-ui-owner-assets-2026-09-16` | `34872816166cd85b70ed6d005c59a6f495d2c475` | DELTA | 0/0/0 |
| `tmp-ignore` | `031aebaad16fc25a39dfc45c58f96fadb658cac2` | ANCESTOR | — |
| `tmp-main-for-voice-sync` | `031aebaad16fc25a39dfc45c58f96fadb658cac2` | ANCESTOR | — |
| `tmp-main-for-voice-sync-2` | `031aebaad16fc25a39dfc45c58f96fadb658cac2` | ANCESTOR | — |
| `tmp-main-for-voice-sync-final` | `031aebaad16fc25a39dfc45c58f96fadb658cac2` | ANCESTOR | — |
| `tmp-never-use` | `c41a9996692d4588592ecf5735e2c72a10ceb9f2` | ANCESTOR | — |
| `validation/v1.2.0.0-full` | `6bfbecd3cf2023d0932e1ca4733917c9ea8ef1c5` | DELTA | 0/0/0 |
| `verify-v1.1.0.0-artifact` | `fd235d6deab6d98e8697f0fc25f730aea2ccb392` | DELTA | 0/0/0 |
| `visual-assets-fix-v1` | `ef49029307bf7b201259fde5e65905495b5aec4e` | DELTA | 0/4/0 |
| `visual-ui-assets-v1.1.2.2` | `13d83aed7b2d15ab5a6bfe2a6613928f30e0f56a` | DELTA | 0/0/0 |
| `visual-ui-v1.1.2.2` | `8d11c0a477595fea658a37aed2552798bca46776` | DELTA | 0/1/5 |
| `voice-android-female-supertonic-20260916` | `758961b2bd93be994e5299e8f2051d09688b2832` | ANCESTOR | — |
| `voice-quality-android-female-supertonic-20260916` | `6cfa3316e6837a175cecdd79fd0ecc4b0e4ca393` | ANCESTOR | — |
| `voice-quality-native-prosody-20260916` | `cea8142818b9d612adc468dc522332ad8ceb3304` | DELTA | 3/1/0 |
| `voice-quality-native-prosody-integration-20260916` | `345934b37e12f648a1c919515818bb5b1b949092` | DELTA | 0/4/0 |
| `voice-quality-ssml-ab-20260916` | `7d9655421da6a74cd7089196ce6b8480b200713f` | DELTA | 0/2/3 |
| `voice-quality-targeted-prosody-20260916` | `fae479d469706b2e3eff6356222eb4071fee72e2` | DELTA | 0/1/0 |
| `windows-package-fix-v1` | `39e785fe020e4ba1597a2251d42131d511d0920b` | DELTA | 0/1/0 |
| `windows-package-validation-v1` | `77e29540f955bfdae84115831a08f1fa7ce6e443` | DELTA | 0/0/0 |
| `windows-stability-ui-v1` | `ae0d4ee0f2b6996c788a47131d88a9bebf036dc4` | DELTA | 1/5/0 |
| `windows-ui-stabilization-v1` | `23c5a48bc110c96b0a582629f81fed8fe585cea7` | DELTA | 0/2/1 |
| `work/coordination-2026-09-16` | `72b0368056fd43028c6f99d7034797a12767bb1d` | DELTA | 0/2/1 |
| `x-temp-ocr` | `5436eec13e34236cf7b6482bc934dfebd8223d73` | ANCESTOR | — |

PROGRESS_COMPLETE: 50%
PROGRESS_REMAINING: 50%
DONE: доказательства выше; branch deletion ещё ожидает actual CI/readback.
REMAINING: Windows installed voice/bridges/package, production Knowledge>=1GiB, physical devices/human UI+voice, deployment/mail/rollback/signing и final same-head acceptance —10/20 checkpoints раздел58.
BLOCKERS: старый Windows timeout не признан исправленным без нового phase/acceptance evidence; никаких ложных release approvals.
NEXT: опубликовать эту атомарную партию поверх96beca в PR92, лично прочитать fast process-contract/file-intelligence/retire job, сверить branch deletion readback; затем довести конкретную Windows фазу по logs. Не bump/merge/tag/release до всех обязательных gates. Если чат остановится, секция60 продолжает действовать; этот AFTER уточняет актуальный код/реестр и заменяет устаревшие сведения об ожидающих96beca CI.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 50%

### AFTER: фактическое удаление и новые быстрые CI-доказательства

Опубликован remote commit `8ac6bd1a4f2925881c8378812bd8d1949456a341`, tree `69170b8eff7db3e1d52999b56b52225a256e6d43`, parent96beca. Все14 GitHub blob SHA сверены с локальным git hash-object, fetch и diff HEAD/FETCH_HEAD пустой. Локальный commit2bb660a — тот же код, НЕ remote identity.

Retire run35349142205/job105612779076 SUCCESS; actual checkout8ac6bd1,6 AURORA_BRANCH_DELETED, каждая с exact lease и API readback. Удалены именно6 веток из фиксированного BEFORE списка: `chat-2026-09-17-work-computer-autonomy-please-stop`, `tmp-ignore`, `tmp-main-for-voice-sync`, `tmp-main-for-voice-sync-2`, `tmp-main-for-voice-sync-final`, `tmp-never-use`. Ошибка предыдущего комментария «семь» исправлена: фактический manifest содержит6 entries (вводный docstring helper со словом seven косметически устарел, логика удаления определяется только шестью exact-SHA entries). Повторное чтение обеих страниц GitHub branches подтвердило117 вместо123; все6 refs отсутствуют, main031aebaad16fc25a39dfc45c58f96fadb658cac2 неизменен. Указанные SHA/работы сохранены в истории и реестре выше. Все72 DELTA branches и canonical lanes сохранены.

Windows run35349142330/process-contract job105612779804 SUCCESS на8ac6bd1: exit17 preserved, parent-exit0 вернулся без ожидания descendant, owned pwsh/conhost stopped; timeout1sec refused и parent cleanup; AURORA_WINDOWS_BOUNDED_PROCESS_SMOKE_OK. Это реально выполнено Windows CI, не локальный PowerShell. Package job105612934621 queued на момент записи; успешная regression НЕ принимает installer/voice.

Core/Voice run35349141942/file-intelligence job105612778995 SUCCESS на8ac6bd1; лично прочитан job log:19 passed in0.70s (parser/index/EPUB/RAR). Windows-integration105612778743 и python-voice105612778997 также SUCCESS. Общий godot-core ещё in_progress; остальные тяжёлые same-head gates не объявлять зелёными заранее.

Эта последующая journal-only запись сохраняет фактические результаты, НЕ меняет проверенный код8ac6bd1 и НЕ является новой final same-head release acceptance. При следующем настоящем изменении исправь косметический docstring helper, не перезапуская дорогую упаковку только ради числа в комментарии.

PROGRESS_COMPLETE: 50%
PROGRESS_REMAINING: 50%
DONE:6 доказанных aliases удалены с readback;36 локальных tests, новая Windows lifecycle regression и file-intelligence CI зелёные.
REMAINING:10 checkpoints раздел58;72 старых DELTA ветки требуют выборочного функционального reconcile; полное доказательство установленного Windows voice/bridges ещё не получено.
BLOCKERS: прежний Windows timeout source96beca, новый package queued; настоящий production Knowledge corpus/devices/deployment/signing ещё не подтверждены.
NEXT: читать Windows package35349142330/job105612934621 после запуска и новые фазовые installer logs; исправлять конкретный сбой без ослабления checks. Обычный чат продолжает по разделу60 и этому реестру; после остановки текущий исполнитель в фоне не работает. PR92 остаётся draft, версия1.3.0.0/code100005, bump/main/tag/release не выполнены.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 50%

## 62. BEFORE: экономная партия по настоящим новым сбоям

TAKEOVER WORK-2026-09-17-FINAL-RELEASE ACTIVE. Fresh main031aeba, PR92/headbd219fc, реализация8ac6bd1. Беру `android_plugin/setup_native.ps1`, `tests/android_native_download_smoke.ps1`, `.github/workflows/android-plugin-ci.yml`, `benchmarks/core/code_specialist_smoke.gd` и существующий общий журнал; intended BUILD diagnostics/network robustness, accumulated MINOR1.4.0.0 remains version-last. Старые claims reconcile единым исполнителем; другие чаты не запускаю.

Core run35349142031/job105612828523/artifact10549936248 SHA256a0178c7fc04e5075d34ff00eb2b7cf3e31e59fa9fea511414c6b3892326bfd7e:7/8. Refactor теперь PASS, generate_tests после bounded repair incomplete. Report потерял raw ответа: исправить bounded diagnostic evidence, НЕ заявлять генератор исправленным и НЕ добавлять canned tests/ослаблять >=2 cases. Android run35349142055/job105612778791: GitHub Server Error на setup_native.ps1:85 при загрузке sherpa1.13.4. Добавить максимум3 попытки с временным файлом/cleanup, не менять pinned hashes/revisions и не делать unbounded retry. Windows35349142330/job105612934621 идёт Build installer, сохранить run. Работа из старых веток уже сравнивалась; свежие функциональные ошибки имеют приоритет над blind merge старых workflows.

### AFTER: небольшая согласованная партия без повторения старых работ

Реализован максимум3 download attempts, TimeoutSec600, ограниченная пауза3/6sec; HTTP4xx кроме429 не retry, временный .download удаляется при каждом сбое и в finally, cache destination публикуется только после завершённой загрузки. Все native revisions/hash/size assertions сохранены. Новая PowerShell fault-injection regression проверяет interrupted partial→complete retry, cache reuse, окончательный отказ после3 attempts и отсутствие повреждённого cache/partial; wired перед дорогими Android toolchain/build steps. Локального pwsh нет, её pass ещё НЕ заявлен.

Core diagnostic report теперь сохраняет returned_ok, test_code_excerpt и rejected_response_excerpt максимум4000chars. Генерация тестов НЕ объявляется исправленной; нет canned fallback/увеличения inference retries/ослабления two-case gate. Причину неполного JSON следующая real-Core проверка покажет непосредственно.

Локально8 passed0.03s: test_core_specialist_team_runtime_contract.py и test_android_voice_supertonic_contract.py. Godot4.7.1 --check-only code_specialist_smoke.gd exit0. Все workflow YAML parsed, git diff --check clean. Лично сопоставлены старые ветки: chatgpt/aurorafox-kb-v7-server aedb76d содержит api/__init__.py и api/knowledge_bundle.py уже идентичные кандидату; coord/updater-contract-drift-20260916 22d9576 содержит test_core_candidate_promotion.py уже идентичный. Переносить повторно нечего. diag/android-apk-stage-split b8fb2f9 сопоставлена с текущим APK workflow: кандидат уже имеет stage layout/exact-head guard/сохранение expensive runs и более узкие test selectors, blind merge вернул бы старые checkout/cancellation contracts. fix/android-apk-gate-timeout cd38413 имеет16 отличающихся paths и не получает ложной patch-equivalence приёмки.

PROGRESS_COMPLETE: 50%
PROGRESS_REMAINING: 50%
DONE: bounded native downloader и failure evidence улучшены;8 local tests/Godot parse/YAML green; две старые ветки содержательно уже взяты.
REMAINING: реальная Android download regression/build, реальный Test Engineer corrected output, текущий Windows installer/bridges/installed voice и остальные10 release checkpoints.
BLOCKERS: Core35349142031/job105612828523 generate_tests incomplete; Android35349142055/job105612778791 download GitHub server error; Windows35349142330/job105612934621 продолжает installer.
NEXT: атомарно опубликовать эту партию в PR92 поверхbd219fc, проверить быстрый native download smoke и сохранить текущую expensive Windows evidence; по новому bounded rejected-response чинить фактическую Test Engineer причину, не перезапускать слепо. Следующему обычному чату продолжать по разделу60; источник текущего SHA — PR/ref, canonical version пока1.3.0.0/code100005.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 50%

## 63. BEFORE: Knowledge identity и доказательства старых веток

WORK-2026-09-17-FINAL-RELEASE ACTIVE, takeover/reconcile прежних lanes одним исполнителем. Fresh main031aeba, PR92/head ae4f55bcd5291b32580fbe8352782c60658abfa1. Claims: benchmarks/knowledge/run_knowledge_benchmark.py, tests/test_knowledge_report_identity.py, .github/workflows/knowledge-performance.yml, .github/workflows/knowledge-1g-release-gate.yml и этот журнал. Intended BUILD evidence bugfix, accumulated MINOR1.4.0.0 version-last. Own existing report_identity.py переиспользовать, не дублировать SHA validation.

Найден оставшийся реальный defect: Knowledge platform_runtime_identity.git_sha берётся из GITHUB_SHA, который при PR обозначает merge event вместо проверенного source head. Проверять actual git HEAD и expected до запуска expensive benchmark, считать отсутствие Git/несовпадение hard error, report сохранять с actual SHA. Не переписывать старый foreign report и не выдавать эту metadata работу за ускорение Knowledge или production1GiB corpus. Текущий ownCore35350878591/job105618637412 ещё выполняет SpecialistTeam; Windows35349142330/job105612934621 ещё installer. Native download smoke на ae4f55b run35350878384/job105618447139 уже success, native build ещё идёт.

### AFTER: identity correction и ещё одна старая ветка сверена

Knowledge использует единый stdlib checkout_sha helper из benchmarks/core/report_identity.py. Проверка actual/expected SHA выполняется ДО logs/Godot/import; повторная проверка source_sha перед report запрещает relabel при изменении HEAD во время работы. platform_runtime_identity.git_sha — настоящий HEAD; GITHUB_SHA не используется. Обе Knowledge workflows передают exact PR-head/normal SHA через AURORAFOX_BENCHMARK_EXPECTED_SHA; новые tests включены в их быстрые contracts и path selectors.

33 passed0.16s: report identity, performance contract/compare, stress gates,1GiB contract, workflow contract; stdlib unittest3 cases0.035s также OK (никаких новых pytest dependencies в CI). Реальные temporary Git repos подтверждают foreign PR merge ignored, mismatch rejects ДО Godot/сохранения report и сохраняет существующий evidence файл, missing Git rejects. YAML всех workflows и changed Python compile OK, diff whitespace clean. Это не новая1GiB production acceptance и не устранение Test Engineer ошибки.

Дополнительно прочитаны api/learning_pull.py и api/learning_daemon.py из autonomy-foundation-2026-08 b16d8cc. Старый daemon использует flush(...,max_seconds=60), несовместимый с нынешним LearningSynchronizer.flush(limit); нынешний server выполняет learning.flush(25) после успешного chat и имеет явный sync endpoint, storage теперь SQLite/RLock. Отдельный автономный periodic daemon этим НЕ доказан: его отсутствующий механизм остаётся задачей reconcile. Возвращать старые daemon/file_lock/store вместо действующих механизмов нельзя. Старый remote pull ожидает /v1/learning/pending и /ack плюс learning.sync credential — таких current server endpoints нет; необследованный remote trust/privacy feature не объявляется перенесённым/готовым. Не возвращать параллельные autonomy journals. Полезные требования/делты остаются под единым takeover, ветка сохранена.

PROGRESS_COMPLETE: 50%
PROGRESS_REMAINING: 50%
DONE:33 local tests+3 stdlib identity cases green, source SHA correction+CI contracts выполнены, старый learning delta лично разобран.
REMAINING: ownCore generate_tests и Windows installed package/voice gates; остальные10 release checkpoints раздел58.
BLOCKERS: real-Core35350878591/job105618637412 ещё выполняется; Windows35349142330/job105612934621 ещё installer; genuine corpus/devices/deployed/signing acceptance не получены.
NEXT: опубликовать эту единую партию поверхae4f55b в PR92; читать завершённый Core artifact с bounded Test Engineer response и Windows phase logs, исправлять точный сбой. Не считать чужой SHA/синтетику/offline smoke установленным product release. Секция60 остаётся инструкцией следующему обычному чату; версия пока1.3.0.0/code100005, PR92 draft.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 50%
