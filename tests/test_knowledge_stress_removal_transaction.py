from __future__ import annotations

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / "benchmarks" / "knowledge"


class KnowledgeRemovalTransactionContractTests(unittest.TestCase):
    def test_canonical_removal_uses_import_transaction_journal(self) -> None:
        transaction = (ROOT / "scripts" / "knowledge_import_transaction.gd").read_text(encoding="utf-8")
        manager = (ROOT / "scripts" / "knowledge_manager.gd").read_text(encoding="utf-8")

        self.assertIn("func remove_source(store: KnowledgeStore, source: String) -> Dictionary:", transaction)
        self.assertIn("result = _remove_source_locked(store, source)", transaction)
        self.assertIn("func _remove_source_locked(store: KnowledgeStore, source: String) -> Dictionary:", transaction)
        self.assertIn("var snapshot := _snapshot(canonical, true)", transaction)
        self.assertIn("var removed := store.remove_source(canonical)", transaction)
        self.assertIn("var registry_result := registry.remove_source(canonical)", transaction)
        self.assertIn('"operation": "remove_source"', transaction)
        self.assertIn("_rollback_result(registry_failed, snapshot)", transaction)
        self.assertIn("_remember_source_presence(canonical, false)", transaction)

        self.assertIn(
            "KnowledgeImportTransaction.new().remove_source(KnowledgeStore.new(), canonical)",
            manager,
        )
        self.assertNotIn("var removed := store.remove_source(canonical)", manager)
        self.assertNotIn("var registry_result := registry.remove_source(source)", manager)
        self.assertIn('"transaction": "alias_registry_only"', manager)

    def test_interrupted_removal_probe_requires_real_snapshot_kill_and_restart_restore(self) -> None:
        probe = (BENCH / "interrupted_removal_probe.gd").read_text(encoding="utf-8")
        runner = (BENCH / "run_interrupted_removal_recovery.py").read_text(encoding="utf-8")

        self.assertIn('"source_b_restored": b_present', probe)
        self.assertIn('bool(recovery.get("recovered", false))', probe)
        self.assertIn('"source_b_registry_restored"', probe)
        self.assertIn('"journals_clean": journals_clean', probe)
        self.assertIn("KnowledgeManagerScript.new()", probe)

        self.assertIn("snapshot_observed", runner)
        self.assertIn("mutation_observed", runner)
        self.assertIn("proc.kill()", runner)
        self.assertIn("and verify.get(\"ok\")", runner)
        self.assertIn("portable.warm_isolated_windows_profile(", runner)
        self.assertIn('"schema": "aurorafox_knowledge_interrupted_removal_v1"', runner)

    def test_registry_write_failure_probe_exercises_post_store_transaction_rollback(self) -> None:
        probe = (BENCH / "write_failure_rollback_probe.gd").read_text(encoding="utf-8")
        self.assertIn('REGISTRY_TEMP', probe)
        self.assertIn("DirAccess.make_dir_recursive_absolute(temp_abs)", probe)
        self.assertIn('txn.call("import_file", store, SOURCE', probe)
        self.assertIn('str(failed.get("transaction", "")) == "rolled_back"', probe)
        self.assertIn('"candidate_partial_absent": candidate_gone', probe)
        self.assertIn('"fingerprint_restored": fp_restored', probe)
        self.assertIn('"revision_restored": revision_restored', probe)
        self.assertIn('"journals_clean": journals_clean', probe)
        self.assertIn('"write_failure_injected": true', probe)
        self.assertIn('"network_required": false', probe)
        self.assertIn('"external_runtime_required": false', probe)
        self.assertIn('"ollama_required": false', probe)


if __name__ == "__main__":
    unittest.main()
