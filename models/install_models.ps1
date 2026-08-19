param(
    [ValidateSet('core','balanced','full')][string]$Profile = 'balanced',
    [string]$StateFile = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Set-Stage([string]$Name, [int]$Progress, [string]$Message) {
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
        } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($StateFile, $payload, [Text.UTF8Encoding]::new($false))
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
        $null = Invoke-RestMethod -Method Get -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 3
        return $true
    } catch {
        return $false
    }
}

try {
    Set-Stage 'runtime' 5 'Проверка локального движка Ollama'
    $ollama = Find-Ollama
    if (-not $ollama) {
        Set-Stage 'runtime_download' 10 'Загрузка официального установщика Ollama'
        $installScript = Invoke-RestMethod -Uri 'https://ollama.com/install.ps1' -Method Get
        if (-not $installScript) { throw 'Не удалось загрузить официальный установщик Ollama.' }
        Set-Stage 'runtime_install' 16 'Установка Ollama в профиль текущего пользователя'
        & ([ScriptBlock]::Create([string]$installScript))
        $ollama = Find-Ollama
        if (-not $ollama) { throw 'Ollama установлен, но ollama.exe не найден.' }
    }

    if (-not (Test-OllamaServer)) {
        Set-Stage 'runtime_start' 22 'Запуск локального Ollama API'
        Start-Process -FilePath $ollama -ArgumentList @('serve') -WindowStyle Hidden | Out-Null
        $deadline = (Get-Date).AddSeconds(45)
        while ((Get-Date) -lt $deadline -and -not (Test-OllamaServer)) {
            Start-Sleep -Milliseconds 500
        }
        if (-not (Test-OllamaServer)) { throw 'Локальный Ollama API не запустился на 127.0.0.1:11434.' }
    }

    $models = @('qwen3:8b')
    if ($Profile -in @('balanced','full')) { $models += 'qwen3-vl:8b' }
    if ($Profile -eq 'full') { $models += 'qwen3-coder:30b' }

    $base = 30
    $span = 60
    for ($i = 0; $i -lt $models.Count; $i++) {
        $model = $models[$i]
        $progress = $base + [int](($span * $i) / [Math]::Max(1, $models.Count))
        Set-Stage 'model_pull' $progress "Загрузка локальной модели $model"
        & $ollama pull $model
        if ($LASTEXITCODE -ne 0) { throw "Не удалось загрузить модель $model" }
    }

    Set-Stage 'verify' 94 'Проверка локальных моделей'
    $tags = Invoke-RestMethod -Method Get -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 10
    $names = @($tags.models | ForEach-Object { [string]$_.name })
    foreach ($model in $models) {
        if ($names -notcontains $model) { throw "Ollama не подтвердил установленную модель $model" }
    }

    Set-Stage 'ready' 100 'Локальное AI-ядро AuroraFox готово'
    Write-Host ''
    Write-Host 'AuroraFox local AI runtime is ready.' -ForegroundColor Green
    Write-Host "Profile: $Profile"
    Write-Host ("Models: " + ($models -join ', '))
} catch {
    Set-Stage 'error' 0 $_.Exception.Message
    throw
}
