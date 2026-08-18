param(
    [string]$Godot = "godot",
    [switch]$SkipModelSetup,
    [switch]$SkipVoiceSetup
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outDir = Join-Path $root "build\windows"
$voiceSource = Join-Path $root "voice"
$voiceOut = Join-Path $outDir "voice"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (-not $SkipModelSetup) {
    $models = Join-Path $root "models\install_models.ps1"
    if (Test-Path $models) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $models
        if ($LASTEXITCODE -ne 0) { throw "Local model setup failed" }
    }
}

if (-not $SkipVoiceSetup) {
    $voiceInstaller = Join-Path $voiceSource "install_voice.ps1"
    if (-not (Test-Path $voiceInstaller)) { throw "Aurora Voice installer is missing" }
    Write-Host "Preparing local AuroraFox voice runtime..." -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File $voiceInstaller
    if ($LASTEXITCODE -ne 0) { throw "Aurora Voice setup failed" }
}

Push-Location $root
try {
    & $Godot --headless --path $root --import
    if ($LASTEXITCODE -ne 0) { throw "Godot import failed" }

    & $Godot --headless --path $root --export-release "Windows Desktop" (Join-Path $outDir "AuroraFox.exe")
    if ($LASTEXITCODE -ne 0) { throw "Windows export failed" }
} finally {
    Pop-Location
}

# The Python voice backend must be an ordinary filesystem tree next to the exported EXE.
# Godot starts pythonw.exe, so no terminal window is shown in production.
if (Test-Path $voiceOut) { Remove-Item $voiceOut -Recurse -Force }
New-Item -ItemType Directory -Force -Path $voiceOut | Out-Null

foreach ($dir in @("python", "config", "models", ".venv")) {
    $source = Join-Path $voiceSource $dir
    if (Test-Path $source) {
        Copy-Item $source (Join-Path $voiceOut $dir) -Recurse -Force
    }
}
foreach ($file in @("voice_service.py", "requirements.txt")) {
    $source = Join-Path $voiceSource $file
    if (Test-Path $source) { Copy-Item $source (Join-Path $voiceOut $file) -Force }
}

$pythonw = Join-Path $voiceOut ".venv\Scripts\pythonw.exe"
$server = Join-Path $voiceOut "python\aurora_voice_server.py"
$wake = Join-Path $voiceOut "models\vosk-model-small-ru-0.22"
if (-not $SkipVoiceSetup) {
    if (-not (Test-Path $pythonw)) { throw "Packaged voice pythonw.exe is missing" }
    if (-not (Test-Path $server)) { throw "Packaged voice backend is missing" }
    if (-not (Test-Path $wake)) { throw "Packaged Fox/Лиса wake model is missing" }
}

Write-Host "AuroraFox Windows build: $outDir\AuroraFox.exe" -ForegroundColor Green
Write-Host "Voice runtime: $voiceOut"
