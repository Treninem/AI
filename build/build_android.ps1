param(
    [string]$Godot = "godot",
    [string]$Gradle = "gradle"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$pluginRoot = Join-Path $root "android_plugin"
$outDir = Join-Path $root "build\android"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (-not $env:ANDROID_HOME -and -not $env:ANDROID_SDK_ROOT) {
    throw "ANDROID_HOME or ANDROID_SDK_ROOT is not configured"
}

$nativeSetup = Join-Path $pluginRoot "setup_native.ps1"
& powershell -ExecutionPolicy Bypass -File $nativeSetup
if ($LASTEXITCODE -ne 0) { throw "Android native source setup failed" }

Push-Location $pluginRoot
try {
    & $Gradle :plugin:installGodotPlugin
    if ($LASTEXITCODE -ne 0) { throw "AuroraFoxRuntime AAR build failed" }
} finally {
    Pop-Location
}

Push-Location $root
try {
    & $Godot --headless --path $root --install-android-build-template --export-release "Android" (Join-Path $outDir "AuroraFox.apk")
    if ($LASTEXITCODE -ne 0) { throw "Android export failed" }
    Write-Host "AuroraFox Android build: $outDir\AuroraFox.apk"
} finally {
    Pop-Location
}
