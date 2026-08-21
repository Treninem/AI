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

### Important finding

The current REG.RU architecture deliberately keeps large-model inference and training on the owner's PC. The server is designed as a lightweight API/synchronization/persistent-data layer. Therefore the correct implementation is a persistent server sync loop plus the existing PC autonomous coordinator, not trying to train a large model inside the 1 GB REG.RU host.

### Not yet completed

- Live external server health cannot be proven from repository access alone because the GitHub connector does not provide SSH access to the REG.RU machine and the repository does not expose its deployment secrets.
- The server-side periodic learning flush/reconnect service still needs to be added and installed.
- The actual REG.RU public IPv4 is not committed to the repository and must not be guessed.

### Next implementation pass

1. Add a lightweight server learning-sync worker that keeps pending learning events and retries the PC runtime bridge.
2. Add systemd service/timer integration to the REG.RU deployment without replacing the current API service.
3. Add health/status reporting for API, sync queue and runtime bridge.
4. Run repository CI for the changed Python code.
5. Update this log with commit hashes and test results.
6. Only after server synchronization is stable, connect the existing autonomous coordinator's research/learning cycle to the persistent server state.
