param(
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [string]$ReportDir = 'artifacts/windows-offline-voice'
)
$ErrorActionPreference = 'Stop'
$voice = Join-Path (Resolve-Path $InstallDir).Path 'voice'
$backend = Join-Path $voice 'AuroraVoiceBackend/AuroraVoiceBackend.exe'
if (-not (Test-Path $backend)) { throw 'Installed portable voice backend is missing' }
New-Item -ItemType Directory -Force $ReportDir | Out-Null
$reportRoot = (Resolve-Path $ReportDir).Path
$state = Join-Path $reportRoot 'user'
$settings = @{
    AURORAFOX_USER_DIR = $state
    AURORAFOX_VOICE_PORT = '18865'
    HF_HOME = (Join-Path $voice 'models/cache/huggingface')
    HUGGINGFACE_HUB_CACHE = (Join-Path $voice 'models/cache/huggingface/hub')
    TORCH_HOME = (Join-Path $voice 'models/cache/torch')
    HF_HUB_OFFLINE = '1'
    TRANSFORMERS_OFFLINE = '1'
}
$previous = @{}
$rule = 'AuroraFoxVoiceOffline-' + [Guid]::NewGuid().ToString('N')
$process = $null
$ruleCreated = $false
$stdoutLog = Join-Path $reportRoot 'backend.stdout.log'
$stderrLog = Join-Path $reportRoot 'backend.stderr.log'
try {
    foreach ($key in $settings.Keys) {
        $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $settings[$key], 'Process')
    }
    New-NetFirewallRule -DisplayName $rule -Direction Outbound -Program $backend -Action Block -Profile Any | Out-Null
    $ruleCreated = $true
    $backendRoot = Split-Path -Parent $backend
    $process = Start-Process -FilePath $backend -WorkingDirectory $backendRoot -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru
    $base = 'http://127.0.0.1:18865'
    $health = $null
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        if ($process.HasExited) {
            $stdout = if (Test-Path $stdoutLog) { Get-Content $stdoutLog -Raw } else { '' }
            $stderr = if (Test-Path $stderrLog) { Get-Content $stderrLog -Raw } else { '' }
            throw "Installed voice backend exited: $($process.ExitCode)`nstdout:`n$stdout`nstderr:`n$stderr"
        }
        try {
            $health = Invoke-RestMethod "$base/health" -TimeoutSec 2
            if ($health.ok -and $health.backend -eq 'AuroraVoice') { break }
        } catch { }
        Start-Sleep -Seconds 1
    }
    if (-not $health -or -not $health.ok -or $health.backend -ne 'AuroraVoice') {
        $stdout = if (Test-Path $stdoutLog) { Get-Content $stdoutLog -Raw } else { '' }
        $stderr = if (Test-Path $stderrLog) { Get-Content $stderrLog -Raw } else { '' }
        throw "Installed voice backend did not become healthy.`nstdout:`n$stdout`nstderr:`n$stderr"
    }
    $started = [Diagnostics.Stopwatch]::StartNew()
    $russianText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('0JDQstGA0L7RgNCwINGA0LDQsdC+0YLQsNC10YIg0LvQvtC60LDQu9GM0L3Qvi4='))
    $body = @{text=$russianText; backend='silero'} | ConvertTo-Json
    $tts = Invoke-RestMethod "$base/say" -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 300
    if (-not $tts.ok -or $tts.engine -ne 'silero' -or $tts.duration -le 0) { throw 'Installed offline TTS failed' }
    if (-not (Test-Path $tts.path) -or (Get-Item $tts.path).Length -le 44) { throw 'Installed TTS did not produce a WAV' }
    Copy-Item $tts.path (Join-Path $reportRoot 'installed-offline-tts.wav') -Force
    $body = @{path=$tts.path} | ConvertTo-Json
    $stt = Invoke-RestMethod "$base/stt_path" -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 600
    if (-not $stt.ok -or [string]::IsNullOrWhiteSpace($stt.text)) { throw 'Installed offline STT failed' }
    $started.Stop()
    @{
        passed=$true; installed=$true; outbound_firewall_block=$true
        offline_model_flags=$true; tts=$tts; stt=$stt; wall_ms=$started.ElapsedMilliseconds
        human_listening_verified=$false
    } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $reportRoot 'report.json') -Encoding UTF8
    Write-Host 'AURORA_WINDOWS_INSTALLED_OFFLINE_VOICE_OK'
} finally {
    if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    if ($ruleCreated) { Remove-NetFirewallRule -DisplayName $rule }
    foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process') }
}
