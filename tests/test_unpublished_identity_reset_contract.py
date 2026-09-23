from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / "build/setup_release_signing.ps1").read_text(encoding="utf-8")
KEYGEN = (ROOT / "build/create_update_signing_key.ps1").read_text(encoding="utf-8")


def test_reset_requires_an_explicit_confirmation_and_prefloor_version() -> None:
    assert "[switch]$ResetUnpublishedIdentity" in SCRIPT
    assert "RESET_UNPUBLISHED_AURORAFOX_RELEASE_IDENTITY" in SCRIPT
    assert "[Version]$signedFloor" in SCRIPT
    assert "reset is forbidden at or above the signed floor" in SCRIPT


def test_dependencies_are_validated_before_public_identity_is_archived() -> None:
    reset_offset = SCRIPT.index("if ($ResetUnpublishedIdentity)")
    assert SCRIPT.index("$keytool = Find-Keytool") < reset_offset
    assert SCRIPT.index("auth status") < reset_offset
    assert "$psi.FileName = $script:ghExecutable" in SCRIPT


def test_reset_never_overwrites_existing_private_identity() -> None:
    assert "Refusing identity reset because an update private key exists" in SCRIPT
    assert "Refusing identity reset because an Android release keystore exists" in SCRIPT
    assert "retired-unpublished-identity-" in SCRIPT
    assert "Copy-Item -LiteralPath $path" in SCRIPT
    assert "Remove-Item -LiteralPath $path" in SCRIPT


def test_reset_regenerates_every_public_identity_pin() -> None:
    for needle in (
        "release_public.pub",
        "release_public_fingerprint.sha256",
        "release_identity.json",
        "android_release_certificate.pem",
        "android_release_certificate_sha256.txt",
        "Format-ColonFingerprint",
    ):
        assert needle in SCRIPT


def test_private_material_stays_local_and_existing_secret_uploader_is_reused() -> None:
    assert "build/private" in (ROOT / ".gitignore").read_text(encoding="utf-8")
    for secret in (
        "AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64",
        "AURORA_ANDROID_KEYSTORE_BASE64",
        "AURORA_ANDROID_KEYSTORE_USER",
        "AURORA_ANDROID_KEYSTORE_PASSWORD",
    ):
        assert f"Set-GitHubSecret '{secret}'" in SCRIPT
    assert "GitHub Actions signing secrets configured" in SCRIPT


def test_update_key_generation_is_compatible_with_windows_powershell_51() -> None:
    assert "ExportPkcs8PrivateKey" not in KEYGEN
    assert "ExportSubjectPublicKeyInfo" not in KEYGEN
    assert "Find-OpenSsl" in KEYGEN
    assert "Git\\usr\\bin\\openssl.exe" in KEYGEN
    assert "Invoke-OpenSsl" in KEYGEN
    assert "RedirectStandardError = $true" in KEYGEN


def test_update_key_generation_is_transactional() -> None:
    assert "aurorafox-signing-" in KEYGEN
    assert "Move-Item -LiteralPath $tempPrivate" in KEYGEN
    assert "Move-Item -LiteralPath $tempPublic" in KEYGEN
    assert "Remove-Item -LiteralPath $privatePath,$publicPath,$privateBase64Path" in KEYGEN
    assert "Remove-Item -LiteralPath $tempDir -Recurse" in KEYGEN
