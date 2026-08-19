from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@dataclass
class Check:
    key: str
    title: str
    weight: int
    ok: bool
    evidence: list[str]
    missing: list[str]


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read(path: str) -> str:
    target = ROOT / path
    if not target.exists() or not target.is_file():
        return ""
    return target.read_text(encoding="utf-8", errors="replace")


def check_files(key: str, title: str, weight: int, files: list[str], markers: dict[str, list[str]] | None = None) -> Check:
    evidence: list[str] = []
    missing: list[str] = []
    markers = markers or {}
    for rel in files:
        target = ROOT / rel
        if not target.exists():
            missing.append(rel)
            continue
        evidence.append(rel)
        text = target.read_text(encoding="utf-8", errors="replace") if target.is_file() else ""
        for marker in markers.get(rel, []):
            if marker not in text:
                missing.append(f"{rel}: marker {marker!r}")
    return Check(key, title, weight, not missing, evidence, missing)


def build_checks() -> list[Check]:
    return [
        check_files(
            "autonomous_cycle",
            "Observation -> analysis -> mutation -> test -> activation -> synchronization",
            18,
            ["agent/autonomous_coordinator.gd", "scripts/self_improver.gd", "scripts/runtime_extension_manager.gd"],
            {
                "agent/autonomous_coordinator.gd": ["run_autonomous_cycle", "propose_improvement", "activate_staged", "synchronize_all"],
                "scripts/self_improver.gd": ["evaluate_generated_module", "workspace_test"],
            },
        ),
        check_files(
            "file_intelligence",
            "Local knowledge and project intelligence",
            12,
            ["file_intelligence/file_service.py", "file_intelligence/project_index_service.py"],
        ),
        check_files(
            "learning_sources",
            "Autonomous local and internet learning collector",
            12,
            ["agent/learning_collector.py"],
        ),
        check_files(
            "sandbox",
            "Sandbox, snapshots, rollback and verification",
            12,
            ["scripts/sandbox_manager.gd", "scripts/sandbox_tool_bridge.gd"],
            {"scripts/sandbox_manager.gd": ["snapshot", "rollback", "test"]},
        ),
        check_files(
            "updater",
            "Existing signed self-update pipeline",
            10,
            ["update/update_manager.gd", "update/windows_updater.ps1", ".github/workflows/release.yml"],
        ),
        check_files(
            "versioning",
            "Canonical VMajor.Minor.Patch.Build version state",
            12,
            ["project/version.json", "agent/version_manager.py", "project.godot"],
            {"agent/version_manager.py": ["major", "minor", "patch", "build", "android_version_code"]},
        ),
        check_files(
            "history",
            "Evolution and changelog history",
            6,
            ["CHANGELOG.md", "evolution.log"],
        ),
        check_files(
            "progress",
            "Real-time local release progress reporting",
            8,
            ["agent/progress_tracker.py", "assets/ui/progress_bar.tscn"],
        ),
        check_files(
            "ci",
            "Automated audit, smoke and release gates",
            10,
            [".github/workflows/agent-sync-ci.yml", ".github/workflows/voice-ci.yml", ".github/workflows/progress.yml"],
        ),
    ]


def audit() -> dict:
    checks = build_checks()
    total = sum(item.weight for item in checks)
    earned = sum(item.weight for item in checks if item.ok)
    percent = round((earned / total) * 100) if total else 0
    missing = [problem for item in checks for problem in item.missing]
    plan = [
        {
            "key": item.key,
            "title": item.title,
            "weight": item.weight,
            "action": "keep" if item.ok else "complete",
            "missing": item.missing,
        }
        for item in checks
    ]
    return {
        "schema_version": 1,
        "generated_at": now_iso(),
        "progress_percent": percent,
        "ready": percent == 100,
        "checks": [asdict(item) for item in checks],
        "missing": missing,
        "plan": plan,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="One-shot AuroraFox autonomous architecture audit")
    parser.add_argument("--output", default="", help="Optional JSON report path relative to repository root")
    parser.add_argument("--compact", action="store_true")
    args = parser.parse_args()

    report = audit()
    text = json.dumps(report, ensure_ascii=False, indent=None if args.compact else 2) + "\n"
    if args.output:
        target = (ROOT / args.output).resolve()
        if ROOT not in target.parents and target != ROOT:
            raise SystemExit("Output path must stay inside the repository")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8", newline="\n")
    print(text, end="")
    return 0 if report["ready"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
