$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '../android_plugin/setup_native.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Native setup parse failed' }
$definition = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Download-IfMissing'
}, $true)
if (-not $definition) { throw 'Native download helper missing' }
# Execute only the repository helper, never the native setup's download/build body.
Invoke-Expression $definition.Extent.Text
$script:calls = 0
$script:failures = 1
function Invoke-WebRequest {
    param($Uri, $OutFile, $TimeoutSec)
    if ($TimeoutSec -ne 600) { throw 'Missing bounded request timeout' }
    $script:calls++
    if ($script:calls -le $script:failures) {
        Set-Content -LiteralPath $OutFile 'partial-corrupt'
        throw 'Injected interrupted network response'
    }
    Set-Content -LiteralPath $OutFile 'complete-pinned-fixture'
}
function Start-Sleep { param($Seconds) }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('aurora-native-download-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$dest = Join-Path $fixture 'asset.aar'
try {
    Download-IfMissing 'https://example.invalid/fixture' $dest
    if ($script:calls -ne 2 -or (Get-Content $dest).Trim() -ne 'complete-pinned-fixture' -or (Test-Path "$dest.download")) {
        throw 'Interrupted download was not atomically replaced by the complete retry'
    }
    Download-IfMissing 'https://example.invalid/fixture' $dest
    if ($script:calls -ne 2) { throw 'Existing asset was unnecessarily downloaded' }
    Remove-Item $dest
    $script:calls = 0
    $script:failures = 10
    $refused = $false
    try { Download-IfMissing 'https://example.invalid/fixture' $dest } catch {
        if ($_.Exception.Message -notmatch 'attempt=3 HTTP=0') { throw }
        $refused = $true
    }
    if (-not $refused -or $script:calls -ne 3 -or (Test-Path $dest) -or (Test-Path "$dest.download")) {
        throw 'Failed download was cached or exceeded its retry budget'
    }
    Write-Host 'AURORA_ANDROID_NATIVE_DOWNLOAD_SMOKE_OK'
} finally {
    Remove-Item $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
