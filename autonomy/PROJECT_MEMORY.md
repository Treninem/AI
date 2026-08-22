# AuroraFox Project Memory

> Persistent handoff file for future chats/accounts. This records project facts, decisions, completed work and next actions. It does not contain hidden chain-of-thought or secrets.

## Current state

- Repository: `Treninem/AI`
- Default branch: `main`
- Working branch: `autonomy-foundation-2026-08`
- Current integration PR: `#25` (open, intentionally not merged until the available verification gate is green).
- Android packaging: confirmed working from GitHub Actions (`AuroraFox-V1.2.0.0-Android-Test`).
- Windows packaging: workflow exists and exports installer + portable package.
- REG.RU deployment: installer and update/backup services already exist on `main`.
- Intended production domain: `aurorafox.ru`; API host: `api.aurorafox.ru`.
- Production IP is intentionally not hard-coded: REG.RU installer accepts `AURORAFOX_PUBLIC_IP` or derives the server's public IPv4 and creates `<ip>.sslip.io` when no host is supplied.
- REG.RU production design uses a lightweight API/synchronization/data server; local inference, voice and training are intended to remain on the owner's PC because the documented server profile is only 1 vCPU / 1 GB RAM / 10 GB storage.

## Existing autonomy already present

`agent/autonomous_coordinator.gd` is instantiated by `main.tscn` and already contains the real autonomous loop: automatic startup, periodic cycles, synchronization/observation, goal selection, public/local research, 3–10 mutation candidates, independent candidate verification, tournament scoring, final winner verification and staged activation. It persists autonomy state and events.

`agent/research_collector.gd` is the existing researcher. It reads configured public sources (including GitHub, Stack Overflow, Reddit and arXiv) plus local documents and writes curated observations into the existing `MemoryStore`. Do not create a second researcher for the same role.

Existing supporting components include learning collection/synchronization, self-audit, version management, runtime extensions, semantic memory, Ollama integration and Git/Project tools.

## Critical architecture decision

Do not replace existing autonomy with a second parallel implementation. Extend and connect the existing coordinator, learning store/sync, memory, self-improvement and version manager.

Ollama remains a replaceable provider/bridge, not the permanent identity of AuroraFox.

## Server role

The server is the persistent public coordination layer. It should:

1. stay reachable through HTTPS;
2. expose API health;
3. persist learning events and pending sync;
4. retry synchronization with the owner's active runtime;
5. keep backups and update rollback;
6. never require the server to load the large local model.

The existing API already exposes `/health`, `/v1/learn`, `/v1/learning/status`, `/v1/learning/sync` and feedback/chat learning paths. Learning is private-by-default for ordinary API interactions unless the caller explicitly opts in through `metadata.share_for_learning=true`.

The server-side addition in this branch is intentionally a synchronization layer: `api/learning_daemon.py` flushes the existing learning queue to the existing AgentCore bridge, and `deploy/reg_ru/install_learning_sync.sh` installs a two-minute systemd retry timer. It does not replace the API or expose the localhost-only AgentCore bridge.

## Verification already completed

For commit `be2361e6e23d0eb618bb81d5ce38d973305f4227`, GitHub Actions reported successful runs for:

- AuroraFox API CI — Godot API smoke, Python API module validation, Windows API script parsing.
- AuroraFox Agent Sync CI — autonomous coordinator smoke, self-improvement smoke, runtime extension smoke and updater smoke.
- AuroraFox Core / Voice CI — autonomous coordinator smoke, self-improver tournament smoke, desktop UI integration, runtime extension lifecycle, updater and voice contracts, plus file-intelligence tests.
- Android APK Artifact CI — successful Android artifact build.

These are repository/CI verification results, not proof that the physical REG.RU machine is currently online. GitHub access does not provide SSH access to that machine.

## Autonomous learning target

`public research -> source curation -> memory -> self-evaluation -> gap/task -> experiment -> 3-10 isolated candidates -> tests -> tournament -> validated promotion -> version/rollback -> repeat`

Research must prefer publicly accessible sources and retain provenance. Training/model inference can run on the owner's PC; the server stores and coordinates the resulting learning state.

## Emergency controls

The owner's STOP/ROLLBACK control remains outside the autonomous agent. Autonomous code must not be able to remove or override that control.

## Current work completed in this branch

- Created autonomy foundation branch without modifying `main`.
- Added autonomy architecture specification.
- Added autonomy configuration schema.
- Added roadmap.
- Added persistent project memory and worklog for cross-chat/account handoff.
- Added server learning queue daemon and REG.RU systemd timer installer.
- Integrated the timer installation into the existing REG.RU update flow only after the existing test gate.
- Added learning synchronization regression tests.
- Added server operations/health documentation.
- Verified the existing autonomous coordinator, researcher and mutation tournament are already present; no duplicate implementations were introduced.
- Verified current CI for the integration commit is green for the available API, Agent Sync, Core/Voice and Android workflows.

## Next actions

1. Verify the physical REG.RU deployment from the server itself (requires SSH/console access; do not infer the IP from GitHub).
2. Run `/health` and confirm API, Ollama/bridge state and learning queue status.
3. Deploy the learning-sync timer and confirm it survives reboot.
4. Connect the existing autonomous coordinator's research/learning events to the persistent server queue without bypassing existing privacy controls.
5. Add durable autonomy-cycle telemetry and self-reflection records to the existing coordinator/state rather than creating a parallel agent.
6. Exercise the full loop with a small permitted public research task, confirm memory ingestion, then test an isolated mutation tournament before any promotion.
7. Only after tests pass, merge the branch into `main` and rebuild Android/Windows artifacts.
