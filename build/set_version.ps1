param(
    [Parameter(Mandatory=$true)][string]$Version
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if ($Version -notmatch '^([0-9]+)\.([0-9]+)\.([0-9]+)$') {
    throw 'Version must be semantic numeric form: MAJOR.MINOR.PATCH (example: 0.4.1)'
}
$major = [int]$Matches[1]
$minor = [int]$Matches[2]
$patch = [int]$Matches[3]
if ($minor -gt 99 -or $patch -gt 99) { throw 'MINOR and PATCH must be 0..99 for Android versionCode mapping' }
$versionCode = $major * 10000 + $minor * 100 + $patch
if ($versionCode -le 0) { $versionCode = 1 }

$projectPath = Join-Path $root 'project.godot'
$project = Get-Content $projectPath -Raw
if ($project -notmatch 'config/version="[^"]+"') { throw 'project.godot has no application/config/version' }
$project = [regex]::Replace($project, 'config/version="[^"]+"', "config/version=`"$Version`"", 1)
Set-Content -Path $projectPath -Value $project -Encoding UTF8 -NoNewline

$exportPath = Join-Path $root 'export_presets.cfg'
$export = Get-Content $exportPath -Raw
if ($export -notmatch 'version/name="[^"]+"') { throw 'export_presets.cfg has no Android version/name' }
if ($export -notmatch 'version/code=[0-9]+') { throw 'export_presets.cfg has no Android version/code' }
$export = [regex]::Replace($export, 'version/name="[^"]+"', "version/name=`"$Version`"", 1)
$export = [regex]::Replace($export, 'version/code=[0-9]+', "version/code=$versionCode", 1)
Set-Content -Path $exportPath -Value $export -Encoding UTF8 -NoNewline

$templatePath = Join-Path $root 'update/manifest.template.json'
if (Test-Path $templatePath) {
    $manifest = Get-Content $templatePath -Raw | ConvertFrom-Json
    $manifest.version = $Version
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -Path $templatePath -Encoding UTF8
}

Write-Host "AuroraFox version synchronized: $Version" -ForegroundColor Green
Write-Host "Android versionCode: $versionCode"
Write-Host "Release tag must be: v$Version"
