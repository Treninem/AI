# AuroraFox Core migration

## Goal
AuroraFox must remain functional without mandatory Ollama or another third-party AI client. Existing memory, agents, voice, computer tools, Work, sandbox, Android, evolution, updates and server synchronization remain intact.

The operating rule is stronger than simply “Ollama is optional”: enabling an Ollama compatibility switch must never make AuroraFox dependent on Ollama. If the adapter is missing, offline, incompatible or temporarily unreachable, AuroraFox continues through its own Core and whatever local resources are available.

## Implemented — local inference and provider independence
- `AuroraCoreRuntime` is the local-first inference boundary. Ollama is a compatibility adapter only and is disabled by default.
- Runtime order is: preferred AuroraFox GGUF -> other locally available GGUF files -> optional Ollama compatibility adapter.
- Failure of the preferred GGUF can recover through another local `.gguf` under `user://models` before any external adapter is attempted.
- Ollama uses a bounded timeout plus a circuit breaker. Once an adapter failure is observed, repeated user work does not keep waiting for the same dead endpoint.
- Ollama errors do not replace the local Core result and are not used to decide whether AuroraFox itself is operational.
- `AIClient.is_available()` means AuroraFox Core availability; optional provider availability has a separate compatibility check.
- Android keeps its packaged native runtime/GGUF path through Core and never routes local Android chat through Ollama.
- Windows uses `DesktopLocalRuntime` and the AuroraFox Core Engine based on packaged/verified `llama-server` support.
- Windows Core Engine installation resolves a llama.cpp release, verifies SHA-256, extracts transactionally and smoke-tests the executable before activation.
- Windows model setup no longer probes Ollama or blocks startup because Ollama is missing/wrong. Primary readiness is the AuroraFox local GGUF model plus Core Engine.
- Existing Ollama settings remain only for backward compatibility and optional fallback.

## Implemented — dependency-free semantic memory
- `AuroraLocalSemanticVectorizer` provides AuroraFox-owned semantic vectors without a network call, model server or external embedding runtime.
- The vectorizer uses normalized word/stem/bigram/character features and a deterministic 256-dimensional local representation.
- `MemoryStore` uses this local vector index as its semantic backend and combines semantic and lexical ranking.
- `semantic_status()` explicitly reports `provider=aurorafox_local_vector`, no endpoint, `network_required=false`, `external_runtime_required=false` and `ollama_required=false`.
- The old Ollama semantic setting is retained only as compatibility/UI state and no longer causes memory retrieval to contact Ollama.
- The local semantic memory smoke test is an obligatory Godot CI gate.

## Implemented — Core Knowledge and user-supplied learning
- `KnowledgeStore` persists user-managed Core Knowledge under `user://knowledge/`.
- Schema-free JSON import accepts arbitrary filenames/nesting and classifies records as algorithm/template/skill/example/instruction/fact/knowledge.
- JSONL/NDJSON and CSV/TSV structured datasets are supported record-by-record.
- Original structured data is retained in `structured.jsonl`; normalized searchable material is retained in `knowledge.jsonl`.
- `KnowledgeDocumentImporter` provides one ingestion boundary for JSON, JSONL, TXT, Markdown, CSV/TSV, YAML, XML, HTML, logs/configs, source code, Word-family documents, PDF, EPUB, Excel and PowerPoint.
- DOCX, ODT, RTF and EPUB now have built-in Godot extractors and therefore do not require Python, Ollama or another AI provider for knowledge ingestion.
- PDF, XLS/XLSX, ODS and PPTX use the existing local File Intelligence parser when native extraction is not available.
- Knowledge Base document extraction calls File Intelligence with `visual=false`; ordinary training ingestion therefore does not trigger the optional Ollama vision compatibility path. Vision remains a separate optional file-analysis feature.
- Rich binary documents are never interpreted as executable code or granted runtime authority.

### Persistent source registry
- `KnowledgeSourceRegistry` stores source records under `user://knowledge/sources.json`.
- Every file import is SHA-256 fingerprinted independently of its filename.
- A byte-identical file copied or renamed to another path is registered as an alias and does not create duplicate knowledge chunks.
- If a canonical file changes, it becomes a new revision and stale aliases are detached instead of silently following different bytes.
- If an alias changes independently, it is detached from the old fingerprint and can become its own source.
- Source records include source ID, fingerprint, format, size, revision, chunk/record counts, categories, parser metadata and timestamps.
- `KnowledgeManager` exposes revisions, aliases and registry statistics to the Knowledge Base UI.
- The UI shows revision/hash information and has an explicit forced reindex action so an unchanged file can be rebuilt after parser/index upgrades.

### Transactional import
- `KnowledgeImportTransaction` snapshots normalized index, structured index and source registry together.
- A failed parse/write/registry commit restores all three to the prior working state.
- Successful imports atomically record the new source fingerprint/revision metadata.
- Duplicate imports can be skipped before rewriting the indexes.

- `AIClient` exposes `learn_from_file`, extracted-file learning, supported formats, source management, statistics, compaction and forced reindex while keeping previous compatibility methods.
- Imported documents are untrusted knowledge data: their contents do not automatically receive system authority and uploaded code/algorithms are not automatically executed.
- Knowledge Base UI supports user-controlled imports and management instead of silently treating personal files as global training data.

## Implemented — autonomous learning
- Existing `ResearchCollector` remains the controlled research input for public internet sources.
- `AuroraLearningCurator` evaluates research provenance before promoting it into Core Knowledge.
- High-provenance sources such as arXiv receive stronger confidence; GitHub uses repository signals; Stack Overflow remains conservative; Reddit/community material receives a lower score and must cross the promotion threshold.
- Autonomous learning keeps a persistent deduplication ledger so the same research item is not learned repeatedly.
- Promoted internet material is explicitly tagged `UNTRUSTED_EXTERNAL_RESEARCH_DATA`, with source URL, source type, observation time and quality score.
- `local_documents` are intentionally rejected by the automatic internet-learning curator. Personal/local documents enter knowledge only through the explicit user-controlled Knowledge Base flow.
- Autonomous learning can be disabled independently, or stopped together with all autonomous development using the master switch.

## Implemented — autonomous self-improvement
AuroraFox has two controlled improvement paths.

### Hot runtime improvement
- Existing `SelfImprover` creates 3–10 isolated mutations, verifies them and retests the tournament winner.
- Passed runtime improvements are handled through `RuntimeExtensionManager`, SHA-256 metadata and constrained activation/rollback rules.

### Verified Core candidate pipeline
- `CoreImprovementPipeline` can generate a complete replacement for one explicitly allowlisted intelligence file.
- Current autonomous Core allowlist is intentionally narrow:
  - `scripts/cognition_layer.gd`
  - `scripts/agent_core.gd`
  - `scripts/memory_store.gd`
  - `agent/goals.gd`
- Updater, signatures, API/security surfaces, model/runtime installers, sandbox/permission bridges, GitHub workflows, `project.godot`, the extension verifier and the Core improvement pipeline itself are outside the model-writable surface.
- A candidate must preserve basic source contracts (`class_name`, base class where present), remain bounded in size and contain no unfinished TODO/FIXME/placeholder markers.
- A candidate is written only into an isolated workspace first.
- AuroraFox imports a full project copy and runs the project’s Godot 4.7.1 verification before promotion.
- The candidate is compared against the real project and stored with base/candidate SHA-256 plus verification metadata.
- Core-candidate hashing uses Godot 4.7.1 `HashingContext/HASH_SHA256`, the same supported primitive family used by the updater.
- In Godot editor/dev checkout only, an already-verified candidate can be applied through `project_apply_file`, which creates a backup and verifies the written SHA. The project is re-indexed afterward.
- A packaged/signed AuroraFox does **not** rewrite its installed protected executable/runtime in place. Verified Core candidates are staged for the signed release/update path instead.
- A signed official update always takes priority over autonomous source evolution; `UpdateAutonomyGuard` pauses mutation/core-candidate work while an update is being selected/downloaded/applied, then resumes the previous autonomy state.

## Implemented — user control over autonomy
`AutonomySettingsManager` persists controls under `user://autonomy_settings.json`.

The Settings UI exposes:
- master autonomous learning/development switch;
- autonomous Core Knowledge learning;
- autonomous goal/research cycles;
- automatic activation of verified hot runtime mutations;
- generation of verified Core rewrite candidates;
- dev/editor-only automatic application of a verified candidate with backup.

Turning the master switch off stops autonomous learning/research cycles, hot mutations and Core candidate generation without deleting the user’s model, knowledge, memory or last working version.

## Implemented — automatic updates
- Stable updater defaults remain automatic: check, download and apply are independently configurable.
- `update.json` is signed using the AuroraFox release signing key and verified with the pinned public key in the application.
- Platform assets are separately verified by SHA-256 before installation.
- Windows updater uses a helper, health marker and rollback to the previous version if the new application fails its startup health check.
- Android uses the platform package installer and does not bypass Android installation permission/confirmation requirements.
- Background check/download/apply transport failures are logged and returned internally without emitting a user-blocking update error; explicit manual checks retain visible diagnostics.
- Network/update-server failure therefore never prevents the current verified local AuroraFox version from operating.
- Release and Android artifact CI explicitly use supported Android SDK bootstrap packages; the obsolete SDK `tools` package is no longer requested.

## Routing principles
Imported material is **Core Knowledge**, not personal conversational memory. Semantic metadata decides where/how it is retrieved. Explicit validation is required before a learned algorithm/template can become executable behavior.

Internet research is untrusted data with provenance. A website, repository, document or JSON record does not gain system/runtime authority merely by being learned.

Personal/local documents are not silently converted into shared autonomous training material.

## Current architecture
`User files -> fingerprint/source registry -> KnowledgeDocumentImporter or local File Intelligence -> classification -> transactional structured archive + normalized Core Knowledge -> retrieval -> AIClient -> AuroraFox Core`

`Memory/knowledge retrieval -> AuroraLocalSemanticVectorizer + lexical fallback -> MemoryStore`

`Public research -> ResearchCollector -> LearningCurator -> quality/provenance + dedupe -> untrusted Core Knowledge`

`AuroraFox Core -> preferred local GGUF -> alternate local GGUF -> optional circuit-broken Ollama compatibility adapter`

`Autonomous goal -> research/knowledge -> 3–10 sandbox mutations -> verification -> hot extension OR verified Core candidate`

`Verified Core candidate -> dev/editor backup+apply OR signed release candidate -> signed updater -> SHA/health/rollback`

## CI / regression gates
The current `AuroraFox Core / Voice CI` head has passed all four jobs after the source-registry/local-semantic changes:
- Godot 4.7.1 project import and script parse;
- core/voice/chat/autonomy/self-improver/runtime-extension/updater smoke tests;
- fingerprinted knowledge source registry and built-in DOCX/EPUB/RTF extraction smoke test;
- dependency-free local semantic memory smoke test;
- Python voice/autonomous evolution contracts;
- real File Intelligence document/archive/project-index tests;
- Windows bootstrap parsing, managed runtime bootstrap, version synchronization and transactional updater integration.

Additional gates cover:
- Core Engine verified installation;
- no mandatory Ollama bootstrap;
- arbitrary JSON knowledge import/re-import/retrieval;
- Android Core routing through the embedded runtime;
- learning provenance/deduplication/untrusted-data boundary;
- autonomy master-stop and per-feature switches;
- protected Core rewrite allowlist.

Core E2E cancels stale runs and places bounded timeouts around expensive stages so an unavailable compatibility service cannot consume an entire runner window.

## Remaining engineering work
1. Continue hardening packaged Windows/Android local inference and benchmark model fallback behavior on real devices.
2. Add richer evidence/benchmarks for Core candidate promotion so improvements are accepted only when they outperform the current version on defined tasks, not merely because they compile.
3. Add signed server-side promotion tooling that can take a verified Core candidate through normal CI/release signing without placing signing authority inside the client.
4. Expand recovery tests: corrupt preferred GGUF -> alternate local GGUF; interrupted update -> current version continues; failed Core candidate -> no production mutation.
5. Continue Windows/Android release regression runs across memory/tools/Work/voice/update/rollback.
6. Expand built-in document extraction where platform-native parsing can replace optional helper runtimes without sacrificing fidelity.

## Compatibility and safety rule
Do not remove existing AuroraFox features while completing this migration. Provider-specific code stays behind adapters and must never become a startup requirement again.

Autonomous improvement may optimize the assistant, but it must not autonomously remove the user’s master stop, rollback path, signed-update boundary, permission boundary, security validation or protected-file denylist.
