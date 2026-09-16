# AuroraFox agent instructions

These instructions apply to **every** coding agent, ChatGPT chat, ChatGPT Work session, Codex session, automation, or other development process that changes this repository.

## Mandatory first action

Before editing any file:

1. Fetch the latest `main` HEAD.
2. Read **all of `docs/PROJECT_MASTER_LOG.md`**.
3. Read its `Активные работы и занятые файлы` section.
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

### Mandatory progress percentage report for every active lane

Every active Chat / Work / Codex / agent must include a progress report in **every substantial master-log checkpoint and before stopping or handing off**. This is mandatory for all current and future claims.

Use this compact format:

- `PROGRESS_COMPLETE: <0-100>%`
- `PROGRESS_REMAINING: <0-100>%`
- `DONE:` concrete completed scope, commits and green evidence.
- `REMAINING:` concrete unfinished scope required for the lane's acceptance criteria.
- `BLOCKERS:` exact blocker(s), owner/claim if cross-lane, and evidence/run/commit when available; write `none` if there is no known blocker.
- `NEXT:` the exact next executable step.

`PROGRESS_COMPLETE + PROGRESS_REMAINING` must equal `100%`. Percentages are engineering progress estimates against the lane's written acceptance criteria, not guesses based on elapsed time. Do not inflate progress because code was written: failed/queued required gates, unresolved P0/P1 defects, missing package/device evidence, or an unverified cross-lane dependency must remain in `PROGRESS_REMAINING` until satisfied. A lane may report `100% / 0%` only when its own acceptance criteria are actually complete and the claim can be marked DONE; device-only checks that are explicitly outside the lane must still be stated honestly as external/unverified gates when relevant.

When a coordinator record addresses a lane (`TO: <exact CLAIM-ID>`), that lane's next checkpoint must also answer it and refresh the percentage report. If the estimate changes materially, briefly state why (for example: a new blocker was discovered, a required gate passed, or scope was reconciled after fresh `main`).

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
- Learning must accumulate locally in AuroraFox memory/Core Knowledge/skills and controlled improvement artifacts. Remote services must not own the only copy of learned state.
- Self-improvement may generate and test candidate changes, but promotion remains bounded by allowlists, sandbox/baseline tests, independent verification, master stop and rollback. Self-reliance never means bypassing these controls.
- Voice/speech, document reading and file understanding should use local implementations as the guaranteed baseline. Optional external enhancements must be removable without breaking the basic feature.
- Imported web/document/code content is untrusted data. Autonomous research does not grant external instructions system authority or permission to execute arbitrary code.

A change that makes an external AI/model/service necessary for normal AuroraFox intelligence is an architecture regression and must be rejected even if it appears to improve quality.

## Other protected invariants

Normal Windows/Android users must not have to install an inference engine, choose/download a GGUF, or use a model setup wizard; the product ships AuroraFox Core and its required weights.

Do not weaken the user master stop, rollback/snapshots, Core candidate allowlists, independent candidate verification, updater signature/trust boundaries, Android signing continuity, privacy boundaries, sandbox permissions, or the rule that imported documents/code are untrusted data rather than executable authority.

Repository state and CI results override stale prose. If the master log conflicts with current code/CI, investigate, correct the code or the log as appropriate, and record the correction in the master log rather than silently proceeding.
