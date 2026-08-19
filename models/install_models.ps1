param(
    [ValidateSet('core','balanced','full')][string]$Profile = 'balanced',
    [string]$StateFile = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$OllamaBase = 'http://127.0.0.1:11434'
$MinimumVisionOllama = [Version]'0.12.7'

function Set-Stage([string]$Name, [int]$Progress, [string]$Message, [hashtable]$Extra = @{}) {
    $Progress = [Math]::Max(0, [Math]::Min(100, $Progress))
    Write-Host ("[{0,3}%] {1}: {2}" -f $Progress, $Name, $Message) -ForegroundColor Cyan
    if ($StateFile) {
        $parent = Split-Path -Parent $StateFile
        if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        $payload = @{
            stage = $Name
            progress = $Progress
            message = $Message
            profile = $Profile
            time = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        }
        foreach ($key in $Extra.Keys) { $payload[$key] = $Extra[$key] }
        $json = $payload | ConvertTo-Json -Compress -Depth 5
        $temp = "$StateFile.tmp"
        [IO.File]::WriteAllText($temp, $json, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temp -Destination $StateFile -Force
    }
}

function Find-Ollama {
    $cmd = Get-Command ollama -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $known = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'),
        (Join-Path $env:LOCALAPPDATA 'Ollama\ollama.exe')
    )
    foreach ($path in $known) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return ''
}

function Test-OllamaServer {
    try {
        $null = Invoke-RestMethod -Method Get -Uri "$OllamaBase/api/tags" -TimeoutSec 3
        return $true
    } catch {
        return $false
    }
}

function Get-OllamaVersion {
    try {
        $response = Invoke-RestMethod -Method Get -Uri "$OllamaBase/api/version" -TimeoutSec 4
        $raw = [string]$response.version
        if ($raw -match '([0-9]+\.[0-9]+\.[0-9]+)') { return [Version]$Matches[1] }
    } catch {}
    return $null
}

function Stop-OllamaProcesses {
    $processes = @(Get-Process -Name 'ollama' -ErrorAction SilentlyContinue)
    foreach ($process in $processes) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
        } catch {
            Write-Warning "Не удалось остановить Ollama PID $($process.Id): $($_.Exception.Message)"
        }
    }
    if ($processes.Count -gt 0) {
        $deadline = (Get-Date).AddSeconds(12)
        while ((Get-Date) -lt $deadline -and (Test-OllamaServer)) {
            Start-Sleep -Milliseconds 300
        }
    }
}

function Install-Or-Update-Ollama([string]$Reason) {
    Set-Stage 'runtime_download' 10 "Загрузка официального установщика Ollama ($Reason)"
    $installScript = Invoke-RestMethod -Uri 'https://ollama.com/install.ps1' -Method Get -TimeoutSec 60
    if (-not $installScript) { throw 'Не удалось загрузить официальный установщик Ollama.' }
    if ([string]$installScript -notmatch 'ollama') { throw 'Получен неожиданный ответ вместо установщика Ollama.' }

    $previous = Find-Ollama
    if (Test-OllamaServer) {
        Set-Stage 'runtime_install' 14 'Останавливаю старый локальный Ollama перед обновлением'
        Stop-OllamaProcesses
    }
    Set-Stage 'runtime_install' 16 'Установка/обновление Ollama в профиль текущего пользователя'
    try {
        & ([ScriptBlock]::Create([string]$installScript))
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "Установщик Ollama завершился с кодом $LASTEXITCODE" }
    } catch {
        if ($previous -and (Test-Path -LiteralPath $previous)) {
            try { Start-Process -FilePath $previous -ArgumentList @('serve') -WindowStyle Hidden | Out-Null } catch {}
        }
        throw
    }
    $found = Find-Ollama
    if (-not $found) { throw 'Ollama установлен/обновлён, но ollama.exe не найден.' }
    return $found
}

function Ensure-OllamaServer([string]$OllamaPath, [switch]$ForceRestart) {
    if ($ForceRestart -and (Test-OllamaServer)) {
        Stop-OllamaProcesses
    }
    if (Test-OllamaServer) { return }
    Set-Stage 'runtime_start' 22 'Запуск локального Ollama API'
    Start-Process -FilePath $OllamaPath -ArgumentList @('serve') -WindowStyle Hidden | Out-Null
    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline -and -not (Test-OllamaServer)) {
        Start-Sleep -Milliseconds 500
    }
    if (-not (Test-OllamaServer)) { throw 'Локальный Ollama API не запустился на 127.0.0.1:11434.' }
}

function Format-Bytes([long]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N2} ГБ' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} МБ' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} КБ' -f ($Bytes / 1KB)) }
    return "$Bytes Б"
}

function Pull-OllamaModel(
    [string]$Model,
    [int]$Index,
    [int]$Count,
    [int]$OverallStart = 30,
    [int]$OverallSpan = 60
) {
    $modelStart = $OverallStart + [int][Math]::Floor(($OverallSpan * $Index) / [Math]::Max(1, $Count))
    $modelEnd = $OverallStart + [int][Math]::Floor(($OverallSpan * ($Index + 1)) / [Math]::Max(1, $Count))
    $modelSpan = [Math]::Max(1, $modelEnd - $modelStart)
    Set-Stage 'model_pull' $modelStart "Подготовка $Model" @{ model = $Model; model_index = $Index + 1; model_count = $Count; completed = 0; total = 0 }

    $handler = [Net.Http.HttpClientHandler]::new()
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromHours(12)
    try {
        $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post, "$OllamaBase/api/pull")
        $request.Content = [Net.Http.StringContent]::new((@{ name = $Model; stream = $true } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
        $response = $client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            throw "Ollama pull $Model HTTP $([int]$response.StatusCode): $($body.Substring(0, [Math]::Min(1000, $body.Length)))"
        }
        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8)
        try {
            $lastProgress = -1
            while (-not $reader.EndOfStream) {
                $line = $reader.ReadLine()
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try { $event = $line | ConvertFrom-Json } catch { continue }
                if ($event.error) { throw "Ollama: $($event.error)" }
                $completed = if ($null -ne $event.completed) { [long]$event.completed } else { 0L }
                $total = if ($null -ne $event.total) { [long]$event.total } else { 0L }
                $overall = $modelStart
                $detail = [string]$event.status
                if ($total -gt 0) {
                    $fraction = [Math]::Max(0.0, [Math]::Min(1.0, [double]$completed / [double]$total))
                    $overall = $modelStart + [int][Math]::Floor($modelSpan * $fraction)
                    $detail = "$Model • $(Format-Bytes $completed) / $(Format-Bytes $total) • $([int]($fraction * 100))%"
                } elseif (-not $detail) {
                    $detail = "Загрузка $Model"
                }
                if ($overall -ne $lastProgress -or $total -gt 0) {
                    Set-Stage 'model_pull' ([Math]::Min($overall, $modelEnd - 1)) $detail @{
                        model = $Model
                        model_index = $Index + 1
                        model_count = $Count
                        completed = $completed
                        total = $total
                        status = [string]$event.status
                    }
                    $lastProgress = $overall
                }
            }
        } finally {
            $reader.Dispose()
            $stream.Dispose()
            $response.Dispose()
            $request.Dispose()
        }
    } finally {
        $client.Dispose()
        $handler.Dispose()
    }
    Set-Stage 'model_pull' $modelEnd "$Model загружена и проверена Ollama" @{ model = $Model; model_index = $Index + 1; model_count = $Count }
}

try {
    Set-Stage 'runtime' 5 'Проверка локального движка Ollama'
    $ollama = Find-Ollama
    if (-not $ollama) {
        $ollama = Install-Or-Update-Ollama 'Ollama не установлен'
        Ensure-OllamaServer $ollama -ForceRestart
    } else {
        Ensure-OllamaServer $ollama
    }

    if ($Profile -in @('balanced','full')) {
        $version = Get-OllamaVersion
        if ($null -eq $version -or $version -lt $MinimumVisionOllama) {
            $shown = if ($null -eq $version) { 'не определена' } else { $version.ToString() }
            Set-Stage 'runtime_install' 18 "Обновление Ollama для vision-модели (текущая версия: $shown)"
            $ollama = Install-Or-Update-Ollama "нужна версия $MinimumVisionOllama или новее для qwen3-vl"
            Ensure-OllamaServer $ollama -ForceRestart
            $version = Get-OllamaVersion
            if ($null -eq $version -or $version -lt $MinimumVisionOllama) {
                throw "Ollama $MinimumVisionOllama+ требуется для qwen3-vl; после обновления обнаружена версия $version"
            }
        }
    }

    $models = @('qwen3:8b')
    if ($Profile -in @('balanced','full')) { $models += 'qwen3-vl:8b' }
    if ($Profile -eq 'full') { $models += 'qwen3-coder:30b' }

    for ($i = 0; $i -lt $models.Count; $i++) {
        Pull-OllamaModel -Model $models[$i] -Index $i -Count $models.Count
    }

    Set-Stage 'verify' 94 'Проверка локальных моделей через Ollama API'
    $tags = Invoke-RestMethod -Method Get -Uri "$OllamaBase/api/tags" -TimeoutSec 10
    $names = @($tags.models | ForEach-Object { [string]$_.name })
    foreach ($model in $models) {
        if ($names -notcontains $model) { throw "Ollama не подтвердил установленную модель $model" }
    }

    $version = Get-OllamaVersion
    Set-Stage 'ready' 100 'Локальное AI-ядро AuroraFox готово' @{ models = $models; ollama_version = if ($version) { $version.ToString() } else { '' } }
    Write-Host ''
    Write-Host 'AuroraFox local AI runtime is ready.' -ForegroundColor Green
    Write-Host "Profile: $Profile"
    Write-Host ("Models: " + ($models -join ', '))
} catch {
    Set-Stage 'error' 0 $_.Exception.Message
    throw
}
