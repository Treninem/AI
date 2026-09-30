#!/usr/bin/env python3
"""Inventory product limits and classify whether the owner can control them."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = ROOT / "config" / "owner_control_policy.json"
SOURCE_SUFFIXES = {".gd", ".py", ".kt", ".java", ".ps1", ".sh", ".yml", ".yaml"}
LIMIT_PATTERN = re.compile(
    r"\b(?:MAX|MIN|TIMEOUT|LIMIT|BUDGET|RETR(?:Y|IES)|CAP)[A-Z0-9_]*\b"
    r"|\bclamp[fi]?\s*\(|\.substr\s*\(\s*0\s*,\s*\d+|\.slice\s*\("
    r"|\btimeout\s*=\s*(?:\d|[A-Z_])",
    re.IGNORECASE,
)


def tracked_source_files() -> list[Path]:
    completed = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    files = []
    for value in completed.stdout.splitlines():
        path = ROOT / value
        if path.is_file() and path.suffix.lower() in SOURCE_SUFFIXES:
            files.append(path)
    return sorted(set(files))


def load_policy() -> dict:
    return json.loads(POLICY_PATH.read_text(encoding="utf-8"))


def classify(relative: str, text: str, policy: dict) -> tuple[str, str, str]:
    for row in policy.get("classifications", []):
        if row.get("path") != relative:
            continue
        if re.search(str(row.get("pattern", "")), text):
            return (
                str(row.get("class", "unclassified")),
                str(row.get("control", "")),
                str(row.get("rationale", "")),
            )
    return "unclassified", "", ""


def audit() -> dict:
    policy = load_policy()
    findings = []
    for path in tracked_source_files():
        relative = path.relative_to(ROOT).as_posix()
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue
        for number, line in enumerate(lines, 1):
            if not LIMIT_PATTERN.search(line):
                continue
            category, control, rationale = classify(relative, line, policy)
            findings.append(
                {
                    "path": relative,
                    "line": number,
                    "text": line.strip()[:300],
                    "class": category,
                    "control": control,
                    "rationale": rationale,
                }
            )
    counts: dict[str, int] = {}
    for item in findings:
        category = item["class"]
        counts[category] = counts.get(category, 0) + 1
    return {
        "schema": "aurorafox.owner-control-audit.v1",
        "policy": POLICY_PATH.relative_to(ROOT).as_posix(),
        "files_scanned": len(tracked_source_files()),
        "findings": len(findings),
        "counts": counts,
        "complete": counts.get("unclassified", 0) == 0,
        "items": findings,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()
    report = audit()
    rendered = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")
    if args.strict and not report["complete"]:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
