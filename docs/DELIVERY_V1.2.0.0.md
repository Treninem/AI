# AuroraFox V1.2.0.0 — verified delivery state

Date: 2026-09-15

This file is the final delivery record for the current V1.2.0.0 implementation. It separates verified installable artifacts from the one-time owner-controlled production signing bootstrap.

## Verified Windows build

Latest Windows Package CI: run `35005296536`, commit `e0ba1a1ace45ac559309805db3b2b1b4f31e560a` — `success`.

The workflow successfully completed:
- PowerShell parse of Windows build/release helpers, including `build/setup_release_signing.ps1`;
- version synchronization;
- Godot 4.7.1 project import;
- Windows package build;
- required runtime/API/Core/update asset checks;
- exported executable smoke;
- installer build;
- silent install;
- launch of the installed application;
- silent uninstall;
- portable ZIP and SHA-256 generation;
- artifact upload.

Final Windows artifacts:
- `AuroraFox-V1.2.0.0-Setup-Windows.exe`
  - SHA-256: `01839fa3da2467792ba7df3570eedeaca9f3cf1b83a6a17a6da37e266a5ca4d3`
- `AuroraFox-V1.2.0.0-Windows-Portable.zip`
  - SHA-256: `7adcc08fdd854f799ae181a23da4c4045dfd9e5f4d76ed2d3bc9c7e26ff9ab20`

## Verified Android build

Latest full Android APK Artifact verification used run `35004268613`, commit `ae05e50cb78022e918f248cfa5b5f08d79d070ea` — `success`.

The workflow successfully completed:
- Android release contract;
- Java/Gradle/Android SDK and pinned native toolchain setup;
- Godot 4.7.1 and export templates;
- full APK export;
- test signing and APK validation;
- installation on Android 35 emulator;
- launch of AuroraFox on Android 35;
- artifact upload.

Installable CI Android artifact:
- `AuroraFox-V1.2.0.0-Android-Test.apk`
  - SHA-256: `59c0e9c7b34e01f0e6b5ea43be84e864b84b5b919a58a28a917880085e21cbe8`
  - package: `com.aurorafox.ai`
  - versionName: `1.2.0.0`
  - versionCode: `100004`
  - min SDK: `26`
  - target SDK: `35`

This APK is installable and emulator-tested, but it uses the CI test signing identity. It must not be mistaken for the permanent Android production signing identity.

## Core/runtime verification

Core Bootstrap E2E run `35004268677` completed successfully after fixing authenticated GitHub release metadata access for CI. The run installed and smoke-tested the verified llama.cpp Core Engine, confirmed Ollama is not required, imported the Godot project and passed Core/Knowledge, local semantic memory and autonomy/self-evolution safety contracts.

Semantic Memory CI, Core/Voice CI and Agent Sync are also green on the current implementation path.

## Knowledge/file import state

The user-controlled Core Knowledge path accepts arbitrary filenames and routes supported JSON/text/code/data/document content by content/format rather than filename. Source fingerprints, duplicate aliases, revisions, source-scoped rollback, delete/reindex and rich local extraction are implemented.

Windows File Intelligence supports local rich-document extraction. Android includes native office/document parsing plus offline PDF text-layer extraction through PDFBox. Scanned PDFs without a text layer are not silently learned as fake text; local OCR remains a separate future capability.

## Updates and signing boundary

Application-side updates are implemented: legacy V1.0 direct-update compatibility, Windows transactional replacement/rollback, Android package install flow, SHA-256 asset verification and signed-manifest support are retained.

A permanent production update channel requires one owner-controlled initialization because signing identities must not be generated with temporary CI keys or committed privately to Git.

Use the new one-time helper on a trusted owner Windows machine:

```powershell
powershell -ExecutionPolicy Bypass -File .\build\setup_release_signing.ps1
```

The helper:
- creates the permanent updater RSA trust root if it does not exist;
- creates/reuses the permanent Android release keystore;
- keeps private material under ignored `build/private/`;
- can configure the required GitHub Actions secrets through an authenticated `gh` CLI without committing private keys;
- instructs the owner to commit only `update/release_public.pub`;
- refuses accidental trust-key/keystore rotation.

Required production identities/secrets are:
- `update/release_public.pub` in the repository;
- `AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64` in GitHub Actions secrets;
- `AURORA_ANDROID_KEYSTORE_BASE64` in GitHub Actions secrets;
- `AURORA_ANDROID_KEYSTORE_USER` in GitHub Actions secrets;
- `AURORA_ANDROID_KEYSTORE_PASSWORD` in GitHub Actions secrets.

At the time of this record, GitHub Releases are empty and `update/release_public.pub` has not yet been owner-initialized. This is deliberately not bypassed. Once the one-time owner signing bootstrap is completed, the existing `AuroraFox Release` workflow is the production path for signed Windows/Android assets plus `update.json` / `update.sig`.

## Security invariant

Do not ship a temporary-key release as production. Android signing identity and updater RSA trust identity are long-lived update compatibility roots. Losing or casually rotating them can force manual reinstall/update recovery for users.
