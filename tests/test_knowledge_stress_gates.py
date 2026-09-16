from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / "benchmarks" / "knowledge"


def load_module(name: str, filename: str):
    path = BENCH / filename
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(BENCH))
    try:
        spec.loader.exec_module(module)
    finally:
        sys.path.remove(str(BENCH))
    return module


class KnowledgeStressGateTests(unittest.TestCase):
    def test_validator_marks_quadratic_finding_as_performance_blocker(self) -> None:
        validator = load_module("knowledge_perf_validator", "validate_performance_report.py")
        report = {
            "schema": "aurorafox_knowledge_performance_v1",
            "hard_correctness": {"passed": True, "errors": []},
            "self_reliance_contract": {
                "network_required": False,
                "external_runtime_required": False,
                "ollama_required": False,
            },
            "relative_performance": {"suspected_quadratic": True},
            "results": [],
        }
        result = validator.evaluate_report(report, "candidate.json")
        self.assertTrue(result["correctness_passed"])
        self.assertEqual(result["performance_blockers"], ["suspected_quadratic"])

    def test_validator_rejects_external_runtime_dependency(self) -> None:
        validator = load_module("knowledge_perf_validator_external", "validate_performance_report.py")
        report = {
            "hard_correctness": {"passed": True, "errors": []},
            "self_reliance_contract": {
                "network_required": False,
                "external_runtime_required": True,
                "ollama_required": False,
            },
            "relative_performance": {},
            "results": [],
        }
        result = validator.evaluate_report(report)
        self.assertFalse(result["correctness_passed"])
        self.assertTrue(any("external_runtime_required" in error for error in result["errors"]))

    def test_validator_keeps_absolute_search_latency_informational(self) -> None:
        validator = load_module("knowledge_perf_validator_latency", "validate_performance_report.py")
        report = {
            "hard_correctness": {"passed": True, "errors": []},
            "self_reliance_contract": {
                "network_required": False,
                "external_runtime_required": False,
                "ollama_required": False,
            },
            "relative_performance": {},
            "results": [
                {"search": {"cases": [{"name": "exact_rare", "p95_ms": 1500.0}]}}
            ],
        }
        result = validator.evaluate_report(report)
        self.assertTrue(result["correctness_passed"])
        self.assertEqual(result["performance_blockers"], [])
        self.assertTrue(result["warnings"])

    def test_memory_write_scaling_detects_near_quadratic_double(self) -> None:
        memory = load_module("knowledge_memory_scaling", "run_memory_scaling.py")
        findings = memory.pair_findings(
            [
                {"ok": True, "records_requested": 125, "write_duration_ms": 100.0, "semantic_index_build_ms": 20.0},
                {"ok": True, "records_requested": 250, "write_duration_ms": 380.0, "semantic_index_build_ms": 40.0},
                {"ok": True, "records_requested": 500, "write_duration_ms": 1450.0, "semantic_index_build_ms": 80.0},
            ]
        )
        self.assertEqual(len(findings), 2)
        self.assertTrue(all(row["suspected_quadratic_write"] for row in findings))

    def test_search_scaling_uses_selected_correctness_queries(self) -> None:
        search = load_module("knowledge_search_scaling", "run_search_scaling.py")
        report = {
            "search": {
                "cases": [
                    {"name": "empty", "p95_ms": 9999.0},
                    {"name": "exact_rare", "p95_ms": 100.0},
                    {"name": "common", "p95_ms": 120.0},
                    {"name": "very_long", "p95_ms": 5000.0},
                ]
            }
        }
        self.assertEqual(search.selected_search_p95(report), 120.0)

    def test_search_scaling_detects_superlinear_double(self) -> None:
        search = load_module("knowledge_search_scaling_ratio", "run_search_scaling.py")
        rows = [
            {
                "ok": True,
                "dataset": {"size_mb": 1.0},
                "search": {"cases": [{"name": "exact_rare", "p95_ms": 100.0}]},
            },
            {
                "ok": True,
                "dataset": {"size_mb": 2.0},
                "search": {"cases": [{"name": "exact_rare", "p95_ms": 390.0}]},
            },
        ]
        findings = search.pair_findings(rows)
        self.assertEqual(len(findings), 1)
        self.assertTrue(findings[0]["suspected_superlinear_search"])


if __name__ == "__main__":
    unittest.main()
