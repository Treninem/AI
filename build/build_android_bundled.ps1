param(
    [string]$Godot = "godot",
    [string]$Gradle = "gradle",
    [switch]$ReleaseOnly,
    [switch]$AllowUnsignedRelease,
    [string]$CoreModelCacheDir = ""
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$modelTarget = Join-Path $root 'models/aurorafox-core.gguf'
$modelHelper = Join-Path $PSScriptRoot 'prepare_bundled_core_model.ps1'
$inner = Join-Path $PSScriptRoot 'build_android.ps1'

if (-not (Test-Path -LiteralPath $modelHelper)) { throw 'Bundled AuroraFox Core preparation helper is missing' }
if (-not (Test-Path -LiteralPath $inner)) { throw 'Android build helper is missing' }

try {
    $prepareArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$modelHelper,'-Destination',$modelTarget)
    if (-not [string]::IsNullOrWhiteSpace($CoreModelCacheDir)) {
        $prepareArgs += @('-CacheDir',$CoreModelCacheDir)
    }
    & powershell @prepareArgs
    if ($LASTEXITCODE -ne 0) { throw 'Bundled AuroraFox Core preparation failed' }

    if (-not (Test-Path -LiteralPath $modelTarget)) { throw 'Bundled AuroraFox Core asset was not staged for Android export' }
    $model = Get-Item -LiteralPath $modelTarget
    if ($model.Length -ne 1282439264) { throw "Bundled Android Core asset size mismatch: $($model.Length)" }
    $sha = (Get-FileHash -LiteralPath $modelTarget -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($sha -ne 'd2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5') {
        throw "Bundled Android Core asset SHA-256 mismatch: $sha"
    }

    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$inner,'-Godot',$Godot,'-Gradle',$Gradle)
    if ($ReleaseOnly) { $args += '-ReleaseOnly' }
    if ($AllowUnsignedRelease) { $args += '-AllowUnsignedRelease' }
    & powershell @args
    if ($LASTEXITCODE -ne 0) { throw 'Android build with bundled AuroraFox Core failed' }

    $apk = Join-Path $root 'build/android/AuroraFox.apk'
    if (-not (Test-Path -LiteralPath $apk)) { throw 'Android APK missing after bundled Core build' }
    Write-Host 'AURORAFOX_ANDROID_BUNDLED_CORE_BUILD_OK' -ForegroundColor Green
    Write-Host "core_sha256=$sha"
} finally {
    # The 1.2+ GiB model is a build input/cache and must never be committed.
    Remove-Item -LiteralPath $modelTarget -Force -ErrorAction SilentlyContinue
}
