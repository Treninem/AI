param(
    [string]$Repository = "Treninem/AI",
    [switch]$SkipGitHubSecrets
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Pass([string]$Message) { Write-Host "[OK] $Message" -ForegroundColor Green }
function Warn([string]$Message) { $warnings.Add($Message); Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Fail([string]$Message) { $failures.Add($Message); Write-Host "[FAIL] $Message" -ForegroundColor Red }
function Has-Command([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

Write-Host 'AuroraFox release preflight' -ForegroundColor Cyan
Write-Host "Repository: $Repository"
Write-Host ''

# Canonical version synchronization.
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\version_sync_test.ps1')
    if ($LASTEXITCODE -ne 0) { throw "version_sync_test.ps1 returned $LASTEXITCODE" }
    Pass 'Project, Android and update-manifest versions are synchronized'
} catch { Fail "Version synchronization: $($_.Exception.Message)" }

$projectText = Get-Content -LiteralPath (Join-Path $root 'project.godot') -Raw
$version = if ($projectText -match 'config/version="([^"]+)"') { $Matches[1] } else { '' }
if ($version) { Pass "Release version is $version; expected tag v$version" } else { Fail 'Cannot read application/config/version' }

# Update trust key. Private key intentionally stays outside Git.
$publicKey = Join-Path $root 'update\release_public.pub'
if (Test-Path -LiteralPath $publicKey) {
    Pass 'Pinned public update key exists'
    if (Has-Command 'openssl') {
        try {
            & openssl pkey -pubin -in $publicKey -noout 2>$null
            if ($LASTEXITCODE -eq 0) { Pass 'Pinned public update key parses successfully' } else { Fail 'Pinned public update key is invalid' }
        } catch { Fail "Public update key validation failed: $($_.Exception.Message)" }
    } else { Warn 'OpenSSL not found locally; GitHub release workflow will validate the public key' }
} else {
    Fail 'update/release_public.pub is missing. Run build/configure_release_signing.ps1 first and commit only the public key.'
}

# Local scripts needed by the two platform builders.
$requiredFiles = @(
    'build\build_windows.ps1',
    'build\build_android.ps1',
    'build\AuroraFox.iss',
    'build\set_version.ps1',
    'build\configure_release_signing.ps1',
    'update\update_manager.gd',
    'update\windows_updater.ps1',
    'android_plugin\setup_native.ps1',
    'export_presets.cfg'
)
foreach ($relative in $requiredFiles) {
    if (Test-Path -LiteralPath (Join-Path $root $relative)) { Pass "$relative present" } else { Fail "$relative missing" }
}

# GitHub release secrets can be verified by name without ever reading values.
if (-not $SkipGitHubSecrets) {
    if (-not (Has-Command 'gh')) {
        Warn 'GitHub CLI not installed; repository secret names were not checked'
    } else {
        try {
            & gh auth status | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'gh is not authenticated' }
            $secretNames = @(& gh secret list --repo $Repository --json name --jq '.[].name')
            if ($LASTEXITCODE -ne 0) { throw 'gh secret list failed' }
            foreach ($name in @(
                'AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64',
                'AURORA_ANDROID_KEYSTORE_BASE64',
                'AURORA_ANDROID_KEYSTORE_USER',
                'AURORA_ANDROID_KEYSTORE_PASSWORD'
            )) {
                if ($secretNames -contains $name) { Pass "GitHub secret exists: $name" } else { Fail "GitHub secret missing: $name" }
            }
        } catch { Fail "GitHub secret preflight: $($_.Exception.Message)" }
    }
}

# Local tooling is advisory because GitHub Actions can build releases even if
# this workstation lacks Android SDK/Inno Setup.
foreach ($tool in @('git', 'powershell')) {
    if (Has-Command $tool) { Pass "$tool available" } else { Fail "$tool is required" }
}
foreach ($tool in @('gh', 'java', 'keytool', 'gradle', 'iscc')) {
    if (Has-Command $tool) { Pass "$tool available" } else { Warn "$tool not found locally; manual local platform build may need it" }
}

Write-Host ''
if ($warnings.Count -gt 0) {
    Write-Host "Warnings: $($warnings.Count)" -ForegroundColor Yellow
}
if ($failures.Count -gt 0) {
    Write-Host "Release preflight FAILED: $($failures.Count) blocking issue(s)." -ForegroundColor Red
    foreach ($item in $failures) { Write-Host " - $item" -ForegroundColor Red }
    exit 1
}

Write-Host "Release preflight PASSED for AuroraFox $version." -ForegroundColor Green
Write-Host "Next release tag: v$version" -ForegroundColor Cyan
exit 0
