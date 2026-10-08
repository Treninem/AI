$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptName = $MyInvocation.MyCommand.Name
if ($scriptName -notmatch '^AuroraFox-V1\.[23]-Repair-Windows\.reassemble\.ps1$') {
    throw "Unexpected repair reassembly script name: $scriptName"
}
$base = $scriptName -replace '\.reassemble\.ps1$', '.exe'
$sums = Join-Path $root ($base -replace '\.exe$', '-SHA256.txt')
if (-not (Test-Path -LiteralPath $sums)) { throw "Repair checksum file is missing: $sums" }

$entries = @()
foreach ($line in Get-Content -LiteralPath $sums) {
    if ($line -cnotmatch '^([0-9a-f]{64})  ([^\\/]+)$') { throw "Invalid repair checksum entry: $line" }
    $entries += [pscustomobject]@{ Hash = $Matches[1]; Name = $Matches[2] }
}
if ($entries.Count -lt 3 -or $entries[0].Name -cne $base) { throw 'Repair checksum manifest is incomplete' }
$parts = @(Get-ChildItem -LiteralPath $root -File -Filter "$base.part-*" | Sort-Object Name)
if ($parts.Count -ne ($entries.Count - 1)) { throw 'Repair installer part count differs from checksum manifest' }
$output = Join-Path $root $base
Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
for ($i = 0; $i -lt $parts.Count; $i++) {
    if ($parts[$i].Name -cne $entries[$i + 1].Name) { throw "Unexpected repair installer part: $($parts[$i].Name)" }
    $actual = (Get-FileHash -LiteralPath $parts[$i].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $entries[$i + 1].Hash) { throw "Repair installer part checksum mismatch: $($parts[$i].Name)" }
}

try {
    $stream = [IO.File]::Open($output, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        foreach ($part in $parts) {
            $inputStream = [IO.File]::OpenRead($part.FullName)
            try { $inputStream.CopyTo($stream) } finally { $inputStream.Dispose() }
        }
    } finally { $stream.Dispose() }
    $actual = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $entries[0].Hash) { throw 'Reassembled repair installer checksum mismatch' }
} catch {
    Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
    throw
}
Write-Host "AuroraFox repair installer reconstructed and SHA-256 verified: $output" -ForegroundColor Green
