#!/usr/bin/env python3
"""Fail-closed validator for AuroraFox Knowledge resilience batch evidence."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

REQUIRED_CASES = {
    "concurrency_race",
    "record_dedupe_shared_source",
    "dedupe_alias_removal",
    "legacy_unregistered_rollback",
    "registry_write_failure_rollback",
    "registry_truncated_temp",
    "interrupted_import_recovery",
    "interrupted_removal_recovery",
    "registry_scaling",
}
REQUIREMENT_KEYS = ("network_required", "external_runtime_required", "ollama_required")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("report")
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return {"_load_error": str(exc)}
    return value if isinstance(value, dict) else {"_load_error": "report root is not an object"}


def _collect_true_requirements(value: Any, path: str = "$") -> list[str]:
    violations: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = f"{path}.{key}"
            if key in REQUIREMENT_KEYS and child is True:
                violations.append(child_path)
            violations.extend(_collect_true_requirements(child, child_path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            violations.extend(_collect_true_requirements(child, f"{path}[{index}]"))
    return violations


def validate_report(report: dict[str, Any]) -> dict[str, Any]:
    errors: list[str] = []
    if report.get("_load_error"):
        errors.append(f"report_unreadable:{report['_load_error']}")

    if report.get("schema") != "aurorafox_knowledge_resilience_batch_v1":
        errors.append("schema_missing_or_wrong")
    if report.get("ok") is not True:
        errors.append("aggregate_ok_not_true")

    hard = report.get("hard_correctness")
    if not isinstance(hard, dict) or hard.get("passed") is not True:
        errors.append("hard_correctness_not_passed")

    contract = report.get("self_reliance_contract")
    if not isinstance(contract, dict):
        errors.append("self_reliance_contract_missing")
    else:
        for key in REQUIREMENT_KEYS:
            if contract.get(key) is not False:
                errors.append(f"self_reliance_contract_{key}_must_be_false")

    true_requirements = _collect_true_requirements(report)
    if true_requirements:
        errors.append("external_requirement_claimed:" + ",".join(true_requirements))

    cases = report.get("cases")
    seen_cases: set[str] = set()
    if not isinstance(cases, list):
        errors.append("cases_missing")
        cases = []
    for row in cases:
        if not isinstance(row, dict):
            errors.append("case_row_not_object")
            continue
        name = str(row.get("name", ""))
        if name:
            seen_cases.add(name)
        if row.get("ok") is not True:
            errors.append(f"case_failed:{name or 'unnamed'}")
    missing_cases = sorted(REQUIRED_CASES - seen_cases)
    if missing_cases:
        errors.append("required_cases_missing:" + ",".join(missing_cases))

    relative = report.get("relative_performance")
    valid_pairs: list[dict[str, Any]] = []
    if not isinstance(relative, dict):
        errors.append("relative_performance_missing")
    else:
        if relative.get("enforced") is not True:
            errors.append("relative_performance_not_enforced")
        blockers = relative.get("blockers")
        if not isinstance(blockers, list):
            errors.append("performance_blockers_missing")
            blockers = []
        if "suspected_quadratic_registry" in blockers:
            errors.append("suspected_quadratic_registry")
        pairs = relative.get("registry_n_2n_4n")
        if not isinstance(pairs, list) or len(pairs) < 2:
            errors.append("registry_doubling_evidence_incomplete")
            pairs = []
        for index, pair in enumerate(pairs):
            if not isinstance(pair, dict):
                errors.append(f"registry_pair_{index}_not_object")
                continue
            from_n = int(pair.get("from_n", 0) or 0)
            to_n = int(pair.get("to_n", 0) or 0)
            ratio = float(pair.get("time_ratio", 0.0) or 0.0)
            if from_n <= 0 or to_n != from_n * 2 or ratio <= 0.0:
                errors.append(f"registry_pair_{index}_invalid")
                continue
            if bool(pair.get("suspected_quadratic_registry", False)) or ratio >= 3.5:
                errors.append(f"registry_pair_{index}_quadratic:{ratio:.4f}")
            valid_pairs.append({"from_n": from_n, "to_n": to_n, "time_ratio": ratio})
        if len(valid_pairs) < 2:
            errors.append("registry_valid_doubling_pairs_lt_2")

    return {
        "schema": "aurorafox_knowledge_resilience_gate_v1",
        "ok": not errors,
        "errors": errors,
        "required_cases": sorted(REQUIRED_CASES),
        "seen_cases": sorted(seen_cases),
        "registry_valid_doubling_pairs": valid_pairs,
        "self_reliance_true_requirement_paths": true_requirements,
    }


def main() -> int:
    args = parse_args()
    report_path = Path(args.report)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    gate = validate_report(load_json(report_path))
    output_path.write_text(json.dumps(gate, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"report": str(report_path), "gate": str(output_path), "ok": gate["ok"], "errors": gate["errors"]}, ensure_ascii=False))
    return 0 if gate["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
