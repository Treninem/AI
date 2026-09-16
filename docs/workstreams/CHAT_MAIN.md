# Chat main workstream journal

## 2026-09-16 — V1.3.0.0 delivery lane

### Starting state

- Base implementation/release trigger: `a00d0b2d07cbcde0fee686ba735933a7959ec7ff`.
- Shared coordination file added by commit `f3ed9c1ccfb3b00fd2cda5f5fdde8253f563aee3`.
- Chat workstream journal added by commit `d96323353ed5e2054a2fef8348738a6ef19fd496`.
- Current release: `V1.3.0.0`.
- Android versionCode: `100005`.

### Verified CI on V1.3.0.0 baseline

- Windows Package CI `35006665055`: success.
- Android APK Artifact `35006664982`: success, including install/launch on Android 35 emulator.
- Core / Voice CI `35006665008`: success.
- Agent Sync CI `35006665083`: success.
- Evolution Progress push run `35006665037`: success.

### Verified V1.3.0.0 delivery artifacts

Baseline Windows workflow artifact `10412017819`:

- `AuroraFox-V1.3.0.0-Setup-Windows.exe`
  - SHA-256: `8dc88d5dcbed12d81daf1ce14d2149207092d97421b85c8c0e5e7d0f5fba6f15`
- `AuroraFox-V1.3.0.0-Windows-Portable.zip`
  - SHA-256: `96aac3962f5d8aa8669144b7a632b48720fc6ca33e8205d13e1645e33e275c6a`

Baseline Android workflow artifact `10412014222`:

- `AuroraFox-V1.3.0.0-Android-Test.apk`
  - SHA-256: `c02fef0e7d58eb4eeb999f7a1ec3c71074250c4993711d003c8ebd939328676c`
  - package: `com.aurorafox.ai`
  - CI/test-signed; not a production signing identity replacement.

### Historical V1.2.0.0 updater defect

Historical version-bump commit: `976ffc175e3d3191af67a85c87a9ac789339e3ef`.

Facts verified from that historical source:

- V1.2 requests `releases/latest/download/update.json`.
- V1.2 requests `update.sig` and requires `res://update/release_public.pub`.
- `update/release_public.pub` did not exist in the V1.2 commit.
- Repository GitHub Releases were empty when the defect was diagnosed, so V1.2 received 404 and reported no published update.
- Historical Android test APK workflow generated an ephemeral keystore per CI run. Such test APKs do not have a reusable signing identity and cannot be upgraded in place by a differently signed APK.

Therefore legacy manifest readability is NOT treated as proof of a working legacy trust chain.

### Implemented V1.2 -> V1.3 repair

Commits in the repair series:

- `3d81626ac6398ce20738f589b3db129d3d7d8a02` — historical V1.2 Inno fixture with the real AuroraFox AppId.
- `baf0a088182ed00a198359bfccaa196aba3e03f3` — current installer performs in-place repair bookkeeping and does not touch Godot user data.
- `ee8c0e1da3c2901271727259a685d7e04e817173` — real Windows V1.2->V1.3 bridge smoke.
- `fadfce67714bba8f857f3b0bb2cfcff31fc7a603` — Windows CI publishes an explicitly named repair installer.
- `92b00a80b9fdfc470f289c0eed580dfe37409958` — manifest compatibility corrected: repair through V1.2, signed floor V1.3.
- `5aa58d091ef42e582ee7144569ebc863126fa541` — compatibility regression contract corrected.
- `94bf124799a2e3059dbdd1953d47abb748dda43f` — updater documentation corrected.
- `36149980044c4483ae1f30ac2427586edc2f127f` — readiness tool corrected to the repair boundary.
- `de17e8d7ba38ba8b944dfed1fb8785b176e957db` — V1.3 updater reports `repair_required` if a newer manifest exists but the local trust root is missing; it never trusts/downloads unsigned asset metadata.
- `fc251d226b4332203664e46dcb50ade53482092c` — Godot update smoke enforces the new contract.
- `8bcd5d51ed828502a9b77e41e5019c536dd7fa71` — signed-release/Core promotion tests aligned with the V1.2 repair boundary.

Verified Windows bridge CI:

- Windows Package CI run `35052987623`: **success**.
- Job `package-windows` / step `Verify V1.2 to V1.3 in-place bridge`: **success**.
- The test installs a V1.2 fixture using the historical AppId, creates a sentinel in `%APPDATA%/Godot/app_userdata/AuroraFox`, installs V1.3 on top, verifies the sentinel is unchanged, verifies `bridge_repair.txt` records `previous=1.2.0.0` and `current=1.3.0.0`, launches the upgraded application, then packages the repair artifact.

Verified repair workflow artifact `10428734786`:

- `AuroraFox-V1.2-to-V1.3.0.0-Repair-Windows.exe`
- independently calculated SHA-256: `e2c2b0aa690a0a96f636e069e8fbc5fcd6379b22c37ce886b3feed8f4d9f70e2`
- CI `SHA256SUMS.txt` reports the same SHA-256.

### Final updater/release contract verification

- Agent Sync run `35053017103`: success, including the updated `tests/update_smoke.gd`.
- Core/Voice run `35053017088` exposed one stale Python test reference only; no product/Godot regression was present.
- Stale release-gate calls were corrected by `8bcd5d51ed828502a9b77e41e5019c536dd7fa71`.
- Core/Voice rerun `35053418709`: **success**.
  - `python-voice`: success, including promotion/release/provider-independence contracts.
  - `windows-integration`: success, including transactional updater integration.
  - `godot-core`: success, including updater GDScript smoke and all Core/knowledge/autonomy gates.
  - `file-intelligence`: success.
- Agent Sync on the same `8bcd5d5...` head, run `35053418745`: success.

The V1.2 repair boundary and V1.3 signed-update floor are therefore green in both the actual Windows bridge installation test and the normal Core/release contract suite.

### V1.3+ permanent signing identity hardening

This work is reserved to chat-main until explicitly released to Work mode.

Implemented after the screenshots confirmed the real V1.2 user-facing update failure:

- `5fe8e26910eaee0ab6329618747be03409f868f0` — `build/setup_release_signing.ps1` now creates/verifies public `update/release_identity.json` containing the SHA-256 fingerprint of the updater public key and the SHA-256 fingerprint of the permanent Android signing certificate. Existing pins must match; silent key rotation is rejected.
- `59be220259938b1763ac9b1027e5800aab357c19` — production `build/build_android.ps1` now verifies the configured release keystore against the pinned Android certificate fingerprint before building, then verifies the signing certificate of the finished APK with `apksigner`. A mismatch rejects the production artifact.
- `4fac3d7372785cc6b0147872b81c166a08a24ee7` — release readiness now requires both `release_public.pub` and `release_identity.json`, checks their update-key fingerprint relationship, and verifies that Android production identity gates remain present.
- `0af867a67e990a5939d7ae933c3c45addaaf8c46` — regression contract added for the permanent V1.3+ Android signing identity. Core/Voice run `35053993479` on this head completed **success** for `python-voice`, `windows-integration`, `godot-core`, and `file-intelligence`.
- `6c1385c4012f910328ec9012f1a5204da05e5656` — regression contract additionally asserts private signing material remains under Git-ignored `build/private/` and that setup instructions commit only public identity pins.

Owner-controlled initialization still has to be done once on a trusted Windows machine because GitHub connector access cannot create repository secrets and private signing material must not be committed. The one-time command remains `build\setup_release_signing.ps1`; after it runs, only `update/release_public.pub` and `update/release_identity.json` are committed, while the private RSA key and Android keystore are backed up outside Git and stored in GitHub Actions secrets.

### Supported update boundary after repair

- Windows V1.0-V1.2: one-time V1.2->V1.3 Repair/Bridge installation is the supported recovery path for the historical trust-root defect.
- Windows V1.3+: signed automatic update path after the owner-controlled RSA trust root is initialized.
- Android: in-place update requires the same package ID **and the same signing certificate**. Historical CI/test APKs used ephemeral signing identities and cannot be repaired into a different signing lineage retroactively.
- Production Android V1.3+ must use one persistent owner-controlled signing keystore; its public certificate fingerprint is pinned by `update/release_identity.json` after initialization.
- Never weaken signature verification or publish an unsigned stable release just to make V1.2 appear updateable.

### Active chat-mode scope

1. Keep stable manifest/asset URL compatibility intact where technically possible.
2. Finish production signing/bootstrap/readiness without exposing private keys.
3. Keep release/version files synchronized.
4. Keep the V1.2 repair bridge green and ensure V1.3+ updates are genuinely automatic after trust-root initialization.
5. Prepare public production release only after owner-controlled signing identities are initialized.
6. Update `docs/DEVELOPMENT_LOG.md` only after factual verification.

### Reserved files for this lane

Until this entry is explicitly changed to RELEASED, avoid parallel edits to:

- `project.godot`
- `project/version.json`
- `export_presets.cfg`
- `update/manifest.template.json`
- `update/update_manager.gd`
- `update/README.md`
- `update/release_public.pub`
- `update/release_identity.json`
- `CHANGELOG.md`
- `build/AuroraFox.iss`
- `build/AuroraFox_V12_BridgeFixture.iss`
- `build/build_android.ps1`
- `build/bridge_release_readiness.ps1`
- `build/setup_release_signing.ps1`
- `build/create_update_signing_key.ps1`
- `tests/windows_v12_bridge_smoke.ps1`
- `tests/test_update_backward_compat.py`
- `tests/update_smoke.gd`
- `.github/workflows/release.yml`
- `.github/workflows/windows-package-ci.yml`
- `.github/workflows/android-apk-artifact.yml`

### Safe parallel work

Work mode may take another subsystem and should record its claim in `docs/workstreams/WORK_MODE.md`. Good independent targets include UI/UX, voice, Work/projects, OCR/File Intelligence and performance work outside the reserved release/update files.

### Release status

The Windows V1.2->V1.3 repair path is implemented and verified end-to-end by CI. The corrected updater/release contract is fully green. V1.3 application packages remain CI-verified. Production public signed update publication still requires the owner-controlled RSA update trust root and persistent Android signing identity; private signing material must never be committed to Git.
