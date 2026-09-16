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
  - version synchronization
  - Godot import
  - Windows package build
  - required runtime assets
  - exported executable smoke
  - Inno Setup installer
  - silent install
  - installed-app launch
  - uninstall
  - portable ZIP/hashes/artifact upload
- Android APK Artifact `35006664982`: success.
  - release contract
  - pinned Android toolchain
  - Godot Android export
  - APK test signing/validation
  - install and launch on Android 35 emulator
  - artifact upload
- Core / Voice CI `35006665008`: success.
- Agent Sync CI `35006665083`: success.
- Evolution Progress push run `35006665037`: success.

### Verified V1.3.0.0 delivery artifacts

Downloaded directly from the successful V1.3 workflows and independently re-hashed after extraction.

Windows workflow artifact `10412017819`:

- `AuroraFox-V1.3.0.0-Setup-Windows.exe`
  - SHA-256: `8dc88d5dcbed12d81daf1ce14d2149207092d97421b85c8c0e5e7d0f5fba6f15`
- `AuroraFox-V1.3.0.0-Windows-Portable.zip`
  - SHA-256: `96aac3962f5d8aa8669144b7a632b48720fc6ca33e8205d13e1645e33e275c6a`

The independently computed Windows hashes match the workflow-generated `SHA256SUMS.txt` exactly.

Android workflow artifact `10412014222`:

- `AuroraFox-V1.3.0.0-Android-Test.apk`
  - SHA-256: `c02fef0e7d58eb4eeb999f7a1ec3c71074250c4993711d003c8ebd939328676c`
  - package: `com.aurorafox.ai`
  - built, validated, installed and launched by the successful Android 35 emulator workflow.

The Android artifact is CI/test-signed. It is suitable for installation/testing, but it is not a production signing identity replacement.

### Active chat-mode scope

1. Keep V1.0+ direct-update manifest/asset compatibility intact.
2. Finish production signing/bootstrap/readiness without exposing private keys.
3. Keep release/version files synchronized.
4. Prepare public production release only after owner-controlled signing identity is initialized.
5. Update `docs/DEVELOPMENT_LOG.md` only after factual verification.

### Reserved files for this lane

Until this entry is explicitly changed to RELEASED, avoid parallel edits to:

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

### Safe parallel work

Work mode may take another subsystem and should record its claim in `docs/workstreams/WORK_MODE.md`. Good independent targets include UI/UX, voice, Work/projects, new regression tests, OCR/File Intelligence or performance work that does not edit the reserved files above.

### Release status

V1.3.0.0 Windows and Android application packages are CI-verified and independently hashed. Production public release/update publication still must retain the owner-controlled Android signing identity and RSA update-signing trust root; private signing material must never be committed to Git.
