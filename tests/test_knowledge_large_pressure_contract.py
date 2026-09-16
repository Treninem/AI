from __future__ import annotations

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class KnowledgeLargePressureContractTest(unittest.TestCase):
    def test_pressure_probe_separates_import_from_percentile_search(self) -> None:
        text = (ROOT / "benchmarks/knowledge/large_import_pressure_probe.gd").read_text(encoding="utf-8")
        self.assertIn('AURORA_KNOWLEDGE_PRESSURE_IMPORT_RESULT=', text)
        self.assertIn('"search_correctness_samples": 1', text)
        self.assertNotIn("_search_matrix(", text)
        self.assertIn('store.search(marker, 8)', text)
        self.assertIn('"network_required": false', text)
        self.assertIn('"external_runtime_required": false', text)
        self.assertIn('"ollama_required": false', text)

    def test_pressure_runner_requires_10_50_100_250_and_restart_remove(self) -> None:
        text = (ROOT / "benchmarks/knowledge/run_large_pressure.py").read_text(encoding="utf-8")
        self.assertIn('default="10,50,100,250"', text)
        self.assertIn("base.run_restart_check(", text)
        self.assertIn("large_remove_pressure_probe.gd", text)
        self.assertIn('"physical_device_proof": False', text)
        self.assertIn("bounded pressure phase timeout", text)
        self.assertNotIn('timeout-seconds", type=int, default=900', text)

    def test_wave_b_large_workflow_runs_independent_relative_gates(self) -> None:
        text = (ROOT / ".github/workflows/knowledge-wave-b-stress.yml").read_text(encoding="utf-8")
        self.assertIn("--sizes-mb 10,50,100,250", text)
        self.assertIn("--counts 250,500,1000", text)
        self.assertIn("--sizes-mb 4,8,16", text)
        self.assertIn("--counts 32,64,128", text)
        self.assertIn("--enforce-performance", text)
        self.assertIn("--scenario rollback", text)
        self.assertIn("--target-mb 100", text)
        self.assertIn("if-no-files-found: error", text)


if __name__ == "__main__":
    unittest.main()
