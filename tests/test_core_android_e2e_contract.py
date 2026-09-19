from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "benchmarks/core/android_godot_benchmark.gd"
SCENE = ROOT / "benchmarks/core/android_godot_benchmark.tscn"
RUNNER = ROOT / "benchmarks/core/run_android_godot_e2e.sh"
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
    assert "installed_voice_tts" in script
    assert "installed_voice_stt" in script
    assert "synthesize_speech(" in script
    assert "transcribe(" in script
    assert "installed_ocr_bilingual" in script
    assert "FileIntelligenceClient.new()" in script
    assert "АВРОРА 5183" in script
    assert 'ocr_meta.get("offline", false)' in script
    assert 'ocr_meta.get("external_ai_required", true)' in script
    assert '"rus" in ocr_languages' in script
    assert '"eng" in ocr_languages' in script
    assert "multi_turn_context" in script
    assert "offline_network_guard" in script
    assert "http://1.1.1.1/" in script
    assert "external_network_probe_blocked" in script
    assert "android_godot_benchmark.gd" in scene


def test_android_godot_e2e_workflow_runs_offline_phase_in_one_shell() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    runner = RUNNER.read_text(encoding="utf-8")
    assert "build/build_android.ps1" in workflow
    assert "--check-only --script benchmarks/core/android_godot_benchmark.gd" in workflow
    assert 'run/main_scene="res://benchmarks/core/android_godot_benchmark.tscn"' in workflow
    assert "reactivecircus/android-emulator-runner@v2.38.0" in workflow
    assert 'bash benchmarks/core/run_android_godot_e2e.sh "$BENCHMARK_APK"' in workflow
    assert "benchmarks/core/run_android_godot_e2e.sh" in workflow

    assert "set -euo pipefail" in runner
    assert "airplane-mode enable" in runner
    assert "svc wifi disable" in runner
    assert "svc data disable" in runner
    assert "ping -c 1 -W 2 1.1.1.1" in runner
    assert "external_ping_blocked" in runner
    assert "core-benchmark-android-e2e.json" in runner
    assert "offline_network_guard" in runner
    assert "external_network_probe_blocked" in runner
    assert "aurora_core_android" in runner
    assert "AURORAFOX_ANDROID_NORMAL_PATH_GATE_OK" in runner
    assert "AURORAFOX_ANDROID_INSTALLED_VOICE_OCR_KNOWLEDGE_OK" in runner
    assert "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5" in runner
