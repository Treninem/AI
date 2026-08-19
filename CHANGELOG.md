# AuroraFox Changelog

## V1.1.0.0 — 2026-08-19

- Added external AuroraFox API Gateway for Telegram, VK, websites, applications and OpenAI-compatible clients.
- API conversations, feedback and corrected answers now feed the same long-term MemoryStore and ExperienceStore used by AgentCore.
- Added scoped API keys, conversation isolation, WebSocket, file/model/tool endpoints and durable learning replay when AgentCore is temporarily offline.
- Reused already installed system Ollama models instead of requiring hardcoded `qwen3:8b`.
- Finalized responsive Windows desktop UI with AuroraFox fox artwork, neon code background, textured buttons and non-overlapping startup/menu layout.
- Preserved the existing Android foundation without running Android builds during this release cycle.

## V1.0.0.0 — 2026-08-19

- Major migration to the autonomous evolution architecture.
- Added compatibility-aware autonomous coordinator over existing AgentCore, SelfImprover, RuntimeExtensionManager, File Intelligence, voice and updater.
- Added canonical four-part versioning `V<Major>.<Minor>.<Patch>.<Build>`.
- Added self-audit, release progress tracking, autonomous learning collection and visible evolution status.
- Kept existing sandbox and signed updater as the canonical test/apply mechanisms instead of duplicating them.