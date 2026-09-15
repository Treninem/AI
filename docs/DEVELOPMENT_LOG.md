# AuroraFox development log

This file is the persistent engineering log requested for AuroraFox. It records what was changed, why the design was chosen, what was verified, what remains incomplete and which boundaries must not be weakened by later autonomous changes.

## 2026-09-15 — Local Core, large learning bases, verified evolution and backward-compatible updates

### Goal
Continue the existing AuroraFox project without restarting it, remove mandatory dependence on Ollama/third-party AI clients, preserve all existing/planned capabilities, support user-supplied learning databases/documents, make autonomous improvement measurable and reversible, and keep old installed AuroraFox versions able to update to future releases.

### Local Core and model recovery
Implemented a local-first `AuroraCoreRuntime`. Ollama remains only an optional compatibility adapter and is disabled by default. Preferred GGUF failure no longer makes Ollama mandatory: AuroraFox preflights local GGUF files, quarantines a failing model with bounded backoff, tries alternate local models and automatically re-enables a replaced model when its file identity changes.

Reason: provider availability must not define whether AuroraFox itself is operational. A broken primary GGUF should degrade to another local model rather than turn into a network dependency.

Verification: Godot CI covers local semantic memory, local GGUF quarantine/recovery and operation with Ollama disabled.

### User learning files / Core Knowledge
Expanded user-controlled learning to arbitrary filenames and multiple formats. JSON/JSONL/NDJSON, text/code/data formats and built-in rich-document extractors route extracted material into Core Knowledge rather than personal conversational memory. Imported instructions/code remain untrusted data and do not receive runtime authority merely because they were uploaded.

Large JSONL/CSV/text sources are streamed. Large monolithic `.json` files use a dependency-free Godot byte-stream parser. Flat records are aggregated within explicit limits so DB records such as `{type, content}` keep their semantic relationship without loading an entire 100–150+ MB file into memory.

Reason: knowledge import must scale with a bounded record/chunk, not the complete database size, while preserving enough structure to classify templates, algorithms, examples and facts correctly.

### Source registry and rollback
Knowledge sources are fingerprinted independently of filename. Identical renamed files become aliases instead of duplicate knowledge. Re-import uses source-scoped transaction journals rather than duplicating the entire global knowledge DB. A failed partial large import removes the incomplete replacement, restores prior rows and restores the old registry fingerprint/revision.

Reason: copying the whole knowledge DB before every re-import becomes prohibitively expensive as the local DB grows; rollback still must remain exact.

Verification: CI deliberately imports a malformed large JSON after partial writes and confirms that old data/fingerprint return and partial replacement data disappears.

### Autonomous Core rewrite quality gate
A Core candidate may change only the narrow intelligence allowlist. It must preserve public functions/signals, base/class contracts, avoid newly introduced risky process/network primitives, remain within a bounded source-growth budget and pass the same deterministic baseline/candidate Godot suite. A separate comparative review must also show measurable improvement; compilation alone is insufficient.

Reason: self-improvement must demonstrate no regression and a real advantage over the current version before it can proceed.

### Independent promotion boundary
Added an independent server/CI verifier and `.github/workflows/core-candidate-promotion.yml`. Trusted `main` and the untrusted candidate ref are checked out separately. The candidate cannot replace the verifier, tests or workflow judging it. Only one allowlisted target can become the verified promotion patch. The promotion workflow has no release-signing or Android signing credentials.

Added `api/core_candidate_queue.py` and scoped API routes. A verified client candidate can be accepted by a VPS queue only with `core.candidate.submit`; queue/list/state management requires `core.candidate.manage`. Ordinary chat/site/integration API keys do not receive either scope by default. The VPS recalculates candidate SHA-256, rechecks target/evidence/limits, stores the bundle atomically and never executes it merely because it was submitted.

Reason: GitHub/release signing authority must remain outside user clients. Candidate transport and candidate release authority are separate trust levels.

Remaining on this subtask: client-side authenticated submission/retry configuration to the VPS queue still needs to be wired to a provisioned device/server credential. Until configured, locally verified candidates remain local; no candidate should be deleted because the server is unavailable.

### Backward-compatible application updates
Repository history was checked instead of assuming compatibility. The completed **V1.0.0.0** release already contained the transactional Windows updater and the permanent manifest URL:

`https://github.com/Treninem/AI/releases/latest/download/update.json`

V1.0 understood the same legacy manifest fields retained by the current release workflow: `version`, `channel`, `mandatory`, `assets.windows.url`, `assets.windows.sha256`, `assets.android.url`, `assets.android.sha256`.

The V1.0 Windows helper verifies SHA-256, expands the full ZIP, expects `AuroraFox.exe` at archive root (or one wrapping directory), performs staging/backup, starts the replacement with a health marker and rolls back on failed startup. The current release workflow still builds `AuroraFox-Windows.zip` from `build/windows/*`, preserving that layout. Android keeps package ID `com.aurorafox.ai` and requires one persistent Android signing identity.

Decision: **V1.0.0.0 and newer are a permanent direct-update compatibility floor.** They may jump directly to the newest compatible stable release; intermediate versions are not required. Pre-V1.0 experimental builds need one manual bootstrap installation because a complete updater contract cannot be guaranteed for them.

Permanent compatibility invariants now covered by tests:
- keep `releases/latest/download/update.json`;
- keep `AuroraFox-Windows.zip` and `AuroraFox-Android.apk` asset names;
- retain original legacy manifest fields;
- keep `update.sig` additive rather than replacing `update.json`;
- preserve full-ZIP Windows replacement layout;
- preserve Android package identity/signing continuity;
- require a bridge release before any future endpoint or asset-name migration.

`tests/update_smoke.gd` now checks direct jumps from old version strings to a new four-part version. `tests/test_update_backward_compat.py` models the V1.0 manifest contract and is invoked through the signed release Core gate, so breaking an old updater contract blocks a future release before signing.

### Update trust-key packaging defect found and fixed
Current updater verifies `update.sig` using `res://update/release_public.pub`. A `.pub` file is not a normal imported Godot resource, while both export presets previously had an empty `include_filter`. This could have produced a build whose updater code existed but whose pinned trust key was absent from the packaged `res://` filesystem.

Both Windows and Android export presets now explicitly include:

`update/release_public.pub`

The backward-compatibility test asserts the include rule exists in both presets.

Reason: a signed updater without its pinned public key cannot accept any later signed update.

### Current release-signing blocker
`update/release_public.pub` does not currently exist on `main`, and GitHub Releases are currently empty. Historical signed-updater code referenced this file but repository history did not contain the actual trust key. This means the update code is ready but the trust root has never been initialized for a real release.

Do **not** solve this by committing a private key or weakening signature checks. One owner-controlled bootstrap remains required:
1. run `build/create_update_signing_key.ps1` once on a trusted owner machine;
2. commit only `update/release_public.pub`;
3. store the matching private key safely outside Git;
4. configure `AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64` in GitHub Actions secrets;
5. preserve that key for future releases, or use a planned bridge-release key rotation.

The first real signed V1.2.0.0 release can then act as the bridge: V1.0/V1.1 clients accept its legacy-compatible `update.json` + package SHA, while the installed V1.2 package contains the pinned public key and requires RSA-signed manifests thereafter.

### CI evidence
Confirmed green on the implementation path:
- API queue/scoped boundary: `AuroraFox API CI` success on commit `047027d9b0c5f3f13957732226324299483b5180`;
- Core/Voice CI success on the same API-boundary head;
- direct legacy-update Godot smoke, Windows transactional updater integration, promotion/release Python contracts and all existing Core/File Intelligence jobs succeeded on commit `dc4f9fc49401c9a5b0c92f5a52fde3c8f0a5e1d5`.

Later documentation/export-key commits trigger another normal CI cycle; do not call them verified until their runs complete.

### Protected invariants for future work
Do not allow autonomous code to remove or weaken:
- user master stop;
- rollback paths;
- Core target allowlists;
- independent candidate verification;
- release-signing boundary;
- pinned updater trust key/signature verification;
- legacy V1.0 direct-update contract without first shipping a compatible bridge release;
- API scope separation for Core candidate submission/management;
- personal-memory privacy boundaries.

### Next work
1. Wait for/inspect CI from the export-key compatibility changes and repair any regression immediately.
2. Wire client-side Core candidate submission/retry only after a proper VPS/device credential provisioning mechanism is available; do not embed a privileged token in application source.
3. Initialize the update RSA trust root on the owner machine, then publish the first signed bridge release through the existing release workflow.
4. Perform real Windows V1.0/V1.1 -> bridge-release update testing and Android old-signed-APK -> new-signed-APK testing on actual devices once historical install artifacts/signing identity are available.
5. Continue real-device local inference, memory, Work, voice and update/rollback regression coverage.
