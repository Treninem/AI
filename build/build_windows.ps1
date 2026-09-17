param(
    [string]$Godot = "godot",
    [switch]$SkipModelSetup,
    [switch]$SkipVoiceSetup,
    [string]$CoreModelCacheDir = ""
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
$coreSource = Join-Path $root "core_runtime"
$coreOut = Join-Path $outDir "core_runtime"
$runtimeSource = Join-Path $root "runtime"
$runtimeOut = Join-Path $outDir "runtime"
$updateSource = Join-Path $root "update"
$updateOut = Join-Path $outDir "update"
$apiSource = Join-Path $root "api"
$apiOut = Join-Path $outDir "api"
$ensureUv = Join-Path $runtimeSource "ensure_uv.ps1"
$fileInstaller = Join-Path $fileSource "install_files.ps1"
$fileOcrPrepare = Join-Path $fileSource "prepare_windows_ocr.ps1"
$portableDist = Join-Path $root "build\voice_backend"
$portableBuilt = $false
$coreBundleHelper = Join-Path $PSScriptRoot "prepare_bundled_windows_core.ps1"
$coreEngineSource = Join-Path $coreSource "engine"
$coreServerSource = Join-Path $coreEngineSource "llama-server.exe"
$coreModelSource = Join-Path $coreEngineSource "aurorafox-core.gguf"
$coreModelBytes = 1282439264
$coreModelSha = 'd2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# AuroraFox owns its auxiliary runtime and its inference stack. A normal user
# must never install Ollama, choose GGUF files, or install a separate Core
# Engine. Every Windows build therefore prepares a complete verified Core.
if (-not (Test-Path -LiteralPath $ensureUv)) { throw "runtime/ensure_uv.ps1 is missing" }
& powershell -NoProfile -ExecutionPolicy Bypass -File $ensureUv -RuntimeRoot (Join-Path $runtimeSource "windows") -SkipPythonInstall | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Failed to prepare bundled uv runtime" }

if (-not (Test-Path -LiteralPath $coreBundleHelper)) { throw "build/prepare_bundled_windows_core.ps1 is missing" }
$coreArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$coreBundleHelper)
if (-not [string]::IsNullOrWhiteSpace($CoreModelCacheDir)) { $coreArgs += @('-CacheDir',$CoreModelCacheDir) }
& powershell @coreArgs
if ($LASTEXITCODE -ne 0) { throw "Failed to prepare complete bundled AuroraFox Core" }
if (-not (Test-Path -LiteralPath $coreServerSource)) { throw "Bundled AuroraFox Core Engine was not prepared" }
if (-not (Test-Path -LiteralPath $coreModelSource)) { throw "Bundled AuroraFox Core weights were not prepared" }
if ((Get-Item -LiteralPath $coreModelSource).Length -ne $coreModelBytes) { throw "Bundled AuroraFox Core weights have the wrong size" }
$coreActualSha = (Get-FileHash -LiteralPath $coreModelSource -Algorithm SHA256).Hash.ToLowerInvariant()
if ($coreActualSha -ne $coreModelSha) { throw "Bundled AuroraFox Core SHA-256 mismatch: $coreActualSha" }
Write-Host "Complete AuroraFox Core prepared for Windows: $coreActualSha" -ForegroundColor Green

# File Intelligence is a release component, not a post-install network
# dependency. Build the relocatable Python bundle and the verified bilingual
# Tesseract runtime now, so local OCR works immediately after installation.
if (-not (Test-Path -LiteralPath $fileInstaller)) { throw "File Intelligence installer is missing" }
if (-not (Test-Path -LiteralPath $fileOcrPrepare)) { throw "file_intelligence/prepare_windows_ocr.ps1 is missing" }
Write-Host "Preparing portable File Intelligence + local rus+eng OCR runtime..." -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File $fileInstaller -PreparePortable
if ($LASTEXITCODE -ne 0) { throw "Failed to prepare portable File Intelligence/OCR runtime" }

# SkipModelSetup remains only for compatibility with older CI invocations. It
# no longer disables Core packaging because the user-facing model setup flow
# has been removed from normal operation.
if ($SkipModelSetup) {
    Write-Host "SkipModelSetup is deprecated; bundled AuroraFox Core remains mandatory." -ForegroundColor DarkGray
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

# Managed runtime bootstrap for voice/file/computer/API services.
if (Test-Path $runtimeOut) { Remove-Item $runtimeOut -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $runtimeOut "windows\uv") | Out-Null
Copy-Item $ensureUv (Join-Path $runtimeOut "ensure_uv.ps1") -Force
$uvSource = Join-Path $runtimeSource "windows\uv"
if (-not (Test-Path (Join-Path $uvSource "uv.exe"))) { throw "Bundled uv.exe was not prepared" }
Get-ChildItem -LiteralPath $uvSource -File | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $runtimeOut "windows\uv\$($_.Name)") -Force
}

# Complete AuroraFox Core: engine + internal weights. These are mandatory
# application assets, not an optional user setup component.
if (Test-Path $coreOut) { Remove-Item $coreOut -Recurse -Force }
New-Item -ItemType Directory -Force -Path $coreOut | Out-Null
$coreInstaller = Join-Path $coreSource "install_core.ps1"
if (-not (Test-Path $coreInstaller)) { throw "AuroraFox Core installer/recovery helper is missing" }
Copy-Item $coreInstaller (Join-Path $coreOut "install_core.ps1") -Force
Copy-Item $coreEngineSource (Join-Path $coreOut "engine") -Recurse -Force
$coreMeta = Join-Path $coreSource "engine.json"
if (Test-Path $coreMeta) { Copy-Item $coreMeta (Join-Path $coreOut "engine.json") -Force }

$packagedServer = Join-Path $coreOut "engine\llama-server.exe"
$packagedModel = Join-Path $coreOut "engine\aurorafox-core.gguf"
if (-not (Test-Path -LiteralPath $packagedServer)) { throw "Packaged AuroraFox Core Engine is missing" }
if (-not (Test-Path -LiteralPath $packagedModel)) { throw "Packaged AuroraFox Core weights are missing" }
if ((Get-Item -LiteralPath $packagedModel).Length -ne $coreModelBytes) { throw "Packaged AuroraFox Core weights have the wrong size" }
$packagedSha = (Get-FileHash -LiteralPath $packagedModel -Algorithm SHA256).Hash.ToLowerInvariant()
if ($packagedSha -ne $coreModelSha) { throw "Packaged AuroraFox Core integrity verification failed: $packagedSha" }

# Developer compatibility tools stay packaged, but normal operation never
# requires a user-selected model or Ollama.
if (Test-Path $modelsOut) { Remove-Item $modelsOut -Recurse -Force }
New-Item -ItemType Directory -Force -Path $modelsOut | Out-Null
$modelInstaller = Join-Path $modelsSource "install_models.ps1"
if (-not (Test-Path $modelInstaller)) { throw "Model compatibility bootstrap is missing" }
Copy-Item $modelInstaller (Join-Path $modelsOut "install_models.ps1") -Force

# Voice runtime/bootstrap next to AuroraFox.exe.
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

# Rich File Intelligence + source-project index bootstrap. The release receives
# the same verified portable Python and OCR runtime proven by the candidate CI.
if (Test-Path $fileOut) { Remove-Item $fileOut -Recurse -Force }
New-Item -ItemType Directory -Force -Path $fileOut | Out-Null
foreach ($file in @("file_service.py", "project_index_service.py", "local_ocr.py", "requirements.txt", "install_files.ps1", "prepare_windows_ocr.ps1")) {
    $source = Join-Path $fileSource $file
    if (-not (Test-Path $source)) { throw "File Intelligence bootstrap is missing: $file" }
    Copy-Item $source (Join-Path $fileOut $file) -Force
}
foreach ($dir in @("python", "vendor", "ocr_runtime")) {
    $source = Join-Path $fileSource $dir
    if (-not (Test-Path -LiteralPath $source)) { throw "Portable File Intelligence component is missing: $dir" }
    Copy-Item $source (Join-Path $fileOut $dir) -Recurse -Force
}
$fileVenv = Join-Path $fileSource ".venv"
if (Test-Path $fileVenv) { Copy-Item $fileVenv (Join-Path $fileOut ".venv") -Recurse -Force }

# External API Gateway bootstrap.
if (Test-Path $apiOut) { Remove-Item $apiOut -Recurse -Force }
New-Item -ItemType Directory -Force -Path $apiOut | Out-Null
Get-ChildItem -LiteralPath $apiSource -File | Where-Object {
    $_.Extension -eq '.py' -or $_.Extension -eq '.ps1' -or $_.Name -eq 'requirements.txt'
} | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $apiOut $_.Name) -Force
}

# Transactional Windows updater + permanent public trust root. The public key
# is also exported inside the Godot PCK, but the sidecar copy is intentionally
# packaged beside windows_updater.ps1 for repair validation, diagnostics and
# future updater helpers. Private signing material is never packaged.
if (Test-Path $updateOut) { Remove-Item $updateOut -Recurse -Force }
New-Item -ItemType Directory -Force -Path $updateOut | Out-Null
$windowsUpdater = Join-Path $updateSource "windows_updater.ps1"
$releasePublicKey = Join-Path $updateSource "release_public.pub"
if (-not (Test-Path $windowsUpdater)) { throw "Windows updater bootstrap is missing" }
if (-not (Test-Path $releasePublicKey)) { throw "Pinned update public trust root is missing" }
Copy-Item $windowsUpdater (Join-Path $updateOut "windows_updater.ps1") -Force
Copy-Item $releasePublicKey (Join-Path $updateOut "release_public.pub") -Force

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
if (-not (Test-Path (Join-Path $fileOut "local_ocr.py"))) { throw "Local OCR service was not packaged" }
if (-not (Test-Path (Join-Path $fileOut "install_files.ps1"))) { throw "File Intelligence installer was not packaged" }
if (-not (Test-Path (Join-Path $fileOut "prepare_windows_ocr.ps1"))) { throw "Local OCR recovery helper was not packaged" }
if (-not (Test-Path (Join-Path $fileOut "python\python.exe"))) { throw "Portable File Intelligence Python was not packaged" }
if (-not (Test-Path (Join-Path $fileOut "ocr_runtime\tesseract.exe"))) { throw "Local Tesseract runtime was not packaged" }
if (-not (Test-Path (Join-Path $fileOut "ocr_runtime\tessdata\eng.traineddata"))) { throw "English OCR data was not packaged" }
if (-not (Test-Path (Join-Path $fileOut "ocr_runtime\tessdata\rus.traineddata"))) { throw "Russian OCR data was not packaged" }
if (-not (Test-Path (Join-Path $modelsOut "install_models.ps1"))) { throw "Local AI compatibility bootstrap is missing" }
if (-not (Test-Path (Join-Path $coreOut "install_core.ps1"))) { throw "AuroraFox Core recovery helper was not packaged" }
if (-not (Test-Path (Join-Path $coreOut "engine\llama-server.exe"))) { throw "AuroraFox built-in Core Engine was not packaged" }
if (-not (Test-Path (Join-Path $coreOut "engine\aurorafox-core.gguf"))) { throw "AuroraFox built-in Core weights were not packaged" }
if (-not (Test-Path (Join-Path $runtimeOut "windows\uv\uv.exe"))) { throw "AuroraFox managed runtime bootstrap was not packaged" }
if (-not (Test-Path (Join-Path $updateOut "windows_updater.ps1"))) { throw "Transactional Windows updater was not packaged" }
if (-not (Test-Path (Join-Path $updateOut "release_public.pub"))) { throw "Pinned update public trust root was not packaged" }
if (-not (Test-Path (Join-Path $apiOut "server.py"))) { throw "AuroraFox API server was not packaged" }
if (-not (Test-Path (Join-Path $apiOut "local_core_client.py"))) { throw "AuroraFox local Core API client was not packaged" }
if (-not (Test-Path (Join-Path $apiOut "runtime_bridge.py"))) { throw "AuroraFox Agent/Core runtime bridge was not packaged" }
if (-not (Test-Path (Join-Path $apiOut "ollama_client.py"))) { throw "AuroraFox optional Ollama compatibility adapter was not packaged" }
if (-not (Test-Path (Join-Path $apiOut "start_api.ps1"))) { throw "AuroraFox API start script was not packaged" }
if (-not (Test-Path (Join-Path $apiOut "install_api.ps1"))) { throw "AuroraFox API installer was not packaged" }
if (-not (Test-Path (Join-Path $apiOut "requirements.txt"))) { throw "AuroraFox API requirements were not packaged" }

Write-Host "AuroraFox Windows build: $outDir\AuroraFox.exe" -ForegroundColor Green
Write-Host "AuroraFox built-in Core Engine: $packagedServer"
Write-Host "AuroraFox built-in Core weights: $packagedModel"
Write-Host "AuroraFox built-in Core SHA-256: $packagedSha"
Write-Host "Managed runtime bootstrap: $runtimeOut"
Write-Host "Voice runtime/bootstrap: $voiceOut"
Write-Host "Computer Agent bootstrap: $computerOut"
Write-Host "File Intelligence + local OCR runtime: $fileOut"
Write-Host "External API Gateway bootstrap: $apiOut"
Write-Host "Transactional updater: $updateOut"
Write-Host ("Portable voice backend: " + ($(if ($portableBuilt) { "YES" } else { "NO - managed-Python fallback/setup wizard" })))