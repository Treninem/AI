param(
    [Parameter(Mandatory = $true)][string]$Iscc,
    [string]$CandidateVersion = '1.3.0.0',
    [string]$CurrentInstaller = ''
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'windows_bounded_process.ps1')
$logDir = Join-Path $root 'artifacts\installer-smoke'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$fixtureSource = Join-Path $root 'build\bridge_fixture'
$fixtureIss = Join-Path $root 'build\AuroraFox_V13_BridgeFixture.iss'
$targetIss = Join-Path $root 'build\AuroraFox.iss'
$targetDir = Join-Path $root 'build\release\v13-repair-target'
$reuseInstaller = -not [string]::IsNullOrWhiteSpace($CurrentInstaller)
if ($reuseInstaller) {
    $targetInstaller = (Resolve-Path -LiteralPath $CurrentInstaller).Path
    $versionState = Get-Content -LiteralPath (Join-Path $root 'project\version.json') -Raw | ConvertFrom-Json
    if ($CandidateVersion -ne [string]$versionState.numeric) { throw 'Reused installer requires the canonical candidate version' }
    Write-Host "AURORA_WINDOWS_V13_REUSE_INSTALLER $targetInstaller"
}

if ($CandidateVersion -notmatch '^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$') { throw 'CandidateVersion must use four numeric parts' }
$parts = @([int]$Matches[1],[int]$Matches[2],[int]$Matches[3],[int]$Matches[4])
if (($parts[0] -lt 1) -or (($parts[0] -eq 1) -and ($parts[1] -lt 3))) {
    throw "V1.3 trust-root repair target must be V1.3.0.0 or newer: $CandidateVersion"
}
if (-not (Test-Path -LiteralPath $Iscc)) { throw "Inno Setup compiler missing: $Iscc" }
if (-not (Test-Path -LiteralPath $fixtureIss)) { throw 'V1.3 bridge fixture definition is missing' }
if (-not (Test-Path -LiteralPath $targetIss)) { throw 'Current AuroraFox installer definition is missing' }

Remove-Item $fixtureSource -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $targetDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $fixtureSource,$targetDir | Out-Null
$builtExe = Join-Path $root 'build\windows\AuroraFox.exe'
if (-not (Test-Path -LiteralPath $builtExe)) { throw 'Current built AuroraFox.exe is missing' }
Copy-Item $builtExe (Join-Path $fixtureSource 'AuroraFox.exe') -Force
Set-Content -LiteralPath (Join-Path $fixtureSource 'v1.3-marker.txt') -Value 'historical-v1.3-install-marker' -Encoding UTF8

Push-Location (Join-Path $root 'build')
try {
    & $Iscc 'AuroraFox_V13_BridgeFixture.iss'
    if ($LASTEXITCODE -ne 0) { throw 'Failed to compile V1.3 bridge fixture installer' }
    if (-not $reuseInstaller) {
        & $Iscc "/DMyAppVersion=$CandidateVersion" "/O$targetDir" '/FAuroraFox_V13_Repair_Target' 'AuroraFox.iss'
        if ($LASTEXITCODE -ne 0) { throw 'Failed to compile V1.3 repair target installer' }
    }
} finally {
    Pop-Location
}

$fixtureInstaller = Join-Path $root 'build\release\AuroraFox_V13_BridgeFixture.exe'
if (-not $reuseInstaller) { $targetInstaller = Join-Path $targetDir 'AuroraFox_V13_Repair_Target.exe' }
if (-not (Test-Path -LiteralPath $fixtureInstaller)) { throw 'V1.3 bridge fixture installer was not produced' }
if (-not (Test-Path -LiteralPath $targetInstaller)) { throw 'V1.3 repair target installer was not produced' }

$installDir = Join-Path $env:RUNNER_TEMP 'AuroraFoxV13BridgeInstalled'
Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
$userDataDir = Join-Path $env:APPDATA 'Godot\app_userdata\AuroraFox'
New-Item -ItemType Directory -Force -Path $userDataDir | Out-Null
$sentinel = Join-Path $userDataDir 'bridge-v13-sentinel.txt'
$sentinelValue = 'AURORAFOX_V13_USER_DATA_MUST_SURVIVE_' + [guid]::NewGuid().ToString('N')
Set-Content -LiteralPath $sentinel -Value $sentinelValue -Encoding UTF8

try {
    $installLog = Join-Path $logDir 'v13-fixture.log'
    $legacyExit = Invoke-AuroraBoundedProcess -FilePath $fixtureInstaller -ArgumentList @('/SP-','/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/DIR=`"$installDir`"","/LOG=`"$installLog`"") -Phase 'v13-fixture-install' -TimeoutSeconds 180
    if ($legacyExit -notin @(0,3010)) { throw "V1.3 fixture installer exited with $($legacyExit)" }
    if (-not (Test-Path (Join-Path $installDir 'v1.3-marker.txt'))) { throw 'V1.3 fixture marker is missing after fixture install' }

    $installLog = Join-Path $logDir 'v13-repair.log'
    $repairExit = Invoke-AuroraBoundedProcess -FilePath $targetInstaller -ArgumentList @('/SP-','/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/DIR=`"$installDir`"","/LOG=`"$installLog`"") -Phase 'v13-repair-install' -TimeoutSeconds 1200
    if ($repairExit -notin @(0,3010)) { throw "V1.3 repair installer exited with $($repairExit)" }

    $installedExe = Join-Path $installDir 'AuroraFox.exe'
    if (-not (Test-Path -LiteralPath $installedExe)) { throw 'AuroraFox.exe is missing after V1.3 repair install' }
    if (Test-Path (Join-Path $installDir 'v1.3-marker.txt')) { throw 'Known V1.3 installation marker was not cleaned by repair installer' }

    $bridgeMarker = Join-Path $installDir 'update\bridge_repair.txt'
    if (-not (Test-Path -LiteralPath $bridgeMarker)) { throw 'V1.3 repair marker was not created' }
    $bridgeText = Get-Content -LiteralPath $bridgeMarker -Raw
    if ($bridgeText -notmatch 'previous=1\.3\.0\.0') { throw "Bridge marker did not record V1.3 source version: $bridgeText" }
    if ($bridgeText -notmatch ('current=' + [regex]::Escape($CandidateVersion))) { throw "Bridge marker did not record repair target $CandidateVersion`: $bridgeText" }

    $trustRoot = Join-Path $installDir 'update\release_public.pub'
    if (-not (Test-Path -LiteralPath $trustRoot)) { throw 'Permanent signed-update trust root was not installed by V1.3 repair' }

    if (-not (Test-Path -LiteralPath $sentinel)) { throw 'Godot user data was deleted during V1.3 repair' }
    $after = (Get-Content -LiteralPath $sentinel -Raw).Trim()
    if ($after -ne $sentinelValue) { throw 'Godot user data changed during V1.3 repair' }

    $runExit = Invoke-AuroraBoundedProcess -FilePath $installedExe -ArgumentList @('--headless','--quit-after','3') -Phase 'v13-installed-app' -TimeoutSeconds 90
    if ($runExit -ne 0) { throw "Repaired AuroraFox exited with $($runExit)" }

    Write-Host "AURORA_WINDOWS_V13_TRUST_ROOT_REPAIR_OK target=$CandidateVersion" -ForegroundColor Green
} finally {
    $uninstaller = Get-ChildItem $installDir -Filter 'unins*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($uninstaller) {
        $uninstallLog = Join-Path $logDir 'v13-uninstall.log'
        $uninstallExit = Invoke-AuroraBoundedProcess -FilePath $uninstaller.FullName -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/LOG=`"$uninstallLog`"") -Phase 'v13-uninstall' -TimeoutSeconds 180
        if ($uninstallExit -notin @(0,3010)) { throw "Uninstaller exited with $uninstallExit" }
    }
    Remove-Item $sentinel -Force -ErrorAction SilentlyContinue
    Remove-Item $fixtureSource -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $targetDir -Recurse -Force -ErrorAction SilentlyContinue
}
