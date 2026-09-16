from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Owner-approved immutable source masters landed in c41a9996692d4588592ecf5735e2c72a10ceb9f2.
# Pin Git blob identity so a byte-level replacement cannot silently pass as the same branding.
EXPECTED_MASTER_BLOBS = {
    "assets/ui/aurorafox_avatar_master.png": "89ff783b171733f88b5153acd24c6a28fb2953dd",
    "assets/ui/aurorafox_background_master.png": "ed17e933244b7ce0f520b28897c0ca1ad50a5347",
}


def _git_blob_sha(path: Path) -> str:
    payload = path.read_bytes()
    header = f"blob {len(payload)}\0".encode("ascii")
    return hashlib.sha1(header + payload).hexdigest()


def test_owner_approved_branding_masters_are_byte_exact() -> None:
    for relative, expected in EXPECTED_MASTER_BLOBS.items():
        path = ROOT / relative
        assert path.is_file(), f"missing owner-approved branding master: {relative}"
        assert _git_blob_sha(path) == expected, f"branding master changed byte-for-byte: {relative}"


def test_runtime_uses_owner_approved_branding_without_legacy_substitution() -> None:
    runtime = (ROOT / "scripts/main.gd").read_text(encoding="utf-8")
    assert 'res://assets/ui/aurorafox_avatar_master.png' in runtime
    assert 'res://assets/ui/aurorafox_background_master.png' in runtime
    assert 'res://assets/ui/fox_logo.svg' not in runtime
    assert 'res://assets/ui/aurora_background.svg' not in runtime


def test_integration_gate_executes_branding_identity_contract() -> None:
    workflow = (ROOT / ".github/workflows/integration-gate.yml").read_text(encoding="utf-8")
    assert "Owner-approved branding identity contract" in workflow
    assert "tests/test_release_branding_contract.py" in workflow
