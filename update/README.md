# AuroraFox Update System

AuroraFox uses GitHub Releases as the stable update channel. Current signed-update-capable builds verify two layers before installation:

1. `update.json` is verified against `update.sig` with the RSA public key pinned inside AuroraFox;
2. the selected Windows ZIP or Android APK is verified against the SHA-256 stored inside that authenticated manifest.

If either verification fails, AuroraFox keeps the current installation running.

## Important V1.2.0.0 repair notice

A historical audit found a defect in the already-built **V1.2.0.0** updater. V1.2 points at the permanent GitHub Releases manifest URL and already contains RSA-signature verification logic, but that build did **not** contain `res://update/release_public.pub`. In addition, the repository had no published GitHub Release carrying `update.json`.

Therefore an already-installed V1.2.0.0 cannot repair its own trust root remotely. Publishing `update.json` alone is insufficient: V1.2 would still reject the update because its local public key is missing.

The supported recovery boundary is now explicit:

- **V1.0.0.0 through V1.2.0.0:** one-time repair/bridge installation is required;
- **V1.3.0.0 and later:** signed automatic updates are the supported normal path once the owner-controlled release trust root is initialized.

The permanent discovery URL remains:

`https://github.com/Treninem/AI/releases/latest/download/update.json`

Legacy manifest field names and stable asset names are still retained so the transport contract is not broken again, but legacy manifest readability must not be confused with a working cryptographic trust chain.

## Windows V1.2 -> V1.3 repair

Use the Windows artifact named:

`AuroraFox-V1.2-to-V1.3.0.0-Repair-Windows.exe`

It is the same verified V1.3 application installer with explicit in-place bridge behavior. It keeps the historical Inno Setup AppId and install location, detects the previous installed version, replaces application files, clears only known installation-directory leftovers, and writes `update/bridge_repair.txt` recording the repaired version transition.

Godot `user://` data is outside the application directory and is deliberately not deleted by the repair installer. CI verifies this by installing a V1.2 fixture with the historical AppId, creating a sentinel in `Godot/app_userdata/AuroraFox`, installing V1.3 on top, checking that the sentinel is unchanged, checking `previous=1.2.0.0` / `current=1.3.0.0`, and launching the upgraded application.

After this one-time repair, the installation uses the V1.3 updater implementation for future signed updates.

## Android V1.2 -> V1.3 signing boundary

Android requires an update APK to use both the same package ID and the same signing identity as the installed APK.

AuroraFox keeps package ID:

`com.aurorafox.ai`

However historical CI test artifacts, including V1.2 test APKs, generated a fresh temporary keystore inside each workflow run and did not retain that key. A V1.2 APK installed from such a test artifact **cannot** be upgraded in place by a differently signed V1.3 APK. Android itself rejects that package replacement; a new APK cannot change this rule retroactively.

Production Android releases must therefore use one persistent owner-controlled keystore. The release workflow already requires:

- `AURORA_ANDROID_KEYSTORE_BASE64`
- `AURORA_ANDROID_KEYSTORE_USER`
- `AURORA_ANDROID_KEYSTORE_PASSWORD`

The keystore must be backed up outside Git and reused for every future production APK. CI/test APKs are explicitly named `-Android-Test.apk` and must not be presented as production-upgrade identities.

If an installed V1.2 APK was built with the same persistent production signing key, V1.3 may update it in place. If it came from an ephemeral CI run, uninstall/reinstall (or a device-specific owner backup/restore procedure) is required because the historical signing key no longer exists.

## Runtime flow for V1.3+

`AuroraUpdate` is an autoload from `update/update_manager.gd`.

Default policy:

- channel: `stable`;
- automatic check: enabled;
- automatic download: enabled;
- automatic apply: enabled where the platform permits it;
- update failure never disables the local AI/chat core.

The UI is `update/update_overlay.gd` and exposes check/download/install plus update preferences.

Stable-release invariants:

- keep `https://github.com/Treninem/AI/releases/latest/download/update.json`;
- keep `AuroraFox-Windows.zip` as the Windows update package;
- keep `AuroraFox-Android.apk` as the Android production update package;
- keep `update.json` legacy top-level and per-platform asset fields;
- always publish `update.sig` for signed-generation releases;
- Windows remains transactional full-package replacement with backup/rollback;
- Android keeps package ID `com.aurorafox.ai` and the same persistent signing identity;
- never rotate the RSA update key or Android signing identity without a deliberate migration release.

## Update trust key

Generate the release trust key once on a trusted owner Windows machine:

```powershell
./build/create_update_signing_key.ps1
```

It creates:

- `update/release_public.pub` — public RSA key; this is committed;
- `build/private/aurora_update_signing_private.pem` — private key; never commit it;
- `build/private/AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64.txt` — value for the GitHub Actions secret.

Configure:

- `AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64`

The release workflow derives the public key from the secret and compares it with the committed trust root before signing. A mismatch aborts release publication.

## Windows signed update flow

GitHub Release asset: `AuroraFox-Windows.zip`.

1. verify RSA signature of `update.json`;
2. select Windows asset and download ZIP;
3. verify ZIP SHA-256;
4. copy `update/windows_updater.ps1` to `user://updates/`;
5. start helper and close AuroraFox;
6. helper stages the new application and keeps the previous installation as rollback;
7. start the new AuroraFox with a health marker;
8. restore the previous installation if health confirmation fails;
9. remove backup/package only after success.

## Android signed update flow

GitHub Release asset: `AuroraFox-Android.apk`.

1. verify RSA signature of `update.json`;
2. download APK to AuroraFox private storage;
3. verify APK SHA-256;
4. native Android plugin exposes the verified private APK through a read-only content URI;
5. Android package installer performs package/signature checks and displays the required system confirmation.

AuroraFox does not bypass Android installation security.

Create the persistent Android key once with:

```powershell
./build/create_android_signing_key.ps1
```

## Publishing a signed release

Synchronize version fields with:

```powershell
./build/set_version.ps1 -Version 1.3.0.0
```

Then publish tag `v1.3.0.0` only after CI is green and both persistent signing identities are configured.

`.github/workflows/release.yml` builds both targets, calculates SHA-256, creates the stable manifest, validates the update signing key pair, signs the exact `update.json` bytes, verifies that signature in CI and publishes:

- `AuroraFox_Setup_Windows.exe`;
- `AuroraFox-Windows.zip`;
- `AuroraFox-Android.apk`;
- `update.json`;
- `update.sig`;
- `release_verification.json`.

## Tests

- `tests/test_update_backward_compat.py` protects the stable manifest/asset transport contract and explicitly enforces the V1.2 repair boundary;
- `tests/windows_v12_bridge_smoke.ps1` performs the in-place V1.2 -> V1.3 Windows repair simulation and verifies user data survival;
- `tests/update_smoke.gd` checks version comparison, manifest URLs, RSA verification and tamper rejection;
- `tests/version_sync_test.ps1` checks project/Android/manifest synchronization;
- `tests/windows_updater_test.ps1` exercises the transactional Windows updater;
- Android CI validates package metadata and installs/launches the produced test APK on Android 35.
