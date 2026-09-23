from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

STATIC_TESTS = (
    "evolution_engine/tests/test_evolution_foundation_contract.py",
    "evolution_engine/tests/test_core_tournament_adapter_contract.py",
    "evolution_engine/tests/test_acceptance_runner_contract.py",
    "evolution_engine/tests/test_windows_evidence_harness_contract.py",
)

GODOT_SMOKES = (
    "tests/self_improver_smoke.gd",
    "tests/core_candidate_benchmark_smoke.gd",
    "evolution_engine/tests/evolution_policy_smoke.gd",
    "evolution_engine/tests/evolution_evidence_smoke.gd",
    "evolution_engine/tests/evolution_controller_smoke.gd",
    "evolution_engine/tests/evolution_runtime_smoke.gd",
    "evolution_engine/tests/evolution_user_control_smoke.gd",
    "evolution_engine/tests/core_tournament_windows_smoke.gd",
)


def run(command: list[str]) -> None:
    print("+", " ".join(command), flush=True)
    subprocess.run(command, cwd=ROOT, check=True)


def resolve_godot(explicit: str) -> str:
    if explicit:
        return explicit
    env = os.environ.get("GODOT_BIN", "").strip()
    if env:
        return env
    for name in ("godot", "godot4"):
        found = shutil.which(name)
        if found:
            return found
    return ""


def main() -> int:
    parser = argparse.ArgumentParser(description="Run isolated AuroraFox Evolution Engine acceptance checks.")
    parser.add_argument("--godot", default="", help="Path to Godot 4.7.1 executable. Defaults to GODOT_BIN/godot/godot4.")
    parser.add_argument("--static-only", action="store_true", help="Run Python contract tests only.")
    args = parser.parse_args()

    run([sys.executable, "-m", "pytest", "-q", *STATIC_TESTS])

    if args.static_only:
        print("EVOLUTION_STATIC_CONTRACTS_OK")
        return 0

    godot = resolve_godot(args.godot)
    if not godot:
        print(
            "Godot executable is required for full Evolution acceptance. "
            "Set GODOT_BIN, pass --godot, or use --static-only.",
            file=sys.stderr,
        )
        return 2

    # A clean checkout has no Godot global-class cache yet. Import the project
    # before executing scripts so class_name dependencies resolve exactly as
    # they do after opening the project in the editor or in package CI.
    run([godot, "--headless", "--path", str(ROOT), "--import"])

    for script in GODOT_SMOKES:
        run([godot, "--headless", "--path", str(ROOT), "--script", script])

    print("AURORAFOX_EVOLUTION_ACCEPTANCE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
