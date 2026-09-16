# AuroraFox parallel work coordination

This file is the shared coordination map for ChatGPT chat mode, Work mode and any other trusted development lane working on the same repository.

## Current baseline

- Repository: `Treninem/AI`
- Branch: `main`
- Current release line: `V1.3.0.0`
- Android versionCode: `100005`
- Godot: `4.7.1`
- Active chat delivery lane head at claim time: `bff0f4dde4f3c13d00168ac47b9c81eedca83114`.

The older `a00d0b2...` V1.3 package baseline was green, but it is no longer the target package because it still required a separately provisioned inference model. The current delivery target is a **complete bundled AuroraFox Core** on Windows and Android.

## Parallel-work protocol

1. Before any write, fetch the latest `main` head. Never assume a baseline above is still HEAD.
2. Read this file plus `docs/DEVELOPMENT_LOG.md` and the lane files in `docs/workstreams/` before changing shared architecture.
3. Each development lane must write only to its own workstream journal for frequent updates. Do not have multiple agents repeatedly rewrite this shared file.
4. Before editing an existing file, check whether another lane currently claims it. If it is claimed, choose another task or integrate the latest owner changes first.
5. After a coherent batch, commit code first, then update the lane journal with: commit SHA, files changed, tests/run IDs, decisions, remaining work and files released from the claim.
6. Do not overwrite a file from a stale copy. Re-fetch it immediately before an update if `main` changed.
7. Never weaken the user master stop, rollback, updater signature verification, Core candidate allowlists, privacy boundaries, Android signing continuity or the documented V1.2 repair/V1.3 signed-update boundary.

## Current chat-mode lane — bundled Core delivery

Owner journal: `docs/workstreams/CHAT_MAIN.md`

User-visible invariant being implemented and tested:

> Install AuroraFox, open it, type a message, receive an answer. The normal user must not install Ollama, choose/download a GGUF, install a separate inference engine, or see a model setup wizard.

Current implementation facts:

- `AuroraBundledCoreModel` selects the application-shipped Core automatically.
- Android first run silently provisions the Core asset and contains no model download/file-picker UI.
- Normal Settings hides model-management controls and describes AuroraFox Core as built into the application.
- `build/build_android.ps1` now stages and SHA-256-verifies the pinned Core weights on **every** APK build and rejects an APK too small to contain them.
- `build/build_windows.ps1` now prepares and packages both `llama-server.exe` and the pinned internal Core weights on **every** Windows build.
- Windows startup starts warming the bundled Core before the first real user message.
- Windows Package CI requires the engine and Core weights in the build and in the silently installed application.
- Android export explicitly includes `models/aurorafox-core.gguf` in the APK.

Pinned bundled-Core artifact contract for V1.3.0.0:

- bytes: `1282439264`
- SHA-256: `d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5`
- source download is a **build-time input only**; end users must not be sent to Hugging Face or asked to manage the file.

### Temporarily reserved files

Work mode must not independently modify these until the chat lane marks bundled-Core delivery VERIFIED/RELEASED:

- `scripts/ai_client.gd`
- `scripts/bundled_core_model.gd`
- `scripts/android_first_run.gd`
- `scripts/windows_startup_coordinator.gd`
- `scripts/core_status_coordinator.gd`
- `scripts/settings_visual_fix.gd`
- `models/model_setup_wizard.gd`
- `build/build_windows.ps1`
- `build/build_android.ps1`
- `build/build_android_bundled.ps1`
- `build/prepare_bundled_core_model.ps1`
- `build/prepare_bundled_windows_core.ps1`
- `export_presets.cfg`
- `tests/test_android_contract.py`
- `.github/workflows/windows-package-ci.yml`
- `.github/workflows/android-apk-artifact.yml`
- `.github/workflows/release.yml`

The existing updater/signing reservation also remains in force for:

- `project.godot`
- `project/version.json`
- `update/manifest.template.json`
- `update/update_manager.gd`
- `update/README.md`
- `update/release_public.pub`
- `update/release_identity.json`
- `CHANGELOG.md`
- `build/AuroraFox.iss`
- `build/AuroraFox_V12_BridgeFixture.iss`
- `build/bridge_release_readiness.ps1`
- `build/setup_release_signing.ps1`
- `build/create_update_signing_key.ps1`
- `tests/windows_v12_bridge_smoke.ps1`
- `tests/test_update_backward_compat.py`
- `tests/update_smoke.gd`

## Current verification target

Do not call the new complete package verified until all of the following are green on a head containing the mandatory bundled-Core build changes:

- Core / Voice CI including Godot parse/smokes.
- Windows Package CI including bundled engine/model integrity, installer, installed-app launch, V1.2 repair and artifact upload.
- Android APK Artifact including >1.2 GiB bundled-Core APK, signing validation, install and launch on Android 35 emulator.
- Agent Sync / other triggered architecture smokes.

After the above, record exact run IDs, artifact IDs and SHA-256 values in `docs/workstreams/CHAT_MAIN.md` and release these files from the active claim as appropriate.

## Recommended independent lanes for Work mode

Work mode can safely make progress in parallel by choosing a separate coherent lane that does not touch the reserved files, for example:

- UI/UX polish in unrelated screens.
- Voice quality and local speech runtime improvements.
- Work/projects UX and persistence improvements.
- File Intelligence/OCR improvements outside release/version files.
- Performance profiling and bounded-memory improvements outside bundled Core startup/build files.
- Documentation in its own lane-specific file.

Work mode should create/update `docs/workstreams/WORK_MODE.md` before its first implementation batch and state exactly which files or subsystem it claims.

## Merge/conflict rule

If two lanes need the same file, the second lane must stop editing that file, fetch the newest `main`, read the first lane's journal, then either:

- move to a different task, or
- make a new integration commit based on the latest version rather than replacing it.

The repository state and CI results are authoritative; prose plans are not.
