from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SMOKE = ROOT / "benchmarks" / "core" / "code_specialist_smoke.gd"
WORKFLOW = ROOT / ".github" / "workflows" / "core-benchmarks.yml"


def test_specialist_team_runtime_smoke_uses_real_owned_code_specialist_path() -> None:
    smoke = SMOKE.read_text(encoding="utf-8")
    assert "SpecialistTeam.new()" in smoke
    assert "team.setup(client)" in smoke
    assert "specialist := team.coder" in smoke
    assert "specialist.analyze_request(" in smoke
    assert "specialist.review_code(" in smoke
    assert "specialist.explain_code(" in smoke
    assert "team_setup_ok" in smoke
    assert "specialist.get_parent() == team" in smoke
    assert "specialist.general_ai == client" in smoke
    assert 'str(info.get("last_runtime", "")) == "aurora_core_desktop"' in smoke
    assert 'int(info.get("ollama_failures", -1)) == 0' in smoke
    assert '"after_analyze": _runtime_evidence(runtime_after_analyze)' in smoke
    assert '"after_review": _runtime_evidence(runtime_after_review)' in smoke
    assert '"after_explain": _runtime_evidence(runtime_after_explain)' in smoke
    assert '"bounded_operations": ["analyze_request", "review_code", "explain_code"]' in smoke
    assert "http://1.1.1.1/" in smoke


def test_specialist_team_runtime_smoke_is_fail_fast_before_full_benchmark() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    start = workflow.index("- name: Run real SpecialistTeam / CodeSpecialist through bundled Core offline")
    end = workflow.index("- name: Run real bundled Core benchmark offline")
    specialist_step = workflow[start:end]
    assert "id: code_specialist_smoke" in specialist_step
    assert "continue-on-error: true" not in specialist_step
    assert "run_windows_code_specialist_smoke.ps1" in specialist_step
    assert start < end
