from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "benchmarks" / "core" / "android_probe"
WORKFLOW = ROOT / ".github" / "workflows" / "core-android-benchmark.yml"


def test_android_probe_uses_exact_native_core_and_has_no_network_permission() -> None:
    activity = (PROBE / "app/src/main/java/com/aurorafox/corebenchmark/MainActivity.kt").read_text(encoding="utf-8")
    manifest = (PROBE / "app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
    app_gradle = (PROBE / "app/build.gradle.kts").read_text(encoding="utf-8")
    settings = (PROBE / "settings.gradle.kts").read_text(encoding="utf-8")
    gradle_properties = (PROBE / "gradle.properties").read_text(encoding="utf-8")

    assert "com.aurorafox.runtime.NativeRuntime" in activity
    assert "native.chat(" in activity
    assert "native.hasLlama()" in activity
    assert '"llama.cpp"' in activity
    assert "ANDROID-LOCAL-READY" in activity
    assert "cold_first_response_ms" in activity
    assert "warm_median_ms" in activity
    assert "process_pss_mb" in activity
    assert "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5" in activity
    assert "android.permission.INTERNET" not in manifest
    assert 'abiFilters += listOf("x86_64")' in app_gradle
    assert 'project(":runtime").projectDir = file("../../../android_plugin/plugin")' in settings
    assert "android.useAndroidX=true" in gradle_properties


def test_android_benchmark_workflow_enforces_real_emulator_inference() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "reactivecircus/android-emulator-runner@v2.38.0" in workflow
    assert "api-level: 35" in workflow
    assert "arch: x86_64" in workflow
    assert "prepare_bundled_core_model.ps1" in workflow
    assert "android_plugin/setup_native.ps1" in workflow
    assert "adb push" in workflow

    # The workflow intentionally stores the package name in a shell variable so
    # every sandbox operation targets the same application id. Assert that
    # contract instead of requiring a brittle literal `run-as <package>` line.
    assert "pkg='com.aurorafox.corebenchmark'" in workflow
    assert 'adb shell run-as "$pkg" mkdir -p files' in workflow
    assert 'adb shell run-as "$pkg" cp /data/local/tmp/aurorafox-core.gguf files/aurorafox-core.gguf' in workflow
    assert 'adb shell run-as "$pkg" test -s files/core-benchmark-android.json' in workflow
    assert 'adb shell run-as "$pkg" cat files/core-benchmark-android.json' in workflow

    assert "core-benchmark-android.json" in workflow
    assert "internet_permission_granted" in workflow
    assert "prepared_sha256" in workflow
    assert "process_pss_mb" in workflow
    assert "passed is True" not in workflow


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
