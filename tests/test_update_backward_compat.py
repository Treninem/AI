from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEGACY_MANIFEST_URL = "https://github.com/Treninem/AI/releases/latest/download/update.json"
WINDOWS_ASSET = "AuroraFox-Windows.zip"
ANDROID_ASSET = "AuroraFox-Android.apk"
LEGACY_REPAIR_THROUGH = "1.3.0.0"
REPAIR_BOOTSTRAP_VERSION = "1.3.0.0"
SIGNED_UPDATE_FLOOR = "1.4.0.0"
APP_ID = "8C21F024-53DE-4FA3-A150-78C80829B6BF"


def legacy_manifest_parser_accepts(manifest: dict) -> bool:
    """Model stable manifest fields; readability never bypasses trust verification."""
    if not isinstance(manifest, dict) or not str(manifest.get("version", "")):
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
        if not str(asset.get("url", "")) or len(str(asset.get("sha256", ""))) < 32:
            return False
    return True


def test_current_updater_keeps_permanent_latest_manifest_url() -> None:
    source = (ROOT / "update/update_manager.gd").read_text(encoding="utf-8")
    assert f'const MANIFEST_URL := "{LEGACY_MANIFEST_URL}"' in source
    assert "releases/latest/download/update.sig" in source
    assert 'const PUBLIC_KEY_PATH := "res://update/release_public.pub"' in source


def test_manifest_template_requires_repair_through_v13_and_signed_v14_floor() -> None:
    template = json.loads((ROOT / "update/manifest.template.json").read_text(encoding="utf-8"))
    test_manifest = json.loads(json.dumps(template))
    test_manifest["version"] = "9.9.9.9"
    for platform, name, digest in (("windows", WINDOWS_ASSET, "a" * 64), ("android", ANDROID_ASSET, "b" * 64)):
        test_manifest["assets"][platform]["url"] = f"https://example.invalid/{name}"
        test_manifest["assets"][platform]["sha256"] = digest
    assert legacy_manifest_parser_accepts(test_manifest)
    compatibility = template["compatibility"]
    assert compatibility["legacy_manifest"] is True
    assert compatibility["legacy_manifest_readable"] is True
    assert compatibility["legacy_direct_update"] is False
    assert compatibility["legacy_repair_required_through"] == LEGACY_REPAIR_THROUGH
    assert compatibility["repair_bootstrap_version"] == REPAIR_BOOTSTRAP_VERSION
    assert compatibility["repair_release_tags"] == ["repair-v1.2-windows", "repair-v1.3-windows"]
    assert compatibility["signed_direct_update"] is True
    assert compatibility["signed_update_floor"] == SIGNED_UPDATE_FLOOR
    assert "trust_root_repair" in compatibility["windows_strategy"]
    assert compatibility["android_strategy"] == "same_package_same_permanent_signing_identity_required"


def test_release_keeps_stable_asset_names_and_signed_latest_contract() -> None:
    workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
    for name in (WINDOWS_ASSET, ANDROID_ASSET, "update.json", "update.sig"):
        assert name in workflow
    assert "gh release create" in workflow
    assert "openssl dgst -sha256 -sign" in workflow
    assert "openssl dgst -sha256 -verify" in workflow
    assert "AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64" in workflow


def test_repair_releases_are_separate_prereleases_not_stable_latest() -> None:
    workflow = (ROOT / ".github/workflows/updater-repair-validation.yml").read_text(encoding="utf-8")
    assert "repair-v1.2-windows" in workflow
    assert "repair-v1.3-windows" in workflow
    assert "--prerelease" in workflow
    assert "--latest=false" in workflow
    assert "releases/latest" not in workflow
    assert "Repair release illegally occupies stable latest" in workflow


def test_repair_assets_publish_only_from_signed_v14_or_newer_floor() -> None:
    workflow = (ROOT / ".github/workflows/updater-repair-validation.yml").read_text(encoding="utf-8")
    assert "Check signed-floor repair publication eligibility" in workflow
    assert "eligible = ver(current) >= ver(floor) and ver(current) > ver(legacy)" in workflow
    assert "if: steps.floor.outputs.eligible == 'true'" in workflow
    assert 'for old in 1.2 1.3' in workflow
    assert 'source="dist/AuroraFox-V${version}-Setup-Windows.exe"' in workflow
    assert 'stable="dist/AuroraFox-V${old}-Repair-Windows.exe"' in workflow
    assert 'gh release upload "$tag" "$stable" "$sums" --clobber' in workflow
    assert "AURORA_REPAIR_RELEASES_READY" in workflow


def test_windows_package_is_only_artifact_producer_not_repair_release_writer() -> None:
    workflow = (ROOT / ".github/workflows/windows-package-ci.yml").read_text(encoding="utf-8")
    assert "publish-v12-repair" not in workflow
    assert "gh release create" not in workflow
    assert "tests/windows_v13_bridge_smoke.ps1" in workflow
    assert "update\\release_public.pub" in workflow


def test_public_update_key_is_embedded_in_windows_and_android() -> None:
    presets = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    windows, android = presets.split("[preset.1]", 1)
    assert 'include_filter="update/release_public.pub"' in windows
    assert "update/release_public.pub" in android
    assert "models/aurorafox-core.gguf" in android


def test_production_android_release_identity_is_pinned_end_to_end() -> None:
    identity = json.loads((ROOT / "update/release_identity.json").read_text(encoding="utf-8"))
    android_build = (ROOT / "build/build_android.ps1").read_text(encoding="utf-8")
    readiness = (ROOT / "build/bridge_release_readiness.ps1").read_text(encoding="utf-8")
    workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")

    assert identity["android_package"] == "com.aurorafox.ai"
    assert identity["android_alias"] == "aurorafox"
    assert identity["signed_update_floor"] == SIGNED_UPDATE_FLOOR
    assert identity["legacy_repair_required_through"] == LEGACY_REPAIR_THROUGH
    for needle in (
        "update/release_identity.json",
        "android_signing_cert_sha256",
        "GODOT_ANDROID_KEYSTORE_RELEASE_PATH",
        "Built APK signing certificate mismatch",
        "AURORAFOX_ANDROID_RELEASE_IDENTITY_OK",
    ):
        assert needle in android_build
    assert "V1.4 signed-update readiness" in readiness
    assert "AURORA_ANDROID_KEYSTORE_BASE64" in workflow
    assert "build_android.ps1" in workflow


def test_private_signing_material_is_git_ignored() -> None:
    ignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    setup = (ROOT / "build/setup_release_signing.ps1").read_text(encoding="utf-8")
    assert "build/private/" in ignore
    assert "*.keystore" in ignore
    assert "aurora_update_signing_private.pem" in setup
    assert "aurorafox-android-release.jks" in setup
    assert "git add build/private" not in setup


def test_windows_v12_and_v13_repairs_share_same_inno_identity() -> None:
    current_iss = (ROOT / "build/AuroraFox.iss").read_text(encoding="utf-8")
    v12_fixture = (ROOT / "build/AuroraFox_V12_BridgeFixture.iss").read_text(encoding="utf-8")
    v13_fixture = (ROOT / "build/AuroraFox_V13_BridgeFixture.iss").read_text(encoding="utf-8")
    for text in (current_iss, v12_fixture, v13_fixture):
        assert f"AppId={{{{{APP_ID}}}" in text
    assert "bridge_repair.txt" in current_iss
    assert "v1.2-marker.txt" in current_iss
    assert "v1.3-marker.txt" in current_iss

    v12_test = (ROOT / "tests/windows_v12_bridge_smoke.ps1").read_text(encoding="utf-8")
    v13_test = (ROOT / "tests/windows_v13_bridge_smoke.ps1").read_text(encoding="utf-8")
    assert "bridge-v12-sentinel.txt" in v12_test
    assert "AURORA_WINDOWS_V12_TO_CURRENT_BRIDGE_OK" in v12_test
    assert "bridge-v13-sentinel.txt" in v13_test
    assert "release_public.pub" in v13_test
    assert "AURORA_WINDOWS_V13_TRUST_ROOT_REPAIR_OK" in v13_test


def test_old_clients_missing_trust_root_get_repair_state_not_unsigned_install() -> None:
    updater = (ROOT / "update/update_manager.gd").read_text(encoding="utf-8")
    assert '"repair_required": true' in updater
    assert "untrusted_remote" in updater
    assert "Автоматическая установка заблокирована безопасностью" in updater
    assert "_verify_manifest_signature" in updater
    assert "_verify_sha256" in updater


def test_documentation_names_v12_v13_repair_and_v14_floor() -> None:
    docs = (ROOT / "docs/PROJECT_MASTER_LOG.md").read_text(encoding="utf-8")
    assert "V1.2/V1.3" in docs or ("V1.2" in docs and "V1.3" in docs)
    assert "V1.4.0.0" in docs
    assert re.search(r"repair|bridge", docs, re.IGNORECASE)
