from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER_PATH = ROOT / "benchmarks" / "knowledge" / "run_knowledge_benchmark.py"
HARNESS_PATH = ROOT / "benchmarks" / "knowledge" / "knowledge_stress_benchmark.gd"


def load_runner():
    spec = importlib.util.spec_from_file_location("knowledge_bench_runner", RUNNER_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class KnowledgePerformanceContractTests(unittest.TestCase):
    def test_large_datasets_are_generated_not_committed(self) -> None:
        runner = load_runner()
        stress = runner.scenario_matrix("stress")
        jsonl_sizes = [int(row.get("target_mb", 0)) for row in stress if row.get("scenario") == "import_jsonl"]
        self.assertEqual(jsonl_sizes, [10, 50, 100, 250])
        self.assertFalse(any(path.stat().st_size > 2 * 1024 * 1024 for path in (ROOT / "benchmarks" / "knowledge").glob("**/*") if path.is_file()))

    def test_harness_uses_real_local_storage_paths_and_safety_sentinel(self) -> None:
        text = HARNESS_PATH.read_text(encoding="utf-8")
        self.assertIn("AURORA_KNOWLEDGE_BENCH_ALLOW_DESTRUCTIVE", text)
        self.assertIn('preload("res://scripts/knowledge_store.gd")', text)
        self.assertIn('preload("res://scripts/knowledge_import_transaction.gd")', text)
        self.assertIn('preload("res://scripts/knowledge_source_registry.gd")', text)
        self.assertIn('preload("res://scripts/memory_store.gd")', text)
        self.assertIn("KnowledgeStoreScript.new()", text)
        self.assertIn("KnowledgeImportTransactionScript.new()", text)
        self.assertIn("MemoryStoreScript.new()", text)
        self.assertIn('"network_required": false', text)
        self.assertIn('"external_runtime_required": false', text)
        self.assertIn('"ollama_required": false', text)
        self.assertNotIn("HTTPRequest.new()", text)
        self.assertNotIn("http://", text.lower())
        self.assertNotIn("https://", text.lower())

    def test_report_contract_contains_scale_memory_restart_and_correctness(self) -> None:
        text = RUNNER_PATH.read_text(encoding="utf-8") + "\n" + HARNESS_PATH.read_text(encoding="utf-8")
        for required in (
            '"schema": "aurorafox_knowledge_performance_v1"',
            '"peak_rss_bytes"',
            '"hard_correctness"',
            '"relative_performance"',
            '"n_2n_4n"',
            '"suspected_quadratic"',
            '"memory_scaling"',
            '"process_restart_proof"',
            '"android_contract"',
            '"physical_device_proof": False',
        ):
            self.assertIn(required, text)

    def test_standard_profile_covers_all_streaming_formats_and_transactions(self) -> None:
        runner = load_runner()
        scenarios = [row.get("scenario") for row in runner.scenario_matrix("standard")]
        for required in (
            "import_jsonl",
            "import_csv",
            "import_txt",
            "import_json",
            "dedupe_seed",
            "source_lifecycle",
            "rollback",
            "scaling_many_sources",
            "semantic_memory",
            "concurrent_import",
            "unicode_long_path",
        ):
            self.assertIn(required, scenarios)
        scaling = [int(row.get("count", 0)) for row in runner.scenario_matrix("standard") if row.get("scenario") == "scaling_many_sources"]
        self.assertEqual(scaling, [8, 16, 32])

    def test_source_removal_hard_gate_rejects_orphan_registry(self) -> None:
        text = HARNESS_PATH.read_text(encoding="utf-8")
        self.assertIn("var orphan_registry := not KnowledgeSourceRegistryScript.new().record_for_source(paths[1]).is_empty()", text)
        self.assertIn('"ok": bool(removed.get("ok", false)) and a_ok and b_gone and c_ok and not orphan_registry', text)
        self.assertIn('"orphan_registry": orphan_registry', text)

    def test_runner_is_stdlib_only_and_keeps_absolute_ci_timings_informational(self) -> None:
        text = RUNNER_PATH.read_text(encoding="utf-8")
        self.assertNotIn("import psutil", text)
        self.assertNotIn("import requests", text)
        self.assertIn('"absolute_ci_timings_are_informational": True', text)
        self.assertIn("ratio >= 3.5", text)
        self.assertIn("bounded execution timeout", text)


if __name__ == "__main__":
    unittest.main()
