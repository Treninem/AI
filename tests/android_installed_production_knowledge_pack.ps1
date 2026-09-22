param(
    [Parameter(Mandatory=$true)][string]$ApkPath,
    [Parameter(Mandatory=$true)][string]$PackDir,
    [Parameter(Mandatory=$true)][string]$ReportDir,
    [string]$Adb = 'adb',
    [int]$TimeoutSeconds = 7200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Package = 'com.aurorafox.ai'
$ExpectedManifestSha256 = 'bc395f76c0797e9b3751f11fcb7a52b9999ce5c5857ece1f433778bf1fd75cbd'
$ExpectedPackId = 'aurorafox-bootstrap-ru'
$ExpectedPackVersion = '2026.09.01'
$ExpectedContentBytes = 1924345221
$ExpectedFileBytes = 1982822407
$ExpectedRecords = 75871
$ExpectedShards = 60

function Invoke-AdbText {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    $output = & $Adb @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed ($LASTEXITCODE): $($Arguments -join ' ') $([Environment]::NewLine)$($output -join [Environment]::NewLine)"
    }
    return (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
}

function Invoke-AdbChecked {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    [void](Invoke-AdbText -Arguments $Arguments)
}

function Read-RemoteJson {
    param(
        [Parameter(Mandatory=$true)][string]$RemotePath,
        [Parameter(Mandatory=$true)][string]$LocalPath
    )
    $text = Invoke-AdbText -Arguments @('exec-out', 'cat', $RemotePath)
    [IO.File]::WriteAllText($LocalPath, $text + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    return ($text | ConvertFrom-Json)
}

function Wait-AcceptanceResult {
    param(
        [Parameter(Mandatory=$true)][string]$RemotePath,
        [Parameter(Mandatory=$true)][string]$LocalPath,
        [Parameter(Mandatory=$true)][string]$Phase
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastError = ''
    while ([DateTime]::UtcNow -lt $deadline) {
        & $Adb shell test -s $RemotePath 2>$null
        if ($LASTEXITCODE -eq 0) {
            try {
                $result = Read-RemoteJson -RemotePath $RemotePath -LocalPath $LocalPath
                if ($null -ne $result.passed) {
                    return $result
                }
            } catch {
                $lastError = $_.Exception.Message
            }
        }
        Start-Sleep -Seconds 5
    }
    $logcat = & $Adb logcat -d -v brief 2>&1
    $logcat | Set-Content -LiteralPath (Join-Path $ReportDir "$Phase.logcat.txt") -Encoding UTF8
    throw "Android $Phase phase did not produce a complete report within $TimeoutSeconds seconds. $lastError"
}

function Start-AcceptancePhase {
    param(
        [Parameter(Mandatory=$true)][string]$Launcher,
        [Parameter(Mandatory=$true)][string]$RemoteReport,
        [Parameter(Mandatory=$true)][string]$LocalReport,
        [Parameter(Mandatory=$true)][string]$Phase
    )
    Invoke-AdbChecked -Arguments @('shell', 'rm', '-f', $RemoteReport)
    Invoke-AdbChecked -Arguments @('shell', 'am', 'force-stop', $Package)
    Invoke-AdbChecked -Arguments @('logcat', '-c')
    Invoke-AdbChecked -Arguments @('shell', 'am', 'start', '-W', '-n', $Launcher)
    $result = Wait-AcceptanceResult -RemotePath $RemoteReport -LocalPath $LocalReport -Phase $Phase
    $logcat = & $Adb logcat -d -v brief 2>&1
    $logcat | Set-Content -LiteralPath (Join-Path $ReportDir "$Phase.logcat.txt") -Encoding UTF8
    if ($result.passed -ne $true) {
        throw "Android $Phase phase failed: $($result.error)"
    }
    return $result
}

$resolvedApk = (Resolve-Path -LiteralPath $ApkPath).Path
$resolvedPack = (Resolve-Path -LiteralPath $PackDir).Path
New-Item -ItemType Directory -Force $ReportDir | Out-Null
$ReportDir = (Resolve-Path -LiteralPath $ReportDir).Path

$manifestPath = Join-Path $resolvedPack 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Production pack manifest is missing: $manifestPath"
}
$manifestSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash.ToLowerInvariant()
if ($manifestSha -ne $ExpectedManifestSha256) {
    throw "Production pack manifest SHA-256 mismatch: $manifestSha"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if (
    $manifest.production -ne $true -or
    [string]$manifest.pack_id -ne $ExpectedPackId -or
    [string]$manifest.pack_version -ne $ExpectedPackVersion -or
    [int64]$manifest.content_bytes -ne $ExpectedContentBytes -or
    [int64]$manifest.file_bytes -ne $ExpectedFileBytes -or
    [int]$manifest.record_count -ne $ExpectedRecords -or
    @($manifest.shards).Count -ne $ExpectedShards
) {
    throw 'Production pack identity does not match the pinned AuroraFox release contract.'
}

$devices = @((& $Adb devices) | Select-String -Pattern '^[^\s]+\s+device$')
if ($devices.Count -ne 1) {
    throw "Exactly one ready Android device/emulator is required; found $($devices.Count)."
}

Invoke-AdbChecked -Arguments @('install', '--no-incremental', '-r', $resolvedApk)
[void](Invoke-AdbText -Arguments @('root'))
Invoke-AdbChecked -Arguments @('wait-for-device')
$uid = Invoke-AdbText -Arguments @('shell', 'id', '-u')
if ($uid -ne '0') {
    throw 'This bounded acceptance harness requires an adb-root test emulator/device; it never changes the shipped app sandbox policy.'
}

$launcher = ''
for ($attempt = 0; $attempt -lt 30 -and [string]::IsNullOrWhiteSpace($launcher); $attempt++) {
    $candidate = Invoke-AdbText -Arguments @(
        'shell', 'cmd', 'package', 'resolve-activity', '--brief',
        '-a', 'android.intent.action.MAIN',
        '-c', 'android.intent.category.LAUNCHER',
        $Package
    )
    $launcher = @($candidate -split "\r?\n" | Where-Object { $_ -match '^[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+' } | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($launcher)) { Start-Sleep -Seconds 2 }
}
if ([string]::IsNullOrWhiteSpace($launcher)) {
    throw 'Android package manager did not resolve the AuroraFox acceptance launcher.'
}

Invoke-AdbChecked -Arguments @('shell', 'pm', 'clear', $Package)
$appUid = Invoke-AdbText -Arguments @('shell', 'stat', '-c', '%u', "/data/user/0/$Package")
if ($appUid -notmatch '^[0-9]+
# Push the already extracted exact corpus once. The archive/payload remains
# owner-local and is never embedded in Git, APK, or an Actions artifact.
$pushOutput = & $Adb push (Join-Path $resolvedPack '.') "$remotePack/" 2>&1
$pushOutput | Set-Content -LiteralPath (Join-Path $ReportDir 'adb-push.txt') -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
    throw "adb push failed ($LASTEXITCODE). See adb-push.txt."
}
# Root-created test input must retain the same ownership and SELinux label as
# normal app-private files before the production process is launched.
Invoke-AdbChecked -Arguments @('shell', 'chown', '-R', "$($appUid):$($appUid)", $appRoot)
Invoke-AdbChecked -Arguments @('shell', 'restorecon', '-RF', "/data/user/0/$Package")

Invoke-AdbChecked -Arguments @('shell', 'cmd', 'connectivity', 'airplane-mode', 'enable')
Invoke-AdbChecked -Arguments @('shell', 'settings', 'put', 'global', 'airplane_mode_on', '1')
Invoke-AdbChecked -Arguments @('shell', 'svc', 'wifi', 'disable')
Invoke-AdbChecked -Arguments @('shell', 'svc', 'data', 'disable')
Start-Sleep -Seconds 2
& $Adb shell ping -c 1 -W 2 1.1.1.1 *> $null
if ($LASTEXITCODE -eq 0) {
    throw 'Android target still has external network connectivity after offline setup.'
}

$firstPath = Join-Path $ReportDir 'install.result.json'
$resumePath = Join-Path $ReportDir 'resume.result.json'
$first = Start-AcceptancePhase -Launcher $launcher -RemoteReport $remoteReport -LocalReport $firstPath -Phase 'install'
if (
    [int]$first.imported_shards -ne $ExpectedShards -or
    [int]$first.skipped_shards -ne 0 -or
    [int]$first.record_count -ne $ExpectedRecords -or
    [int64]$first.content_bytes -ne $ExpectedContentBytes -or
    [string]$first.manifest_sha256 -ne $ExpectedManifestSha256 -or
    $first.query_match -ne $true -or
    $first.offline -ne $true -or
    $first.external_ai_required -ne $false
) {
    throw 'Installed Android production first-run proof is invalid.'
}

$resumed = Start-AcceptancePhase -Launcher $launcher -RemoteReport $remoteReport -LocalReport $resumePath -Phase 'restart'
if (
    [int]$resumed.imported_shards -ne 0 -or
    [int]$resumed.skipped_shards -ne $ExpectedShards -or
    [int]$resumed.record_count -ne $ExpectedRecords -or
    [string]$resumed.manifest_sha256 -ne $ExpectedManifestSha256 -or
    $resumed.query_match -ne $true -or
    $resumed.offline -ne $true -or
    $resumed.external_ai_required -ne $false
) {
    throw 'Installed Android production restart proof is invalid.'
}

$stateRemote = [string]$resumed.state_path
$stateLocal = Join-Path $ReportDir 'pack-state.json'
Invoke-AdbChecked -Arguments @('pull', $stateRemote, $stateLocal)
$stateSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $stateLocal).Hash.ToLowerInvariant()
if ($stateSha -ne [string]$resumed.state_sha256) {
    throw "Android durable state SHA-256 mismatch: $stateSha"
}
$state = Get-Content -LiteralPath $stateLocal -Raw | ConvertFrom-Json
if (@($state.completed_shards).Count -ne $ExpectedShards) {
    throw 'Android durable state does not contain all 60 completed shards.'
}

$final = [ordered]@{
    schema = 'aurorafox.android-installed-production-knowledge.v1'
    passed = $true
    installed = $true
    platform = 'Android'
    offline = $true
    outbound_network_block = $true
    external_ai_required = $false
    package = $Package
    launcher = $launcher
    pack_id = $ExpectedPackId
    pack_version = $ExpectedPackVersion
    manifest_sha256 = $ExpectedManifestSha256
    shards = $ExpectedShards
    record_count = $ExpectedRecords
    content_bytes = $ExpectedContentBytes
    first_imported_shards = [int]$first.imported_shards
    restart_skipped_shards = [int]$resumed.skipped_shards
    first_query_match = [bool]$first.query_match
    restart_query_match = [bool]$resumed.query_match
    state_sha256 = $stateSha
}
$finalPath = Join-Path $ReportDir 'report.json'
$final | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $finalPath -Encoding UTF8
Write-Host 'AURORA_ANDROID_INSTALLED_PRODUCTION_KNOWLEDGE_OK'
Write-Host "REPORT=$finalPath"
) {
    throw "Cannot resolve Android application UID: $appUid"
}
$appRoot = "/data/user/0/$Package/files/app_userdata/AuroraFox"
$remotePack = "$appRoot/android-production-pack"
$remoteReport = "$appRoot/android-production-knowledge.json"
Invoke-AdbChecked -Arguments @('shell', 'mkdir', '-p', $remotePack)

# Push the already extracted exact corpus once. The archive/payload remains
# owner-local and is never embedded in Git, APK, or an Actions artifact.
$pushOutput = & $Adb push (Join-Path $resolvedPack '.') "$remotePack/" 2>&1
$pushOutput | Set-Content -LiteralPath (Join-Path $ReportDir 'adb-push.txt') -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
    throw "adb push failed ($LASTEXITCODE). See adb-push.txt."
}

Invoke-AdbChecked -Arguments @('shell', 'cmd', 'connectivity', 'airplane-mode', 'enable')
Invoke-AdbChecked -Arguments @('shell', 'settings', 'put', 'global', 'airplane_mode_on', '1')
Invoke-AdbChecked -Arguments @('shell', 'svc', 'wifi', 'disable')
Invoke-AdbChecked -Arguments @('shell', 'svc', 'data', 'disable')
Start-Sleep -Seconds 2
& $Adb shell ping -c 1 -W 2 1.1.1.1 *> $null
if ($LASTEXITCODE -eq 0) {
    throw 'Android target still has external network connectivity after offline setup.'
}

$firstPath = Join-Path $ReportDir 'install.result.json'
$resumePath = Join-Path $ReportDir 'resume.result.json'
$first = Start-AcceptancePhase -Launcher $launcher -RemoteReport $remoteReport -LocalReport $firstPath -Phase 'install'
if (
    [int]$first.imported_shards -ne $ExpectedShards -or
    [int]$first.skipped_shards -ne 0 -or
    [int]$first.record_count -ne $ExpectedRecords -or
    [int64]$first.content_bytes -ne $ExpectedContentBytes -or
    [string]$first.manifest_sha256 -ne $ExpectedManifestSha256 -or
    $first.query_match -ne $true -or
    $first.offline -ne $true -or
    $first.external_ai_required -ne $false
) {
    throw 'Installed Android production first-run proof is invalid.'
}

$resumed = Start-AcceptancePhase -Launcher $launcher -RemoteReport $remoteReport -LocalReport $resumePath -Phase 'restart'
if (
    [int]$resumed.imported_shards -ne 0 -or
    [int]$resumed.skipped_shards -ne $ExpectedShards -or
    [int]$resumed.record_count -ne $ExpectedRecords -or
    [string]$resumed.manifest_sha256 -ne $ExpectedManifestSha256 -or
    $resumed.query_match -ne $true -or
    $resumed.offline -ne $true -or
    $resumed.external_ai_required -ne $false
) {
    throw 'Installed Android production restart proof is invalid.'
}

$stateRemote = [string]$resumed.state_path
$stateLocal = Join-Path $ReportDir 'pack-state.json'
Invoke-AdbChecked -Arguments @('pull', $stateRemote, $stateLocal)
$stateSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $stateLocal).Hash.ToLowerInvariant()
if ($stateSha -ne [string]$resumed.state_sha256) {
    throw "Android durable state SHA-256 mismatch: $stateSha"
}
$state = Get-Content -LiteralPath $stateLocal -Raw | ConvertFrom-Json
if (@($state.completed_shards).Count -ne $ExpectedShards) {
    throw 'Android durable state does not contain all 60 completed shards.'
}

$final = [ordered]@{
    schema = 'aurorafox.android-installed-production-knowledge.v1'
    passed = $true
    installed = $true
    platform = 'Android'
    offline = $true
    outbound_network_block = $true
    external_ai_required = $false
    package = $Package
    launcher = $launcher
    pack_id = $ExpectedPackId
    pack_version = $ExpectedPackVersion
    manifest_sha256 = $ExpectedManifestSha256
    shards = $ExpectedShards
    record_count = $ExpectedRecords
    content_bytes = $ExpectedContentBytes
    first_imported_shards = [int]$first.imported_shards
    restart_skipped_shards = [int]$resumed.skipped_shards
    first_query_match = [bool]$first.query_match
    restart_query_match = [bool]$resumed.query_match
    state_sha256 = $stateSha
}
$finalPath = Join-Path $ReportDir 'report.json'
$final | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $finalPath -Encoding UTF8
Write-Host 'AURORA_ANDROID_INSTALLED_PRODUCTION_KNOWLEDGE_OK'
Write-Host "REPORT=$finalPath"
