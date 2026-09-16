from __future__ import annotations

import argparse
import json
import math
from collections import Counter
from copy import deepcopy
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
REQUIRED_PERFORMANCE_MEASUREMENTS = (
    "cold_first_response_ms",
    "warm_median_ms",
    "throughput_equivalent_tps",
    "peak_rss_mb",
    "suite_wall_ms",
)


def load_json(path: str | Path) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _scenario_map(report: dict[str, Any]) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    for row in report.get("scenarios", []):
        if isinstance(row, dict) and row.get("id"):
            out[str(row["id"])] = row
    return out


def evaluate_quality(
    report: dict[str, Any],
    required_scenarios: list[str],
    local_runtime_required_scenarios: list[str] | None = None,
    allowed_local_runtimes: list[str] | None = None,
    runtime_policy_available: bool = True,
    expected_suite: str = "",
) -> dict[str, Any]:
    raw_rows = [row for row in report.get("scenarios", []) if isinstance(row, dict)]
    scenario_ids = [str(row.get("id", "")) for row in raw_rows if row.get("id")]
    duplicates = sorted(name for name, count in Counter(scenario_ids).items() if count > 1)
    scenarios = _scenario_map(report)
    missing = [name for name in required_scenarios if name not in scenarios]
    failed = [
        name for name in required_scenarios
        if name in scenarios and not bool(scenarios[name].get("passed", False))
    ]
    timeouts = [
        str(row.get("id", "unknown")) for row in raw_rows
        if bool(row.get("timeout", False))
    ]
    runtime_names = {
        str(row.get("runtime", ""))
        for row in raw_rows
        if row.get("runtime")
    }
    forbidden_runtime = sorted(
        name for name in runtime_names
        if any(marker in name.lower() for marker in ("ollama", "openai", "remote", "cloud"))
    )

    runtime_required = list(local_runtime_required_scenarios or [])
    allowed = {str(name) for name in (allowed_local_runtimes or []) if str(name)}
    runtime_policy_missing = bool(runtime_required and not runtime_policy_available)
    missing_runtime: list[str] = []
    unexpected_runtime: list[dict[str, str]] = []
    for name in runtime_required:
        row = scenarios.get(name)
        if row is None:
            continue
        runtime = str(row.get("runtime", "")).strip()
        if not runtime:
            missing_runtime.append(name)
        elif allowed and runtime not in allowed:
            unexpected_runtime.append({"scenario": name, "runtime": runtime})

    schema_valid = report.get("schema_version") == SCHEMA_VERSION
    report_status = str(report.get("status", "")).strip()
    status_complete = report_status == "completed"
    actual_suite = str(report.get("suite", "")).strip()
    suite_valid = not expected_suite or actual_suite == expected_suite
    platform = str(report.get("platform", "")).strip()
    machine_os = str(report.get("machine", {}).get("os", "")).strip()
    platform_identity_mismatch = bool(platform and machine_os and platform.lower() != machine_os.lower())
    environment = report.get("environment", {}) if isinstance(report.get("environment", {}), dict) else {}
    remote_ai_allowed = bool(environment.get("remote_ai_allowed", True))
    fixture_core_used = bool(environment.get("fixture_core_used", True))

    passed = (
        schema_valid
        and status_complete
        and suite_valid
        and not duplicates
        and not missing
        and not failed
        and not timeouts
        and not forbidden_runtime
        and not runtime_policy_missing
        and not missing_runtime
        and not unexpected_runtime
        and not platform_identity_mismatch
        and not remote_ai_allowed
        and not fixture_core_used
    )
    total = len(required_scenarios)
    failed_identity = set(missing_runtime) | {row["scenario"] for row in unexpected_runtime}
    passed_count = total - len(missing) - len(set(failed)) - len(failed_identity - set(failed))
    return {
        "passed": passed,
        "required": total,
        "passed_count": max(0, passed_count),
        "score": (max(0, passed_count) / total) if total else 0.0,
        "schema_valid": schema_valid,
        "report_status": report_status,
        "status_complete": status_complete,
        "suite_valid": suite_valid,
        "expected_suite": expected_suite,
        "actual_suite": actual_suite,
        "duplicate_scenario_ids": duplicates,
        "missing_scenarios": missing,
        "failed_scenarios": failed,
        "timeout_scenarios": timeouts,
        "forbidden_runtime_names": forbidden_runtime,
        "runtime_policy_available": runtime_policy_available,
        "runtime_policy_missing": runtime_policy_missing,
        "missing_runtime_scenarios": missing_runtime,
        "unexpected_runtime_scenarios": unexpected_runtime,
        "allowed_local_runtimes": sorted(allowed),
        "platform": platform,
        "machine_os": machine_os,
        "platform_identity_mismatch": platform_identity_mismatch,
        "remote_ai_allowed": remote_ai_allowed,
        "fixture_core_used": fixture_core_used,
    }


def _finite(value: Any, default: float = 0.0) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return default
    return result if math.isfinite(result) else default


def _metric(report: dict[str, Any], key: str, default: float = 0.0) -> float:
    return _finite(report.get("performance", {}).get(key, default), default)


def validate_baseline(baseline: dict[str, Any]) -> list[dict[str, Any]]:
    """Reject baseline evidence that would silently disable relative checks."""
    failures: list[dict[str, Any]] = []
    for metric_key in REQUIRED_PERFORMANCE_MEASUREMENTS:
        actual = _metric(baseline, metric_key)
        if actual <= 0:
            failures.append(
                {
                    "metric": metric_key,
                    "actual": actual,
                    "reason": "baseline_missing_or_non_positive_measurement",
                }
            )
    timeout_count = int(_finite(baseline.get("performance", {}).get("timeout_count", 0), 0.0))
    if timeout_count > 0:
        failures.append(
            {
                "metric": "timeout_count",
                "actual": timeout_count,
                "reason": "baseline_contains_timeout",
            }
        )
    return failures


def machine_compatible(
    current: dict[str, Any], baseline: dict[str, Any], policy: dict[str, Any]
) -> tuple[bool, list[str]]:
    rules = policy.get("baseline_compatibility", {})
    current_machine = current.get("machine", {})
    baseline_machine = baseline.get("machine", {})
    mismatches: list[str] = []
    checks = (
        ("require_same_os", "os"),
        ("require_same_arch", "arch"),
        ("require_same_logical_processors", "logical_processors"),
        ("require_same_processor_identifier", "processor_identifier"),
    )
    for flag, key in checks:
        if not bool(rules.get(flag, False)):
            continue
        a = str(current_machine.get(key, "")).strip().lower()
        b = str(baseline_machine.get(key, "")).strip().lower()
        if not a or not b or a != b:
            mismatches.append(key)

    identity_checks = (
        ("require_same_core_model_sha", "prepared_sha256"),
        ("require_same_core_engine_version", "engine_version"),
    )
    current_core = current.get("core", {})
    baseline_core = baseline.get("core", {})
    for flag, key in identity_checks:
        if not bool(rules.get(flag, False)):
            continue
        a = str(current_core.get(key, "")).strip().lower()
        b = str(baseline_core.get(key, "")).strip().lower()
        if not a or not b or a != b:
            mismatches.append("core." + key)
    return not mismatches, mismatches


def _regressed_higher(current: float, baseline: float, ratio: float, min_delta: float) -> bool:
    if current <= 0 or baseline <= 0:
        return False
    return current > baseline * ratio and (current - baseline) > min_delta


def _regressed_lower(current: float, baseline: float, floor_ratio: float, min_delta: float) -> bool:
    if current <= 0 or baseline <= 0:
        return False
    return current < baseline * floor_ratio and (baseline - current) > min_delta


def evaluate_performance(
    report: dict[str, Any], policy: dict[str, Any], baseline: dict[str, Any] | None = None
) -> dict[str, Any]:
    hard = policy.get("hard_limits", {})
    hard_failures: list[dict[str, Any]] = []
    missing_measurements: list[str] = []

    for metric_key in REQUIRED_PERFORMANCE_MEASUREMENTS:
        actual = _metric(report, metric_key)
        if actual <= 0:
            missing_measurements.append(metric_key)
            hard_failures.append(
                {
                    "metric": metric_key,
                    "actual": actual,
                    "reason": "missing_or_non_positive_measurement",
                }
            )

    timeout_count = int(_finite(report.get("performance", {}).get("timeout_count", 0), 0.0))
    if timeout_count > 0:
        hard_failures.append({"metric": "timeout_count", "actual": timeout_count, "limit": 0})

    hard_specs = (
        ("cold_first_response_ms", "cold_first_response_ms"),
        ("warm_median_ms", "warm_response_ms"),
        ("peak_rss_mb", "peak_rss_mb"),
    )
    for metric_key, limit_key in hard_specs:
        actual = _metric(report, metric_key)
        limit = _finite(hard.get(limit_key, 0))
        if actual > 0 and limit > 0 and actual > limit:
            hard_failures.append({"metric": metric_key, "actual": actual, "limit": limit})

    throughput = _metric(report, "throughput_equivalent_tps")
    minimum_throughput = _finite(hard.get("minimum_throughput_equivalent_tps", 0))
    if throughput > 0 and minimum_throughput > 0 and throughput < minimum_throughput:
        hard_failures.append(
            {"metric": "throughput_equivalent_tps", "actual": throughput, "minimum": minimum_throughput}
        )

    suite_wall = _metric(report, "suite_wall_ms")
    suite_limit = _finite(hard.get("suite_timeout_ms", 0))
    if suite_wall > 0 and suite_limit > 0 and suite_wall > suite_limit:
        hard_failures.append({"metric": "suite_wall_ms", "actual": suite_wall, "limit": suite_limit})

    relative_failures: list[dict[str, Any]] = []
    baseline_validation_failures: list[dict[str, Any]] = []
    comparison_status = "no_baseline"
    machine_mismatches: list[str] = []
    compatible = False
    if baseline is not None:
        baseline_validation_failures = validate_baseline(baseline)
        if baseline_validation_failures:
            comparison_status = "baseline_invalid"
            hard_failures.append(
                {
                    "metric": "baseline",
                    "reason": "invalid_baseline",
                    "failures": baseline_validation_failures,
                }
            )
        else:
            compatible, machine_mismatches = machine_compatible(report, baseline, policy)
            comparison_status = "comparable" if compatible else "baseline_machine_mismatch"
            if compatible:
                rel = policy.get("relative_regression", {})
                comparisons = (
                    (
                        "cold_first_response_ms",
                        "higher",
                        _finite(rel.get("cold_latency_ratio", 1.4), 1.4),
                        _finite(rel.get("cold_latency_min_delta_ms", 5000), 5000),
                    ),
                    (
                        "warm_median_ms",
                        "higher",
                        _finite(rel.get("warm_median_ratio", 1.35), 1.35),
                        _finite(rel.get("warm_median_min_delta_ms", 1000), 1000),
                    ),
                    (
                        "throughput_equivalent_tps",
                        "lower",
                        _finite(rel.get("throughput_floor_ratio", 0.7), 0.7),
                        _finite(rel.get("throughput_min_delta_tps", 0.5), 0.5),
                    ),
                    (
                        "peak_rss_mb",
                        "higher",
                        _finite(rel.get("peak_rss_ratio", 1.3), 1.3),
                        _finite(rel.get("peak_rss_min_delta_mb", 256), 256),
                    ),
                    (
                        "suite_wall_ms",
                        "higher",
                        _finite(rel.get("suite_wall_ratio", 1.35), 1.35),
                        _finite(rel.get("suite_wall_min_delta_ms", 15000), 15000),
                    ),
                )
                for metric_key, direction, ratio, min_delta in comparisons:
                    current_value = _metric(report, metric_key)
                    baseline_value = _metric(baseline, metric_key)
                    regressed = (
                        _regressed_higher(current_value, baseline_value, ratio, min_delta)
                        if direction == "higher"
                        else _regressed_lower(current_value, baseline_value, ratio, min_delta)
                    )
                    if regressed:
                        relative_failures.append(
                            {
                                "metric": metric_key,
                                "direction": direction,
                                "actual": current_value,
                                "baseline": baseline_value,
                                "ratio_threshold": ratio,
                                "minimum_absolute_delta": min_delta,
                            }
                        )

    passed = not hard_failures and not relative_failures
    return {
        "passed": passed,
        "hard_limits_passed": not hard_failures,
        "relative_gate_applied": bool(baseline is not None and compatible),
        "comparison_status": comparison_status,
        "machine_mismatches": machine_mismatches,
        "missing_measurements": missing_measurements,
        "baseline_validation_failures": baseline_validation_failures,
        "hard_failures": hard_failures,
        "relative_failures": relative_failures,
    }


def enrich_report(
    report: dict[str, Any],
    policy: dict[str, Any],
    scenario_spec: dict[str, Any],
    baseline: dict[str, Any] | None = None,
) -> dict[str, Any]:
    enriched = deepcopy(report)
    required = [str(x) for x in scenario_spec.get("required_scenarios", [])]
    runtime_required = [str(x) for x in scenario_spec.get("local_runtime_required_scenarios", [])]
    platform = str(enriched.get("platform") or enriched.get("machine", {}).get("os", "")).strip()
    allowed_map = scenario_spec.get("allowed_local_runtimes_by_platform", {})
    allowed = [str(x) for x in allowed_map.get(platform, [])] if isinstance(allowed_map, dict) else []
    runtime_policy_available = bool(isinstance(allowed_map, dict) and platform in allowed_map and allowed)
    expected_suite = str(scenario_spec.get("suite", "")).strip()
    quality = evaluate_quality(
        enriched,
        required,
        runtime_required,
        allowed,
        runtime_policy_available,
        expected_suite,
    )
    performance = evaluate_performance(enriched, policy, baseline)
    enriched["evaluation"] = {
        "schema_version": SCHEMA_VERSION,
        "quality_gate": quality,
        "performance_gate": performance,
        "overall_passed": bool(quality["passed"] and performance["passed"]),
        "baseline_used": baseline is not None,
        "policy": policy,
    }
    return enriched


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Evaluate AuroraFox Core benchmark report")
    parser.add_argument("--report", required=True)
    parser.add_argument("--policy", required=True)
    parser.add_argument("--scenarios", required=True)
    parser.add_argument("--baseline")
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)

    report = load_json(args.report)
    policy = load_json(args.policy)
    scenarios = load_json(args.scenarios)
    baseline = load_json(args.baseline) if args.baseline else None
    enriched = enrich_report(report, policy, scenarios, baseline)
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(json.dumps(enriched, ensure_ascii=False, indent=2), encoding="utf-8")

    quality = enriched["evaluation"]["quality_gate"]
    performance = enriched["evaluation"]["performance_gate"]
    print(
        "AURORAFOX_CORE_BENCHMARK_EVALUATED "
        f"quality={quality['passed']} performance={performance['passed']} "
        f"relative={performance['relative_gate_applied']}"
    )
    return 0 if enriched["evaluation"]["overall_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
