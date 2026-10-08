#!/usr/bin/env python3
"""Deterministic tracked-file inventory and static product-quality audit.

This does not pretend to replace runtime, render, package or device acceptance.
It gives those later gates an exact byte ledger and catches source/resource
defects that should never reach them.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path


TEXT_EXTENSIONS = {
    ".cfg", ".cpp", ".gd", ".gdignore", ".gitignore", ".godot", ".iss",
    ".json", ".kt", ".kts", ".md", ".properties", ".ps1", ".pub", ".py",
    ".sha256", ".sh", ".svg", ".tscn", ".txt", ".xml", ".yml", ".yaml",
}
JSON_EXTENSIONS = {".json"}
XML_EXTENSIONS = {".svg", ".xml"}
LOAD_RESOURCE_PATTERN = re.compile(r"(?:preload|load)\(\s*[\"']res://([^\"']+)[\"']\s*\)")
CONFIG_RESOURCE_PATTERN = re.compile(r"=\s*[\"']res://([^\"']+)[\"']")
PLACEHOLDER_PATTERN = re.compile(r"\b(?:TODO|FIXME|HACK|PLACEHOLDER|NOT_IMPLEMENTED)\b", re.I)
EMPTY_CONTROL_PATTERN = re.compile(r"\b(?:text|tooltip_text)\s*=\s*[\"']\s*[\"']")


def _tracked(root: Path) -> list[str]:
    raw = subprocess.check_output(
        ["git", "ls-files", "-z"], cwd=root, stderr=subprocess.DEVNULL
    )
    return sorted(part.decode("utf-8") for part in raw.split(b"\0") if part)


def _issue(severity: str, code: str, path: str, detail: str) -> dict[str, str]:
    return {"severity": severity, "code": code, "path": path, "detail": detail}


def audit(root: Path) -> dict[str, object]:
    files: list[dict[str, object]] = []
    issues: list[dict[str, str]] = []
    extensions: Counter[str] = Counter()
    total_bytes = 0
    tracked = _tracked(root)

    for relative in tracked:
        path = root / relative
        if not path.is_file():
            issues.append(_issue("critical", "tracked_file_missing", relative, "tracked path is not a file"))
            continue
        data = path.read_bytes()
        suffix = path.suffix.lower()
        extensions[suffix or "<none>"] += 1
        total_bytes += len(data)
        row: dict[str, object] = {
            "path": relative,
            "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
            "extension": suffix or "<none>",
        }
        if suffix in TEXT_EXTENSIONS or path.name in {"AGENTS.md", "LICENSE"}:
            try:
                text = data.decode("utf-8")
                row["utf8"] = True
            except UnicodeDecodeError as exc:
                row["utf8"] = False
                issues.append(_issue("critical", "invalid_utf8", relative, str(exc)))
                files.append(row)
                continue
            if "\x00" in text:
                issues.append(_issue("critical", "nul_in_text", relative, "NUL byte in a text file"))
            if suffix in JSON_EXTENSIONS:
                try:
                    json.loads(text)
                except json.JSONDecodeError as exc:
                    issues.append(_issue("critical", "invalid_json", relative, str(exc)))
            if suffix in XML_EXTENSIONS:
                try:
                    ET.fromstring(text)
                except ET.ParseError as exc:
                    issues.append(_issue("critical", "invalid_xml", relative, str(exc)))
            resource_matches = list(LOAD_RESOURCE_PATTERN.finditer(text)) if suffix == ".gd" else []
            if suffix in {".cfg", ".godot", ".tscn"}:
                resource_matches.extend(CONFIG_RESOURCE_PATTERN.finditer(text))
            for match in resource_matches:
                resource = match.group(1).split("::", 1)[0]
                if not (root / resource).exists():
                    issues.append(_issue("critical", "missing_static_res_reference", relative, resource))
            placeholders = len(PLACEHOLDER_PATTERN.findall(text))
            if placeholders:
                issues.append(_issue("warning", "placeholder_marker", relative, str(placeholders)))
            empty_controls = len(EMPTY_CONTROL_PATTERN.findall(text))
            if empty_controls:
                issues.append(_issue("warning", "empty_control_text", relative, str(empty_controls)))
        files.append(row)

    severity = Counter(str(item["severity"]) for item in issues)
    return {
        "schema": "aurorafox.product-quality-audit.v1",
        "scope": "git-tracked-files",
        "limitations": [
            "static inventory is not runtime behavior proof",
            "pixel/layout acceptance requires rendered matrices and device artifacts",
            "performance acceptance requires measured package/device runs",
        ],
        "summary": {
            "tracked_files": len(tracked),
            "audited_files": len(files),
            "total_bytes": total_bytes,
            "critical": severity["critical"],
            "warning": severity["warning"],
            "extensions": dict(sorted(extensions.items())),
        },
        "issues": issues,
        "files": files,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--fail-on-critical", action="store_true")
    args = parser.parse_args()
    report = audit(args.root.resolve())
    encoded = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
    else:
        sys.stdout.write(encoded)
    return 1 if args.fail_on_critical and report["summary"]["critical"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
