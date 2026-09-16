from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / "benchmarks" / "knowledge"


def load_batch():
    path = BENCH / "run_resilience_batch.py"
    spec = importlib.util.spec_from_file_location("knowledge_resilience_batch", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(BENCH))
    try:
        spec.loader.exec_module(module)
    finally:
        sys.path.remove(str(BENCH))
    return module


class KnowledgeResilienceBatchTests(unittest.TestCase):
    def test_report_passed_supports_probe_and_scaling_schemas(self) -> None:
        batch = load_batch()
        self.assertTrue(batch.report_passed({"ok": True}))
        self.assertFalse(batch.report_passed({"ok": False}))
        self.assertTrue(batch.report_passed({"hard_correctness": {"passed": True}}))
        self.assertFalse(batch.report_passed({"hard_correctness": {"passed": False}}))
        self.assertFalse(batch.report_passed({}))

    def test_registry_blocker_is_relative_not_absolute(self) -> None:
        batch = load_batch()
        clean = {
            "relative_performance": {
                "suspected_quadratic_registry": False,
                "n_2n_4n": [
                    {"from_n": 16, "to_n": 32, "time_ratio": 2.1},
                    {"from_n": 32, "to_n": 64, "time_ratio": 2.2},
                ],
            }
        }
        bad_flag = {
            "relative_performance": {
                "suspected_quadratic_registry": True,
                "n_2n_4n": [
                    {"from_n": 16, "to_n": 32, "time_ratio": 3.8},
                    {"from_n": 32, "to_n": 64, "time_ratio": 3.7},
                ],
            }
        }
        hidden_bad_ratio = {
            "relative_performance": {
                "suspected_quadratic_registry": False,
                "n_2n_4n": [
                    {"from_n": 16, "to_n": 32, "time_ratio": 2.1},
                    {"from_n": 32, "to_n": 64, "time_ratio": 3.8},
                ],
            }
        }
        incomplete = {
            "relative_performance": {
                "suspected_quadratic_registry": False,
                "n_2n_4n": [{"from_n": 16, "to_n": 32, "time_ratio": 2.1}],
            }
        }
        self.assertEqual(batch.registry_performance_blockers(clean), [])
        self.assertIn("suspected_quadratic_registry", batch.registry_performance_blockers(bad_flag))
        self.assertIn("suspected_quadratic_registry", batch.registry_performance_blockers(hidden_bad_ratio))
        self.assertIn("registry_doubling_evidence_incomplete", batch.registry_performance_blockers(incomplete))
        self.assertIn("registry_relative_performance_missing", batch.registry_performance_blockers({}))

    def test_batch_wires_required_race_scaling_and_failure_evidence(self) -> None:
        text = (BENCH / "run_resilience_batch.py").read_text(encoding="utf-8")
        required = [
            "concurrency_race_probe.gd",
            "record_dedupe_shared_source_probe.gd",
            "dedupe_alias_removal_probe.gd",
            "legacy_unregistered_rollback_probe.gd",
            "write_failure_rollback_probe.gd",
            "registry_truncated_temp_probe.gd",
            "run_interrupted_import_recovery.py",
            "run_interrupted_removal_recovery.py",
            "run_registry_scaling.py",
            "suspected_quadratic_registry",
            '"network_required": False',
            '"external_runtime_required": False',
            '"ollama_required": False',
            'report_path.unlink(missing_ok=True)',
            '"fresh_report": fresh_report',
        ]
        for marker in required:
            self.assertIn(marker, text)

    def test_registry_scaling_warms_same_isolated_windows_profile(self) -> None:
        text = (BENCH / "run_registry_scaling.py").read_text(encoding="utf-8")
        self.assertIn("import run_knowledge_benchmark_portable as portable", text)
        self.assertIn("portable.warm_isolated_windows_profile(", text)
        self.assertIn('"isolated_profile_warmup": warm', text)
        self.assertLess(
            text.index("portable.warm_isolated_windows_profile("),
            text.index("subprocess.Popen("),
        )

    def test_missing_child_report_fails_closed(self) -> None:
        batch = load_batch()
        with tempfile.TemporaryDirectory() as tmp:
            payload = batch.load_report(Path(tmp) / "missing.json")
        self.assertFalse(payload["ok"])
        self.assertIn("cannot read child report", payload["error"])

    def test_run_child_cannot_reuse_stale_success_report(self) -> None:
        batch = load_batch()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            report = root / "child.json"
            report.write_text('{"ok": true}', encoding="utf-8")
            result = batch.run_child(
                "stale_probe",
                [sys.executable, "-c", "pass"],
                report,
                root,
                30,
            )
        self.assertFalse(result["ok"])
        self.assertFalse(result["fresh_report"])
        self.assertEqual(result["return_code"], 0)
        self.assertEqual(result["report"].get("error"), "fresh child report missing")


if __name__ == "__main__":
    unittest.main()
