Warning: truncated output (original token count: 101993)
Total output lines: 2684

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
- Следующий шаг: первым делом забрать `35117014347` и `35112699152`. Если record-dedupe probe падает — передать точный `PERFORMANCE-BLOCKER` владельцу `CHAT-2026-09-16-LOCAL-OCR` с run/job/artifact и требованием content-based within-source dedupe…51993 tokens truncated…верять содержимому.

1. **Universal Intake через чат.** Один inbox/transaction registry с hash, размером, MIME/signature, provenance, владельцем, статусом (`staged`, `quarantine`, `accepted`, `rejected`), rollback/recovery/dedupe. Маршруты: Knowledge dataset/document; training dataset; skill description; local model weights; embedding model; archive; unknown. Неизвестное хранить как staged attachment с понятным сообщением, не терять и не исполнять.
2. **Несколько моделей, включая GGUF.** Не заменять активную модель при каждом upload: отдельный model registry поддерживает много записей, SHA-256, source/license, architecture/quantization/context metadata, required RAM/storage, health/quarantine, compatibility test, explicit activate/deactivate/rollback. Router выбирает одну совместимую модель для запроса; одновременная загрузка всех моделей не требуется и не допускается при нехватке памяти. Chat GGUF import — confirmation → transactional copy → hash/compatibility smoke → registry → optional activation; повреждённый/несовместимый файл quarantine. Existing `LocalModelManager.install_local_gguf` — фундамент, но ещё не chat/multi-model registry.
3. **Embeddings + RAG.** Local embedding provider/model registry, chunking, embedding version, vector index, source-level provenance/citations, hybrid retrieval, reindex/remove/rollback and offline bounded-RAM tests. RAG дополняет KnowledgeStore; не подменяет память диалога и не превращает document text в authority.
4. **Память/инструменты/оценка.** Разделять краткую память диалога, user memory и curated knowledge; сохранять user scope/privacy. Tools остаются allowlisted, consent-gated и sandboxed. Добавить offline answer-evaluation set: factuality against cited sources, relevance, safety, latency/resource budget, regression holdouts и explicit failure reports.
5. **AuroraFox Evolution Engine.** Отдельный Candidate sandbox: analyzer → experiment manager → 3–10 bounded mutations → test runner/evaluator → improvement registry → human/automatic policy gate → blue/green accept or rollback. Никаких прямых self-edits Stable Core, no tool/secret escalation, no auto-training arbitrary uploaded weights. Каждое accepted improvement имеет diff, provenance, tests, metrics and rollback.

NEXT: продолжать текущий release без реализации этого следующего обновления. Ближайший доступный релизный blocker — доказать/получить отсутствующие external acceptance boundaries, прежде всего настоящий лицензированный полезный Knowledge corpus с provenance и Android installed Voice/OCR/Knowledge; затем final version/RC/signing only after all gates. Обычный чат после остановки сначала делает fresh fetch PR92/main, читает этот раздел, не смешивает next-update architecture с текущим candidate и не повышает readiness без exact evidence.

PROGRESS_COMPLETE: 55%
PROGRESS_REMAINING: 45%
DONE: installed Windows voice/files/computer доказан exact run/job markers; all exact-head workflows SUCCESS; ТЗ следующего обновления записано как отдельная безопасная граница.
REMAINING: 9 из 20 acceptance checkpoints и их внешние доказательства.
BLOCKERS: новый Universal Intake/Multi-Model/RAG/Evolution не реализуется в текущем RC по решению владельца; external corpus/device/human/server/signing evidence отсутствует.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 55%

## 69. BEFORE: устранение Inno race от generated API virtualenv

`WORK-2026-09-17-FINAL-RELEASE` ACTIVE у единственного исполнителя. Fresh main `4c6fe649af69c9be0eb080863f0e94b80cc3e082`, PR #92/head `bec633240582c2f4bdc3d45afc8dc98589b23b1e`; intended bump BUILD для packaging-only correction, public version остаётся version-last. Claim: `build/AuroraFox.iss`, `.github/workflows/windows-package-ci.yml`, `tests/test_windows_voice_package.py` и этот журнал.

Exact Windows Package run `35449964366`, package job `105915327224` failed только на Build installer; export/runtime/asset checks прошли. Лично прочитан terminating log: broad `Source: "windows\\*"` enters generated `build\\windows\\api\\.venv`, Inno compresses `uvicorn\\lifespan\\__pycache__\\on.cpython-311.pyc.<temporary-id>` and immediately fails `The system cannot find the file specified`. API build copy explicitly selects только top-level `.py`/`.ps1`/`requirements.txt`; API `start_api.ps1` recreates `.venv` through `install_api.ps1` после установки. Следовательно `.venv` не является installer payload, а изменчивое generated output must be excluded. PyInstaller warnings не terminating cause.

Исправление: exclude только `api\\.venv\\*` из broad Inno source, не удаляя portable voice/Computer/File runtimes; перед ISCC проверить script/package root/required staged API+Core files и дать конкретный missing-path error. Добавить static regression, чтобы broad include не вернул API virtualenv и preflight не исчез.

### AFTER: Inno packages stable API payload only

`build/AuroraFox.iss` сохраняет единую recursive package entry, но исключает лишь `api\\.venv\\*`. Поэтому normal installed API продолжает иметь `server.py`, clients, scripts and requirements, а `start_api.ps1` создаёт fresh per-user `.venv` через existing managed-runtime installer; portable Voice, Computer и File Intelligence не затронуты. Workflow перед ISCC resolve-ит exact `.iss` и package root, требует staged API/Core payload и оставляет path/exit-code diagnostics вместо общего `Inno Setup failed`.

Локально `24 passed, 13 subtests passed` за `0.21s` (`test_windows_voice_package.py`, `test_update_backward_compat.py`), Python compile и `git diff --check` successful. Local Linux does not have Inno Setup/PowerShell, поэтому настоящий recursive enumeration/install proof остаётся новым Windows Package CI boundary.

PROGRESS_COMPLETE: 55%
PROGRESS_REMAINING: 45%
DONE: exact generated-file race identified from Windows log; targeted installer exclusion, preflight and regression contract implemented locally.
REMAINING: fast-forward publish and real Windows installer/bridges/installed services proof on new exact head; other 9 release checkpoints remain.
BLOCKERS: current head `bec6332` Windows package red only at Inno compile; no local Windows/Inno runtime.
NEXT: publish this coherent BUILD correction, then wait for and inspect the exact Windows Package job before any further release mutation; do not change hidden imports or production API behavior.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 55%

## 70. BEFORE: installed Android Voice/OCR/Knowledge runtime acceptance

`WORK-2026-09-17-FINAL-RELEASE` остаётся единственным активным исполнителем. Remote exact PR #92/head `40d45dca1225050315944593388dbad8813ffe36`, tree `23919971979a782f2a69a5b2b0702fd71fb91056`, main `4c6fe649af69c9be0eb080863f0e94b80cc3e082`; version `1.3.0.0`/Android code `100005`, финальный MINOR остаётся version-last. Claim: `benchmarks/core/android_godot_benchmark.gd`, `benchmarks/core/run_android_godot_e2e.sh`, `tests/test_core_android_e2e_contract.py`, `tests/test_android_e2e_runner.py`, stale `tests/test_android_voice_quality_contract.py`, `.github/workflows/core-android-e2e.yml` только если необходим path trigger, и этот журнал. Unrelated owner asset `assets/ui/aurorafox_background_master.png` не принадлежит claim и не меняется.

Windows packaging correction section 69 подтверждён exact Windows Package run `35451459634`: process-contract job `105919229958` SUCCESS и package job `105919312960` SUCCESS; Build installer, historical V1.2/V1.3 bridges, silent install, installed-app smoke и artifact upload завершились успешно. Все 25 workflows exact head `40d45dc` завершились SUCCESS. Это закрывает regression самой Inno-поправки, но не добавляет новый readiness checkpoint сверх уже принятого Windows installed checkpoint section 68.

BEFORE GAP: текущий Android APK smoke доказывает install/version/launch/no-crash, а Android normal-path E2E доказывает offline Core, multi-turn и Core Knowledge import/retrieval. Ни один installed-emulator gate не вызывает packaged Supertonic/Whisper voice assets и packaged `rus+eng` Tesseract OCR через production Godot/Kotlin bridge. Static Kotlin/asset/contract checks не считаются runtime acceptance.

INTENDED CHANGE: расширить существующий disposable exact-production-runtime Android E2E, не добавляя test hook в рабочую main scene и не создавая второй тяжёлый APK job. В установленном release APK при отключённой внешней сети: вызвать packaged Russian TTS и локальный STT на созданном WAV; создать high-contrast bilingual ru/en image внутри app sandbox, пропустить её через normal `FileIntelligenceClient` Android OCR path; сохранить bounded hashes/metadata/errors в существующий report; сохранить уже существующий Core Knowledge import/retrieval scenario. Runner обязан требовать новые scenario IDs и отдельный marker только после completed/passed report. Никакого снижения существующих Core assertions или сетевого guard.

PROGRESS_COMPLETE: 55%
PROGRESS_REMAINING: 45%
DONE: Inno regression accepted on exact head; missing Android installed runtime boundary identified without crediting static tests.
REMAINING: implement locally, parse/contract-test, publish coherent BUILD candidate, then require real Android 35 emulator evidence before readiness changes.
BLOCKERS: installed TTS/STT/OCR evidence does not yet exist; emulator CI is the first authoritative runtime boundary.
NEXT: add the three bounded scenarios to the already installed/offline Android normal-path benchmark and keep version unchanged until final release identity gate.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 55%

### AFTER: exact installed-runtime scenarios are mandatory

Existing disposable Android normal-path APK now performs three additional calls after the already accepted Core Knowledge import/retrieval: packaged Supertonic Russian TTS must create a non-empty WAV with exact engine/language metadata; packaged Whisper STT must transcribe that WAV locally; `FileIntelligenceClient` must send a runtime-rendered high-contrast `AURORA 7429` + `АВРОРА 5183` PNG through the asynchronous Android plugin and receive both markers with `tesseract4android`, `rus+eng`, `offline=true`, `external_ai_required=false`. The emulator remains in airplane mode with Wi-Fi/data disabled and the pre-existing external ping/HTTP probes blocked. The runner requires all 11 scenario IDs and prints `AURORAFOX_ANDROID_INSTALLED_VOICE_OCR_KNOWLEDGE_OK` only after the completed report passes; a regression verifies the marker is absent on scenario failure.

The benchmark remains a disposable scene selected only in the CI checkout, so the production `main.tscn`, stable Core and shipped UI receive no test backdoor. The previously orphaned quality test still required removed Piper Denis strings and contradicted the active pinned Supertonic contract; it now checks the current offline Supertonic engine/cache identity and rejects Piper. No production voice implementation changed.

LOCAL EVIDENCE: Godot `4.7.1-stable` imported the project and parsed `android_godot_benchmark.gd` with exit 0; `28 passed` across Android E2E runner/report, APK/OCR, Supertonic and voice-quality contracts; standalone Android contract printed `AURORA_ANDROID_CONTRACT_OK`; shell syntax and `git diff --check` pass. A broad unprovisioned local pytest collection cannot represent CI because this container lacks optional FastAPI/requests dependencies; the affected isolated release contracts above are green. Real packaged TTS/STT/Tesseract execution remains deliberately uncredited until the exact Android emulator job returns its new marker.

PROGRESS_COMPLETE: 55%
PROGRESS_REMAINING: 45%
DONE: production-path installed Android Voice/OCR/Knowledge acceptance implemented locally with fail-closed report/runner contract; stale Piper-only test corrected to active Supertonic.
REMAINING: publish exact candidate and inspect the real Android 35 offline emulator report/logcat; only then may installed Android checkpoint increase readiness to 12/20.
BLOCKERS: local Linux cannot execute the packaged Android Kotlin/ONNX/Tesseract runtime; CI marker is mandatory.
NEXT: commit only claimed files (never the unrelated owner background), publish to PR #92, then wait for exact-head Core Android E2E instead of spending tokens polling prematurely.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 55%

## 71. BEFORE: release Android OCR bridge must call exported plugin methods

Exact PR #92/head `56697577383b333eb5329be218b3dd095bad91b1`; Android Core E2E run `35466043477`, real-normal-path job `105958581074` failed only at installed OCR. Build, test-sign, Android 35 install/launch, offline Core, reasoning, Russian dialog, Knowledge retrieval, Supertonic TTS, Whisper STT and compatibility all passed. Exact report failure: `installed_ocr_bilingual` received `engine=tesseract4android`, empty content and `Android runtime does not expose File Intelligence`.

The proposed "skip if external AI required" is rejected: product contract is offline local `tesseract4android`, and the diagnostic `external_ai_required=true` is only the benchmark's default for a malformed error response. Root cause is local: `scripts/android_local_runtime.gd` already documents that Godot Android release singleton methods may dispatch correctly through `call()` while `has_method()` falsely returns false; `scripts/file_intelligence_client.gd` nevertheless gates every exported File Intelligence method on `has_method()`. Claim: `scripts/file_intelligence_client.gd`, Android E2E contract/runner regression only as necessary, and this journal. Do not change Kotlin OCR assets, change scenario to skipped, or relax OCR assertions.

INTENDED FIX: for an existing `AuroraFoxRuntime` singleton invoke its known `@UsedByGodot` File Intelligence methods directly, parse/fail closed on malformed native response, and retain async OCR cancellation/polling path. This restores the actual local bridge rather than masking an unavailable capability.

PROGRESS_COMPLETE: 55%
PROGRESS_REMAINING: 45%
DONE: exact failing scenario isolated from Android CI evidence.
REMAINING: bridge correction, local parse/contracts, publish and rerun exact Android E2E.
BLOCKERS: no local Android emulator/runtime proof; only a new CI report may accept installed OCR.
NEXT: remove unreliable reflection gates for declared Android plugin methods.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 55%

### AFTER: local OCR is invoked, never reclassified as an external fallback

`FileIntelligenceClient` now invokes known exported `AuroraFoxRuntime` APIs through `plugin.call()` after verifying the singleton exists. It no longer uses false-negative `has_method()` reflection for `getCapabilitiesJson`, synchronous File Intelligence, OCR async start/poll/cancel, tree, or shutdown cancellation. Unknown/malformed native output still fails closed through existing JSON parsing; no external OCR, skip path, or capability downgrade was introduced. The async image/PDF OCR route is therefore selected in the installed release APK and receives the actual `startAnalyzeLocalFile` response from Kotlin.

Regression coverage explicitly rejects restoration of the false reflection gate and of the misleading `Android runtime does not expose File Intelligence` path. Local verification: `29 passed` selected Android E2E/runner/APK/OCR/Supertonic contracts; `AURORA_ANDROID_CONTRACT_OK`; Godot 4.7.1 parse, shell syntax and diff check succeed. Actual Android 35 Tesseract execution remains pending a new exact CI run.

PROGRESS_COMPLETE: 55%
PROGRESS_REMAINING: 45%
DONE: exact release OCR failure repaired at the Godot-to-Kotlin bridge without weakening the local-only acceptance contract.
REMAINING: publish and require `AURORAFOX_ANDROID_INSTALLED_VOICE_OCR_KNOWLEDGE_OK` plus a completed report with nonempty bilingual OCR content.
BLOCKERS: only the real emulator validates packaged JNI/assets and recognition.
NEXT: publish this minimal correction and wait for its exact Android E2E job before further release mutation.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 55%

## 72. BEFORE: deterministic bilingual bitmap and fail-closed empty OCR response

Exact PR #92/head `d2d11fa369bc01b1f915aa30cae0eeef642e642f`; Android Core E2E job `105962815237` reaches Kotlin OCR bridge. TTS, STT, Core, Knowledge and all other scenarios pass. The OCR response has `engine=tesseract4android`, `offline=false` is not reported, no error, but empty `content`, proving the bridge call now occurs but its input contains no recognisable pixels.

Native inspection matters here: `AndroidFileRuntime.analyzeOcr()` delegates image files to `AndroidOcrRuntime.extractImage()`, which loads the bitmap, initializes Tesseract with pinned `rus+eng`, calls `getUTF8Text()` and returns it as `content`. Therefore no invented replacement Kotlin API is required. The benchmark's prior `SubViewport`-rendered fixture is the unstable component: it can capture an unrendered frame in the no-window emulator. Claim: `benchmarks/core/android_godot_benchmark.gd`, `scripts/file_intelligence_client.gd`, Android E2E contracts and this journal. No OCR skip, no external fallback, and no relaxation of required bilingual markers.

INTENDED FIX: replace the runtime off-screen render with a deterministic, high-contrast 1280×420 PNG payload containing actual DejaVu Sans glyphs `AURORA 7429` and `АВРОРА 5183`; persist those bytes inside the app sandbox and retain SHA evidence. On the Godot wrapper, a successful image OCR JSON with blank `content` becomes `ok=false, error=Android OCR returned empty content` before decoration, so an input/bridge regression cannot look healthy.

PROGRESS_COMPLETE: 55%
PROGRESS_REMAINING: 45%
DONE: exact empty-content failure traced to test fixture capture, not a missing Tesseract invocation.
REMAINING: fixture/wrapper correction, local parse/contracts, exact Android rerun.
BLOCKERS: Russian recognition is only authoritative on packaged Android Tesseract data.
NEXT: make the fixture pixel-deterministic and preserve strict gate semantics.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 55%

### AFTER: OCR fixture contains deterministic text pixels

The Android benchmark no longer depends on `SubViewport`/frame-post-draw timing. It decodes an embedded 1280×420 DejaVu Sans Bold PNG, verified before inclusion by local Tesseract (`AURORA 7429`, second Cyrillic line rendered as visible glyphs), validates dimensions, writes exactly those bytes to `user://android-installed-ocr-e2e.png`, and records its SHA. This makes the packaged Tesseract input deterministic under the no-window emulator.

`FileIntelligenceClient` additionally changes `ok=true` plus blank OCR `content` into `ok=false` with `Android OCR returned empty content`; the benchmark still requires every English/Russian marker and has no skip route. Local verification: `29 passed` selected contracts, `AURORA_ANDROID_CONTRACT_OK`, Godot 4.7.1 parse, shell syntax and diff check succeed.

PROGRESS_COMPLETE: 55%
PROGRESS_REMAINING: 45%
DONE: deterministic bitmap source and explicit empty-OCR rejection implemented without altering native engine or gate semantics.
REMAINING: publish and inspect actual Android 35 `rus+eng` report content/marker.
BLOCKERS: only the packaged emulator can prove the pinned Russian traineddata recognizes the second line.
NEXT: publish minimal candidate and wait for exact Core Android E2E.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 55%

### ACCEPTED: installed Android Voice/OCR/Knowledge checkpoint

Exact PR #92/head `11371893d654c30b5d900f44e1f405dc85b4fa37`; all 25 GitHub workflows attached to that head are SUCCESS. The authoritative Android Core E2E run `35468876578`, real-normal-path job `105966140759`, built and test-signed the disposable production-runtime APK, installed/started it on Android 35 with airplane mode plus Wi-Fi/data disabled, and completed the report. Evidence artifact `10591862955`, SHA-256 `042b195bb8af1d6fdece669c9cbf153fd349880575e0165fefbbae4e1ba65432`, contains report `git_sha=11371893...` and passed `installed_ocr_bilingual`: `content_excerpt="AURORA 7429\\nАВРОРА 5183"`, engine `tesseract4android`, languages `[rus, eng]`, `offline=true`, `external_ai_required=false`, duration `1666.587ms`. It also records packaged Supertonic TTS WAV (`370588` bytes) and local Whisper STT. Thus this is actual installed/offline Voice + OCR + Knowledge evidence, not static source evidence.

Checkpoint accepted: installed Android Voice/OCR/Knowledge raises release acceptance from `11/20` to `12/20 = 60%`. This does not imply release readiness beyond the defined boundary: remaining are genuine useful licensed corpus/provenance, physical-device and human UI/listening acceptance, server/mail/rollback, final version metadata, final same-SHA RC and production signing/update/release.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: Android installed offline Voice/OCR/Knowledge accepted from exact artifact and all exact-head workflows success.
REMAINING: 8 release checkpoints, chiefly external/product evidence and final release identity.
BLOCKERS: no genuine corpus/provenance or physical/human/server-production acceptance yet.
NEXT: preserve this accepted evidence, then address the next independently demonstrable release boundary without changing version before final identity gate.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

## 73. BEFORE: make UI Godot bootstrap retryable and cached

Exact PR #92/head `03d0b1116853d8b7e1f9b8647571470402a2434b`; UI Visual job `106032550831` verified `AURORA_CI_CHECKOUT_SHA=03d0b111...` then failed before project import/tests because GitHub release download returned curl `(35) Recv failure: Connection reset by peer`. This is runner/network infrastructure, not a UI or product failure. Claim: `.github/workflows/ui-visual-ci.yml`, a narrow workflow regression test if added, and this journal. Unrelated owner background remains untouched.

The UI workflow has a distinct release boundary: desktop/Android portrait layout, actual pointer navigation, and 34 rendered acceptance surfaces. It cannot be silently merged into Core/Android/package jobs because it needs Xvfb/GL rendering and its own artifacts. Repeated Godot downloads occur because GitHub jobs are isolated; however bootstrap can be cached and transient release-asset resets retried without duplicating UI assertions.

INTENDED FIX: cache only the verified Godot 4.7.1 Linux executable under a fixed key; on cache miss use HTTP/1.1, connection/total timeouts, `--retry-all-errors`, bounded exponential-style retry delay and archive integrity test before extraction. Keep the actual UI gates unchanged and no retry of a failing product test.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: exact infrastructure-only failure classified before any product claim changed.
REMAINING: resilient bootstrap implementation/local YAML check/new UI job.
BLOCKERS: external GitHub release connection reset; no application failure observed.
NEXT: make only the downloader retry/cache boundary resilient.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

### AFTER: UI bootstrap retries transient Godot delivery failures

UI Visual CI restores/saves only the pinned Godot 4.7.1 Linux executable cache (`aurorafox-godot-linux-4.7.1-stable-a13da4feb`). On a miss it uses `curl --http1.1 --connect-timeout 30 --max-time 300 --retry 8 --retry-all-errors --retry-delay 5 --retry-max-time 300`, validates ZIP structure before extraction, and still verifies `./godot --version`. This retries transport resets such as curl 35 but does not retry or hide a product/UI test failure. The workflow's distinct Xvfb/pointer/render artifact gates remain intact.

LOCAL EVIDENCE: dedicated workflow regression `1 passed`; YAML parses with PyYAML; `git diff --check` succeeds. A broad branding test was intentionally not used as this change's acceptance because the shared worktree has a pre-existing, unrelated modified owner background PNG; it is not staged or claimed and remains unchanged. The remote exact branch retains the approved asset.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: transient UI bootstrap failure made retryable/cacheable without deleting UI coverage.
REMAINING: publish and accept a new exact UI Visual run; remaining external release checkpoints unchanged.
BLOCKERS: GitHub asset delivery remains external, but resets now have bounded retry and future cache hits avoid download.
NEXT: publish minimal workflow/test/journal change, then wait for exact UI evidence rather than rerunning unrelated checks locally.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

## 74. BEFORE: remove 1 GiB search-sampling timeout instability

Exact PR #92/head `f943958f246b5dcb47ae001fe915ad938ad89de0`; Knowledge run `35493971205`, job `106043170612`, artifact `10602033376` was downloaded and inspected. Godot installation succeeded. The actual report records a bounded timeout after `5400s`, return `-9`, peak RSS `901107712`, and the stage log proves generation/import completed (`1073742199` bytes, `1221299` generated records, `1221202` imported chunks, import `348486.762ms`) before the process remained in the search matrix. No final result/restart evidence was emitted.

Comparison with the immediately preceding successful exact-parent run `35493583972`, job `106032591110`, artifact `10600946637` proves the gate is timing-fragile rather than a new product regression: its import process consumed `5050429ms`, including eight search cases repeated five times over a `3751630715`-byte store, and restart consumed another `271702ms`. Total work completed only about 78 seconds inside the 5400-second bound. Individual full-scan searches were approximately 115-188 seconds, so 40 repetitions dominate runtime.

CLAIM: benchmark/workflow diagnostics only. Preserve all eight correctness queries, the 1 GiB threshold, restart proof, RSS ceiling and failure exit. For the >=1 GiB correctness/RSS gate run each query once; smaller performance/scaling profiles retain five samples. Emit per-query stage timing, print the JSON report before returning the captured benchmark status, and make the independent Godot download resilient without treating retry as a product pass.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: exact artifact cause established; curl/Godot misdiagnosis rejected.
REMAINING: implement bounded sample policy, workflow report printing and regression coverage; run local contracts and publish one candidate.
BLOCKERS: new exact remote runtime evidence is required after the repair.
NEXT: reduce redundant 1 GiB scans without removing a correctness case or raising the timeout.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

### AFTER: 1 GiB keeps correctness coverage without 40 full scans

`knowledge_stress_benchmark.gd` now selects one sample per search case only when `target_mb >= 1024`; all eight cases remain (`empty`, exact rare marker, common, multiple tokens, Russian, mixed RU/EN, very long and malformed), and every required query still verifies the expected source. Profiles below 1 GiB retain five samples and percentile evidence. Each case now prints its name, sample count, elapsed time and correctness, so a later interruption identifies the exact phase. The 5400-second bound, 1 GiB dataset, restart process, RSS limit and hard failure behavior are unchanged.

The workflow captures the runner status, prints `knowledge-1g.json` when present, then exits with the original status. Missing report is a failure. Godot transport now uses HTTP/1.1, bounded connection/total timeouts, eight all-error retries with delay/max time, and ZIP integrity validation. Product tests are not retried.

LOCAL EVIDENCE: six stdlib workflow/report identity tests pass; workflow YAML parses; Godot 4.7.1 downloaded with the new command and passed archive validation/version check. A real portable 1 MiB import + separate-process restart smoke passed: 1,048,655 dataset bytes, 1,201 imported records/chunks, `hard_correctness.passed=true`, `error_count=0`; its search report proves smaller profiles still execute five samples for every case and emits the new per-case diagnostics. Full editor import encountered only the pre-existing unrelated modified/corrupt owner background PNG and is not used as acceptance; that owner file remains untouched and unstaged.

REMOTE STATE BEFORE PUBLICATION: exact `f943958` has 24 successful workflows including Windows Package `35493971222`; only Knowledge run `35493971205` is FAILURE, localized above. This change therefore targets the sole exact-head red gate.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: timeout cause fixed without weakening size/correctness/restart/RSS gates; failure diagnostics made visible.
REMAINING: publish one candidate and inspect its exact 1 GiB report/artifact.
BLOCKERS: remote 1 GiB runtime proof is pending; external release acceptance boundaries remain unchanged.
NEXT: commit/push only these Knowledge files, then wait for the single serialized heavy gate rather than launching duplicates manually.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

## 75. Production licensed Knowledge Pack contract and exact artifact verification

### BEFORE

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Fresh `origin/main` is `4c6fe649af69c9be0eb080863f0e94b80cc3e082`; exact PR #92/head is `74a64ab262cac815cf3a00491fc9da8133f035c8`; public version remains `1.3.0.0`/Android code `100005`, with the accumulated MINOR `1.4.0.0` still version-last. The unrelated owner-modified `assets/ui/aurorafox_background_master.png` remains outside this claim and must not be staged or repaired.

Exact-head acceptance is now complete: all 25 workflows for `74a64ab` are SUCCESS. Knowledge 1 GiB run `35502773190`, job `106057436777`, artifact `10602813727` reports `git_sha=74a64ab...`, two passed cases, `1073742199` dataset bytes, `1221202` imported chunks/records, zero errors/duplicates, hard correctness and separate-process restart proof, no network/external runtime/Ollama/remote inference. Import wall time is `1398054.524ms`, restart wall time `265747.622ms`, peak import RSS `901038080`; the gate fell from the prior 90-minute timeout to about 28 minutes while retaining all eight correctness queries.

CLAIM: add a small production-pack validator contract, release metadata and tests under new `tools/knowledge_pack/**`, `knowledge_pack/**`, `tests/test_production_knowledge_pack.py`, and this journal. No >=1 GiB payload enters Git. The independently preserved artifact `AuroraFox-Knowledge-RU-2026.09.01-v1.tar.zst` is 429,588,529 packed bytes with SHA-256 `bc0f312448f70a650435af8f30e853ca0a81a58f69c61802de7095bed9e24614`; its tar stream contains 60 bounded JSONL shards plus `manifest.json`. The manifest claims 1,924,345,221 genuine content bytes, 1,982,822,407 JSONL bytes and 75,871 records from the pinned Russian Wikipedia 2026-09-01 source segment under CC BY-SA 4.0. These claims are not accepted until an in-repo validator independently streams the exact archive, verifies every shard hash/size/count/schema/provenance/license, detects duplicate IDs/content, and proves the manifest totals without extracting the full pack.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: exact `74a64ab` all-workflow and 1 GiB synthetic capacity/restart evidence accepted; preserved production artifact identity verified at the outer SHA and archive-integrity level.
REMAINING: implement and run independent exact production-pack validation; then integrate bounded installed Windows/Android import/query evidence before crediting Knowledge release readiness.
BLOCKERS: production artifact has not yet passed the new independent per-record/per-shard validator; physical-device/human/server/signing boundaries remain external.
NEXT: implement fail-closed streaming validation without modifying the stable Core or committing payload bytes.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

### AFTER: the preserved production artifact passes independent full-stream validation

Added `knowledge_pack/production_pack.json` as the small Git-tracked release identity: exact artifact name/size/SHA-256, production manifest totals, 60-shard/32 MiB boundary, pinned source dump input hash, language/domain and complete CC BY-SA 4.0 attribution. Added a stdlib validator and operator README. The validator hashes the outer archive, streams the zstd tar once without full extraction, requires `manifest.json` first and an exact safe member set, hashes and counts every shard, parses every UTF-8 JSONL record, checks schema and source/license/provenance consistency, rejects empty records, duplicate IDs/content and shards above the bound, independently recomputes all aggregate totals, and enforces genuine content >=1 GiB.

FULL ARTIFACT EVIDENCE: the exact 429,588,529-byte archive passed. Computed SHA-256 is `bc0f312448f70a650435af8f30e853ca0a81a58f69c61802de7095bed9e24614`; 60/60 shards, 75,871 records, 1,982,822,407 JSONL bytes and 1,924,345,221 content bytes were read; duplicate IDs = 0 and duplicate content = 0. Every record matched Russian Wikipedia source version `20260901`, revision-level provenance fields, CC BY-SA 4.0 URL and contributor attribution. Three focused contract/fail-closed tests pass through direct stdlib invocation; both implementation/test files compile with `py_compile`. This environment lacks pytest, so no pytest executable result is claimed.

This closes uncertainty that the preserved artifact is filler or an unverified manifest, but release readiness stays at 60% until the production artifact is connected to bounded Windows/Android import/query acceptance. The runtime remains self-primary/offline; `zstd` is only a release/build validation tool, not an intelligence dependency. No public version changed and the large payload remains outside Git.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: exact-head CI is all green; genuine licensed production corpus and every shard/record/provenance total are independently validated from the exact preserved artifact.
REMAINING: add bounded install/import/query consumption of this exact pack on Windows and Android; physical-device/human/server/version/same-SHA/signing gates remain.
BLOCKERS: current AuroraFox runtime imports JSONL files, not the outer tar.zst release artifact; installed cross-platform production-pack evidence does not yet exist.
NEXT: design the smallest fail-closed streaming pack installer that verifies the pinned artifact and feeds shards through the existing transactional Knowledge importer without loading the corpus into RAM.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

## 76. Android benchmark ApkFlinger heap exhaustion

### BEFORE

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Fresh `origin/main` is `4c6fe649af69c9be0eb080863f0e94b80cc3e082`; exact PR #92/head is `cf1422aac72643c78ac5070a803a4f83c9c3821a`; version remains `1.3.0.0`/Android code `100005`, accumulated MINOR `1.4.0.0` version-last. The unrelated owner-modified `assets/ui/aurorafox_background_master.png` remains outside this claim.

Android Core Benchmark job `106067774199` checked out exact `cf1422a`, prepared the pinned 1,282,439,264-byte Core model and production native runtime, compiled Kotlin/Java/CMake for the benchmark, then failed only at `:app:packageBenchmark`. The complete job log establishes the nested cause: `java.lang.OutOfMemoryError: Java heap space` from `NioFileInterceptors.readAllBytes -> ZipFlinger BytesSource -> ApkFlinger.writeFile`. There is no `No space left on device` and no duplicate-entry error. The Core model is not packaged into this APK: `run_android_probe.sh` intentionally pushes it separately with `adb`, so adding a generated model asset would duplicate work and make the APK much larger.

CLAIM: `benchmarks/core/android_probe/gradle.properties`, `.github/workflows/core-android-benchmark.yml`, `tests/test_core_android_benchmark_contract.py`, and this journal. Set a bounded packaging-capable Gradle heap with one worker, capture full `--info --stacktrace` output while preserving the real exit status, always upload it, and add a disk/memory diagnostic without destructive runner-image cleanup. Product runtime, model identity, APK contents and benchmark assertions stay unchanged.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: exact nested Android packaging failure identified from authoritative job log; disk/duplicate/model-copy guesses rejected.
REMAINING: implement diagnostics/heap correction, run local contracts/YAML parse, publish, and require exact Android emulator evidence.
BLOCKERS: hosted runner is the authoritative ApkFlinger/emulator boundary.
NEXT: raise only the Gradle packaging heap, serialize workers, and retain the complete failure log.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

### AFTER: packaging receives a bounded 4 GiB heap and complete diagnostics

The benchmark Gradle policy now sets `-Xmx4g`, a bounded 768 MiB metaspace and one worker. This directly addresses ZipFlinger reading a large packaged native file into heap while avoiding multiple memory-heavy workers. The workflow records disk, memory and the effective Gradle policy before packaging; Gradle runs with `--stacktrace --info`, tees the complete output to `artifacts/core-benchmark-gradle.log`, preserves the original failure exit code, and uploads both build log and capacity report under `if: always()`. No runner directories are deleted because the authoritative failure is heap exhaustion, not disk exhaustion.

LOCAL EVIDENCE: all three Android benchmark contract functions pass by direct stdlib invocation; workflow YAML parses; Python compilation and `git diff --check` pass. The model remains outside the APK and is still SHA-verified then pushed into the installed app sandbox by the existing runner. No production source, native runtime, benchmark threshold or version changed.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: exact ApkFlinger OOM corrected at its JVM resource boundary with fail-visible diagnostics and regression assertions.
REMAINING: publish the minimal BUILD candidate and require the exact Android benchmark APK/package/emulator report to pass.
BLOCKERS: local environment does not reproduce the hosted Android SDK/NDK/emulator packaging boundary.
NEXT: publish only the four claimed files, then wait for the exact Core Android Benchmark run rather than starting duplicate work.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

### ACCEPTED: exact Android package and offline Core runtime

Exact head `1c6e2fd0ce6075a8b07245138df018c2fffb8da9` completed all 25 attached workflows successfully. Android Core Benchmark run `35507363754`, jobs `106069333821`/`106069422076`, built `:app:assembleBenchmark` successfully in `3m21s`, installed it on Android 35 and completed the no-INTERNET runtime gate. Evidence artifact `10604382356` has SHA-256 `f0db79f8d378c0ec53f97005788dbd5578cea5245fcdb73ee3ef0dba0099e6e4` and exact `git_sha=1c6e2fd...`. It proves release `llama.cpp`, `runtime_debug=false`, native library loaded, exact 1,282,439,264-byte model/SHA, local cold response `ANDROID-LOCAL-READY`, reasoning `56`, Russian response `ЛОКАЛЬНО`, no INTERNET permission and no remote AI. The capacity report shows 76 GiB disk available and 14 GiB memory available, confirming the previous failure was JVM heap policy; the retained Gradle log ends `BUILD SUCCESSFUL`.

The correction is accepted without increasing the 12/20 release checkpoint count because Android real-Core runtime was already an accepted checkpoint; this closes a regression on that evidence lane rather than adding a new release boundary.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: Android ApkFlinger correction and exact installed offline Core benchmark accepted; all exact-head workflows green.
REMAINING: production Knowledge Pack consumption, physical/human/server/version/final signing boundaries.
BLOCKERS: none inside the Android benchmark lane.
NEXT: connect the independently verified production Knowledge Pack to the existing bounded transactional importer.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

## 77. BEFORE: resumable extracted production Knowledge Pack installation

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE, sole executor, exact accepted head `1c6e2fd`; accumulated MINOR remains version-last. Claim: new `scripts/knowledge_pack_installer.gd`, focused smoke/contract tests, `project.godot` only if class registration requires it, and this journal. Existing `knowledge_import_transaction.gd`, stores and registry are read-only dependencies unless a reproduced defect requires an explicit claim extension.

The production archive itself is correctly kept outside Git and validated at release/build time. Runtime installation must not require loading 1.98 GiB into memory or adding zstd as an intelligence dependency. The smallest cross-platform boundary is an already extracted directory containing the signed/hashed `manifest.json` and bounded JSONL shards: validate schema/production floor/source/shard member safety, exact size and SHA-256 for every shard, then feed shards sequentially through `KnowledgeImportTransaction`. Persist progress after each committed shard so interruption resumes safely; duplicate registry handling makes replay idempotent. Archive extraction remains an installer/updater concern.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: exact production artifact and existing per-source transactional streaming importer independently accepted.
REMAINING: implement directory/manifest verification, resumable sequential install and focused failure/restart evidence.
BLOCKERS: installed Windows/Android tests need a bounded fixture first; full production payload remains outside Git by design.
NEXT: add the adapter without changing normalized Knowledge storage or Core authority.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

### AFTER: verified shards install sequentially and resume idempotently

Added `KnowledgePackInstaller` as a thin offline adapter over the accepted `KnowledgeImportTransaction`. It consumes an already extracted pack directory, requires the canonical pack/record schemas and complete pack identity/license/attribution, enforces the >=1 GiB content floor for `production=true`, rejects unsafe/duplicate member names, missing shards, size/limit/hash mismatches and inconsistent manifest totals. Only after every shard passes integrity inspection does installation feed one bounded JSONL shard at a time through the existing transactional importer with pack/shard provenance metadata.

Progress is atomically persisted after each committed shard under `user://knowledge/pack-installs`; restart with the same manifest SHA skips completed shards, while a changed manifest/version starts a distinct state. The adapter has no HTTP, external process, external AI or archive-decompression dependency. Thus Windows/Android installers/updaters may extract the separately distributed artifact, while normal Knowledge ingestion remains offline and self-contained.

LOCAL EVIDENCE: two focused Python source contracts pass; `py_compile` and `git diff --check` pass. A real Godot 4.7.1 isolated-user-data smoke created a JSONL shard/manifest, verified and imported it, repeated installation with `skipped_shards=1`, then changed the fixture to `production=true` and confirmed rejection below 1 GiB. Marker: `AURORA_KNOWLEDGE_PACK_INSTALLER_OK verified=true resumable=true offline=true`.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: bounded verified/resumable pack-to-transaction adapter implemented and exercised in the actual engine; stable Knowledge storage/Core remain unchanged.
REMAINING: publish and add installed Windows/Android fixture gates; then run the exact production pack through the platform staging/import boundary before crediting readiness.
BLOCKERS: full 1.98 GiB platform import evidence remains expensive/external; this local smoke proves control flow, not production payload duration/RSS.
NEXT: publish the adapter/tests/journal, inspect exact CI, then wire a small packaged fixture into existing installed platform gates before scheduling one full production import.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

## 78. Installed Android Knowledge Pack fixture in the existing normal-path gate

### BEFORE

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Fresh `origin/main` is `4c6fe649af69c9be0eb080863f0e94b80cc3e082`; exact PR #92/head is `28437fa5f1cfc4649688b3bbf362f5e4853a8a6d`; public version remains `1.3.0.0`/Android code `100005`, with the accumulated MINOR `1.4.0.0` still version-last. All 25 workflows on this exact head are SUCCESS. The unrelated owner-modified `assets/ui/aurorafox_background_master.png` remains outside this claim and must not be staged or repaired.

CLAIM: extend only the existing installed Android normal-path E2E through `benchmarks/core/android_godot_benchmark.gd`, `benchmarks/core/run_android_godot_e2e.sh`, focused Android E2E contract/runner tests and this journal. Add a small locally generated pack fixture inside the installed offline APK run, verify the same production installer contract, first import, idempotent/resumable second install and direct local Knowledge search. Do not add another workflow, model inference call, network dependency or production payload; do not weaken any existing Core, voice, OCR, identity or offline gate.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: exact `28437fa` has 25/25 green workflows; the standalone Knowledge Pack installer smoke and contract tests are already accepted.
REMAINING: implement the installed Android fixture scenario, run focused local checks, publish one atomic candidate and obtain same-SHA Android E2E evidence; full production-pack Windows/Android import remains separate acceptance work.
BLOCKERS: none for the small installed fixture; physical-device/human/server/signing and full production-payload boundaries remain external.
NEXT: add the fixture to the existing Android E2E and raise its required scenario set from 11 to 12 without launching duplicate CI.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

### AFTER: installed release APK now gates pack verification, resume and query

The existing Android normal-path suite now creates a one-record pack inside the installed app sandbox and uses `KnowledgePackInstaller` against the real `AIClient.knowledge` store. The twelfth required scenario fails unless manifest/shard integrity succeeds, exactly one shard is imported, a second install skips that committed shard, the local Knowledge index returns the marker, and the result remains explicitly resumable/offline with `external_ai_required=false`. The runner independently checks those fields instead of trusting only the scenario `passed` flag. No extra inference request, workflow, network call, external tool or repository payload was added.

LOCAL EVIDENCE: `tests/test_android_e2e_runner.py` passes 11/11 simulated release-report cases including rejection of an incomplete pack contract; all three `test_core_android_e2e_contract.py` functions pass; shell syntax, Python compilation and `git diff --check` pass. Godot 4.7.1 parses the changed benchmark with `--check-only`. A fresh isolated real-engine `knowledge_pack_installer_smoke.gd` run prints `AURORA_KNOWLEDGE_PACK_INSTALLER_OK verified=true resumable=true offline=true`. These checks prove syntax/control contracts locally; the installed Android result is intentionally still pending exact-head CI.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: installed Android gate extended from 11 to 12 required scenarios with fail-closed pack details; all focused local tests pass.
REMAINING: publish this atomic candidate and require exact-head Android APK/emulator evidence; full 1.98 GiB production artifact import on Android/Windows is not claimed by the small fixture.
BLOCKERS: no implementation blocker; hosted Android package/emulator acceptance is pending.
NEXT: commit/publish only the four implementation/test files plus this journal, then wait for the single automatically triggered Android E2E instead of dispatching duplicate runs.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

### ACCEPTED: exact installed Android pack evidence

Exact head `94d83f6849e170f34705597d41bec918e61f6dfa` completed all 25 workflows successfully. Core Android E2E run `35524065614`, real installed job `106113115481`, checked out the exact SHA, built and installed the production-runtime APK, disabled external networking and passed all 12 required scenarios. Evidence artifact `10609264894` has ZIP SHA-256 `b4667943267f7bcc96555abe1ede02c7456e79ba691f71d8fb750aafc7a12276`. Its report records `installed_knowledge_pack` passed in `21.369ms`: status `ready`, one imported shard, one skipped shard on resume, `query_match=true`, `offline=true`, `external_ai_required=false`; the overall report is passed with no failed scenarios and exact `git_sha=94d83f6...`.

This accepts the installed Android fixture boundary but does not claim a full 1.98 GiB mobile import. Release-train readiness remains 12/20 (60%) because the fixture closes adapter packaging/control flow, while the mandatory production-payload cross-platform evidence is still pending.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: all exact-head workflows green; installed Android APK verifies pack integrity, import, resume and local query fully offline.
REMAINING: symmetric installed Windows pack evidence and full production-payload platform import/query; physical/human/server/version/signing boundaries remain.
BLOCKERS: none for the Windows installed fixture.
NEXT: add the installed Windows fixture to the existing Windows Package and signed Release paths without a new workflow.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

## 79. Installed Windows Knowledge Pack fixture in existing package/release gates

### BEFORE

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Fresh `origin/main` is `4c6fe649af69c9be0eb080863f0e94b80cc3e082`; exact accepted PR #92/head is `94d83f6849e170f34705597d41bec918e61f6dfa`; public version remains `1.3.0.0`/Android code `100005`, accumulated MINOR `1.4.0.0` version-last. The unrelated owner-modified `assets/ui/aurorafox_background_master.png` remains outside the claim.

CLAIM: add `tests/windows_installed_knowledge_pack_smoke.ps1`, wire it into the already existing installed phase and artifact set of `.github/workflows/windows-package-ci.yml` and `.github/workflows/release.yml`, extend `tests/test_windows_voice_package.py`, and update this journal. The installed executable must run the embedded real Godot pack smoke with isolated user data and external destinations firewall-blocked, then prove durable ready state and one completed shard. Do not add a workflow, alter product Core/Knowledge implementation, include the production payload, weaken other package checks or bump the version early.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: installed Android pack boundary is accepted on exact SHA; Windows package/release already perform one installed-app phase suitable for the symmetric fixture.
REMAINING: implement and locally parse/contract-test the Windows helper, publish once, then require exact installed Windows CI evidence.
BLOCKERS: Windows executable execution and firewall proof require hosted Windows CI; local Linux can only validate contracts and embedded GDScript behavior.
NEXT: implement the minimal helper and reuse the current Windows install instead of rebuilding in a separate job.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

### AFTER: Windows package and signed-release paths require the embedded pack smoke

Added one installed-only PowerShell harness. It selects the installed console wrapper when present, firewall-blocks external IPv4/IPv6 destinations for both wrapper and primary executable while preserving loopback, assigns a unique APPDATA/LOCALAPPDATA profile, and runs `res://tests/knowledge_pack_installer_smoke.gd` from the installed PCK. Acceptance requires exit code zero plus newly persisted manifest, shard and durable state under that isolated profile; state must be `ready`, contain exactly one completed shard whose SHA matches the actual file, and the fixture must have reached its final `production=true` below-1-GiB rejection check. The report records hashes, duration, offline/external-AI flags and diagnostics.

The helper is parsed and invoked inside the existing Windows Package installed phase and is also mandatory in the signed Release Windows install phase. Its evidence joins the existing Windows artifact; there is no additional package build or workflow. The normal product implementation, Core authority, production pack bytes and version remain unchanged.

LOCAL EVIDENCE: all 13 `tests.test_windows_voice_package` unittest cases pass, including new installed-pack/firewall/state/workflow contracts; both changed workflow YAML files parse; Python compilation, Godot 4.7.1 parse of the embedded smoke, and `git diff --check` pass. Local pytest is unavailable, so no pytest result is claimed. Windows installed execution remains pending the exact hosted package run.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: minimal installed Windows pack proof is implemented in both existing package/release paths with focused green local contracts.
REMAINING: publish once and require exact-head Windows installer execution/artifact; the small fixture still does not substitute for the full production-payload import.
BLOCKERS: hosted Windows package boundary is pending; no local Linux substitute is claimed.
NEXT: publish only the claimed workflows/helper/test/journal, then inspect the automatically triggered exact-head Windows run without manual duplicates.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%


## 80. BEFORE: CodeSpecialist structured-response timeout resilience

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Exact PR #92/head is `8b9a253f897906049f232383581b2e42abd68850`; public version remains `1.3.0.0`/Android code `100005`, accumulated MINOR `1.4.0.0` version-last. The unrelated owner-modified `assets/ui/aurorafox_background_master.png` remains outside this claim.

Authoritative Core Benchmarks run `35529016730`, job `106126221219`, artifact `10610379062` disproves the suggested network diagnosis: `guard_expected=true`, `external_probe_blocked=true`, probe HTTP `0`, bundled Core was self-primary, external AI was false and Ollama failures were zero. Six real SpecialistTeam operations passed. `generate_tests` instead consumed the exact 180-second request timeout and returned empty content; stderr records JSON parsing of that empty response. The generic local-model failure path then quarantined the still-running healthy model, so `reason_across_files` failed immediately with the circuit-open message. The offline firewall/probe gate remains unchanged.

CLAIM: `scripts/desktop_local_runtime.gd`, `scripts/aurora_core_runtime.gd`, `benchmarks/core/code_specialist_smoke.gd`, focused Core specialist contracts and this journal. Strict-JSON specialist prompts disable hidden thinking while retaining the full product token ceiling; empty/transport responses are explicit request-scoped failures without noisy empty JSON parsing; a single request-scoped timeout does not quarantine a valid GGUF. Concise failed-condition diagnostics are added without weakening any operation, runtime or offline assertion.

### AFTER: strict JSON uses visible output and request failures preserve model health

Desktop Core now detects the explicit strict-JSON contract already used by every CodeSpecialist operation and sends `reasoning_effort=none`, while retaining the normal 2048-token ceiling. Ordinary complex conversations keep the reasoning path. HTTP transport timeout/empty/invalid-JSON responses are returned as explicit retryable request-scoped failures; empty bodies are no longer passed into `JSON.parse_string`. Missing `choices`/message payloads receive the same request classification.

Aurora Core records that classification in attempt evidence and advances the model circuit breaker only for actual model-scoped failures. A single generation deadline can therefore fail visibly without falsely quarantining a valid, loaded GGUF and blocking the next independent operation. The smoke retains the actual firewall plus `1.1.1.1` probe and all eight operation/runtime assertions, and now prints concise condition values on failure.

LOCAL EVIDENCE: 38 focused and integration Core contract functions pass by direct Python invocation; both changed Python modules compile; `git diff --check` passes. A Godot executable is not present in the fresh local workspace, so no local Godot parse result is claimed. Exact Windows bundled-Core behavior remains pending the automatically triggered hosted benchmark.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: evidence-backed timeout/circuit-breaker correction implemented without weakening the offline network or operation gates.
REMAINING: require exact-head Windows CodeSpecialist and Windows installed Knowledge Pack evidence.
BLOCKERS: hosted Windows runner owns the bundled engine/model timing boundary.
NEXT: wait for attached CI rather than dispatching duplicate checks.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

## 81. BEFORE: installed Windows Knowledge Pack completion polling

Exact remote head `f61f24ee68e396f63b739da7f82c3d9f324ebf93` completed Core Benchmarks run `35534183981` successfully, proving the CodeSpecialist correction. Of 25 workflows, only Windows Package run `35534183886`, job `106146948740`, failed. Packaging, installer creation, historical bridges, silent install and installed app launch all passed. The sole failure is `windows_installed_knowledge_pack_smoke.ps1`: it blocked for 120 seconds on the launcher process and threw before reading its redirected logs or checking whether the isolated fixture/state had already completed.

CLAIM: `tests/windows_installed_knowledge_pack_smoke.ps1`, its focused package contract, and this journal. Replace the blocking process wait with bounded polling of both process state and the fail-closed durable proof. Completion requires the unique isolated profile to contain the ready state, final `production=true` manifest and verified shard; only then may the harness terminate a lingering launcher wrapper and continue the existing strict validations. A timeout must include process state plus stdout/stderr. Do not weaken pack integrity, resume, production-floor, firewall or installed-executable requirements.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: exact failing workflow/job/step identified; Core benchmark fix accepted on the same SHA.
REMAINING: implement bounded completion polling, run focused contracts, publish and require Windows Package rerun.
BLOCKERS: installed Windows executable remains a hosted-runner boundary.
NEXT: make the harness observe the durable result instead of assuming the wrapper process must exit first.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

### AFTER: durable installed result is authoritative, with bounded diagnostics

The Windows harness now polls at 250 ms for at most 120 seconds. It accepts completion only after the unique isolated profile contains all three expected files, the state is `ready` with exactly one completed shard, and the final manifest is `production=true`; the unchanged post-checks still verify schema, pack ID, record count, shard SHA and production-floor exercise. If this proof appears while the exported console wrapper remains alive, the harness terminates only that already-completed wrapper and records `durable_completion_observed=true`. A process exit without proof still fails, and a timeout now includes PID plus captured stdout/stderr instead of the prior opaque message.

LOCAL EVIDENCE: all 13 Windows package/voice/service contract tests pass, the Python test module compiles and `git diff --check` passes. PowerShell is not installed in this Linux workspace, so no local PowerShell parser result is claimed; the existing workflow parser step remains the first exact Windows check. No workflow, installer payload, product Knowledge implementation, firewall boundary or acceptance field was removed.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: installed Knowledge Pack harness no longer conflates a lingering exported wrapper with failure, while durable proof remains fail-closed.
REMAINING: publish and require the exact Windows Package run to pass; full production-payload platform import remains separate.
BLOCKERS: exact installed execution is Windows-hosted only.
NEXT: publish the three-file correction once and wait for automatically attached CI.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

## 82. Installed Windows Knowledge Pack: real exported entrypoint

### BEFORE

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Exact candidate head `61f3bc89557a2534620d01be78a544eeb13b2893` failed Windows Package run `35567400695`, job `106231963299`, after packaging, installer, bridge and normal installed launch had all passed. The installed Knowledge smoke timed out after 120 seconds with no completion result. Its log contained only the normal application startup plus unrelated persisted-JSON parse warnings. The previous polling/atomic-result corrections therefore fixed diagnostics and publication races but did not fix execution: an exported release executable owns its main scene and did not execute the supplied `--script` smoke entrypoint.

CLAIM: `scripts/main.gd`, a reusable installed Knowledge smoke runner under `scripts/`, the existing GDScript/PowerShell wrappers, focused contracts, `.github/workflows/windows-package-ci.yml`, and this journal. Intended bump: BUILD inside the accumulated unreleased MINOR; canonical version remains version-last. Replace the unsupported exported `--script` route with an exact, environment-guarded main-scene mode; keep isolated profile, firewall, integrity, resume and production-floor assertions. Add the same exported-executable gate before the expensive installer, then avoid repeating that identical embedded-PCK check after installation in package CI. Signed Release keeps the installed check.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: exact repeated failure and false assumption identified from the hosted log.
REMAINING: implement, prove the packed main-scene route locally, publish once and require exact Windows evidence.
BLOCKERS: Windows PowerShell/firewall execution remains hosted-runner-only.
NEXT: validate the actual exported resource pack rather than another source-tree-only wrapper.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

### AFTER: exported main scene produces the durable offline proof

The product main scene now recognizes only the exact `AURORAFOX_INSTALLED_SMOKE_MODE=knowledge-pack-v1` value. Before ordinary child nodes enter, it detaches them so services and user state do not initialize, then calls the same reusable `InstalledKnowledgePackSmoke` implementation used by the standalone wrapper. The Windows harness launches only `--headless`, restores every changed environment variable in `finally`, and retains firewall isolation, atomic completion proof, hashes, durable state, resume/idempotence and production-floor rejection checks.

Windows Package now runs this proof directly against `build/windows/AuroraFox.exe` before the 30+ minute Inno Setup phase. Because the Knowledge implementation is compiled inside the executable/PCK and installation cannot change it, the identical package-CI invocation was removed from the later installed phase; installed file inventory, ordinary launch, Voice and local-services checks remain. The signed Release workflow still executes the corrected Knowledge proof from the installed directory.

LOCAL EVIDENCE: 43 focused Python tests plus 13 subtests pass; Python compilation and `git diff --check` pass. Godot 4.7.1 successfully imports the project, runs the standalone wrapper, runs the unchanged normal main scene, and runs the new guarded main-scene route with an isolated profile. Most importantly, a Windows Desktop export PCK was created and launched through its packed main scene (not `--script`): exit `0`, marker `AURORA_KNOWLEDGE_PACK_INSTALLER_OK`, schema `aurorafox.installed-knowledge-smoke.v1`, `passed=true`, `offline=true`, `external_ai_required=false`, and all three persisted file SHA-256 values matched. PowerShell is absent locally, so its exact parser/firewall boundary is not claimed before hosted CI.

PROGRESS_COMPLETE: 60%
PROGRESS_REMAINING: 40%
DONE: real exported main-scene entrypoint and pre-installer fail-fast gate are locally proven; duplicate late package-CI Knowledge invocation removed.
REMAINING: publish the atomic candidate and require the automatically triggered exact-head Windows Package job; no readiness credit until it passes.
BLOCKERS: hosted Windows execution only; unrelated owner-modified UI asset remains untouched and outside this claim.
NEXT: publish once, do not dispatch duplicates, then inspect the early Knowledge gate and complete package job on the exact SHA. If this chat stops, the next ordinary chat must fetch PR #92/head, read this section and the actual run, and fix only the first failing exact phase rather than repeating timeout/speculation changes.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 60%

## 83. ACCEPTED: installed Windows Knowledge Pack and exact-head package train

Exact candidate `82b9f616d595c0850b2cc4ed7acd0ebc6d5b1cf8` completed all 25 automatically attached workflows successfully. Windows Package run `35589431854`, jobs `106300222794` and `106300379048`, passed the exported main-scene Knowledge Pack proof, installer compilation, historical bridges, silent install, ordinary installed launch, offline Voice and local File/Computer services. Windows artifact `10635947773` is 5.45 GB with SHA-256 `86fa579c96a617f6b560453f19c92d34a6648b5593838a74c272c9bd2d165b48`; diagnostics artifact `10636337275` has SHA-256 `40659468e74a1d92d68cdc370e06f9d4b8a4aaa5efa3895fd252349fc7b35317`. Remote candidate tree was independently compared with locally tested commit `245da0b9b25a2d3d813100474c2445f597119e8f` and is byte-identical.

This closes one release checkpoint: installed Windows Knowledge Pack integrity/resume/query execution. The separate Knowledge 1 GiB run `35589431805` remains performance/correctness evidence over a deterministic generated dataset and is not misreported as genuine production content.

PROGRESS_COMPLETE: 65%
PROGRESS_REMAINING: 35%
DONE: 13/20 release checkpoints now have exact evidence; all exact-head automated workflows are green.
REMAINING: full production-payload Windows/Android consumption; physical-device and human UI/listening acceptance; deployed server/mail/backup/rollback; final version/versionCode metadata; final same-SHA RC; production signing/update/release.
BLOCKERS: physical devices, authenticated production host and private release signing authority are external boundaries; full production archive was not yet locally available at this checkpoint.
NEXT: obtain the exact pinned production archive without regenerating it, verify its size/SHA, then run one bounded full-payload import/query acceptance path rather than another fixture or synthetic stress run.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 65%

## 84. BEFORE: exact production Knowledge Pack platform-consumption evidence

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Fresh `origin/main` is `4c6fe649af69c9be0eb080863f0e94b80cc3e082`; exact accepted candidate is `82b9f616d595c0850b2cc4ed7acd0ebc6d5b1cf8`. Public version remains `1.3.0.0`/Android code `100005`; accumulated MINOR `1.4.0.0` remains version-last. Intended claim: `tools/knowledge_pack/**`, the existing Knowledge installer/acceptance harnesses and workflows only when exact full-payload evidence requires a minimal correction, focused contracts, and this journal. Do not alter Core authority, production corpus bytes or accepted fixture gates.

Claimed preparation files are narrowed to new `benchmarks/knowledge/production_pack_acceptance.gd`, `benchmarks/knowledge/run_production_pack_acceptance.py`, `tests/test_production_pack_acceptance.py`, and this journal. Existing production importer/store files remain read-only unless the actual full run reproduces a defect.

The preserved owner artifact with exact filename `AuroraFox-Knowledge-RU-2026.09.01-v1.tar.zst` is present in saved storage with the contract size `429588529` bytes. Two bounded materialization attempts failed with transient HTTP 502 before any local bytes survived; the only similarly named local file is truncated at `98779136` bytes and must never be used as acceptance evidence. The already recorded independent validator evidence for the exact archive remains valid, but full Windows/Android consumption is not accepted until a platform importer reads/query-proves the actual 60 shards.

PROGRESS_COMPLETE: 65%
PROGRESS_REMAINING: 35%
DONE: exact artifact identity and availability were resolved without executing archive contents; truncated local copy rejected.
REMAINING: materialize exact bytes, recheck SHA-256, run bounded full import/restart/query and retain report/RSS evidence.
BLOCKERS: saved-file transfer currently returns HTTP 502; do not substitute generated or partial data.
NEXT: retry only after the transfer boundary is healthy; meanwhile inspect and prepare the smallest fail-closed full-pack runner using the existing validated installer, without launching duplicate multi-hour CI.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 65%

### AFTER: resumable full-payload acceptance runner is ready for the exact archive

Added `production_pack_acceptance.gd` and its bounded Python launcher. The probe first reuses the production installer inspection (schema, production floor, 60 declared shard hashes/sizes and aggregate counts), imports through the existing transactional shard path, reruns the installer to require every shard to be skipped from durable state, restarts `KnowledgeStore`, and searches by a real first-record ID. A pass additionally requires the returned row to retain both the expected shard source and the production `pack_id`; this prevents a stale/unrelated local row from satisfying the query. Reports are atomic and record manifest identity, counts, timings, offline/external-AI flags and Godot static-memory peak.

The Python launcher creates an isolated HOME/XDG/APPDATA profile through the existing benchmark environment, enforces a six-hour default timeout, monitors process RSS, writes stdout/stderr to files so a verbose child cannot deadlock on pipe buffers, and always folds exit/timeout/log tails into the final report. It accepts only an already extracted directory; archive validation/extraction remains a release-input boundary and is not silently delegated to an external AI/runtime.

LOCAL EVIDENCE: both new contract tests and both existing installer contract tests pass by direct standard-Python invocation; the new runner/test modules compile; `--help` imports successfully; a fake executable that returned zero without producing a Godot report was correctly rejected and persisted as `passed=false`; `git diff --check` passes. `pytest` and Godot are not installed in this workspace, so no local Godot runtime result is claimed. The full saved artifact still could not be materialized after two HTTP 502 responses, therefore the runner has not earned release-checkpoint credit.

PROGRESS_COMPLETE: 65%
PROGRESS_REMAINING: 35%
DONE: deterministic full-payload import/resume/restart/query/RSS evidence path implemented without changing the production importer.
REMAINING: obtain exact archive bytes, validate/extract them, execute this runner, then repeat the accepted result through installed Windows and Android boundaries.
BLOCKERS: exact 429588529-byte saved artifact transfer currently fails with HTTP 502; Godot runtime is absent locally; physical/device/host/signing boundaries remain external.
NEXT: commit this isolated preparation batch. On the next available transfer attempt, verify SHA-256 `bc0f312448f70a650435af8f30e853ca0a81a58f69c61802de7095bed9e24614`, run the full acceptance once, and fix only a reproduced failure. Do not start CI or raise readiness for source-only preparation.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 65%

## 85. Production Knowledge acceptance runner: real Godot parse/import correction

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Fresh `origin/main` is `4c6fe649af69c9be0eb080863f0e94b80cc3e082`; PR #92/head is `71d2b78656a7a0b5259ae9f328e9b877207934a7`. All 25 workflows attached to code head `8bafb1035582d227d4658604802d0a6a7a78747f` completed successfully, including Knowledge 1 GiB run `35609087432`, Android E2E `35609087226` and Windows Package `35609086929`. The later three candidate commits change only this journal. Windows artifact `10646213723` is 5.45 GB with workflow digest `0b3950649b9b55496aabf3eb74c1e0cff7aec291c6778adf2825e8a2730ddd8a`.

The first real Godot 4.7.1 execution of the new production-pack probe reproduced a parse failure at the statically resolved `installer.install(...)` member. A fresh checkout also has no global class cache before editor import, so its dependent `KnowledgeImportTransaction`, `KnowledgeStore` and `KnowledgeDocumentImporter` types were unavailable. The runner could therefore time out without ever writing its report even though its source-only contract tests passed.

The probe now invokes the already validated installer method through a checked dynamic boundary and rejects a missing method or non-Dictionary result. The Python runner first performs a bounded Godot editor import in the exact isolated environment, retains separate import stdout/stderr evidence, and fails before the acceptance probe if that import fails or times out. This changes only the evidence harness; the production installer/store, corpus and release contract remain unchanged.

LOCAL EVIDENCE: the two focused Python contracts pass by direct invocation; both modules compile; a clean-project Godot 4.7.1 editor import completed in 6.486 seconds; the corrected probe then executed and fail-closed on a deliberately incomplete copy of the real manifest in 0.501 seconds with exit 3 and `Knowledge Pack shard is missing: knowledge-00000.jsonl`. Warm-up `return_code=0`, probe `timed_out=false`, peak RSS `114626560`. This proves the runtime path is executable and rejects truncated input; it is not full-payload acceptance.

Three authenticated Library transfer attempts for exact saved artifact `libfile_a84d4b8533808191950f7527806ab930` progressed as far as hundreds of megabytes but ended with HTTP 502 and removed the temporary transfer. The existing 98,779,136-byte local file remains rejected as truncated. No substitute corpus or partial pass is claimed.

PROGRESS_COMPLETE: 65%
PROGRESS_REMAINING: 35%
DONE: all current candidate workflows are green; the full-pack runner now parses and runs under real Godot from a clean project and fails closed on incomplete data.
REMAINING: obtain all 429,588,529 archive bytes, verify SHA-256, extract safely, run full import/resume/restart/query evidence, then complete platform/device/host/signing/version-last release gates.
BLOCKERS: Library byte transfer currently terminates with HTTP 502 near the end; physical-device, production-host and signing boundaries remain external.
NEXT: publish this three-file runner correction without starting duplicate long CI; retry the exact archive only after the transfer path is healthy, then run the bounded full acceptance once.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 65%

## 86. External-owner verification: exact production Knowledge Pack recovered

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Journal-only claim from local HEAD `4a655e6d833da96ec767348285b17f8baa23f1b9`: record owner-supplied verification evidence for the exact release input; no product code, corpus bytes, release version or CI workflow is changed. Intended version bump remains the accumulated MINOR `1.4.0.0`, version-last.

The owner verified the exact archive locally after managed transfer repeatedly returned HTTP 502. The archived filename was restored to the contract name `AuroraFox-Knowledge-RU-2026.09.01-v1.tar.zst`; observed size was `429588529` bytes and SHA-256 was `bc0f312448f70a650435af8f30e853ca0a81a58f69c61802de7095bed9e24614`, exactly matching `knowledge_pack/production_pack.json`. A full streaming Zstandard/tar traversal completed: `manifest.json` was first, total members `61`, JSONL members `60`, and the returned manifest states `pack_id=aurorafox-bootstrap-ru`, `pack_version=2026.09.01`, `production=true`, `record_count=75871`, `content_bytes=1924345221`, `file_bytes=1982822407`, Russian Wikipedia 20260901 provenance and CC BY-SA 4.0. The final success marker was subject to Windows console encoding, but the assertions completed without an exception and the complete manifest was emitted.

This closes only archive identity/structural availability. It does not substitute for the already prepared full platform importer acceptance: the exact 60 shards must still be consumed through the bounded import/resume/restart/query runner, then demonstrated through installed Windows and Android boundaries. The archive must remain full and external to Git; do not trim or regenerate it. If a starter subset is later required, create it as a separately hashed optional distribution while retaining this full master artifact unchanged.

PROGRESS_COMPLETE: 65%
PROGRESS_REMAINING: 35%
DONE: exact production artifact SHA/size and complete tar member structure independently confirmed on the owner Windows machine.
REMAINING: full import/resume/restart/query/RSS evidence using the exact artifact; installed Windows/Android consumption; physical device, production host, signing, version-last and same-SHA RC gates.
BLOCKERS: exact bytes are locally available to the owner but still unavailable to this execution workspace because managed transfer returns HTTP 502; physical-device, host and signing boundaries remain external.
NEXT: run the prepared full-pack acceptance against the owner-local archive or materialize the same verified archive once transfer is healthy; fix only a reproduced importer/runtime failure and do not dispatch duplicate long CI.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 65%

## 87. ACCEPTED: exact production Knowledge Pack full offline import/resume/query

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. The owner executed the bounded production acceptance runner from exact published head `5dee3404de6e48101180734e6e2a084d7e4ae760` in an isolated Windows worktree and user-data directory with Godot 4.7.1. The input was the exact full archive `AuroraFox-Knowledge-RU-2026.09.01-v1.tar.zst`: `429588529` bytes, SHA-256 `bc0f312448f70a650435af8f30e853ca0a81a58f69c61802de7095bed9e24614`. Safe streaming extraction completed before the product acceptance run.

The generated `aurorafox.production-knowledge-acceptance.v1` report has `passed=true`, `offline=true`, `external_ai_required=false`, `record_count=75871`, `shards=60`, `content_bytes=1924345221`, and no stderr. Manifest inspection and the release contract passed with `pack_id=aurorafox-bootstrap-ru`, `pack_version=2026.09.01`, manifest SHA-256 `bc395f76c0797e9b3751f11fcb7a52b9999ce5c5857ece1f433778bf1fd75cbd` and extracted-pack SHA-256 `9446aea1a724ca3158a99246ff8af1827cbbe9fad9b5b0476aca38bbc7d30195`. The first install imported all 60 shards and reached `status=ready`; the resume pass imported zero, skipped all 60 durable shards and again reached `status=ready`. After restart, a real lookup returned one row with matching production-pack provenance. Godot warm-up returned zero without timeout; the acceptance process returned zero without timeout in approximately 594.5 seconds. Reported static memory peak was `79960087` bytes.

This is genuine full-payload source-tree Windows/Godot acceptance, not the synthetic 1 GiB benchmark and not a fixture. It closes the production corpus import/resume/restart/query checkpoint. It does not prove that the same full corpus was consumed through the installed Windows package or an Android device, and it does not replace physical-device, human UI/listening, deployment, signing, update or same-SHA release-candidate gates. The full master archive remains external to Git and must not be trimmed or regenerated.

PROGRESS_COMPLETE: 70%
PROGRESS_REMAINING: 30%
DONE: 14/20 release checkpoints now have exact evidence; the full Russian production corpus is identity-verified and has passed a complete offline import/resume/restart/query run.
REMAINING: full-payload installed Windows/Android consumption; physical-device and human UI/listening acceptance; deployed server/mail/backup/rollback; final version/versionCode metadata; production signing/update/release and final same-SHA RC.
BLOCKERS: installed/device acceptance, authenticated production host and private signing authority remain external boundaries; do not weaken these gates or rerun the already accepted source-tree corpus path.
NEXT: retain this report and archive unchanged, then exercise the full corpus through the installed Windows boundary and Android/device boundary. If this chat stops, the next ordinary chat must read section 87 first, accept this exact source-tree result, and continue from the remaining platform boundary instead of repeating extraction or the ten-minute import.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 70%

## 88. BEFORE: installed Windows full production Knowledge Pack boundary

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Fresh `origin/main` is `4c6fe649af69c9be0eb080863f0e94b80cc3e082`; exact PR #92/head is `89c95277ef530a4a0a55bbf3fc4af29d632894b6`. Public version remains `1.3.0.0`/Android code `100005`; the accumulated MINOR `1.4.0.0` remains version-last. The source-tree full production pack gate is accepted in section 87 and must not be rerun merely to exercise the same path.

CLAIM: add an external-pack, environment-guarded installed main-scene mode through `scripts/main.gd`, a new production-only installed Knowledge runner under `scripts/`, a bounded Windows PowerShell harness under `tests/`, focused static contracts, and this journal. The installed executable must inspect the exact release contract, import the owner-supplied extracted production pack with outbound traffic blocked and isolated user data, restart, prove all 60 shards are durably skipped, and query a row with matching pack provenance. Do not bundle the 429 MB archive into Git or CI, alter the accepted importer/store, weaken the existing fixture package gate, start a duplicate workflow, or claim acceptance before the owner runs the resulting installed executable against the exact pack.

PROGRESS_COMPLETE: 70%
PROGRESS_REMAINING: 30%
DONE: exact archive and source-tree full import/resume/restart/query evidence are accepted.
REMAINING: implement and contract-test the installed full-payload boundary, publish it, then execute it once on owner Windows; Android full-payload/device and remaining release gates follow.
BLOCKERS: exact corpus and Windows runtime are owner-local, so this workspace can prepare and test contracts but cannot earn the installed full-payload checkpoint itself.
NEXT: implement the fail-closed installed production mode and bounded two-process Windows harness, run focused contracts, and publish only after local review.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 70%

### AFTER: installed full-payload runner implemented; runtime acceptance still pending

Added the separate guarded mode `knowledge-pack-production-v1`. Normal startup and the already accepted one-shard installed fixture remain unchanged. In the new mode the exported main scene detaches normal application children, reads only an explicit external pack directory, reuses the production installer, compares the manifest with the bundled pinned release contract, performs the import, reopens the local store, and requires a query match with both the production `pack_id` and exact shard source. Its atomic proof records production identity/counts, import/skip counts, state and manifest hashes, query evidence, elapsed time and memory peak; it has no HTTP/process-execution path.

Added `tests/windows_installed_production_knowledge_pack.ps1` as an owner-local acceptance harness. It requires an already installed candidate and the already extracted exact pack, validates the pinned 60-shard/75,871-record/size identity before launch, creates a unique profile, blocks external IPv4/IPv6 destinations for the installed executable, and runs two separate product processes. The first must import all 60 shards and query successfully; after process restart the second must import zero, skip all 60, query successfully, and expose a ready 60-hash state whose SHA-256 is independently recomputed. Timeout is bounded to two hours per phase and failures retain proof/stdout/stderr diagnostics. The archive remains outside Git and no CI workflow was added.

LOCAL EVIDENCE: all four focused production acceptance contract functions pass by direct standard-Python execution; all 13 Windows packaging/voice contract tests pass; `git diff --check` passes. A broad unittest discovery executed 82 tests but ended with 17 import errors because this workspace lacks existing optional test dependencies (`pytest`, `fastapi`, `requests`); no product assertion failure was reported in that run. Godot and PowerShell are not installed here, so no installed runtime pass is claimed. Readiness remains unchanged until the exported Windows candidate executes this harness against the exact owner-local corpus.

PROGRESS_COMPLETE: 70%
PROGRESS_REMAINING: 30%
DONE: fail-closed installed production mode and two-process Windows acceptance harness implemented and focused contracts green.
REMAINING: publish the code, produce one candidate Windows artifact, run `tests\windows_installed_production_knowledge_pack.ps1 -InstallDir <installed-candidate> -PackDir D:\Desktop\AuroraFox-production-test-20260921-223011\knowledge-pack`, then record exact report evidence; Android full-payload/device and remaining release gates follow.
BLOCKERS: this workspace has neither Godot/PowerShell nor the exact corpus/installed Windows binary; owner Windows execution is required for the checkpoint.
NEXT: review and commit this five-file implementation plus journal. After publication, allow exactly one candidate package build and use that artifact for the owner-local installed full-payload run; do not repeat the accepted source-tree import.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 70%

## 89. Exact-head automation accepted; owner installed full-pack run is next

Exact published candidate `fbcb6be180422f2cd776f2940082c516e3e95f85` completed all 25 PR #92 workflows successfully: the authenticated Actions page reports 25 successful, zero failed and zero in-progress runs. Windows Package run `35651438651` (`AuroraFox Windows Package CI #903`) is `Success`; both `process-contract` and `package-windows` passed in 1h03m45s. The only annotations are GitHub's Node.js 20 deprecation warnings for standard actions, not product failures.

The resulting `AuroraFox-Windows` artifact is ID `10666242273`, size 5.45 GB, workflow digest SHA-256 `bc88907a24a0a9dda80446a5171b8352135f057d8c9d6050b78828ac469c514d`. Diagnostics artifact `Windows-installer-diagnostics-fbcb6be180422f2cd776f2940082c516e3e95f85` is ID `10666282475`, size 1.57 MB, digest SHA-256 `ebc8798ed0e720e215fe2a320cc5a216e6fecf901183aad42e60c2dd7f2ab7b7`. This proves that the new guarded mode parses, exports and packages without regressing the accepted automated train. It does not replace the owner-local full-payload installed run because the 429 MB production archive intentionally remains outside CI.

PROGRESS_COMPLETE: 70%
PROGRESS_REMAINING: 30%
DONE: exact-head code publication verified byte-for-byte; 25/25 automated workflows including Windows package and Android gates green; candidate Windows artifact retained with digest.
REMAINING: download/install artifact `10666242273` and execute the two-process full production Knowledge harness against the already extracted exact pack; then Android full-payload/device, production host, signing, version-last and same-SHA RC gates.
BLOCKERS: the installed full-payload evidence requires the owner-local extracted pack and Windows host; no additional CI rerun is required.
NEXT: owner downloads `https://github.com/Treninem/AI/actions/runs/35651438651/artifacts/10666242273`, verifies the artifact digest, installs the contained Setup into an isolated directory, and runs `tests\windows_installed_production_knowledge_pack.ps1` from exact head `fbcb6be` with the existing extracted pack directory. If this chat stops, the next ordinary chat must start from section 89 and must not rebuild or repeat the source-tree pack acceptance.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 70%

## 90. BEFORE: Windows installed full-pack harness exit-code correction

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Fresh `origin/main` is `4c6fe649af69c9be0eb080863f0e94b80cc3e082`; exact release-branch journal head is `bc912de439806412341495efb7bf5cfbfcb864c1`; the packaged product candidate remains `fbcb6be180422f2cd776f2940082c516e3e95f85`. Intended bump remains the accumulated MINOR `1.4.0.0`, version-last.

The owner executed the installed full-pack harness against the exact 5.45 GB artifact and exact production corpus. Artifact SHA-256 matched. The installed first phase genuinely returned `passed=true`, `installed=true`, `offline=true`, `external_ai_required=false`, imported all 60 shards/75,871 records, and matched a production-provenance query. The harness nevertheless threw because Windows PowerShell exposed an empty `Process.ExitCode` after the proof appeared; the code had not unconditionally completed the parameterless `WaitForExit()` synchronization before reading `ExitCode`. This is a harness-only false negative, not a product/import failure.

CLAIM: change only `tests/windows_installed_production_knowledge_pack.ps1`, its focused static contract, and this journal. Synchronize the exited process before reading and caching its exit code, reject a still-running process, retain proof/stdout/stderr diagnostics, and publish without rebuilding the already accepted product artifact or triggering duplicate long CI.

PROGRESS_COMPLETE: 70%
PROGRESS_REMAINING: 30%
DONE: exact installed binary completed the full first import/query phase successfully; the false-negative cause is isolated to PowerShell process-exit observation.
REMAINING: correct and contract-test the harness, publish it, then rerun the two-process acceptance against the same installed artifact/corpus to prove restart skips all 60 shards.
BLOCKERS: owner Windows host is required for the final two-process report; no product rebuild is required.
NEXT: add deterministic process-finalization/exit-code capture, run focused contracts, publish the small harness correction, and give the owner one exact rerun command.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 70%

### AFTER: false-negative exit observation corrected

The harness now treats process completion and proof completion as separate requirements. After the bounded wait succeeds or `HasExited` is observed, it unconditionally calls the parameterless `WaitForExit()` to finalize the Windows process handle and drain redirected stdout/stderr, refreshes the process, and caches `ExitCode` before assertions. A missing exit code now produces its own fail-closed diagnostic instead of being compared as if it were a real nonzero result. Product code, installer bytes, production corpus, firewall isolation and the two-process restart gate are unchanged.

LOCAL EVIDENCE: all four focused functions in `tests/test_production_pack_acceptance.py` pass by direct standard-Python invocation; the module compiles; `git diff --check` passes. This Linux workspace has no PowerShell runtime, so the final Windows verdict remains owner-local. The retained owner proof is accepted only for the first installed phase: exact artifact hash matched, all 60 shards/75,871 records imported offline, and the production-provenance query passed. The checkpoint does not advance until the corrected harness also proves a separate restart imports zero and skips all 60 durable shards.

PROGRESS_COMPLETE: 70%
PROGRESS_REMAINING: 30%
DONE: reproduced false negative corrected without rebuilding or modifying the product candidate; focused contracts are green; successful installed first-phase evidence retained.
REMAINING: publish this harness-only correction and run it once on the owner Windows host against the same installed artifact and exact pack; accept only a complete `report.json` with the restart proof.
BLOCKERS: PowerShell/installed runtime/exact corpus remain owner-local; no automated product workflow needs to be rerun for this harness-only change.
NEXT: publish the two test files plus this journal with CI skipped, then rerun the corrected harness and return only the final report or the first exact exception.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 70%

## 91. BEFORE: replace unreliable Start-Process exit observation and resume existing proof

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Fresh `origin/main` is `4c6fe649af69c9be0eb080863f0e94b80cc3e082`; exact release-branch head is `6fd8b1fd47e8e4fd3b3d78f8d56a7a96ca9013a5`; product candidate remains `fbcb6be180422f2cd776f2940082c516e3e95f85`. Intended bump remains the accumulated MINOR `1.4.0.0`, version-last.

The corrected owner run again proved the installed product path itself: `passed=true`, all 60 shards/75,871 records imported, offline/provenance query matched, and the process exited. Windows PowerShell 5 still exposed a null `ExitCode` even after parameterless `WaitForExit()` on the object returned by `Start-Process`. Therefore the remaining defect is specifically the launcher API, not the corpus, installed executable or importer. Repeating the ten-minute first phase a third time would add no evidence.

CLAIM: modify only `tests/windows_installed_production_knowledge_pack.ps1`, its focused contract, and this journal. Replace `Start-Process` with a directly owned `System.Diagnostics.Process` using asynchronous stdout/stderr draining, and add an explicit paired resume mode that consumes an existing successful install proof plus its existing isolated profile. Default fresh two-phase behavior must remain unchanged; resume mode must fail closed unless the supplied proof is the exact successful 60-import production contract.

PROGRESS_COMPLETE: 70%
PROGRESS_REMAINING: 30%
DONE: two independent installed first-phase runs passed the full production import/query contract; the launcher failure is reproduced and isolated.
REMAINING: implement/test/publish direct process ownership and resume-only evidence reuse, then run only the missing restart phase and produce final report.json.
BLOCKERS: final runtime execution remains owner-local; no product rebuild or corpus re-import is required.
NEXT: patch the harness and static contract, publish with `[skip ci]`, then resume from `D:\Desktop\AuroraFox-fixed-harness-20260922-025430\report\profile-920e52f4118d4e2ca093289267761101` using its `install.result.json`.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 70%

### AFTER: direct .NET process ownership and resume-only completion path ready

The harness no longer uses `Start-Process`. It creates and owns `System.Diagnostics.Process` directly with `UseShellExecute=false`, redirects both streams, starts asynchronous `ReadToEndAsync()` drains immediately, performs the same bounded proof/exit wait, then obtains the native integer `ExitCode` from the directly owned process. Stdout/stderr are still persisted and included in failures. This removes the exact Windows PowerShell 5 wrapper behavior reproduced twice.

Added paired optional parameters `ResumeProfileRoot` and `InstallProofPath`. They must be supplied together. When present, the harness reuses the already isolated APPDATA/LOCALAPPDATA profile and accepts the prior install phase only after checking the strict installed-production schema, `passed/installed/offline`, no external AI, ready status, exact 60 imported/zero skipped identity and successful query. It then runs only a separate `resume` process and retains every existing check: zero imported, 60 skipped, exact pack identity/counts, manifest hash, durable 60-shard state/hash, firewall isolation and query provenance. Default invocation still performs both fresh phases.

LOCAL EVIDENCE: all four focused production acceptance contract functions pass by direct standard-Python invocation; module compilation and `git diff --check` pass. The contract now forbids `Start-Process` in this harness and requires the direct process/async-drain and paired resume-proof paths. PowerShell runtime remains unavailable in this workspace, so readiness stays at 70% until the owner runs the short resume-only phase.

PROGRESS_COMPLETE: 70%
PROGRESS_REMAINING: 30%
DONE: unreliable launcher removed; fail-closed evidence reuse prevents a third full import; focused contracts are green.
REMAINING: publish the harness-only correction and execute the short resume-only command on the retained owner profile; accept the Windows checkpoint only from complete report.json.
BLOCKERS: final installed restart execution is owner-local; no product rebuild, workflow rerun or corpus re-import is needed.
NEXT: publish with `[skip ci]`, fetch the resulting exact head, invoke with `-ResumeProfileRoot` and `-InstallProofPath`, and return the final JSON.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 70%
