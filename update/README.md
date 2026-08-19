# AuroraFox Update System

AuroraFox uses GitHub Releases as the stable update channel. It does not execute arbitrary repository files. Every published update uses two verification layers before installation:

1. `update.json` is verified against `update.sig` with the RSA public key pinned inside the AuroraFox build;
2. the selected Windows ZIP or Android APK is then verified against the SHA-256 stored inside that already-authenticated manifest.

If the manifest signature or package checksum is invalid, the update is rejected and the existing AuroraFox keeps running.

## Runtime flow

`AuroraUpdate` is an autoload from `update/update_manager.gd`.

Default policy:

- channel: `stable`;
- automatic check: enabled;
- interval: 6 hours;
- automatic download: enabled;
- install remains platform-controlled;
- update failure never disables the chat/AI core.

The UI is `update/update_overlay.gd` and exposes check/download/install plus update preferences.

## Update trust key

Generate the release trust key **once** on a trusted local Windows machine:

```powershell
./build/create_update_signing_key.ps1
```

It creates:

- `update/release_public.pub` — public RSA key; commit this file to the repository;
- `build/private/aurora_update_signing_private.pem` — private RSA key; never commit it;
- `build/private/AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64.txt` — value for the GitHub Actions secret.

Configure repository secret:

- `AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64`

The release workflow derives the public key from the secret and compares its SHA-256 fingerprint to the committed `update/release_public.pub` before signing. A mismatched private key aborts the release.

Back up the private update-signing key outside the repository. A planned key rotation requires shipping a version that trusts the next public key before the old private key is retired.

## Windows

GitHub Release asset: `AuroraFox-Windows.zip`.

Flow:

1. verify RSA signature of `update.json`;
2. download ZIP;
3. verify ZIP SHA-256;
4. copy `update/windows_updater.ps1` to `user://updates/`;
5. start the helper hidden and close AuroraFox;
6. helper waits for the old process to exit and stops remaining AuroraFox sidecar processes that could lock files;
7. extract into a sibling staging directory;
8. keep the old installation as a rollback directory;
9. atomically switch directories;
10. preserve locally installed large runtime/model folders when possible;
11. start the new AuroraFox with a health-marker argument;
12. if startup health is not confirmed within the timeout, restore and relaunch the previous version;
13. on success remove backup and downloaded package.

The first installation is built by Inno Setup from `build/AuroraFox.iss` and creates Start Menu/Desktop shortcuts.

## Android

GitHub Release asset: `AuroraFox-Android.apk`.

Flow:

1. verify RSA signature of `update.json`;
2. download APK to AuroraFox private storage;
3. verify APK SHA-256;
4. native Godot Android plugin copies it into app cache;
5. `AuroraUpdateProvider` exposes only that exact private APK through a read-only content URI;
6. Android package installer is opened;
7. Android performs its own final package/signature checks and displays required system confirmation.

AuroraFox does not bypass Android package-install security dialogs. All Android releases must use the same persistent release signing key or Android will reject an APK as an update to the installed app.

Create the Android signing key once with:

```powershell
./build/create_android_signing_key.ps1
```

Then configure these GitHub Actions repository secrets:

- `AURORA_ANDROID_KEYSTORE_BASE64`
- `AURORA_ANDROID_KEYSTORE_USER`
- `AURORA_ANDROID_KEYSTORE_PASSWORD`

The Android keystore/password must also be backed up outside the repository. They are intentionally ignored by Git.

## Publishing a release

Use one command to synchronize project and Android version fields:

```powershell
./build/set_version.ps1 -Version 0.4.1
```

Then publish tag `v0.4.1` after CI is clean.

`.github/workflows/release.yml` builds both targets, calculates SHA-256, generates the manifest, validates the update signing private/public key pair, signs the exact `update.json` bytes, verifies that signature again in CI, and publishes:

- `AuroraFox_Setup_Windows.exe`;
- `AuroraFox-Windows.zip`;
- `AuroraFox-Android.apk`;
- `update.json`;
- `update.sig`.

The tag must match `application/config/version` in `project.godot`.

## Tests

- `tests/update_smoke.gd` checks version ordering, manifest structure, RSA signing/verification and tamper rejection using Godot cryptographic APIs;
- `tests/version_sync_test.ps1` checks project/Android/manifest version synchronization;
- `tests/windows_updater_test.ps1` exercises the real transactional Windows updater against a temporary installation;
- `.github/workflows/android-plugin-ci.yml` compiles the native Android plugin and verifies both AuroraFoxRuntime and sherpa-onnx AAR outputs;
- core CI parses the Godot 4.7.1 project and executes the updater smoke tests.

CI coverage is not a substitute for installing the produced Windows installer and Android APK on actual devices. Release artifacts should only be called device-verified after those platform runtime tests pass.
