from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_acceptance_runner_keeps_existing_foundation_smokes():
    text = (ROOT / "evolution_engine/tests/run_evolution_checks.py").read_text(encoding="utf-8")
    assert "tests/self_improver_smoke.gd" in text
    assert "tests/core_candidate_benchmark_smoke.gd" in text
    assert "evolution_policy_smoke.gd" in text
    assert "evolution_evidence_smoke.gd" in text
    assert "evolution_controller_smoke.gd" in text


def test_acceptance_runner_requires_godot_unless_static_only():
    text = (ROOT / "evolution_engine/tests/run_evolution_checks.py").read_text(encoding="utf-8")
    assert "--static-only" in text
    assert "return 2" in text
    assert "Godot executable is required" in text
    assert "AURORAFOX_EVOLUTION_ACCEPTANCE_OK" in text


def test_windows_core_tournament_smoke_is_platform_scoped():
    text = (ROOT / "evolution_engine/tests/run_evolution_checks.py").read_text(encoding="utf-8")
    smoke = (ROOT / "evolution_engine/tests/core_tournament_windows_smoke.gd").read_text(encoding="utf-8")
    assert 'platform.system() == "Windows"' in text
    assert "core_tournament_windows_smoke.gd" in text
    assert 'OS.get_name() != "Windows"' in smoke
    assert "store_calls != 0" in smoke
    assert "store_calls != 1" in smoke
    assert "signed_update" in smoke
