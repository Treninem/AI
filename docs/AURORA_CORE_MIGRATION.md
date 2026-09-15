# AuroraFox Core migration

## Goal
AuroraFox must remain functional without mandatory Ollama or another third-party AI client. Existing memory, agents, voice, computer tools, Work, sandbox, Android, evolution, updates and server synchronization remain intact.

The operating rule is stronger than simply “Ollama is optional”: enabling an Ollama compatibility switch must never make AuroraFox dependent on Ollama. If the adapter is missing, offline, incompatible or temporarily unreachable, AuroraFox continues through its own Core and whatever local resources are available.

## Implemented — local inference and provider independence
- `AuroraCoreRuntime` is the local-first inference boundary. Ollama is a compatibility adapter only and is disabled by default.
- Runtime order is: preferred AuroraFox GGUF -> other locally available GGUF files -> optional Ollama compatibility adapter.
- Local GGUF candidates are preflighted for minimum size and the `GGUF` header before an inference backend is invoked.
- A local model that fails at runtime is placed into its own bounded exponential retry/quarantine state. Other local GGUF models continue to be tried before Ollama.
- Model quarantine is keyed to the file identity; replacing the failed file changes its size/mtime identity and automatically re-enables it without requiring an AuroraFox restart.
- `runtime_info()` exposes local model health and the number of currently quarantined models.
- Ollama uses a separate bounded timeout/circuit breaker. A dead compatibility adapter therefore never turns a local-model failure into repeated network stalls.
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
- DOCX, ODT, RTF and EPUB have built-in Godot extractors and therefore do not require Python, Ollama or another AI provider for knowledge ingestion.
- PDF, XLS/XLSX, ODS and PPTX use the existing local File Intelligence parser when native extraction is not available.
- Knowledge Base document extraction calls File Intelligence with `visual=false`; ordinary training ingestion therefore does not trigger the optional Ollama vision compatibility path. Vision remains a separate optional file-analysis feature.
- Rich binary documents are never interpreted as executable code or granted runtime authority.

### Large knowledge bases and monolithic JSON
- Large JSONL/NDJSON, CSV/TSV and text/code sources are processed incrementally instead of being materialized as one giant in-memory array/string.
- Knowledge search, source deletion, statistics and compaction operate as streaming scans so large indexes remain manageable after import.
- Plain monolithic `.json` files at or above the large-file threshold use `AuroraJsonStreamReader`, a dependency-free cross-platform Godot byte-stream parser rather than whole-file `JSON.parse()`.
- The streaming JSON reader handles arbitrary nested arrays/objects, strings, numbers, booleans and null, reports byte offsets on malformed input and enforces explicit depth/scalar/record limits.
- `LargeJsonKnowledgeImporter` preserves record semantics by bounded aggregation of flat objects. Common DB shapes such as `{"type":"template","content":"..."}` remain one record for classification instead of being fragmented into unrelated scalar fields.
- Aggregation is bounded to 64 fields / 256 KiB per flat record and the streaming parser caps a single scalar at 16 MiB. Overall memory therefore scales with a bounded record/scalar rather than with a 100–150+ MiB source file.

### Persistent source registry
- `KnowledgeSourceRegistry` stores source records under `user://knowledge/sources.json`.
- Every file import is SHA-256 fingerprinted independently of its filename.
- A byte-identical file copied or renamed to another path is registered as an alias and does not create duplicate knowledge chunks.
- If a canonical file changes, it becomes a new revision and stale aliases are detached instead of silently following different bytes.
- If an alias changes independently, it is detached from the old fingerprint and can become its own source.
- Source records include source ID, fingerprint, format, size, revision, chunk/record counts, categories, parser metadata and timestamps.
- `KnowledgeManager` exposes revisions, aliases and registry statistics to the Knowledge Base UI.
- The UI shows revision/hash information and has an explicit forced reindex action so an unchanged file can be rebuilt after parser/index upgrades.

### Source-scoped transactional import
- `KnowledgeImportTransaction` no longer needs to duplicate the entire global knowledge index before every large re-import.
- Before replacing a source it journals only that source’s rows from `knowledge.jsonl` and `structured.jsonl`, plus the small source registry state.
- A failed parse/write/registry commit streams the partially written replacement out of the indexes, restores the previous source rows from the journal and restores the previous registry fingerprint/revision.
- Successful imports remove the journals and commit the new fingerprint/revision.
- Duplicate imports can still be skipped before rewriting the indexes.
- CI deliberately exercises a failure after a large malformed JSON has already written partial knowledge and proves that old knowledge/fingerprint return while the partial replacement disappears.

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
- A candidate must preserve `class_name`/base-class contracts and all existing public functions/signals, remain bounded in size and contain no unfinished TODO/FIXME/placeholder markers.
- `CoreCandidateBenchmark` independently rejects newly introduced process/network primitives and source growth beyond the configured 1.35× budget.
- A candidate is written only into an isolated full project workspace first.
- Before replacement, AuroraFox runs the target-specific deterministic suite on the unchanged baseline. After replacement it runs the same suite again, in addition to whole-project Godot verification.
- A candidate that merely compiles is insufficient: baseline and candidate suites must remain healthy/no-regression, and a separate comparative review must score the candidate as a real improvement above the configured threshold.
- The candidate is compared against the real project and stored with base/candidate SHA-256 plus source-contract, benchmark and comparative-review evidence.
- Core-candidate hashing uses Godot 4.7.1 `HashingContext/HASH_SHA256`, the same supported primitive family used by the updater.
- In Godot editor/dev checkout only, an already-verified candidate can be applied through `project_apply_file`, which creates a backup and verifies the written SHA. The project is re-indexed afterward.
- A packaged/signed AuroraFox does **not** rewrite its installed protected executable/runtime in place. Verified Core candidates are staged for the trusted promotion/release path instead.
- A signed official update always takes priority over autonomous source evolution; `UpdateAutonomyGuard` pauses mutation/core-candidate work while an update is being selected/downloaded/applied, then resumes the previous autonomy state.

### Independent server/CI promotion boundary
- `build/verify_core_candidate_bundle.py` independently revalidates a candidate bundle outside the client. It recalculates base/candidate SHA-256, verifies the exact target allowlist and repeats public API/signal, risky-primitive and source-growth checks rather than trusting `candidate.json` by itself.
- `.github/workflows/core-candidate-promotion.yml` checks out trusted `main` separately from an untrusted candidate ref. Candidate code therefore cannot replace the verifier/tests/workflow that judge it.
- Only `core_candidate_submission/candidate.json` plus its allowlisted target is consumed from the candidate ref.
- The candidate is applied to a clean trusted-main checkout, parsed by Godot 4.7.1, run through target-specific and protected-boundary regression gates, and required to change exactly one allowed file.
- A verified patch/report is passed to a second job. Only after the verification job succeeds can that job receive repository/PR write permission and create an isolated promotion PR.
- The promotion workflow intentionally has no updater private key or Android signing credentials. Merge/branch protection plus the ordinary signed release workflow remain the final production boundary.
- The remaining missing link is automated transport/submission from a client/VPS verified candidate into the standardized `core_candidate_submission` ref/bundle. The promotion verifier itself is already implemented.

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

## Implemented — automatic and signed updates
- Stable updater defaults remain automatic: check, download and apply are independently configurable.
- `update.json` is signed using the AuroraFox release signing key and verified with the pinned public key in the application.
- Platform assets are separately verified by SHA-256 before installation.
- Windows updater uses a helper, health marker and rollback to the previous version if the new application fails its startup health check.
- Android uses the platform package installer and does not bypass Android installation permission/confirmation requirements.
- Background check/download/apply transport failures are logged and returned internally without emitting a user-blocking update error; explicit manual checks retain visible diagnostics.
- Network/update-server failure therefore never prevents the current verified local AuroraFox version from operating.
- The real signed release workflow now has a blocking `core-gates` job before both Windows and Android jobs. Platform builds therefore cannot reach updater/Android signing if local semantic memory, GGUF recovery, knowledge registry/streaming/rollback, autonomous rewrite benchmark or promotion-contract gates fail.
- `release_verification.json` records these new gates as release evidence before the signed update manifest is created.
- The separate Core-candidate promotion workflow does not have release-signing secrets; only the standard release workflow reaches those credentials after build dependencies have passed.

## Routing principles
Imported material is **Core Knowledge**, not personal conversational memory. Semantic metadata decides where/how it is retrieved. Explicit validation is required before a learned algorithm/template can become executable behavior.

Internet research is untrusted data with provenance. A website, repository, document or JSON record does not gain system/runtime authority merely by being learned.

Personal/local documents are not silently converted into shared autonomous training material.

## Current architecture
`User files -> fingerprint/source registry -> streaming/native KnowledgeDocumentImporter or local File Intelligence -> classification -> source-scoped transactional structured archive + normalized Core Knowledge -> retrieval -> AIClient -> AuroraFox Core`

`Memory/knowledge retrieval -> AuroraLocalSemanticVectorizer + lexical fallback -> MemoryStore`

`Public research -> ResearchCollector -> LearningCurator -> quality/provenance + dedupe -> untrusted Core Knowledge`

`AuroraFox Core -> preferred local GGUF -> per-model health/quarantine -> alternate local GGUF -> optional separately circuit-broken Ollama compatibility adapter`

`Autonomous goal -> research/knowledge -> 3–10 sandbox mutations -> verification -> hot extension OR verified Core candidate`

`Verified Core candidate -> baseline/candidate benchmarks + comparative improvement -> local candidate bundle -> independent trusted-main verifier -> verified promotion patch/PR -> blocking signed-release Core gates -> platform builds -> updater signature -> SHA/health/rollback`

## CI / regression gates
Confirmed green Core/Voice CI at commit `087935a24c653b66866a80e964996fd0f6fa68c7` includes all four main jobs and the current implementation through release-gate integration. The Godot 4.7.1 job covers:
- project import/script parse;
- voice/chat/autonomy/self-improver/runtime-extension/updater;
- source registry and rich-document extraction;
- dependency-free local semantic memory;
- local GGUF quarantine/recovery;
- large streaming knowledge import/search/removal;
- monolithic arbitrary JSON streaming with semantic record aggregation;
- source-scoped rollback after a partial malformed large import;
- Core-candidate benchmark/source-contract gate.

The Python job covers autonomous evolution, independent Core candidate verifier/promotion contracts and voice contracts. File Intelligence document/archive/index tests and Windows bootstrap/version/updater integration also pass in the same workflow family.

A release-workflow dependency contract additionally guards that Windows and Android release jobs depend on `core-gates`, publish depends on both platform jobs, and release signing remains downstream of those dependencies.

## Remaining engineering work
1. Implement authenticated client/VPS transport for a locally verified Core candidate into the standardized server-side `core_candidate_submission` queue/ref without putting GitHub or release credentials in the client.
2. Continue real-device Windows/Android local inference benchmarking, especially model load failure/VRAM-RAM pressure, cold-start latency and fallback quality.
3. Consider a higher-fidelity AuroraFox-owned dense/neural embedding backend as an optional upgrade over the current dependency-free local feature-hash semantic vectorizer; the current vectorizer remains the guaranteed offline baseline.
4. Continue server synchronization/conflict/evolution integration so shared infrastructure can carry approved general improvements while personal memory remains private and per-user.
5. Expand release regressions on real Windows/Android hardware across memory/tools/Work/voice/update/rollback and interrupted-download scenarios.
6. Expand built-in document extraction where platform-native parsing can replace helper runtimes without sacrificing fidelity.

## Compatibility and safety rule
Do not remove existing AuroraFox features while completing this migration. Provider-specific code stays behind adapters and must never become a startup requirement again.

Autonomous improvement may optimize the assistant, but it must not autonomously remove the user’s master stop, rollback path, signed-update boundary, permission boundary, security validation or protected-file denylist.
