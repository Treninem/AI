from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[1]
VERSION_PATH = ROOT / "project" / "version.json"
PROJECT_GODOT = ROOT / "project.godot"
EXPORT_PRESETS = ROOT / "export_presets.cfg"
MANIFEST = ROOT / "update" / "manifest.template.json"
CHANGELOG = ROOT / "CHANGELOG.md"
EVOLUTION_LOG = ROOT / "evolution.log"
VERSION_RE = re.compile(r"^[Vv]?(\d+)\.(\d+)\.(\d+)\.(\d+)$")


@dataclass(frozen=True)
class AuroraVersion:
    major: int
    minor: int
    patch: int
    build: int

    @property
    def numeric(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}.{self.build}"

    @property
    def display(self) -> str:
        return f"V{self.numeric}"

    @classmethod
    def parse(cls, value: str) -> "AuroraVersion":
        match = VERSION_RE.match((value or "").strip())
        if not match:
            raise ValueError("Version must use V<Major>.<Minor>.<Patch>.<Build>")
        parts = tuple(int(part) for part in match.groups())
        return cls(*parts)

    def bump(self, kind: str) -> "AuroraVersion":
        kind = kind.lower().strip()
        if kind == "major":
            return AuroraVersion(self.major + 1, 0, 0, 0)
        if kind == "minor":
            return AuroraVersion(self.major, self.minor + 1, 0, 0)
        if kind == "patch":
            # AuroraFox rule: a patch increments Patch and also records a new Build.
            return AuroraVersion(self.major, self.minor, self.patch + 1, self.build + 1)
        if kind == "build":
            return AuroraVersion(self.major, self.minor, self.patch, self.build + 1)
        raise ValueError(f"Unknown bump kind: {kind}")


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".aurora-tmp")
    tmp.write_text(text, encoding="utf-8", newline="\n")
    tmp.replace(path)


def load_state() -> tuple[AuroraVersion, dict]:
    if VERSION_PATH.exists():
        state = read_json(VERSION_PATH)
        version = AuroraVersion.parse(str(state.get("version") or state.get("numeric") or ""))
        return version, state

    text = PROJECT_GODOT.read_text(encoding="utf-8")
    match = re.search(r'config/version="([^"]+)"', text)
    if not match:
        raise RuntimeError("project.godot does not contain application/config/version")
    legacy = match.group(1).split(".")
    if len(legacy) == 3:
        legacy.append("0")
    version = AuroraVersion.parse(".".join(legacy))
    return version, {
        "android_version_code": 1,
        "status": "evolving",
        "auto_increment": True,
    }


def replace_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise RuntimeError(f"Could not synchronize {label}")
    return updated


def sync_project_godot(version: AuroraVersion) -> str:
    text = PROJECT_GODOT.read_text(encoding="utf-8")
    return replace_once(
        text,
        r'config/version="[^"]+"',
        f'config/version="{version.numeric}"',
        "project.godot config/version",
    )


def sync_export_presets(version: AuroraVersion, android_code: int) -> str:
    text = EXPORT_PRESETS.read_text(encoding="utf-8")
    text = replace_once(text, r'version/name="[^"]+"', f'version/name="{version.numeric}"', "Android version/name")
    text = replace_once(text, r'version/code=\d+', f'version/code={android_code}', "Android version/code")
    return text


def sync_manifest(version: AuroraVersion) -> str:
    data = read_json(MANIFEST)
    data["version"] = version.numeric
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


def render_state(previous: dict, version: AuroraVersion, android_code: int, reason: str) -> str:
    state = dict(previous)
    state.update(
        {
            "version": version.display,
            "numeric": version.numeric,
            "major": version.major,
            "minor": version.minor,
            "patch": version.patch,
            "build": version.build,
            "android_version_code": android_code,
            "status": str(previous.get("status", "evolving")),
            "auto_increment": bool(previous.get("auto_increment", True)),
            "updated_at": utc_now(),
            "reason": reason,
        }
    )
    return json.dumps(state, ensure_ascii=False, indent=2) + "\n"


def append_changelog(version: AuroraVersion, reason: str) -> str:
    current = CHANGELOG.read_text(encoding="utf-8") if CHANGELOG.exists() else "# AuroraFox Changelog\n\n"
    header = f"## {version.display} — {datetime.now(timezone.utc).date().isoformat()}"
    if header in current:
        return current
    entry = f"{header}\n\n- {reason.strip() or 'Autonomous evolution update'}\n\n"
    if current.startswith("# AuroraFox Changelog"):
        head, _, tail = current.partition("\n\n")
        return head + "\n\n" + entry + tail
    return "# AuroraFox Changelog\n\n" + entry + current


def append_evolution(version: AuroraVersion, reason: str) -> str:
    current = EVOLUTION_LOG.read_text(encoding="utf-8") if EVOLUTION_LOG.exists() else ""
    line = f"[{utc_now()}] {version.display} — {reason.strip() or 'autonomous evolution update'}\n"
    return current + line


def validate_generated(files: Iterable[tuple[Path, str]], version: AuroraVersion, android_code: int) -> None:
    mapping = {path: text for path, text in files}
    if f'config/version="{version.numeric}"' not in mapping[PROJECT_GODOT]:
        raise RuntimeError("Generated project.godot version validation failed")
    if f'version/name="{version.numeric}"' not in mapping[EXPORT_PRESETS]:
        raise RuntimeError("Generated Android version/name validation failed")
    if f"version/code={android_code}" not in mapping[EXPORT_PRESETS]:
        raise RuntimeError("Generated Android version/code validation failed")
    manifest = json.loads(mapping[MANIFEST])
    if str(manifest.get("version")) != version.numeric:
        raise RuntimeError("Generated update manifest version validation failed")
    state = json.loads(mapping[VERSION_PATH])
    if str(state.get("version")) != version.display:
        raise RuntimeError("Generated version.json validation failed")


def apply_version(target: AuroraVersion, reason: str, dry_run: bool = False) -> dict:
    current, state = load_state()
    current_code = max(1, int(state.get("android_version_code", 1)))
    changed = target != current
    android_code = current_code + 1 if changed else current_code
    if android_code > 2_100_000_000:
        raise RuntimeError("Android versionCode limit reached")

    generated = [
        (PROJECT_GODOT, sync_project_godot(target)),
        (EXPORT_PRESETS, sync_export_presets(target, android_code)),
        (MANIFEST, sync_manifest(target)),
        (VERSION_PATH, render_state(state, target, android_code, reason)),
        (CHANGELOG, append_changelog(target, reason)),
        (EVOLUTION_LOG, append_evolution(target, reason)),
    ]
    validate_generated(generated, target, android_code)

    if not dry_run:
        for path, text in generated:
            atomic_write(path, text)

    return {
        "ok": True,
        "changed": changed,
        "previous": current.display,
        "version": target.display,
        "numeric": target.numeric,
        "android_version_code": android_code,
        "reason": reason,
        "dry_run": dry_run,
        "updated_files": [str(path.relative_to(ROOT)).replace("\\", "/") for path, _ in generated],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="AuroraFox VMajor.Minor.Patch.Build version manager")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--bump", choices=["major", "minor", "patch", "build"])
    group.add_argument("--set", dest="set_version")
    group.add_argument("--show", action="store_true")
    parser.add_argument("--reason", default="Autonomous evolution update")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    current, state = load_state()
    if args.show:
        payload = {
            "version": current.display,
            "numeric": current.numeric,
            "android_version_code": int(state.get("android_version_code", 1)),
        }
    else:
        target = current.bump(args.bump) if args.bump else AuroraVersion.parse(args.set_version)
        payload = apply_version(target, args.reason, args.dry_run)

    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print(payload["version"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
