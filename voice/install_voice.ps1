$ErrorActionPreference = 'Stop'

Write-Host 'AuroraFox Voice setup' -ForegroundColor Cyan

$venv = Join-Path $PSScriptRoot '.venv'
$python = Join-Path $venv 'Scripts\python.exe'
$models = Join-Path $PSScriptRoot 'models'
$voskDir = Join-Path $models 'vosk-model-small-ru-0.22'
$voskZip = Join-Path $env:TEMP 'aurorafox-vosk-ru.zip'

$launcher = Get-Command py -ErrorAction SilentlyContinue
if ($launcher) {
    $base = @('-3.11')
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $base = @()
} else {
    throw 'Python 3.11 не найден.'
}

if (-not (Test-Path $python)) {
    if ($launcher) { & py @base -m venv $venv } else { python -m venv $venv }
}

& $python -m pip install --upgrade 'pip==25.2' 'setuptools==80.9.0' 'wheel==0.45.1'
& $python -m pip install -r (Join-Path $PSScriptRoot 'requirements.txt')

New-Item -ItemType Directory -Force -Path $models | Out-Null
if (-not (Test-Path $voskDir)) {
    Write-Host 'Загрузка локальной wake-word модели Fox/Лиса...' -ForegroundColor Yellow
    Invoke-WebRequest -Uri 'https://alphacephei.com/vosk/models/vosk-model-small-ru-0.22.zip' -OutFile $voskZip
    Expand-Archive -Path $voskZip -DestinationPath $models -Force
    Remove-Item $voskZip -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'AuroraFox Voice установлен.' -ForegroundColor Green
Write-Host 'VAD и wake word работают локально. Whisper и Silero загрузят модели при первом обращении.'
Write-Host 'XTTS является необязательным backend и устанавливается отдельно только при наличии собственного разрешённого speaker_wav.'
