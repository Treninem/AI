param(
    [switch]$SkipHeavyModels,
    [string]$StateFile = ""
)

$ErrorActionPreference = 'Stop'

$venv = Join-Path $PSScriptRoot '.venv'
$python = Join-Path $venv 'Scripts\python.exe'
$models = Join-Path $PSScriptRoot 'models'
$modelCache = Join-Path $models 'cache'
$hfHome = Join-Path $modelCache 'huggingface'
$torchHome = Join-Path $modelCache 'torch'
$voskDir = Join-Path $models 'vosk-model-small-ru-0.22'
$voskZip = Join-Path $env:TEMP 'aurorafox-vosk-ru.zip'

function Set-Stage([string]$Name, [int]$Progress, [string]$Message) {
    Write-Host ("[{0,3}%] {1}: {2}" -f $Progress, $Name, $Message) -ForegroundColor Cyan
    if ($StateFile) {
        $parent = Split-Path -Parent $StateFile
        if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        $payload = @{
            stage = $Name
            progress = $Progress
            message = $Message
            time = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($StateFile, $payload, [Text.UTF8Encoding]::new($false))
    }
}

try {
    Set-Stage 'components' 5 'Проверка Python 3.11 и окружения'
    $launcher = Get-Command py -ErrorAction SilentlyContinue
    $plainPython = Get-Command python -ErrorAction SilentlyContinue
    if (-not $launcher -and -not $plainPython) { throw 'Python 3.11 не найден.' }

    if (-not (Test-Path $python)) {
        if ($launcher) {
            & py -3.11 -m venv $venv
        } else {
            & python -m venv $venv
        }
        if ($LASTEXITCODE -ne 0) { throw 'Не удалось создать Python окружение.' }
    }

    Set-Stage 'dependencies' 18 'Установка зафиксированных локальных зависимостей'
    & $python -m pip install --disable-pip-version-check --upgrade 'pip==25.2' 'setuptools==80.9.0' 'wheel==0.45.1'
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось обновить pip.' }
    & $python -m pip install --disable-pip-version-check -r (Join-Path $PSScriptRoot 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось установить зависимости Aurora Voice.' }

    New-Item -ItemType Directory -Force -Path $models,$modelCache,$hfHome,$torchHome | Out-Null

    Set-Stage 'wake_word' 38 'Подготовка локальной модели Fox / Лиса'
    if (-not (Test-Path $voskDir)) {
        Invoke-WebRequest -Uri 'https://alphacephei.com/vosk/models/vosk-model-small-ru-0.22.zip' -OutFile $voskZip
        Expand-Archive -Path $voskZip -DestinationPath $models -Force
        Remove-Item $voskZip -Force -ErrorAction SilentlyContinue
    }

    $env:HF_HOME = $hfHome
    $env:HUGGINGFACE_HUB_CACHE = Join-Path $hfHome 'hub'
    $env:TORCH_HOME = $torchHome

    if (-not $SkipHeavyModels) {
        Set-Stage 'stt_model' 55 'Загрузка Whisper large-v3-turbo для локального распознавания'
        $sttCode = @'
from transformers import pipeline
import torch
pipeline(
    "automatic-speech-recognition",
    model="openai/whisper-large-v3-turbo",
    torch_dtype=torch.float32,
    device=-1,
)
print("WHISPER_READY")
'@
        & $python -c $sttCode
        if ($LASTEXITCODE -ne 0) { throw 'Не удалось подготовить Whisper.' }

        Set-Stage 'tts_model' 78 'Загрузка русского Silero TTS fallback'
        $ttsCode = @'
from silero import silero_tts
model, _ = silero_tts(language="ru", speaker="v5_5_ru")
print("SILERO_READY")
'@
        & $python -c $ttsCode
        if ($LASTEXITCODE -ne 0) { throw 'Не удалось подготовить Silero TTS.' }
    }

    Set-Stage 'microphone' 92 'Проверка аудио-библиотеки'
    $audioCode = @'
import sounddevice as sd
print("AUDIO_DEVICES", len(sd.query_devices()))
'@
    & $python -c $audioCode
    if ($LASTEXITCODE -ne 0) { throw 'Аудио-библиотека не смогла инициализироваться.' }

    Set-Stage 'ready' 100 'Голосовой модуль AuroraFox готов'
    Write-Host ''
    Write-Host 'AuroraFox Voice установлен.' -ForegroundColor Green
    Write-Host 'Wake word, VAD, STT и TTS подготовлены для локальной работы.'
    Write-Host 'XTTS остаётся необязательным backend и включается только с разрешённым оригинальным speaker_wav.'
} catch {
    Set-Stage 'error' 0 $_.Exception.Message
    throw
}
