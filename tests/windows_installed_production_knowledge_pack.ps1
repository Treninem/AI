param(
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [Parameter(Mandatory=$true)][string]$PackDir,
    [string]$ReportDir = 'artifacts/windows-installed-production-knowledge',
    [int]$TimeoutSeconds = 7200
)

$ErrorActionPreference = 'Stop'
$installRoot = (Resolve-Path $InstallDir).Path
$packRoot = (Resolve-Path $PackDir).Path
$primaryExe = Join-Path $installRoot 'AuroraFox.exe'
$consoleExe = Join-Path $installRoot 'AuroraFox.console.exe'
if (-not (Test-Path -LiteralPath $primaryExe -PathType Leaf)) { throw 'Installed AuroraFox.exe is missing' }
$launcher = if (Test-Path -LiteralPath $consoleExe -PathType Leaf) { $consoleExe } else { $primaryExe }
$manifestPath = Join-Path $packRoot 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Extracted production Knowledge Pack manifest is missing' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 'aurorafox.knowledge-pack.v1' -or
    $manifest.pack_id -ne 'aurorafox-bootstrap-ru' -or
    $manifest.pack_version -ne '2026.09.01' -or
    -not [bool]$manifest.production -or
    [int64]$manifest.content_bytes -ne 1924345221 -or
    [int64]$manifest.file_bytes -ne 1982822407 -or
    [int64]$manifest.record_count -ne 75871 -or
    @($manifest.shards).Count -ne 60) {
    throw 'Extracted production Knowledge Pack does not match the pinned release contract'
}

New-Item -ItemType Directory -Force $ReportDir | Out-Null
$reportRoot = (Resolve-Path $ReportDir).Path
$profileRoot = Join-Path $reportRoot ('profile-' + [Guid]::NewGuid().ToString('N'))
$appData = Join-Path $profileRoot 'AppData\Roaming'
$localAppData = Join-Path $profileRoot 'AppData\Local'
New-Item -ItemType Directory -Force $appData,$localAppData | Out-Null

$environmentNames = @(
    'APPDATA', 'LOCALAPPDATA', 'AURORAFOX_KNOWLEDGE_SMOKE_RESULT',
    'AURORAFOX_INSTALLED_SMOKE_MODE', 'AURORAFOX_PRODUCTION_PACK_DIR',
    'AURORAFOX_OFFLINE', 'AURORAFOX_DISABLE_NETWORK'
)
$previousEnvironment = @{}
foreach ($name in $environmentNames) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

$externalIpv4 = @('0.0.0.0-126.255.255.255','128.0.0.0-255.255.255.255')
$externalIpv6 = @('::2-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff')
$rulePrefix = 'AuroraFoxInstalledProductionKnowledge-' + [Guid]::NewGuid().ToString('N')
$rules = @()
$activeProcess = $null
$overall = [Diagnostics.Stopwatch]::StartNew()

function Invoke-InstalledProductionPhase {
    param([Parameter(Mandatory=$true)][string]$Name)

    $resultFile = Join-Path $reportRoot "$Name.result.json"
    $stdoutLog = Join-Path $reportRoot "$Name.stdout.log"
    $stderrLog = Join-Path $reportRoot "$Name.stderr.log"
    Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
    [Environment]::SetEnvironmentVariable('AURORAFOX_KNOWLEDGE_SMOKE_RESULT', $resultFile, 'Process')

    $script:activeProcess = Start-Process -FilePath $launcher -WorkingDirectory $installRoot `
        -ArgumentList @('--headless') -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog -PassThru
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $proof = $null
    $lastJsonError = ''
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $script:activeProcess.Refresh()
        if (Test-Path -LiteralPath $resultFile -PathType Leaf) {
            try {
                $raw1 = Get-Content -LiteralPath $resultFile -Raw
                Start-Sleep -Milliseconds 50
                $raw2 = Get-Content -LiteralPath $resultFile -Raw
                if ($raw1 -ne $raw2) { throw 'Completion proof changed while being read' }
                $candidate = $raw2 | ConvertFrom-Json
                if ($candidate.schema -eq 'aurorafox.installed-production-knowledge.v1') {
                    $proof = $candidate
                    break
                }
            } catch { $lastJsonError = $_.Exception.Message }
        }
        if ($script:activeProcess.HasExited) { break }
        Start-Sleep -Milliseconds 250
    }

    if ($proof -and -not $script:activeProcess.HasExited) {
        if (-not $script:activeProcess.WaitForExit(30000)) {
            Stop-Process -Id $script:activeProcess.Id -Force -ErrorAction SilentlyContinue
            throw "Installed production phase $Name wrote a result but did not exit"
        }
    }
    $script:activeProcess.Refresh()
    $stdout = if (Test-Path $stdoutLog) { Get-Content $stdoutLog -Raw } else { '' }
    $stderr = if (Test-Path $stderrLog) { Get-Content $stderrLog -Raw } else { '' }
    if (-not $proof) {
        if (-not $script:activeProcess.HasExited) {
            Stop-Process -Id $script:activeProcess.Id -Force -ErrorAction SilentlyContinue
        }
        throw "Installed production phase $Name produced no proof within $TimeoutSeconds seconds.`nProcessId: $($script:activeProcess.Id)`nProcessExited: $($script:activeProcess.HasExited)`nLast JSON error: $lastJsonError`nstdout:`n$stdout`nstderr:`n$stderr"
    }
    if (-not [bool]$proof.passed -or $script:activeProcess.ExitCode -ne 0) {
        throw "Installed production phase $Name failed with exit $($script:activeProcess.ExitCode).`nProof:`n$($proof | ConvertTo-Json -Depth 12)`nstdout:`n$stdout`nstderr:`n$stderr"
    }
    return $proof
}

try {
    [Environment]::SetEnvironmentVariable('APPDATA', $appData, 'Process')
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $localAppData, 'Process')
    [Environment]::SetEnvironmentVariable('AURORAFOX_INSTALLED_SMOKE_MODE', 'knowledge-pack-production-v1', 'Process')
    [Environment]::SetEnvironmentVariable('AURORAFOX_PRODUCTION_PACK_DIR', $packRoot, 'Process')
    [Environment]::SetEnvironmentVariable('AURORAFOX_OFFLINE', '1', 'Process')
    [Environment]::SetEnvironmentVariable('AURORAFOX_DISABLE_NETWORK', '1', 'Process')

    $programs = @(@($primaryExe,$launcher) | Select-Object -Unique)
    for ($index = 0; $index -lt $programs.Count; $index++) {
        $rule = "$rulePrefix-$index"
        New-NetFirewallRule -DisplayName $rule -Direction Outbound -Program $programs[$index] `
            -Action Block -Profile Any -RemoteAddress ($externalIpv4 + $externalIpv6) | Out-Null
        $rules += $rule
    }

    $installed = Invoke-InstalledProductionPhase -Name 'install'
    if ($installed.status -ne 'ready' -or
        [int]$installed.imported_shards -ne 60 -or
        [int]$installed.skipped_shards -ne 0 -or
        -not [bool]$installed.query_match) {
        throw 'Installed production first-run contract failed'
    }

    $resumed = Invoke-InstalledProductionPhase -Name 'resume'
    if ($resumed.status -ne 'ready' -or
        [int]$resumed.imported_shards -ne 0 -or
        [int]$resumed.skipped_shards -ne 60 -or
        -not [bool]$resumed.query_match) {
        throw 'Installed production restart/resume contract failed'
    }
    foreach ($proof in @($installed,$resumed)) {
        if ($proof.pack_id -ne 'aurorafox-bootstrap-ru' -or
            $proof.pack_version -ne '2026.09.01' -or
            [int]$proof.shards -ne 60 -or
            [int64]$proof.record_count -ne 75871 -or
            [int64]$proof.content_bytes -ne 1924345221 -or
            -not [bool]$proof.offline -or
            [bool]$proof.external_ai_required) {
            throw 'Installed production proof identity/offline contract failed'
        }
    }
    $manifestSha = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([string]$installed.manifest_sha256 -ne $manifestSha -or [string]$resumed.manifest_sha256 -ne $manifestSha) {
        throw 'Installed production manifest SHA-256 proof failed'
    }
    $statePath = [string]$resumed.state_path
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw 'Installed production resume state is missing' }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.status -ne 'ready' -or @($state.completed_shards).Count -ne 60) {
        throw 'Installed production durable state is incomplete'
    }
    $stateSha = (Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([string]$resumed.state_sha256 -ne $stateSha) { throw 'Installed production state SHA-256 proof failed' }

    $overall.Stop()
    @{
        schema = 'aurorafox.windows-installed-production-knowledge.v1'
        passed = $true
        installed = $true
        offline = $true
        external_ai_required = $false
        outbound_firewall_block = $true
        launcher = [IO.Path]::GetFileName($launcher)
        pack_id = [string]$resumed.pack_id
        pack_version = [string]$resumed.pack_version
        manifest_sha256 = $manifestSha
        state_sha256 = $stateSha
        shards = 60
        record_count = 75871
        content_bytes = 1924345221
        first_imported_shards = [int]$installed.imported_shards
        restart_skipped_shards = [int]$resumed.skipped_shards
        first_query_match = [bool]$installed.query_match
        restart_query_match = [bool]$resumed.query_match
        wall_ms = $overall.ElapsedMilliseconds
    } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $reportRoot 'report.json') -Encoding UTF8
    Write-Host 'AURORA_WINDOWS_INSTALLED_PRODUCTION_KNOWLEDGE_OK'
} finally {
    if ($activeProcess -and -not $activeProcess.HasExited) { Stop-Process -Id $activeProcess.Id -Force -ErrorAction SilentlyContinue }
    foreach ($rule in $rules) { Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue }
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
}
