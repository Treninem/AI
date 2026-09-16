from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "verify_core_candidate_bundle", ROOT / "build" / "verify_core_candidate_bundle.py"
)
assert SPEC and SPEC.loader
promotion = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(promotion)

COMPAT_SPEC = importlib.util.spec_from_file_location(
    "test_update_backward_compat", ROOT / "tests" / "test_update_backward_compat.py"
)
assert COMPAT_SPEC and COMPAT_SPEC.loader
update_compat = importlib.util.module_from_spec(COMPAT_SPEC)
COMPAT_SPEC.loader.exec_module(update_compat)


def _sha(data: str) -> str:
    return hashlib.sha256(data.encode("utf-8")).hexdigest()


def _fixture(tmp_path: Path, *, target: str = "scripts/memory_store.gd") -> tuple[Path, Path, dict]:
    project = tmp_path / "project"
    bundle = tmp_path / "bundle"
    base = (
        "class_name PromotionFixture\n"
        "extends RefCounted\n"
        "signal changed(value)\n"
        "# baseline padding keeps bounded safe improvements measurable without source bloat\n"
        "# retrieval remains local deterministic and offline for this promotion fixture\n"
        "func public_api(value):\n"
        "\treturn value\n"
        "func _private_helper():\n"
        "\treturn 1\n"
    )
    candidate = base.replace("\treturn value\n", "\treturn value if value != null else \"\"\n")
    project_target = project / target
    candidate_target = bundle / target
    project_target.parent.mkdir(parents=True, exist_ok=True)
    candidate_target.parent.mkdir(parents=True, exist_ok=True)
    project_target.write_text(base, encoding="utf-8")
    candidate_target.write_text(candidate, encoding="utf-8")
    manifest = {
        "candidate_id": "fixture_001",
        "target": target,
        "base_sha256": _sha(base),
        "candidate_sha256": _sha(candidate),
        "verified": True,
        "promotion": "signed_update",
        "verification": {
            "source_contract": {"ok": True},
            "comparative_review": {"ok": True, "improvement": 1.5},
        },
    }
    bundle.mkdir(parents=True, exist_ok=True)
    (bundle / "candidate.json").write_text(json.dumps(manifest), encoding="utf-8")
    return project, bundle, manifest


def test_verified_bundle_is_rechecked_and_applied(tmp_path: Path) -> None:
    project, bundle, manifest = _fixture(tmp_path)
    report = promotion.verify_bundle(project, bundle, apply=True)
    target = project / manifest["target"]
    assert report["ok"] is True
    assert report["applied"] is True
    assert report["candidate_sha256"] == promotion.sha256_file(target)
    assert report["source_contract"]["ok"] is True
    assert report["promotion_boundary"] == "ci_verified_pr_then_normal_signed_release"


def test_stale_base_hash_is_rejected(tmp_path: Path) -> None:
    project, bundle, manifest = _fixture(tmp_path)
    manifest["base_sha256"] = "0" * 64
    (bundle / "candidate.json").write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(promotion.CandidateVerificationError, match="base SHA-256"):
        promotion.verify_bundle(project, bundle)


def test_protected_target_is_rejected_before_access(tmp_path: Path) -> None:
    project, bundle, manifest = _fixture(tmp_path)
    manifest["target"] = "update/update_manager.gd"
    (bundle / "candidate.json").write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(promotion.CandidateVerificationError, match="allowlist"):
        promotion.verify_bundle(project, bundle)


def test_missing_comparative_review_is_rejected(tmp_path: Path) -> None:
    project, bundle, manifest = _fixture(tmp_path)
    manifest["verification"].pop("comparative_review")
    (bundle / "candidate.json").write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(promotion.CandidateVerificationError, match="comparative-review"):
        promotion.verify_bundle(project, bundle)


def test_independent_contract_rejects_new_process_primitive() -> None:
    original = (
        "class_name X\nextends RefCounted\n"
        "signal changed\n"
        "# padding padding padding padding padding padding padding padding padding padding\n"
        "func public_api():\n\treturn true\n"
    )
    candidate = original.replace(
        "# padding padding padding padding padding padding padding padding padding padding",
        "var result = OS.execute(\"cmd\", []) # padding padding padding padding padding",
    )
    contract = promotion.source_contract(original, candidate, "scripts/memory_store.gd")
    assert contract["ok"] is False
    assert "OS.execute(" in contract["risky_primitive_increases"]


def test_independent_contract_rejects_removed_public_api() -> None:
    original = "class_name X\nextends RefCounted\nsignal changed\nfunc public_api():\n\treturn true\n"
    candidate = "class_name X\nextends RefCounted\nsignal changed\nfunc _replacement():\n\treturn true\n"
    contract = promotion.source_contract(original, candidate, "scripts/agent_core.gd")
    assert contract["ok"] is False
    assert contract["missing_public_functions"] == ["public_api"]


def test_promotion_workflow_keeps_candidate_untrusted_until_verified() -> None:
    workflow = (ROOT / ".github" / "workflows" / "core-candidate-promotion.yml").read_text(encoding="utf-8")
    assert "permissions:\n  contents: read" in workflow
    assert "Checkout trusted main" in workflow
    assert "Checkout untrusted candidate ref separately" in workflow
    assert "path: project" in workflow
    assert "path: submission" in workflow
    assert "persist-credentials: false" in workflow
    assert "project/build/verify_core_candidate_bundle.py" in workflow
    assert "submission/core_candidate_submission" in workflow
    assert "git -C project diff --name-only" in workflow
    assert "needs: verify-candidate" in workflow
    assert "pull-requests: write" in workflow
    assert "git apply --check promotion/core-candidate.patch" in workflow
    assert "Normal branch protection and the standard signed release workflow remain the final release boundary" in workflow
    for secret_name in (
        "AURORA_UPDATE_PRIVATE_KEY",
        "AURORA_ANDROID_KEYSTORE_BASE64",
        "AURORA_ANDROID_KEYSTORE_PASSWORD",
    ):
        assert secret_name not in workflow


def test_signed_release_enforces_v12_v13_repair_and_v14_signed_update_floor() -> None:
    # This file is part of release.yml/core-gates. Keep the bridge pointed at
    # the current compatibility contract instead of duplicating or weakening it.
    update_compat.test_current_updater_keeps_permanent_latest_manifest_url()
    update_compat.test_manifest_template_requires_repair_through_v13_and_signed_v14_floor()
    update_compat.test_release_keeps_stable_asset_names_and_signed_latest_contract()
    update_compat.test_repair_releases_are_separate_prereleases_not_stable_latest()
    update_compat.test_repair_assets_publish_only_from_signed_v14_or_newer_floor()
    update_compat.test_windows_package_is_only_artifact_producer_not_repair_release_writer()
    update_compat.test_public_update_key_is_embedded_in_windows_and_android()
    update_compat.test_production_android_release_identity_is_pinned_end_to_end()
    update_compat.test_private_signing_material_is_git_ignored()
    update_compat.test_windows_v12_and_v13_repairs_share_same_inno_identity()
    update_compat.test_old_clients_missing_trust_root_get_repair_state_not_unsigned_install()
    update_compat.test_documentation_names_v12_v13_repair_and_v14_floor()
