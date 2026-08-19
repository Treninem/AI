$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$project = Get-Content (Join-Path $root 'project.godot') -Raw
if ($project -notmatch 'config/version="([0-9]+)\.([0-9]+)\.([0-9]+)"') {
    throw 'project.godot application/config/version is missing or invalid'
}
$version = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
$major = [int]$Matches[1]
$minor = [int]$Matches[2]
$patch = [int]$Matches[3]
$expectedCode = $major * 10000 + $minor * 100 + $patch
if ($expectedCode -le 0) { $expectedCode = 1 }

$export = Get-Content (Join-Path $root 'export_presets.cfg') -Raw
if ($export -notmatch 'version/name="([^"]+)"') { throw 'Android version/name missing' }
$androidName = $Matches[1]
if ($androidName -ne $version) { throw "Android version/name $androidName != project version $version" }
if ($export -notmatch 'version/code=([0-9]+)') { throw 'Android version/code missing' }
$androidCode = [int]$Matches[1]
if ($androidCode -ne $expectedCode) { throw "Android version/code $androidCode != expected $expectedCode" }

$manifest = Get-Content (Join-Path $root 'update/manifest.template.json') -Raw | ConvertFrom-Json
if ([string]$manifest.version -ne $version) { throw "Manifest version $($manifest.version) != project version $version" }

Write-Host "AURORA_VERSION_SYNC_OK version=$version androidCode=$androidCode" -ForegroundColor Green
