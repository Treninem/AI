#!/usr/bin/env python3
"""Validate AuroraFox Knowledge/Memory performance reports.

Absolute GitHub-hosted-runner timings remain informational. The gate fails on
hard correctness/self-reliance regressions, malformed/missing evidence, and on
reproducible N->2N scaling classified as a quadratic/superlinear blocker.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

SUPPORTED_SCHEMAS = {
    "aurorafox_knowledge_performance_v1",
    "aurorafox_memory_scaling_v1",
    "aurorafox_knowledge_search_scaling_v1",
    "aurorafox_knowledge_registry_scaling_v1",
}
SCALING_SCHEMAS = {
    "aurorafox_memory_scaling_v1",
    "aurorafox_knowledge_search_scaling_v1",
    "aurorafox_knowledge_registry_scaling_v1",
}
SELF_RELIANCE_KEYS = ("network_required", "external_runtime_required", "ollama_required")
FORBIDDEN_TRUE_KEYS = {
    "network_required",
    "external_runtime_required",
    "ollama_required",
    "external_ai_required",
    "remote_inference",
}
BLOCKER_FIELDS = (
    "suspected_quadratic",
    "suspected_quadratic_write",
    "suspected_quadratic_registry",
    "suspected_superlinear_search",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("reports", nargs="+", help="Machine-readable benchmark reports")
    parser.add_argument("--output", default="", help="Optional JSON gate summary")
    parser.add_argument(
        "--enforce-performance",
        action="store_true",
        help="Fail on reproducible quadratic/superlinear findings",
    )
    return parser.parse_args()


def _load(path: str) -> dict[str, Any]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"report is not an object: {path}")
    return data


def _float(value: Any, *, field: str, errors: list[str]) -> float:
    try:
        return float(value or 0.0)
    except (TypeError, ValueError):
        errors.append(f"malformed numeric field: {field}")
        return 0.0


def _collect_forbidden_true(value: Any, path: str = "$") -> list[str]:
    violations: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = f"{path}.{key}"
            if key in FORBIDDEN_TRUE_KEYS and child is True:
                violations.append(child_path)
            violations.extend(_collect_forbidden_true(child, child_path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            violations.extend(_collect_forbidden_true(child, f"{path}[{index}]"))
    return violations


def _valid_scaling_pairs(schema: str, pairs: Any, errors: list[str]) -> int:
    if not isinstance(pairs, list):
        errors.append("relative performance n_2n_4n missing or malformed")
        return 0
    valid = 0
    for index, pair in enumerate(pairs):
        if not isinstance(pair, dict):
            errors.append(f"scaling pair malformed: index={index}")
            continue
        if schema == "aurorafox_knowledge_search_scaling_v1":
            start = _float(pair.get("from_mb"), field=f"n_2n_4n[{index}].from_mb", errors=errors)
            end = _float(pair.get("to_mb"), field=f"n_2n_4n[{index}].to_mb", errors=errors)
            ratio = _float(pair.get("time_ratio"), field=f"n_2n_4n[{index}].time_ratio", errors=errors)
            if start <= 0 or end <= 0 or not (1.8 <= end / start <= 2.2) or ratio <= 0:
                errors.append(f"invalid search scaling pair: index={index}")
                continue
        else:
            try:
                start = int(pair.get("from_n", 0) or 0)
                end = int(pair.get("to_n", 0) or 0)
            except (TypeError, ValueError):
                errors.append(f"invalid count scaling pair: index={index}")
                continue
            ratio_key = "write_time_ratio" if schema == "aurorafox_memory_scaling_v1" else "time_ratio"
            ratio = _float(pair.get(ratio_key), field=f"n_2n_4n[{index}].{ratio_key}", errors=errors)
            if start <= 0 or end != start * 2 or ratio <= 0:
                errors.append(f"invalid count scaling pair: index={index}")
                continue
        valid += 1
    if len(pairs) < 2 or valid < 2:
        errors.append(f"incomplete N->2N->4N evidence: valid_pairs={valid}")
    return valid


def evaluate_report(report: dict[str, Any], path: str = "") -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    schema = str(report.get("schema", ""))
    if schema not in SUPPORTED_SCHEMAS:
        errors.append(f"unsupported or missing schema: {schema or '<empty>'}")

    hard = report.get("hard_correctness")
    if not isinstance(hard, dict):
        errors.append("hard correctness section missing or malformed")
    elif hard.get("passed") is not True:
        errors.append("hard correctness gate failed")

    self_reliance = report.get("self_reliance_contract")
    if not isinstance(self_reliance, dict):
        errors.append("self-reliance section missing or malformed")
    else:
        for key in SELF_RELIANCE_KEYS:
            if key not in self_reliance:
                errors.append(f"self-reliance field missing: {key}")
            elif self_reliance.get(key) is not False:
                errors.append(f"self-reliance regression: {key}=true")

    # The aggregate contract is not allowed to contradict child/runtime evidence.
    # Imported/benchmark result objects are untrusted evidence until verified.
    true_requirement_paths = _collect_forbidden_true(report)
    if true_requirement_paths:
        errors.append("nested self-reliance regression: " + ",".join(true_requirement_paths))

    relative = report.get("relative_performance")
    blocker_fields: list[str] = []
    if not isinstance(relative, dict):
        errors.append("relative performance section missing or malformed")
    else:
        for key in BLOCKER_FIELDS:
            if bool(relative.get(key, False)):
                blocker_fields.append(key)
        pairs = relative.get("n_2n_4n")
        if schema in SCALING_SCHEMAS:
            _valid_scaling_pairs(schema, pairs, errors)
        elif pairs is not None and not isinstance(pairs, list):
            errors.append("relative performance n_2n_4n malformed")

    results = report.get("results")
    if not isinstance(results, list):
        errors.append("results section missing or malformed")
        results = []

    # Search absolute latency is runner-dependent, but retain a visible risk
    # summary rather than silently normalizing it with larger timeouts.
    max_search_p95 = 0.0
    for result_index, result in enumerate(results):
        if not isinstance(result, dict):
            errors.append(f"result row malformed: index={result_index}")
            continue
        search = result.get("search")
        if not isinstance(search, dict):
            continue
        cases = search.get("cases")
        if not isinstance(cases, list):
            errors.append(f"search cases malformed: result={result_index}")
            continue
        for case_index, case in enumerate(cases):
            if not isinstance(case, dict):
                errors.append(f"search case malformed: result={result_index} case={case_index}")
                continue
            max_search_p95 = max(
                max_search_p95,
                _float(case.get("p95_ms", 0.0), field=f"results[{result_index}].search.cases[{case_index}].p95_ms", errors=errors),
            )
    if max_search_p95 >= 1000.0:
        warnings.append(
            f"informational CI search latency >=1s (max p95={max_search_p95:.3f} ms); "
            "compare only on matching runner identity"
        )

    return {
        "path": path,
        "schema": schema,
        "correctness_passed": not errors,
        "performance_blockers": blocker_fields,
        "max_search_p95_ms": max_search_p95,
        "self_reliance_true_requirement_paths": true_requirement_paths,
        "errors": errors,
        "warnings": warnings,
    }


def main() -> int:
    args = parse_args()
    evaluations: list[dict[str, Any]] = []
    load_errors: list[str] = []
    for path in args.reports:
        try:
            evaluations.append(evaluate_report(_load(path), path))
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            load_errors.append(f"{path}: {exc}")

    correctness_passed = bool(evaluations) and not load_errors and all(row["correctness_passed"] for row in evaluations)
    blockers = [
        {"path": row["path"], "fields": row["performance_blockers"]}
        for row in evaluations
        if row["performance_blockers"]
    ]
    performance_passed = not blockers
    passed = correctness_passed and (performance_passed or not args.enforce_performance)
    summary = {
        "schema": "aurorafox_knowledge_performance_gate_v1",
        "passed": passed,
        "correctness_passed": correctness_passed,
        "performance_passed": performance_passed,
        "performance_enforced": bool(args.enforce_performance),
        "load_errors": load_errors,
        "blockers": blockers,
        "reports": evaluations,
        "rule": "missing/malformed evidence fails closed; nested runtime self-reliance must agree with aggregate contract; scaling reports require complete N->2N->4N evidence; absolute hosted-runner timings are informational; reproducible near-4x scaling is blocking",
    }
    if args.output:
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
