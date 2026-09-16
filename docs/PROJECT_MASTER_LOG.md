# AuroraFox — PROJECT MASTER LOG

> **ЕДИНЫЙ КАНОНИЧЕСКИЙ ЖУРНАЛ ПРОЕКТА.**
>
> Этот файл обязателен для чтения и обновления всеми режимами разработки: обычный ChatGPT-чат, Work, Codex, локальные/серверные агенты и любой другой процесс, который меняет `Treninem/AI`.
>
> Других параллельных журналов разработки/координации быть не должно. Репозиторий и результаты CI являются окончательным техническим источником истины; этот файл является единым источником координации, решений, выполненного ТЗ и плана продолжения.

## 0. Обязательный протокол для Chat / Work / Codex / агентов

Перед **любой** записью в репозиторий исполнитель обязан:

1. Получить актуальный HEAD ветки `main` и не работать по старой копии.
2. Полностью прочитать этот `docs/PROJECT_MASTER_LOG.md`.
3. Прочитать его `Активные работы и занятые файлы` section.
4. Add an ACTIVE claim to that same master log before touching implementation files.
5. Do not edit files/subsystems claimed by another active lane unless you first integrate the latest `main` and explicitly take over/reconcile the claim in the master log.

## One journal only

`docs/PROJECT_MASTER_LOG.md` is the **only development/coordination journal** for AuroraFox.

Do not create separate Chat, Work, Codex, lane, progress, development, or coordination journals. Technical subsystem documentation is allowed, but project status, engineering decisions, claims, completed work, CI evidence, and the continuation plan must be recorded in the master log.

## During and after work

Work in coherent batches. After each completed batch, update `docs/PROJECT_MASTER_LOG.md` with:

- starting HEAD and produced commit(s);
- what changed;
- concise engineering rationale (problem/decision/reason, not private chain-of-thought);
- tests and GitHub Actions run IDs/results;
- artifacts/hashes when relevant;
- remaining limitations/risks;
- exact next step;
- files/subsystem released from the claim.

Every substantial progress update and every handoff/stop report MUST also include a numeric completion estimate in this exact form:

- `PROGRESS_COMPLETE: XX%`
- `PROGRESS_REMAINING: YY%`

`XX + YY` must equal `100`. Percentages must reflect the lane's acceptance criteria, not just how much code was written. Pending CI, unresolved P0/P1 defects, unverified packaging/device gates, cross-lane integration blockers, and missing evidence must remain counted in `PROGRESS_REMAINING`.

Under the percentages, report four compact sections:

- `DONE:` concrete completed items, commits, and green tests/CI evidence;
- `REMAINING:` concrete unfinished acceptance items;
- `BLOCKERS:` exact blocker owner/CLAIM plus SHA/run/test evidence, or `none`;
- `NEXT:` the exact next executable step.

When a lane reaches `PROGRESS_COMPLETE: 100%`, do not idle. Mark the claim DONE, release its owned files, fetch fresh `main`/master log, and take the declared POST-DONE/next free large package or help another active lane through independent tests, benchmarks, audit, or integration evidence without editing that lane's occupied production files.

When stopping, mark the claim DONE or clearly state what remains so the next Chat/Work/Codex session can continue directly from the repository without repeating completed work.

## HARD VERSIONING INVARIANT — test first, version last

AuroraFox uses four-part versions `MAJOR.MINOR.PATCH.BUILD`.

Every user-visible or functional change must be assigned an intended bump level in its ACTIVE claim, but **the canonical version must not be bumped before the changed block passes its relevant acceptance tests**. Versioning is the final release step, not a substitute for testing.

- `MAJOR`: incompatible architecture/product/data/API migration requiring an intentional transition.
- `MINOR`: major new capability, broad multi-subsystem improvement, or a new release/update floor.
- `PATCH`: accepted improvement/rework of an existing block such as UI, voice, memory, knowledge, updater, Core quality or Computer Agent while compatibility is preserved.
- `BUILD`: narrow bugfix/hotfix/packaging-only correction.

Required sequence for every lane:

1. Declare the intended bump in the master-log claim.
2. Implement without reusing an already shipped version for delivery.
3. Run unit/smoke/integration/package/device/release tests relevant to the changed block.
4. Accept the block only when those tests are green and no known P0/P1 defect makes the changed feature unusable or regressed.
5. Only then perform one final version bump for the accumulated release using the highest required bump level.
6. Synchronize `project/version.json`, `project.godot`, Android `versionCode`, export/installer/update metadata, CHANGELOG and release contracts.
7. Re-run version-sync plus package/update/release gates after the bump. A red post-bump gate means the new version is not ready.
8. Android `versionCode` must strictly increase for every installable Android release.
9. Never publish or hand out a functionally changed binary under the same version number as an older binary.

Do not increment the public version for every internal commit. Multiple accepted changes may be grouped into one release, but that release must have a strictly newer version than every previously distributed normal build.

## HARD PRODUCT INVARIANT — AuroraFox is self-primary and self-reliant

AuroraFox must **depend and rely on its own Core as the foundation of intelligence**. This is stronger than merely preferring a local provider.

The normal product must remain capable of its core work when Ollama, OpenAI/other AI APIs, cloud models, remote inference services, third-party AI clients, and the public Internet are all unavailable. Its own bundled model/runtime, local memory, Core Knowledge, planning/agent logic, local tools and local speech/file subsystems are the primary path.

External systems may be used only as **optional tools or information sources** when available and permitted. They must never become the authority or required cognitive engine. In particular:

- Ollama is compatibility-only, opt-in, disabled by default and never the product default model/runtime.
- External AI/model APIs may not be required for chat, planning, memory, local generation, learning, self-evaluation or self-improvement.
- Internet/websites are research/action surfaces: AuroraFox should browse/read/use them through its own agent/tooling, then reason with its own Core. Loss of Internet must degrade online tasks, not the intelligence core itself.
- Learning must accumulate locally in AuroraFox memory/Core Knowledge/skills/checkpoints. Remote services must not own the only copy of learned state.
- Self-improvement may generate and test candidate changes, but promotion remains bounded by allowlists, sandbox/baseline tests, independent verification, master stop and rollback. Self-reliance never means bypassing these controls.
- Voice/speech, document reading and file understanding should use local implementations as the guaranteed baseline. Optional external enhancements must be removable without breaking the basic feature.
- Imported web/document/code content is untrusted data. Autonomous research does not grant external instructions system authority or permission to execute arbitrary code.

A change that makes an external AI/model/service necessary for normal AuroraFox intelligence is an architecture regression and must be rejected even if it appears to improve quality.

## Other protected invariants

Normal Windows/Android users must not have to install an inference engine, choose/download a GGUF, or use a model setup wizard; the product ships AuroraFox Core and its required weights.

Do not weaken the user master stop, rollback/snapshots, Core candidate allowlists, independent candidate verification, updater signature/trust boundaries, Android signing continuity, privacy boundaries, sandbox permissions, or the rule that imported documents/code are untrusted data rather than executable authority.

Repository state and CI results override stale prose. If the master log conflicts with current code/CI, investigate, correct the code or the log as appropriate, and record the correction in the master log rather than silently proceeding.

## 38. Work / Computer / Autonomy — takeover/reconcile, 2026-09-17

### CLAIM `CHAT-2026-09-17-WORK-COMPUTER-AUTONOMY`

- Статус: **ACTIVE — TAKEOVER/RECONCILE**.
- Started from fresh `main`: `5479a05e36aa8888fdeb96bbf9b9bac397b7780f`.
- Branch: `chat-2026-09-17-work-computer-autonomy`.
- Режим: Chat.
- Предполагаемый bump после acceptance: **PATCH**; каноническую версию и Android `versionCode` этот lane не меняет, финальный bump/release остаётся за координатором.
- Наследуется из `CHAT-2026-09-16-WORK-COMPUTER-RELIABILITY` / draft PR #40: head `f4ad58377752020823900fea107914af49021349`; deterministic Work lifecycle/recovery, atomic WorkStore, safe/unsafe retry and uncertain-result handling, bounded local Computer primitives, default-OFF permission/master-stop, sandbox/idempotency/privacy contracts and Work/Computer regression tests. Exact-head evidence на старом candidate: Work Computer Reliability `35147796178` SUCCESS; Work Mode `35147796111` SUCCESS; Windows Package `35147796213` SUCCESS; Android APK `35147795977` SUCCESS; Agent Sync `35147796112` SUCCESS; Core/Voice `35147796205` SUCCESS. PR #40 целиком не переносится: он diverged от текущего main на 82 ahead / 18 behind commits и содержит чужие workflow-diffs; будут reconciled только verified owned deltas.
- Наследуется из autonomy durability PR #72: head `3434f70ba32f74462c4b9f5216cf26cd5ddb2afa`, уже merged в current `main` merge commit `5479a05e36aa8888fdeb96bbf9b9bac397b7780f`. Сохраняются crash-safe temp/backup/atomic replacement, corrupt-state recovery, legacy schema support и fail-closed autonomous boot. Exact-head evidence: Agent Sync `35150755820` SUCCESS, Core/Voice `35150755870` SUCCESS, Windows Package `35150755901` SUCCESS, Android APK `35150755919` SUCCESS; Windows artifact `10469683226` digest `sha256:965ecd3670ca26bfc2ea478c1135deeda01c13ae87c3166ca90350ca26d05eaf`, Android artifact `10469586976` digest `sha256:fa9c968aa8b54e2ad7e8770f8a6c25b60e5d8231b1d0863441fc15fb17431ca4`.
- Owned implementation scope after reconcile: `work/work_manager.gd`, `work/work_store.gd`, `computer/computer_service.py`, `computer/install_computer.ps1`, `computer/requirements.txt`, `scripts/computer_client.gd`, Work/Computer reliability tests and `.github/workflows/work-computer-reliability.yml`; `scripts/agent_core.gd`, `scripts/tool_registry.gd`, `scripts/sandbox_manager.gd`, `agent/autonomous_coordinator.gd` and its smoke are touched only when runtime evidence requires it and after rechecking fresh ownership.
- UI boundary: do **not** edit `scripts/computer_overlay.gd`, `scripts/computer_overlay_compat.gd`, `work/work_overlay.gd` or other UI-owned paths. UI contract defects are routed to `CHAT-2026-09-17-UI-VISUAL-UX` as FROM/TO/TYPE/EVIDENCE/ACTION.
- Architecture invariant: high-level user goal = AuroraFox Core / AgentCore → ToolRegistry → bounded Computer primitives. `ComputerClient.plan()` / `run()` and sidecar service must not become planners; no mandatory external AI/model for Computer.
- Acceptance includes Work lifecycle/migration/corruption/concurrency/restart, fail-closed recovery, safe-vs-unsafe retry, duplicate idempotency, destructive uncertain-result replay prevention, Computer service timeout/malformed/permission/screenshot/platform/crash failures, sandbox/path/symlink/command-injection/untrusted-authority/privacy boundaries, Windows supported Computer scope and Android Work + explicit graceful unsupported Computer contract.

PROGRESS_COMPLETE: 30%
PROGRESS_REMAINING: 70%

DONE:
- Fresh main/AGENTS/full master log read; old CLAIMs, PR #40/#72, exact heads, changed files and exact-head workflows/artifacts audited.
- PR #72 is already integrated in main and its verified durability work is preserved rather than reimplemented.
- PR #40 verified candidate evidence is accepted as inheritance input, while stale unrelated workflow diffs are explicitly excluded.

REMAINING:
- Reconcile the owned PR #40 files onto fresh main, then run same-SHA runtime/failure matrix and inspect artifacts.
- Extend missing failure-injection gates only where current candidate evidence is insufficient; close Windows/Android capability boundaries and same-SHA UI contract handoff.

BLOCKERS:
- UI high-level Computer presentation remains owned by `CHAT-2026-09-17-UI-VISUAL-UX`; this lane will not edit its overlays.
- Physical Windows/Android device-only evidence may remain an external boundary if no hardware connector is available.

NEXT:
- Port only PR #40 owned Work/Computer/safety deltas whose merge-base→main paths are unchanged, preserve merged PR #72 state, then run Work Computer Reliability + Work Mode and inspect any failing failure-injection case before additional implementation.
