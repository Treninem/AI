param(
    [string]$Godot = "godot",
    [string]$Gradle = "gradle",
    [switch]$ReleaseOnly,
    [switch]$AllowUnsignedRelease
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$pluginRoot = Join-Path $root "android_plugin"
$outDir = Join-Path $root "build/android"
$exportPresetPath = Join-Path $root "export_presets.cfg"
$versionTest = Join-Path $root "tests/version_sync_test.ps1"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (-not $env:ANDROID_HOME -and -not $env:ANDROID_SDK_ROOT) {
    throw "ANDROID_HOME or ANDROID_SDK_ROOT is not configured"
}
if (-not (Test-Path -LiteralPath $exportPresetPath)) {
    throw "export_presets.cfg is missing"
}

if (Test-Path -LiteralPath $versionTest) {
    & $versionTest
}

$nativeSetup = Join-Path $pluginRoot "setup_native.ps1"
& $nativeSetup
if ($LASTEXITCODE -ne 0) { throw "Android native source setup failed" }

Push-Location $pluginRoot
try {
    $pluginTask = if ($ReleaseOnly) { ":plugin:installGodotPluginRelease" } else { ":plugin:installGodotPlugin" }
    $gradleArgs = @(
        $pluginTask,
        "--build-cache",
        "--parallel",
        "--no-daemon",
        "--stacktrace"
    )
    Write-Host "Building Android plugin task: $pluginTask (Gradle build cache + parallel workers enabled)"
    & $Gradle @gradleArgs
    if ($LASTEXITCODE -ne 0) { throw "AuroraFoxRuntime AAR build failed" }
} finally {
    Pop-Location
}

$originalPreset = $null
$presetTemporarilyChanged = $false
try {
    if ($AllowUnsignedRelease) {
        $originalPreset = Get-Content -LiteralPath $exportPresetPath -Raw
        if ($originalPreset -notmatch '(?m)^package/signed=true\s*$') {
            throw "Android export preset does not contain package/signed=true"
        }
        $unsignedPreset = [regex]::Replace(
            $originalPreset,
            '(?m)^package/signed=true\s*$',
            'package/signed=false',
            1
        )
        [IO.File]::WriteAllText(
            $exportPresetPath,
            $unsignedPreset,
            (New-Object Text.UTF8Encoding($false))
        )
        $presetTemporarilyChanged = $true
        Write-Host "Android CI export will be unsigned; signing is performed after export." -ForegroundColor Yellow
    }

    Push-Location $root
    try {
        & $Godot --headless --path $root --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import failed" }

        $apkPath = Join-Path $outDir "AuroraFox.apk"
        if (Test-Path -LiteralPath $apkPath) {
            Remove-Item -LiteralPath $apkPath -Force
        }
        # This flag is an export modifier, not a standalone one-shot command.
        # Invoking it alone starts the project after installing the template and
        # leaves CI running indefinitely. Keep installation and export in the
        # same Godot process so the editor exits when the APK is produced.
        & $Godot --headless --path $root --install-android-build-template --export-release "Android" $apkPath
        if ($LASTEXITCODE -ne 0) { throw "Android export failed" }
        if (-not (Test-Path -LiteralPath $apkPath)) { throw "Android APK was not produced" }

        $apk = Get-Item -LiteralPath $apkPath
        if ($apk.Length -lt 1048576) {
            throw "Android APK is unexpectedly small ($($apk.Length) bytes)"
        }

        Write-Host "AuroraFox Android build: $apkPath ($($apk.Length) bytes)" -ForegroundColor Green
    } finally {
        Pop-Location
    }
} finally {
    if ($presetTemporarilyChanged -and $null -ne $originalPreset) {
        [IO.File]::WriteAllText(
            $exportPresetPath,
            $originalPreset,
            (New-Object Text.UTF8Encoding($false))
        )
        Write-Host "Restored signed Android export preset." -ForegroundColor DarkGray
    }
}
