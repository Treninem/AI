param(
    [string]$Repository = 'Treninem/AI',
    [string]$AndroidAlias = 'aurorafox',
    [switch]$SkipGitHubSecrets
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$privateDir = Join-Path $root 'build/private'
$androidKeystore = Join-Path $privateDir 'aurorafox-android-release.jks'
$androidBase64 = Join-Path $privateDir 'AURORA_ANDROID_KEYSTORE_BASE64.txt'
$updatePrivate = Join-Path $privateDir 'aurora_update_signing_private.pem'
$updateBase64 = Join-Path $privateDir 'AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64.txt'
$updatePublic = Join-Path $root 'update/release_public.pub'
$releaseIdentity = Join-Path $root 'update/release_identity.json'
$androidPackage = 'com.aurorafox.ai'
$signedFloor = '1.4.0.0'
$legacyRepairThrough = '1.3.0.0'

function Convert-SecureToPlain([Security.SecureString]$Secure) {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Read-MatchingPassword {
    while ($true) {
        $first = Read-Host 'Create/enter the permanent Android release keystore password' -AsSecureString
        $second = Read-Host 'Repeat the Android release keystore password' -AsSecureString
        $a = Convert-SecureToPlain $first
        $b = Convert-SecureToPlain $second
        try {
            if ($a.Length -lt 12) { Write-Warning 'Use at least 12 characters.'; continue }
            if ($a -ne $b) { Write-Warning 'Passwords do not match.'; continue }
            return $a
        } finally {
            $a = $null
            $b = $null
        }
    }
}

function Find-Keytool {
    $cmd = Get-Command keytool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command keytool -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    if ($env:JAVA_HOME) {
        foreach ($leaf in @('keytool.exe', 'keytool')) {
            $candidate = Join-Path $env:JAVA_HOME "bin/$leaf"
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }
    foreach ($candidate in @(
        'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe',
        'C:\Program Files\Eclipse Adoptium\jdk-17*\bin\keytool.exe',
        'C:\Program Files\Java\jdk-17*\bin\keytool.exe'
    )) {
        $match = Get-Item $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($match) { return $match.FullName }
    }
    throw 'keytool was not found. Install JDK 17 (or Android Studio) and run this script again.'
}

function Get-Sha256Hex([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-PublicKeyFingerprint([string]$Path) {
    $pem = Get-Content -LiteralPath $Path -Raw
    $base64 = ($pem -replace '-----BEGIN PUBLIC KEY-----', '' -replace '-----END PUBLIC KEY-----', '' -replace '\s', '')
    if ([string]::IsNullOrWhiteSpace($base64)) { throw 'Pinned update public key PEM is empty' }
    return Get-Sha256Hex ([Convert]::FromBase64String($base64))
}

function Get-AndroidCertificateFingerprint([string]$Keytool, [string]$Keystore, [string]$Alias, [string]$Password) {
    $certPath = Join-Path ([IO.Path]::GetTempPath()) ("aurorafox-release-cert-{0}.der" -f [Guid]::NewGuid().ToString('N'))
    try {
        & $Keytool -exportcert -keystore $Keystore -storepass $Password -alias $Alias -file $certPath | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $certPath)) { throw 'Could not export Android release certificate from keystore' }
        return Get-Sha256Hex ([IO.File]::ReadAllBytes($certPath))
    } finally {
        Remove-Item -LiteralPath $certPath -Force -ErrorAction SilentlyContinue
    }
}

function Set-GitHubSecret([string]$Name, [string]$Value) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'gh'
    $psi.Arguments = "secret set $Name --repo $Repository"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $psi
    if (-not $process.Start()) { throw "Could not start gh for secret $Name" }
    try {
        $process.StandardInput.Write($Value)
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "gh secret set $Name failed: $stderr $stdout" }
    } finally {
        $process.Dispose()
    }
}

function Write-OrVerifyReleaseIdentity([string]$UpdateFingerprint, [string]$AndroidFingerprint) {
    if (Test-Path -LiteralPath $releaseIdentity) {
        $existing = Get-Content -LiteralPath $releaseIdentity -Raw | ConvertFrom-Json
        if ([string]$existing.update_signing_public_key_sha256 -ne $UpdateFingerprint) {
            throw 'Existing release_identity.json pins a different update signing key. Restore the original private/public key pair; do not rotate silently.'
        }
        $existingAndroid = ([string]$existing.android_signing_cert_sha256).Replace(':','').ToLowerInvariant()
        if ($existingAndroid -ne $AndroidFingerprint.ToLowerInvariant()) {
            throw 'Existing release_identity.json pins a different Android signing certificate. Restore the original Android release keystore; do not rotate silently.'
        }
        if ([string]$existing.android_package -ne $androidPackage) { throw "Existing release_identity.json pins a different Android package: $($existing.android_package)" }
        if ([string]$existing.android_alias -ne $AndroidAlias) { throw "Existing release_identity.json pins Android alias '$($existing.android_alias)', not '$AndroidAlias'" }
        if ([string]$existing.signed_update_floor -ne $signedFloor) { throw "Existing release identity signed floor is not $signedFloor" }
        if ([string]$existing.legacy_repair_required_through -ne $legacyRepairThrough) { throw "Existing release identity legacy repair boundary is not $legacyRepairThrough" }
        Write-Host 'Existing public release identity matches both permanent signing keys.' -ForegroundColor Green
        return
    }

    $identity = [ordered]@{
        schema_version = 1
        android_package = $androidPackage
        android_alias = $AndroidAlias
        android_signing_cert_sha256 = $AndroidFingerprint
        update_signing_public_key_sha256 = $UpdateFingerprint
        signed_update_floor = $signedFloor
        legacy_repair_required_through = $legacyRepairThrough
        notes = 'Permanent release identity. Private keys are owner-controlled secrets and must never be committed.'
    }
    $json = ($identity | ConvertTo-Json -Depth 4) + [Environment]::NewLine
    [IO.File]::WriteAllText($releaseIdentity, $json, (New-Object Text.UTF8Encoding($false)))
    Write-Host "Created public release identity pin: $releaseIdentity" -ForegroundColor Green
}

New-Item -ItemType Directory -Force -Path $privateDir,(Split-Path -Parent $releaseIdentity) | Out-Null

if (-not (Test-Path -LiteralPath $updatePublic)) {
    if (Test-Path -LiteralPath $updatePrivate) { throw "Private update key exists but pinned public key is missing: $updatePrivate / $updatePublic. Restore the matching public key; do not generate a new pair." }
    & (Join-Path $PSScriptRoot 'create_update_signing_key.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create AuroraFox update signing key.' }
} elseif (-not (Test-Path -LiteralPath $updatePrivate)) {
    throw "Pinned update public key already exists but its private key is not in build/private. Restore the matching private key before configuring release secrets."
}
if (-not (Test-Path -LiteralPath $updateBase64)) {
    [Convert]::ToBase64String([IO.File]::ReadAllBytes($updatePrivate)) | Set-Content -LiteralPath $updateBase64 -Encoding ASCII -NoNewline
}

$keytool = Find-Keytool
$password = Read-MatchingPassword
try {
    if (-not (Test-Path -LiteralPath $androidKeystore)) {
        & $keytool -genkeypair -v -keystore $androidKeystore -storetype JKS -storepass $password -keypass $password -alias $AndroidAlias -keyalg RSA -keysize 4096 -sigalg SHA256withRSA -validity 36500 -dname 'CN=AuroraFox Android Release, O=AuroraFox'
        if ($LASTEXITCODE -ne 0) { throw 'Android release keystore generation failed.' }
    } else {
        & $keytool -list -keystore $androidKeystore -storepass $password -alias $AndroidAlias | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Existing Android keystore/password/alias validation failed. Do not overwrite the keystore.' }
    }

    $updateFingerprint = Get-PublicKeyFingerprint $updatePublic
    $androidFingerprint = Get-AndroidCertificateFingerprint $keytool $androidKeystore $AndroidAlias $password
    Write-OrVerifyReleaseIdentity $updateFingerprint $androidFingerprint
    [Convert]::ToBase64String([IO.File]::ReadAllBytes($androidKeystore)) | Set-Content -LiteralPath $androidBase64 -Encoding ASCII -NoNewline

    Write-Host "Update public-key SHA-256: $updateFingerprint" -ForegroundColor Cyan
    Write-Host "Android signing-cert SHA-256: $androidFingerprint" -ForegroundColor Cyan

    if (-not $SkipGitHubSecrets) {
        $gh = Get-Command gh.exe -ErrorAction SilentlyContinue
        if (-not $gh) { $gh = Get-Command gh -ErrorAction SilentlyContinue }
        if (-not $gh) { throw 'GitHub CLI (gh) is not installed. Re-run with -SkipGitHubSecrets to only generate local signing material, or install/authenticate gh.' }
        & $gh.Source auth status | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not authenticated. Run: gh auth login' }
        Set-GitHubSecret 'AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64' (Get-Content -LiteralPath $updateBase64 -Raw)
        Set-GitHubSecret 'AURORA_ANDROID_KEYSTORE_BASE64' (Get-Content -LiteralPath $androidBase64 -Raw)
        Set-GitHubSecret 'AURORA_ANDROID_KEYSTORE_USER' $AndroidAlias
        Set-GitHubSecret 'AURORA_ANDROID_KEYSTORE_PASSWORD' $password
        Write-Host "GitHub Actions signing secrets configured for $Repository." -ForegroundColor Green
    }
} finally {
    $password = $null
}

Write-Host ''
Write-Host 'AuroraFox permanent release signing bootstrap is ready.' -ForegroundColor Green
Write-Host 'Commit ONLY public identity files:' -ForegroundColor Cyan
Write-Host "  $updatePublic"
Write-Host "  $releaseIdentity"
Write-Host "Keep this Android keystore private and backed up: $androidKeystore" -ForegroundColor Yellow
Write-Host "Keep this updater private key private and backed up: $updatePrivate" -ForegroundColor Yellow
Write-Host 'Do not regenerate either identity for normal updates.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
Write-Host '  git add update/release_public.pub update/release_identity.json'
Write-Host '  git commit -m "release: initialize AuroraFox permanent signing identity"'
Write-Host '  git push'
Write-Host 'Then run build/bridge_release_readiness.ps1 and the AuroraFox Release workflow (or push the matching v<version> tag).'
