from __future__ import annotations

import argparse
import json
import subprocess
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RELEASE_EVIDENCE = ROOT / "agent" / "state" / "release_verification.json"
REQUIRED_RELEASE_GATES = {
    "android_apk",
    "android_emulator",
    "windows_package",
    "windows_install",
    "voice_core",
    "api_gateway",
    "api_privacy",
    "semantic_memory",
    "work_mode",
    "updater",
}


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


def current_version() -> str:
    try:
        data = json.loads(read("project/version.json"))
        return str(data.get("version", "V0.0.0.0"))
    except Exception:
        return "V0.0.0.0"


def repository_matches_verified_commit(commit: str) -> bool | None:
    """Return True when current committed state differs only by readiness evidence.

    The tag/source commit is stored in release_verification.json. The release bot
    may add that one evidence file to main after verification; no other committed
    change is allowed without forcing readiness back to false.
    """
    if len(commit.strip()) < 7:
        return False
    try:
        exists = subprocess.run(
            ["git", "-C", str(ROOT), "cat-file", "-e", f"{commit}^{{commit}}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if exists.returncode != 0:
            return False
        diff = subprocess.run(
            [
                "git", "-C", str(ROOT), "diff", "--quiet", f"{commit}..HEAD", "--", ".",
                ":(exclude)agent/state/release_verification.json",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return diff.returncode == 0
    except FileNotFoundError:
        return None
    except Exception:
        return False


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


def check_release_verification(weight: int = 24) -> Check:
    evidence: list[str] = []
    missing: list[str] = []
    rel = "agent/state/release_verification.json"
    if not RELEASE_EVIDENCE.exists():
        return Check(
            "release_verification",
            "Observed full release verification for current repository state",
            weight,
            False,
            [],
            [rel + ": no full release verification evidence for current repository state"],
        )
    evidence.append(rel)
    try:
        data = json.loads(RELEASE_EVIDENCE.read_text(encoding="utf-8"))
    except Exception as exc:
        return Check("release_verification", "Observed full release verification for current repository state", weight, False, evidence, [f"{rel}: invalid JSON: {exc}"])

    version = current_version()
    if not bool(data.get("verified", False)):
        missing.append(f"{rel}: verified=true is required")
    if str(data.get("version", "")) != version:
        missing.append(f"{rel}: version {data.get('version', '')!r} does not match {version!r}")
    passed = {str(item) for item in data.get("passed_gates", [])}
    absent = sorted(REQUIRED_RELEASE_GATES - passed)
    if absent:
        missing.append(f"{rel}: missing passed gates: {', '.join(absent)}")
    commit = str(data.get("commit", "")).strip()
    if len(commit) < 7:
        missing.append(f"{rel}: verified commit SHA is missing")
    else:
        matches = repository_matches_verified_commit(commit)
        if matches is None:
            missing.append(f"{rel}: Git is unavailable, so verified source state cannot be confirmed")
        elif not matches:
            missing.append(f"{rel}: repository code/config/tests changed after verified commit {commit[:12]}")

    return Check(
        "release_verification",
        "Observed full release verification for current repository state",
        weight,
        not missing,
        evidence,
        missing,
    )


def build_checks() -> list[Check]:
    return [
        check_files(
            "autonomous_cycle",
            "Autonomous research -> 3-10 mutations -> independent tests -> competition -> final test -> activation",
            12,
            [
                "agent/autonomous_coordinator.gd",
                "scripts/self_improver.gd",
                "scripts/runtime_extension_manager.gd",
                "tests/test_autonomous_evolution_contract.py",
                "tests/autonomous_coordinator_smoke.gd",
                "tests/self_improver_smoke.gd",
            ],
            {
                "agent/autonomous_coordinator.gd": [
                    "run_autonomous_cycle",
                    "run_mutation_tournament",
                    "mutation_population_size",
                    "_run_initial_cycle",
                    "activate_staged",
                    "synchronize_all",
                ],
                "scripts/self_improver.gd": [
                    "MIN_MUTATIONS := 3",
                    "MAX_MUTATIONS := 10",
                    "run_mutation_tournament",
                    "workspace_test",
                    "winner_final_test",
                    "_judge_verified_candidates",
                ],
            },
        ),
        check_files(
            "semantic_memory",
            "Semantic long-term memory and shared knowledge",
            8,
            ["scripts/memory_store.gd", "tests/semantic_memory_smoke.gd", ".github/workflows/memory-ci.yml"],
            {"scripts/memory_store.gd": ["retrieve", "reindex_semantic", "EMBEDDING_MODEL"]},
        ),
        check_files(
            "api_privacy",
            "External API with conversation isolation and private-by-default learning",
            8,
            ["api/server.py", "api/agent_bridge.gd", "api/learning_sync.py", "api/private_memory_view.gd", "api/private_experience_store.gd", "tests/test_api_privacy_contract.py", ".github/workflows/api-ci.yml"],
            {
                "api/agent_bridge.gd": ["ApiPrivateMemoryView", "ApiPrivateExperienceStore", "share_for_learning"],
                "api/learning_sync.py": ["skipped_private", "share_for_learning"],
            },
        ),
        check_files(
            "voice",
            "Local voice, wake word, STT/TTS and optional XTTS-v2",
            7,
            ["voice/voice_manager.gd", "voice/python/tts_engine.py", "voice/requirements_xtts.txt", "tests/test_xtts_contract.py", ".github/workflows/voice-ci.yml"],
            {"voice/python/tts_engine.py": ["XTTSVoiceEngine", "xtts_v2"]},
        ),
        check_files(
            "work_mode",
            "Persistent Work projects, tasks and artifacts",
            7,
            ["work", "tests/work_mode_smoke.gd", "tests/work_mode_store_smoke.gd", ".github/workflows/work-mode-ci.yml"],
        ),
        check_files(
            "android_release",
            "Android native runtime, signed APK and emulator gate",
            8,
            ["android_plugin", "build/build_android.ps1", "tests/test_android_contract.py", ".github/workflows/android-apk-artifact.yml", ".github/workflows/release.yml"],
            {
                ".github/workflows/android-apk-artifact.yml": ["android-emulator-runner", "adb install", "apksigner"],
                "build/build_android.ps1": ["AllowUnsignedRelease", "Android APK was not produced"],
            },
        ),
        check_files(
            "windows_release",
            "Windows export, installer and installed-app smoke",
            7,
            ["build/build_windows.ps1", "build/AuroraFox.iss", ".github/workflows/windows-package-ci.yml"],
            {".github/workflows/windows-package-ci.yml": ["Silent install and installed-app smoke", "Uninstaller missing"]},
        ),
        check_files(
            "file_intelligence",
            "Local knowledge, documents and project intelligence",
            5,
            ["file_intelligence/file_service.py", "file_intelligence/project_index_service.py"],
        ),
        check_files(
            "learning_sources",
            "Autonomous local and internet learning collector",
            5,
            ["agent/learning_collector.py"],
        ),
        check_files(
            "sandbox",
            "Sandbox, snapshots, rollback and verification",
            5,
            ["scripts/sandbox_manager.gd", "scripts/sandbox_tool_bridge.gd"],
            {"scripts/sandbox_manager.gd": ["snapshot", "rollback", "test"]},
        ),
        check_files(
            "updater",
            "Signed automatic self-update pipeline",
            5,
            ["update/update_manager.gd", "update/windows_updater.ps1", ".github/workflows/release.yml", "tests/update_smoke.gd"],
            {
                "update/update_manager.gd": ["auto_apply", "apply_downloaded_update", "update manifest RSA-SHA256 signature verified"],
                "tests/update_smoke.gd": ["auto_apply", "automatically applied"],
            },
        ),
        check_files(
            "versioning",
            "Canonical VMajor.Minor.Patch.Build version state",
            5,
            ["project/version.json", "agent/version_manager.py", "project.godot", "export_presets.cfg"],
            {"agent/version_manager.py": ["major", "minor", "patch", "build", "android_version_code"]},
        ),
        check_release_verification(18),
    ]


def audit() -> dict:
    checks = build_checks()
    total = sum(item.weight for item in checks)
    earned = sum(item.weight for item in checks if item.ok)
    percent = round((earned / total) * 100) if total else 0
    missing = [problem for item in checks for problem in item.missing]
    release_check = next((item for item in checks if item.key == "release_verification"), None)
    ready = bool(release_check and release_check.ok and all(item.ok for item in checks))
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
        "schema_version": 5,
        "generated_at": now_iso(),
        "version": current_version(),
        "progress_percent": percent,
        "ready": ready,
        "readiness_basis": "full release verification must match current version and current committed repository state",
        "required_release_gates": sorted(REQUIRED_RELEASE_GATES),
        "checks": [asdict(item) for item in checks],
        "missing": missing,
        "plan": plan,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="One-shot AuroraFox architecture and verified-release audit")
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
