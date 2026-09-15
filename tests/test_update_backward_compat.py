from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEGACY_MANIFEST_URL = "https://github.com/Treninem/AI/releases/latest/download/update.json"
WINDOWS_ASSET = "AuroraFox-Windows.zip"
ANDROID_ASSET = "AuroraFox-Android.apk"


def legacy_updater_accepts(manifest: dict) -> bool:
    """Model the first embedded AuroraFox updater contract from 2026-08-19."""
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


def test_current_updater_keeps_original_latest_manifest_url() -> None:
    source = (ROOT / "update" / "update_manager.gd").read_text(encoding="utf-8")
    assert f'const MANIFEST_URL := "{LEGACY_MANIFEST_URL}"' in source
    assert "releases/latest/download/update.sig" in source


def test_manifest_template_remains_readable_by_first_embedded_updater() -> None:
    template = json.loads((ROOT / "update" / "manifest.template.json").read_text(encoding="utf-8"))
    template["version"] = "9.9.9.9"
    template["channel"] = "stable"
    template["assets"]["windows"]["url"] = f"https://example.invalid/{WINDOWS_ASSET}"
    template["assets"]["windows"]["sha256"] = "a" * 64
    template["assets"]["android"]["url"] = f"https://example.invalid/{ANDROID_ASSET}"
    template["assets"]["android"]["sha256"] = "b" * 64
    assert legacy_updater_accepts(template)
    assert template.get("schema_version") == 1
    compatibility = template.get("compatibility", {})
    assert compatibility.get("legacy_manifest") is True
    assert compatibility.get("direct_update") is True


def test_release_keeps_legacy_asset_names_and_latest_update_json() -> None:
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


def test_update_signature_is_additive_not_a_replacement_for_legacy_manifest() -> None:
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
    assert WINDOWS_ASSET in workflow
    template = json.loads((ROOT / "update" / "manifest.template.json").read_text(encoding="utf-8"))
    compatibility = template["compatibility"]
    assert compatibility["windows_strategy"] == "full_zip_replace"
    assert compatibility["android_strategy"] == "same_package_signed_apk"


def test_pre_updater_builds_are_documented_as_one_time_manual_bootstrap() -> None:
    docs = (ROOT / "update" / "README.md").read_text(encoding="utf-8")
    assert "2026-08-19" in docs
    assert re.search(r"manual.+bootstrap|bootstrap.+manual", docs, re.IGNORECASE | re.DOTALL)
