from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path, PurePosixPath
from typing import Any

ALLOWED_TARGETS = {
    "scripts/cognition_layer.gd",
    "scripts/agent_core.gd",
    "scripts/memory_store.gd",
    "agent/goals.gd",
}
MAX_CANDIDATE_BYTES = 1024 * 1024
MAX_SOURCE_GROWTH_RATIO = 1.35
RISKY_PRIMITIVES = (
    "OS.execute(",
    "OS.create_process(",
    "HTTPRequest.new(",
    "HTTPClient.new(",
    "TCPServer.new(",
    "StreamPeerTCP.new(",
    "PacketPeerUDP.new(",
    "WebSocketPeer.new(",
    "JavaScriptBridge",
    "Engine.get_singleton(",
)
CANDIDATE_ID_RE = re.compile(r"^[A-Za-z0-9._-]{1,80}$")


class CandidateVerificationError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().lower()


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _public_functions(source: str) -> list[str]:
    out: set[str] = set()
    for raw in source.splitlines():
        line = raw.strip()
        if not line.startswith("func "):
            continue
        name = line.removeprefix("func ").split("(", 1)[0].strip()
        if name and not name.startswith("_"):
            out.add(name)
    return sorted(out)


def _signals(source: str) -> list[str]:
    out: set[str] = set()
    for raw in source.splitlines():
        line = raw.strip()
        if not line.startswith("signal "):
            continue
        tail = line.removeprefix("signal ").strip()
        name = tail.split("(", 1)[0].split(" ", 1)[0].strip()
        if name:
            out.add(name)
    return sorted(out)


def source_contract(original: str, candidate: str, target: str) -> dict[str, Any]:
    baseline_public = _public_functions(original)
    candidate_public = _public_functions(candidate)
    missing_public = sorted(set(baseline_public) - set(candidate_public))
    baseline_signals = _signals(original)
    candidate_signals = _signals(candidate)
    missing_signals = sorted(set(baseline_signals) - set(candidate_signals))
    risky_increases: dict[str, dict[str, int]] = {}
    for marker in RISKY_PRIMITIVES:
        before = original.count(marker)
        after = candidate.count(marker)
        if after > before:
            risky_increases[marker] = {"before": before, "after": after}
    baseline_bytes = len(original.encode("utf-8"))
    candidate_bytes = len(candidate.encode("utf-8"))
    growth_ratio = candidate_bytes / max(1, baseline_bytes)
    growth_ok = growth_ratio <= MAX_SOURCE_GROWTH_RATIO
    return {
        "ok": not missing_public and not missing_signals and not risky_increases and growth_ok,
        "target": target,
        "baseline_public_functions": baseline_public,
        "candidate_public_functions": candidate_public,
        "missing_public_functions": missing_public,
        "baseline_signals": baseline_signals,
        "candidate_signals": candidate_signals,
        "missing_signals": missing_signals,
        "risky_primitive_increases": risky_increases,
        "baseline_bytes": baseline_bytes,
        "candidate_bytes": candidate_bytes,
        "growth_ratio": growth_ratio,
        "max_growth_ratio": MAX_SOURCE_GROWTH_RATIO,
        "growth_ok": growth_ok,
    }


def _safe_target(raw: Any) -> str:
    target = str(raw or "").strip()
    if "\\" in target or target.startswith("/"):
        raise CandidateVerificationError("candidate target is not a canonical repository path")
    parts = PurePosixPath(target).parts
    if not parts or any(part in {"", ".", ".."} for part in parts):
        raise CandidateVerificationError("candidate target contains unsafe path components")
    if target not in ALLOWED_TARGETS:
        raise CandidateVerificationError(f"candidate target is outside the promotion allowlist: {target}")
    return target


def _inside(root: Path, child: Path) -> bool:
    root = root.resolve()
    child = child.resolve()
    return child == root or root in child.parents


def verify_bundle(project: Path, bundle: Path, *, apply: bool = False) -> dict[str, Any]:
    project = project.resolve(strict=True)
    bundle = bundle.resolve(strict=True)
    manifest_path = bundle / "candidate.json"
    if not manifest_path.is_file() or not _inside(bundle, manifest_path):
        raise CandidateVerificationError("candidate.json is missing or escapes the bundle")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise CandidateVerificationError(f"candidate.json is invalid: {exc}") from exc
    if not isinstance(manifest, dict):
        raise CandidateVerificationError("candidate.json must contain an object")

    candidate_id = str(manifest.get("candidate_id", "")).strip()
    if not CANDIDATE_ID_RE.fullmatch(candidate_id):
        raise CandidateVerificationError("candidate_id is missing or unsafe")
    target = _safe_target(manifest.get("target"))
    if manifest.get("verified") is not True:
        raise CandidateVerificationError("client manifest does not mark the candidate verified")
    if str(manifest.get("promotion", "")) != "signed_update":
        raise CandidateVerificationError("candidate was not staged for the signed-update boundary")

    verification = manifest.get("verification")
    if not isinstance(verification, dict):
        raise CandidateVerificationError("verification evidence is missing")
    source_evidence = verification.get("source_contract")
    review_evidence = verification.get("comparative_review")
    if not isinstance(source_evidence, dict) or source_evidence.get("ok") is not True:
        raise CandidateVerificationError("source-contract evidence is missing or failed")
    if not isinstance(review_evidence, dict) or review_evidence.get("ok") is not True:
        raise CandidateVerificationError("comparative-review evidence is missing or failed")

    base_path = (project / target).resolve(strict=True)
    candidate_path = (bundle / target).resolve(strict=True)
    if not _inside(project, base_path):
        raise CandidateVerificationError("base target escapes the checked-out project")
    if not _inside(bundle, candidate_path) or not candidate_path.is_file():
        raise CandidateVerificationError("candidate source is missing or escapes the bundle")
    if candidate_path.stat().st_size <= 0 or candidate_path.stat().st_size > MAX_CANDIDATE_BYTES:
        raise CandidateVerificationError("candidate source is empty or exceeds the 1 MiB limit")

    base_sha = sha256_file(base_path)
    candidate_sha = sha256_file(candidate_path)
    expected_base = str(manifest.get("base_sha256", "")).lower()
    expected_candidate = str(manifest.get("candidate_sha256", "")).lower()
    if base_sha != expected_base:
        raise CandidateVerificationError("candidate base SHA-256 does not match current main")
    if candidate_sha != expected_candidate:
        raise CandidateVerificationError("candidate source SHA-256 does not match candidate.json")
    if base_sha == candidate_sha:
        raise CandidateVerificationError("candidate is byte-identical to current source")

    original_text = _read_text(base_path)
    candidate_text = _read_text(candidate_path)
    contract = source_contract(original_text, candidate_text, target)
    if not contract["ok"]:
        raise CandidateVerificationError(
            "independent source contract rejected the candidate: "
            + json.dumps(contract, ensure_ascii=False, separators=(",", ":"))
        )

    report: dict[str, Any] = {
        "ok": True,
        "candidate_id": candidate_id,
        "target": target,
        "base_sha256": base_sha,
        "candidate_sha256": candidate_sha,
        "source_contract": contract,
        "client_verification_present": True,
        "client_review_present": True,
        "promotion_boundary": "ci_verified_pr_then_normal_signed_release",
    }
    if apply:
        shutil.copyfile(candidate_path, base_path)
        applied_sha = sha256_file(base_path)
        if applied_sha != candidate_sha:
            raise CandidateVerificationError("post-apply SHA-256 verification failed")
        report["applied"] = True
        report["applied_sha256"] = applied_sha
    else:
        report["applied"] = False
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="Independently verify an AuroraFox Core candidate bundle.")
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--bundle", required=True, type=Path)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        report = verify_bundle(args.project, args.bundle, apply=args.apply)
    except CandidateVerificationError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        return 2
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
