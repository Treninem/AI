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
- Собственные файлы/подсистема: только новые независимые `tests/integration_*`, `tests/release_readiness_*`, `tests/cross_subsystem_*`, новый `.github/workflows/integration-gate.yml` при отсутствии конфликта, integration scripts и `docs/PROJECT_MASTER_LOG.md`.
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

The coordinator is responsible for preventing queue deadlocks: if a dependency can be removed by changing merge order, reconciling a stale candidate, routing a defect to its true owner, splitting an independent test wave, or moving an idle/finished executor to an unowned bottleneck, the coordinator does so and records that decision here.

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

## 40. Voice / Audio — TAKEOVER/RECONCILE, 2026-09-17

### CLAIM `CHAT-2026-09-17-VOICE-AUDIO`

- Статус: **ACTIVE — TAKEOVER/RECONCILE**.
- Fresh baseline: `7be54b6a0ee6bb8a20ef410ef0b6af3e64ece956`; working branch: `chat-2026-09-17-voice-audio-r2`.
- Режим: Chat. Intended bump after acceptance: **PATCH**; canonical version, Android `versionCode`, final merge and release remain coordinator-only.
- Inherits `CHAT-2026-09-16-VOICE-QUALITY` / PR #34 and Android female-voice candidate section 33. Old replacement branch `chat-2026-09-17-voice-audio` is superseded for implementation because fresh `main` advanced; its verified asset-audit evidence remains valid and is not discarded.
- Verified Supertonic 3 supply evidence: Voice Asset Audit run `35159816459` on `7d6d074ec597b21ff0a0a906e3a04871cae2158a` SUCCESS; official `sherpa-onnx-supertonic-3-tts-int8-2026-05-11.tar.bz2` = `128774318` bytes, SHA-256 `82fa96f91c4ef8abaae3a14a3f4153facf88bed821d1f7331cec2700f432c427`, with required `duration_predictor.int8.onnx`, `text_encoder.int8.onnx`, `vector_estimator.int8.onnx`, `vocoder.int8.onnx`, `tts.json`, `unicode_indexer.bin`, `voice.bin`. Audit artifact `10473160371`.
- Owned implementation scope for this takeover stage: `android_plugin/plugin/src/main/java/com/aurorafox/runtime/AndroidVoiceRuntime.kt`, `android_plugin/setup_native.ps1`, new Voice-specific Android tests/workflows/benchmarks and `docs/PROJECT_MASTER_LOG.md`. Do not edit OCR-owned `AndroidFileRuntime.kt`, `plugin/build.gradle.kts`, `settings.gradle.kts`; do not edit UI-owned overlays; do not edit old Windows Voice/Python files until old Voice-Quality ownership is explicitly reconciled/released.
- Architecture invariant: Android speech remains fully local at runtime. Required TTS/STT model assets are staged into the APK/build before delivery; normal runtime must not download models. sherpa-onnx stays pinned at `1.13.4` unless independent evidence requires a coordinated dependency change.
- Immediate acceptance target: replace male Piper Denis Android TTS with integrity-pinned Supertonic 3; pass Russian via `GenerationConfig.extra["lang"]="ru"`; keep cache/interruption/degradation behavior; compile/package without Gradle/settings changes; then measure F1-F5 female candidates with reproducible WAV/RTF/clipping/ASR evidence before selecting a release speaker.

PROGRESS_COMPLETE: 42%
PROGRESS_REMAINING: 58%

DONE:
- Fresh main/AGENTS/full master log and active ownership audited.
- Current Android runtime confirmed to use male `vits-piper-ru_RU-denis-medium` / `sherpa-onnx-piper-denis`, so female acceptance is genuinely open.
- sherpa-onnx `v1.13.4` Kotlin API verified to contain `OfflineTtsSupertonicModelConfig` and `GenerationConfig.extra: Map<String,String>?`.
- Official Supertonic 3 asset identity/layout proven by exact CI download and SHA audit above.

REMAINING:
- Implement fail-closed build staging + Supertonic Android runtime/config and Voice-specific contracts.
- Obtain exact-head compile/package CI; then generate/measure F1-F5 Russian outputs, select a female candidate from evidence, and rerun Android APK install/launch + real TTS invocation.
- Preserve model license/notice in release packaging and record physical-device human listening separately if no real device is available.

BLOCKERS:
- none for owned-scope implementation now. Physical Android human-listen proof remains a later device boundary, not a blocker for compile/package/acoustic CI.

NEXT:
- Patch only the owned Android Voice runtime/setup plus isolated Voice contracts, then run exact-head CI and classify any failure by job/test before touching additional files.

## 41. Voice / Audio — Supertonic acoustic acceptance + ownership reconciliation, 2026-09-17

### `CHAT-2026-09-17-VOICE-AUDIO` — checkpoint / ownership extension

- Статус: **ACTIVE — Android Supertonic integration and acoustic evidence green; end-to-end cancellation, multilingual production routing, physical listening and Windows multilingual baseline remain open**.
- Fresh main verified at `9eb1431dfd2137dc831ec0cb0b131e57b8ef41f2`; branch `chat-2026-09-17-voice-audio-r2` is ahead with no main-behind delta at this checkpoint. Draft PR #85 remains integration-only; this lane does not merge/release it.
- Android runtime commits: `d7c3518410be710cbb0a472edda28e481effe199` switches Piper Denis to Supertonic 3; `b46e8716d2774489f5008b95e6a94116ce348dd9` adds fail-closed model bytes/SHA/layout staging; `2efde2ad27c7a1d61aeb25fe8d1594aef1a6d956` packages third-party notice; `6fdcf8dc4fe15bf8251b0c9b9afaca4ae0259113` locks license/model contract.
- Exact Supertonic asset remains `128774318` bytes / SHA-256 `82fa96f91c4ef8abaae3a14a3f4153facf88bed821d1f7331cec2700f432c427`; sherpa-onnx remains pinned `1.13.4`. Model weights/voice styles are OpenRAIL-M; Supertonic software/sample code is MIT. Notice is bundled under `android_plugin/plugin/src/main/assets/voice/SUPERTONIC-THIRD-PARTY-NOTICE.txt`.
- Kotlin compile proof: Android Voice Supertonic run `35187222091`, job `105092579223`, SUCCESS against sherpa-onnx 1.13.4. Earlier run `35185856294` failed before compile only because setup-android requested removed SDK package `tools`; workflow bootstrap was fixed without product-code changes and rerun green.
- First F1–F5 artifact: run `35186145818`, job `105088518510`, artifact `10482237725`, digest `sha256:46ac5c173dd74e175def2520f8a99c9349c6aca9186436f7599cf147e577383d`, 25 WAV + report. It was evidence only and did not authorize final speaker selection.
- Comprehensive acceptance: run `35190491124`, job `105101749363`, SUCCESS; artifact `10483254925`, 36,915,843 bytes, digest `sha256:6c7cd0547d91393611f7f7a99261d010ee9fe23c69c31872d30d5b0bd4a12374`, 65 WAV + report. Covers neutral/morning/night/playful/serious/calm/long neutral/numbers/dates/measurements/abbreviations/RU/EN/RU+EN for F1–F5 plus repeated/rapid requests, model reload and callback-progress evidence. All generated acceptance WAVs had zero clipping.
- Expanded machine metrics changed the provisional ranking: F3/sid2 = mean ASR similarity `0.8780`, mean RTF `0.1905`, max RTF `0.2208`, zero clipping; F1 = `0.8092` / `0.1928`; F2 = `0.8441` / `0.1975`; F4 = `0.7530` / `0.2055`; F5 = `0.8385` / `0.1961`. **No speaker is promoted by these metrics alone.** Current product sid0/F1 remains provisional until human listening proves female identity/naturalness/persona; physical Android human listening is not available in this chat.
- Remaining intelligibility weakness is measurable: numbers/dates/measurements/abbreviations are materially weaker than morning/night/playful/calm/English. This remains an acceptance target; machine ASR is not human-listen proof.
- Important cancellation correction: the comprehensive report observed progress callbacks, but that is **not native cancellation proof**. sherpa-onnx v1.13.4 `OfflineTtsSupertonicImpl::ProcessChunksAndConcatenate()` calls the callback and ignores its return value. The test returned non-zero yet generation reached progress 1.0 and took about 16–18 s for the intentionally long probe. Therefore native mid-call Supertonic cancellation is unsupported in this pinned implementation and must not be reported green. AuroraFox must implement request-layer asynchronous cancellation/result suppression/barge-in responsiveness around bounded speech chunks instead of faking a backend abort.
- Current product gaps confirmed by read-only audit: Android TTS hardcodes `lang=ru`, so normal EN routing is not production-ready; `speech_queue.stop()/interrupt()` stops playback and invalidates generation but cannot stop a synchronous Android JNI synthesis call; missing/no-frame microphone currently degrades silently; Windows default Silero baseline is RU-only while optional XTTS is not an acceptable mandatory multilingual baseline.
- Ownership reconciliation: legacy `CHAT-2026-09-16-VOICE-QUALITY` is inherited/superseded for Voice production implementation by `CHAT-2026-09-17-VOICE-AUDIO`. This fresh lane now owns, in addition to section 40 paths, `android_plugin/plugin/src/main/java/com/aurorafox/runtime/GodotAndroidPlugin.kt`, `scripts/android_local_runtime.gd`, `voice/voice_bridge.gd`, `voice/speech_queue.gd`, `voice/android_mic_monitor.gd`, and the legacy Voice-owned `voice/python/tts_engine.py`, `voice/python/processor.py`, `voice/config/voice_config.json`, `voice/config/emotions.json`, related Voice tests/README and Voice-specific CI/benchmarks. UI overlays remain UI-owned; OCR/Knowledge/Core/Server/Updater and Gradle/settings remain untouched unless explicitly handed off.
- Normal Voice remains local-only: runtime synthesis/transcription must not download models or require Internet/OpenAI/remote inference. Any new Windows multilingual baseline must be packaged and integrity-pinned rather than turned into a first-run model download.

PROGRESS_COMPLETE: 63%
PROGRESS_REMAINING: 37%

DONE:
- Android male Piper runtime removed from the owned Voice path and replaced with exact integrity-pinned Supertonic 3.
- Exact Kotlin compile, model supply integrity, licenses, F1–F5 WAV evidence, RU/EN/mixed acoustic probes, repeated/rapid synthesis and restart evidence obtained.
- Machine-only candidate ranking is recorded without misrepresenting it as female/human listening proof.
- Callback-progress evidence reclassified correctly: it does not prove cancellation for Supertonic 1.13.4.

REMAINING:
- Add Android language routing and language-aware text normalization/cache metadata; preserve RU and make EN/mixed explicit without invalid `lang=na`.
- Move Android synthesis off the Godot main-thread path, add request cancellation/result suppression and prove barge-in stays responsive even though the pinned Supertonic call itself cannot abort mid-chunk.
- Add missing-microphone / missing-output-device degradation evidence and real Android startup TTS WAV extraction from the installed APK.
- Reconcile Windows baseline to a packaged multilingual local path and obtain real Windows WAV/latency/restart/interruption evidence.
- Human-listen F1–F5 on a physical Android device (or equivalent owner listening evidence) before selecting the release female speaker.

BLOCKERS:
- Final female speaker selection: human listening evidence unavailable in this executor environment. Machine ASR/RTF metrics cannot substitute for it.
- Native mid-call cancellation inside sherpa-onnx Supertonic 1.13.4 is unavailable by upstream implementation; AuroraFox will use bounded asynchronous request cancellation/result suppression and must report this limitation honestly.

NEXT:
- Implement Android async synthesis + request cancel/result suppression + RU/EN routing within the newly reconciled Voice-owned bridge/runtime files; add exact contract/compile/device evidence. Then package a multilingual Windows local baseline and generate Windows acoustic artifacts before requesting final human speaker choice.
