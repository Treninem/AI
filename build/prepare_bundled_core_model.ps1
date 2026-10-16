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
$expectedBytes = 1396198496
$expectedSha = '57a1085840f497d764a7fc5d346922dbde961efb54cc792ea81d694fd846a1d8'
$url = 'https://huggingface.co/bartowski/Qwen_Qwen3.5-2B-GGUF/resolve/7d26695454df6de5fbcce2e58681e62dae06ce43/Qwen_Qwen3.5-2B-Q4_K_M.gguf?download=true'
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

function Get-CoreModelEvidence([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'missing' }
    $item = Get-Item -LiteralPath $Path
    $stream = [IO.File]::OpenRead($Path)
    try {
        $magic = New-Object byte[] 4
        $read = $stream.Read($magic, 0, 4)
        $magicText = if ($read -eq 4) { '0x' + (($magic | ForEach-Object { $_.ToString('x2') }) -join '') } else { 'short-file' }
    } finally {
        $stream.Dispose()
    }
    $sha = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    return "bytes=$($item.Length) magic=$magicText sha256=$sha"
}

New-Item -ItemType Directory -Force -Path $CacheDir,(Split-Path -Parent $Destination) | Out-Null
if (-not (Test-CoreModel $cacheFile)) {
    Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue
    $temp = $cacheFile + '.download'
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    $curlCommand = Get-Command curl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $curlCommand) {
        $curlCommand = Get-Command curl -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $curlCommand) {
        throw 'curl is required for verified AuroraFox Core weight transfer'
    }
    $downloadVerified = $false
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        Write-Host "Downloading verified AuroraFox Core weights for packaging (attempt $attempt/2)..." -ForegroundColor Cyan
        & $curlCommand.Source --location --proto '=https' --proto-redir '=https' --fail --silent --show-error --connect-timeout 30 --max-time 1500 --max-filesize $expectedBytes --output $temp $url
        $curlExit = $LASTEXITCODE
        if ($curlExit -eq 0 -and (Test-CoreModel $temp)) {
            $downloadVerified = $true
            break
        }
        $evidence = Get-CoreModelEvidence $temp
        Write-Warning "Bundled Core transfer rejected: curl_exit=$curlExit $evidence"
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
    if (-not $downloadVerified) {
        throw 'Bundled AuroraFox Core verification failed after two bounded transfers'
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
