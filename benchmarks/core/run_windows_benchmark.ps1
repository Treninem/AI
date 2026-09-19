param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath,
    [string]$ReportPath = "",
    [int]$SuiteTimeoutSeconds = 1200
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $root 'artifacts/core-benchmark-raw.json'
}
$ReportPath = [IO.Path]::GetFullPath($ReportPath)
$artifactDir = Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
Remove-Item -LiteralPath $ReportPath -Force -ErrorAction SilentlyContinue

$godot = (Resolve-Path -LiteralPath $GodotPath).Path
$godotDir = Split-Path -Parent $godot
$runtimeRoot = Join-Path $godotDir 'core_runtime'
$llama = Join-Path $runtimeRoot 'engine/llama-server.exe'
$model = Join-Path $runtimeRoot 'engine/aurorafox-core.gguf'
if (-not (Test-Path -LiteralPath $llama)) { throw "Benchmark Core Engine missing: $llama" }
if (-not (Test-Path -LiteralPath $model)) { throw "Benchmark bundled Core model missing: $model" }

$expectedBytes = 1282439264
$expectedSha = 'd2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5'
$modelItem = Get-Item -LiteralPath $model
if ($modelItem.Length -ne $expectedBytes) { throw "Benchmark model size mismatch: $($modelItem.Length)" }
$modelSha = (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash.ToLowerInvariant()
if ($modelSha -ne $expectedSha) { throw "Benchmark model SHA mismatch: $modelSha" }

$engineVersion = (& $llama --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($engineVersion)) {
    throw 'Unable to identify bundled Core Engine version.'
}

Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^ollama' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 250
$ollamaLeft = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^ollama' })
if ($ollamaLeft.Count -ne 0) { throw 'Ollama process is still running; offline Core benchmark cannot start.' }

$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name).Trim()
$env:AURORAFOX_BENCHMARK_REPORT = $ReportPath
$checkoutSha = & python (Join-Path $PSScriptRoot 'report_identity.py') --repo $root
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$checkoutSha)) { throw 'Benchmark source checkout identity failed.' }
$env:AURORAFOX_BENCHMARK_GIT_SHA = ([string]$checkoutSha).Trim()
$env:AURORAFOX_BENCHMARK_MODEL_SHA = $modelSha
$env:AURORAFOX_BENCHMARK_CPU = $cpu
$env:AURORAFOX_BENCHMARK_OLLAMA_ABSENT = '1'
$env:AURORAFOX_BENCHMARK_CLEAN_USER = '1'
$env:AURORAFOX_BENCHMARK_REQUIRE_NETWORK_GUARD = '1'
$env:AURORAFOX_BENCHMARK_SCENARIO_TIMEOUT_MS = '120000'

# Godot's Windows *_console.exe is a console wrapper that launches the sibling
# GUI executable. Guard and measure both binaries plus llama-server while leaving
# localhost usable for the bundled Core Engine.
$guardExecutables = @($godot, $llama)
if ($godot.ToLowerInvariant().EndsWith('_console.exe')) {
    $runtimeGodot = $godot.Substring(0, $godot.Length - '_console.exe'.Length) + '.exe'
    if (Test-Path -LiteralPath $runtimeGodot) {
        $guardExecutables += (Resolve-Path -LiteralPath $runtimeGodot).Path
    }
}
$guardExecutables = @($guardExecutables | Select-Object -Unique)
$godotProcessPaths = @($guardExecutables | Where-Object { $_ -ne $llama })
$godotProcessNames = @(
    $godotProcessPaths |
        ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) } |
        Select-Object -Unique
)

$ruleNames = @()
$networkGuardReady = $false
$exitCode = 255
$timedOut = $false
$godotPeak = [int64]0
$serverPeak = [int64]0
$combinedPeak = [int64]0
$stdoutPath = Join-Path $artifactDir 'core-benchmark-godot.stdout.log'
$stderrPath = Join-Path $artifactDir 'core-benchmark-godot.stderr.log'
Remove-Item $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
$stopwatch = [Diagnostics.Stopwatch]::StartNew()

try {
    foreach ($exe in $guardExecutables) {
        $name = 'AuroraFox-Core-Benchmark-' + [Guid]::NewGuid().ToString('N')
        New-NetFirewallRule -DisplayName $name -Direction Outbound -Action Block -Program $exe -RemoteAddress Internet -Profile Any | Out-Null
        $ruleNames += $name
    }
    $networkGuardReady = $ruleNames.Count -eq $guardExecutables.Count
    if (-not $networkGuardReady) { throw 'Failed to install benchmark Internet firewall guard.' }
    $env:AURORAFOX_BENCHMARK_NETWORK_GUARD_ACTIVE = '1'

    $script = Join-Path $root 'benchmarks/core/core_benchmark.gd'
    $argumentString = "--headless --path `"$root`" --script `"$script`""
    $process = Start-Process -FilePath $godot -ArgumentList $argumentString -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $deadline = [DateTime]::UtcNow.AddSeconds($SuiteTimeoutSeconds)

    while (-not $process.HasExited) {
        if ([DateTime]::UtcNow -ge $deadline) {
            $timedOut = $true
            & taskkill /PID $process.Id /T /F 2>$null | Out-Null
            break
        }
        $godotWorking = [int64]0
        foreach ($processName in $godotProcessNames) {
            foreach ($candidate in @(Get-Process -Name $processName -ErrorAction SilentlyContinue)) {
                try {
                    if ($godotProcessPaths -contains $candidate.Path) {
                        $godotWorking += [int64]$candidate.WorkingSet64
                    }
                } catch { }
            }
        }
        $serverWorking = [int64]0
        foreach ($server in @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue)) {
            try {
                if ($server.Path -eq $llama) { $serverWorking += [int64]$server.WorkingSet64 }
            } catch { }
        }
        $godotPeak = [Math]::Max($godotPeak, $godotWorking)
        $serverPeak = [Math]::Max($serverPeak, $serverWorking)
        $combinedPeak = [Math]::Max($combinedPeak, $godotWorking + $serverWorking)
        Start-Sleep -Milliseconds 250
        $process.Refresh()
    }

    if ($timedOut) {
        $exitCode = 124
    } else {
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    }
} finally {
    $stopwatch.Stop()
    foreach ($name in $ruleNames) {
        Remove-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
    }
    $env:AURORAFOX_BENCHMARK_NETWORK_GUARD_ACTIVE = '0'

    $report = $null
    if (Test-Path -LiteralPath $ReportPath) {
        try { $report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json -AsHashtable } catch { }
    }
    if ($null -eq $report) {
        $report = [ordered]@{
            schema_version = 1
            suite = 'aurorafox_core_quality_v1'
            status = if ($timedOut) { 'suite_timeout' } else { 'runner_failure' }
            git_sha = $env:AURORAFOX_BENCHMARK_GIT_SHA
            platform = 'Windows'
            machine = @{}
            environment = @{}
            core = @{}
            scenarios = @()
            performance = @{}
        }
    }
    if (-not $report.Contains('machine')) { $report['machine'] = @{} }
    if (-not $report.Contains('environment')) { $report['environment'] = @{} }
    if (-not $report.Contains('core')) { $report['core'] = @{} }
    if (-not $report.Contains('performance')) { $report['performance'] = @{} }

    $report['machine']['os'] = 'Windows'
    $report['machine']['arch'] = $env:PROCESSOR_ARCHITECTURE
    $report['machine']['logical_processors'] = [Environment]::ProcessorCount
    $report['machine']['processor_identifier'] = $cpu
    $report['environment']['network_guard_os_active'] = $networkGuardReady
    $report['environment']['ollama_absent_os_verified'] = $true
    $report['environment']['network_firewall_rules'] = $ruleNames
    $report['environment']['network_guard_executables'] = $guardExecutables
    $report['environment']['godot_process_paths_measured'] = $godotProcessPaths
    $report['core']['prepared_sha256'] = $modelSha
    $report['core']['actual_bytes'] = $modelItem.Length
    $report['core']['engine_version'] = $engineVersion
    $report['performance']['peak_rss_mb'] = [Math]::Round($combinedPeak / 1MB, 2)
    $report['performance']['godot_peak_rss_mb'] = [Math]::Round($godotPeak / 1MB, 2)
    $report['performance']['core_engine_peak_rss_mb'] = [Math]::Round($serverPeak / 1MB, 2)
    $report['performance']['suite_wall_ms'] = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
    $report['performance']['runner_suite_timeout'] = $timedOut
    if ($timedOut) {
        $report['performance']['timeout_count'] = [Math]::Max(1, [int]($report['performance']['timeout_count'] ?? 0))
        $report['status'] = 'suite_timeout'
    }
    $json = $report | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($ReportPath, $json, (New-Object Text.UTF8Encoding($false)))
}

Write-Host "AURORAFOX_CORE_BENCHMARK_RUNNER exit=$exitCode report=$ReportPath peak_rss_mb=$([Math]::Round($combinedPeak / 1MB, 2))"
exit $exitCode
