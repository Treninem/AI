param(
    [string]$Version = "0.12.0",
    [string]$Destination = ""
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$runtimeRoot = $PSScriptRoot
if (-not $Destination) { $Destination = Join-Path $runtimeRoot 'uv' }
$uvExe = Join-Path $Destination 'uv.exe'
$marker = Join-Path $Destination 'version.txt'

if ((Test-Path $uvExe) -and (Test-Path $marker) -and ((Get-Content $marker -Raw).Trim() -eq $Version)) {
    Write-Host "AuroraFox uv runtime $Version already prepared." -ForegroundColor Green
    exit 0
}

$arch = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
$asset = switch ($arch) {
    'x64' { 'uv-x86_64-pc-windows-msvc.zip' }
    'arm64' { 'uv-aarch64-pc-windows-msvc.zip' }
    default { throw "Unsupported Windows architecture for AuroraFox runtime: $arch" }
}

$base = "https://github.com/astral-sh/uv/releases/download/$Version"
$temp = Join-Path ([IO.Path]::GetTempPath()) "aurorafox-uv-$Version-$([Guid]::NewGuid().ToString('N'))"
$zip = Join-Path $temp $asset
$checksumFile = "$zip.sha256"
$extract = Join-Path $temp 'extract'
New-Item -ItemType Directory -Force -Path $temp,$extract | Out-Null

try {
    Write-Host "Downloading pinned uv $Version ($asset)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri "$base/$asset" -OutFile $zip
    Invoke-WebRequest -Uri "$base/$asset.sha256" -OutFile $checksumFile

    $checksumText = (Get-Content $checksumFile -Raw).Trim()
    if ($checksumText -notmatch '(?i)\b([0-9a-f]{64})\b') { throw 'Invalid uv checksum file' }
    $expected = $Matches[1].ToLowerInvariant()
    $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "uv SHA-256 mismatch: $actual != $expected" }

    Expand-Archive -Path $zip -DestinationPath $extract -Force
    $found = Get-ChildItem $extract -Recurse -Filter 'uv.exe' | Select-Object -First 1
    if (-not $found) { throw 'uv.exe was not found in verified release archive' }

    if (Test-Path $Destination) { Remove-Item $Destination -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Copy-Item $found.FullName $uvExe -Force
    $uvx = Get-ChildItem $extract -Recurse -Filter 'uvx.exe' | Select-Object -First 1
    if ($uvx) { Copy-Item $uvx.FullName (Join-Path $Destination 'uvx.exe') -Force }
    $Version | Set-Content -Path $marker -Encoding ASCII -NoNewline

    & $uvExe --version
    if ($LASTEXITCODE -ne 0) { throw 'Prepared uv.exe failed its startup check' }
    Write-Host "AuroraFox local uv runtime ready: $uvExe" -ForegroundColor Green
} finally {
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}
