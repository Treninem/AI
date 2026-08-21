# AuroraFox Project Memory

> Persistent handoff file for future chats/accounts. This records project facts, decisions, completed work and next actions. It does not contain hidden chain-of-thought or secrets.

## Current state

- Repository: `Treninem/AI`
- Default branch: `main`
- Working branch: `autonomy-foundation-2026-08`
- Android packaging: confirmed working from GitHub Actions (`AuroraFox-V1.2.0.0-Android-Test`).
- Windows packaging: workflow exists and exports installer + portable package.
- REG.RU deployment: installer and update/backup services already exist on `main`.
- Intended production domain: `aurorafox.ru`; API host: `api.aurorafox.ru`.
- Production IP is intentionally not hard-coded: REG.RU installer accepts `AURORAFOX_PUBLIC_IP` or derives the server's public IPv4 and creates `<ip>.sslip.io` when no host is supplied.
- REG.RU production design uses a lightweight API/synchronization/data server; local inference, voice and training are intended to remain on the owner's PC because the documented server profile is only 1 vCPU / 1 GB RAM / 10 GB storage.

## Existing autonomy already present

`agent/autonomous_coordinator.gd` already contains an autonomous loop: periodic cycles, self-observation, goal selection, internet/local research, 3–10 mutation candidates, tournament scoring, validation and staged activation. It persists autonomy state and events.

Existing supporting components include learning collection, research collection, self-audit, version management, runtime extensions, memory, Ollama integration and Git/Project tools.

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

## Autonomous learning target

`public research -> source curation -> memory -> self-evaluation -> gap/task -> experiment -> 3-10 isolated candidates -> tests -> tournament -> validated promotion -> version/rollback -> repeat`

Research must prefer publicly accessible sources and retain provenance. Training/model inference can run on the owner's PC; the server stores and coordinates the resulting learning state.

## Emergency controls

The owner's STOP/ROLLBACK control remains outside the autonomous agent. Autonomous code must not be able to remove or override that control.

## Current work started

- Created autonomy foundation branch.
- Added autonomy architecture specification.
- Added autonomy configuration schema.
- Added roadmap.
- Added this persistent project memory.
- Next: make REG.RU server synchronization/health loop operational without changing existing production API behavior; then connect the existing client-side autonomous coordinator to that persistent server loop.
