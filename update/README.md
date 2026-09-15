# AuroraFox Update System

AuroraFox uses GitHub Releases as the stable update channel. It does not execute arbitrary repository files. Every published update uses two verification layers before installation:

1. `update.json` is verified against `update.sig` with the RSA public key pinned inside current AuroraFox builds;
2. the selected Windows ZIP or Android APK is then verified against the SHA-256 stored inside that authenticated manifest.

If the manifest signature or package checksum is invalid, the current updater rejects the update and the existing AuroraFox keeps running.

## Runtime flow

`AuroraUpdate` is an autoload from `update/update_manager.gd`.

Default policy:

- channel: `stable`;
- automatic check: enabled;
- automatic download: enabled;
- automatic apply: enabled where the platform permits it;
- update failure never disables the chat/AI core.

The UI is `update/update_overlay.gd` and exposes check/download/install plus update preferences.

## Backward-compatible updates

The update system was completed before the **AuroraFox V1.0.0.0** release on **2026-08-19**. V1.0.0.0 already contained the permanent update discovery URL and the transactional Windows updater needed to replace a complete application package safely.

The permanent discovery URL is:

`https://github.com/Treninem/AI/releases/latest/download/update.json`

V1.0.0.0 already understood the same legacy manifest fields used today: `version`, `channel`, `mandatory`, `assets.windows.url`, `assets.windows.sha256`, `assets.android.url` and `assets.android.sha256`.

Therefore **V1.0.0.0 and every later AuroraFox release can update directly to the newest compatible stable release**. The application does not need to install V1.1, V1.2 and other intermediate versions in sequence. A current release may add new manifest fields such as `schema_version`, `compatibility`, sizes, formats and signature metadata, but it must retain the legacy fields because old clients ignore unknown fields and keep reading the original ones.

Permanent compatibility rules for stable releases:

- always publish `update.json` in the GitHub **latest release** path;
- keep `AuroraFox-Windows.zip` as the Windows full-package update asset;
- keep `AuroraFox-Android.apk` as the Android update asset;
- keep the legacy top-level manifest and `assets.windows` / `assets.android` fields;
- `update.sig` is additive security for newer clients and must never replace `update.json`;
- Windows updates remain a full ZIP replacement with transactional backup/rollback. The release ZIP must keep `AuroraFox.exe` at archive root (or a single wrapping directory accepted by the V1.0 helper), so the V1.0 updater can jump directly to the current package;
- Android keeps package ID `com.aurorafox.ai` and the same persistent signing identity. Android rejects an APK signed by a different key as an update of the installed app;
- do not move the legacy manifest URL or rename legacy release assets unless a bridge release has first shipped an updater that understands both old and new locations.

Experimental builds made **before V1.0.0.0**, before the complete release updater contract was guaranteed, need one manual bootstrap installation of V1.0.0.0 or newer. After that one-time manual bootstrap, later compatible releases can update through the application normally.

This compatibility contract is enforced by `tests/test_update_backward_compat.py`, `tests/update_smoke.gd` and the signed release Core gates.

## First signed bridge release

The repository currently requires current-generation clients to verify `update.sig` with `update/release_public.pub`. The first real signed release after the trust key is initialized acts as a bridge:

- V1.0/V1.1 legacy clients keep using `update.json` and package SHA-256 and can install that release directly;
- the bridge release contains the pinned RSA public key;
- every client updated to the bridge release verifies future `update.json` files with RSA before trusting package hashes.

The bridge release must not be published until the public update key is committed and its matching private key is configured only as the GitHub Actions secret described below.

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

Back up the private update-signing key outside the repository. A planned key rotation requires shipping a bridge version that trusts the next public key before the old private key is retired. Old signed-update-capable builds must never be stranded by an unannounced trust-key replacement.

## Windows

GitHub Release asset: `AuroraFox-Windows.zip`.

Flow:

1. current clients verify the RSA signature of `update.json`; V1.0/V1.1 clients read the same backwards-compatible manifest contract;
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

1. current clients verify the RSA signature of `update.json`; legacy updater clients use the same manifest URL and asset fields;
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
./build/set_version.ps1 -Version 1.2.0.0
```

Then publish tag `v1.2.0.0` after CI is clean and the trust/signing keys are configured.

`.github/workflows/release.yml` builds both targets, calculates SHA-256, generates the backwards-compatible manifest, validates the update signing private/public key pair, signs the exact `update.json` bytes, verifies that signature again in CI, and publishes:

- `AuroraFox_Setup_Windows.exe`;
- `AuroraFox-Windows.zip`;
- `AuroraFox-Android.apk`;
- `update.json`;
- `update.sig`;
- `release_verification.json`.

The tag must match `application/config/version` in `project.godot`.

## Tests

- `tests/update_smoke.gd` checks direct version jumps, permanent manifest URLs, manifest structure, RSA signing/verification and tamper rejection using Godot cryptographic APIs;
- `tests/test_update_backward_compat.py` emulates the V1.0 embedded updater contract and protects the permanent legacy URL, full ZIP layout, manifest fields and release asset names;
- `tests/version_sync_test.ps1` checks project/Android/manifest version synchronization;
- `tests/windows_updater_test.ps1` exercises the real transactional Windows updater against a temporary installation;
- `.github/workflows/android-plugin-ci.yml` compiles the native Android plugin and verifies both AuroraFoxRuntime and sherpa-onnx AAR outputs;
- core/release CI parses the Godot 4.7.1 project and executes updater/recovery smoke tests before signed artifacts may be published.

CI coverage is not a substitute for installing the produced Windows installer and Android APK on actual devices. Release artifacts should only be called device-verified after those platform runtime tests pass.
