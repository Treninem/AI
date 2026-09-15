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

Write-Host 'AuroraFox V1 direct-update bridge readiness' -ForegroundColor Cyan
Write-Host 'Compatibility floor: V1.0.0.0 -> latest stable'
Write-Host "Repository: $Repository"
Write-Host ''

$python = if (Has-Command 'python') { 'python' } elseif (Has-Command 'python3') { 'python3' } else { '' }
if ([string]::IsNullOrWhiteSpace($python)) {
    Fail 'Python is required to validate the legacy update contract'
} else {
    try {
        & $python -m pytest -q (Join-Path $root 'tests\test_update_backward_compat.py')
        if ($LASTEXITCODE -ne 0) { throw "legacy update contract tests returned $LASTEXITCODE" }
        Pass 'V1.0 manifest, asset-name, ZIP-layout and export-key compatibility contract passed'
    } catch {
        Fail "Backward update compatibility: $($_.Exception.Message)"
    }
}

try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\version_sync_test.ps1')
    if ($LASTEXITCODE -ne 0) { throw "version_sync_test.ps1 returned $LASTEXITCODE" }
    Pass 'Project, Android and manifest template versions are synchronized'
} catch {
    Fail "Version synchronization: $($_.Exception.Message)"
}

$versionPath = Join-Path $root 'project\version.json'
try {
    $versionState = Get-Content -LiteralPath $versionPath -Raw | ConvertFrom-Json
    $numeric = [string]$versionState.numeric
    if ($numeric -notmatch '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$') { throw 'invalid four-part numeric version' }
    $parts = @($numeric.Split('.') | ForEach-Object { [int]$_ })
    $floor = @(1,0,0,0)
    $atLeastFloor = $false
    for ($i = 0; $i -lt 4; $i++) {
        if ($parts[$i] -gt $floor[$i]) { $atLeastFloor = $true; break }
        if ($parts[$i] -lt $floor[$i]) { break }
        if ($i -eq 3) { $atLeastFloor = $true }
    }
    if (-not $atLeastFloor) { throw "bridge target $numeric is older than V1.0.0.0 compatibility floor" }
    Pass "Bridge target version is V$numeric"
} catch {
    Fail "Canonical bridge version: $($_.Exception.Message)"
}

$publicKey = Join-Path $root 'update\release_public.pub'
if (-not (Test-Path -LiteralPath $publicKey)) {
    Fail 'update/release_public.pub is missing. Run build/create_update_signing_key.ps1 once on the trusted owner machine, commit ONLY the public key, and keep the private key outside Git.'
} else {
    try {
        $text = Get-Content -LiteralPath $publicKey -Raw
        if ($text -notmatch '-----BEGIN PUBLIC KEY-----') { throw 'public key is not SubjectPublicKeyInfo PEM' }
        if (Has-Command 'openssl') {
            & openssl pkey -pubin -in $publicKey -noout 2>$null
            if ($LASTEXITCODE -ne 0) { throw 'OpenSSL rejected the pinned public key' }
            $der = Join-Path $env:TEMP ('aurora-public-' + [Guid]::NewGuid().ToString('N') + '.der')
            try {
                & openssl pkey -pubin -in $publicKey -outform DER -out $der
                if ($LASTEXITCODE -ne 0) { throw 'Failed to derive public-key DER' }
                $fingerprint = (Get-FileHash -LiteralPath $der -Algorithm SHA256).Hash.ToLowerInvariant()
                Pass "Pinned update public key parses; SHA-256=$fingerprint"
            } finally {
                Remove-Item -LiteralPath $der -Force -ErrorAction SilentlyContinue
            }
        } else {
            Pass 'Pinned update public key exists in PEM format'
            Warn 'OpenSSL is unavailable locally; GitHub release workflow will perform the key-pair fingerprint check'
        }
    } catch {
        Fail "Pinned update public key: $($_.Exception.Message)"
    }
}

$presets = Get-Content -LiteralPath (Join-Path $root 'export_presets.cfg') -Raw
$includeCount = ([regex]::Matches($presets, 'include_filter="update/release_public\.pub"')).Count
if ($includeCount -eq 2) {
    Pass 'Pinned update public key is explicitly included in both Windows and Android exports'
} else {
    Fail "Expected update/release_public.pub in both export presets; found $includeCount include rules"
}
if ($presets -match 'package/unique_name="com\.aurorafox\.ai"') {
    Pass 'Android package identity remains com.aurorafox.ai'
} else {
    Fail 'Android package identity changed; installed legacy APKs would not update in place'
}

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
    Write-Host "BRIDGE RELEASE NOT READY: $($failures.Count) blocking issue(s)." -ForegroundColor Red
    foreach ($item in $failures) { Write-Host " - $item" -ForegroundColor Red }
    Write-Host 'No tag/release should be published until all blocking items are resolved.' -ForegroundColor Yellow
    exit 1
}

Write-Host 'BRIDGE RELEASE READY.' -ForegroundColor Green
Write-Host 'V1.0.0.0+ clients retain a direct path to this stable release; current clients retain RSA manifest verification.' -ForegroundColor Cyan
exit 0
