from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tests" / "windows_android_production_knowledge_orchestrator.ps1"


def test_windows_android_orchestrator_is_pinned_bounded_and_reuses_strict_harness() -> None:
    source = SCRIPT.read_text(encoding="utf-8")
    for value in [
        "android_installed_production_knowledge_pack.ps1",
        "system-images;android-35;google_apis;x86_64",
        "AuroraFox_Acceptance_API_35",
        "e56bc27f48a5f860f8fa5bb6a0b6fde6f0c809adf1e38f3bfe4928a3e1c82d28",
        "10691590889",
        "Get-FileHash -Algorithm SHA256",
        "production-knowledge-acceptance.sha256",
        "-accel-check",
        "--licenses",
        "create avd",
        "-no-snapshot",
        "-no-window",
        "-wipe-data",
        "sys.boot_completed",
        "$adb root",
        "shell id -u",
        "Exactly one Android target is required",
        "-TimeoutSeconds $AcceptanceTimeoutSeconds",
        "AURORA_WINDOWS_ANDROID_PRODUCTION_ORCHESTRATION_OK",
        "report.json",
        "$nativeErrorActionPreference = $ErrorActionPreference",
        "$ErrorActionPreference = 'Continue'",
        "$nativeExitCode = $LASTEXITCODE",
        "$ErrorActionPreference = $nativeErrorActionPreference",
        "if ($nativeExitCode -ne 0)",
    ]:
        assert value in source
    assert "Invoke-WebRequest" not in source
    assert "Remove-Item -Recurse" not in source
    assert "Set-VMProcessor" not in source
    assert "bcdedit" not in source

