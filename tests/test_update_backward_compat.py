from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEGACY_MANIFEST_URL = "https://github.com/Treninem/AI/releases/latest/download/update.json"
WINDOWS_ASSET = "AuroraFox-Windows.zip"
ANDROID_ASSET = "AuroraFox-Android.apk"
LEGACY_REPAIR_THROUGH = "1.2.0.0"
SIGNED_UPDATE_FLOOR = "1.3.0.0"
APP_ID = "8C21F024-53DE-4FA3-A150-78C80829B6BF"


def legacy_manifest_parser_accepts(manifest: dict) -> bool:
    """Model the legacy manifest fields. Parsing does not imply trust can succeed."""
    if not isinstance(manifest, dict):
        return False
    if not str(manifest.get("version", "")):
        return False
    if str(manifest.get("channel", "stable")) != "stable":
        return False
    assets = manifest.get("assets")
    if not isinstance(assets, dict):
        return False
    for platform in ("windows", "android"):
        asset = assets.get(platform)
        if not isinstance(asset, dict):
            return False
        if not str(asset.get("url", "")):
            return False
        if len(str(asset.get("sha256", ""))) < 32:
            return False
    return True


def test_current_updater_keeps_permanent_latest_manifest_url() -> None:
    source = (ROOT / "update" / "update_manager.gd").read_text(encoding="utf-8")
    assert f'const MANIFEST_URL := "{LEGACY_MANIFEST_URL}"' in source
    assert "releases/latest/download/update.sig" in source


def test_manifest_template_is_legacy_readable_but_does_not_claim_legacy_direct_update() -> None:
    template = json.loads((ROOT / "update" / "manifest.template.json").read_text(encoding="utf-8"))
    test_manifest = json.loads(json.dumps(template))
    test_manifest["version"] = "9.9.9.9"
    test_manifest["channel"] = "stable"
    test_manifest["assets"]["windows"]["url"] = f"https://example.invalid/{WINDOWS_ASSET}"
    test_manifest["assets"]["windows"]["sha256"] = "a" * 64
    test_manifest["assets"]["android"]["url"] = f"https://example.invalid/{ANDROID_ASSET}"
    test_manifest["assets"]["android"]["sha256"] = "b" * 64
    assert legacy_manifest_parser_accepts(test_manifest)
    compatibility = template.get("compatibility", {})
    assert compatibility.get("legacy_manifest") is True
    assert compatibility.get("legacy_manifest_readable") is True
    assert compatibility.get("legacy_direct_update") is False
    assert compatibility.get("legacy_repair_required_through") == LEGACY_REPAIR_THROUGH
    assert compatibility.get("signed_direct_update") is True
    assert compatibility.get("signed_update_floor") == SIGNED_UPDATE_FLOOR


def test_release_keeps_stable_asset_names_and_latest_update_json() -> None:
    workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8")
    assert f"/{WINDOWS_ASSET}" in workflow
    assert f"/{ANDROID_ASSET}" in workflow
    assert "dist/update.json" in workflow
    assert "dist/update.sig" in workflow
    assert "gh release create" in workflow
    release_block = workflow.split("gh release create", 1)[1]
    for name in (WINDOWS_ASSET, ANDROID_ASSET, "update.json", "update.sig"):
        assert name in release_block


def test_release_manifest_generator_preserves_legacy_top_level_and_asset_fields() -> None:
    workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8")
    for literal in (
        "'version': version",
        "'channel': 'stable'",
        "'mandatory': False",
        "'assets': {",
        "'windows': {'url': base + '/AuroraFox-Windows.zip', 'sha256': win_sha",
        "'android': {'url': base + '/AuroraFox-Android.apk', 'sha256': apk_sha",
    ):
        assert literal in workflow


def test_update_signature_is_required_for_signed_generation() -> None:
    workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8")
    generate = workflow.index("Generate verified update manifest and release evidence")
    sign = workflow.index("Sign update manifest with pinned AuroraFox release key")
    publish = workflow.index("Create draft GitHub Release")
    assert generate < sign < publish
    assert "openssl dgst -sha256 -sign" in workflow[sign:publish]
    assert "dist/update.json" in workflow[generate:publish]
    assert "dist/update.sig" in workflow[sign:publish]


def test_android_identity_and_windows_full_zip_strategy_are_stable() -> None:
    workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8")
    assert "package: name='com.aurorafox.ai'" in workflow
    assert "Compress-Archive -Path build\\windows\\*" in workflow
    assert WINDOWS_ASSET in workflow
    template = json.loads((ROOT / "update" / "manifest.template.json").read_text(encoding="utf-8"))
    compatibility = template["compatibility"]
    assert "full_zip_replace" in compatibility["windows_strategy"]
    assert compatibility["android_strategy"] == "same_package_same_signing_identity_required"


def test_public_update_key_is_embedded_in_signed_generation_exports() -> None:
    presets = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    windows, android = presets.split("[preset.1]", 1)
    assert 'include_filter="update/release_public.pub"' in windows
    # Android additionally ships the built-in AuroraFox Core weights, but the
    # pinned update trust root must remain in the same export.
    assert 'include_filter="update/release_public.pub,models/aurorafox-core.gguf"' in android
    updater = (ROOT / "update" / "update_manager.gd").read_text(encoding="utf-8")
    assert 'const PUBLIC_KEY_PATH := "res://update/release_public.pub"' in updater


def test_production_android_release_identity_is_pinned_end_to_end() -> None:
    setup = (ROOT / "build" / "setup_release_signing.ps1").read_text(encoding="utf-8")
    android_build = (ROOT / "build" / "build_android.ps1").read_text(encoding="utf-8")
    readiness = (ROOT / "build" / "bridge_release_readiness.ps1").read_text(encoding="utf-8")
    workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8")

    for needle in (
        "update/release_identity.json",
        "android_signing_cert_sha256",
        "update_manifest_public_key_sha256",
        "signed_update_floor = '1.3.0.0'",
        "Do not regenerate either identity for normal updates",
    ):
        assert needle in setup

    for needle in (
        "update/release_identity.json",
        "GODOT_ANDROID_KEYSTORE_RELEASE_PATH",
        "GODOT_ANDROID_KEYSTORE_RELEASE_USER",
        "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD",
        "Built APK signing certificate mismatch",
        "AURORAFOX_ANDROID_RELEASE_IDENTITY_OK",
        "certificate SHA-256 digest",
    ):
        assert needle in android_build

    assert "update/release_identity.json" in readiness
    assert "Android cert=" in readiness
    assert "AURORA_ANDROID_KEYSTORE_BASE64" in workflow
    assert "GODOT_ANDROID_KEYSTORE_RELEASE_PATH" in workflow
    assert "build_android.ps1" in workflow


def test_release_private_material_is_git_ignored_and_only_public_pins_are_committed() -> None:
    ignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    setup = (ROOT / "build" / "setup_release_signing.ps1").read_text(encoding="utf-8")
    assert "build/private/" in ignore
    assert "*.keystore" in ignore
    assert "*.jks" in ignore
    assert "aurora_update_signing_private.pem" in setup
    assert "aurorafox-android-release.jks" in setup
    assert "git add update/release_public.pub update/release_identity.json" in setup
    assert "git add build/private" not in setup


def test_windows_v12_repair_uses_same_inno_identity_and_is_ci_verified() -> None:
    current_iss = (ROOT / "build" / "AuroraFox.iss").read_text(encoding="utf-8")
    fixture_iss = (ROOT / "build" / "AuroraFox_V12_BridgeFixture.iss").read_text(encoding="utf-8")
    for text in (current_iss, fixture_iss):
        assert f"AppId={{{{{APP_ID}}}" in text
    assert "bridge_repair.txt" in current_iss
    assert "v1.2-marker.txt" in current_iss

    bridge_test = (ROOT / "tests" / "windows_v12_bridge_smoke.ps1").read_text(encoding="utf-8")
    assert "AURORA_WINDOWS_V12_TO_V13_BRIDGE_OK" in bridge_test
    assert "bridge-v12-sentinel.txt" in bridge_test
    assert "previous=1\\.2\\.0\\.0" in bridge_test
    assert "current=1\\.3\\.0\\.0" in bridge_test

    workflow = (ROOT / ".github" / "workflows" / "windows-package-ci.yml").read_text(encoding="utf-8")
    assert "Verify V1.2 to V1.3 in-place bridge" in workflow
    assert "AuroraFox-V1.2-to-V$version-Repair-Windows.exe" in workflow
    assert "publish-v12-repair:" in workflow
    assert "repair-v1.2-windows" in workflow
    assert "AuroraFox-V1.2-Repair-Windows.exe" in workflow
    assert "--latest=false" in workflow
    assert "github.event_name == 'push' && github.ref == 'refs/heads/main'" in workflow


def test_documentation_states_v12_repair_and_android_signing_boundary() -> None:
    docs = (ROOT / "update" / "README.md").read_text(encoding="utf-8")
    assert "V1.2.0.0" in docs
    assert re.search(r"repair|bridge", docs, re.IGNORECASE)
    assert re.search(r"same.+sign|signing.+same", docs, re.IGNORECASE | re.DOTALL)
    assert "V1.3.0.0" in docs
    assert "releases/tag/repair-v1.2-windows" in docs
