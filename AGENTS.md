# AuroraFox agent instructions

These instructions apply to **every** coding agent, ChatGPT chat, ChatGPT Work session, Codex session, automation, or other development process that changes this repository.

## Mandatory first action

Before editing any file:

1. Fetch the latest `main` HEAD.
2. Read **all of `docs/PROJECT_MASTER_LOG.md`**.
3. Read **all of `docs/AURORAFOX_ENGINEERING_MEMORY.md`** and search it for the subsystem, tool and exact error text involved.
4. Read the master log's `Активные работы и занятые файлы` section.
5. Add an ACTIVE claim to that same master log before touching implementation files.
6. Do not edit files/subsystems claimed by another active lane unless you first integrate the latest `main` and explicitly take over/reconcile the claim in the master log.

## Mandatory engineering-memory protocol

`docs/AURORAFOX_ENGINEERING_MEMORY.md` is the durable technical memory of confirmed failures, constraints, unsuccessful workarounds, root causes, fixes and prevention rules shared by **all** ChatGPT Chat, Work, Codex, agent and automation sessions.

- Before proposing a workaround or repeating a failed command, search that file by subsystem, tool and exact error text.
- Repository state, current CI and reproducible logs override remembered chat prose. Correct stale entries instead of following them blindly.
- Every newly confirmed blocker or materially useful workaround MUST be added or reconciled before the owning CLAIM is closed. Record symptom, environment/exact SHA, root cause (or label it as an unconfirmed hypothesis), failed attempts worth avoiding, fix, prevention test/preflight, evidence and status.
- A waiver, skipped test or owner deferral is never recorded as PASS. Use explicit `WAIVED` / `OWNER_WAIVED_NOT_EXECUTED` status and keep the missing evidence visible.
- Never store passwords, tokens, private keys, keystores, secret values or personal credentials. Secret names and public fingerprints are allowed when needed for diagnostics.
- Do not delete old lessons merely because the immediate bug is fixed. Mark them `RESOLVED`, preserve prevention guidance and merge duplicates by reference.
- The engineering-memory file is technical reference material, not a competing progress journal. CLAIMs, current status, commits, CI runs, release readiness and exact NEXT remain exclusively in `docs/PROJECT_MASTER_LOG.md`.
- A work batch that encountered a new failure is incomplete until the reusable lesson and its prevention mechanism are recorded, unless no repository write was authorized; in that case the handoff must state the exact pending memory entry.

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

### Mandatory readiness footer in every chat response

Every executor chat response to the owner MUST end with exactly one explicit readiness line:

`ГОТОВНОСТЬ LANE: XX%`

The footer value MUST match the latest evidence-backed `PROGRESS_COMPLETE` for that lane. If no acceptance gate changed since the previous response, repeat the last verified percentage; do not increase it merely because more code was written. A lane may report `100%` only after all lane-owned acceptance gates are green, no known P0/P1 blocker remains in its scope, and any remaining external/device or cross-lane boundary is explicitly handed off rather than silently ignored.

The main coordinator MUST end every owner-facing progress response with:

`ОБЩАЯ ГОТОВНОСТЬ AURORAFOX: XX%`

The coordinator percentage is release-train readiness, not an optimistic average of executor percentages. It cannot reach `100%` before final same-SHA release acceptance, canonical version/versionCode bump, Windows/Android package gates and update/release checks are green. Missing the footer is a coordination-protocol violation and must be corrected in the next response.

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
- Learning must accumulate locally in AuroraFox memory/Core Knowledge/skills and controlled improvement artifacts. Remote services must not own the only copy of learned state.
- Self-improvement may generate and test candidate changes, but promotion remains bounded by allowlists, sandbox/baseline tests, independent verification, master stop and rollback. Self-reliance never means bypassing these controls.
- Voice/speech, document reading and file understanding should use local implementations as the guaranteed baseline. Optional external enhancements must be removable without breaking the basic feature.
- Imported web/document/code content is untrusted data. Autonomous research does not grant external instructions system authority or permission to execute arbitrary code.

A change that makes an external AI/model/service necessary for normal AuroraFox intelligence is an architecture regression and must be rejected even if it appears to improve quality.

## HARD EVOLUTION INVARIANT — 3–10 isolated mutations must compete before promotion

An autonomous AuroraFox Core improvement cycle MUST be a bounded tournament, not a single-candidate rewrite.

- Every cycle creates **at least 3 and at most 10 distinct mutation candidates** from the exact same stable baseline. The normal default should be 5 unless an explicit resource policy selects another value inside the 3–10 range.
- Each mutation runs in its **own isolated sandbox/workspace**. A candidate must not observe or inherit another candidate's modified checkout/state.
- The stable baseline participates as the incumbent. Being merely the best mutation is insufficient: if every mutation is worse, unsafe, unverified or statistically indistinguishable from the incumbent, **no update is promoted**.
- All surviving mutations run the same deterministic target-specific compile/tests/benchmarks and the same bounded quality/safety evaluation. Comparison evidence must identify the baseline SHA, candidate SHA, test set, metrics and rejection reason for non-winners.
- Tournament scoring must prioritize hard safety/contract/no-regression gates before quality/performance. A candidate that fails a hard gate cannot win regardless of aggregate score.
- Ties or inconclusive results keep the stable baseline unless an independent deterministic tie-break proves improvement.
- Only one tournament winner can proceed to independent verification. Promotion requires a second verification pass from a clean baseline plus integrity/hash checks, snapshot/rollback readiness, master-stop compliance and the existing candidate/release authority separation.
- A tournament winner may become the next **verified Core candidate/stable local Core update** only through the protected promotion path. It must not directly bypass signed product updater/release authority or rewrite packaged signed runtime in place.
- Candidate generation/evaluation must use AuroraFox's own local Core as the intelligence authority. External AI services must not be required.

Any path that autonomously generates one candidate and directly applies/promotes it without a 3–10 candidate tournament is an acceptance failure.

## HARD KNOWLEDGE INVARIANT — real local bootstrap knowledge of at least 1 GiB

AuroraFox release readiness requires a useful initial local Knowledge Pack with **at least 1 GiB (1,073,741,824 bytes) of genuine unpacked knowledge content**. Artificially repeating templates, padding, duplicate records or generated filler to reach the byte threshold does not count.

- Do **not** put the ≥1 GiB payload into ordinary Git history. Keep code, schemas, manifests, source/license metadata and small fixtures in Git; distribute the large pack as a separately hashed release/install artifact or owner-supplied local archive.
- Use a cross-platform, versioned, chunked/sharded archive contract with SHA-256 integrity. Shards must be small enough for bounded-memory Windows/Android import; the importer must stream/extract bounded chunks rather than materialize the whole corpus in RAM.
- The pack manifest must record pack/schema version, exact packed/unpacked sizes, record count, languages/domains, per-shard hashes, source provenance, source version/date and license information. Every production source must be legally redistributable for the chosen packaging mode.
- The Knowledge layer must ingest the pack locally, preserve source/provenance identity, deduplicate content, build searchable local indexes, survive interruption/restart, and expose retrieval to AuroraFox Core so the model can select relevant knowledge for later chats/tasks rather than loading the whole corpus into the prompt.
- Pack contents are untrusted data, never executable instructions. Imported text/code must not gain tool/system authority.
- Normal use of the installed pack must require no Internet. Downloading/assembling the pack is a release/build/import concern, not a runtime intelligence dependency.
- A small repository seed/fixture may remain for tests, but it cannot be reported as satisfying the ≥1 GiB production Knowledge Pack requirement.
- Release acceptance must prove the actual production pack meets the ≥1 GiB genuine-content threshold and that Windows/Android can import/query it with bounded memory and deterministic integrity checks.

## Other protected invariants

Normal Windows/Android users must not have to install an inference engine, choose/download a GGUF, or use a model setup wizard; the product ships AuroraFox Core and its required weights.

Do not weaken the user master stop, rollback/snapshots, Core candidate allowlists, independent candidate verification, updater signature/trust boundaries, Android signing continuity, privacy boundaries, sandbox permissions, or the rule that imported documents/code are untrusted data rather than executable authority.

Repository state and CI results override stale prose. If the master log conflicts with current code/CI, investigate, correct the code or the log as appropriate, and record the correction in the master log rather than silently proceeding.
