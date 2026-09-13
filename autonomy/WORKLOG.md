# AuroraFox Autonomy Work Log

## 2026-09-13 — implementation following PR review

- Rechecked PR head 54cc9b2 and main 9611864 before editing.
- Recovered owner's full distributed-system and visual requirements. Added
  OWNER_REQUIREMENTS.md, including latest autonomous research/full-core arena,
  provider independence and owner-only STOP/rollback requirements.
- Preserved existing Android, Windows, Godot runtime and image assets.
- Added portable process locking and durable writes to existing JSONL queue;
  protected unsent records from retention and corrected pending/attempt counts.
- Fixed installer executable-bit dependency, fresh-install integration, deployment
  test gate, rollback of systemd units and installed updater refresh.
- Added key-isolated HTTPS pending/ACK endpoints and owner-PC pull client with
  persistent receipts; documented remaining at-least-once crash boundary.
- Added multiprocess, retention, corruption, failed-replace, daemon, scope,
  lost-ACK and real TLS API tests. Final execution results belong to the handoff.
- Local verification: `python -m pytest -q tests` — 68 passed; API compileall,
  bash syntax validation and git diff whitespace validation passed. First TLS
  run exposed a test-server cleanup timeout; bounded shutdown/cleanup corrected
  it and the full suite was repeated. GitHub/native-platform results are separate.
- Flush now checkpoints each successful delivery and observes a timer budget,
  so a long queue does not lose all batch progress at the systemd timeout.
- Original approved fox/background pixels not recovered: prior conversation notes
  are not usable image assets. Full visual acceptance is not complete.
- No claim of production deployment, complete account synchronization, full-core
  evolution or a protected external STOP implementation.

## 2026-08-22

### Completed

- Inspected the repository structure before changing production code.
- Confirmed that Android packaging already works.
- Confirmed a Windows packaging workflow already exists.
- Confirmed REG.RU deployment scripts already exist.
- Confirmed intended production hosts are `aurorafox.ru` / `api.aurorafox.ru`; the actual IPv4 is supplied/derived at deployment time rather than committed.
- Inspected `agent/autonomous_coordinator.gd` and found a substantial existing autonomous cycle rather than a blank project.
- Confirmed the existing coordinator is instantiated by `main.tscn` and already supports automatic startup, periodic operation, synchronization/observation, goal selection, public/local research, 3–10 mutation candidates, independent candidate verification, tournament scoring, final winner verification, staged activation and persistent cycle state.
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
- Updated the persistent project memory with the actual CI evidence and the remaining physical-server verification requirement.

### Verification observed

For integration commit `be2361e6e23d0eb618bb81d5ce38d973305f4227`, GitHub Actions completed successfully for the available workflows:

- AuroraFox API CI: `godot-api`, `python-api`, `windows-api` all passed.
- AuroraFox Agent Sync CI: `godot-sync` passed, including autonomous coordinator, self-improvement, runtime extension and updater smoke tests.
- AuroraFox Core / Voice CI: `godot-core`, `file-intelligence`, `windows-integration`, `python-voice` all passed, including autonomous coordinator and self-improver tournament smoke tests.
- AuroraFox Android APK Artifact: completed successfully.

The combined status endpoint returned no legacy status entries, so the workflow conclusions above are the authoritative CI evidence currently visible.

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
- Current visible CI for the integration commit is green for API, Agent Sync, Core/Voice and Android workflows.
- PR #25 remains unmerged until the production gate is explicitly satisfied.

### Next implementation pass

1. Verify the physical REG.RU deployment from the server itself; do not infer live health from GitHub.
2. Add authenticated server-to-PC learning synchronization without exposing the local AgentCore TCP bridge publicly.
3. Add server-visible autonomy status and cycle history using the existing coordinator state rather than a duplicate runtime.
4. Connect the existing autonomous coordinator's research/learning cycle to the persistent server queue.
5. Extend the existing self-evaluation/goals path to generate measurable knowledge-gap tasks.
6. Extend the existing SelfImprover mutation tournament so candidates remain isolated and validated before promotion.
7. Connect the existing VersionManager/RuntimeExtensionManager to persistent candidate/version records and rollback history.
8. Add the owner's external STOP/ROLLBACK control as a separate control plane and make the autonomous loop honor it.
9. Add visual/UI self-improvement on top of the existing visual/project tooling rather than creating a parallel UI agent.
10. Keep Ollama behind the existing model abstraction and progressively measure whether it can be replaced by a local AuroraFox provider.
