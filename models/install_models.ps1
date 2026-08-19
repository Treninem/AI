param(
    [ValidateSet('core','balanced','full')][string]$Profile = 'balanced',
    [string]$StateFile = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$OllamaBase = 'http://127.0.0.1:11434'
$OllamaInstallerUrl = 'https://ollama.com/download/OllamaSetup.exe'
$MinimumVisionOllama = [Version]'0.12.7'
$ModelEstimatedBytes = @{
    'qwen3:8b' = 5200000000L
    'qwen3-embedding:0.6b' = 639000000L
    'qwen3-vl:8b' = 6100000000L
    'qwen3-coder:30b' = 19000000000L
}

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
        [IO.File]::WriteAllText($temp, $json, (New-Object Text.UTF8Encoding($false)))
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

function Get-InstalledModelNames {
    try {
        $tags = Invoke-RestMethod -Method Get -Uri "$OllamaBase/api/tags" -TimeoutSec 10
        return @($tags.models | ForEach-Object { [string]$_.name })
    } catch {
        return @()
    }
}

function Get-OllamaModelRoot {
    if ($env:OLLAMA_MODELS) {
        return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($env:OLLAMA_MODELS))
    }
    return Join-Path $env:USERPROFILE '.ollama\models'
}

function Get-FreeBytesForPath([string]$Path) {
    try {
        $full = [IO.Path]::GetFullPath($Path)
        $root = [IO.Path]::GetPathRoot($full)
        if (-not $root) { return -1L }
        return (New-Object IO.DriveInfo($root)).AvailableFreeSpace
    } catch {
        return -1L
    }
}

function Assert-ModelStorage([string[]]$Models) {
    $installed = Get-InstalledModelNames
    [long]$missingBytes = 0
    $missing = @()
    foreach ($model in $Models) {
        if ($installed -contains $model) { continue }
        $missing += $model
        if ($ModelEstimatedBytes.ContainsKey($model)) { $missingBytes += [long]$ModelEstimatedBytes[$model] }
    }
    if ($missing.Count -eq 0) {
        Set-Stage 'storage' 27 'Все модели выбранного профиля уже находятся локально' @{ required_bytes = 0; free_bytes = (Get-FreeBytesForPath (Get-OllamaModelRoot)); missing_models = @() }
        return
    }
    $root = Get-OllamaModelRoot
    $free = Get-FreeBytesForPath $root
    $required = [long][Math]::Ceiling($missingBytes * 1.08 + 1500000000L)
    Set-Stage 'storage' 27 "Проверка места: нужно примерно $(Format-Bytes $required), свободно $(if ($free -ge 0) { Format-Bytes $free } else { 'не удалось определить' })" @{
        model_root = $root
        required_bytes = $required
        free_bytes = $free
        missing_models = $missing
    }
    if ($free -ge 0 -and $free -lt $required) {
        throw "Недостаточно места для профиля $Profile. Нужно примерно $(Format-Bytes $required), свободно $(Format-Bytes $free)."
    }
}

function Stop-OllamaProcesses {
    $processes = @()
    foreach ($name in @('ollama', 'ollama app')) {
        $processes += @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    }
    $processes = @($processes | Sort-Object Id -Unique)
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

function Remove-DirectoryWithRetry([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq 8) {
                Write-Warning "Не удалось удалить временную папку ${Path}: $($_.Exception.Message)"
                return
            }
            Start-Sleep -Milliseconds (250 * $attempt)
        }
    }
}

function Install-Or-Update-Ollama([string]$Reason) {
    Set-Stage 'runtime_download' 10 "Загрузка официального установщика Ollama ($Reason)"
    $previous = Find-Ollama
    if (Test-OllamaServer) {
        Set-Stage 'runtime_install' 13 'Останавливаю старый локальный Ollama перед обновлением'
        Stop-OllamaProcesses
    }

    $tempRoot = Join-Path $env:TEMP ("AuroraFox-Ollama-" + [Guid]::NewGuid().ToString('N'))
    $tempInstaller = Join-Path $tempRoot 'OllamaSetup.exe'
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    try {
        $downloaded = $false
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Invoke-WebRequest -Uri $OllamaInstallerUrl -OutFile $tempInstaller -UseBasicParsing -TimeoutSec 240
                if (-not (Test-Path -LiteralPath $tempInstaller)) { throw 'Файл установщика не появился после загрузки.' }
                if ((Get-Item -LiteralPath $tempInstaller).Length -lt 1000000) { throw 'Получен слишком маленький файл вместо OllamaSetup.exe.' }
                $downloaded = $true
                break
            } catch {
                if ($attempt -eq 3) { throw }
                Start-Sleep -Seconds (2 * $attempt)
            }
        }
        if (-not $downloaded) { throw 'Не удалось загрузить OllamaSetup.exe.' }

        Set-Stage 'runtime_install' 15 'Проверка цифровой подписи OllamaSetup.exe'
        $signature = Get-AuthenticodeSignature -FilePath $tempInstaller
        if ($signature.Status -ne 'Valid') {
            throw "Цифровая подпись OllamaSetup.exe не прошла проверку: $($signature.Status)"
        }

        Set-Stage 'runtime_install' 17 'Установка/обновление Ollama в профиль текущего пользователя'
        $process = Start-Process -FilePath $tempInstaller -ArgumentList @('/VERYSILENT','/NORESTART','/SUPPRESSMSGBOXES') -Wait -PassThru
        if ($process.ExitCode -notin @(0, 3010)) {
            throw "Установщик Ollama завершился с кодом $($process.ExitCode)"
        }
    } catch {
        if ($previous -and (Test-Path -LiteralPath $previous)) {
            try { Start-Process -FilePath $previous -ArgumentList @('serve') -WindowStyle Hidden | Out-Null } catch {}
        }
        throw
    } finally {
        Remove-DirectoryWithRetry $tempRoot
    }

    $deadline = (Get-Date).AddSeconds(20)
    $found = Find-Ollama
    while (-not $found -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $found = Find-Ollama
    }
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

    $request = [System.Net.HttpWebRequest]::Create("$OllamaBase/api/pull")
    $request.Method = 'POST'
    $request.ContentType = 'application/json'
    $request.Accept = 'application/x-ndjson, application/json'
    $request.Timeout = 43200000
    $request.ReadWriteTimeout = 43200000
    $payload = @{ name = $Model; stream = $true } | ConvertTo-Json -Compress
    $payloadBytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $request.ContentLength = $payloadBytes.Length

    $requestStream = $null
    $response = $null
    $stream = $null
    $reader = $null
    try {
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($payloadBytes, 0, $payloadBytes.Length)
        $requestStream.Flush()
        $requestStream.Dispose()
        $requestStream = $null

        try {
            $response = $request.GetResponse()
        } catch [System.Net.WebException] {
            $webError = $_.Exception
            if ($webError.Response) {
                $errorStream = $webError.Response.GetResponseStream()
                $errorReader = New-Object IO.StreamReader($errorStream, [Text.Encoding]::UTF8)
                try { $errorBody = $errorReader.ReadToEnd() } finally { $errorReader.Dispose(); $errorStream.Dispose(); $webError.Response.Dispose() }
                throw "Ollama pull $Model HTTP error: $($errorBody.Substring(0, [Math]::Min(1000, $errorBody.Length)))"
            }
            throw
        }

        $stream = $response.GetResponseStream()
        $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8)
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
        if ($reader) { $reader.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }
        if ($requestStream) { $requestStream.Dispose() }
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

    $models = @('qwen3:8b', 'qwen3-embedding:0.6b')
    if ($Profile -in @('balanced','full')) { $models += 'qwen3-vl:8b' }
    if ($Profile -eq 'full') { $models += 'qwen3-coder:30b' }

    Assert-ModelStorage $models
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