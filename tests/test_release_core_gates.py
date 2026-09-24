from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / ".github" / "workflows" / "release.yml"


def _workflow() -> str:
    return RELEASE.read_text(encoding="utf-8")


def test_signed_release_is_blocked_by_core_gates() -> None:
    text = _workflow()
    assert "  core-gates:\n" in text
    assert "  windows:\n    needs: core-gates\n" in text
    assert "  android:\n    needs: core-gates\n" in text
    publish = text[text.index("  publish:\n") :]
    assert "needs: [windows, android]" in publish
    assert "startsWith(github.ref, 'refs/tags/v')" in publish
    assert "needs.windows.result == 'success'" in publish
    assert "needs.android.result == 'success'" in publish
    assert "github.event_name == 'workflow_dispatch'" in publish
    assert "inputs.publish_run_id != ''" in publish


def test_latest_recovery_knowledge_and_rewrite_gates_run_before_builds() -> None:
    text = _workflow()
    core_start = text.index("  core-gates:\n")
    windows_start = text.index("  windows:\n")
    android_start = text.index("  android:\n")
    publish_start = text.index("  publish:\n")
    assert core_start < windows_start < android_start < publish_start
    for script in (
        "tests/local_semantic_memory_smoke.gd",
        "tests/local_model_failover_smoke.gd",
        "tests/knowledge_registry_smoke.gd",
        "tests/large_knowledge_streaming_smoke.gd",
        "tests/monolithic_json_stream_smoke.gd",
        "tests/knowledge_transaction_rollback_smoke.gd",
        "tests/core_candidate_benchmark_smoke.gd",
    ):
        assert script in text[core_start:windows_start]
    assert "tests/test_core_candidate_promotion.py" in text[core_start:windows_start]


def test_release_signature_is_after_all_build_dependencies() -> None:
    text = _workflow()
    publish_start = text.index("  publish:\n")
    sign_step = text.index("      - name: Sign update manifest with pinned AuroraFox release key", publish_start)
    manifest_step = text.index("      - name: Generate verified update manifest and release evidence", publish_start)
    assert publish_start < manifest_step < sign_step
    assert "UPDATE_KEY_B64: ${{ secrets.AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64 }}" in text[sign_step:]
    assert "needs: [windows, android]" in text[publish_start:sign_step]


def test_release_evidence_names_new_blocking_gates() -> None:
    text = _workflow()
    for gate in (
        "local_semantic_memory",
        "local_model_failover",
        "knowledge_registry",
        "large_knowledge_streaming",
        "monolithic_json_streaming",
        "knowledge_transaction_rollback",
        "core_candidate_benchmark",
        "core_candidate_promotion",
    ):
        assert f"'{gate}'" in text


def test_promotion_workflow_cannot_access_release_signing_secrets() -> None:
    promotion = (ROOT / ".github" / "workflows" / "core-candidate-promotion.yml").read_text(encoding="utf-8")
    for secret in (
        "AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64",
        "AURORA_ANDROID_KEYSTORE_BASE64",
        "AURORA_ANDROID_KEYSTORE_USER",
        "AURORA_ANDROID_KEYSTORE_PASSWORD",
    ):
        assert secret not in promotion
