import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "benchmarks" / "knowledge" / "production_pack_acceptance.gd"
RUNNER = ROOT / "benchmarks" / "knowledge" / "run_production_pack_acceptance.py"
INSTALLED_RUNNER = ROOT / "scripts" / "installed_production_knowledge_pack_smoke.gd"
WINDOWS_HARNESS = ROOT / "tests" / "windows_installed_production_knowledge_pack.ps1"
MAIN = ROOT / "scripts" / "main.gd"


def test_production_pack_probe_is_strict_offline_and_provenance_aware() -> None:
    source = PROBE.read_text(encoding="utf-8")
    assert 'REPORT_SCHEMA := "aurorafox.production-knowledge-acceptance.v1"' in source
    assert 'installer.inspect(pack_dir)' in source
    assert 'bool(manifest.get("production", false))' in source
    assert 'RELEASE_CONTRACT_PATH := "res://knowledge_pack/production_pack.json"' in source
    assert 'production release input provenance mismatch' in source
    assert 'installer.call("install", StoreScript.new(), pack_dir)' in source
    assert 'installer.has_method("install")' in source
    assert 'int(resumed.get("skipped_shards", -1))' in source
    assert 'metadata.get("pack_id", "")' in source
    assert '"offline": true' in source
    assert '"external_ai_required": false' in source
    assert "HTTPClient" not in source
    assert "HTTPRequest" not in source
    assert "OS.execute" not in source


def test_production_pack_runner_has_timeout_isolation_and_rss_evidence() -> None:
    source = RUNNER.read_text(encoding="utf-8")
    assert 'default=21600' in source
    assert 'TemporaryDirectory(prefix="aurorafox-production-pack-")' in source
    assert 'base.base_environment(user_data' in source
    assert '[str(godot), "--headless", "--editor", "--path", str(ROOT), "--quit"]' in source
    assert '"warmup": warmup' in source
    assert '"AURORAFOX_OFFLINE": "1"' in source
    assert '"AURORAFOX_DISABLE_NETWORK": "1"' in source
    assert "base.process_rss_bytes(process.pid)" in source
    assert '"timed_out": timed_out' in source
    assert '"peak_rss_bytes": peak_rss' in source
    assert 'stdout_log.open("w"' in source
    spec = importlib.util.spec_from_file_location("production_pack_runner", RUNNER)
    assert spec is not None and spec.loader is not None


def test_installed_production_mode_uses_release_contract_and_provenance() -> None:
    source = INSTALLED_RUNNER.read_text(encoding="utf-8")
    assert 'RESULT_SCHEMA := "aurorafox.installed-production-knowledge.v1"' in source
    assert 'RELEASE_CONTRACT_PATH := "res://knowledge_pack/production_pack.json"' in source
    assert 'installer.inspect(pack_dir)' in source
    assert 'installer.call("install", StoreScript.new(), pack_dir)' in source
    assert 'metadata.get("pack_id", "")' in source
    assert 'str(item.get("source", "")) == expected_source' in source
    assert '"offline": true' in source
    assert '"external_ai_required": false' in source
    assert "HTTPClient" not in source
    assert "HTTPRequest" not in source
    assert "OS.execute" not in source

    main = MAIN.read_text(encoding="utf-8")
    assert 'INSTALLED_PRODUCTION_KNOWLEDGE_SMOKE_MODE := "knowledge-pack-production-v1"' in main
    assert 'InstalledProductionKnowledgePackSmokeScript.new().run(result_path, pack_dir)' in main


def test_windows_installed_production_harness_requires_restart_and_exact_pack() -> None:
    source = WINDOWS_HARNESS.read_text(encoding="utf-8")
    assert "[Parameter(Mandatory=$true)][string]$PackDir" in source
    assert "'knowledge-pack-production-v1'" in source
    assert "'AURORAFOX_PRODUCTION_PACK_DIR'" in source
    assert "'AURORAFOX_OFFLINE', '1'" in source
    assert "'AURORAFOX_DISABLE_NETWORK', '1'" in source
    assert "-RemoteAddress ($externalIpv4 + $externalIpv6)" in source
    assert "Invoke-InstalledProductionPhase -Name 'install'" in source
    assert "Invoke-InstalledProductionPhase -Name 'resume'" in source
    assert "[string]$ResumeProfileRoot = ''" in source
    assert "[string]$InstallProofPath = ''" in source
    assert "ResumeProfileRoot and InstallProofPath must be supplied together" in source
    assert "New-Object System.Diagnostics.ProcessStartInfo" in source
    assert "Start-Process" not in source
    assert "$startInfo.UseShellExecute = $false" in source
    assert "$startInfo.RedirectStandardOutput = $true" in source
    assert "$stdoutTask = $script:activeProcess.StandardOutput.ReadToEndAsync()" in source
    assert "$script:activeProcess.WaitForExit()" in source
    assert "$exitCode = $script:activeProcess.ExitCode" in source
    assert "if ($null -eq $exitCode)" in source
    assert "Get-Content -LiteralPath $resolvedInstallProof -Raw | ConvertFrom-Json" in source
    assert "Installed production first-run proof is invalid" in source
    assert "[int]$installed.imported_shards -ne 60" in source
    assert "[int]$resumed.skipped_shards -ne 60" in source
    assert "@($state.completed_shards).Count -ne 60" in source
    assert "AURORA_WINDOWS_INSTALLED_PRODUCTION_KNOWLEDGE_OK" in source
    assert "1924345221" in source
    assert "1982822407" in source
    assert "75871" in source
