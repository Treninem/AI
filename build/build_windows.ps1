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
$computerSource = Join-Path $root "computer"
$computerOut = Join-Path $outDir "computer"
$fileSource = Join-Path $root "file_intelligence"
$fileOut = Join-Path $outDir "file_intelligence"
$modelsSource = Join-Path $root "models"
$modelsOut = Join-Path $outDir "models"
$runtimeSource = Join-Path $root "runtime"
$runtimeOut = Join-Path $outDir "runtime"
$updateSource = Join-Path $root "update"
$updateOut = Join-Path $outDir "update"
$apiSource = Join-Path $root "api"
$apiOut = Join-Path $outDir "api"
$ensureUv = Join-Path $runtimeSource "ensure_uv.ps1"
$portableDist = Join-Path $root "build\voice_backend"
$portableBuilt = $false
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# Always ship AuroraFox's own uv runtime so the installed app never requires
# a system Python. Python 3.11 itself is installed into AuroraFox's runtime
# on first voice/computer/file/API setup and then reused locally.
if (-not (Test-Path -LiteralPath $ensureUv)) { throw "runtime/ensure_uv.ps1 is missing" }
& powershell -NoProfile -ExecutionPolicy Bypass -File $ensureUv -RuntimeRoot (Join-Path $runtimeSource "windows") -SkipPythonInstall | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Failed to prepare bundled uv runtime" }

if (-not $SkipModelSetup) {
    $modelInstaller = Join-Path $modelsSource "install_models.ps1"
    if (Test-Path $modelInstaller) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $modelInstaller
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
            Write-Warning "Portable AuroraVoiceBackend build failed. Windows package will use the local managed-Python fallback: $($_.Exception.Message)"
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

# Managed runtime bootstrap. Only uv binaries are shipped; Python/cache are
# populated inside the installed AuroraFox directory on demand.
if (Test-Path $runtimeOut) { Remove-Item $runtimeOut -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $runtimeOut "windows\uv") | Out-Null
Copy-Item $ensureUv (Join-Path $runtimeOut "ensure_uv.ps1") -Force
$uvSource = Join-Path $runtimeSource "windows\uv"
if (-not (Test-Path (Join-Path $uvSource "uv.exe"))) { throw "Bundled uv.exe was not prepared" }
Get-ChildItem -LiteralPath $uvSource -File | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $runtimeOut "windows\uv\$($_.Name)") -Force
}

# Local AI bootstrap.
if (Test-Path $modelsOut) { Remove-Item $modelsOut -Recurse -Force }
New-Item -ItemType Directory -Force -Path $modelsOut | Out-Null
$modelInstaller = Join-Path $modelsSource "install_models.ps1"
if (-not (Test-Path $modelInstaller)) { throw "Model bootstrap is missing" }
Copy-Item $modelInstaller (Join-Path $modelsOut "install_models.ps1") -Force

# Voice runtime/bootstrap next to AuroraFox.exe. The lightweight portable
# backend serves the default profile; optional XTTS is installed on demand
# into the managed .venv and gets its own verified shared FFmpeg runtime.
if (Test-Path $voiceOut) { Remove-Item $voiceOut -Recurse -Force }
New-Item -ItemType Directory -Force -Path $voiceOut | Out-Null
foreach ($dir in @("python", "config", "models")) {
    $source = Join-Path $voiceSource $dir
    if (Test-Path $source) { Copy-Item $source (Join-Path $voiceOut $dir) -Recurse -Force }
}
foreach ($file in @(
    "voice_service.py",
    "requirements.txt",
    "requirements_xtts.txt",
    "install_voice.ps1",
    "prepare_ffmpeg.ps1",
    "build_backend.ps1"
)) {
    $source = Join-Path $voiceSource $file
    if (-not (Test-Path $source)) { throw "Voice bootstrap is missing: $file" }
    Copy-Item $source (Join-Path $voiceOut $file) -Force
}
if ($portableBuilt) {
    Copy-Item (Join-Path $portableDist "AuroraVoiceBackend") (Join-Path $voiceOut "AuroraVoiceBackend") -Recurse -Force
} elseif (-not $SkipVoiceSetup) {
    $venvSource = Join-Path $voiceSource ".venv"
    if (Test-Path $venvSource) { Copy-Item $venvSource (Join-Path $voiceOut ".venv") -Recurse -Force }
}

# Computer Agent bootstrap.
if (Test-Path $computerOut) { Remove-Item $computerOut -Recurse -Force }
New-Item -ItemType Directory -Force -Path $computerOut | Out-Null
foreach ($file in @("computer_service.py", "requirements.txt", "install_computer.ps1")) {
    $source = Join-Path $computerSource $file
    if (Test-Path $source) { Copy-Item $source (Join-Path $computerOut $file) -Force }
}
$computerVenv = Join-Path $computerSource ".venv"
if (Test-Path $computerVenv) { Copy-Item $computerVenv (Join-Path $computerOut ".venv") -Recurse -Force }

# Rich File Intelligence + source-project index bootstrap. Both services reuse
# the same isolated .venv and managed AuroraFox Python.
if (Test-Path $fileOut) { Remove-Item $fileOut -Recurse -Force }
New-Item -ItemType Directory -Force -Path $fileOut | Out-Null
foreach ($file in @("file_service.py", "project_index_service.py", "requirements.txt", "install_files.ps1")) {
    $source = Join-Path $fileSource $file
    if (-not (Test-Path $source)) { throw "File Intelligence bootstrap is missing: $file" }
    Copy-Item $source (Join-Path $fileOut $file) -Force
}
$fileVenv = Join-Path $fileSource ".venv"
if (Test-Path $fileVenv) { Copy-Item $fileVenv (Join-Path $fileOut ".venv") -Recurse -Force }

# External API Gateway bootstrap. Keep the source next to AuroraFox.exe so
# the managed Python service can run independently from the Godot PCK.
if (Test-Path $apiOut) { Remove-Item $apiOut -Recurse -Force }
New-Item -ItemType Directory -Force -Path $apiOut | Out-Null
Get-ChildItem -LiteralPath $apiSource -File | Where-Object {
    $_.Extension -eq '.py' -or $_.Extension -eq '.ps1' -or $_.Name -eq 'requirements.txt'
} | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $apiOut $_.Name) -Force
}

# Transactional Windows updater must be present next to the installed app.
if (Test-Path $updateOut) { Remove-Item $updateOut -Recurse -Force }
New-Item -ItemType Directory -Force -Path $updateOut | Out-Null
$windowsUpdater = Join-Path $updateSource "windows_updater.ps1"
if (-not (Test-Path $windowsUpdater)) { throw "Windows updater bootstrap is missing" }
Copy-Item $windowsUpdater (Join-Path $updateOut "windows_updater.ps1") -Force

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
        throw "Neither portable nor managed-Python Aurora Voice runtime is available"
    }
}
if (-not (Test-Path (Join-Path $voiceOut "requirements_xtts.txt"))) { throw "XTTS dependency profile was not packaged" }
if (-not (Test-Path (Join-Path $voiceOut "prepare_ffmpeg.ps1"))) { throw "XTTS shared FFmpeg bootstrap was not packaged" }

if (-not (Test-Path (Join-Path $computerOut "computer_service.py"))) { throw "Computer Agent service was not packaged" }
if (-not (Test-Path (Join-Path $computerOut "install_computer.ps1"))) { throw "Computer Agent bootstrap was not packaged" }
if (-not (Test-Path (Join-Path $fileOut "file_service.py"))) { throw "File Intelligence service was not packaged" }
if (-not (Test-Path (Join-Path $fileOut "project_index_service.py"))) { throw "Project index service was not packaged" }
if (-not (Test-Path (Join-Path $fileOut "install_files.ps1"))) { throw "File Intelligence installer was not packaged" }
if (-not (Test-Path (Join-Path $modelsOut "install_models.ps1"))) { throw "Local AI model bootstrap was not packaged" }
if (-not (Test-Path (Join-Path $runtimeOut "windows\uv\uv.exe"))) { throw "AuroraFox managed runtime bootstrap was not packaged" }
if (-not (Test-Path (Join-Path $updateOut "windows_updater.ps1"))) { throw "Transactional Windows updater was not packaged" }
if (-not (Test-Path (Join-Path $apiOut "server.py"))) { throw "AuroraFox API server was not packaged" }
if (-not (Test-Path (Join-Path $apiOut "start_api.ps1"))) { throw "AuroraFox API start script was not packaged" }
if (-not (Test-Path (Join-Path $apiOut "install_api.ps1"))) { throw "AuroraFox API installer was not packaged" }
if (-not (Test-Path (Join-Path $apiOut "requirements.txt"))) { throw "AuroraFox API requirements were not packaged" }

Write-Host "AuroraFox Windows build: $outDir\AuroraFox.exe" -ForegroundColor Green
Write-Host "Managed runtime bootstrap: $runtimeOut"
Write-Host "Local AI bootstrap: $modelsOut"
Write-Host "Voice runtime/bootstrap: $voiceOut"
Write-Host "Computer Agent bootstrap: $computerOut"
Write-Host "File Intelligence + Project Index bootstrap: $fileOut"
Write-Host "External API Gateway bootstrap: $apiOut"
Write-Host "Transactional updater: $updateOut"
Write-Host ("Portable voice backend: " + ($(if ($portableBuilt) { "YES" } else { "NO - managed-Python fallback/setup wizard" })))