# AuroraFox Autonomy Work Log

## 2026-08-22

### Completed

- Inspected the repository structure before changing production code.
- Confirmed that Android packaging already works.
- Confirmed a Windows packaging workflow already exists.
- Confirmed REG.RU deployment scripts already exist.
- Confirmed intended production hosts are `aurorafox.ru` / `api.aurorafox.ru`; the actual IPv4 is supplied/derived at deployment time rather than committed.
- Inspected `agent/autonomous_coordinator.gd` and found a substantial existing autonomous cycle rather than a blank project.
- Confirmed the existing coordinator already supports periodic operation, research, goal selection, 3–10 mutation candidates, tournament scoring, staged activation and persistent cycle state.
- Confirmed `agent/research_collector.gd` already performs public internet collection from GitHub, Stack Overflow, Reddit and arXiv and writes selected observations into MemoryStore.
- Confirmed `agent/learning_collector.py` already has a separate allowlisted public-source collector for GitHub, Stack Overflow, Reddit, arXiv, Habr, Medium, Godot docs and Ollama docs, plus local project observations.
- Confirmed `api/learning_sync.py` persists learning events and retries synchronization through the existing runtime bridge.
- Created branch `autonomy-foundation-2026-08` so the existing `main` branch remains untouched while the autonomy/server integration is developed.
- Added `autonomy/README.md`.
- Added `autonomy/config.schema.json`.
- Added `autonomy/ROADMAP.md`.
- Added `autonomy/PROJECT_MEMORY.md`.
- Added this `autonomy/WORKLOG.md`.
- Added `api/learning_daemon.py`: a lightweight one-shot worker that flushes queued learning events to the existing AgentCore bridge and keeps the timer successful when the PC runtime is temporarily offline.
- Added `deploy/reg_ru/install_learning_sync.sh`: installs the learning sync systemd service and a two-minute retry timer without replacing the existing API service.
- Extended `deploy/reg_ru/update.sh` so the new sync service is installed only after the candidate passes the existing compilation/test gate and remains covered by the existing rollback trap.
- Added `tests/test_learning_sync.py` covering private interaction filtering, successful opt-in learning, retry after bridge failure and feedback retry.
- Extended API CI to run the learning synchronization regression tests and validate the new deployment script.
- Opened PR #25 to review/merge the additive server-learning foundation.

### Important findings

- The current REG.RU architecture deliberately keeps large-model inference, voice and model training on the owner's PC. The server is designed as a lightweight API/synchronization/persistent-data layer. The autonomous learning loop therefore spans the persistent server queue and the existing PC autonomous coordinator rather than trying to load/train a large model on the 1 GB host.
- The actual production IPv4 is deployment-time configuration and is not present as a committed value. `aurorafox.ru` and `api.aurorafox.ru` are explicitly represented in the deployment configuration.
- The Godot coordinator is already the canonical autonomous loop. Do not create a second coordinator.
- The existing research collector is already the canonical internet-research component. Extend its source selection, curation and scheduling instead of creating another researcher.
- The existing learning collector is a useful offline/CLI collection path and should feed the same memory/learning pipeline rather than becoming a second memory system.
- The existing AgentCore bridge intentionally binds to `127.0.0.1:8770`; therefore a REG.RU server cannot legitimately assume that the owner's PC bridge is reachable over the public internet. The server should persist/queue state and use an authenticated sync transport rather than exposing the raw bridge port.
- Live external server health is not yet proven from GitHub access alone because the connector does not provide SSH access to the REG.RU machine and deployment credentials are not committed.

### Validation status

- Repository-level static inspection completed.
- Existing API/backup/deployment tests remain the production gate in `deploy/reg_ru/update.sh`.
- New installer is included in API CI bash syntax validation.
- New learning synchronization unit tests are included in API CI.
- Full GitHub Actions result for the current PR head must be observed before promotion to `main`.

### Next implementation pass

1. Observe the current PR CI and fix any failures before merge.
2. Add authenticated server-to-PC learning synchronization without exposing the local AgentCore TCP bridge publicly.
3. Add server-visible autonomy status and cycle history using the existing coordinator state rather than a duplicate runtime.
4. Connect the existing autonomous coordinator's research/learning cycle to the persistent server queue.
5. Extend the existing self-evaluation/goals path to generate measurable knowledge-gap tasks.
6. Extend the existing SelfImprover mutation tournament so candidates remain isolated and validated before promotion.
7. Connect the existing VersionManager/RuntimeExtensionManager to persistent candidate/version records and rollback history.
8. Add the owner's external STOP/ROLLBACK control as a separate control plane and make the autonomous loop honor it.
9. Add visual/UI self-improvement on top of the existing visual/project tooling rather than creating a parallel UI agent.
10. Keep Ollama behind the existing model abstraction and progressively measure whether it can be replaced by a local AuroraFox provider.
