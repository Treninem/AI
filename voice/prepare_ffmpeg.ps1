param(
    [string]$Destination = "",
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$voiceRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Destination)) {
    $Destination = Join-Path $voiceRoot 'runtime\ffmpeg'
}
$Destination = [IO.Path]::GetFullPath($Destination)
$binDir = Join-Path $Destination 'bin'
$ffmpegExe = Join-Path $binDir 'ffmpeg.exe'

function Test-SharedFfmpeg([string]$Bin) {
    if (-not (Test-Path -LiteralPath (Join-Path $Bin 'ffmpeg.exe'))) { return $false }
    $avcodec = @(Get-ChildItem -LiteralPath $Bin -Filter 'avcodec-*.dll' -File -ErrorAction SilentlyContinue)
    $avformat = @(Get-ChildItem -LiteralPath $Bin -Filter 'avformat-*.dll' -File -ErrorAction SilentlyContinue)
    $avutil = @(Get-ChildItem -LiteralPath $Bin -Filter 'avutil-*.dll' -File -ErrorAction SilentlyContinue)
    return $avcodec.Count -gt 0 -and $avformat.Count -gt 0 -and $avutil.Count -gt 0
}

if (-not $Force -and (Test-SharedFfmpeg $binDir)) {
    Write-Host "AuroraFox shared FFmpeg already prepared: $binDir" -ForegroundColor Green
    Write-Output $binDir
    exit 0
}

# ffmpeg.org does not publish Windows binaries itself; its official download
# page links BtbN/FFmpeg-Builds as a Windows build provider. TorchCodec requires
# a shared FFmpeg build on Windows, so use the provider's LGPL shared release.
$releaseApi = 'https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/tags/latest'
$headers = @{
    'Accept' = 'application/vnd.github+json'
    'User-Agent' = 'AuroraFox-Voice-Installer'
    'X-GitHub-Api-Version' = '2022-11-28'
}

Write-Host 'Resolving current BtbN shared FFmpeg release linked by ffmpeg.org...' -ForegroundColor Cyan
$release = Invoke-RestMethod -Uri $releaseApi -Headers $headers -Method Get
if ($null -eq $release -or $null -eq $release.assets) {
    throw 'Could not resolve the FFmpeg release assets.'
}

$assets = @($release.assets)
$preferred = @($assets | Where-Object {
    [string]$_.name -match '^ffmpeg-n7\.1-.*win64-lgpl-shared.*\.zip$'
})
if ($preferred.Count -eq 0) {
    $preferred = @($assets | Where-Object {
        [string]$_.name -match '^ffmpeg-.*win64-lgpl-shared.*\.zip$' -and
        [string]$_.name -notmatch 'winarm64'
    })
}
if ($preferred.Count -eq 0) {
    throw 'No Windows x64 LGPL shared FFmpeg ZIP was found in the current BtbN release.'
}

# Prefer a release-branch build over master when multiple matching assets exist.
$asset = $preferred | Sort-Object @{Expression={ if ([string]$_.name -match 'master') { 1 } else { 0 } }}, name | Select-Object -First 1
$checksumsAsset = $assets | Where-Object { [string]$_.name -eq 'checksums.sha256' } | Select-Object -First 1
if ($null -eq $checksumsAsset) {
    throw 'The FFmpeg release does not contain checksums.sha256; refusing an unverified download.'
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('aurorafox-ffmpeg-' + [guid]::NewGuid().ToString('N'))
$zipPath = Join-Path $tempRoot ([string]$asset.name)
$checksumsPath = Join-Path $tempRoot 'checksums.sha256'
$extractPath = Join-Path $tempRoot 'extract'
New-Item -ItemType Directory -Force -Path $tempRoot,$extractPath | Out-Null

try {
    Write-Host ("Downloading {0}..." -f $asset.name) -ForegroundColor Cyan
    Invoke-WebRequest -Uri ([string]$asset.browser_download_url) -Headers $headers -OutFile $zipPath
    Invoke-WebRequest -Uri ([string]$checksumsAsset.browser_download_url) -Headers $headers -OutFile $checksumsPath

    $expected = ''
    foreach ($line in Get-Content -LiteralPath $checksumsPath) {
        if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+)$') {
            if ($Matches[2].Trim() -eq [string]$asset.name) {
                $expected = $Matches[1].ToLowerInvariant()
                break
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($expected)) {
        throw "No SHA-256 entry for $($asset.name) was found in checksums.sha256."
    }
    $actual = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "FFmpeg SHA-256 mismatch. Expected $expected, got $actual."
    }

    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force
    $foundExe = Get-ChildItem -LiteralPath $extractPath -Recurse -Filter 'ffmpeg.exe' -File | Select-Object -First 1
    if ($null -eq $foundExe) { throw 'ffmpeg.exe was not found in the verified archive.' }
    $sourceBin = $foundExe.Directory.FullName
    if (-not (Test-SharedFfmpeg $sourceBin)) {
        throw 'Downloaded FFmpeg archive is not a shared build with avcodec/avformat/avutil DLLs.'
    }

    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    Copy-Item -Path (Join-Path $sourceBin '*') -Destination $binDir -Recurse -Force

    $license = Get-ChildItem -LiteralPath $extractPath -Recurse -File | Where-Object {
        $_.Name -match '^(LICENSE|COPYING)(\..*)?$'
    } | Select-Object -First 1
    if ($null -ne $license) {
        Copy-Item -LiteralPath $license.FullName -Destination (Join-Path $Destination $license.Name) -Force
    }

    $metadata = [ordered]@{
        provider = 'BtbN/FFmpeg-Builds'
        provider_reason = 'linked by ffmpeg.org Windows downloads'
        release_tag = [string]$release.tag_name
        asset = [string]$asset.name
        sha256 = $actual
        source_url = [string]$asset.browser_download_url
        prepared_at = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    $metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Destination 'source.json') -Encoding UTF8

    if (-not (Test-SharedFfmpeg $binDir)) { throw 'Local shared FFmpeg validation failed after extraction.' }
    & $ffmpegExe -version | Select-Object -First 1
    if ($LASTEXITCODE -ne 0) { throw 'Local ffmpeg.exe failed to start.' }

    Write-Host "AuroraFox shared FFmpeg prepared and SHA-256 verified: $binDir" -ForegroundColor Green
    Write-Output $binDir
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
