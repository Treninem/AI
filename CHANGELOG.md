# AuroraFox Changelog

## V1.2.0.0 — 2026-08-20

- Replaced the single-mutation self-improvement path with an automatic evolutionary tournament that creates 3–10 distinct mutation candidates for the same goal.
- Each mutation is generated with a different strategy, receives its own isolated workspace copy, and must pass Godot 4.7.1 verification before it can enter the competition.
- The tournament requires at least three independently verified survivors; otherwise AuroraFox rejects the evolution cycle and applies nothing.
- Verified candidates are scored by deterministic quality signals plus a zero-temperature comparative judge; the strongest candidate wins, then is tested again from a fresh sandbox immediately before staging.
- The winning mutation is activated automatically through RuntimeExtensionManager without a user confirmation step, with SHA-256 integrity checks and persistent activation metadata.
- Autonomous research now writes sourced findings into shared long-term knowledge instead of only episodic memory/logs.
- AuroraFox now starts its first autonomous learning/evolution cycle shortly after bootstrap instead of waiting for the first long timer interval.
- Default evolution cadence changed to a 5-minute observation cycle, 5-minute research cooldown and 15-minute mutation cooldown; default competition population is five and can adapt up to ten after repeated failures.
- Stable signed releases are checked hourly by default, downloaded automatically and applied automatically after signature and SHA-256 verification. Android opens the platform package installer automatically where Android requires OS-level installation permission.
- Added regression contracts and Godot smoke tests that reject builds where the 3–10 tournament, startup evolution, independent testing, winner retest, automatic activation or automatic update path disappears.
- Fixed Android release-emulator validation so the exact APK contains both production arm64-v8a and CI x86_64 ABIs instead of trying to install an arm64-only package on an x86_64 emulator.
- Bumped AuroraFox to `V1.2.0.0` and Android `versionCode` to `100004`.

## V1.1.1.2 — 2026-08-19

- Re-enabled Android as an actively validated release target instead of leaving only the mobile foundation in the repository.
- Fixed the broken Android APK artifact workflow: `-AllowUnsignedRelease` is now implemented by the build script and the signed export preset is restored after CI export.
- Removed the stale hard-coded `V1.0.0.0` Android artifact name; APK artifacts now derive the canonical four-part AuroraFox version.
- Added Android release-contract checks for package id, versionName/versionCode, SDK levels, arm64, permissions, updater manifest, native plugin and routing invariants.
- Added APK signature, package metadata and SHA-256 validation.
- Added an Android 35 emulator smoke that installs the generated APK, launches `com.aurorafox.ai`, verifies the running process/version and rejects launch-time fatal crashes.
- Fixed Android AI routing so a missing native runtime never falls through to desktop Ollama on `127.0.0.1:11434`.
- Removed misleading first-run text that claimed the whole AuroraFox application was ready merely because a GGUF model finished installing.
- Bumped Android `versionCode` to `100003` for the V1.1.1.2 update path.

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
