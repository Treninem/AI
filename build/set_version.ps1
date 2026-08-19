param(
    [ValidatePattern('^[Vv]?[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')][string]$Version = '',
    [ValidateSet('major','minor','patch','build')][string]$Bump = '',
    [string]$Reason = 'AuroraFox evolution update'
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Version) -and [string]::IsNullOrWhiteSpace($Bump)) {
    throw 'Specify either -Version V<Major>.<Minor>.<Patch>.<Build> or -Bump major|minor|patch|build.'
}
if (-not [string]::IsNullOrWhiteSpace($Version) -and -not [string]::IsNullOrWhiteSpace($Bump)) {
    throw 'Use -Version or -Bump, not both.'
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$projectPath = Join-Path $root 'project.godot'
$exportPath = Join-Path $root 'export_presets.cfg'
$manifestPath = Join-Path $root 'update\manifest.template.json'
$versionPath = Join-Path $root 'project\version.json'
$changelogPath = Join-Path $root 'CHANGELOG.md'
$evolutionPath = Join-Path $root 'evolution.log'

if (-not (Test-Path -LiteralPath $versionPath)) { throw 'project/version.json is missing' }
$state = Get-Content -LiteralPath $versionPath -Raw | ConvertFrom-Json
if ([string]$state.version -notmatch '^V([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$') {
    throw 'project/version.json contains an invalid version'
}
$currentMajor = [int]$Matches[1]
$currentMinor = [int]$Matches[2]
$currentPatch = [int]$Matches[3]
$currentBuild = [int]$Matches[4]
$currentNumeric = "$currentMajor.$currentMinor.$currentPatch.$currentBuild"

if (-not [string]::IsNullOrWhiteSpace($Version)) {
    $clean = $Version.TrimStart('V','v')
    if ($clean -notmatch '^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$') { throw 'Invalid four-part version' }
    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    $patch = [int]$Matches[3]
    $build = [int]$Matches[4]
} else {
    $major = $currentMajor
    $minor = $currentMinor
    $patch = $currentPatch
    $build = $currentBuild
    switch ($Bump) {
        'major' { $major++; $minor = 0; $patch = 0; $build = 0 }
        'minor' { $minor++; $patch = 0; $build = 0 }
        'patch' { $patch++; $build++ }
        'build' { $build++ }
    }
}

$numeric = "$major.$minor.$patch.$build"
$display = "V$numeric"
$changed = $numeric -ne $currentNumeric
$androidCode = [int]$state.android_version_code
if ($androidCode -le 0) { $androidCode = 1 }
if ($changed) { $androidCode++ }
if ($androidCode -gt 2100000000) { throw 'Android versionCode limit reached.' }

function Write-AtomicUtf8([string]$Path, [string]$Text) {
    $temp = "$Path.aurora-version-tmp"
    $utf8 = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($temp, $Text, $utf8)
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

$project = Get-Content -LiteralPath $projectPath -Raw
if ($project -notmatch 'config/version="[^"]+"') { throw 'project.godot config/version is missing' }
$project = [regex]::Replace($project, 'config/version="[^"]+"', "config/version=`"$numeric`"", 1)

$export = Get-Content -LiteralPath $exportPath -Raw
if ($export -notmatch 'version/name="[^"]+"') { throw 'Android version/name is missing' }
if ($export -notmatch 'version/code=[0-9]+') { throw 'Android version/code is missing' }
$export = [regex]::Replace($export, 'version/name="[^"]+"', "version/name=`"$numeric`"", 1)
$export = [regex]::Replace($export, 'version/code=[0-9]+', "version/code=$androidCode", 1)

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifest.version = $numeric
$manifestText = ($manifest | ConvertTo-Json -Depth 10) + "`n"

$state.version = $display
$state.numeric = $numeric
$state.major = $major
$state.minor = $minor
$state.patch = $patch
$state.build = $build
$state.android_version_code = $androidCode
$state.status = 'evolving'
$state.auto_increment = $true
$state.updated_at = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$state.reason = $Reason
$stateText = ($state | ConvertTo-Json -Depth 10) + "`n"

$date = [DateTime]::UtcNow.ToString('yyyy-MM-dd')
$stamp = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$entry = "## $display - $date`n`n- $Reason`n`n"
if (Test-Path -LiteralPath $changelogPath) {
    $changelog = Get-Content -LiteralPath $changelogPath -Raw
} else {
    $changelog = "# AuroraFox Changelog`n`n"
}
if ($changelog -notmatch [regex]::Escape("## $display - $date")) {
    if ($changelog.StartsWith("# AuroraFox Changelog`n`n")) {
        $changelog = "# AuroraFox Changelog`n`n" + $entry + $changelog.Substring("# AuroraFox Changelog`n`n".Length)
    } else {
        $changelog = "# AuroraFox Changelog`n`n" + $entry + $changelog
    }
}
$evolution = ''
if (Test-Path -LiteralPath $evolutionPath) { $evolution = Get-Content -LiteralPath $evolutionPath -Raw }
$evolution += "[$stamp] $display - $Reason`n"

if ($project -notmatch ('config/version="' + [regex]::Escape($numeric) + '"')) { throw 'Generated project.godot validation failed' }
if ($export -notmatch ('version/name="' + [regex]::Escape($numeric) + '"')) { throw 'Generated Android version/name validation failed' }
if ($export -notmatch ('version/code=' + $androidCode + '(?:\r?\n|$)')) { throw 'Generated Android version/code validation failed' }
if ([string](($manifestText | ConvertFrom-Json).version) -ne $numeric) { throw 'Generated update manifest validation failed' }
if ([string](($stateText | ConvertFrom-Json).version) -ne $display) { throw 'Generated version.json validation failed' }

$backupDir = Join-Path $root 'build\private\version-backup'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$backupStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupMap = @{}
$filesToBackup = @($projectPath, $exportPath, $manifestPath, $versionPath, $changelogPath, $evolutionPath)
foreach ($path in $filesToBackup) {
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $backupPath = Join-Path $backupDir ($backupStamp + '-' + (Split-Path $path -Leaf))
    Copy-Item -LiteralPath $path -Destination $backupPath -Force
    $backupMap[$path] = $backupPath
}

try {
    Write-AtomicUtf8 $projectPath $project
    Write-AtomicUtf8 $exportPath $export
    Write-AtomicUtf8 $manifestPath $manifestText
    Write-AtomicUtf8 $versionPath $stateText
    Write-AtomicUtf8 $changelogPath $changelog
    Write-AtomicUtf8 $evolutionPath $evolution

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\version_sync_test.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Version synchronization test failed after update' }
} catch {
    $originalError = $_
    foreach ($path in $filesToBackup) {
        if ($backupMap.ContainsKey($path)) {
            Copy-Item -LiteralPath $backupMap[$path] -Destination $path -Force
        } elseif (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
    throw $originalError
}

Write-Host "AuroraFox version synchronized: $display (Android versionCode=$androidCode)" -ForegroundColor Green
Write-Host 'Updated: project/version.json, project.godot, export_presets.cfg, update/manifest.template.json, CHANGELOG.md, evolution.log'
Write-Host "Release tag: v$numeric"
