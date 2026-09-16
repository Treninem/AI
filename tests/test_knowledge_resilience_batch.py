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
                "n_2n_4n": [{"time_ratio": 2.1}],
            }
        }
        bad = {
            "relative_performance": {
                "suspected_quadratic_registry": True,
                "n_2n_4n": [{"time_ratio": 3.8}],
            }
        }
        self.assertEqual(batch.registry_performance_blockers(clean), [])
        self.assertEqual(batch.registry_performance_blockers(bad), ["suspected_quadratic_registry"])

    def test_batch_wires_required_race_scaling_and_failure_evidence(self) -> None:
        text = (BENCH / "run_resilience_batch.py").read_text(encoding="utf-8")
        required = [
            "concurrency_race_probe.gd",
            "record_dedupe_shared_source_probe.gd",
            "dedupe_alias_removal_probe.gd",
            "write_failure_rollback_probe.gd",
            "registry_truncated_temp_probe.gd",
            "run_interrupted_import_recovery.py",
            "run_interrupted_removal_recovery.py",
            "run_registry_scaling.py",
            "suspected_quadratic_registry",
            '"network_required": False',
            '"external_runtime_required": False',
            '"ollama_required": False',
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


if __name__ == "__main__":
    unittest.main()
