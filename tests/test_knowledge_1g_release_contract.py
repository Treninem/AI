from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "knowledge-1g-release-gate.yml"


class KnowledgeOneGiBReleaseContractTests(unittest.TestCase):
    def test_release_gate_runs_real_one_gib_streaming_import_and_restart(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("Checkout exact SHA", text)
        self.assertIn("KNOWLEDGE_1G_HEAD_SHA=", text)
        self.assertIn("--scenario import_jsonl", text)
        self.assertIn("--target-mb 1024", text)
        self.assertIn("--timeout-seconds 5400", text)
        self.assertIn("restart_check", text)
        self.assertIn("1024 * 1024 * 1024", text)
        self.assertIn("1536 * 1024 * 1024", text)
        self.assertIn("network_required", text)
        self.assertIn("external_runtime_required", text)
        self.assertIn("ollama_required", text)
        self.assertIn("uses: actions/upload-artifact@v4", text)

    def test_release_gate_prints_failure_report_and_retries_only_transport(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("status=0", text)
        self.assertIn("|| status=$?", text)
        self.assertIn("python -m json.tool artifacts/knowledge-1g/knowledge-1g.json", text)
        self.assertIn('exit "$status"', text)
        self.assertIn("--retry-all-errors", text)
        self.assertIn("--retry 8", text)
        self.assertIn("unzip -tq godot.zip", text)

    def test_one_gib_gate_keeps_every_query_with_one_bounded_sample(self) -> None:
        benchmark = (ROOT / "benchmarks" / "knowledge" / "knowledge_stress_benchmark.gd").read_text(encoding="utf-8")
        self.assertIn("var search_samples := 1 if target_mb >= 1024 else 5", benchmark)
        self.assertIn("range(bounded_samples)", benchmark)
        self.assertIn("clampi(sample_count, 1, 5)", benchmark)
        for name in ("empty", "exact_rare", "common", "multiple_tokens", "russian", "mixed_ru_en", "very_long", "malformed"):
            self.assertIn(f'"name": "{name}"', benchmark)
        self.assertIn("AURORA_KNOWLEDGE_SEARCH", benchmark)


if __name__ == "__main__":
    unittest.main()
