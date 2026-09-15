# AuroraFox Core migration

## Goal
AuroraFox must remain functional without mandatory Ollama or another third-party AI client. Existing memory, agents, voice, computer tools, Work, sandbox, Android, evolution, updates and server synchronization remain intact.

The operating rule is now stronger than simply “Ollama is optional”: enabling an Ollama compatibility switch must never make AuroraFox dependent on Ollama. If the adapter is missing, offline, incompatible or temporarily unreachable, AuroraFox continues through its own Core and whatever local resources are available.

## Implemented — local inference and provider independence
- `AuroraCoreRuntime` is the local-first inference boundary. Ollama is a compatibility adapter only and is disabled by default.
- Runtime order is: preferred AuroraFox GGUF -> other locally available GGUF files -> optional Ollama compatibility adapter.
- Failure of the preferred GGUF can recover through another local `.gguf` under `user://models` before any external adapter is attempted.
- Ollama uses a bounded timeout plus an exponential circuit breaker. Once an adapter failure is observed, repeated user work does not keep waiting for the same dead endpoint.
- Ollama errors do not replace the local Core result and are not used to decide whether AuroraFox itself is operational.
- `AIClient.is_available()` means AuroraFox Core availability; optional provider availability has a separate compatibility check.
- Android keeps its packaged native runtime/GGUF path through Core and never routes local Android chat through Ollama.
- Windows uses `DesktopLocalRuntime` and the AuroraFox Core Engine based on packaged/verified `llama-server` support.
- Windows Core Engine installation resolves a llama.cpp release, verifies SHA-256, extracts transactionally and smoke-tests the executable before activation.
- Windows model setup no longer probes Ollama or blocks startup because Ollama is missing/wrong. Primary readiness is the AuroraFox local GGUF model plus Core Engine.
- Existing Ollama settings remain only for backward compatibility and optional fallback.

## Implemented — Core Knowledge and user-supplied learning
- `KnowledgeStore` persists user-managed Core Knowledge under `user://knowledge/`.
- Schema-free JSON import accepts arbitrary filenames/nesting and classifies records as algorithm/template/skill/example/instruction/fact/knowledge.
- JSONL/NDJSON and CSV/TSV structured datasets are supported record-by-record.
- Original structured data is retained in `structured.jsonl`; normalized searchable material is retained in `knowledge.jsonl`.
- `KnowledgeDocumentImporter` provides one ingestion boundary for JSON, JSONL, TXT, Markdown, CSV/TSV, YAML, XML, HTML, logs/configs, source code, Word-family documents, PDF and EPUB.
- Rich binary documents are never interpreted as raw text. Supported documents route through File Intelligence / native extraction.
- `KnowledgeManager` adds source inventory, category statistics, storage size, source deletion and duplicate compaction.
- Re-import replaces an existing source rather than multiplying stale chunks.
- `KnowledgeImportTransaction` snapshots both normalized and structured indexes before source replacement and restores the previous working index if parsing/writing fails.
- `AIClient` exposes `learn_from_file`, supported formats, source management, statistics and compaction while keeping previous compatibility methods.
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
AuroraFox now has two controlled improvement paths.

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
- In Godot editor/dev checkout only, an already-verified candidate can be applied through `project_apply_file`, which creates a backup and verifies the written SHA. The project is re-indexed afterward.
- A packaged/signed AuroraFox does **not** rewrite its installed protected executable/runtime in place. Verified Core candidates are staged for the signed release/update path instead.
- A signed official update always takes priority over autonomous source evolution; `UpdateAutonomyGuard` pauses mutation/core-candidate work while an update is being selected/downloaded/applied, then resumes the previous autonomy state.

## Implemented — user control over autonomy
`AutonomySettingsManager` persists controls under `user://autonomy_settings.json`.

The Settings UI now exposes:
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
`User files -> KnowledgeDocumentImporter/File Intelligence -> classification -> transactional structured archive + normalized Core Knowledge -> retrieval -> AIClient -> AuroraFox Core`

`Public research -> ResearchCollector -> LearningCurator -> quality/provenance + dedupe -> untrusted Core Knowledge`

`AuroraFox Core -> preferred local GGUF -> alternate local GGUF -> optional circuit-broken Ollama compatibility adapter`

`Autonomous goal -> research/knowledge -> 3–10 sandbox mutations -> verification -> hot extension OR verified Core candidate`

`Verified Core candidate -> dev/editor backup+apply OR signed release candidate -> signed updater -> SHA/health/rollback`

## CI / regression gates
Current gates cover or are being expanded to cover:
- Core Engine verified installation;
- no mandatory Ollama bootstrap;
- arbitrary JSON knowledge import/re-import/retrieval;
- local-first memory with no automatic Ollama embedding traffic;
- Android Core routing through the embedded runtime;
- autonomous evolution contracts;
- runtime-extension activation constraints;
- updater verification/rollback;
- autonomy master-stop and per-feature switches;
- learning provenance/deduplication/untrusted-data boundary;
- protected Core rewrite allowlist.

Core E2E now cancels stale runs and places bounded timeouts around expensive stages so an unavailable compatibility service cannot consume an entire runner window.

## Remaining engineering work
1. Continue hardening packaged Windows/Android local inference and benchmark model fallback behavior on real devices.
2. Add an AuroraFox-native embedding backend so semantic retrieval no longer needs any optional Ollama embedding compatibility path; lexical retrieval remains the offline baseline.
3. Add richer evidence/benchmarks for Core candidate promotion so improvements are accepted only when they outperform the current version on defined tasks, not merely because they compile.
4. Add signed server-side promotion tooling that can take a verified Core candidate through normal CI/release signing without placing signing authority inside the client.
5. Expand recovery tests: corrupt preferred GGUF -> alternate local GGUF; interrupted update -> current version continues; failed Core candidate -> no production mutation.
6. Continue Windows/Android release regression runs across memory/tools/Work/voice/update/rollback.

## Compatibility and safety rule
Do not remove existing AuroraFox features while completing this migration. Provider-specific code stays behind adapters and must never become a startup requirement again.

Autonomous improvement may optimize the assistant, but it must not autonomously remove the user’s master stop, rollback path, signed-update boundary, permission boundary, security validation or protected-file denylist.
