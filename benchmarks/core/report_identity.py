"""Bind benchmark evidence to the checked-out source, not the CI event merge."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def checkout_sha(repo: Path, expected: str | None = None) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "--verify", "HEAD"],
        capture_output=True, text=True, check=False,
    )
    sha = result.stdout.strip()
    if result.returncode or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", sha):
        raise ValueError("Unable to identify benchmark source checkout")
    if expected is None:
        expected = os.environ.get("AURORAFOX_BENCHMARK_EXPECTED_SHA", "")
    if expected and expected != sha:
        raise ValueError(f"Benchmark source mismatch: actual={sha}, expected={expected}")
    return sha


def bind_report(path: Path, repo: Path = ROOT, expected: str | None = None) -> str:
    sha = checkout_sha(repo, expected)
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(data, dict):
        raise ValueError("Benchmark report must be an object")
    if data.get("git_sha") not in (None, "", sha):
        raise ValueError("Refusing to relabel a report from another source checkout")
    data["git_sha"] = sha
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, delete=False,
            prefix=f".{path.name}.", suffix=".tmp",
        ) as output:
            temporary = Path(output.name)
            json.dump(data, output, ensure_ascii=False, indent=2)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return sha


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        sha = bind_report(args.report, args.repo) if args.report else checkout_sha(args.repo)
    except (ValueError, OSError) as error:
        parser.exit(1, f"Benchmark report identity rejected: {error}\n")
    print(sha if args.report is None else f"AURORA_REPORT_SOURCE_SHA={sha}")


if __name__ == "__main__":
    main()
