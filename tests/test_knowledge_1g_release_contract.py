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
        self.assertIn("--timeout-seconds 3600", text)
        self.assertIn("restart_check", text)
        self.assertIn("1024 * 1024 * 1024", text)
        self.assertIn("1536 * 1024 * 1024", text)
        self.assertIn("network_required", text)
        self.assertIn("external_runtime_required", text)
        self.assertIn("ollama_required", text)
        self.assertIn("uses: actions/upload-artifact@v4", text)


if __name__ == "__main__":
    unittest.main()
