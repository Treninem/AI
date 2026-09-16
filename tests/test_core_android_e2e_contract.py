from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "benchmarks/core/android_godot_benchmark.gd"
SCENE = ROOT / "benchmarks/core/android_godot_benchmark.tscn"
WORKFLOW = ROOT / ".github/workflows/core-android-e2e.yml"


def test_android_godot_probe_exercises_normal_aiclient_path() -> None:
    script = SCRIPT.read_text(encoding="utf-8")
    scene = SCENE.read_text(encoding="utf-8")
    assert "AIClient.new()" in script
    assert "client.chat(" in script
    assert "AuroraBundledCoreModel.runtime_candidate()" in script
    assert "set_ollama_fallback(true)" in script
    assert "chat_with_compatibility" not in script
    assert '"aurora_core_android"' in script
    assert "ollama_failures" in script
    assert "fallback_from" in script
    assert "core_knowledge_retrieval" in script
    assert "multi_turn_context" in script
    assert "offline_network_guard" in script
    assert "http://1.1.1.1/" in script
    assert "external_network_probe_blocked" in script
    assert "android_godot_benchmark.gd" in scene


def test_android_godot_e2e_workflow_is_offline_during_measured_phase() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "build/build_android.ps1" in workflow
    assert "--check-only --script benchmarks/core/android_godot_benchmark.gd" in workflow
    assert 'run/main_scene="res://benchmarks/core/android_godot_benchmark.tscn"' in workflow
    assert "reactivecircus/android-emulator-runner@v2.38.0" in workflow
    assert "airplane-mode enable" in workflow
    assert "svc wifi disable" in workflow
    assert "svc data disable" in workflow
    assert "core-benchmark-android-e2e.json" in workflow
    assert "offline_network_guard" in workflow
    assert "aurora_core_android" in workflow
    assert "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5" in workflow
