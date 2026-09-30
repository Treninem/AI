import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("owner_control_audit", ROOT / "tools" / "owner_control_audit.py")
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def test_audit_is_machine_readable_and_does_not_claim_incomplete_inventory_is_done():
    report = MODULE.audit()
    assert report["schema"] == "aurorafox.owner-control-audit.v1"
    assert report["files_scanned"] > 100
    assert report["findings"] > 0
    assert report["complete"] is (report["counts"].get("unclassified", 0) == 0)


def test_web_limits_and_security_boundaries_have_explicit_different_classes():
    report = MODULE.audit()
    web = [item for item in report["items"] if item["path"] == "scripts/public_web_manager.gd"]
    assert any(item["class"] == "owner_adjustable" for item in web)
    assert any(item["class"] == "hard_boundary" for item in web)


def test_policy_explains_the_small_set_allowed_to_be_hard_boundaries():
    policy = MODULE.load_policy()
    principle = policy["principle"].lower()
    for required in ["authorization", "access control", "cryptographic", "master-stop", "secret", "untrusted-code"]:
        assert required in principle
