$ErrorActionPreference = 'Stop'

Write-Host 'AuroraFox Voice setup' -ForegroundColor Cyan

$root = Split-Path -Parent $PSScriptRoot
$venv = Join-Path $PSScriptRoot '.venv'
$python = Join-Path $venv 'Scripts\python.exe'
$pip = Join-Path $venv 'Scripts\pip.exe'

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw 'Python 3.11+ не найден. Установите Python и повторите запуск.'
}

if (-not (Test-Path $python)) {
    python -m venv $venv
}

& $python -m pip install --upgrade pip wheel setuptools
& $pip install -r (Join-Path $PSScriptRoot 'requirements.txt')

Write-Host ''
Write-Host 'Голосовой модуль установлен.' -ForegroundColor Green
Write-Host 'Модели Silero v5_5_ru и Whisper large-v3-turbo загрузятся автоматически при первом использовании.'
Write-Host 'Для GPU будет автоматически использована CUDA, если установлен совместимый PyTorch.'
