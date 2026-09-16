from __future__ import annotations

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "scripts" / "knowledge_source_registry.gd"
PROBE = ROOT / "benchmarks" / "knowledge" / "registry_truncated_temp_probe.gd"
WORKFLOW = ROOT / ".github" / "workflows" / "knowledge-performance.yml"


class KnowledgeRegistryDurabilityContractTests(unittest.TestCase):
    def test_registry_temp_is_validated_before_atomic_replacement(self) -> None:
        text = REGISTRY.read_text(encoding="utf-8")
        self.assertIn("file.flush()", text)
        self.assertIn("var write_error := file.get_error()", text)
        self.assertIn("if write_error != OK or not _valid_registry_file(REGISTRY_TEMP):", text)

        replace_start = text.index("func _replace_registry_file() -> bool:")
        replace_end = text.index("func _repair_interrupted_save() -> bool:")
        replace = text[replace_start:replace_end]
        validation = replace.index("if not _valid_registry_file(REGISTRY_TEMP):")
        move_old = replace.index("if FileAccess.file_exists(REGISTRY_PATH):")
        self.assertLess(validation, move_old, "malformed temp must be rejected before canonical registry is renamed")
        self.assertIn("_remove_if_exists(REGISTRY_TEMP)", replace)

    def test_probe_reproduces_truncated_temp_without_touching_good_registry(self) -> None:
        text = PROBE.read_text(encoding="utf-8")
        self.assertIn("AURORA_KNOWLEDGE_TRUNCATED_REGISTRY_RESULT=", text)
        self.assertIn("KnowledgeSourceRegistryScript.REGISTRY_TEMP", text)
        self.assertIn("malformed.store_string", text)
        self.assertIn('registry.call("_replace_registry_file")', text)
        self.assertIn('"malformed_temp_promoted": promoted', text)
        self.assertIn('"source_preserved_after_restart"', text)
        self.assertIn('"fingerprint_preserved"', text)
        self.assertIn('"temp_removed"', text)

    def test_linux_and_windows_smoke_execute_truncated_temp_probe(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertGreaterEqual(workflow.count("registry_truncated_temp_probe.gd"), 2)
        self.assertIn("registry-truncated-temp.json", workflow)
        self.assertIn("registry-truncated-temp-windows.json", workflow)
        self.assertIn("tests.test_knowledge_stress_registry_durability", workflow)


if __name__ == "__main__":
    unittest.main()
