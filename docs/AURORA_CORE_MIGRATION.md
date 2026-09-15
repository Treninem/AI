# AuroraFox Core migration

## Goal
AuroraFox must remain functional without a mandatory Ollama installation or a third-party AI client. Existing memory, agents, voice, computer tools, Work, sandbox, Android, evolution, updates and server synchronization remain intact.

## Implemented in this stage
- Added `AuroraCoreRuntime` as the local-first inference boundary.
- `AIClient` now calls AuroraFox Core instead of calling Ollama directly.
- Ollama remains an optional legacy fallback for compatibility; its absence no longer defines the architecture.
- Android continues using the packaged native runtime and local GGUF model through the Core boundary.
- Added `KnowledgeStore`, a persistent user-managed knowledge base under `user://knowledge/knowledge.jsonl`.
- Added text/file knowledge import, chunking, lightweight local retrieval and automatic relevant-context injection into chat.
- Added public AIClient methods: `configure_local_model`, `set_ollama_fallback`, `import_knowledge_text`, `import_knowledge_file`, `search_knowledge`.

## Why
The previous desktop `AIClient.chat()` always entered `_chat_ollama()`, so missing/incompatible Ollama prevented normal inference. The new boundary makes the inference provider replaceable while callers continue using the same AIClient API.

## Next stages
1. Package a desktop native llama.cpp/GDExtension backend implementing `AuroraFoxRuntime.chatLocal`, so Windows has the same embedded GGUF path as Android.
2. Change the model setup wizard and Windows installer from mandatory Ollama bootstrap to AuroraFox local model bootstrap; keep an advanced optional Ollama compatibility switch.
3. Add UI for Knowledge Base: import files/folders, list sources, delete/reindex sources, storage size and status.
4. Extend document ingestion through existing File Intelligence for PDF/DOCX and other rich formats before storing extracted text.
5. Add semantic/vector retrieval when an embedded local embedding backend is available; keep keyword retrieval as offline fallback.
6. Replace Ollama-specific CI with Core-runtime contract tests while retaining one compatibility test for the optional adapter.
7. Verify Windows/Android release pipelines, startup behavior with no Ollama installed, memory/tool/Work regressions and rollback/update flows.

## Compatibility rule
Do not remove existing AuroraFox features while completing this migration. Provider-specific code must stay behind adapters and must never become a startup requirement again.
