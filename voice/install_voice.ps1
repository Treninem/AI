param(
    [switch]$SkipHeavyModels,
    [string]$StateFile = ""
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeRoot = Join-Path $projectRoot 'runtime\windows'
$ensureUv = Join-Path $projectRoot 'runtime\ensure_uv.ps1'
$uv = Join-Path $runtimeRoot 'uv\uv.exe'
$venv = Join-Path $PSScriptRoot '.venv'
$python = Join-Path $venv 'Scripts\python.exe'
$models = Join-Path $PSScriptRoot 'models'
$modelCache = Join-Path $models 'cache'
$hfHome = Join-Path $modelCache 'huggingface'
$torchHome = Join-Path $modelCache 'torch'
$voskDir = Join-Path $models 'vosk-model-small-ru-0.22'
$voskZip = Join-Path ([IO.Path]::GetTempPath()) 'aurorafox-vosk-ru.zip'

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
        [IO.File]::WriteAllText($StateFile, $payload, (New-Object Text.UTF8Encoding($false)))
    }
}

try {
    Set-Stage 'components' 5 'Preparing AuroraFox managed Python runtime'
    if (-not (Test-Path -LiteralPath $ensureUv)) { throw 'runtime/ensure_uv.ps1 was not found.' }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $ensureUv -RuntimeRoot $runtimeRoot | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $uv)) { throw 'Failed to prepare the local uv/Python runtime.' }

    $env:UV_PYTHON_INSTALL_DIR = Join-Path $runtimeRoot 'python'
    $env:UV_CACHE_DIR = Join-Path $runtimeRoot 'cache'
    $env:UV_PYTHON_PREFERENCE = 'only-managed'

    if (-not (Test-Path -LiteralPath $python)) {
        & $uv venv --python 3.11 $venv
        if ($LASTEXITCODE -ne 0) { throw 'Failed to create the Aurora Voice environment.' }
    }

    Set-Stage 'dependencies' 18 'Installing Aurora Voice dependencies'
    & $uv pip install --python $python -r (Join-Path $PSScriptRoot 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install Aurora Voice dependencies.' }

    New-Item -ItemType Directory -Force -Path $models,$modelCache,$hfHome,$torchHome | Out-Null

    Set-Stage 'wake_word' 38 'Preparing local Fox wake-word model'
    if (-not (Test-Path $voskDir)) {
        Invoke-WebRequest -Uri 'https://alphacephei.com/vosk/models/vosk-model-small-ru-0.22.zip' -OutFile $voskZip
        Expand-Archive -Path $voskZip -DestinationPath $models -Force
        Remove-Item $voskZip -Force -ErrorAction SilentlyContinue
    }

    $env:HF_HOME = $hfHome
    $env:HUGGINGFACE_HUB_CACHE = Join-Path $hfHome 'hub'
    $env:TORCH_HOME = $torchHome

    if (-not $SkipHeavyModels) {
        Set-Stage 'stt_model' 55 'Downloading Whisper large-v3-turbo for local STT'
        $sttCode = @(
            'from transformers import pipeline',
            'import torch',
            'pipeline(',
            '    "automatic-speech-recognition",',
            '    model="openai/whisper-large-v3-turbo",',
            '    torch_dtype=torch.float32,',
            '    device=-1,',
            ')',
            'print("WHISPER_READY")'
        ) -join "`n"
        & $python -c $sttCode
        if ($LASTEXITCODE -ne 0) { throw 'Failed to prepare Whisper.' }

        Set-Stage 'tts_model' 78 'Downloading Russian Silero TTS fallback'
        $ttsCode = @(
            'from silero import silero_tts',
            'model, _ = silero_tts(language="ru", speaker="v5_5_ru")',
            'print("SILERO_READY")'
        ) -join "`n"
        & $python -c $ttsCode
        if ($LASTEXITCODE -ne 0) { throw 'Failed to prepare Silero TTS.' }
    }

    Set-Stage 'microphone' 92 'Checking audio library'
    $audioCode = @(
        'import sounddevice as sd',
        'print("AUDIO_DEVICES", len(sd.query_devices()))'
    ) -join "`n"
    & $python -c $audioCode
    if ($LASTEXITCODE -ne 0) { throw 'Audio library initialization failed.' }

    Set-Stage 'ready' 100 'AuroraFox voice module is ready'
    Write-Host ''
    Write-Host 'AuroraFox Voice installed.' -ForegroundColor Green
    Write-Host 'System Python is not required; AuroraFox uses managed Python 3.11.'
    Write-Host 'Wake word, VAD, STT and TTS are prepared for local use.'
    Write-Host 'XTTS remains optional and requires an authorized original speaker_wav.'
} catch {
    Set-Stage 'error' 0 $_.Exception.Message
    throw
}
