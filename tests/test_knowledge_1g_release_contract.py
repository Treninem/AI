from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "knowledge-1g-release-gate.yml"


def test_release_gate_runs_real_one_gib_streaming_import_and_restart() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    assert "Checkout exact SHA" in text
    assert "KNOWLEDGE_1G_HEAD_SHA=" in text
    assert "--scenario import_jsonl" in text
    assert "--target-mb 1024" in text
    assert "--timeout-seconds 3600" in text
    assert "restart_check" in text
    assert "1024 * 1024 * 1024" in text
    assert "1536 * 1024 * 1024" in text
    assert "network_required" in text
    assert "external_runtime_required" in text
    assert "ollama_required" in text
    assert "uses: actions/upload-artifact@v4" in text
