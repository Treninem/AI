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
$portableDist = Join-Path $root "build\voice_backend"
$portableBuilt = $false
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

    $portableBuilder = Join-Path $voiceSource "build_backend.ps1"
    if (Test-Path $portableBuilder) {
        try {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $portableBuilder -OutputDir $portableDist
            $portableExe = Join-Path $portableDist "AuroraVoiceBackend\AuroraVoiceBackend.exe"
            $portableBuilt = (Test-Path $portableExe)
        } catch {
            Write-Warning "Portable AuroraVoiceBackend build failed. Windows package will use the local Python environment fallback: $($_.Exception.Message)"
            $portableBuilt = $false
        }
    }
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

if (Test-Path $voiceOut) { Remove-Item $voiceOut -Recurse -Force }
New-Item -ItemType Directory -Force -Path $voiceOut | Out-Null

# Runtime-independent resources are always copied next to the EXE.
foreach ($dir in @("python", "config", "models")) {
    $source = Join-Path $voiceSource $dir
    if (Test-Path $source) { Copy-Item $source (Join-Path $voiceOut $dir) -Recurse -Force }
}
foreach ($file in @("voice_service.py", "requirements.txt", "install_voice.ps1", "build_backend.ps1")) {
    $source = Join-Path $voiceSource $file
    if (Test-Path $source) { Copy-Item $source (Join-Path $voiceOut $file) -Force }
}

if ($portableBuilt) {
    Copy-Item (Join-Path $portableDist "AuroraVoiceBackend") (Join-Path $voiceOut "AuroraVoiceBackend") -Recurse -Force
} elseif (-not $SkipVoiceSetup) {
    # Development/emergency fallback. On the build PC this remains fully functional.
    $venvSource = Join-Path $voiceSource ".venv"
    if (Test-Path $venvSource) { Copy-Item $venvSource (Join-Path $voiceOut ".venv") -Recurse -Force }
}

$server = Join-Path $voiceOut "python\aurora_voice_server.py"
$wake = Join-Path $voiceOut "models\vosk-model-small-ru-0.22"
$hfCache = Join-Path $voiceOut "models\cache\huggingface"
$portableExe = Join-Path $voiceOut "AuroraVoiceBackend\AuroraVoiceBackend.exe"
$pythonw = Join-Path $voiceOut ".venv\Scripts\pythonw.exe"
if (-not $SkipVoiceSetup) {
    if (-not (Test-Path $server)) { throw "Packaged voice backend sources are missing" }
    if (-not (Test-Path $wake)) { throw "Packaged Fox/Лиса wake model is missing" }
    if (-not (Test-Path $hfCache)) { throw "Packaged Whisper cache is missing" }
    if (-not (Test-Path $portableExe) -and -not (Test-Path $pythonw)) {
        throw "Neither portable nor Python Aurora Voice runtime is available"
    }
}

Write-Host "AuroraFox Windows build: $outDir\AuroraFox.exe" -ForegroundColor Green
Write-Host "Voice runtime: $voiceOut"
Write-Host ("Portable voice backend: " + ($(if ($portableBuilt) { "YES" } else { "NO - fallback" })))
