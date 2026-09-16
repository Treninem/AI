# AuroraFox parallel work coordination

This file is the shared coordination map for ChatGPT chat mode, Work mode and any other trusted development lane working on the same repository.

## Current baseline

- Repository: `Treninem/AI`
- Branch: `main`
- Coordination baseline commit: `a00d0b2d07cbcde0fee686ba735933a7959ec7ff`
- Current release line: `V1.3.0.0`
- Android versionCode: `100005`
- Godot: `4.7.1`

Verified on this baseline:

- Windows Package CI run `35006665055`: success.
- Android APK Artifact run `35006664982`: success, including install/launch on Android 35 emulator.
- Core / Voice CI run `35006665008`: success.
- Agent Sync CI run `35006665083`: success.
- Evolution Progress push run `35006665037`: success.

## Parallel-work protocol

1. Before any write, fetch the latest `main` head. Never assume the baseline above is still HEAD.
2. Read this file plus `docs/DEVELOPMENT_LOG.md` and the lane files in `docs/workstreams/` before changing shared architecture.
3. Each development lane must write only to its own workstream journal for frequent updates. Do not have multiple agents repeatedly rewrite this shared file.
4. Before editing an existing file, check whether another lane currently claims it. If it is claimed, choose another task or integrate the latest owner changes first.
5. After a coherent batch, commit code first, then update the lane journal with: commit SHA, files changed, tests/run IDs, decisions, remaining work and files released from the claim.
6. Do not overwrite a file from a stale copy. Re-fetch it immediately before an update if `main` changed.
7. Never weaken the user master stop, rollback, updater signature verification, Core candidate allowlists, privacy boundaries, Android signing continuity or V1.0+ direct-update compatibility.

## Current chat-mode lane

Owner journal: `docs/workstreams/CHAT_MAIN.md`

Current scope:

- V1.3.0.0 release delivery and artifact verification.
- Backward-compatible updater/release readiness.
- Production signing bootstrap/readiness without committing private keys.
- Final verification of Windows/Android packages.

Temporarily reserved/shared-sensitive files while this lane is active:

- `project.godot`
- `project/version.json`
- `export_presets.cfg`
- `update/manifest.template.json`
- `CHANGELOG.md`
- `build/setup_release_signing.ps1`
- `build/create_update_signing_key.ps1`
- `.github/workflows/release.yml`
- `.github/workflows/windows-package-ci.yml`
- `.github/workflows/android-apk-artifact.yml`

Work mode should not independently change the files above without first reading the latest chat workstream journal and deliberately integrating current release work.

## Recommended independent lanes for Work mode

Work mode can safely make progress in parallel by choosing a separate coherent lane, for example:

- UI/UX polish in existing screens while avoiding release/version/updater files.
- Additional regression/smoke tests in new test files.
- Voice quality and local speech runtime improvements.
- Work/projects UX and persistence improvements.
- File Intelligence/OCR improvements outside release/version files.
- Performance profiling and bounded-memory improvements.
- Documentation in a lane-specific file.

Work mode should create/update `docs/workstreams/WORK_MODE.md` before its first implementation batch and state exactly which files or subsystem it claims.

## Merge/conflict rule

If two lanes need the same file, the second lane must stop editing that file, fetch the newest `main`, read the first lane's journal, then either:

- move to a different task, or
- make a new integration commit based on the latest version rather than replacing it.

The repository state and CI results are authoritative; prose plans are not.
