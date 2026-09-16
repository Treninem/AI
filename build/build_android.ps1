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
$releaseIdentityPath = Join-Path $root "update/release_identity.json"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Get-Sha256Hex([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Find-Keytool {
    foreach ($name in @('keytool.exe', 'keytool')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    if ($env:JAVA_HOME) {
        foreach ($leaf in @('keytool.exe', 'keytool')) {
            $candidate = Join-Path $env:JAVA_HOME "bin/$leaf"
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }
    throw 'keytool was not found; JDK 17 is required for pinned Android release identity verification'
}

function Find-ApkSigner {
    foreach ($name in @('apksigner.bat', 'apksigner')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
    if ([string]::IsNullOrWhiteSpace($sdk)) { throw 'Android SDK path is unavailable while locating apksigner' }
    $buildTools = Join-Path $sdk 'build-tools'
    if (-not (Test-Path -LiteralPath $buildTools)) { throw "Android build-tools directory is missing: $buildTools" }
    $candidate = Get-ChildItem -LiteralPath $buildTools -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @('apksigner', 'apksigner.bat') } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $candidate) { throw 'apksigner was not found in Android build-tools' }
    return $candidate.FullName
}

function Get-KeystoreCertificateFingerprint([string]$Keytool, [string]$Keystore, [string]$Alias, [string]$Password) {
    $certPath = Join-Path ([IO.Path]::GetTempPath()) ("aurorafox-build-cert-{0}.der" -f [Guid]::NewGuid().ToString('N'))
    try {
        & $Keytool -exportcert -keystore $Keystore -storepass $Password -alias $Alias -file $certPath | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $certPath)) {
            throw 'Could not export certificate from configured Android release keystore'
        }
        return Get-Sha256Hex ([IO.File]::ReadAllBytes($certPath))
    } finally {
        Remove-Item -LiteralPath $certPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-PinnedReleaseIdentity {
    if (-not (Test-Path -LiteralPath $releaseIdentityPath)) {
        throw 'update/release_identity.json is missing. Run build/setup_release_signing.ps1 before a production Android release.'
    }
    $identity = Get-Content -LiteralPath $releaseIdentityPath -Raw | ConvertFrom-Json
    if ([int]$identity.schema_version -ne 1) { throw 'Unsupported release identity schema' }
    if ([string]$identity.android_package -ne 'com.aurorafox.ai') { throw 'Pinned Android package identity is not com.aurorafox.ai' }
    $fingerprint = ([string]$identity.android_signing_cert_sha256).ToLowerInvariant().Replace(':', '')
    if ($fingerprint -notmatch '^[0-9a-f]{64}$') { throw 'Pinned Android signing certificate SHA-256 is invalid' }
    return @{ data = $identity; fingerprint = $fingerprint }
}

if (-not $env:ANDROID_HOME -and -not $env:ANDROID_SDK_ROOT) {
    throw "ANDROID_HOME or ANDROID_SDK_ROOT is not configured"
}
if (-not (Test-Path -LiteralPath $exportPresetPath)) {
    throw "export_presets.cfg is missing"
}

if (Test-Path -LiteralPath $versionTest) {
    & $versionTest
}

$enforcePinnedReleaseIdentity = $false
$pinnedAndroidFingerprint = ''
$releaseKeystorePath = [string]$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH
$releaseKeystoreUser = [string]$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER
$releaseKeystorePassword = [string]$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
$releaseSigningConfigured = -not [string]::IsNullOrWhiteSpace($releaseKeystorePath) -or
    -not [string]::IsNullOrWhiteSpace($releaseKeystoreUser) -or
    -not [string]::IsNullOrWhiteSpace($releaseKeystorePassword)

if ($releaseSigningConfigured -and -not $AllowUnsignedRelease) {
    if ([string]::IsNullOrWhiteSpace($releaseKeystorePath) -or
        [string]::IsNullOrWhiteSpace($releaseKeystoreUser) -or
        [string]::IsNullOrWhiteSpace($releaseKeystorePassword)) {
        throw 'Production Android signing environment is incomplete; path, alias and password must all be configured'
    }
    if (-not (Test-Path -LiteralPath $releaseKeystorePath)) {
        throw "Configured Android release keystore does not exist: $releaseKeystorePath"
    }

    $pinned = Get-PinnedReleaseIdentity
    if ([string]$pinned.data.android_alias -ne $releaseKeystoreUser) {
        throw "Configured Android release alias '$releaseKeystoreUser' does not match pinned alias '$($pinned.data.android_alias)'"
    }
    $keytool = Find-Keytool
    $configuredFingerprint = Get-KeystoreCertificateFingerprint $keytool $releaseKeystorePath $releaseKeystoreUser $releaseKeystorePassword
    if ($configuredFingerprint -ne $pinned.fingerprint) {
        throw "Android release keystore certificate mismatch. Expected $($pinned.fingerprint), got $configuredFingerprint. Restore the permanent AuroraFox release keystore; do not rotate it silently."
    }
    $pinnedAndroidFingerprint = $pinned.fingerprint
    $enforcePinnedReleaseIdentity = $true
    Write-Host "Pinned Android release keystore identity verified: $pinnedAndroidFingerprint" -ForegroundColor Green
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

        if ($enforcePinnedReleaseIdentity) {
            $apksigner = Find-ApkSigner
            $verifyOutput = (& $apksigner verify --verbose --print-certs $apkPath 2>&1 | Out-String)
            if ($LASTEXITCODE -ne 0) { throw "apksigner rejected production APK: $verifyOutput" }
            $match = [regex]::Match($verifyOutput, 'certificate SHA-256 digest:\s*([0-9A-Fa-f:]+)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if (-not $match.Success) { throw "Could not read APK signing certificate SHA-256 from apksigner output: $verifyOutput" }
            $apkFingerprint = $match.Groups[1].Value.ToLowerInvariant().Replace(':', '')
            if ($apkFingerprint -ne $pinnedAndroidFingerprint) {
                throw "Built APK signing certificate mismatch. Expected $pinnedAndroidFingerprint, got $apkFingerprint. Production artifact rejected."
            }
            $identityReport = @(
                'AURORAFOX_ANDROID_RELEASE_IDENTITY_OK',
                "package=com.aurorafox.ai",
                "certificate_sha256=$apkFingerprint"
            ) -join [Environment]::NewLine
            [IO.File]::WriteAllText((Join-Path $outDir 'release-identity-verification.txt'), $identityReport + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
            Write-Host "Built APK signing identity verified: $apkFingerprint" -ForegroundColor Green
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
