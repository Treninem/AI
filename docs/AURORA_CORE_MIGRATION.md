# AuroraFox Core migration

## Goal
AuroraFox must remain functional without a mandatory Ollama installation or a third-party AI client. Existing memory, agents, voice, computer tools, Work, sandbox, Android, evolution, updates and server synchronization remain intact.

## Implemented
- Added `AuroraCoreRuntime` as the local-first inference boundary.
- `AIClient` now calls AuroraFox Core instead of calling Ollama directly.
- Ollama remains an optional legacy fallback for compatibility; its absence no longer defines the architecture.
- Android continues using the packaged native runtime and local GGUF model through the Core boundary.
- Added `KnowledgeStore`, a persistent user-managed Core Knowledge base under `user://knowledge/`.
- Added text/file knowledge import, chunking, lightweight local retrieval and automatic relevant-context injection into chat.
- Added schema-free JSON database import. A `.json` file may have any filename and arbitrary nested object/array structure.
- JSON is recursively inspected and records are automatically classified as `algorithm`, `template`, `skill`, `example`, `instruction`, `fact` or general `knowledge` based on structure/content rather than filename.
- Original structured JSON records are retained in `structured.jsonl`; searchable normalized text goes to `knowledge.jsonl`. This allows later re-indexing without losing source structure.
- Related leaf objects are kept together so datasets such as question/answer pairs, templates and algorithm records do not get unnecessarily split apart.
- Added public AIClient methods: `configure_local_model`, `set_ollama_fallback`, `import_knowledge_text`, `import_knowledge_file`, `search_knowledge`.

## Routing principle
Imported material is treated as **Core Knowledge**, not blindly written into personal conversational memory. Templates, algorithms, examples and factual datasets receive semantic type metadata and are retrieved when relevant. This prevents a random training JSON from overwriting user memory or runtime configuration. In later stages, explicit trusted packages can be routed to dedicated Skills/Algorithms stores through a validated importer.

## Why
The previous desktop `AIClient.chat()` always entered the Ollama path, so missing/incompatible Ollama prevented normal inference. The new boundary makes the inference provider replaceable while callers continue using the same AIClient API.

## Next stages
1. Package a desktop native llama.cpp/GDExtension backend implementing `AuroraFoxRuntime.chatLocal`, so Windows has the same embedded GGUF path as Android.
2. Change the model setup wizard and Windows installer from mandatory Ollama bootstrap to AuroraFox local model bootstrap; keep an advanced optional Ollama compatibility switch.
3. Add UI for Knowledge Base: import JSON/files/folders, list sources and detected categories, delete/reindex sources, storage size and status.
4. Extend document ingestion through existing File Intelligence for PDF/DOCX and other rich formats before storing extracted text.
5. Add semantic/vector retrieval when an embedded local embedding backend is available; keep keyword retrieval as offline fallback.
6. Add validated promotion of trusted imported algorithms/templates into dedicated skill/runtime registries. Imported data must never execute code merely because it was uploaded.
7. Replace Ollama-specific CI with Core-runtime contract tests while retaining one compatibility test for the optional adapter.
8. Verify Windows/Android release pipelines, startup behavior with no Ollama installed, memory/tool/Work regressions and rollback/update flows.

## Compatibility rule
Do not remove existing AuroraFox features while completing this migration. Provider-specific code must stay behind adapters and must never become a startup requirement again.
