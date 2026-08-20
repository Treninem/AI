param(
    [string]$Godot = "godot",
    [string]$Gradle = "gradle",
    [switch]$ReleaseOnly,
    [switch]$AllowUnsignedRelease,
    [ValidateSet("all", "native", "import", "template", "export")]
    [string]$Stage = "all"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$pluginRoot = Join-Path $root "android_plugin"
$outDir = Join-Path $root "build/android"
$exportPresetPath = Join-Path $root "export_presets.cfg"
$versionTest = Join-Path $root "tests/version_sync_test.ps1"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (-not (Test-Path -LiteralPath $exportPresetPath)) {
    throw "export_presets.cfg is missing"
}

if (Test-Path -LiteralPath $versionTest) {
    & $versionTest
}

function Invoke-NativeBuild {
    if (-not $env:ANDROID_HOME -and -not $env:ANDROID_SDK_ROOT) {
        throw "ANDROID_HOME or ANDROID_SDK_ROOT is not configured"
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
}

function Invoke-GodotImport {
    Push-Location $root
    try {
        Write-Host "Importing AuroraFox resources with Godot..."
        & $Godot --headless --path $root --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import failed" }
    } finally {
        Pop-Location
    }
}

function Invoke-AndroidTemplateInstall {
    Push-Location $root
    try {
        Write-Host "Installing Godot Android Gradle build template..."
        & $Godot --headless --path $root --install-android-build-template
        if ($LASTEXITCODE -ne 0) { throw "Godot Android Gradle build template installation failed" }
    } finally {
        Pop-Location
    }
}

function Invoke-ApkExport {
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
            $apkPath = Join-Path $outDir "AuroraFox.apk"
            if (Test-Path -LiteralPath $apkPath) {
                Remove-Item -LiteralPath $apkPath -Force
            }
            Write-Host "Exporting AuroraFox Android release APK..."
            & $Godot --headless --path $root --export-release "Android" $apkPath
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
}

switch ($Stage) {
    "native" {
        Invoke-NativeBuild
    }
    "import" {
        Invoke-GodotImport
    }
    "template" {
        Invoke-AndroidTemplateInstall
    }
    "export" {
        Invoke-ApkExport
    }
    "all" {
        Invoke-NativeBuild
        Invoke-GodotImport
        Invoke-AndroidTemplateInstall
        Invoke-ApkExport
    }
    default {
        throw "Unknown Android build stage: $Stage"
    }
}
