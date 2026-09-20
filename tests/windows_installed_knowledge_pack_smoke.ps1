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
    if (-not $process.WaitForExit(120000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw 'Installed Knowledge Pack smoke timed out after 120 seconds'
    }
    $process.Refresh()
    $stdout = if (Test-Path $stdoutLog) { Get-Content $stdoutLog -Raw } else { '' }
    $stderr = if (Test-Path $stderrLog) { Get-Content $stderrLog -Raw } else { '' }
    if ($process.ExitCode -ne 0) {
        throw "Installed Knowledge Pack smoke exited with $($process.ExitCode).`nstdout:`n$stdout`nstderr:`n$stderr"
    }

    $stateFile = Get-ChildItem -LiteralPath $profileRoot -Filter 'aurorafox-smoke.json' -Recurse -File |
        Select-Object -First 1
    $manifestFile = Get-ChildItem -LiteralPath $profileRoot -Filter 'manifest.json' -Recurse -File |
        Where-Object { $_.FullName -like '*knowledge_pack_installer_smoke*' } |
        Select-Object -First 1
    $shardFile = Get-ChildItem -LiteralPath $profileRoot -Filter 'knowledge-00000.jsonl' -Recurse -File |
        Select-Object -First 1
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
