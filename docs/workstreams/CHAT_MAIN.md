# Chat main workstream journal

## 2026-09-16 — V1.3.0.0 delivery lane

### Starting state

- Base implementation/release trigger: `a00d0b2d07cbcde0fee686ba735933a7959ec7ff`.
- Shared coordination file added by commit `f3ed9c1ccfb3b00fd2cda5f5fdde8253f563aee3`.
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

### Active chat-mode scope

1. Download and independently verify the V1.3 Windows and Android artifacts.
2. Keep V1.0+ direct-update manifest/asset compatibility intact.
3. Finish production signing bootstrap/readiness without exposing private keys.
4. Keep release/version files synchronized.
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

V1.3.0.0 application packages are CI-verified. Production public release/update publication still must retain the owner-controlled Android signing identity and RSA update-signing trust root; private signing material must never be committed to Git.
