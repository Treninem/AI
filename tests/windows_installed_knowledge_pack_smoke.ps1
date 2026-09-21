param(
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [string]$ReportDir = 'artifacts/windows-offline-knowledge-pack'
)

$ErrorActionPreference = 'Stop'
$installRoot = (Resolve-Path $InstallDir).Path
$primaryExe = Join-Path $installRoot 'AuroraFox.exe'
$consoleExe = Join-Path $installRoot 'AuroraFox.console.exe'
if (-not (Test-Path -LiteralPath $primaryExe)) { throw 'Installed AuroraFox.exe is missing' }
$launcher = if (Test-Path -LiteralPath $consoleExe) { $consoleExe } else { $primaryExe }

New-Item -ItemType Directory -Force $ReportDir | Out-Null
$reportRoot = (Resolve-Path $ReportDir).Path
$profileRoot = Join-Path $reportRoot ('profile-' + [Guid]::NewGuid().ToString('N'))
$appData = Join-Path $profileRoot 'AppData\Roaming'
$localAppData = Join-Path $profileRoot 'AppData\Local'
New-Item -ItemType Directory -Force $appData,$localAppData | Out-Null
$stdoutLog = Join-Path $reportRoot 'knowledge-pack.stdout.log'
$stderrLog = Join-Path $reportRoot 'knowledge-pack.stderr.log'
$resultFile = Join-Path $reportRoot 'knowledge-pack.result.json'

$previousAppData = [Environment]::GetEnvironmentVariable('APPDATA', 'Process')
$previousLocalAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA', 'Process')
$previousSmokeResult = [Environment]::GetEnvironmentVariable('AURORAFOX_KNOWLEDGE_SMOKE_RESULT', 'Process')
$externalIpv4 = @('0.0.0.0-126.255.255.255','128.0.0.0-255.255.255.255')
$externalIpv6 = @('::2-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff')
$rulePrefix = 'AuroraFoxInstalledKnowledge-' + [Guid]::NewGuid().ToString('N')
$rules = @()
$process = $null
$started = [Diagnostics.Stopwatch]::StartNew()
try {
    [Environment]::SetEnvironmentVariable('APPDATA', $appData, 'Process')
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $localAppData, 'Process')
    [Environment]::SetEnvironmentVariable('AURORAFOX_KNOWLEDGE_SMOKE_RESULT', $resultFile, 'Process')

    $programs = @(@($primaryExe,$launcher) | Select-Object -Unique)
    for ($index = 0; $index -lt $programs.Count; $index++) {
        $rule = "$rulePrefix-$index"
        New-NetFirewallRule -DisplayName $rule -Direction Outbound -Program $programs[$index] -Action Block -Profile Any -RemoteAddress ($externalIpv4 + $externalIpv6) | Out-Null
        $rules += $rule
    }

    $process = Start-Process -FilePath $launcher -WorkingDirectory $installRoot -ArgumentList @('--headless','--script','res://tests/knowledge_pack_installer_smoke.gd') -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru
    $fixtureComplete = $false
    $proof = $null
    $lastJsonError = ''
    for ($attempt = 0; $attempt -lt 480; $attempt++) {
        $process.Refresh()
        if (Test-Path -LiteralPath $resultFile) {
            try {
                # Read twice so the poller never accepts a file while Windows is
                # still publishing it. The fixture also writes through a temp
                # file and rename, but this protects against filesystem timing.
                $raw1 = Get-Content -LiteralPath $resultFile -Raw
                Start-Sleep -Milliseconds 50
                $raw2 = Get-Content -LiteralPath $resultFile -Raw
                if ($raw1 -ne $raw2) { throw 'Completion proof changed while being read' }
                $candidate = $raw2 | ConvertFrom-Json
                if ($candidate.schema -eq 'aurorafox.installed-knowledge-smoke.v1' -and [bool]$candidate.passed -and [bool]$candidate.offline -and -not [bool]$candidate.external_ai_required) {
                    $proof = $candidate
                    $fixtureComplete = $true
                    break
                }
            } catch { $lastJsonError = $_.Exception.Message }
        }
        if ($process.HasExited) { break }
        Start-Sleep -Milliseconds 250
    }
    if ($fixtureComplete -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit(10000) | Out-Null
    }
    $process.Refresh()
    if (-not $fixtureComplete -and -not $process.HasExited) {
        $stdout = if (Test-Path $stdoutLog) { Get-Content $stdoutLog -Raw } else { '' }
        $stderr = if (Test-Path $stderrLog) { Get-Content $stderrLog -Raw } else { '' }
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "Installed Knowledge Pack smoke timed out after 120 seconds.`nProcessId: $($process.Id)`nLast JSON error: $lastJsonError`nstdout:`n$stdout`nstderr:`n$stderr"
    }
    $stdout = if (Test-Path $stdoutLog) { Get-Content $stdoutLog -Raw } else { '' }
    $stderr = if (Test-Path $stderrLog) { Get-Content $stderrLog -Raw } else { '' }
    if (-not $fixtureComplete -and $process.ExitCode -ne 0) {
        throw "Installed Knowledge Pack smoke exited with $($process.ExitCode).`nLast JSON error: $lastJsonError`nstdout:`n$stdout`nstderr:`n$stderr"
    }

    if (-not $proof) { throw "Installed Knowledge Pack did not persist its completion proof.`nstdout:`n$stdout`nstderr:`n$stderr" }
    $statePath = [string]$proof.state_path
    $manifestPath = [string]$proof.manifest_path
    $shardPath = [string]$proof.shard_path
    foreach ($path in @($statePath,$manifestPath,$shardPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Installed Knowledge Pack proof references a missing file: $path" }
    }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $shardHash = (Get-FileHash $shardPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($state.status -ne 'ready' -or @($state.completed_shards).Count -ne 1) { throw 'Installed Knowledge Pack durable resume state is invalid' }
    if ($manifest.schema -ne 'aurorafox.knowledge-pack.v1' -or $manifest.pack_id -ne 'aurorafox-smoke' -or [int]$manifest.record_count -ne 1 -or -not [bool]$manifest.production) { throw 'Installed Knowledge Pack fixture manifest is invalid' }
    if ([string]@($state.completed_shards)[0] -ne $shardHash) { throw 'Installed Knowledge Pack durable state does not identify the verified shard' }
    if ([string]$proof.shard_sha256 -ne $shardHash -or [string]$proof.state_sha256 -ne (Get-FileHash $statePath -Algorithm SHA256).Hash.ToLowerInvariant() -or [string]$proof.manifest_sha256 -ne (Get-FileHash $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()) { throw 'Installed Knowledge Pack completion proof hash validation failed' }
    $markerPresent = ($stdout + "`n" + $stderr).Contains('AURORA_KNOWLEDGE_PACK_INSTALLER_OK')
    $started.Stop()
    @{
        passed = $true; installed = $true; offline = $true; external_ai_required = $false
        outbound_firewall_block = $true; launcher = [IO.Path]::GetFileName($launcher)
        script = 'res://tests/knowledge_pack_installer_smoke.gd'; pack_id = [string]$manifest.pack_id
        status = [string]$state.status; completed_shards = @($state.completed_shards).Count
        production_floor_rejection_exercised = [bool]$manifest.production; marker_present = $markerPresent
        durable_completion_observed = $fixtureComplete
        state_sha256 = (Get-FileHash $statePath -Algorithm SHA256).Hash.ToLowerInvariant()
        manifest_sha256 = (Get-FileHash $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        shard_sha256 = $shardHash; wall_ms = $started.ElapsedMilliseconds
    } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $reportRoot 'report.json') -Encoding UTF8
    Write-Host 'AURORA_WINDOWS_INSTALLED_OFFLINE_KNOWLEDGE_PACK_OK'
} finally {
    if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    foreach ($rule in $rules) { Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue }
    [Environment]::SetEnvironmentVariable('APPDATA', $previousAppData, 'Process')
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $previousLocalAppData, 'Process')
    [Environment]::SetEnvironmentVariable('AURORAFOX_KNOWLEDGE_SMOKE_RESULT', $previousSmokeResult, 'Process')
}
