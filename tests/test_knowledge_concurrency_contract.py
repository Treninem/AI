from __future__ import annotations

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "benchmarks" / "knowledge" / "concurrency_race_probe.gd"
WORKFLOW = ROOT / ".github" / "workflows" / "knowledge-performance.yml"


class KnowledgeConcurrencyContractTests(unittest.TestCase):
    def test_probe_covers_duplicate_import_and_search_remove(self) -> None:
        text = PROBE.read_text(encoding="utf-8")
        self.assertIn("func _concurrent_duplicate_import()", text)
        self.assertIn("func _search_remove_race()", text)
        self.assertIn("Semaphore.new()", text)
        self.assertGreaterEqual(text.count("Thread.new()"), 4)
        self.assertIn('"transaction_serialized": serialized', text)
        self.assertIn('"one_import_one_duplicate_alias": one_import_one_alias', text)
        self.assertIn('"post_remove_empty"', text)
        self.assertIn('"control_source_preserved"', text)
        self.assertIn('"transaction_residue"', text)
        self.assertIn('"network_required": false', text)
        self.assertIn('"external_runtime_required": false', text)
        self.assertIn('"ollama_required": false', text)

    def test_workflow_runs_probe_on_linux_and_windows(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertEqual(workflow.count("concurrency_race_probe.gd"), 2)
        self.assertEqual(workflow.count("AURORA_KNOWLEDGE_CONCURRENCY_RESULT="), 2)
        self.assertIn("concurrency-races.json", workflow)
        self.assertIn("concurrency-races-windows.json", workflow)


if __name__ == "__main__":
    unittest.main()
