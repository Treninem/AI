$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root

$tracked = @(
    'project/version.json',
    'project.godot',
    'export_presets.cfg',
    'update/manifest.template.json',
    'CHANGELOG.md',
    'evolution.log'
)
$original = @{}
foreach ($path in $tracked) {
    if (Test-Path -LiteralPath $path) { $original[$path] = [IO.File]::ReadAllBytes((Resolve-Path $path)) }
}

function Restore-Tracked {
    foreach ($path in $tracked) {
        if ($original.ContainsKey($path)) {
            [IO.File]::WriteAllBytes((Join-Path $root $path), $original[$path])
        }
    }
}

function Parts([string]$Version) {
    return @($Version.TrimStart('V','v').Split('.') | ForEach-Object { [int]$_ })
}

$base = Get-Content project/version.json -Raw | ConvertFrom-Json
$baseParts = Parts ([string]$base.numeric)
$baseCode = [int]$base.android_version_code

try {
    $cases = @(
        @{ bump='build'; expected=@($baseParts[0], $baseParts[1], $baseParts[2], ($baseParts[3] + 1)) },
        @{ bump='patch'; expected=@($baseParts[0], $baseParts[1], ($baseParts[2] + 1), 0) },
        @{ bump='minor'; expected=@($baseParts[0], ($baseParts[1] + 1), 0, 0) },
        @{ bump='major'; expected=@(($baseParts[0] + 1), 0, 0, 0) }
    )

    foreach ($case in $cases) {
        Restore-Tracked
        & powershell -NoProfile -ExecutionPolicy Bypass -File .\build\set_version.ps1 -Bump $case.bump -Reason "CI version policy $($case.bump)"
        if ($LASTEXITCODE -ne 0) { throw "set_version failed for $($case.bump)" }
        $state = Get-Content project/version.json -Raw | ConvertFrom-Json
        $actual = Parts ([string]$state.numeric)
        if (($actual -join '.') -ne ($case.expected -join '.')) {
            throw "$($case.bump) bump produced $($actual -join '.') expected $($case.expected -join '.')"
        }
        if ([int]$state.android_version_code -ne ($baseCode + 1)) {
            throw "$($case.bump) bump did not increment Android versionCode exactly once"
        }
        & powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\version_sync_test.ps1
        if ($LASTEXITCODE -ne 0) { throw "version sync failed after $($case.bump) bump" }
    }

    Restore-Tracked
    $same = [string]$base.numeric
    & powershell -NoProfile -ExecutionPolicy Bypass -File .\build\set_version.ps1 -Version $same -Reason 'must fail'
    if ($LASTEXITCODE -eq 0) { throw 'set_version accepted the already-current version' }
    $global:LASTEXITCODE = 0

    Restore-Tracked
    $lower = "$($baseParts[0]).$($baseParts[1]).$($baseParts[2]).0"
    if ($lower -eq $same) {
        $lower = "0.0.0.0"
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File .\build\set_version.ps1 -Version $lower -Reason 'must fail downgrade'
    if ($LASTEXITCODE -eq 0) { throw 'set_version accepted a non-newer explicit version' }
    $global:LASTEXITCODE = 0

    Write-Host 'AURORA_VERSION_POLICY_EXECUTION_OK' -ForegroundColor Green
} finally {
    Restore-Tracked
}
