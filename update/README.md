# AuroraFox Update System

AuroraFox uses GitHub Releases as the stable update channel. The application code does not update from arbitrary repository files: it reads the release `update.json`, selects the current platform asset, downloads it to private `user://updates/`, calculates SHA-256 locally, and installs only when the checksum matches the release manifest.

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

## Windows

GitHub Release asset: `AuroraFox-Windows.zip`.

Flow:

1. download ZIP;
2. verify SHA-256;
3. copy `update/windows_updater.ps1` to `user://updates/`;
4. start the helper hidden and close AuroraFox;
5. helper waits for the old process to exit;
6. extract into a sibling staging directory;
7. keep the old installation as a rollback directory;
8. atomically switch directories;
9. preserve locally installed large runtime/model folders when possible;
10. start the new AuroraFox with a health-marker argument;
11. if startup health is not confirmed within the timeout, restore and relaunch the previous version;
12. on success remove backup and downloaded package.

The first installation is built by Inno Setup from `build/AuroraFox.iss` and creates Start Menu/Desktop shortcuts.

## Android

GitHub Release asset: `AuroraFox-Android.apk`.

Flow:

1. download APK to AuroraFox private storage;
2. verify SHA-256;
3. native Godot Android plugin copies it into app cache;
4. `AuroraUpdateProvider` exposes only that exact private APK through a read-only content URI;
5. Android package installer is opened;
6. Android performs the final package/signature checks and displays its required system confirmation.

AuroraFox does not bypass Android package-install security dialogs. All Android releases must use the same persistent release signing key or Android will reject an APK as an update to the installed app.

Create the signing key once with:

```powershell
./build/create_android_signing_key.ps1
```

Then configure these GitHub Actions repository secrets:

- `AURORA_ANDROID_KEYSTORE_BASE64`
- `AURORA_ANDROID_KEYSTORE_USER`
- `AURORA_ANDROID_KEYSTORE_PASSWORD`

The keystore/password must be backed up outside the repository. They are intentionally ignored by Git.

## Publishing a release

`.github/workflows/release.yml` builds both targets from a `v*` tag, calculates SHA-256, generates `update.json`, and attaches these assets to the GitHub Release:

- `AuroraFox_Setup_Windows.exe`
- `AuroraFox-Windows.zip`
- `AuroraFox-Android.apk`
- `update.json`

The tag must match `application/config/version` in `project.godot`.

Example for version `0.4.0`:

```text
project.godot: config/version="0.4.0"
export_presets.cfg Android version/name="0.4.0"
tag: v0.4.0
```

## Tests

`tests/update_smoke.gd` checks version ordering and the manifest structure. The core CI parses the Godot project and runs both voice and update smoke tests.

A successful smoke test is not a substitute for running the produced Windows installer and Android APK on actual devices. Release artifacts should only be called verified after those platform tests pass.
