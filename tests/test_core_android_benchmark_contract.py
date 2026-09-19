from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "benchmarks" / "core" / "android_probe"
RUNNER = ROOT / "benchmarks" / "core" / "run_android_probe.sh"
RUNTIME_GRADLE = ROOT / "android_plugin" / "plugin" / "build.gradle.kts"
WORKFLOW = ROOT / ".github" / "workflows" / "core-android-benchmark.yml"
PINNED_NDK = 'ndkVersion = "28.1.13356709"'


def test_android_probe_uses_exact_native_core_and_has_no_network_permission() -> None:
    activity = (PROBE / "app/src/main/java/com/aurorafox/corebenchmark/MainActivity.kt").read_text(encoding="utf-8")
    manifest = (PROBE / "app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
    app_gradle = (PROBE / "app/build.gradle.kts").read_text(encoding="utf-8")
    runtime_gradle = RUNTIME_GRADLE.read_text(encoding="utf-8")
    settings = (PROBE / "settings.gradle.kts").read_text(encoding="utf-8")
    gradle_properties = (PROBE / "gradle.properties").read_text(encoding="utf-8")

    assert "com.aurorafox.runtime.NativeRuntime" in activity
    assert "native.chat(" in activity
    assert "native.hasLlama()" in activity
    assert "CoreChatPrompt.format(" in activity
    assert 'RuntimeBuildConfig.BUILD_TYPE == "release" && !RuntimeBuildConfig.DEBUG' in activity
    assert '.put("runtime_build_type", RuntimeBuildConfig.BUILD_TYPE)' in activity
    assert '.put("runtime_debug", RuntimeBuildConfig.DEBUG)' in activity
    plugin = (ROOT / "android_plugin/plugin/src/main/java/com/aurorafox/runtime/GodotAndroidPlugin.kt").read_text(encoding="utf-8")
    assert "return CoreChatPrompt.format(items)" in plugin
    assert '"llama.cpp"' in activity
    assert "ANDROID-LOCAL-READY" in activity
    assert '.put("max_tokens", 16)' in activity
    assert "cold_first_response_ms" in activity
    assert "warm_median_ms" in activity
    assert "process_pss_mb" in activity
    assert "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5" in activity
    assert "android.permission.INTERNET" not in manifest
    assert 'abiFilters += listOf("x86_64")' in app_gradle
    assert 'pickFirsts += "**/libc++_shared.so"' in app_gradle
    assert 'create("benchmark")' in app_gradle
    assert 'initWith(getByName("debug"))' in app_gradle
    assert 'matchingFallbacks += listOf("release")' in app_gradle
    assert PINNED_NDK in app_gradle
    assert PINNED_NDK in runtime_gradle
    assert 'project(":runtime").projectDir = file("../../../android_plugin/plugin")' in settings
    assert "android.useAndroidX=true" in gradle_properties


def test_android_benchmark_workflow_runs_emulator_probe_in_one_shell() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    runner = RUNNER.read_text(encoding="utf-8")
    assert "reactivecircus/android-emulator-runner@v2.38.0" in workflow
    assert "api-level: 35" in workflow
    assert "arch: x86_64" in workflow
    assert "prepare_bundled_core_model.ps1" in workflow
    assert "android_plugin/setup_native.ps1" in workflow
    assert 'bash benchmarks/core/run_android_probe.sh "$CORE_MODEL"' in workflow
    assert "benchmarks/core/run_android_probe.sh" in workflow
    assert ":app:assembleBenchmark" in workflow
    assert ":app:assembleDebug" not in workflow
    assert "outputs/apk/benchmark/app-benchmark.apk" in workflow
    assert "outputs/apk/benchmark/app-benchmark.apk" in runner

    assert "set -euo pipefail" in runner
    assert "pkg='com.aurorafox.corebenchmark'" in runner
    assert "adb push" in runner
    assert 'adb shell run-as "$pkg" mkdir -p files' in runner
    assert 'adb shell run-as "$pkg" cp /data/local/tmp/aurorafox-core.gguf files/aurorafox-core.gguf' in runner
    assert 'adb shell run-as "$pkg" test -s files/core-benchmark-android.json' in runner
    assert 'adb shell run-as "$pkg" cat files/core-benchmark-android.json' in runner
    assert "internet_permission_granted" in runner
    assert "prepared_sha256" in runner
    assert "process_pss_mb" in runner
    assert "failures.append('production_release_runtime')" in runner
    assert "AURORAFOX_ANDROID_REAL_CORE_GATE_OK" in runner


def test_android_model_preparation_uses_terminating_errors_and_sha_not_stale_last_exit_code() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    start = workflow.index("- name: Prepare verified bundled Core weights")
    end = workflow.index("- name: Save verified Core model cache")
    prepare_step = workflow[start:end]
    assert "$ErrorActionPreference = 'Stop'" in prepare_step
    assert "prepare_bundled_core_model.ps1" in prepare_step
    assert "Get-FileHash" in prepare_step
    assert "Android benchmark model SHA mismatch" in prepare_step
    assert "$LASTEXITCODE" not in prepare_step
