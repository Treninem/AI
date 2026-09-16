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

Write-Host 'AuroraFox V1.2 repair / V1.3 signed-update readiness' -ForegroundColor Cyan
Write-Host 'Historical V1.0-V1.2 clients require a one-time repair bridge.'
Write-Host 'Signed automatic-update floor: V1.3.0.0'
Write-Host "Repository: $Repository"
Write-Host ''

$python = if (Has-Command 'python') { 'python' } elseif (Has-Command 'python3') { 'python3' } else { '' }
if ([string]::IsNullOrWhiteSpace($python)) {
    Fail 'Python is required to validate the update compatibility contract'
} else {
    try {
        & $python -m pytest -q (Join-Path $root 'tests\test_update_backward_compat.py')
        if ($LASTEXITCODE -ne 0) { throw "update compatibility tests returned $LASTEXITCODE" }
        Pass 'V1.2 repair boundary and V1.3 signed-update contract passed'
    } catch {
        Fail "Update compatibility: $($_.Exception.Message)"
    }
}

try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\version_sync_test.ps1')
    if ($LASTEXITCODE -ne 0) { throw "version_sync_test.ps1 returned $LASTEXITCODE" }
    Pass 'Project, Android and manifest template versions are synchronized'
} catch {
    Fail "Version synchronization: $($_.Exception.Message)"
}

try {
    $versionState = Get-Content -LiteralPath (Join-Path $root 'project\version.json') -Raw | ConvertFrom-Json
    $numeric = [string]$versionState.numeric
    if ($numeric -notmatch '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$') { throw 'invalid four-part numeric version' }
    $parts = @($numeric.Split('.') | ForEach-Object { [int]$_ })
    $floor = @(1,3,0,0)
    $atLeastFloor = $false
    for ($i = 0; $i -lt 4; $i++) {
        if ($parts[$i] -gt $floor[$i]) { $atLeastFloor = $true; break }
        if ($parts[$i] -lt $floor[$i]) { break }
        if ($i -eq 3) { $atLeastFloor = $true }
    }
    if (-not $atLeastFloor) { throw "signed update target $numeric is older than V1.3.0.0" }
    Pass "Signed update target version is V$numeric"
} catch {
    Fail "Canonical signed-update version: $($_.Exception.Message)"
}

$iss = Get-Content -LiteralPath (Join-Path $root 'build\AuroraFox.iss') -Raw
$fixture = Get-Content -LiteralPath (Join-Path $root 'build\AuroraFox_V12_BridgeFixture.iss') -Raw
if ($iss -match 'AppId=\{\{8C21F024-53DE-4FA3-A150-78C80829B6BF\}' -and $fixture -match 'AppId=\{\{8C21F024-53DE-4FA3-A150-78C80829B6BF\}') {
    Pass 'V1.2 fixture and current Windows installer share the same upgrade AppId'
} else {
    Fail 'Windows repair AppId continuity is broken'
}
if ($iss.Contains('bridge_repair.txt')) { Pass 'Windows installer records successful bridge repair' } else { Fail 'Windows installer does not record bridge repair' }

$publicKey = Join-Path $root 'update\release_public.pub'
if (-not (Test-Path -LiteralPath $publicKey)) {
    Fail 'update/release_public.pub is missing. Initialize the owner-controlled trust root before publishing the first signed release.'
} else {
    try {
        $text = Get-Content -LiteralPath $publicKey -Raw
        if ($text -notmatch '-----BEGIN PUBLIC KEY-----') { throw 'public key is not SubjectPublicKeyInfo PEM' }
        Pass 'Pinned update public key exists in PEM format'
    } catch {
        Fail "Pinned update public key: $($_.Exception.Message)"
    }
}

$presets = Get-Content -LiteralPath (Join-Path $root 'export_presets.cfg') -Raw
$includeCount = ([regex]::Matches($presets, 'include_filter="update/release_public\.pub"')).Count
if ($includeCount -eq 2) { Pass 'Pinned update key is included in Windows and Android exports' } else { Fail "Expected public key in both exports; found $includeCount include rules" }
if ($presets -match 'package/unique_name="com\.aurorafox\.ai"') { Pass 'Android package identity remains com.aurorafox.ai' } else { Fail 'Android package identity changed' }

$release = Get-Content -LiteralPath (Join-Path $root '.github\workflows\release.yml') -Raw
foreach ($needle in @(
    'AuroraFox-Windows.zip',
    'AuroraFox-Android.apk',
    'dist/update.json',
    'dist/update.sig',
    'AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64',
    'needs: core-gates'
)) {
    if ($release.Contains($needle)) { Pass "Release contract contains: $needle" } else { Fail "Release contract missing: $needle" }
}

if (-not $SkipGitHubSecrets) {
    if (-not (Has-Command 'gh')) {
        Warn 'GitHub CLI is unavailable; repository secret names were not checked locally'
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
        } catch {
            Fail "GitHub signing-secret readiness: $($_.Exception.Message)"
        }
    }
}

Write-Host ''
if ($warnings.Count -gt 0) { Write-Host "Warnings: $($warnings.Count)" -ForegroundColor Yellow }
if ($failures.Count -gt 0) {
    Write-Host "SIGNED RELEASE NOT READY: $($failures.Count) blocking issue(s)." -ForegroundColor Red
    foreach ($item in $failures) { Write-Host " - $item" -ForegroundColor Red }
    Write-Host 'V1.2 users may use the tested Windows repair installer, but no signed auto-update release should be published until trust/signing requirements are satisfied.' -ForegroundColor Yellow
    exit 1
}

Write-Host 'V1.2 REPAIR + V1.3 SIGNED RELEASE READY.' -ForegroundColor Green
Write-Host 'Legacy V1.2 installations use the one-time repair installer; V1.3+ uses the signed update channel.' -ForegroundColor Cyan
exit 0
