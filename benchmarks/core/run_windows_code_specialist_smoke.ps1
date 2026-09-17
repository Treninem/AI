param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath,
    [string]$ReportPath = "",
    [int]$TimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $root 'artifacts/code-specialist-smoke.json'
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
if (-not (Test-Path -LiteralPath $llama)) { throw "CodeSpecialist Core Engine missing: $llama" }
if (-not (Test-Path -LiteralPath $model)) { throw "CodeSpecialist bundled Core model missing: $model" }

Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^ollama' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 250
$ollamaLeft = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^ollama' })
if ($ollamaLeft.Count -ne 0) {
    throw 'Ollama process is still running; CodeSpecialist offline smoke cannot start.'
}

$guardExecutables = @($godot, $llama)
if ($godot.ToLowerInvariant().EndsWith('_console.exe')) {
    $runtimeGodot = $godot.Substring(0, $godot.Length - '_console.exe'.Length) + '.exe'
    if (Test-Path -LiteralPath $runtimeGodot) {
        $guardExecutables += (Resolve-Path -LiteralPath $runtimeGodot).Path
    }
}
$guardExecutables = @($guardExecutables | Select-Object -Unique)
$ruleNames = @()
$stdoutPath = Join-Path $artifactDir 'code-specialist-smoke.stdout.log'
$stderrPath = Join-Path $artifactDir 'code-specialist-smoke.stderr.log'
Remove-Item $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
$exitCode = 255
$timedOut = $false

try {
    foreach ($exe in $guardExecutables) {
        $name = 'AuroraFox-CodeSpecialist-Smoke-' + [Guid]::NewGuid().ToString('N')
        New-NetFirewallRule -DisplayName $name -Direction Outbound -Action Block -Program $exe -RemoteAddress Internet -Profile Any | Out-Null
        $ruleNames += $name
    }
    if ($ruleNames.Count -ne $guardExecutables.Count) { throw 'Failed to install CodeSpecialist Internet firewall guard.' }
    $env:AURORAFOX_CODE_SPECIALIST_REPORT = $ReportPath
    $env:AURORAFOX_CODE_SPECIALIST_NETWORK_GUARD = '1'

    $script = Join-Path $root 'benchmarks/core/code_specialist_smoke.gd'
    $argumentString = "--headless --path `"$root`" --script `"$script`""
    $process = Start-Process -FilePath $godot -ArgumentList $argumentString -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while (-not $process.HasExited) {
        if ([DateTime]::UtcNow -ge $deadline) {
            $timedOut = $true
            & taskkill /PID $process.Id /T /F 2>$null | Out-Null
            break
        }
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
    foreach ($name in $ruleNames) {
        Remove-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
    }
    $env:AURORAFOX_CODE_SPECIALIST_NETWORK_GUARD = '0'
}

if ($timedOut) {
    Write-Host 'AURORAFOX_CODE_SPECIALIST_TIMEOUT_DIAGNOSTICS' -ForegroundColor Yellow
    if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Tail 120 | Write-Host }
    if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Tail 120 | Write-Host }
    throw "CodeSpecialist offline smoke timed out after $TimeoutSeconds seconds. Individual desktop Core requests are separately bounded by DesktopLocalRuntime."
}
if (-not (Test-Path -LiteralPath $ReportPath)) { throw "CodeSpecialist smoke report missing: $ReportPath" }
$report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
if ($report.passed -ne $true) { throw 'CodeSpecialist offline smoke reported failure.' }
if ($exitCode -ne 0) { throw "CodeSpecialist offline smoke process failed with exit code $exitCode" }
Write-Host "AURORAFOX_CODE_SPECIALIST_OFFLINE_GATE_OK report=$ReportPath"