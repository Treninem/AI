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
function Get-Sha256Hex([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-PublicKeyFingerprint([string]$Path) {
    $pem = Get-Content -LiteralPath $Path -Raw
    $base64 = ($pem -replace '-----BEGIN PUBLIC KEY-----', '' -replace '-----END PUBLIC KEY-----', '' -replace '\s', '')
    if ([string]::IsNullOrWhiteSpace($base64)) { throw 'public key PEM is empty' }
    return Get-Sha256Hex ([Convert]::FromBase64String($base64))
}

Write-Host 'AuroraFox historical repair / V1.4 signed-update readiness' -ForegroundColor Cyan
Write-Host 'Historical V1.2 and V1.3 Windows clients require a one-time repair bridge.'
Write-Host 'Permanent signed automatic-update floor: V1.4.0.0'
Write-Host "Repository: $Repository"
Write-Host ''

$python = if (Has-Command 'python') { 'python' } elseif (Has-Command 'python3') { 'python3' } else { '' }
if ([string]::IsNullOrWhiteSpace($python)) {
    Fail 'Python is required to validate the update compatibility contract'
} else {
    try {
        & $python -m pytest -q (Join-Path $root 'tests\test_update_backward_compat.py') (Join-Path $root 'tests\test_release_identity_version_policy.py')
        if ($LASTEXITCODE -ne 0) { throw "update/release contract tests returned $LASTEXITCODE" }
        Pass 'Historical repair boundary, permanent release identity and version policy contracts passed'
    } catch {
        Fail "Update/release contracts: $($_.Exception.Message)"
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
    $floor = @(1,4,0,0)
    $atLeastFloor = $false
    for ($i = 0; $i -lt 4; $i++) {
        if ($parts[$i] -gt $floor[$i]) { $atLeastFloor = $true; break }
        if ($parts[$i] -lt $floor[$i]) { break }
        if ($i -eq 3) { $atLeastFloor = $true }
    }
    if (-not $atLeastFloor) {
        Warn "Canonical version V$numeric is still pre-floor; finish pre-bump gates, then bump to V1.4.0.0 or newer before production release."
    } else {
        Pass "Signed update target version is V$numeric"
    }
} catch {
    Fail "Canonical signed-update version: $($_.Exception.Message)"
}

$iss = Get-Content -LiteralPath (Join-Path $root 'build\AuroraFox.iss') -Raw
$v12Fixture = Get-Content -LiteralPath (Join-Path $root 'build\AuroraFox_V12_BridgeFixture.iss') -Raw
$v13FixturePath = Join-Path $root 'build\AuroraFox_V13_BridgeFixture.iss'
if (-not (Test-Path $v13FixturePath)) { Fail 'V1.3 bridge fixture is missing' } else { $v13Fixture = Get-Content -LiteralPath $v13FixturePath -Raw }
if ($iss -match 'AppId=\{\{8C21F024-53DE-4FA3-A150-78C80829B6BF\}' -and $v12Fixture -match 'AppId=\{\{8C21F024-53DE-4FA3-A150-78C80829B6BF\}' -and $v13Fixture -match 'AppId=\{\{8C21F024-53DE-4FA3-A150-78C80829B6BF\}') {
    Pass 'V1.2, V1.3 and current Windows installers share the same upgrade AppId'
} else {
    Fail 'Windows repair AppId continuity is broken'
}
if ($iss.Contains('bridge_repair.txt') -and $iss.Contains('v1.3-marker.txt')) { Pass 'Windows installer records repair and cleans V1.3 legacy marker' } else { Fail 'Windows V1.3 repair behavior is incomplete' }

$publicKey = Join-Path $root 'update\release_public.pub'
$fingerprintPath = Join-Path $root 'update\release_public_fingerprint.sha256'
$identityPath = Join-Path $root 'update\release_identity.json'
$publicFingerprint = ''
if (-not (Test-Path -LiteralPath $publicKey)) {
    Fail 'update/release_public.pub is missing'
} else {
    try {
        $text = Get-Content -LiteralPath $publicKey -Raw
        if ($text -notmatch '-----BEGIN PUBLIC KEY-----') { throw 'public key is not SubjectPublicKeyInfo PEM' }
        $publicFingerprint = Get-PublicKeyFingerprint $publicKey
        if (-not (Test-Path $fingerprintPath)) { throw 'release_public_fingerprint.sha256 is missing' }
        $declaredFingerprint = ((Get-Content $fingerprintPath -Raw).Split(' ',[System.StringSplitOptions]::RemoveEmptyEntries)[0]).ToLowerInvariant()
        if ($publicFingerprint -ne $declaredFingerprint) { throw "public key fingerprint mismatch: $publicFingerprint != $declaredFingerprint" }
        Pass "Pinned update public key exists: $publicFingerprint"
    } catch {
        Fail "Pinned update public key: $($_.Exception.Message)"
    }
}

if (-not (Test-Path -LiteralPath $identityPath)) {
    Fail 'update/release_identity.json is missing'
} else {
    try {
        $identity = Get-Content -LiteralPath $identityPath -Raw | ConvertFrom-Json
        if ([int]$identity.schema_version -ne 1) { throw 'unsupported release identity schema' }
        if ([string]$identity.android_package -ne 'com.aurorafox.ai') { throw 'Android package pin is not com.aurorafox.ai' }
        if ([string]$identity.signed_update_floor -ne '1.4.0.0') { throw 'signed update floor pin is not 1.4.0.0' }
        if ([string]$identity.legacy_repair_required_through -ne '1.3.0.0') { throw 'legacy repair boundary is not V1.3.0.0' }
        $androidFingerprint = ([string]$identity.android_signing_cert_sha256).ToLowerInvariant().Replace(':', '')
        if ($androidFingerprint -notmatch '^[0-9a-f]{64}$') { throw 'Android certificate SHA-256 pin is invalid' }
        $updateFingerprint = ([string]$identity.update_signing_public_key_sha256).ToLowerInvariant().Replace(':', '')
        if ($updateFingerprint -notmatch '^[0-9a-f]{64}$') { throw 'update public-key SHA-256 pin is invalid' }
        if (-not [string]::IsNullOrWhiteSpace($publicFingerprint) -and $updateFingerprint -ne $publicFingerprint) {
            throw "release identity pins update key $updateFingerprint but committed release_public.pub is $publicFingerprint"
        }
        Pass "Permanent release identity is pinned; Android cert=$androidFingerprint"
    } catch {
        Fail "Permanent release identity: $($_.Exception.Message)"
    }
}

$presets = Get-Content -LiteralPath (Join-Path $root 'export_presets.cfg') -Raw
$includeCount = ([regex]::Matches($presets, 'update/release_public\.pub')).Count
if ($includeCount -ge 2) { Pass 'Pinned update key is included in Windows and Android exports' } else { Fail "Expected public key in both exports; found $includeCount include references" }
if ($presets -match 'package/unique_name="com\.aurorafox\.ai"') { Pass 'Android package identity remains com.aurorafox.ai' } else { Fail 'Android package identity changed' }

$androidBuild = Get-Content -LiteralPath (Join-Path $root 'build\build_android.ps1') -Raw
foreach ($needle in @('update/release_identity.json','GODOT_ANDROID_KEYSTORE_RELEASE_PATH','certificate SHA-256 digest','Built APK signing certificate mismatch','AURORAFOX_ANDROID_RELEASE_IDENTITY_OK')) {
    if ($androidBuild.Contains($needle)) { Pass "Android release identity gate contains: $needle" } else { Fail "Android release identity gate missing: $needle" }
}

$release = Get-Content -LiteralPath (Join-Path $root '.github\workflows\release.yml') -Raw
foreach ($needle in @('AuroraFox-Windows.zip','AuroraFox-Android.apk','dist/update.json','dist/update.sig','AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64','AURORA_ANDROID_KEYSTORE_BASE64','GODOT_ANDROID_KEYSTORE_RELEASE_PATH','build_android.ps1','needs: core-gates')) {
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
            foreach ($name in @('AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64','AURORA_ANDROID_KEYSTORE_BASE64','AURORA_ANDROID_KEYSTORE_USER','AURORA_ANDROID_KEYSTORE_PASSWORD')) {
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
    Write-Host 'Historical V1.2/V1.3 Windows users require the one-time repair installer; no normal signed release should be published until all trust/signing requirements pass.' -ForegroundColor Yellow
    exit 1
}

Write-Host 'AURORAFOX V1.2/V1.3 REPAIR + V1.4 SIGNED-FLOOR CONTRACT READY.' -ForegroundColor Green
Write-Host 'After the canonical version reaches V1.4.0.0 and signing secrets are installed, V1.4+ uses the pinned signed update channel.' -ForegroundColor Cyan
exit 0
