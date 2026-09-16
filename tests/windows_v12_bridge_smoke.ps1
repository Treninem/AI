param(
    [Parameter(Mandatory = $true)][string]$Iscc,
    [Parameter(Mandatory = $true)][string]$CurrentInstaller
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$fixtureSource = Join-Path $root 'build\bridge_fixture'
$fixtureIss = Join-Path $root 'build\AuroraFox_V12_BridgeFixture.iss'
$currentInstallerPath = (Resolve-Path $CurrentInstaller).Path
$versionState = Get-Content -LiteralPath (Join-Path $root 'project\version.json') -Raw | ConvertFrom-Json
$currentVersion = [string]$versionState.numeric
if ($currentVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$') { throw 'Canonical current version is invalid' }

if (-not (Test-Path -LiteralPath $Iscc)) { throw "Inno Setup compiler missing: $Iscc" }
if (-not (Test-Path -LiteralPath $fixtureIss)) { throw 'V1.2 bridge fixture definition is missing' }
if (-not (Test-Path -LiteralPath $currentInstallerPath)) { throw 'Current AuroraFox installer is missing' }

Remove-Item $fixtureSource -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $fixtureSource | Out-Null
$builtExe = Join-Path $root 'build\windows\AuroraFox.exe'
if (-not (Test-Path -LiteralPath $builtExe)) { throw 'Current built AuroraFox.exe is missing' }
Copy-Item $builtExe (Join-Path $fixtureSource 'AuroraFox.exe') -Force
Set-Content -LiteralPath (Join-Path $fixtureSource 'v1.2-marker.txt') -Value 'historical-v1.2-install-marker' -Encoding UTF8

Push-Location (Join-Path $root 'build')
try {
    & $Iscc 'AuroraFox_V12_BridgeFixture.iss'
    if ($LASTEXITCODE -ne 0) { throw 'Failed to compile V1.2 bridge fixture installer' }
} finally {
    Pop-Location
}

$fixtureInstaller = Join-Path $root 'build\release\AuroraFox_V12_BridgeFixture.exe'
if (-not (Test-Path -LiteralPath $fixtureInstaller)) { throw 'V1.2 bridge fixture installer was not produced' }

$installDir = Join-Path $env:RUNNER_TEMP 'AuroraFoxBridgeInstalled'
Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
$userDataDir = Join-Path $env:APPDATA 'Godot\app_userdata\AuroraFox'
New-Item -ItemType Directory -Force -Path $userDataDir | Out-Null
$sentinel = Join-Path $userDataDir 'bridge-v12-sentinel.txt'
$sentinelValue = 'AURORAFOX_V12_USER_DATA_MUST_SURVIVE_' + [guid]::NewGuid().ToString('N')
Set-Content -LiteralPath $sentinel -Value $sentinelValue -Encoding UTF8

try {
    $v12 = Start-Process -FilePath $fixtureInstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/DIR=$installDir") -PassThru -Wait
    if ($v12.ExitCode -notin @(0,3010)) { throw "V1.2 fixture installer exited with $($v12.ExitCode)" }
    if (-not (Test-Path (Join-Path $installDir 'v1.2-marker.txt'))) { throw 'V1.2 fixture marker is missing after fixture install' }

    $current = Start-Process -FilePath $currentInstallerPath -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/DIR=$installDir") -PassThru -Wait
    if ($current.ExitCode -notin @(0,3010)) { throw "Current bridge installer exited with $($current.ExitCode)" }

    $installedExe = Join-Path $installDir 'AuroraFox.exe'
    if (-not (Test-Path -LiteralPath $installedExe)) { throw 'AuroraFox.exe is missing after V1.2 -> current bridge install' }
    if (Test-Path (Join-Path $installDir 'v1.2-marker.txt')) { throw 'Known V1.2 installation marker was not cleaned by bridge installer' }

    $bridgeMarker = Join-Path $installDir 'update\bridge_repair.txt'
    if (-not (Test-Path -LiteralPath $bridgeMarker)) { throw 'Bridge repair marker was not created' }
    $bridgeText = Get-Content -LiteralPath $bridgeMarker -Raw
    if ($bridgeText -notmatch 'previous=1\.2\.0\.0') { throw "Bridge marker did not record V1.2 source version: $bridgeText" }
    if ($bridgeText -notmatch ('current=' + [regex]::Escape($currentVersion))) { throw "Bridge marker did not record target $currentVersion`: $bridgeText" }

    if (-not (Test-Path -LiteralPath $sentinel)) { throw 'Godot user data was deleted during bridge install' }
    $after = (Get-Content -LiteralPath $sentinel -Raw).Trim()
    if ($after -ne $sentinelValue) { throw 'Godot user data changed during bridge install' }

    $run = Start-Process -FilePath $installedExe -ArgumentList @('--headless','--quit-after','3') -PassThru -Wait
    if ($run.ExitCode -ne 0) { throw "Bridged AuroraFox exited with $($run.ExitCode)" }

    Write-Host "AURORA_WINDOWS_V12_TO_CURRENT_BRIDGE_OK target=$currentVersion" -ForegroundColor Green
} finally {
    $uninstaller = Get-ChildItem $installDir -Filter 'unins*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($uninstaller) {
        Start-Process -FilePath $uninstaller.FullName -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -PassThru -Wait | Out-Null
    }
    Remove-Item $sentinel -Force -ErrorAction SilentlyContinue
    Remove-Item $fixtureSource -Recurse -Force -ErrorAction SilentlyContinue
}
