from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
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

    def test_portable_harness_makes_dynamic_script_locals_explicit_variant(self) -> None:
        portable = load_module("knowledge_portable_runner", "run_knowledge_benchmark_portable.py")
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            bench = repo / "benchmarks" / "knowledge"
            bench.mkdir(parents=True)
            lines = [
                "extends SceneTree",
                *[
                    f'const {name} = preload("res://scripts/{index}.gd")'
                    for index, name in enumerate(portable.SCRIPT_NAMES)
                ],
                "func _run() -> void:",
                "\tvar store := KnowledgeStoreScript.new()",
                "\tvar result := store.call(\"search\", \"x\", 1)",
                "\tprint(result)",
            ]
            (bench / "knowledge_stress_benchmark.gd").write_text("\n".join(lines), encoding="utf-8")
            generated = portable.portable_harness(repo).read_text(encoding="utf-8")
            self.assertIn("const KnowledgeStoreScript: Variant = preload(", generated)
            self.assertIn("var store: Variant = KnowledgeStoreScript.new()", generated)
            self.assertIn('var result: Variant = store.call("search", "x", 1)', generated)
            self.assertNotIn("var store :=", generated)
            self.assertNotIn("var result :=", generated)

    def test_alias_removal_probe_uses_explicit_dynamic_result_types(self) -> None:
        text = (BENCH / "dedupe_alias_removal_probe.gd").read_text(encoding="utf-8")
        self.assertIn("var canonical_survived: bool =", text)
        self.assertIn("var alias_detached: bool =", text)
        self.assertIn("var ok: bool =", text)
        self.assertIn("var after: Variant =", text)

    def test_interrupted_recovery_contract_is_retry_safe(self) -> None:
        transaction = (ROOT / "scripts" / "knowledge_import_transaction.gd").read_text(encoding="utf-8")
        manager = (ROOT / "scripts" / "knowledge_manager.gd").read_text(encoding="utf-8")
        probe = (BENCH / "interrupted_import_probe.gd").read_text(encoding="utf-8")

        self.assertIn("TXN_SNAPSHOT_MARKER", transaction)
        self.assertIn("TXN_COMMIT_MARKER", transaction)
        self.assertIn("if FileAccess.file_exists(TXN_COMMIT_MARKER):", transaction)
        self.assertIn("actual_rows != expected_rows", transaction)
        self.assertIn("_repair_interrupted_filter_swap(path)", transaction)
        self.assertIn("_repair_recovery_swap(path)", transaction)
        self.assertIn("DirAccess.copy_absolute(ProjectSettings.globalize_path(REGISTRY_BACKUP)", transaction)
        self.assertNotIn("DirAccess.rename_absolute(backup_abs, target_abs)", transaction)

        restore = transaction.split("func _restore(snapshot: Dictionary) -> bool:", 1)[1].split("func _restore_source_file", 1)[0]
        self.assertTrue(restore.rstrip().endswith("_cleanup_backups(true)\n\treturn true"))
        cleanup = transaction.split("func _cleanup_backups", 1)[1]
        self.assertLess(cleanup.index("paths.append(TXN_MANIFEST)"), cleanup.index("paths.append(TXN_COMMIT_MARKER)"))

        self.assertIn("recover_interrupted_transaction()", manager)
        self.assertIn("KnowledgeManagerScript.new()", probe)
        self.assertIn('"automatic_manager_recovery": true', probe)
        for marker in ("TXN_MANIFEST", "TXN_SNAPSHOT_MARKER", "TXN_COMMIT_MARKER"):
            self.assertIn(f'"{marker}"', probe)


if __name__ == "__main__":
    unittest.main()
