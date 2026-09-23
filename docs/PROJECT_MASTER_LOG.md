Warning: truncated output (original token count: 114419)
Total output lines: 3033

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
- Следующий шаг: первым делом забрать `35117014347` и `35112699152`. Если record-dedupe probe падает — передать точный `PERFORMANCE-BLOCKER` владельцу `CHAT-2026-09-16-LOCAL-OCR` с run/job/artifact и требованием content-based within-source dedupe…64419 tokens truncated…ion artifact import on Android/Windows is not claimed by the small fixture.
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

## 92. ACCEPTED: installed Windows full production Knowledge Pack import/restart/query

The owner executed the corrected harness from exact published head `252553900202066bc7b21976caed86acfb54fccb` against the already installed product candidate `fbcb6be180422f2cd776f2940082c516e3e95f85` and the exact extracted production pack. The retained first-process proof had already imported all 60 shards and passed the production-provenance query. A separately launched installed process then reused the isolated durable profile and completed the missing restart phase. The success marker was `AURORA_WINDOWS_INSTALLED_PRODUCTION_KNOWLEDGE_OK`.

The final `aurorafox.windows-installed-production-knowledge.v1` report at `D:\Desktop\AuroraFox-resume-test-20260922-063432\report\report.json` has `passed=true`, `installed=true`, `offline=true`, `external_ai_required=false`, `outbound_firewall_block=true`, `first_imported_shards=60`, `restart_skipped_shards=60`, `first_query_match=true`, and `restart_query_match=true`. Exact identity is `pack_id=aurorafox-bootstrap-ru`, `pack_version=2026.09.01`, 60 shards, 75,871 records and 1,924,345,221 content bytes. Manifest SHA-256 is `bc395f76c0797e9b3751f11fcb7a52b9999ce5c5857ece1f433778bf1fd75cbd`; final durable state SHA-256 is `b9c534b6ece785cf6cdc75cfcab14ad75208d5377f6726773f5444abc5217ee7`. The restart-only wall time was 275,386 ms. Launcher was the installed `AuroraFox.exe`.

The preceding `git fetch` printed an `incorrect old value provided` warning while concurrently updating the local remote-tracking ref, but the exact requested commit was present, the detached worktree was created at `2525539`, and the acceptance ran to completion. This warning did not affect source identity or the runtime verdict. Godot's earlier exit-time leaked-object/resource warnings remain cleanup debt but did not appear as a failure in the final direct-process run and do not invalidate the explicit proof/report contracts.

This closes the installed Windows full-production-payload checkpoint. Do not repeat the archive extraction, source-tree import or Windows full import. The same genuine corpus still requires Android/device consumption evidence; automated Android gates over packaged/synthetic fixtures do not substitute for that boundary.

PROGRESS_COMPLETE: 75%
PROGRESS_REMAINING: 25%
DONE: 15/20 release checkpoints now have exact evidence; genuine production corpus identity, source-tree import/resume/query and installed Windows import/separate-process restart/query are accepted offline.
REMAINING: Android full-production-payload/device consumption; physical-device and human UI/listening acceptance; deployed server/mail/backup/rollback; version/versionCode-last metadata; production signing/update/release and final same-SHA RC.
BLOCKERS: Android physical/runtime boundary, authenticated production host and private signing authority remain external; Windows full-payload acceptance is no longer a blocker.
NEXT: preserve the Windows artifact/report/profile, stop rerunning this checkpoint, and move to the smallest bounded Android full-payload/device evidence path without weakening the ≥1 GiB genuine-content requirement.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 75%

## 93. BEFORE: Android installed full production Knowledge Pack boundary

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Fresh release-branch HEAD is `a60b647dbe32d4706455b257250605c8f95ba17f`; `origin/main` remains the merge base, while this branch contains the accepted release train. Section 92 closes the installed Windows full-payload checkpoint at 75%. Public version remains `1.3.0.0` / Android code `100005`; the accumulated MINOR `1.4.0.0` remains version-last.

CLAIM: add a separate Android production-pack acceptance scene, an owner/emulator ADB harness, focused static contracts and an opt-in workflow that builds an installed test-signed APK from the exact release-branch source. The harness must push the already extracted exact 60-shard corpus once into isolated Android app storage, disable external networking, launch two separate app processes, require the first to import all 60 shards and the restart to import zero/skip all 60, verify production provenance/query and hashes, and retain report/logcat evidence. Do not modify the accepted importer/store, normal main scene, production release metadata or corpus; do not put the 429 MB archive or 1.9 GB extracted payload in Git or Actions artifacts.

Owned files: new `benchmarks/knowledge/android_production_pack_acceptance.gd`, new `benchmarks/knowledge/android_production_pack_acceptance.tscn`, new `tests/android_installed_production_knowledge_pack.ps1`, new `tests/test_android_production_pack_acceptance.py`, optional new manual-only `.github/workflows/android-production-knowledge-acceptance.yml`, and `docs/PROJECT_MASTER_LOG.md`. No production subsystem file is claimed. Intended public bump: none for acceptance tooling; the accumulated release bump remains MINOR and version-last.

PROGRESS_COMPLETE: 75%
PROGRESS_REMAINING: 25%

DONE: Windows installed full production pack is accepted at exact source/report identities; Android production acceptance lane is claimed without touching production runtime files.
REMAINING: implement and contract-test the Android acceptance APK/harness, publish it, execute it with the exact corpus on an Android emulator/device, then complete human/device, production host, signing/version-last and same-SHA RC gates.
BLOCKERS: exact corpus and Android runtime/device boundary are owner-local; production signing and authenticated host boundaries remain external.
NEXT: implement the isolated Android production-pack scene and two-process ADB harness, run focused contracts, publish, then build exactly one acceptance APK and execute it against the retained exact corpus.


## 94. AFTER: Android production Knowledge acceptance APK built

The isolated Android full-payload acceptance tooling is published. The production importer/store and normal main scene were not changed. New acceptance scene `benchmarks/knowledge/android_production_pack_acceptance.tscn` invokes the existing strict installed production runner against `user://android-production-pack`; the PowerShell/ADB harness pins the exact 60-shard identity, clears app state, pushes the owner-local extracted corpus once, restores app UID and SELinux labels, disables external networking, launches two separate installed processes, requires first-import 60 / restart-import 0 / restart-skip 60, verifies provenance queries and independently pulls/hashes the durable state.

Exact build source is `993dd23f93ec1ad6ee7a045d497414751d9b3f66`. GitHub Actions run `35688129695` (`AuroraFox Android Production Knowledge Acceptance APK #4`) completed SUCCESS. Focused contracts (3/3), exact checkout, toolchain setup, Godot import/parse, production-runtime APK build, test signing and artifact upload all passed. Artifact `android-production-knowledge-acceptance-993dd23f93ec1ad6ee7a045d497414751d9b3f66` has ID `10678445830`, size `1633882559` bytes and workflow ZIP digest SHA-256 `d47ba0a96d9aa2321e89cce850deac85bfa80890fda6eb1196ef3ab78683601b`; it expires 2026-10-06. Direct artifact page: `https://github.com/Treninem/AI/actions/runs/35688129695/artifacts/10678445830`.

The workflow is returned to manual-only after this one build so future release-branch commits do not duplicate the 1.6 GB artifact. The corpus itself was not uploaded to GitHub. Runtime acceptance is still pending because the exact extracted corpus and adb-root Android emulator/device are owner-local. On a Windows host with exactly one rooted test emulator visible in `adb devices`, download/extract the artifact and run:

`& '<repo>\\tests\\android_installed_production_knowledge_pack.ps1' -ApkPath '<artifact>\\AuroraFox-Android-Production-Knowledge-Acceptance.apk' -PackDir 'D:\\Desktop\\AuroraFox-production-test-20260921-223011\\knowledge-pack' -ReportDir ('D:\\Desktop\\AuroraFox-android-production-test-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -TimeoutSeconds 7200`

Accept only `AURORA_ANDROID_INSTALLED_PRODUCTION_KNOWLEDGE_OK` plus complete `report.json`. A physical non-root device remains a separate honest boundary; this harness intentionally requires adb-root only for injecting the owner-local corpus into isolated app-private storage and does not weaken the shipped sandbox.

PROGRESS_COMPLETE: 75%
PROGRESS_REMAINING: 25%

DONE: Android exact-pack acceptance scene/harness/contracts are implemented; exact-source 1.6 GB APK build/sign/upload is green at run 35688129695; no production runtime or normal UI file changed.
REMAINING: execute the APK with the exact corpus on Android and record import/restart/query/state evidence; then physical-device/human UI-listening, production host/mail/backup/rollback, production signing/version-last and final same-SHA RC gates remain.
BLOCKERS: exact corpus plus adb-root Android emulator/device are owner-local; authenticated production host and private signing authority remain external.
NEXT: download artifact 10678445830, start one rooted Android emulator with sufficient free space, execute the pinned harness once, and return report.json or the first exact exception. Do not rebuild or re-upload the already accepted APK.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 75%


## 95. BEFORE: rootless physical Android production Knowledge acceptance

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Exact release-branch HEAD before this claim is `02e3d010ca04a439513fcea394e9a26c721d8938`. Section 94 proved the exact-source Android acceptance APK build, but its adb-root injection boundary cannot run on the owner's current non-root physical Android device. The exact production archive is retained outside Git and independently reverified at SHA-256 `bc0f312448f70a650435af8f30e853ca0a81a58f69c61802de7095bed9e24614`.

CLAIM: extend only the isolated Android acceptance surface and Android bridge needed for Storage Access Framework folder selection/copy, plus focused contracts, the manual acceptance workflow and this journal. Add a rootless physical-device path that lets the owner select an already extracted exact pack directory, copies it into app-private storage with bounded progress and path validation, runs the unchanged strict production importer, persists first-run state, performs a separate restart verification, and exports/displays a complete report without adb or root. Do not change the production Knowledge importer/store, normal main scene, public release metadata, corpus bytes or sandbox policy. Intended public bump: none for acceptance-only tooling; accumulated MINOR `1.4.0.0` remains version-last.

Owned files: `android_plugin/plugin/src/main/java/com/aurorafox/runtime/GodotAndroidPlugin.kt`, a new isolated rootless acceptance helper under the same plugin package if needed, `benchmarks/knowledge/android_production_pack_acceptance.gd`, its scene, `tests/test_android_production_pack_acceptance.py`, `.github/workflows/android-production-knowledge-acceptance.yml`, and this journal.

PROGRESS_COMPLETE: 75%
PROGRESS_REMAINING: 25%
DONE: exact archive bytes and existing Android APK build are verified; non-root physical-device constraint is reproduced from the harness contract.
REMAINING: implement, contract-test, build and execute the rootless physical-device acceptance; then human UI/listening, production host/mail/backup/rollback, signing/version-last and same-SHA RC gates remain.
BLOCKERS: physical-device execution remains owner-interactive after the rootless APK is built; authenticated production host and private signing authority remain external.
NEXT: add a narrowly scoped Android SAF directory-copy bridge and interactive acceptance state machine, run focused contracts, build one exact-source APK, then give the owner direct install/select/restart instructions.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 75%


### AFTER: rootless physical-device acceptance APK built

The non-root Android boundary now has a dedicated isolated acceptance path. The APK uses Android's system document picker to select the exact owner-held `.tar.zst` archive, hashes the complete compressed stream before extraction, requires archive SHA-256 `bc0f312448f70a650435af8f30e853ca0a81a58f69c61802de7095bed9e24614`, rejects traversal/special entries and bounded-size/file-count violations, extracts only into the app-private acceptance directory, and requires exactly 60 JSONL shards plus a root manifest. No root, adb, PC, broad storage permission, corpus-in-Git or corpus-in-APK is used.

The interactive acceptance scene preserves the existing adb-root automation path while adding a physical-device state machine. It instructs the owner to enable airplane mode after verified local extraction, runs the unchanged strict production importer, requires first-import 60/skip 0 and the exact manifest/count/bytes/query contract, persists the first proof, exits, then on a separately launched process requires import 0/skip 60 and a second provenance query. Success emits `AURORA_ANDROID_ROOTLESS_PRODUCTION_KNOWLEDGE_OK` and exposes the complete JSON through the Android share sheet.

LOCAL EVIDENCE: all four focused Android production acceptance contract functions pass by direct standard-Python invocation; the exact 429,588,529-byte archive was independently listed and confirmed to contain root `manifest.json` plus `knowledge-00000.jsonl` through `knowledge-00059.jsonl`. CI build source `0a9680f03ea84987dd89cd0f69fdae40939c5110` passed exact checkout, 4/4 focused contracts, Android/Kotlin/Gradle compilation with bounded zstd/tar support, Godot import/parse, full production-runtime APK build, test signing and upload in run `35719694874` (SUCCESS). Artifact `android-production-knowledge-acceptance-0a9680f03ea84987dd89cd0f69fdae40939c5110` has ID `10691590889`, size `1633906700` bytes and ZIP digest `sha256:e56bc27f48a5f860f8fa5bb6a0b6fde6f0c809adf1e38f3bfe4928a3e1c82d28`; it expires 2026-10-06. Direct artifact page: `https://github.com/Treninem/AI/actions/runs/35719694874/artifacts/10691590889`. The workflow is restored to manual-only after this one build.

PROGRESS_COMPLETE: 75%
PROGRESS_REMAINING: 25%
DONE: rootless exact-archive selection, hash verification, bounded private extraction, two-launch strict import/restart/query proof and report sharing are implemented; full APK build/sign/upload is green at run 35719694874.
REMAINING: install and execute the rootless APK on the owner's current physical Android device and accept only its shared complete report; then human UI/listening, production host/mail/backup/rollback, private signing/version-last and final same-SHA RC gates remain.
BLOCKERS: the next step is owner interaction on the current non-root physical device; authenticated production host and private signing authority remain external.
NEXT: owner downloads artifact 10691590889 on Android, extracts the workflow ZIP, installs the APK, selects `AuroraFox-Knowledge-RU-2026.09.01-v1.tar.zst`, enables airplane mode when prompted, completes the first run and separate relaunch, then shares the generated JSON back to this chat.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 75%


## 96. BEFORE: one-command Windows Android emulator acceptance orchestration

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Exact release-branch HEAD before this claim is `ad06c29a0beaf503e056ab6ed417022b76205ed7`. The rootless APK is built, but the owner elected to execute the strict adb-root acceptance later from the retained Windows PC, where the exact extracted pack already exists. Existing Android acceptance APK artifact `10691590889` and the accepted Windows pack directory are reusable; neither corpus import code nor product binaries require another change.

CLAIM: add one Windows-only orchestration script and a focused static contract test, plus this journal. The script must discover Android SDK tools, optionally install a pinned emulator/system image, create or reuse a dedicated AVD, boot it with bounded waits, require exactly one target and successful `adb root`, resolve the already downloaded APK artifact and exact extracted pack, invoke the existing strict two-process harness, preserve reports, and stop with precise remediation rather than modifying Windows virtualization settings. Do not rebuild the APK, duplicate the corpus, weaken hashes, edit product code or change release metadata. Intended public bump: none; acceptance tooling only.

Owned files: new `tests/windows_android_production_knowledge_orchestrator.ps1`, new `tests/test_windows_android_production_orchestrator.py`, and this journal.

PROGRESS_COMPLETE: 75%
PROGRESS_REMAINING: 25%
DONE: Windows installed full-pack proof accepted; exact Android APK and corpus are retained; PC route selected.
REMAINING: implement/publish the bounded Windows emulator orchestrator, then execute it on the owner's PC and accept only the strict Android report.
BLOCKERS: final emulator execution requires the owner's Windows virtualization boundary; authenticated production host and private signing authority remain external.
NEXT: implement and contract-test the one-command orchestrator using the pinned Android API/system image and existing strict harness.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 75%


### AFTER: one-command Windows emulator orchestration published

Added `tests/windows_android_production_knowledge_orchestrator.ps1`. It discovers an existing Windows Android SDK, installs/accepts only the pinned `platform-tools`, emulator and `system-images;android-35;google_apis;x86_64` components when requested, creates or reuses dedicated AVD `AuroraFox_Acceptance_API_35`, runs the emulator acceleration check, boots a clean headless instance with bounded timeout, requires exactly one ready target and UID 0 after `adb root`, verifies the retained workflow artifact ZIP digest `e56bc27f48a5f860f8fa5bb6a0b6fde6f0c809adf1e38f3bfe4928a3e1c82d28` plus its embedded APK SHA file, and invokes the unchanged strict Android full-production harness. Reports, acceleration output, adb-root output and emulator PID are retained under one timestamped report directory. The script never downloads an unpinned executable, changes BIOS/Hyper-V settings, deletes arbitrary directories or rebuilds the APK/corpus.

Focused evidence: `tests/test_windows_android_production_orchestrator.py` passes by direct standard-Python invocation and compiles. It asserts the pinned API 35 image/AVD, exact artifact identity, SHA checks, acceleration/boot/root/one-device gates, strict harness reuse, bounded timeouts, final report marker and absence of network downloader/destructive virtualization commands. This environment cannot execute Windows PowerShell or hardware-accelerated Android virtualization, so the runtime verdict remains correctly pending on the owner PC.

PROGRESS_COMPLETE: 75%
PROGRESS_REMAINING: 25%
DONE: reusable exact APK/corpus retained; Windows SDK/AVD/root/boot/artifact/harness orchestration implemented and focused contract green.
REMAINING: execute the published one-command orchestrator on the owner Windows PC and accept only `AURORA_WINDOWS_ANDROID_PRODUCTION_ORCHESTRATION_OK` plus complete `report.json`; then remaining physical/human, production-host, signing/version-last and same-SHA RC gates continue.
BLOCKERS: Windows hardware virtualization and installed Android SDK boundary are owner-local; authenticated production host and private signing authority remain external.
NEXT: fetch the resulting exact head on the owner PC, download artifact 10691590889 once, and invoke the orchestrator with `-ArtifactPath`; if it stops, return only its first exact exception.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 75%


## 97. BEFORE: Windows PowerShell 5 native stderr compatibility hotfix

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Exact release-branch HEAD before this claim is `355c122ec3ad8b2f69a805e0597d5c2436c61baf`. Owner-PC execution reached the Android SDK command-line boundary and reproduced a deterministic Windows PowerShell 5 failure: the installed `sdkmanager.bat` emits a non-fatal deprecation warning on stderr, but `$ErrorActionPreference = 'Stop'` promotes the native stderr record to `NativeCommandError` before the orchestrator can inspect `$LASTEXITCODE`.

CLAIM: update only the Windows Android production Knowledge orchestrator, its focused static test and this journal so native SDK tools may emit warnings on stderr while non-zero exit codes remain fatal with complete captured output. Do not weaken artifact hashes, SDK/image pinning, emulator/root/device gates or the strict production Knowledge harness. Intended public bump: none; acceptance-tooling hotfix only.

Owned files: `tests/windows_android_production_knowledge_orchestrator.ps1`, `tests/test_windows_android_production_orchestrator.py`, and `docs/PROJECT_MASTER_LOG.md`.

PROGRESS_COMPLETE: 75%
PROGRESS_REMAINING: 25%
DONE: owner PC proved SDK discovery, adb availability and exact PowerShell 5 stderr failure boundary.
REMAINING: implement and contract-test the native invocation compatibility fix, publish it, rerun on the owner PC and accept the strict Android report.
BLOCKERS: Windows emulator/runtime execution remains owner-local; authenticated production host and private signing authority remain external.
NEXT: make native command stderr capture non-terminating only inside the checked invocation helper, preserve exit-code enforcement, add a regression contract and publish the hotfix.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 75%


### AFTER: Windows PowerShell 5 native stderr compatibility hotfix published

Published implementation commit `9c7e183cb22cfc47ab3562d53c9c51a5472e8288` after claim commit `8be582e95fa52761946cd654997c23c2d114405c`. `Invoke-Checked` now temporarily changes only its local native-command error preference to `Continue`, redirects both native streams, saves `$LASTEXITCODE`, restores the caller preference in `finally`, and still throws with complete output for every non-zero native exit. This prevents a successful `sdkmanager.bat` deprecation warning from aborting Windows PowerShell 5 while preserving all actual SDK-tool failures.

The focused contract now pins the save/restore behavior, captured exit code and non-zero enforcement. Exact committed script/test blobs `da4b9c3a170f9dc5f495dc3aa840c4d59942255b` and `66c09b4004d01c9db8829ff0e8eab28c54bef250` passed remote exact-content verification for all five regression assertions. Artifact digest, SDK/image pinning, acceleration, adb-root, one-device and strict production Knowledge gates are unchanged. Windows runtime proof remains pending on the owner PC. The hotfix claim is DONE and its owned implementation/test files are released; the parent final-release claim remains ACTIVE.

PROGRESS_COMPLETE: 75%
PROGRESS_REMAINING: 25%
DONE: reproduced PowerShell 5 `NativeCommandError`; published commit `9c7e183cb22cfc47ab3562d53c9c51a5472e8288`; exact-source regression contract verified; strict acceptance gates preserved.
REMAINING: fetch the hotfix on the owner PC, rerun the emulator orchestrator and accept only its complete strict Android report; subsequent release gates remain unchanged.
BLOCKERS: Windows emulator/runtime execution is owner-local; authenticated production host and private signing authority remain external.
NEXT: fast-forward the owner repository, create a fresh detached worktree at the new exact head, and rerun `windows_android_production_knowledge_orchestrator.ps1` with the discovered SDK root.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 75%

## 98. BEFORE: owner-directed Android deferral and production-host release continuation

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Fresh release-branch HEAD is `392fffaf7e8b6de040d19ee09cc8b695047f006c`; fresh `origin/main` is `4c6fe649af69c9be0eb080863f0e94b80cc3e082`. Public version remains `1.3.0.0` / Android code `100005`; accumulated MINOR `1.4.0.0` remains version-last.

OWNER DECISION: defer the Android full-production-payload emulator/device acceptance for the current continuation because Android is not release-critical now. The repeated `emulator-5554 offline` outcome on Emulator 37.1.11 and 36.6.11 is not accepted as a product pass and is not a reason to keep the Windows/server release work idle. The Android checkpoint remains explicitly unverified and the production release workflow keeps its existing fail-closed Android gates.

CLAIM: audit and exercise the existing production-host deployment, mail, backup, restore/rollback and release-preflight contracts; fix only a reproduced repository-side defect, if any, and add focused regression coverage before implementation. Owned scope is limited to `deploy/`, related focused tests/workflow contracts, release-preflight diagnostics and this journal. Do not access or invent production credentials, deploy externally, weaken signing/platform gates, merge `main`, tag a release or bump the public version early.

PROGRESS_COMPLETE: 75%
PROGRESS_REMAINING: 25%
DONE: installed Windows exact full-production Knowledge proof remains accepted; Android runtime acceptance is honestly deferred rather than misreported.
REMAINING: identify and close the next repository-side production-host/preflight defect; authenticated host execution, human UI/listening, version/versionCode-last, production signing/update/release and final same-SHA RC remain external or later gates.
BLOCKERS: authenticated production host and private signing authority are unavailable in this environment; Android device acceptance is deferred by owner decision.
NEXT: run focused deployment/persistence/release contract tests, inspect the first exact failure, and make one bounded test-first correction or record the existing boundary as ready.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 75%


### AFTER: repository deployment and signing boundary is ready; external execution remains

No repository-side defect was reproduced in the claimed boundary, so no production deployment, backup, signing or release code was changed. `install.sh`, `update.sh` and `verify.sh` pass `bash -n`; the API and focused Python contracts compile. Nine deployment contracts pass, including pinned SFTP backup, GitHub-main-only fast-forward updates, database snapshot/rollback, fail-closed production verification, SMTP/TLS boundaries and the self-cleaning CI verifier. Seven executable persistence-maintenance tests pass against temporary SQLite stores, including WAL-aware capacity warnings, protected private/sync state, refresh replay preservation and persisted maintenance cadence. Twenty-five release identity, signing-order, version-policy and legacy update compatibility contracts pass.

The committed update public key parses successfully and its DER SHA-256 is `9cd72647edfa647a2988cc094080597860de8ce386bcfb1b40c2360e363d8ae7`, matching `update/release_identity.json`. The committed Android certificate DER SHA-256 is `79b9451912d74ed9bffb1b4070795786470e6a26d1bc2833213de3092d793c93`, also matching the pinned identity. Full pytest was unavailable in this environment; the seven fixture-dependent persistence tests were executed with isolated temporary paths and equivalent environment/exception fixtures, and all other focused tests were invoked directly with standard Python.

This proves repository readiness only. It does not prove REG.RU DNS/TLS, real SMTP delivery, live backup retrieval, rollback on the authenticated host, availability of private signing keys, or a published same-SHA release. Those gates require owner-controlled access and must remain fail-closed. The production release workflow still requires both Windows and Android jobs; Android full-payload acceptance remains deferred, not passed. Public version and Android versionCode remain unchanged for version-last.

PROGRESS_COMPLETE: 75%
PROGRESS_REMAINING: 25%
DONE: Android deferral recorded; deployment/mail/backup/rollback contracts and pinned public identities revalidated; no repository-side blocker found.
REMAINING: authenticated REG.RU install/configure/verify evidence; human UI/listening; private-key readiness; version/versionCode-last; final same-SHA signed RC and publication. Deferred Android acceptance remains outstanding for the full cross-platform release.
BLOCKERS: production-host credentials, SMTP settings and private signing authority are owner-controlled and absent here.
NEXT: on the authenticated production host configure SMTP and run `bash /opt/aurorafox/repository/deploy/reg_ru/verify.sh`; return its final marker or first exact failure. Do not bump/tag/sign before that evidence is accepted.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 75%

## 99. BEFORE: release-branch Python audit dependency and stale Knowledge batch contract

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Exact release-branch HEAD before this claim is `86e88a65cc44f3efae16eba374c1c492b7ef2c12`; fresh `origin/main` is `4c6fe649af69c9be0eb080863f0e94b80cc3e082`. Public version remains `1.3.0.0` / Android code `100005`; intended public bump is none for this test-only correction.

SERVER AUDIT EVIDENCE: an isolated Python 3.14 audit environment on the authenticated production host completed 380 tests with five failures. Four are environment-only missing optional format dependencies (`Pillow`/`rarfile`). The fifth is `tests/test_knowledge_store_batch_contract.py`, which still asserts `STRUCTURED_WRITE_BATCH := 128` even though later intentional performance commit `54b726a` changed the production constant to `2048` (`perf: batch and compact large knowledge persistence`). The runtime implementation is not reverted; the stale source-text contract must follow the accepted optimized value.

CLAIM: update only `tests/test_knowledge_store_batch_contract.py` and this journal, then run the focused contract and the expanded host suite after optional test dependencies are installed in `/opt/aurorafox/audit/.venv`. Do not change production Knowledge code, production Python/runtime packages, public version metadata, deployment state or release signing.

PROGRESS_COMPLETE: 80%
PROGRESS_REMAINING: 20%
DONE: production-host verify is green; 32/32 focused deployment/release tests and 380 expanded Python tests pass; stale Knowledge batch assertion and four dependency-only failures are classified.
REMAINING: correct and verify the stale test; install isolated audit-only `Pillow 12.3.0` and `rarfile 4.5` after owner confirmation; rerun the expanded suite and record the exact result. Remaining release gates stay unchanged.
BLOCKERS: action-time owner confirmation is required before installing the two audit-only Python packages; private signing/version-last/final same-SHA RC and deferred Android acceptance remain outstanding.
NEXT: commit the claim, change the single stale assertion to `2048`, run the focused test, then request/install only the compatible wheel packages in the isolated audit venv.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 80%

### AFTER: stale Knowledge batch contract corrected locally

Updated only `tests/test_knowledge_store_batch_contract.py`: the source-text contract now pins the intentional production value `STRUCTURED_WRITE_BATCH := 2048` introduced by performance commit `54b726a`, rather than reverting optimized production code to the obsolete `128` batch size. Both functions in the focused contract were imported and executed directly with standard Python because the local sandbox does not include pytest; both completed successfully. The authenticated host expanded suite remains pending until compatible optional-format wheels are installed in the isolated audit venv.

PROGRESS_COMPLETE: 80%
PROGRESS_REMAINING: 20%
DONE: stale assertion corrected; both focused Knowledge batch/removal contract functions pass locally; production Knowledge code remains unchanged.
REMAINING: install audit-only `Pillow 12.3.0` and `rarfile 4.5` after action-time owner confirmation, mirror this exact test correction to the host audit checkout, rerun the expanded suite and publish the verified commit.
BLOCKERS: owner confirmation is required for the isolated test-package installation; final release gates remain unchanged.
NEXT: obtain confirmation, install only the two compatible wheels under `/opt/aurorafox/audit/.venv`, apply the exact one-line test correction in the audit checkout and rerun the expanded Python suite.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 80%

### AFTER: complete release-branch Python audit is green

The exact one-line Knowledge contract correction was mirrored to the authenticated host audit checkout. Owner-approved optional dependencies were installed only under `/opt/aurorafox/audit/.venv`; no production Python environment, service, data or deployment state was modified. The complete release-branch Python suite then passed without exclusions: `421 passed, 1 skipped, 942 warnings in 16.74s`. The seven initially failing local-OCR tests passed after adding their declared PDF renderer dependency `pypdfium2 5.13.0` to the isolated audit environment. The earlier four optional-format dependency failures also pass with the isolated compatible wheels.

This closes the repository Python-audit defect and dependency-classification boundary. It does not claim Android runtime acceptance, private-key availability, a version bump, signed artifacts, a tag or a published same-SHA release.

PROGRESS_COMPLETE: 80%
PROGRESS_REMAINING: 20%
DONE: production-host verification is green; 32/32 focused deployment/release tests pass; the complete release-branch Python audit passes 421/421 executed tests with one skip; the stale Knowledge batch contract is corrected without changing production runtime code.
REMAINING: publish these journal/test commits to the release branch; then complete human UI/listening, private signing readiness, version/versionCode-last, final same-SHA signed RC and publication. Android full-production-payload acceptance remains explicitly deferred and unverified.
BLOCKERS: this environment has no GitHub push credentials; private signing authority and final owner acceptance remain external. Deferred Android acceptance remains outstanding for the eventual full cross-platform release.
NEXT: transfer the local commits to the authenticated owner repository, push the release branch, then execute the next version-last/signing preflight without weakening the deferred Android gate.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 80%

## 100. OWNER WAIVER: Android full-production Knowledge payload acceptance deferred

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Exact release-branch source for this decision is `245b98ca0347b29e7022277b3613e3d0e4f33729`. The authenticated production-host verifier is green, the complete release-branch Python audit is green (`421 passed, 1 skipped`), and the installed Windows full-production Knowledge proof remains accepted.

OWNER DECISION: the separate 1.9 GB Android full-production Knowledge payload acceptance attempted on the owner's Windows emulator is waived for the current release decision. The observed `emulator-5554 offline` runs produced no valid strict report, so this checkpoint is recorded as `OWNER_WAIVED_NOT_EXECUTED`, never as a technical pass. It no longer blocks the current release continuation.

The ordinary Android production release gates are not weakened: `.github/workflows/release.yml` must still build with the pinned package/version and permanent signing identity, verify the finished APK certificate, install and launch the signed APK on Android 35, reject a package crash, and publish the Android artifact only after those checks succeed. The deferred 1.9 GB Knowledge import must be completed later before claiming the separate full-payload Android capability as verified.

PROGRESS_COMPLETE: 80%
PROGRESS_REMAINING: 20%
DONE: owner waiver is explicit and auditable; the failed local emulator attempt is not misrepresented; current release work may continue; standard signed Android CI gates remain mandatory.
REMAINING: verify owner-controlled GitHub signing-secret names, perform version/versionCode-last for V1.4.0.0, run the final same-SHA signed Windows/Android RC and publish only after the mandatory release workflow is green. Complete the waived full-payload Android Knowledge acceptance later.
BLOCKERS: private signing-secret readiness is not readable through the connected GitHub App and must be checked from the authenticated owner environment before version-last/tagging.
NEXT: run `build/bridge_release_readiness.ps1` from the authenticated owner PC without `-SkipGitHubSecrets` and return its final marker or first exact failure.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 80%

## 101. BEFORE: canonical application icon and silent bundled-Core recovery

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Exact release-branch HEAD before this claim is `7b4806fa74b3034c9cbf09144c5e30bfd6461050`. Owner screenshots from the installed V1.3 package reproduce two release-facing defects: the Windows shell/title icon still uses the legacy SVG placeholder instead of the approved white-fox master, and normal chat exposes the internal `Ошибка модели` quarantine diagnostic after a valid-header user GGUF fails to load.

CLAIM: use the existing byte-pinned `assets/ui/aurorafox_avatar_master.png` as the canonical project/Windows application icon; make the verified packaged Windows Core the primary runtime candidate while retaining local user GGUF only as fallback; include the packaged Core in failover discovery; perform one bounded automatic Core recovery retry for normal chat; and replace any final internal model diagnostic with a non-technical message that explicitly requires no installation or configuration. Add focused static contracts and journal evidence. Do not weaken model integrity, signing, offline, privacy, Work/Computer failure or release gates.

PROGRESS_COMPLETE: 80%
PROGRESS_REMAINING: 20%
DONE: owner screenshots classified; exact legacy icon and model-quarantine paths reproduced in source; canonical owner artwork and verified packaged Core already exist.
REMAINING: implement and test the bounded icon/Core recovery correction, publish it, then rerun signing preflight and version-last gates.
BLOCKERS: GitHub secret-name readiness and local pytest availability remain separate owner-environment preflight items.
NEXT: add failing contracts for canonical icon, packaged-Core priority/fallback and bounded user-facing recovery, then implement the minimal runtime/UI correction.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 80%

### AFTER: canonical owner icon and bounded automatic Core recovery implemented

The canonical byte-pinned `aurorafox_avatar_master.png` is now the project icon and explicit Windows export icon. Godot 4.7 supports generating the Windows executable/taskbar icon from this PNG through `application/icon`, so the legacy `fox_logo.svg` is no longer the installed application identity. The in-app owner avatar/background masters are unchanged byte-for-byte.

Windows runtime selection now prefers the verified packaged Core before any valid-header `user://` model left by an older installation. The packaged Core is also inserted into the bounded failover candidate list when a different model was selected. Normal chat performs exactly one automatic recovery reset/restart and retry; if the owned Core still cannot answer, the internal `Ошибка модели` diagnostic is replaced before chat persistence, speech and UI display with a non-technical notice stating that no installation or configuration is required. Work and Computer failure classification remains fail-closed and unchanged.

Focused evidence: all 15 branding/Core static contract functions pass by direct standard-Python invocation; all 20 release/update identity contract functions pass the same way; both changed Python files compile; `git diff --check` is clean. This sandbox has no Godot executable or pytest module, so parser/export/package verification remains assigned to the existing GitHub integration and Windows package workflows on the exact published commit.

PROGRESS_COMPLETE: 82%
PROGRESS_REMAINING: 18%
DONE: owner-master app icon wired; verified packaged Core prioritized and retained in failover; one bounded automatic normal-chat recovery added; raw model diagnostics removed from user chat; 35 focused contracts pass.
REMAINING: publish the exact implementation, accept CI, verify the four owner-controlled GitHub signing-secret names, then perform V1.4.0.0 version/versionCode-last and final same-SHA signed RC.
BLOCKERS: GitHub secret names cannot be read through the connected GitHub App; the owner PC lacks `gh` and pytest, but the 20 release contracts themselves are green in the audited environment.
NEXT: publish the implementation to the release branch and inspect triggered integration/package checks; install/authenticate GitHub CLI on the owner PC only for secret-name verification.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 82%

## 102. BEFORE: GitHub-hosted signing-secret readiness gate

`WORK-2026-09-17-FINAL-RELEASE` remains ACTIVE under the sole coordinator/executor. Exact release-branch HEAD is `3791ca6ae2e50189a0e103c0fbfae831a78ff794`; all 25 workflows associated with this exact SHA completed `success`, including Windows package/install/smoke, Android APK/offline E2E, Release Identity, Integration and real Knowledge 1 GiB gates. Public version remains `1.3.0.0` / Android code `100005`; accumulated release bump remains MINOR `V1.4.0.0`, version-last.

CLAIM: add a manual, non-publishing GitHub Actions preflight which validates presence and basic parseability of the four owner-controlled release secret values inside GitHub without printing them, plus a focused static contract and this journal. The preflight must not build, sign, tag, upload, release or expose secret content. Intended public bump: none; release acceptance tooling only.

Owned files: new `.github/workflows/release-secret-readiness.yml`, new `tests/test_release_secret_readiness_workflow.py`, and this journal.

PROGRESS_COMPLETE: 82%
PROGRESS_REMAINING: 18%
DONE: exact candidate `3791ca6` accepted by all 25 triggered workflows; owner icon/Core recovery package and Android offline E2E are green.
REMAINING: implement/publish/run the secret-readiness preflight; if green, perform the single V1.4.0.0/versionCode-last bump and final same-SHA signed RC.
BLOCKERS: the connected GitHub App cannot read repository secret names or values directly; the owner PC does not have GitHub CLI.
NEXT: implement a fail-closed workflow_dispatch preflight that checks secrets only inside GitHub Actions and emits no secret material.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 82%

### AFTER: non-publishing GitHub signing-secret preflight implemented

Added manual workflow `AuroraFox Release Secret Readiness`. It has read-only repository permission, no push/tag/release/artifact operation and a ten-minute bound. Inside GitHub Actions it fails closed if any of the four signing secrets is empty, masks the non-base64 credentials, decodes values only into a mode-077 temporary directory, validates the update RSA private key, derives its public-key fingerprint and compares it with `update/release_identity.json`, then validates the Android keystore alias/password and compares its exported certificate SHA-256 with the pinned Android identity. Temporary private material is removed by a shell trap and no secret content is printed.

Focused evidence: all three functions in `tests/test_release_secret_readiness_workflow.py` pass by direct standard-Python invocation; the test compiles; the workflow parses as YAML; `git diff --check` is clean. The actual secret verdict remains pending until the newly published `workflow_dispatch` is executed in GitHub Actions.

PROGRESS_COMPLETE: 82%
PROGRESS_REMAINING: 18%
DONE: 25/25 exact-candidate workflows green; safe GitHub-hosted secret presence/identity preflight implemented and statically verified.
REMAINING: publish and manually dispatch the preflight; if green, perform V1.4.0.0/code100006 version-last, rerun exact-SHA package/release gates and publish the signed RC.
BLOCKERS: actual owner-controlled secret values can only be validated when GitHub executes the workflow.
NEXT: publish this tooling-only commit, dispatch `release-secret-readiness.yml` on the release branch, and inspect its exact result without polling unrelated workflows.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 82%

### TAKEOVER: embed the preflight in the default-branch Release workflow

GitHub correctly does not expose a newly added standalone `workflow_dispatch` until that workflow file exists on the default branch. The tooling commit `f7c5e83c37d21d6011ef85d736956f358894883c` is published, but its standalone manual workflow therefore cannot be dispatched on the release branch before merge. To avoid merging an unversioned candidate or running the full expensive release build merely to inspect secrets, this claim now explicitly takes over `.github/workflows/release.yml` from the already integrated updater/release lane and revises the static contract.

The existing Release workflow will receive a boolean `secrets_only` manual input, a bounded read-only identity check, and an `if` guard that skips `core-gates` (therefore all dependent build/publish jobs) when the preflight-only mode is selected. Tag pushes and ordinary manual release runs retain their existing behavior. The inaccessible standalone workflow will be removed.

Owned files now: `.github/workflows/release.yml`, removal of `.github/workflows/release-secret-readiness.yml`, `tests/test_release_secret_readiness_workflow.py`, and this journal. Intended public bump remains none; this is release acceptance tooling only.

PROGRESS_COMPLETE: 82%
PROGRESS_REMAINING: 18%
DONE: standalone preflight logic is implemented and its default-branch dispatch limitation is reproduced in authenticated GitHub UI.
REMAINING: embed and test the input/job/skip contract, publish it, dispatch `release.yml` with `secrets_only=true`, then act on the exact secret identity result.
BLOCKERS: none for implementation; actual secret validity remains a GitHub-hosted runtime fact.
NEXT: patch existing Release workflow and focused contract, verify ordinary/tag paths are unchanged, publish and run only the preflight job.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 82%

### AFTER: dispatchable secrets-only mode embedded in Release workflow

The existing default-branch `AuroraFox Release` workflow now exposes a boolean manual input `secrets_only` defaulting to false. When true, only the ten-minute signing-identity preflight is eligible to run; `core-gates` is explicitly skipped, so its dependent Windows and Android jobs cannot start, and the publish job remains tag-only. Ordinary manual runs and tag pushes preserve the previous full release behavior. The standalone workflow from `f7c5e83` is removed because GitHub cannot dispatch it before default-branch integration.

Focused evidence: 29 directly invocable release/preflight contract functions pass across the new static contract, release core gates, backward compatibility and release identity/version policy; the changed Python test compiles; the modified Release workflow parses as YAML and has the expected guarded job structure; `git diff --check` is clean.

PROGRESS_COMPLETE: 82%
PROGRESS_REMAINING: 18%
DONE: all 25 candidate CI gates green; safe secret identity validation is now reachable through the existing GitHub Release workflow without invoking builds or publication.
REMAINING: publish this correction, dispatch `release.yml` on the release branch with `secrets_only=true`, inspect the exact result, then proceed to version-last only if all four identities are valid.
BLOCKERS: none before GitHub runtime validation.
NEXT: publish the follow-up commit and launch the guarded manual preflight from authenticated GitHub Actions.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 82%

### RUNTIME RESULT: guarded preflight identifies missing update signing key

Published dispatchable-preflight commit `248fc58260d84907acfa64f34fc22660bc50362b` and manually launched Release run `35914518593` on the exact release branch with `secrets_only=true`. The safety guard worked: `core-gates`, Windows, Android and publish were all skipped. Only `secret-readiness` ran and failed before decoding any key with the exact diagnostic `AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64 is missing.` No build, artifact, tag or release was produced.

The first implementation stopped at the first missing value, so one bounded follow-up changes presence validation to report every missing secret name in the same run while still exposing no values. Identity parsing remains reachable only when all four values exist.

PROGRESS_COMPLETE: 82%
PROGRESS_REMAINING: 18%
DONE: authenticated GitHub runtime proved the guarded preflight path and absence of the update private-key secret; heavy jobs were correctly skipped.
REMAINING: publish/rerun the aggregate-name check once; provision every reported missing owner secret, obtain green pinned-identity evidence, then version-last and signed RC.
BLOCKERS: at least `AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64` is absent from repository secrets.
NEXT: publish the aggregate missing-name diagnostic, rerun only `secret-readiness`, and use its single result as the owner secret provisioning checklist.
ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: 82%
