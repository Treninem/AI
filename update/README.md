# AuroraFox Update System

AuroraFox uses GitHub Releases as the stable update channel. Current signed-update-capable builds verify two layers before installation:

1. `update.json` is verified against `update.sig` with the RSA public key pinned inside AuroraFox;
2. the selected Windows ZIP or Android APK is verified against the SHA-256 stored inside that authenticated manifest.

If either verification fails, AuroraFox keeps the current installation running.

## Important V1.2.0.0 repair notice

A historical audit found a defect in the already-built **V1.2.0.0** updater. V1.2 points at the permanent GitHub Releases manifest URL and already contains RSA-signature verification logic, but that build did **not** contain `res://update/release_public.pub`. In addition, the repository had no published stable GitHub Release carrying `update.json`.

Therefore an already-installed V1.2.0.0 cannot repair its own trust root remotely. Publishing `update.json` alone is insufficient: V1.2 would still reject the update because its local public key is missing.

The supported recovery boundary is now explicit:

- **V1.0.0.0 through V1.2.0.0:** one-time repair/bridge installation is required;
- **V1.3.0.0 and later:** signed automatic updates are the supported normal path once the owner-controlled release trust root is initialized.

The permanent discovery URL for the normal signed update channel remains:

`https://github.com/Treninem/AI/releases/latest/download/update.json`

Legacy manifest field names and stable asset names are retained so the transport contract is not broken again, but legacy manifest readability must not be confused with a working cryptographic trust chain.

## Windows V1.2 -> V1.3 repair

A separate non-latest GitHub Release is maintained specifically for the historical Windows repair:

`https://github.com/Treninem/AI/releases/tag/repair-v1.2-windows`

Stable repair asset name:

`AuroraFox-V1.2-Repair-Windows.exe`

The Windows Package CI creates the repair installer only after the real V1.2 -> current bridge test passes, then publishes or refreshes that stable asset and its SHA-256 file. The repair release is explicitly created with `latest=false`, so it never replaces the signed `latest/update.json` channel.

The repair executable is the same verified current AuroraFox installer with explicit in-place bridge behavior. It keeps the historical Inno Setup AppId and install location, detects the previous installed version, replaces application files, clears only known installation-directory leftovers, and writes `update/bridge_repair.txt` recording the repaired version transition.

Godot `user://` data is outside the application directory and is deliberately not deleted by the repair installer. CI verifies this by installing a V1.2 fixture with the historical AppId, creating a sentinel in `Godot/app_userdata/AuroraFox`, installing V1.3 on top, checking that the sentinel is unchanged, checking `previous=1.2.0.0` / `current=1.3.0.0`, and launching the upgraded application.

After this one-time repair, the installation uses the V1.3 updater implementation for future signed updates.

## Android V1.2 -> V1.3 signing boundary

Android requires an update APK to use both the same package ID and the same signing identity as the installed APK.

AuroraFox keeps package ID:

`com.aurorafox.ai`

However historical CI test artifacts, including V1.2 test APKs, generated a fresh temporary keystore inside each workflow run and did not retain that key. A V1.2 APK installed from such a test artifact **cannot** be upgraded in place by a differently signed V1.3 APK. Android itself rejects that package replacement; a new APK cannot change this rule retroactively.

Production Android releases therefore use one persistent owner-controlled keystore. Its public certificate SHA-256 is pinned in `update/release_identity.json`. The production build verifies the configured keystore against that pin **before** export and then verifies the certificate of the finished APK with `apksigner`. A mismatch aborts the release.

Required GitHub Actions secrets:

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
- Android keeps package ID `com.aurorafox.ai` and the same persistent signing certificate;
- `update/release_identity.json` pins both the update public-key fingerprint and Android signing-certificate fingerprint;
- never rotate the RSA update key or Android signing identity without a deliberate migration release.

## One-time production signing bootstrap

Run the combined owner-only setup once on a trusted Windows machine:

```powershell
./build/setup_release_signing.ps1
```

The helper creates or validates both permanent identities:

- `update/release_public.pub` — public RSA update-verification key; commit this;
- `update/release_identity.json` — public fingerprints for the update key and Android signing certificate; commit this;
- `build/private/aurora_update_signing_private.pem` — private update signing key; never commit;
- `build/private/aurorafox-android-release.jks` — permanent Android release keystore; never commit;
- base64 helper files under `build/private/` for GitHub Actions secrets.

`build/private/`, `*.jks` and `*.keystore` are Git-ignored. The setup helper refuses silent identity rotation: if public pins already exist but the local private key/keystore do not match, it stops instead of generating replacements.

When authenticated `gh` is available, the setup helper stores these repository secrets via stdin:

- `AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64`
- `AURORA_ANDROID_KEYSTORE_BASE64`
- `AURORA_ANDROID_KEYSTORE_USER`
- `AURORA_ANDROID_KEYSTORE_PASSWORD`

Only the two public files are committed:

```powershell
git add update/release_public.pub update/release_identity.json
```

Then run:

```powershell
./build/bridge_release_readiness.ps1
```

The readiness gate checks the V1.2 repair boundary, version synchronization, public update key, public release identity pins, Android production certificate gate and required GitHub secret names.

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

## Publishing a signed release

Synchronize version fields with:

```powershell
./build/set_version.ps1 -Version 1.3.0.0
```

Then publish tag `v1.3.0.0` only after CI is green, `bridge_release_readiness.ps1` passes, and both permanent signing identities are initialized.

`.github/workflows/release.yml` builds both targets, calculates SHA-256, validates the Android production signing identity, creates the stable manifest, validates the update signing key pair, signs the exact `update.json` bytes, verifies that signature in CI and publishes:

- `AuroraFox_Setup_Windows.exe`;
- `AuroraFox-Windows.zip`;
- `AuroraFox-Android.apk`;
- `update.json`;
- `update.sig`;
- `release_verification.json`.

## Tests

- `tests/test_update_backward_compat.py` protects the stable manifest/asset transport contract, V1.2 repair boundary, V1.3 signed-update floor and permanent signing-identity gates;
- `tests/windows_v12_bridge_smoke.ps1` performs the in-place V1.2 -> V1.3 Windows repair simulation and verifies user data survival;
- `tests/update_smoke.gd` checks version comparison, manifest URLs, RSA verification and tamper rejection;
- `tests/version_sync_test.ps1` checks project/Android/manifest synchronization;
- `tests/windows_updater_test.ps1` exercises the transactional Windows updater;
- Android CI validates package metadata and installs/launches the produced test APK on Android 35;
- production Android build additionally verifies the pinned signing certificate of both the configured keystore and the finished APK.
