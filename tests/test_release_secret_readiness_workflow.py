from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "release.yml"


def _text() -> str:
    return WORKFLOW.read_text(encoding="utf-8")


def test_preflight_has_a_manual_secrets_only_mode() -> None:
    text = _text()
    assert "workflow_dispatch:" in text
    assert "secrets_only:" in text
    assert "type: boolean" in text
    assert "default: false" in text
    assert "secret-readiness:" in text
    assert "github.event_name == 'workflow_dispatch' && inputs.secrets_only" in text
    assert "github.event_name != 'workflow_dispatch' || !inputs.secrets_only" in text


def test_secrets_only_mode_cannot_reach_build_or_publish_jobs() -> None:
    text = _text()
    core = text.index("  core-gates:")
    windows = text.index("  windows:")
    android = text.index("  android:")
    publish = text.index("  publish:")
    assert "if: github.event_name != 'workflow_dispatch' || !inputs.secrets_only" in text[core:windows]
    assert "needs: core-gates" in text[windows:android]
    assert "needs: core-gates" in text[android:publish]
    assert "if: startsWith(github.ref, 'refs/tags/v')" in text[publish:]


def test_all_release_secrets_are_required_without_printing_values() -> None:
    text = _text()
    for name in (
        "AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64",
        "AURORA_ANDROID_KEYSTORE_BASE64",
        "AURORA_ANDROID_KEYSTORE_USER",
        "AURORA_ANDROID_KEYSTORE_PASSWORD",
    ):
        assert f"secrets.{name}" in text
        assert f"{name} is missing." in text
    assert "set -x" not in text
    assert '::add-mask::$KEYSTORE_USER' in text
    assert '::add-mask::$KEYSTORE_PASSWORD' in text


def test_private_keys_must_match_the_pinned_release_identity() -> None:
    text = _text()
    assert "update/release_identity.json" in text
    assert "openssl pkey" in text
    assert "update_signing_public_key_sha256" in text
    assert "keytool -list" in text
    assert "keytool -exportcert" in text
    assert "android_signing_cert_sha256" in text
    assert "AURORAFOX_RELEASE_SIGNING_SECRETS_READY" in text
