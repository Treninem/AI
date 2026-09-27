param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ExpectedHead,
    [Parameter(Mandatory=$true)][string]$Godot,
    [string]$Python = 'python',
    [string]$ReportDir = 'artifacts/evolution-windows'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:OS -ne 'Windows_NT') {
    throw 'Native Windows is required; compatibility layers are not accepted as Windows evidence'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$godotPath = (Resolve-Path $Godot).Path
$expected = $ExpectedHead.ToLowerInvariant()

Push-Location $repoRoot
try {
    $actual = (& git rev-parse HEAD).Trim().ToLowerInvariant()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve Git HEAD' }
    if ($actual -ne $expected) {
        throw "Wrong checkout HEAD: expected $expected, got $actual"
    }

    $dirty = @(& git status --porcelain --untracked-files=all)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect Git worktree' }
    if ($dirty.Count -ne 0) {
        throw 'Evolution Windows evidence requires a clean checkout'
    }

    $godotVersion = ((& $godotPath --version 2>&1) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Godot version probe failed' }
    if ($godotVersion -notmatch '^4\.7\.1(?:[.-]|$)') {
        throw "Godot 4.7.1 is required, got: $godotVersion"
    }

    $pythonCommand = Get-Command $Python -ErrorAction Stop
    New-Item -ItemType Directory -Force $ReportDir | Out-Null
    $reportRoot = (Resolve-Path $ReportDir).Path
    $logPath = Join-Path $reportRoot "evolution-windows-$actual.log"
    $reportPath = Join-Path $reportRoot "evolution-windows-$actual.json"

    & $pythonCommand.Source evolution_engine/tests/run_evolution_checks.py --godot $godotPath 2>&1 |
        Tee-Object -FilePath $logPath
    $runnerExit = $LASTEXITCODE

    $logText = Get-Content $logPath -Raw
    $acceptanceMarker = $logText -match 'AURORAFOX_EVOLUTION_ACCEPTANCE_OK'
    $nativeMarker = $logText -match 'AURORA_CORE_TOURNAMENT_SMOKE_OK[^\r\n]*native_windows=true'
    $nonNativeMarker = $logText -match 'AURORA_CORE_TOURNAMENT_SMOKE_OK[^\r\n]*native_windows=false'
    $passed = $runnerExit -eq 0 -and $acceptanceMarker -and $nativeMarker -and -not $nonNativeMarker
    $logSha256 = (Get-FileHash $logPath -Algorithm SHA256).Hash.ToLowerInvariant()

    $report = [ordered]@{
        schema_version = 1
        passed = $passed
        expected_head = $expected
        actual_head = $actual
        pre_run_clean = $true
        platform = 'Windows'
        native_windows = $nativeMarker -and -not $nonNativeMarker
        godot_version = $godotVersion
        runner_exit_code = $runnerExit
        acceptance_marker = $acceptanceMarker
        native_tournament_marker = $nativeMarker
        non_native_tournament_marker = $nonNativeMarker
        log_sha256 = $logSha256
        created_at_utc = [DateTime]::UtcNow.ToString('o')
    }
    $report | ConvertTo-Json -Depth 4 | Set-Content $reportPath -Encoding UTF8

    if (-not $passed) {
        throw "Evolution Windows acceptance failed; inspect $reportPath and $logPath"
    }

    Write-Host "AURORAFOX_EVOLUTION_WINDOWS_EVIDENCE_OK sha=$actual log_sha256=$logSha256"
}
finally {
    Pop-Location
}
