# AuroraFox Core migration

## Goal
AuroraFox must remain functional without mandatory Ollama or another third-party AI client. Existing memory, agents, voice, computer tools, Work, sandbox, Android, evolution, updates and server synchronization remain intact.

## Implemented
- `AuroraCoreRuntime` is the local-first inference boundary; Ollama is an optional legacy fallback only.
- Android keeps its packaged native runtime/GGUF path through Core.
- Windows model setup no longer probes Ollama or blocks startup because Ollama is missing/wrong. Primary readiness is the AuroraFox local GGUF model.
- `KnowledgeStore` persists user-managed Core Knowledge under `user://knowledge/`.
- Schema-free JSON import accepts arbitrary filenames/nesting and classifies records as algorithm/template/skill/example/instruction/fact/knowledge.
- Original structured JSON is retained in `structured.jsonl`; normalized searchable material is retained in `knowledge.jsonl`.
- `KnowledgeDocumentImporter` provides one ingestion boundary for JSON, JSONL, TXT, Markdown, CSV/TSV, YAML, XML, HTML, logs/configs, source code, Word-family documents, PDF and EPUB.
- Rich binary documents are never interpreted as raw text. DOCX/ODT/RTF/PDF/EPUB route to the packaged `AuroraFoxRuntime.extractDocumentText` interface when available.
- `KnowledgeManager` adds source inventory, category statistics, storage size, source deletion and duplicate compaction.
- `AIClient` exposes `learn_from_file`, supported formats, source management, statistics and compaction while keeping previous compatibility methods.
- Imported documents are untrusted knowledge data: their contents do not automatically receive system authority and uploaded code/algorithms are not automatically executed.

## Routing principle
Imported material is **Core Knowledge**, not personal conversational memory. Semantic metadata decides where/how it is retrieved. Explicit validated promotion will be required before a trusted algorithm/template can become an executable skill. This preserves user memory boundaries and prevents a random uploaded database from silently changing runtime policy.

## Current architecture
`File -> KnowledgeDocumentImporter -> extraction/parser -> semantic classification -> structured archive + normalized Core Knowledge -> retrieval -> AIClient -> AuroraFox Core`

`AuroraFox Core -> embedded local runtime first -> optional Ollama compatibility fallback`

## Next stages
1. Implement/package the Windows desktop native llama.cpp/GDExtension backend for `AuroraFoxRuntime.chatLocal` and `extractDocumentText`.
2. Replace the old Ollama-oriented PowerShell model installer with AuroraFox-owned GGUF model installation/import and integrity verification.
3. Add Knowledge Base UI: file/folder picker, drag/drop, import progress, source/category list, delete/reindex/compact, storage/status.
4. Add actual packaged DOCX/PDF/ODT/RTF extraction backend.
5. Add embedded semantic/vector retrieval while retaining keyword retrieval as offline fallback.
6. Add validated trusted-package promotion for algorithms/templates/skills with review, versioning and rollback; uploaded data never executes merely because it was imported.
7. Add Core runtime contract tests, no-Ollama startup tests, import/retrieval tests and compatibility tests.
8. Verify Windows/Android release pipelines and regressions across memory/tools/Work/voice/update/rollback.

## Compatibility rule
Do not remove existing AuroraFox features while completing this migration. Provider-specific code stays behind adapters and must never become a startup requirement again.
