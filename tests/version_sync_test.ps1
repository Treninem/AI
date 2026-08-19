$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$statePath = Join-Path $root 'project/version.json'
if (-not (Test-Path -LiteralPath $statePath)) { throw 'project/version.json is missing' }
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
if ([string]$state.version -notmatch '^V([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$') {
    throw 'project/version.json version must use VMajor.Minor.Patch.Build'
}
$version = "$($Matches[1]).$($Matches[2]).$($Matches[3]).$($Matches[4])"
if ([string]$state.numeric -ne $version) { throw "version.json numeric $($state.numeric) != $version" }
if ([int]$state.major -ne [int]$Matches[1] -or [int]$state.minor -ne [int]$Matches[2] -or [int]$state.patch -ne [int]$Matches[3] -or [int]$state.build -ne [int]$Matches[4]) {
    throw 'version.json numeric fields do not match display version'
}
$expectedCode = [int]$state.android_version_code
if ($expectedCode -le 0) { throw 'android_version_code must be positive' }

$project = Get-Content (Join-Path $root 'project.godot') -Raw
if ($project -notmatch 'config/version="([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)"') {
    throw 'project.godot application/config/version is missing or invalid'
}
if ($Matches[1] -ne $version) { throw "project.godot version $($Matches[1]) != canonical version $version" }

$export = Get-Content (Join-Path $root 'export_presets.cfg') -Raw
if ($export -notmatch 'version/name="([^"]+)"') { throw 'Android version/name missing' }
if ($Matches[1] -ne $version) { throw "Android version/name $($Matches[1]) != canonical version $version" }
if ($export -notmatch 'version/code=([0-9]+)') { throw 'Android version/code missing' }
$androidCode = [int]$Matches[1]
if ($androidCode -ne $expectedCode) { throw "Android version/code $androidCode != canonical android_version_code $expectedCode" }

$manifest = Get-Content (Join-Path $root 'update/manifest.template.json') -Raw | ConvertFrom-Json
if ([string]$manifest.version -ne $version) { throw "Manifest version $($manifest.version) != canonical version $version" }

Write-Host "AURORA_VERSION_SYNC_OK version=V$version androidCode=$androidCode" -ForegroundColor Green
