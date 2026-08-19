param(
    [string]$StateFile = ""
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppRoot = Split-Path -Parent $Root
$RuntimeScript = Join-Path $AppRoot 'runtime\ensure_uv.ps1'
$RuntimeRoot = Join-Path $AppRoot 'runtime\windows'
$Venv = Join-Path $Root '.venv'
$Python = Join-Path $Venv 'Scripts\python.exe'
$Requirements = Join-Path $Root 'requirements.txt'

function Set-Stage([string]$Name, [int]$Progress, [string]$Message) {
    Write-Host ("[{0,3}%] {1}: {2}" -f $Progress, $Name, $Message) -ForegroundColor Cyan
    if ($StateFile) {
        $parent = Split-Path -Parent $StateFile
        if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        $payload = @{
            stage = $Name
            progress = $Progress
            message = $Message
            time = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($StateFile, $payload, (New-Object Text.UTF8Encoding($false)))
    }
}

try {
    Set-Stage 'runtime' 5 'Preparing AuroraFox managed Python runtime'
    if (-not (Test-Path -LiteralPath $RuntimeScript)) {
        throw "runtime/ensure_uv.ps1 was not found: $RuntimeScript"
    }
    $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $RuntimeScript -RuntimeRoot $RuntimeRoot
    if ($LASTEXITCODE -ne 0) { throw 'Failed to prepare managed Python 3.11.' }
    $uv = Join-Path $RuntimeRoot 'uv\uv.exe'
    if (-not (Test-Path -LiteralPath $uv)) { throw "uv.exe was not found: $uv" }

    $env:UV_PYTHON_INSTALL_DIR = Join-Path $RuntimeRoot 'python'
    $env:UV_CACHE_DIR = Join-Path $RuntimeRoot 'cache'
    $env:UV_PYTHON_PREFERENCE = 'only-managed'

    Set-Stage 'venv' 22 'Creating isolated File Intelligence environment'
    if (-not (Test-Path -LiteralPath $Python)) {
        & $uv venv --python 3.11 $Venv
        if ($LASTEXITCODE -ne 0) { throw 'Failed to create File Intelligence environment.' }
    }

    Set-Stage 'dependencies' 42 'Installing local document image video EPUB and RAR parsers'
    & $uv pip install --python $Python --requirements $Requirements
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install File Intelligence dependencies.' }

    Set-Stage 'verify' 90 'Verifying parsers extended formats and bundled ffmpeg'
    $check = @(
        'import imageio_ffmpeg',
        'import pypdf, pypdfium2, docx, openpyxl, xlrd, pptx, PIL, py7zr, rarfile',
        'import extended_formats',
        'from pathlib import Path',
        'exe = Path(imageio_ffmpeg.get_ffmpeg_exe())',
        'assert exe.is_file(), f"ffmpeg missing: {exe}"',
        'assert callable(extended_formats.analyze_epub)',
        'assert callable(extended_formats.analyze_rar)',
        'print("AURORA_FILE_INTELLIGENCE_READY", exe, rarfile.__version__)'
    ) -join "`n"
    & $Python -c $check
    if ($LASTEXITCODE -ne 0) { throw 'File Intelligence verification failed.' }

    Set-Stage 'ready' 100 'File Intelligence is ready for local use'
    Write-Host 'AuroraFox File Intelligence installed.' -ForegroundColor Green
} catch {
    Set-Stage 'error' 0 $_.Exception.Message
    throw
}