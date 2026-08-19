param(
    [string]$Godot = "godot",
    [string]$Gradle = "gradle",
    [switch]$ReleaseOnly
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$pluginRoot = Join-Path $root "android_plugin"
$outDir = Join-Path $root "build/android"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (-not $env:ANDROID_HOME -and -not $env:ANDROID_SDK_ROOT) {
    throw "ANDROID_HOME or ANDROID_SDK_ROOT is not configured"
}

$nativeSetup = Join-Path $pluginRoot "setup_native.ps1"
& $nativeSetup
if ($LASTEXITCODE -ne 0) { throw "Android native source setup failed" }

Push-Location $pluginRoot
try {
    $pluginTask = if ($ReleaseOnly) { ":plugin:installGodotPluginRelease" } else { ":plugin:installGodotPlugin" }
    Write-Host "Building Android plugin task: $pluginTask"
    & $Gradle $pluginTask
    if ($LASTEXITCODE -ne 0) { throw "AuroraFoxRuntime AAR build failed" }
} finally {
    Pop-Location
}

Push-Location $root
try {
    & $Godot --headless --path $root --import
    if ($LASTEXITCODE -ne 0) { throw "Godot import failed" }

    & $Godot --headless --path $root --install-android-build-template
    if ($LASTEXITCODE -ne 0) { throw "Godot Android Gradle build template installation failed" }

    & $Godot --headless --path $root --export-release "Android" (Join-Path $outDir "AuroraFox.apk")
    if ($LASTEXITCODE -ne 0) { throw "Android export failed" }
    if (-not (Test-Path (Join-Path $outDir "AuroraFox.apk"))) { throw "Android APK was not produced" }

    Write-Host "AuroraFox Android build: $(Join-Path $outDir 'AuroraFox.apk')" -ForegroundColor Green
} finally {
    Pop-Location
}
