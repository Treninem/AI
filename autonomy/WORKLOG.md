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
- Confirmed `api/learning_sync.py` persists learning events and retries synchronization through the runtime bridge.
- Created branch `autonomy-foundation-2026-08` so the existing `main` branch remains untouched while the autonomy/server integration is developed.
- Added `autonomy/README.md`.
- Added `autonomy/config.schema.json`.
- Added `autonomy/ROADMAP.md`.
- Added `autonomy/PROJECT_MEMORY.md`.
- Added this `autonomy/WORKLOG.md`.
- Added `api/learning_daemon.py`: a lightweight one-shot worker that flushes queued learning events to the existing AgentCore bridge and keeps the timer successful when the PC runtime is temporarily offline.
- Added `deploy/reg_ru/install_learning_sync.sh`: installs the learning sync systemd service and a two-minute retry timer without replacing the existing API service.
- Extended `deploy/reg_ru/update.sh` so the new sync service is installed only after the candidate passes the existing compilation/test gate and remains covered by the existing rollback trap.
- Extended API CI syntax validation to include the new REG.RU installer script.
- Opened PR #25 to review/merge the additive server-learning foundation.

### Important findings

- The current REG.RU architecture deliberately keeps large-model inference, voice and model training on the owner's PC. The server is designed as a lightweight API/synchronization/persistent-data layer. The autonomous learning loop therefore spans the persistent server queue and the existing PC autonomous coordinator rather than trying to load/train a large model on the 1 GB host.
- The actual production IPv4 is deployment-time configuration and is not present as a committed value. `aurorafox.ru` and `api.aurorafox.ru` are explicitly represented in the deployment configuration.
- Live external server health is not yet proven from GitHub access alone because the connector does not provide SSH access to the REG.RU machine and deployment credentials are not committed.

### Validation status

- Repository-level static inspection completed.
- Existing API/backup/deployment tests remain the production gate in `deploy/reg_ru/update.sh`.
- New installer is included in API CI bash syntax validation.
- Full GitHub Actions result for PR #25 has not yet been observed through the available connector.

### Next implementation pass

1. Merge PR #25 only after the CI gate is confirmed green.
2. Verify the REG.RU host externally using its actual deployment endpoint/IP and `/health`.
3. Confirm the PC AgentCore bridge is reachable from the server or establish the intended authenticated sync transport if it is not local.
4. Connect the existing autonomous coordinator's research/learning cycle to the persistent server state.
5. Add explicit server-visible autonomy status and cycle history.
6. Then implement the next layer: self-evaluation gaps -> research queue -> memory -> sandbox mutation arena -> validation -> version promotion/rollback.
