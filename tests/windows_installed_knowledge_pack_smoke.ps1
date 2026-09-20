param(
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [string]$ReportDir = 'artifacts/windows-offline-knowledge-pack'
)

$ErrorActionPreference = 'Stop'
# CI rerun marker: durable completion polling v1.
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

$previousAppData = [Environment]::GetEnvironmentVariable('APPDATA', 'Process')
$previousLocalAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA', 'Process')
$externalIpv4 = @('0.0.0.0-126.255.255.255','128.0.0.0-255.255.255.255')
$externalIpv6 = @('::2-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff')
$rulePrefix = 'AuroraFoxInstalledKnowledge-' + [Guid]::NewGuid().ToString('N')
$rules = @()
$process = $null
$started = [Diagnostics.Stopwatch]::StartNew()
try {
    [Environment]::SetEnvironmentVariable('APPDATA', $appData, 'Process')
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $localAppData, 'Process')

    $programs = @(@($primaryExe,$launcher) | Select-Object -Unique)
    for ($index = 0; $index -lt $programs.Count; $index++) {
        $rule = "$rulePrefix-$index"
        New-NetFirewallRule `
            -DisplayName $rule `
            -Direction Outbound `
            -Program $programs[$index] `
            -Action Block `
            -Profile Any `
            -RemoteAddress ($externalIpv4 + $externalIpv6) | Out-Null
        $rules += $rule
    }

    $process = Start-Process `
        -FilePath $launcher `
        -WorkingDirectory $installRoot `
        -ArgumentList @('--headless','--script','res://tests/knowledge_pack_installer_smoke.gd') `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog `
        -PassThru

    # The exported console launcher can remain alive after the embedded
    # SceneTree has persisted its final result. Observe the fail-closed durable
    # proof as well as process exit instead of blocking on the wrapper alone.
    $fixtureComplete = $false
    $stateFile = $null
    $manifestFile = $null
    $shardFile = $null
    for ($attempt = 0; $attempt -lt 480; $attempt++) {
        $process.Refresh()
        $stateFile = Get-ChildItem -LiteralPath $profileRoot -Filter 'aurorafox-smoke.json' -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        $manifestFile = Get-ChildItem -LiteralPath $profileRoot -Filter 'manifest.json' -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like '*knowledge_pack_installer_smoke*' } |
            Select-Object -First 1
        $shardFile = Get-ChildItem -LiteralPath $profileRoot -Filter 'knowledge-00000.jsonl' -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($stateFile -and $manifestFile -and $shardFile) {
            try {
                $probeState = Get-Content -LiteralPath $stateFile.FullName -Raw | ConvertFrom-Json
                $probeManifest = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json
                if ($probeState.status -eq 'ready' -and
                    @($probeState.completed_shards).Count -eq 1 -and
                    [bool]$probeManifest.production) {
                    $fixtureComplete = $true
                    break
                }
            } catch { }
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
        throw "Installed Knowledge Pack smoke timed out after 120 seconds.`nProcessId: $($process.Id)`nstdout:`n$stdout`nstderr:`n$stderr"
    }
    $stdout = if (Test-Path $stdoutLog) { Get-Content $stdoutLog -Raw } else { '' }
    $stderr = if (Test-Path $stderrLog) { Get-Content $stderrLog -Raw } else { '' }
    if (-not $fixtureComplete -and $process.ExitCode -ne 0) {
        throw "Installed Knowledge Pack smoke exited with $($process.ExitCode).`nstdout:`n$stdout`nstderr:`n$stderr"
    }

    if (-not $stateFile -or -not $manifestFile -or -not $shardFile) {
        throw "Installed Knowledge Pack did not persist its fixture/state.`nstdout:`n$stdout`nstderr:`n$stderr"
    }
    $state = Get-Content -LiteralPath $stateFile.FullName -Raw | ConvertFrom-Json
    $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json
    $shardHash = (Get-FileHash -LiteralPath $shardFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($state.status -ne 'ready' -or @($state.completed_shards).Count -ne 1) {
        throw 'Installed Knowledge Pack durable resume state is invalid'
    }
    if ($manifest.schema -ne 'aurorafox.knowledge-pack.v1' -or
        $manifest.pack_id -ne 'aurorafox-smoke' -or
        [int]$manifest.record_count -ne 1 -or
        -not [bool]$manifest.production) {
        throw 'Installed Knowledge Pack fixture manifest is invalid'
    }
    if ([string](@($state.completed_shards)[0]) -ne $shardHash) {
        throw 'Installed Knowledge Pack durable state does not identify the verified shard'
    }
    $markerPresent = ($stdout + "`n" + $stderr).Contains('AURORA_KNOWLEDGE_PACK_INSTALLER_OK')
    $started.Stop()
    @{
        passed = $true
        installed = $true
        offline = $true
        external_ai_required = $false
        outbound_firewall_block = $true
        launcher = [IO.Path]::GetFileName($launcher)
        script = 'res://tests/knowledge_pack_installer_smoke.gd'
        pack_id = [string]$manifest.pack_id
        status = [string]$state.status
        completed_shards = @($state.completed_shards).Count
        production_floor_rejection_exercised = [bool]$manifest.production
        marker_present = $markerPresent
        durable_completion_observed = $fixtureComplete
        state_sha256 = (Get-FileHash -LiteralPath $stateFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        manifest_sha256 = (Get-FileHash -LiteralPath $manifestFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        shard_sha256 = $shardHash
        wall_ms = $started.ElapsedMilliseconds
    } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $reportRoot 'report.json') -Encoding UTF8
    Write-Host 'AURORA_WINDOWS_INSTALLED_OFFLINE_KNOWLEDGE_PACK_OK'
} finally {
    if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    foreach ($rule in $rules) { Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue }
    [Environment]::SetEnvironmentVariable('APPDATA', $previousAppData, 'Process')
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $previousLocalAppData, 'Process')
}
