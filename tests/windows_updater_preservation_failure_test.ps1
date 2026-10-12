$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$updater = Join-Path $repo 'update\windows_updater.ps1'
$sourceText = Get-Content -LiteralPath $updater -Raw

# A failed preservation must stop before the old install is renamed. Extract
# the trusted helper so the test can deterministically hold a target file open.
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($updater, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) { throw 'Updater script has PowerShell parse errors' }
$definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Preserve-LocalRuntime' }, $true)
if (-not $definition) { throw 'Preserve-LocalRuntime function missing' }
Invoke-Expression $definition.Extent.Text
function Write-UpdateLog([string]$Message) { }

$temporaryRoot = $env:RUNNER_TEMP
if ([string]::IsNullOrWhiteSpace($temporaryRoot)) { $temporaryRoot = Join-Path $repo 'work' }
$root = Join-Path $temporaryRoot ('aurorafox-preserve-failure-' + [guid]::NewGuid().ToString('N'))
$old = Join-Path $root 'old'
$new = Join-Path $root 'new'
$HealthFile = Join-Path $root 'health.ok'
$sourceFile = Join-Path $old 'runtime\windows\python\keep.txt'
$targetFile = Join-Path $new 'runtime\windows\python\keep.txt'
$locked = $null
try {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $sourceFile),(Split-Path -Parent $targetFile) | Out-Null
    Set-Content -LiteralPath $sourceFile -Value 'owner-runtime' -Encoding ASCII
    Set-Content -LiteralPath $targetFile -Value 'packaged-runtime' -Encoding ASCII
    $locked = [IO.File]::Open($targetFile, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $failed = $false
    try { Preserve-LocalRuntime -OldRoot $old -NewRoot $new } catch { $failed = $true }
    if (-not $failed) { throw 'Preservation failure was swallowed: update would report false success' }
    if ((Get-Content -LiteralPath $sourceFile -Raw).Trim() -ne 'owner-runtime') { throw 'Original owner runtime changed' }
    if (Test-Path -LiteralPath $HealthFile) { throw 'Health marker written after failed preservation' }

    $preserveCall = $sourceText.IndexOf('Preserve-LocalRuntime -OldRoot $InstallDir -NewRoot $staging', [StringComparison]::Ordinal)
    $switch = $sourceText.IndexOf("Write-UpdateLog 'Switching application directories'", [StringComparison]::Ordinal)
    if ($preserveCall -lt 0 -or $switch -lt 0 -or $preserveCall -ge $switch) {
        throw 'Runtime preservation must finish before switching installation directories'
    }
    Write-Host 'AURORA_WINDOWS_UPDATER_PRESERVATION_FAILURE_OK' -ForegroundColor Green
} finally {
    if ($locked) { $locked.Dispose() }
    $resolvedRoot = [IO.Path]::GetFullPath($root)
    $resolvedParent = [IO.Path]::GetFullPath($temporaryRoot).TrimEnd('\') + '\'
    if (-not $resolvedRoot.StartsWith($resolvedParent, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path' }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
