from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / "benchmarks" / "knowledge"
VALIDATOR = BENCH / "validate_performance_report.py"


def load_validator():
    spec = importlib.util.spec_from_file_location("knowledge_performance_validator", VALIDATOR)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    try:
        spec.loader.exec_module(module)
    finally:
        sys.modules.pop(spec.name, None)
    return module


def report(schema: str = "aurorafox_knowledge_performance_v1"):
    if schema == "aurorafox_memory_scaling_v1":
        pairs = [
            {"from_n": 125, "to_n": 250, "write_time_ratio": 2.0},
            {"from_n": 250, "to_n": 500, "write_time_ratio": 2.1},
        ]
    elif schema == "aurorafox_knowledge_search_scaling_v1":
        pairs = [
            {"from_mb": 1.0, "to_mb": 2.0, "time_ratio": 2.0},
            {"from_mb": 2.0, "to_mb": 4.0, "time_ratio": 2.1},
        ]
    elif schema == "aurorafox_knowledge_registry_scaling_v1":
        pairs = [
            {"from_n": 16, "to_n": 32, "time_ratio": 2.0},
            {"from_n": 32, "to_n": 64, "time_ratio": 2.1},
        ]
    else:
        pairs = []
    return {
        "schema": schema,
        "hard_correctness": {"passed": True, "errors": []},
        "self_reliance_contract": {
            "network_required": False,
            "external_runtime_required": False,
            "ollama_required": False,
        },
        "relative_performance": {"n_2n_4n": pairs, "suspected_quadratic": False},
        "results": [],
    }


class KnowledgePerformanceValidatorTests(unittest.TestCase):
    def test_valid_supported_report_passes_correctness(self) -> None:
        module = load_validator()
        result = module.evaluate_report(report(), "ok.json")
        self.assertTrue(result["correctness_passed"])
        self.assertEqual(result["errors"], [])

    def test_missing_core_sections_fail_closed(self) -> None:
        module = load_validator()
        for missing in ("hard_correctness", "self_reliance_contract", "relative_performance", "results"):
            payload = report()
            del payload[missing]
            result = module.evaluate_report(payload, f"missing-{missing}.json")
            self.assertFalse(result["correctness_passed"], missing)

    def test_unknown_schema_fails_closed(self) -> None:
        module = load_validator()
        result = module.evaluate_report(report("unknown-v9"), "unknown.json")
        self.assertFalse(result["correctness_passed"])
        self.assertTrue(any("unsupported or missing schema" in error for error in result["errors"]))

    def test_self_reliance_field_must_be_explicit_false(self) -> None:
        module = load_validator()
        payload = report()
        del payload["self_reliance_contract"]["ollama_required"]
        result = module.evaluate_report(payload, "missing-ollama.json")
        self.assertFalse(result["correctness_passed"])
        self.assertIn("self-reliance field missing: ollama_required", result["errors"])

        payload = report()
        payload["self_reliance_contract"]["network_required"] = True
        result = module.evaluate_report(payload, "network.json")
        self.assertFalse(result["correctness_passed"])
        self.assertIn("self-reliance regression: network_required=true", result["errors"])

    def test_malformed_relative_pairs_fail_closed(self) -> None:
        module = load_validator()
        payload = report()
        payload["relative_performance"]["n_2n_4n"] = {"bad": "shape"}
        result = module.evaluate_report(payload, "pairs.json")
        self.assertFalse(result["correctness_passed"])
        self.assertIn("relative performance n_2n_4n malformed", result["errors"])

    def test_scaling_schema_requires_two_valid_doubling_pairs(self) -> None:
        module = load_validator()
        for schema in (
            "aurorafox_memory_scaling_v1",
            "aurorafox_knowledge_search_scaling_v1",
            "aurorafox_knowledge_registry_scaling_v1",
        ):
            payload = report(schema)
            payload["relative_performance"]["n_2n_4n"] = payload["relative_performance"]["n_2n_4n"][:1]
            result = module.evaluate_report(payload, f"incomplete-{schema}.json")
            self.assertFalse(result["correctness_passed"], schema)
            self.assertTrue(any("incomplete N->2N->4N evidence" in error for error in result["errors"]))

    def test_malformed_search_latency_fails_closed_without_crash(self) -> None:
        module = load_validator()
        payload = report()
        payload["results"] = [{"search": {"cases": [{"p95_ms": "not-a-number"}]}}]
        result = module.evaluate_report(payload, "latency.json")
        self.assertFalse(result["correctness_passed"])
        self.assertTrue(any("malformed numeric field" in error for error in result["errors"]))

    def test_all_supported_scaling_schemas_are_accepted(self) -> None:
        module = load_validator()
        for schema in (
            "aurorafox_memory_scaling_v1",
            "aurorafox_knowledge_search_scaling_v1",
            "aurorafox_knowledge_registry_scaling_v1",
        ):
            result = module.evaluate_report(report(schema), schema)
            self.assertTrue(result["correctness_passed"], (schema, result["errors"]))

    def test_memory_scaling_requires_valid_measured_baseline(self) -> None:
        text = (BENCH / "run_memory_scaling.py").read_text(encoding="utf-8")
        self.assertIn('"phase": "rss_baseline"', text)
        self.assertIn('"baseline peak RSS was not measured"', text)
        self.assertIn('baseline.get(key) is not False', text)
        self.assertLess(text.index('hard_errors: list[dict[str, Any]] = []'), text.index('baseline_root = Path('))
        self.assertIn('"network_required": baseline.get("network_required", None)', text)
        self.assertIn('"external_runtime_required": baseline.get("external_runtime_required", None)', text)
        self.assertIn('"ollama_required": baseline.get("ollama_required", None)', text)


if __name__ == "__main__":
    unittest.main()
