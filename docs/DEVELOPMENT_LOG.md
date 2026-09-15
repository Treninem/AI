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

### Independent promotion boundary and completed client/VPS transport
Added an independent server/CI verifier and `.github/workflows/core-candidate-promotion.yml`. Trusted `main` and the untrusted candidate ref are checked out separately. The candidate cannot replace the verifier, tests or workflow judging it. Only one allowlisted target can become the verified promotion patch. The promotion workflow has no release-signing or Android signing credentials.

Added `api/core_candidate_queue.py` and scoped API routes. A verified client candidate can be accepted by a VPS queue only with `core.candidate.submit`; queue/list/state management requires `core.candidate.manage`. Ordinary chat/site/integration API keys do not receive either scope by default. The VPS recalculates candidate SHA-256, rechecks target/evidence/limits, stores the bundle atomically and never executes it merely because it was submitted.

Added `scripts/core_candidate_submitter.gd` as an autoload. It scans locally verified `user://core_candidates` bundles and only enables network submission when both `AURORAFOX_PROMOTION_API_URL` and `AURORAFOX_PROMOTION_API_TOKEN` are explicitly provisioned. Remote plaintext HTTP is rejected; HTTPS is required except localhost development. Candidate bytes are re-hashed before POST, credentials are not written to submission state, failed delivery leaves the original candidate intact and uses bounded exponential retry/backoff.

Reason: GitHub/release signing authority must remain outside user clients. Candidate transport and candidate release authority are separate trust levels, and a missing VPS must never delete a locally verified candidate.

Verification: Core/Voice CI commit `6d36d8d7b64b0424ab90f4decd4f9b0a6c9d3e74` passed all four jobs. Its Godot 4.7.1 job explicitly passed `core_candidate_submitter_smoke.gd` in addition to the existing Core/knowledge/update gates.

Remaining on this subtask: production deployment still needs an owner-provisioned VPS URL and a narrowly scoped device token. Those credentials must be provisioned outside source control; they are intentionally not embedded in the application. A trusted server-side worker/CI identity still performs the final queue-to-promotion-ref dispatch rather than giving GitHub credentials to the client.

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
- explicitly include the pinned public update key in both Godot exports;
- require a bridge release before any future endpoint, asset-name or trust-key migration.

`tests/update_smoke.gd` checks direct jumps from old version strings to a new four-part version. `tests/test_update_backward_compat.py` models the V1.0 manifest contract and is invoked through the signed release Core gate, so breaking an old updater contract blocks a future release before signing.

### Update trust-key packaging defect found and fixed
Current updater verifies `update.sig` using `res://update/release_public.pub`. A `.pub` file is not a normal imported Godot resource, while both export presets previously had an empty `include_filter`. This could have produced a build whose updater code existed but whose pinned trust key was absent from the packaged `res://` filesystem.

Both Windows and Android export presets now explicitly include:

`update/release_public.pub`

The backward-compatibility test asserts the include rule exists in both presets.

Reason: a signed updater without its pinned public key cannot accept any later signed update.

### Bridge release readiness tooling
Added `build/bridge_release_readiness.ps1`. It validates the V1 backward-update contract, version synchronization, V1.0 compatibility floor, Android package identity, legacy asset names, release Core-gate dependency, public-key presence/format/export inclusion and—when GitHub CLI access is available—the required update/Android signing secret names.

The script intentionally fails while the trust root or signing secrets are absent. It is a release-readiness tool, not a way to bypass missing credentials. The normal Windows CI parses the script so syntax regressions are caught without pretending an uninitialized trust root is release-ready.

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
- direct legacy-update Godot smoke, Windows transactional updater integration, promotion/release Python contracts and all existing Core/File Intelligence jobs succeeded on commit `dc4f9fc49401c9a5b0c92f5a52fde3c8f0a5e1d5`;
- client candidate transport and its credential/SHA guard passed the complete four-job Core/Voice workflow on commit `6d36d8d7b64b0424ab90f4decd4f9b0a6c9d3e74`.

The subsequent trust-key export/readiness documentation commits trigger another normal CI cycle; their latest run must be checked before calling that exact head verified.

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
- credential-gated HTTPS client candidate submission;
- personal-memory privacy boundaries.

### Next work
1. Inspect the final CI cycle after bridge-readiness tooling and repair any regression immediately.
2. Provision the production VPS promotion endpoint/device token outside source control and connect the trusted server-side worker/CI identity that materializes queued bundles into the existing promotion workflow.
3. Initialize the update RSA trust root on the owner machine, commit only the public key, configure the matching GitHub secret and then publish the first signed bridge release through the existing release workflow.
4. Perform real Windows V1.0/V1.1 -> bridge-release update testing and Android old-signed-APK -> new-signed-APK testing on actual devices once historical install artifacts/signing identity are available.
5. Continue real-device local inference, memory, Work, voice and update/rollback regression coverage.

## 2026-09-15 — Resilient API packaging and Android offline PDF knowledge import

### Provider-independent API/VPS runtime
The external API was aligned with the local-first runtime policy. Agent bridge results now preserve their real runtime identity instead of being relabelled blindly as `aurorafox-agent`, and absence of AgentCore/Ollama is not treated as fatal when AuroraFox local Core/Knowledge fallback can answer. Initial REG.RU installation now runs the same API/privacy/no-Ollama/Core-candidate/backup/deployment/network regression gates before production activation that are required for later VPS updates.

Reason: Ollama or an optional compatibility layer must never be a single point of failure for AuroraFox.

### Windows package contract
`windows-package-ci.yml` now runs for `api/**` and `core_runtime/**` changes and verifies the Core/API/update assets both in the staged package and after a real silent install. Run `34993367532` on commit `951ee5dc1fa9e48b5ae7cdb08ee0f8b449d7838f` completed successfully, including installer smoke and uninstall.

`build/build_windows.ps1` now also requires `api/local_core_client.py`, `api/runtime_bridge.py` and the optional `api/ollama_client.py` compatibility adapter in every Windows package. This puts the invariant in the build itself, so manual builds and production release builds cannot silently omit the resilient runtime even if a workflow-specific check changes later. Commit: `e016e0bafe7a175b5fbec753a0c8de28e8d1713c`.

### Android local PDF extraction for Core Knowledge
Android File Intelligence previously parsed DOCX/XLSX/PPTX/ODT/ODS locally but PDF analysis returned metadata only. Added an offline text-layer parser using `com.tom-roush:pdfbox-android:2.0.27.0` and exported the dependency through the Godot Android export plugin so it is present in the final APK, not only while compiling the plugin AAR.

The mobile PDF path is bounded: files over 128 MB are rejected for local PDF extraction, no more than 200 pages are read in one import, extracted context is capped at 160k characters, and no cloud/Ollama/external AI is involved. Image-only scanned PDFs return an empty content result plus a warning; `knowledge_base_overlay.gd` already refuses to commit empty extracted content, so a warning string cannot accidentally become learned Core Knowledge.

The Android plugin CI initially failed before Gradle because `android-actions/setup-android@v3` attempted to install the obsolete SDK `tools` package. `android-plugin-ci.yml` now requests `platform-tools` explicitly and installs the pinned Android 35/NDK/CMake toolchain itself, matching the full APK workflow. `tests/test_android_contract.py` locks the PDFBox dependency, final APK export dependency, offline metadata, `PDDocument`/`PDFTextStripper` extraction path and guards against regression to the old metadata-only `PdfRenderer` path.

Verification state at the time of this log entry:
- prior full Android artifact run `34981910973` on commit `7167213a3a5f5db125c2ff14ff8ab754180f2bab` was green and produced an installable emulator-tested Android test artifact;
- Android Plugin CI run `34994300368` for the SDK-setup/PDFBox path is currently in progress at native AAR compilation; all setup/toolchain steps have passed;
- Android APK Artifact run `34994347552` on `b174dda5bab429ccd1959bb6e09d7a7a3adec6f6` is currently in progress at the full APK build step; Android contract/toolchain/Godot setup steps have passed;
- Windows/API/Core workflows for commit `e016e0bafe7a175b5fbec753a0c8de28e8d1713c` were triggered by the stronger build-package contract and are currently in progress.

Do not rewrite these in-progress runs as verified successes until GitHub Actions actually reports `conclusion=success`.

### Remaining external release boundary
Production Android release still intentionally requires the owner-controlled persistent Android keystore. Signed updater releases still require the owner-controlled RSA private update key corresponding to the public trust key. These private credentials must remain outside source control; no code change should bypass that boundary.

## 2026-09-15 — V1.2.0.0 delivery verification and final CI repairs

### Core bootstrap rate-limit repair
A real Windows Core Bootstrap E2E exposed a GitHub API `403` caused by anonymous release-metadata rate limiting while resolving the verified llama.cpp binary. `core_runtime/install_core.ps1` now uses `AURORAFOX_GITHUB_TOKEN` when a trusted environment provides it, retains anonymous installation for ordinary user machines, retries transient metadata requests and keeps SHA-256 verification plus executable smoke testing unchanged. The workflow passes the standard read-only `${{ github.token }}` rather than adding a release secret.

Verification: run `35004268677` on commit `ae05e50cb78022e918f248cfa5b5f08d79d070ea` completed successfully. It installed a verified llama.cpp Core Engine, confirmed Ollama is not required, imported the Godot project, passed Core/Knowledge, local-first memory and autonomy/self-evolution safety contracts.

### Local semantic-memory contract repair
The implementation had already migrated from the old lexical/legacy semantic marker to `aurorafox_local_vector`, but one old smoke test still expected `retrieval=semantic` and provider `local_lexical`. The test was corrected to validate the actual current architecture rather than an obsolete provider name: local-vector ranking, `aurorafox-local-vector-v1`, 256 dimensions, no network/external runtime/Ollama requirement, legacy compatibility disabled by default and an explicit lexical fallback when vectors are absent.

Verification: `AuroraFox Semantic Memory CI` and `AuroraFox Core / Voice CI` are successful on commit `ae05e50cb78022e918f248cfa5b5f08d79d070ea`; Agent Sync also passes its coordinator/self-improvement/runtime-extension/update smoke jobs on the same head.

### Android PDF and installable APK verified
Android Plugin CI run `34994300368` completed successfully after the SDK setup repair, proving the PDFBox-backed AuroraFoxRuntime AAR builds. Full Android APK Artifact run `34994347552` on product commit `b174dda5bab429ccd1959bb6e09d7a7a3adec6f6` completed successfully, including Godot export, test signing, APK validation, install and launch on an Android 35 emulator.

Delivered installable Android test build metadata:
- package: `com.aurorafox.ai`;
- version: `1.2.0.0` / versionCode `100004`;
- min SDK: `26`;
- target SDK: `35`;
- APK SHA-256: `02d78db3f4132fd9acf84bc0b0a6e893368557ea0d3b64b2c23639b76cf3085b`.

Later commits through `ae05e50cb78022e918f248cfa5b5f08d79d070ea` changed Windows Core bootstrap/CI/tests only and did not change Android product code. A repeated exact-head Android artifact run is therefore a redundant binary regression check, not a missing Android feature.

### Windows V1.2.0.0 delivery artifacts
Windows Package CI run `34995614726` on commit `1b2cf17b1e43f06d619d9537338cb1eef08a6b23` completed successfully after the Core installer authentication repair. Product code after this commit was unchanged by the subsequent workflow/test-only commits.

The verified Windows artifact contains:
- `AuroraFox-V1.2.0.0-Setup-Windows.exe` — SHA-256 `c5b7b12d047efd52363a467c0f59f8ecb7fc59989013842ff426f52e01afd74c`;
- `AuroraFox-V1.2.0.0-Windows-Portable.zip` — SHA-256 `9f3c47b9d4086c846e70a074c02bede37309a320e3af1fcd40802fc7268ac5cc`.

The Windows CI did a real silent install, verified packaged runtime/API/Core/update assets, launched the installed AuroraFox executable and then uninstalled it successfully.

### What is product-ready vs owner-signing-ready
The installable Windows program and Android test-signed program are built and verified. The application-side update code, legacy V1.0 direct-update compatibility, rollback and manifest contracts are implemented and tested.

A **production automatic-update channel is intentionally not published yet** because two owner-controlled signing identities do not exist in the repository/environment:
1. `update/release_public.pub` is still absent, so the permanent updater RSA trust root has not been initialized and the matching `AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64` cannot yet be configured;
2. the permanent Android release keystore (`AURORA_ANDROID_KEYSTORE_BASE64`, user and password secrets) has not been provisioned, so the delivered Android APK is CI test-signed rather than the permanent production identity.

GitHub Releases are still empty. This is an external signing/provisioning boundary, not an unfinished application feature. Do not publish a temporary-key “production” release: doing so would break Android update continuity and/or the updater trust chain. The next owner action is to initialize and preserve those signing identities once, then run the existing `AuroraFox Release` workflow to produce the first signed bridge release and update manifest.
