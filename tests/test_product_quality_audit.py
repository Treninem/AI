from pathlib import Path
import importlib.util
import subprocess


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "product_quality_audit", ROOT / "tools" / "product_quality_audit.py"
)
assert SPEC and SPEC.loader
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


def test_tracked_file_byte_ledger_is_complete_and_critical_free() -> None:
    report = AUDIT.audit(ROOT)
    tracked = subprocess.check_output(["git", "ls-files"], cwd=ROOT, text=True).splitlines()
    assert report["summary"]["tracked_files"] == len(tracked)
    assert report["summary"]["audited_files"] == len(tracked)
    assert report["summary"]["total_bytes"] > 0
    assert report["summary"]["critical"] == 0, report["issues"]
    rows = report["files"]
    assert len({row["path"] for row in rows}) == len(rows)
    assert all(len(row["sha256"]) == 64 for row in rows)


def test_audit_states_runtime_render_and_performance_limitations() -> None:
    report = AUDIT.audit(ROOT)
    limitations = " ".join(report["limitations"])
    assert "runtime" in limitations
    assert "pixel" in limitations
    assert "performance" in limitations
