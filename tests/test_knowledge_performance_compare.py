from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMPARE_PATH = ROOT / "benchmarks" / "knowledge" / "compare_reports.py"


def load_compare():
    spec = importlib.util.spec_from_file_location("knowledge_compare", COMPARE_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def report(*, runner_name: str = "runner-a", records_per_sec: float = 100.0, search_p95: float = 10.0, rss: int = 1000):
    return {
        "schema": "aurorafox_knowledge_performance_v1",
        "platform_runtime_identity": {
            "os": "Linux",
            "machine": "x86_64",
            "cpu_count": 4,
            "runner_os": "Linux",
            "runner_arch": "X64",
            "runner_name": runner_name,
        },
        "results": [
            {
                "scenario": "import_jsonl",
                "target_mb": 10,
                "records_per_sec": records_per_sec,
                "peak_rss_bytes": rss,
                "dataset": {"bytes": 10 * 1024 * 1024},
                "case": {"scenario": "import_jsonl", "target_mb": 10},
                "search": {"cases": [{"name": "exact", "p95_ms": search_p95}]},
            }
        ],
    }


class KnowledgePerformanceCompareTests(unittest.TestCase):
    def test_comparable_report_passes_small_noise(self) -> None:
        module = load_compare()
        result = module.compare_reports(report(), report(records_per_sec=95.0, search_p95=11.0, rss=1100))
        self.assertTrue(result["comparable"])
        self.assertTrue(result["passed"])
        self.assertEqual(result["matched_cases"], 1)

    def test_comparable_report_detects_throughput_latency_and_rss_regressions(self) -> None:
        module = load_compare()
        result = module.compare_reports(report(), report(records_per_sec=60.0, search_p95=20.0, rss=1500))
        self.assertTrue(result["comparable"])
        self.assertFalse(result["passed"])
        metrics = {row["metric"] for row in result["regressions"]}
        self.assertIn("records_per_sec", metrics)
        self.assertIn("search_p95_ms", metrics)
        self.assertIn("peak_rss_bytes", metrics)

    def test_cross_machine_comparison_is_skipped_not_misreported(self) -> None:
        module = load_compare()
        candidate = report()
        candidate["platform_runtime_identity"]["cpu_count"] = 8
        result = module.compare_reports(report(), candidate)
        self.assertFalse(result["comparable"])
        self.assertTrue(result["comparison_skipped"])
        self.assertTrue(result["passed"])
        self.assertIn("cpu_count", result["identity_mismatches"])

    def test_commit_sha_and_runner_name_are_not_identity_gates(self) -> None:
        module = load_compare()
        baseline = report(runner_name="ephemeral-a")
        candidate = report(runner_name="ephemeral-b")
        baseline["platform_runtime_identity"]["git_sha"] = "aaa"
        candidate["platform_runtime_identity"]["git_sha"] = "bbb"
        result = module.compare_reports(baseline, candidate)
        self.assertTrue(result["comparable"])


if __name__ == "__main__":
    unittest.main()
