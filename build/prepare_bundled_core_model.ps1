param(
    [Parameter(Mandatory = $true)]
    [string]$Destination,
    [string]$CacheDir = ""
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($CacheDir)) {
    $CacheDir = Join-Path $root '.ci/core-model'
}
$expectedBytes = 1282439264
$expectedSha = 'd2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5'
$url = 'https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf?download=true'
$cacheFile = Join-Path $CacheDir ($expectedSha + '.gguf')

function Test-CoreModel([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -ne $expectedBytes) { return $false }
    $stream = [IO.File]::OpenRead($Path)
    try {
        $magic = New-Object byte[] 4
        if ($stream.Read($magic, 0, 4) -ne 4) { return $false }
        if ([Text.Encoding]::ASCII.GetString($magic) -ne 'GGUF') { return $false }
    } finally {
        $stream.Dispose()
    }
    $sha = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    return $sha -eq $expectedSha
}

New-Item -ItemType Directory -Force -Path $CacheDir,(Split-Path -Parent $Destination) | Out-Null
if (-not (Test-CoreModel $cacheFile)) {
    Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue
    $temp = $cacheFile + '.download'
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    Write-Host 'Downloading verified AuroraFox Core weights for packaging...' -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $url -OutFile $temp -Headers @{ 'User-Agent' = 'AuroraFox-Build/1.3.0.0'; 'Accept-Encoding' = 'identity' }
    } catch {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        throw "Bundled AuroraFox Core download failed: $($_.Exception.Message)"
    }
    if (-not (Test-CoreModel $temp)) {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        throw 'Bundled AuroraFox Core verification failed after download'
    }
    Move-Item -LiteralPath $temp -Destination $cacheFile -Force
}

if (-not (Test-CoreModel $cacheFile)) {
    throw 'Cached AuroraFox Core weights failed verification'
}
Copy-Item -LiteralPath $cacheFile -Destination $Destination -Force
if (-not (Test-CoreModel $Destination)) {
    Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    throw 'Packaged AuroraFox Core weights failed verification after copy'
}

Write-Host "AURORAFOX_BUNDLED_CORE_READY $Destination" -ForegroundColor Green
Write-Host "bytes=$expectedBytes sha256=$expectedSha"
