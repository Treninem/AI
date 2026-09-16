from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / "benchmarks" / "knowledge"


def load_gate():
    path = BENCH / "validate_resilience_batch.py"
    spec = importlib.util.spec_from_file_location("knowledge_resilience_gate", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    try:
        spec.loader.exec_module(module)
    finally:
        sys.modules.pop(spec.name, None)
    return module


def good_report():
    names = [
        "concurrency_race",
        "record_dedupe_shared_source",
        "dedupe_alias_removal",
        "legacy_unregistered_rollback",
        "registry_write_failure_rollback",
        "registry_truncated_temp",
        "interrupted_import_recovery",
        "interrupted_removal_recovery",
        "registry_scaling",
    ]
    return {
        "schema": "aurorafox_knowledge_resilience_batch_v1",
        "ok": True,
        "hard_correctness": {"passed": True, "errors": []},
        "self_reliance_contract": {
            "network_required": False,
            "external_runtime_required": False,
            "ollama_required": False,
        },
        "relative_performance": {
            "enforced": True,
            "blockers": [],
            "registry_n_2n_4n": [
                {"from_n": 16, "to_n": 32, "time_ratio": 2.1, "suspected_quadratic_registry": False},
                {"from_n": 32, "to_n": 64, "time_ratio": 2.2, "suspected_quadratic_registry": False},
            ],
        },
        "cases": [{"name": name, "ok": True, "report": {}} for name in names],
    }


class KnowledgeResilienceGateTests(unittest.TestCase):
    def test_complete_report_passes(self) -> None:
        gate = load_gate()
        result = gate.validate_report(good_report())
        self.assertTrue(result["ok"])
        self.assertEqual(result["errors"], [])
        self.assertEqual(len(result["registry_valid_doubling_pairs"]), 2)

    def test_missing_scaling_pairs_fails_closed(self) -> None:
        gate = load_gate()
        report = good_report()
        report["relative_performance"]["registry_n_2n_4n"] = []
        result = gate.validate_report(report)
        self.assertFalse(result["ok"])
        self.assertIn("registry_doubling_evidence_incomplete", result["errors"])
        self.assertIn("registry_valid_doubling_pairs_lt_2", result["errors"])

    def test_quadratic_pair_fails_even_if_blocker_list_is_wrong(self) -> None:
        gate = load_gate()
        report = good_report()
        report["relative_performance"]["blockers"] = []
        report["relative_performance"]["registry_n_2n_4n"][1]["time_ratio"] = 3.7
        result = gate.validate_report(report)
        self.assertFalse(result["ok"])
        self.assertTrue(any(error.startswith("registry_pair_1_quadratic:") for error in result["errors"]))

    def test_external_requirement_claim_fails_at_any_nested_level(self) -> None:
        gate = load_gate()
        report = good_report()
        report["cases"][0]["report"] = {"runtime": {"network_required": True}}
        result = gate.validate_report(report)
        self.assertFalse(result["ok"])
        self.assertTrue(any(error.startswith("external_requirement_claimed:") for error in result["errors"]))

    def test_missing_required_case_fails(self) -> None:
        gate = load_gate()
        report = good_report()
        report["cases"] = report["cases"][1:]
        result = gate.validate_report(report)
        self.assertFalse(result["ok"])
        self.assertTrue(any(error.startswith("required_cases_missing:") for error in result["errors"]))

    def test_failed_case_fails(self) -> None:
        gate = load_gate()
        report = good_report()
        report["cases"][2]["ok"] = False
        result = gate.validate_report(report)
        self.assertFalse(result["ok"])
        self.assertIn("case_failed:dedupe_alias_removal", result["errors"])

    def test_workflow_runs_fail_closed_validator_on_linux_and_windows(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "knowledge-performance-concurrency.yml").read_text(encoding="utf-8")
        self.assertIn("tests.test_knowledge_resilience_gate", workflow)
        self.assertIn("benchmarks/knowledge/validate_resilience_batch.py", workflow)
        self.assertIn("resilience-linux-gate.json", workflow)
        self.assertIn("resilience-windows-gate.json", workflow)
        self.assertGreaterEqual(workflow.count("Validate consolidated resilience evidence"), 2)

    def test_search_remove_probe_forces_open_reader_overlap(self) -> None:
        probe = (BENCH / "concurrency_race_probe.gd").read_text(encoding="utf-8")
        required = [
            "var reader_ready := Semaphore.new()",
            "FileAccess.open(KnowledgeStoreScript.DB_PATH, FileAccess.READ)",
            "reader_ready.post()",
            "reader_ready.wait()",
            "OS.delay_msec(READER_HOLD_MS)",
            'result["remove_started_after_reader_ready"] = true',
            '"deterministic_open_reader_overlap"',
        ]
        for marker in required:
            self.assertIn(marker, probe)


if __name__ == "__main__":
    unittest.main()
