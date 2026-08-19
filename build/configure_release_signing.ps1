param(
    [string]$Repository = "Treninem/AI",
    [string]$AndroidAlias = "aurorafox",
    [string]$AndroidPassword = ""
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$privateDir = Join-Path $root 'build\private'
$updatePrivate = Join-Path $privateDir 'aurora_update_signing_private.pem'
$updatePublic = Join-Path $root 'update\release_public.pub'
$androidKeystore = Join-Path $privateDir 'aurorafox-android-release.keystore'
$androidBackup = Join-Path $privateDir 'android_signing_backup.txt'

New-Item -ItemType Directory -Force -Path $privateDir | Out-Null

function New-RandomAlphaNumeric([int]$Length = 36) {
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $bytes = New-Object byte[] $Length
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $chars = for ($i = 0; $i -lt $Length; $i++) {
        $alphabet[[int]$bytes[$i] % $alphabet.Length]
    }
    return -join $chars
}

function Require-Command([string]$Name, [string]$Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is required. $Hint"
    }
}

function Set-GitHubSecret([string]$Name, [string]$Value) {
    if ([string]::IsNullOrEmpty($Value)) { throw "Refusing to set empty GitHub secret: $Name" }
    & gh secret set $Name --repo $Repository --body $Value
    if ($LASTEXITCODE -ne 0) { throw "Failed to set GitHub secret $Name" }
}

Require-Command 'gh' 'Install GitHub CLI and run: gh auth login'
Require-Command 'keytool' 'Install/use JDK 17 so keytool is available.'

& gh auth status | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not authenticated. Run: gh auth login' }
& gh repo view $Repository --json nameWithOwner | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Cannot access GitHub repository $Repository with current gh account" }

# Update manifest signing identity.
if (-not (Test-Path -LiteralPath $updatePrivate) -or -not (Test-Path -LiteralPath $updatePublic)) {
    if ((Test-Path -LiteralPath $updatePrivate) -xor (Test-Path -LiteralPath $updatePublic)) {
        throw 'Only one half of the update signing key exists. Restore the matching backup instead of rotating trust accidentally.'
    }
    Write-Host 'Creating pinned AuroraFox update signing key...' -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'create_update_signing_key.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Update signing key creation failed' }
}

$updatePrivateB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($updatePrivate))
Set-GitHubSecret 'AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64' $updatePrivateB64

# Android signing identity. Every APK update must keep this same keystore.
if (-not (Test-Path -LiteralPath $androidKeystore)) {
    if ([string]::IsNullOrWhiteSpace($AndroidPassword)) {
        $AndroidPassword = New-RandomAlphaNumeric 40
    }
    Write-Host 'Creating stable AuroraFox Android release keystore...' -ForegroundColor Cyan
    & keytool -genkeypair -v `
        -keystore $androidKeystore `
        -alias $AndroidAlias `
        -keyalg RSA `
        -keysize 4096 `
        -validity 10000 `
        -storepass $AndroidPassword `
        -keypass $AndroidPassword `
        -dname 'CN=AuroraFox, OU=AuroraFox, O=AuroraFox, L=Local, ST=Local, C=NL'
    if ($LASTEXITCODE -ne 0) { throw 'Android keystore creation failed' }
    [IO.File]::WriteAllText(
        $androidBackup,
        "Repository=$Repository`r`nAlias=$AndroidAlias`r`nPassword=$AndroidPassword`r`nKeystore=$androidKeystore`r`n",
        [Text.Encoding]::UTF8
    )
} elseif ([string]::IsNullOrWhiteSpace($AndroidPassword)) {
    if (-not (Test-Path -LiteralPath $androidBackup)) {
        throw "Android keystore exists but its local backup file is missing. Re-run with -AndroidPassword '<existing password>'; do NOT create a new keystore."
    }
    $backupText = Get-Content -LiteralPath $androidBackup -Raw
    if ($backupText -notmatch '(?m)^Password=(.+)$') { throw 'Cannot read Android password from local signing backup' }
    $AndroidPassword = $Matches[1].Trim()
    if ($backupText -match '(?m)^Alias=(.+)$') { $AndroidAlias = $Matches[1].Trim() }
}

# Verify the key before uploading secrets.
& keytool -list -keystore $androidKeystore -alias $AndroidAlias -storepass $AndroidPassword | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Android keystore password/alias verification failed' }

$keystoreB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($androidKeystore))
Set-GitHubSecret 'AURORA_ANDROID_KEYSTORE_BASE64' $keystoreB64
Set-GitHubSecret 'AURORA_ANDROID_KEYSTORE_USER' $AndroidAlias
Set-GitHubSecret 'AURORA_ANDROID_KEYSTORE_PASSWORD' $AndroidPassword

Write-Host ''
Write-Host 'AuroraFox release signing is configured in GitHub.' -ForegroundColor Green
Write-Host "Pinned public update key: $updatePublic" -ForegroundColor Cyan
Write-Host "Private update key backup: $updatePrivate" -ForegroundColor Yellow
Write-Host "Android keystore backup: $androidKeystore" -ForegroundColor Yellow
Write-Host "Android signing notes: $androidBackup" -ForegroundColor Yellow
Write-Host ''
Write-Host 'IMPORTANT: back up build/private outside the repository. Never commit it.' -ForegroundColor Yellow
Write-Host 'Commit ONLY update/release_public.pub. After that, tagged releases can produce mutually updateable signed APKs and signed update manifests.' -ForegroundColor Cyan
