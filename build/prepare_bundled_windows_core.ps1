param(
    [string]$CacheDir = ""
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$coreInstaller = Join-Path $root 'core_runtime/install_core.ps1'
$coreEngineDir = Join-Path $root 'core_runtime/engine'
$modelDestination = Join-Path $coreEngineDir 'aurorafox-core.gguf'
$modelHelper = Join-Path $PSScriptRoot 'prepare_bundled_core_model.ps1'

if (-not (Test-Path -LiteralPath $coreInstaller)) { throw 'core_runtime/install_core.ps1 is missing' }
if (-not (Test-Path -LiteralPath $modelHelper)) { throw 'build/prepare_bundled_core_model.ps1 is missing' }

Write-Host 'Preparing complete bundled AuroraFox Core for Windows...' -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File $coreInstaller
if ($LASTEXITCODE -ne 0) { throw 'AuroraFox Core Engine preparation failed' }

$server = Join-Path $coreEngineDir 'llama-server.exe'
if (-not (Test-Path -LiteralPath $server)) { throw 'Bundled llama-server.exe was not prepared' }

$args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$modelHelper,'-Destination',$modelDestination)
if (-not [string]::IsNullOrWhiteSpace($CacheDir)) { $args += @('-CacheDir',$CacheDir) }
& powershell @args
if ($LASTEXITCODE -ne 0) { throw 'AuroraFox Core weight preparation failed' }

if (-not (Test-Path -LiteralPath $modelDestination)) { throw 'Bundled AuroraFox Core model is missing after preparation' }
$size = (Get-Item -LiteralPath $modelDestination).Length
if ($size -ne 1282439264) { throw "Bundled AuroraFox Core model size mismatch: $size" }
$sha = (Get-FileHash -LiteralPath $modelDestination -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sha -ne 'd2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5') { throw "Bundled AuroraFox Core SHA-256 mismatch: $sha" }

Write-Host 'AURORAFOX_WINDOWS_CORE_BUNDLE_READY' -ForegroundColor Green
Write-Host "engine=$server"
Write-Host "weights=$modelDestination"
