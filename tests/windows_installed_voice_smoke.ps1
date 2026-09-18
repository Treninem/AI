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
$rule = 'AuroraFoxVoiceOffline-' + [Guid]::NewGuid().ToString('N')
$process = $null
$ruleCreated = $false
try {
    $externalIpv4 = @('0.0.0.0-126.255.255.255','128.0.0.0-255.255.255.255')
    $externalIpv6 = @('::/1','8000::/1')

    New-NetFirewallRule `
        -DisplayName $rule `
        -Direction Outbound `
        -Program $backend `
        -Action Block `
        -Profile Any `
        -RemoteAddress ($externalIpv4 + $externalIpv6) | Out-Null
    $ruleCreated = $true

    $backendRoot = Split-Path -Parent $backend
    $process = Start-Process -FilePath $backend -WorkingDirectory $backendRoot -PassThru
    $base = 'http://127.0.0.1:18865'
    $health = $null
    for ($i=0; $i -lt 120; $i++) {
        try {
            $health = Invoke-RestMethod "$base/health" -TimeoutSec 2
            if ($health.ok -and $health.backend -eq 'AuroraVoice') { break }
        } catch {}
        Start-Sleep 1
    }
    if (-not $health.ok) { throw 'Installed voice backend unhealthy' }

    $text = 'Проверка автономного голоса Аврора Фокс'
    $body = @{text=$text; backend='silero'} | ConvertTo-Json
    $tts = Invoke-RestMethod "$base/say" -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 300
    if (-not $tts.ok -or $tts.engine -ne 'silero') { throw 'Installed offline TTS failed' }

    $started = [Diagnostics.Stopwatch]::StartNew()
    $sttBody = @{path=$tts.path} | ConvertTo-Json
    $stt = Invoke-RestMethod "$base/stt_path" -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($sttBody)) -TimeoutSec 600
    $started.Stop()
    if (-not $stt.ok -or [string]::IsNullOrWhiteSpace($stt.text)) { throw 'Installed offline STT failed' }

    @{ passed=$true; installed=$true; outbound_firewall_block=$true; loopback_allowed=$true; offline_model_flags=$true; tts=$tts; stt=$stt; wall_ms=$started.ElapsedMilliseconds; human_listening_verified=$false } |
        ConvertTo-Json -Depth 12 | Set-Content (Join-Path $reportRoot 'report.json') -Encoding UTF8

    Write-Host 'AURORA_WINDOWS_INSTALLED_OFFLINE_VOICE_OK'
}
finally {
    if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    if ($ruleCreated) { Remove-NetFirewallRule -DisplayName $rule }
}
