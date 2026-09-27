from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "evolution_engine/tests/run_windows_evidence.ps1"


def read_harness() -> str:
    return HARNESS.read_text(encoding="utf-8")


def test_windows_evidence_is_bound_to_exact_clean_native_checkout():
    text = read_harness()
    assert "[ValidatePattern('^[0-9a-fA-F]{40}$')]" in text
    assert "$env:OS -ne 'Windows_NT'" in text
    assert "git rev-parse HEAD" in text
    assert "$actual -ne $expected" in text
    assert "git status --porcelain --untracked-files=all" in text
    assert "requires a clean checkout" in text


def test_windows_evidence_requires_exact_godot_and_full_acceptance():
    text = read_harness()
    assert "^4\\.7\\.1(?:[.-]|$)" in text
    assert "evolution_engine/tests/run_evolution_checks.py --godot" in text
    assert "AURORAFOX_EVOLUTION_ACCEPTANCE_OK" in text
    assert "native_windows=true" in text
    assert "native_windows=false" in text
    assert "$runnerExit -eq 0" in text


def test_windows_evidence_writes_hashed_machine_readable_result():
    text = read_harness()
    assert "Get-FileHash $logPath -Algorithm SHA256" in text
    assert "schema_version = 1" in text
    assert "expected_head = $expected" in text
    assert "pre_run_clean = $true" in text
    assert "native_tournament_marker = $nativeMarker" in text
    assert "log_sha256 = $logSha256" in text
    assert "ConvertTo-Json" in text
    assert "AURORAFOX_EVOLUTION_WINDOWS_EVIDENCE_OK" in text
