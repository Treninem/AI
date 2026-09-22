from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCENE = ROOT / "benchmarks" / "knowledge" / "android_production_pack_acceptance.tscn"
RUNNER = ROOT / "benchmarks" / "knowledge" / "android_production_pack_acceptance.gd"
HARNESS = ROOT / "tests" / "android_installed_production_knowledge_pack.ps1"
WORKFLOW = ROOT / ".github" / "workflows" / "android-production-knowledge-acceptance.yml"


def test_android_acceptance_scene_reuses_strict_production_runner() -> None:
    scene = SCENE.read_text(encoding="utf-8")
    source = RUNNER.read_text(encoding="utf-8")
    assert "android_production_pack_acceptance.gd" in scene
    assert 'InstalledProductionKnowledgePackSmokeScript = preload("res://scripts/installed_production_knowledge_pack_smoke.gd")' in source
    assert 'PACK_ROOT := "user://android-production-pack"' in source
    assert 'REPORT_PATH := "user://android-production-knowledge.json"' in source
    assert "ProjectSettings.globalize_path(PACK_ROOT)" in source
    assert "InstalledProductionKnowledgePackSmokeScript.new().run(report_path, pack_root)" in source
    assert "HTTPClient" not in source
    assert "HTTPRequest" not in source
    assert "OS.execute" not in source


def test_android_harness_requires_exact_pack_offline_two_processes() -> None:
    source = HARNESS.read_text(encoding="utf-8")
    for value in [
        "bc395f76c0797e9b3751f11fcb7a52b9999ce5c5857ece1f433778bf1fd75cbd",
        "1924345221", "1982822407", "75871", "60",
        "'root'", "'pm', 'clear'", "'stat', '-c', '%u'",
        "'chown', '-R'", "'restorecon', '-RF'", "'airplane-mode', 'enable'",
        "'wifi', 'disable'", "'data', 'disable'", "'push'",
        "Start-AcceptancePhase", "-Phase 'install'", "-Phase 'restart'",
        "[int]$first.imported_shards -ne $ExpectedShards",
        "[int]$resumed.imported_shards -ne 0",
        "[int]$resumed.skipped_shards -ne $ExpectedShards",
        "AURORA_ANDROID_INSTALLED_PRODUCTION_KNOWLEDGE_OK",
    ]:
        assert value in source
    assert source.count("Start-AcceptancePhase -Launcher") == 2
    assert "http://" not in source
    assert "https://" not in source


def test_workflow_is_manual_only_and_never_packages_corpus() -> None:
    source = WORKFLOW.read_text(encoding="utf-8")
    assert "workflow_dispatch:" in source
    assert "pull_request:" not in source
    assert "push:" in source
    assert "branches: [chat-2026-09-17-unified-finalization]" in source
    assert 'run/main_scene="res://benchmarks/knowledge/android_production_pack_acceptance.tscn"' in source
    assert "AllowUnsignedRelease" in source
    assert "android-production-knowledge-acceptance" in source
    assert "AuroraFox-Knowledge-RU" not in source
