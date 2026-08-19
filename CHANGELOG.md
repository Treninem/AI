# AuroraFox Changelog

## V1.1.1.1 — 2026-08-19

- Fixed Ollama fallback after HTTP 404: a stale/broken chat model is blacklisted for the retry and AuroraFox selects another installed compatible chat model instead of repeating the same failed request.
- Removed the corrupted desktop button/avatar JPG assets from the active theme until the final per-element AuroraFox PNG asset pack is imported.
- Added an opaque, high-contrast settings panel so chat content no longer bleeds through the settings window.
- Added the first persistent AuroraFox Work mode: projects, project instructions, linked files, long-running tasks, visible progress and saved result artifacts, all routed through the existing AgentCore and long-term memory.
- Added Work/Ollama/settings regression smoke tests for Godot 4.7.1.
- Kept Android build disabled for this Windows bugfix cycle while synchronizing Android versionCode/versionName for the next APK.

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