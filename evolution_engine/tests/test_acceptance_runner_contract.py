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
    assert "evolution_runtime_smoke.gd" in text


def test_acceptance_runner_requires_godot_unless_static_only():
    text = (ROOT / "evolution_engine/tests/run_evolution_checks.py").read_text(encoding="utf-8")
    assert "--static-only" in text
    assert "return 2" in text
    assert "Godot executable is required" in text
    assert "AURORAFOX_EVOLUTION_ACCEPTANCE_OK" in text


def test_acceptance_runner_imports_clean_checkout_before_godot_smokes():
    text = (ROOT / "evolution_engine/tests/run_evolution_checks.py").read_text(encoding="utf-8")
    import_command = 'run([godot, "--headless", "--path", str(ROOT), "--import"])'
    assert import_command in text
    assert text.index(import_command) < text.index("for script in GODOT_SMOKES")


def test_core_tournament_logic_runs_everywhere_without_weakening_windows_gate():
    text = (ROOT / "evolution_engine/tests/run_evolution_checks.py").read_text(encoding="utf-8")
    smoke = (ROOT / "evolution_engine/tests/core_tournament_windows_smoke.gd").read_text(encoding="utf-8")
    adapter = (ROOT / "evolution_engine/evaluation/core_tournament_adapter.gd").read_text(encoding="utf-8")
    assert "core_tournament_windows_smoke.gd" in text
    assert "class ContractTestAdapter" in smoke
    assert "var native_windows := OS.get_name() == \"Windows\"" in smoke
    assert "AuroraEvolutionCoreTournamentAdapter.new() if native_windows else ContractTestAdapter.new()" in smoke
    assert 'return OS.get_name() == "Windows"' in adapter
    assert "if not _platform_supported()" in adapter
    assert "store_calls != 0" in smoke
    assert "store_calls != 1" in smoke
    assert "signed_update" in smoke
