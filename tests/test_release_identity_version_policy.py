from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _version(value: str) -> tuple[int, int, int, int]:
    clean = value.strip().lstrip("Vv")
    parts = tuple(int(p) for p in clean.split("."))
    assert len(parts) == 4
    return parts  # type: ignore[return-value]


def test_release_identity_matches_manifest_and_package_contract() -> None:
    identity = json.loads((ROOT / "update/release_identity.json").read_text(encoding="utf-8"))
    manifest = json.loads((ROOT / "update/manifest.template.json").read_text(encoding="utf-8"))
    export = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")

    assert identity["schema_version"] == 1
    assert identity["android_package"] == "com.aurorafox.ai"
    assert identity["android_alias"] == "aurorafox"
    assert re.fullmatch(r"(?:[0-9A-F]{2}:){31}[0-9A-F]{2}", identity["android_signing_cert_sha256"])
    assert re.fullmatch(r"[0-9a-f]{64}", identity["update_signing_public_key_sha256"])
    assert manifest["compatibility"]["legacy_repair_required_through"] == identity["legacy_repair_required_through"]
    assert manifest["compatibility"]["signed_update_floor"] == identity["signed_update_floor"]
    assert _version(identity["signed_update_floor"]) > _version(identity["legacy_repair_required_through"])
    assert 'package/unique_name="com.aurorafox.ai"' in export
    assert "update/release_public.pub" in export


def test_pinned_update_public_key_fingerprint_is_real() -> None:
    public_key = ROOT / "update/release_public.pub"
    expected = (ROOT / "update/release_public_fingerprint.sha256").read_text(encoding="utf-8").split()[0].lower()
    identity = json.loads((ROOT / "update/release_identity.json").read_text(encoding="utf-8"))
    der = subprocess.run(
        ["openssl", "pkey", "-pubin", "-in", str(public_key), "-outform", "DER"],
        check=True,
        capture_output=True,
    ).stdout
    actual = hashlib.sha256(der).hexdigest()
    assert actual == expected == identity["update_signing_public_key_sha256"]


def test_pinned_android_certificate_fingerprint_is_real() -> None:
    identity = json.loads((ROOT / "update/release_identity.json").read_text(encoding="utf-8"))
    expected = identity["android_signing_cert_sha256"].replace(":", "").lower()
    declared = (ROOT / "release/android_release_certificate_sha256.txt").read_text(encoding="utf-8").strip().replace(":", "").lower()
    out = subprocess.run(
        ["openssl", "x509", "-in", str(ROOT / "release/android_release_certificate.pem"), "-noout", "-fingerprint", "-sha256"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    actual = out.split("=", 1)[1].replace(":", "").lower()
    assert actual == declared == expected


def test_production_android_build_rejects_wrong_signing_identity() -> None:
    build = (ROOT / "build/build_android.ps1").read_text(encoding="utf-8")
    assert "Get-PinnedReleaseIdentity" in build
    assert "android_signing_cert_sha256" in build
    assert "Android release keystore certificate mismatch" in build
    assert "Built APK signing certificate mismatch" in build
    assert "update/release_identity.json" in build


def test_release_workflow_signs_manifest_and_checks_update_key_pair() -> None:
    workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
    assert "AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64" in workflow
    assert "update/release_public.pub" in workflow
    assert "openssl pkey -in" in workflow
    assert "openssl dgst -sha256 -sign" in workflow
    assert "openssl dgst -sha256 -verify" in workflow
    for asset in (
        "AuroraFox-Windows.zip",
        "AuroraFox_Setup_Windows.exe",
        "AuroraFox-Android.apk",
        "update.json",
        "update.sig",
    ):
        assert asset in workflow


def test_release_android_emulator_installs_the_signed_apk_without_cross_line_shell_state() -> None:
    workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
    emulator = workflow.split("- name: Install and launch signed APK on Android 35", 1)[1].split("- name: Upload Android artifact", 1)[0]
    assert "adb install -r dist/AuroraFox-Android.apk" in emulator
    assert "apk='dist/AuroraFox-Android.apk'" not in emulator
    assert 'adb install -r "$apk"' not in emulator


def test_release_windows_smokes_wait_only_for_the_aurorafox_parent_process() -> None:
    workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
    assert workflow.count(". .\\tests\\windows_bounded_process.ps1") >= 2
    assert "-Phase 'release-exported-app' -TimeoutSeconds 120" in workflow
    assert "-Phase 'release-installed-app' -TimeoutSeconds 120" in workflow
    assert "Start-Process -FilePath $exe -ArgumentList @('--headless','--quit-after','3') -PassThru -Wait" not in workflow


def test_repair_releases_cannot_occupy_stable_latest() -> None:
    workflow = (ROOT / ".github/workflows/updater-repair-validation.yml").read_text(encoding="utf-8")
    assert "repair-v1.2-windows" in workflow
    assert "repair-v1.3-windows" in workflow
    assert "--prerelease" in workflow
    assert "--latest=false" in workflow
    assert "AuroraFox Windows Package CI" in workflow
    assert "windows_v13_bridge_smoke.ps1" in workflow


def test_version_policy_is_hierarchical_and_test_first() -> None:
    script = (ROOT / "build/set_version.ps1").read_text(encoding="utf-8")
    agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
    master = (ROOT / "docs/PROJECT_MASTER_LOG.md").read_text(encoding="utf-8")

    assert "'major' { $major++; $minor = 0; $patch = 0; $build = 0 }" in script
    assert "'minor' { $minor++; $patch = 0; $build = 0 }" in script
    assert "'patch' { $patch++; $build = 0 }" in script
    assert "'build' { $build++ }" in script
    assert "strictly newer" in script
    assert "test first, version last" in agents
    assert "must not be bumped before" in agents
    assert "ЖЁСТКОЕ ПРАВИЛО ВЕРСИОНИРОВАНИЯ" in master


def test_current_version_does_not_exceed_declared_signed_floor_before_release() -> None:
    state = json.loads((ROOT / "project/version.json").read_text(encoding="utf-8"))
    identity = json.loads((ROOT / "update/release_identity.json").read_text(encoding="utf-8"))
    assert _version(state["numeric"]) <= _version(identity["signed_update_floor"])
    assert state["version"] == "V" + state["numeric"]
