param(
    [string]$Godot = "godot",
    [switch]$SkipModelSetup
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outDir = Join-Path $root "build\windows"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (-not $SkipModelSetup) {
    $models = Join-Path $root "models\install_models.ps1"
    if (Test-Path $models) {
        & powershell -ExecutionPolicy Bypass -File $models
        if ($LASTEXITCODE -ne 0) { throw "Local model setup failed" }
    }
}

Push-Location $root
try {
    & $Godot --headless --path $root --import
    if ($LASTEXITCODE -ne 0) { throw "Godot import failed" }

    & $Godot --headless --path $root --export-release "Windows Desktop" (Join-Path $outDir "AuroraFox.exe")
    if ($LASTEXITCODE -ne 0) { throw "Windows export failed" }

    Write-Host "AuroraFox Windows build: $outDir\AuroraFox.exe"
} finally {
    Pop-Location
}
