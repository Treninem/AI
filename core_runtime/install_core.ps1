param(
    [string]$StateFile = "",
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$EngineDir = Join-Path $Root 'engine'
$MetaFile = Join-Path $Root 'engine.json'
$UserAgent = 'AuroraFox-Core/1.2'

function Set-Stage([string]$Name, [int]$Progress, [string]$Message, [hashtable]$Extra = @{}) {
    $Progress = [Math]::Max(0, [Math]::Min(100, $Progress))
    Write-Host ("[{0,3}%] {1}: {2}" -f $Progress, $Name, $Message) -ForegroundColor Cyan
    if ($StateFile) {
        $parent = Split-Path -Parent $StateFile
        if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        $payload = @{
            stage = $Name
            progress = $Progress
            message = $Message
            time = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        }
        foreach ($key in $Extra.Keys) { $payload[$key] = $Extra[$key] }
        $json = $payload | ConvertTo-Json -Compress -Depth 6
        $tmp = "$StateFile.tmp"
        [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $StateFile -Force
    }
}

function Get-Json([string]$Uri) {
    return Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ 'User-Agent' = $UserAgent; 'Accept' = 'application/vnd.github+json' } -TimeoutSec 45
}

function Remove-Tree([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq 6) { throw }
            Start-Sleep -Milliseconds (250 * $attempt)
        }
    }
}

function Test-CoreExecutable([string]$Executable) {
    $probeRoot = Join-Path $env:TEMP ('AuroraFox-Core-Probe-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $probeRoot | Out-Null
    $stdout = Join-Path $probeRoot 'stdout.txt'
    $stderr = Join-Path $probeRoot 'stderr.txt'
    try {
        $process = Start-Process -FilePath $Executable -ArgumentList @('--version') -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $text = ''
        if (Test-Path -LiteralPath $stdout) { $text += (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue) }
        if (Test-Path -LiteralPath $stderr) { $text += (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue) }
        if ($process.ExitCode -ne 0) { throw "llama-server --version failed with code $($process.ExitCode): $text" }
        if ($text -notmatch '(?i)(llama|version|build)') { throw "Unexpected Core Engine version output: $text" }
        return $text.Trim()
    } finally {
        Remove-Tree $probeRoot
    }
}

try {
    $existingServer = Join-Path $EngineDir 'llama-server.exe'
    if (-not $Force -and (Test-Path -LiteralPath $existingServer) -and (Test-Path -LiteralPath $MetaFile)) {
        $version = Test-CoreExecutable $existingServer
        Set-Stage 'ready' 100 'AuroraFox Core Engine already installed' @{ engine = $existingServer; reused = $true; version = $version }
        exit 0
    }

    Set-Stage 'release' 5 'Resolving verified llama.cpp runtime release'
    $latest = Get-Json 'https://api.github.com/repos/ggml-org/llama.cpp/releases/latest'
    $nightlyTag = ''
    if ([string]$latest.body -match '/releases/tag/(b[0-9]+)') { $nightlyTag = $Matches[1] }
    if (-not $nightlyTag) {
        $tagFile = Join-Path $env:TEMP ('AuroraFox-nightly-tag-' + [Guid]::NewGuid().ToString('N') + '.txt')
        try {
            Invoke-WebRequest -Uri 'https://github.com/ggml-org/llama.cpp/releases/latest/download/nightly-tag.txt' -OutFile $tagFile -Headers @{ 'User-Agent' = $UserAgent } -UseBasicParsing -TimeoutSec 45
            $nightlyTag = (Get-Content -LiteralPath $tagFile -Raw).Trim()
        } finally {
            if (Test-Path -LiteralPath $tagFile) { Remove-Item -LiteralPath $tagFile -Force }
        }
    }
    if ($nightlyTag -notmatch '^b[0-9]+$') { throw "Cannot resolve llama.cpp binary build tag from stable release $($latest.tag_name)." }

    $release = Get-Json ("https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/{0}" -f $nightlyTag)
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    $pattern = if ($arch -eq 'arm64') { 'llama-*-bin-win-cpu-arm64.zip' } else { 'llama-*-bin-win-cpu-x64.zip' }
    $asset = @($release.assets | Where-Object { $_.name -like $pattern }) | Select-Object -First 1
    if (-not $asset) { throw "Windows CPU runtime asset not found for $nightlyTag ($arch)." }
    $digest = [string]$asset.digest
    if ($digest -notmatch '^sha256:([0-9a-fA-F]{64})$') { throw "GitHub release asset has no usable SHA-256 digest: $($asset.name)" }
    $expectedHash = $Matches[1].ToLowerInvariant()

    Set-Stage 'download' 18 ("Downloading AuroraFox Core Engine {0}" -f $nightlyTag) @{ tag = $nightlyTag; asset = [string]$asset.name }
    $tempRoot = Join-Path $env:TEMP ('AuroraFox-Core-' + [Guid]::NewGuid().ToString('N'))
    $zip = Join-Path $tempRoot 'engine.zip'
    $extract = Join-Path $tempRoot 'extract'
    New-Item -ItemType Directory -Force -Path $tempRoot,$extract | Out-Null
    try {
        Invoke-WebRequest -Uri ([string]$asset.browser_download_url) -OutFile $zip -Headers @{ 'User-Agent' = $UserAgent } -UseBasicParsing -TimeoutSec 600
        if (-not (Test-Path -LiteralPath $zip)) { throw 'Core Engine archive was not downloaded.' }

        Set-Stage 'verify' 52 'Verifying Core Engine SHA-256'
        $actualHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) { throw "Core Engine SHA-256 mismatch. expected=$expectedHash actual=$actualHash" }

        Set-Stage 'extract' 68 'Extracting AuroraFox Core Engine'
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $server = Get-ChildItem -LiteralPath $extract -Recurse -File -Filter 'llama-server.exe' | Select-Object -First 1
        if (-not $server) { throw 'Verified archive does not contain llama-server.exe.' }
        $payloadRoot = $server.Directory.FullName

        $nextDir = "$EngineDir.next"
        $backupDir = "$EngineDir.previous"
        Remove-Tree $nextDir
        Remove-Tree $backupDir
        New-Item -ItemType Directory -Force -Path $nextDir | Out-Null
        Copy-Item -Path (Join-Path $payloadRoot '*') -Destination $nextDir -Recurse -Force
        if (-not (Test-Path -LiteralPath (Join-Path $nextDir 'llama-server.exe'))) { throw 'Prepared Core Engine payload is incomplete.' }

        Set-Stage 'activate' 84 'Activating verified Core Engine'
        if (Test-Path -LiteralPath $EngineDir) { Move-Item -LiteralPath $EngineDir -Destination $backupDir -Force }
        try {
            Move-Item -LiteralPath $nextDir -Destination $EngineDir -Force
        } catch {
            if (Test-Path -LiteralPath $backupDir) { Move-Item -LiteralPath $backupDir -Destination $EngineDir -Force }
            throw
        }
        Remove-Tree $backupDir

        $meta = @{
            provider = 'llama.cpp'
            role = 'AuroraFox Core Engine'
            stable_release = [string]$latest.tag_name
            binary_tag = $nightlyTag
            asset = [string]$asset.name
            sha256 = $actualHash
            installed_at = [DateTimeOffset]::UtcNow.ToString('o')
            source = 'https://github.com/ggml-org/llama.cpp'
        } | ConvertTo-Json -Depth 5
        [IO.File]::WriteAllText($MetaFile, $meta, (New-Object Text.UTF8Encoding($false)))

        Set-Stage 'smoke' 94 'Checking Core Engine executable'
        $serverExe = Join-Path $EngineDir 'llama-server.exe'
        $versionOutput = Test-CoreExecutable $serverExe

        Set-Stage 'ready' 100 'AuroraFox Core Engine is ready' @{ engine = $serverExe; tag = $nightlyTag; sha256 = $actualHash; version = $versionOutput }
        Write-Host 'AuroraFox Core Engine installed successfully.' -ForegroundColor Green
    } finally {
        Remove-Tree $tempRoot
    }
} catch {
    Set-Stage 'error' 0 $_.Exception.Message
    throw
}
