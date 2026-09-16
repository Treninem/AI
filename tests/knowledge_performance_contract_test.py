from __future__ import annotations

import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
BENCH = ROOT / "benchmarks" / "knowledge"


def load_runner():
    spec = importlib.util.spec_from_file_location("knowledge_benchmark", BENCH / "run_benchmark.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class KnowledgePerformanceContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runner = load_runner()
        cls.worker_text = (BENCH / "knowledge_benchmark_worker.gd").read_text(encoding="utf-8")
        cls.runner_text = (BENCH / "run_benchmark.py").read_text(encoding="utf-8")

    def test_required_generated_stress_sizes_exist_without_large_git_fixtures(self):
        standard = self.runner.PROFILES["standard"]
        extended = self.runner.PROFILES["extended"]
        self.assertEqual([10, 50, 100, 250], standard["knowledge_mb"])
        self.assertIn(500, extended["knowledge_mb"])
        self.assertEqual({"jsonl", "csv", "txt", "json"}, set(standard["formats"]))
        for path in BENCH.rglob("*"):
            if path.is_file():
                self.assertLess(path.stat().st_size, 1024 * 1024, f"large fixture/code artifact checked in: {path}")

    def test_ci_profile_has_n_2n_4n_scaling(self):
        ci = self.runner.PROFILES["ci"]
        sizes = ci["knowledge_mb"]
        self.assertEqual(3, len(sizes))
        self.assertAlmostEqual(sizes[1] / sizes[0], 2.0)
        self.assertAlmostEqual(sizes[2] / sizes[1], 2.0)
        source_counts = ci["source_counts"]
        self.assertEqual([4, 8, 16], source_counts)
        memory_records = ci["memory_records"]
        self.assertEqual([50, 100, 200], memory_records)

    def test_worker_exercises_real_production_storage_layers(self):
        for symbol in (
            "KnowledgeImportTransaction.new()",
            "KnowledgeStore.new()",
            "KnowledgeManager.new()",
            "MemoryStore.new()",
        ):
            self.assertIn(symbol, self.worker_text)
        self.assertIn('"knowledge_restart"', self.worker_text)
        self.assertIn('"knowledge_remove"', self.worker_text)
        self.assertIn('"dedup_rollback"', self.worker_text)
        self.assertIn('"source_scaling"', self.worker_text)

    def test_report_contract_contains_required_metrics(self):
        required = (
            "dataset_size_bytes",
            "record_count",
            "chunk_count",
            "import_duration_ms",
            "records_per_sec",
            "mb_per_sec",
            "process_peak_rss_bytes",
            "store_size_bytes",
            "p50_ms",
            "p95_ms",
            "p99_ms",
            "restart_load_and_search_ms",
            "source_removal_ms",
            "rollback_ms",
            "quadratic_suspected",
            "machine_identity",
        )
        combined = self.worker_text + self.runner_text
        for field in required:
            self.assertIn(field, combined, f"missing machine-readable metric: {field}")

    def test_benchmark_isolated_from_real_user_data_and_external_ai_credentials(self):
        for key in ("XDG_DATA_HOME", "HOME", "APPDATA", "LOCALAPPDATA"):
            self.assertIn(key, self.runner_text)
        for provider in ("OPENAI", "ANTHROPIC", "GEMINI", "OLLAMA", "AZURE_OPENAI"):
            self.assertIn(provider, self.runner_text)
        # The worker is deliberately storage-only: no network/API client is instantiated.
        forbidden_worker_tokens = ("HTTPRequest.new", "AIClient.new", "chat_with_compatibility", "http://", "https://")
        for token in forbidden_worker_tokens:
            self.assertNotIn(token, self.worker_text)

    def test_local_semantic_memory_contract_is_checked(self):
        memory_source = (ROOT / "scripts" / "memory_store.gd").read_text(encoding="utf-8")
        for fragment in (
            '"provider": "aurorafox_local_vector"',
            '"network_required": false',
            '"external_runtime_required": false',
            '"ollama_required": false',
        ):
            self.assertIn(fragment, memory_source)
        self.assertIn("semantic_self_reliance", self.runner_text)

    def test_android_is_not_falsely_claimed_from_desktop_benchmark(self):
        self.assertIn('"physical_device_tested": False', self.runner_text)
        self.assertIn('"desktop_result_is_not_android_device_proof": True', self.runner_text)

    def test_relative_regression_gate_is_separate_from_correctness(self):
        compare = (BENCH / "compare_reports.py").read_text(encoding="utf-8")
        self.assertIn("passing baseline became failing", compare)
        self.assertIn("--import-regression", compare)
        self.assertIn("--search-regression", compare)
        self.assertIn("--memory-regression", compare)
        self.assertIn("--storage-regression", compare)


if __name__ == "__main__":
    unittest.main()
