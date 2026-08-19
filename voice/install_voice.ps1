param(
    [switch]$SkipHeavyModels,
    [switch]$EnableXtts,
    [switch]$AcceptXttsCpml,
    [string]$XttsSpeakerWav = "",
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
$voiceConfigPath = Join-Path $PSScriptRoot 'config\voice_config.json'
$xttsRequirements = Join-Path $PSScriptRoot 'requirements_xtts.txt'
$xttsSpeakerTarget = Join-Path $models 'xtts_speaker.wav'
$prepareFfmpeg = Join-Path $PSScriptRoot 'prepare_ffmpeg.ps1'
$ffmpegBin = Join-Path $PSScriptRoot 'runtime\ffmpeg\bin'
$xttsAgreementMarker = Join-Path $PSScriptRoot 'runtime\xtts_cpml_accepted.txt'
$voicePythonDir = Join-Path $PSScriptRoot 'python'

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

function Configure-Xtts([string]$SpeakerPath) {
    if (-not (Test-Path -LiteralPath $voiceConfigPath)) { throw 'voice/config/voice_config.json is missing.' }
    $config = Get-Content -LiteralPath $voiceConfigPath -Raw | ConvertFrom-Json
    if ($null -eq $config.xtts) { throw 'XTTS configuration section is missing.' }
    $config.xtts.enabled = $true
    $config.xtts.model = 'tts_models/multilingual/multi-dataset/xtts_v2'
    $config.xtts.speaker_wav = 'models/xtts_speaker.wav'
    $config.xtts.language = 'ru'
    $config.quality = 'quality'
    $json = ($config | ConvertTo-Json -Depth 20) + "`n"
    [IO.File]::WriteAllText($voiceConfigPath, $json, (New-Object Text.UTF8Encoding($false)))
    Copy-Item -LiteralPath $SpeakerPath -Destination $xttsSpeakerTarget -Force
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $xttsAgreementMarker) | Out-Null
    [IO.File]::WriteAllText(
        $xttsAgreementMarker,
        "XTTS-v2 CPML/TOS explicitly accepted by the local user via -AcceptXttsCpml.`n",
        (New-Object Text.UTF8Encoding($false))
    )
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

    if ($EnableXtts) {
        if (-not $AcceptXttsCpml) {
            throw 'XTTS-v2 requires explicit CPML/TOS acceptance. Re-run with -AcceptXttsCpml after reviewing the Coqui Public Model License.'
        }
        if ([string]::IsNullOrWhiteSpace($XttsSpeakerWav)) {
            throw 'EnableXtts requires -XttsSpeakerWav with an authorized speaker reference WAV.'
        }
        $speaker = (Resolve-Path -LiteralPath $XttsSpeakerWav).Path
        if ([IO.Path]::GetExtension($speaker).ToLowerInvariant() -ne '.wav') {
            throw 'XTTS speaker reference must be a WAV file.'
        }

        Set-Stage 'ffmpeg' 25 'Preparing verified shared FFmpeg runtime for XTTS/TorchCodec'
        if (-not (Test-Path -LiteralPath $prepareFfmpeg)) { throw 'voice/prepare_ffmpeg.ps1 is missing.' }
        & powershell -NoProfile -ExecutionPolicy Bypass -File $prepareFfmpeg | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Failed to prepare the AuroraFox shared FFmpeg runtime.' }
        if (-not (Test-Path -LiteralPath (Join-Path $ffmpegBin 'ffmpeg.exe'))) {
            throw 'AuroraFox shared FFmpeg runtime was not produced.'
        }
        if (@(Get-ChildItem -LiteralPath $ffmpegBin -Filter 'avcodec-*.dll' -File -ErrorAction SilentlyContinue).Count -eq 0) {
            throw 'AuroraFox FFmpeg runtime does not contain shared avcodec DLLs.'
        }
        $env:AURORAFOX_FFMPEG_BIN = $ffmpegBin
        $env:PATH = "$ffmpegBin;$env:PATH"

        Set-Stage 'xtts_dependencies' 32 'Installing maintained Coqui XTTS-v2 backend'
        if (-not (Test-Path -LiteralPath $xttsRequirements)) { throw 'voice/requirements_xtts.txt is missing.' }
        & $uv pip install --python $python -r $xttsRequirements
        if ($LASTEXITCODE -ne 0) { throw 'Failed to install XTTS-v2 dependencies.' }

        Configure-Xtts $speaker
        $env:COQUI_TOS_AGREED = '1'
        $env:AURORAFOX_VOICE_PYTHON_DIR = $voicePythonDir
        & $python -c "import os,sys; sys.path.insert(0, os.environ['AURORAFOX_VOICE_PYTHON_DIR']); import tts_engine; from TTS.api import TTS; import torchcodec; print('XTTS_IMPORT_OK', tts_engine.LOCAL_FFMPEG_BIN)"
        if ($LASTEXITCODE -ne 0) { throw 'XTTS-v2/TorchCodec/FFmpeg import validation failed.' }
    }

    Set-Stage 'wake_word' 42 'Preparing local Fox wake-word model'
    if (-not (Test-Path $voskDir)) {
        Invoke-WebRequest -Uri 'https://alphacephei.com/vosk/models/vosk-model-small-ru-0.22.zip' -OutFile $voskZip
        Expand-Archive -Path $voskZip -DestinationPath $models -Force
        Remove-Item $voskZip -Force -ErrorAction SilentlyContinue
    }

    $env:HF_HOME = $hfHome
    $env:HUGGINGFACE_HUB_CACHE = Join-Path $hfHome 'hub'
    $env:TORCH_HOME = $torchHome

    if (-not $SkipHeavyModels) {
        Set-Stage 'stt_model' 58 'Downloading Whisper large-v3-turbo for local STT'
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

        Set-Stage 'tts_model' 75 'Downloading Russian Silero TTS fallback'
        $ttsCode = @(
            'from silero import silero_tts',
            'model, _ = silero_tts(language="ru", speaker="v5_5_ru")',
            'print("SILERO_READY")'
        ) -join "`n"
        & $python -c $ttsCode
        if ($LASTEXITCODE -ne 0) { throw 'Failed to prepare Silero TTS.' }

        if ($EnableXtts) {
            Set-Stage 'xtts_model' 87 'Downloading and loading XTTS-v2 model through AuroraFox runtime'
            $env:AURORAFOX_VOICE_PYTHON_DIR = $voicePythonDir
            $env:AURORAFOX_VOICE_CONFIG = $voiceConfigPath
            $xttsCode = @(
                'import json, os, sys',
                'sys.path.insert(0, os.environ["AURORAFOX_VOICE_PYTHON_DIR"])',
                'import tts_engine',
                'cfg = json.load(open(os.environ["AURORAFOX_VOICE_CONFIG"], encoding="utf-8"))',
                'engine = tts_engine.XTTSVoiceEngine(cfg["xtts"], "cpu")',
                'assert engine.available(), engine.diagnostics()',
                'engine._load()',
                'print("XTTS_MODEL_READY", engine.diagnostics())'
            ) -join "`n"
            & $python -c $xttsCode
            if ($LASTEXITCODE -ne 0) { throw 'Failed to prepare XTTS-v2 model.' }
        }
    }

    Set-Stage 'microphone' 95 'Checking audio library'
    $audioCode = @(
        'import sounddevice as sd',
        'print("AUDIO_DEVICES", len(sd.query_devices()))'
    ) -join "`n"
    & $python -c $audioCode
    if ($LASTEXITCODE -ne 0) { throw 'Audio library initialization failed.' }

    Set-Stage 'ready' 100 'AuroraFox voice installation checks passed'
    Write-Host ''
    Write-Host 'AuroraFox Voice installation checks passed.' -ForegroundColor Green
    Write-Host 'System Python is not required; AuroraFox uses managed Python 3.11.'
    Write-Host 'Wake word, VAD, STT and local TTS dependencies are prepared.'
    if ($EnableXtts) {
        Write-Host 'XTTS-v2 is enabled with the supplied local speaker reference and AuroraFox-local shared FFmpeg runtime.' -ForegroundColor Green
    } else {
        Write-Host 'XTTS-v2 is optional and remains disabled by default.'
        Write-Host 'To enable it, review CPML and run: install_voice.ps1 -EnableXtts -AcceptXttsCpml -XttsSpeakerWav <authorized.wav>'
    }
} catch {
    Set-Stage 'error' 0 $_.Exception.Message
    throw
}
