param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')][string]$Version
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$projectPath = Join-Path $root 'project.godot'
$exportPath = Join-Path $root 'export_presets.cfg'
$manifestPath = Join-Path $root 'update\manifest.template.json'

$parts = $Version.Split('.') | ForEach-Object { [int]$_ }
$major, $minor, $patch = $parts
if ($minor -gt 99 -or $patch -gt 99) {
    throw 'For Android versionCode mapping, minor and patch must be in the range 0..99.'
}
$versionCode = $major * 10000 + $minor * 100 + $patch
if ($versionCode -le 0) { $versionCode = 1 }
if ($versionCode -gt 2100000000) { throw 'Calculated Android versionCode is too large.' }

function Write-AtomicUtf8([string]$Path, [string]$Text) {
    $temp = "$Path.aurora-version-tmp"
    [IO.File]::WriteAllText($temp, $Text, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

$project = Get-Content -LiteralPath $projectPath -Raw
if ($project -notmatch 'config/version="[^"]+"') { throw 'project.godot config/version is missing' }
$project = [regex]::Replace($project, 'config/version="[^"]+"', "config/version=`"$Version`"", 1)

$export = Get-Content -LiteralPath $exportPath -Raw
if ($export -notmatch 'version/name="[^"]+"') { throw 'Android version/name is missing' }
if ($export -notmatch 'version/code=[0-9]+') { throw 'Android version/code is missing' }
$export = [regex]::Replace($export, 'version/name="[^"]+"', "version/name=`"$Version`"", 1)
$export = [regex]::Replace($export, 'version/code=[0-9]+', "version/code=$versionCode", 1)

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifest.version = $Version
$manifestText = ($manifest | ConvertTo-Json -Depth 10) + "`n"

# Validate all generated content before replacing any canonical file.
if ($project -notmatch ('config/version="' + [regex]::Escape($Version) + '"')) { throw 'Generated project.godot version validation failed' }
if ($export -notmatch ('version/name="' + [regex]::Escape($Version) + '"')) { throw 'Generated Android version/name validation failed' }
if ($export -notmatch ('version/code=' + $versionCode + '(?:\r?\n|$)')) { throw 'Generated Android version/code validation failed' }
$manifestCheck = $manifestText | ConvertFrom-Json
if ([string]$manifestCheck.version -ne $Version) { throw 'Generated update manifest validation failed' }

$backupDir = Join-Path $root 'build\private\version-backup'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$projectBackup = Join-Path $backupDir "$stamp-project.godot"
$exportBackup = Join-Path $backupDir "$stamp-export_presets.cfg"
$manifestBackup = Join-Path $backupDir "$stamp-manifest.template.json"
Copy-Item -LiteralPath $projectPath -Destination $projectBackup -Force
Copy-Item -LiteralPath $exportPath -Destination $exportBackup -Force
Copy-Item -LiteralPath $manifestPath -Destination $manifestBackup -Force

try {
    Write-AtomicUtf8 $projectPath $project
    Write-AtomicUtf8 $exportPath $export
    Write-AtomicUtf8 $manifestPath $manifestText

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\version_sync_test.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Version synchronization test failed after update' }
} catch {
    Copy-Item -LiteralPath $projectBackup -Destination $projectPath -Force
    Copy-Item -LiteralPath $exportBackup -Destination $exportPath -Force
    Copy-Item -LiteralPath $manifestBackup -Destination $manifestPath -Force
    throw
}

Write-Host "AuroraFox version synchronized: $Version (Android versionCode=$versionCode)" -ForegroundColor Green
Write-Host 'Updated: project.godot, export_presets.cfg, update/manifest.template.json'
Write-Host "Release tag: v$Version"
