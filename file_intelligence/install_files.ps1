param(
    [string]$StateFile = "",
    [switch]$PreparePortable
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppRoot = Split-Path -Parent $Root
$RuntimeScript = Join-Path $AppRoot 'runtime\ensure_uv.ps1'
$RuntimeRoot = Join-Path $AppRoot 'runtime\windows'
$Requirements = Join-Path $Root 'requirements.txt'
$OcrPrepare = Join-Path $Root 'prepare_windows_ocr.ps1'
$Venv = Join-Path $Root '.venv'
$VenvPython = Join-Path $Venv 'Scripts\python.exe'

function Set-Stage([string]$Name, [int]$Progress, [string]$Message) {
    Write-Host ("[{0,3}%] {1}: {2}" -f $Progress, $Name, $Message) -ForegroundColor Cyan
    if ($StateFile) {
        $parent = Split-Path -Parent $StateFile
        if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        $payload = @{ stage=$Name; progress=$Progress; message=$Message; time=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds() } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($StateFile, $payload, (New-Object Text.UTF8Encoding($false)))
    }
}

try {
    Set-Stage 'runtime' 5 'Preparing AuroraFox managed Python runtime'
    if (-not (Test-Path -LiteralPath $RuntimeScript)) { throw "runtime/ensure_uv.ps1 was not found: $RuntimeScript" }
    $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $RuntimeScript -RuntimeRoot $RuntimeRoot
    if ($LASTEXITCODE -ne 0) { throw 'Failed to prepare managed Python 3.11.' }
    $uv = Join-Path $RuntimeRoot 'uv\uv.exe'
    if (-not (Test-Path -LiteralPath $uv)) { throw "uv.exe was not found: $uv" }
    $env:UV_PYTHON_INSTALL_DIR = Join-Path $RuntimeRoot 'python'
    $env:UV_CACHE_DIR = Join-Path $RuntimeRoot 'cache'
    $env:UV_PYTHON_PREFERENCE = 'only-managed'
    $managedPython = ((& $uv python find 3.11) | Select-Object -Last 1).Trim()
    if (-not (Test-Path -LiteralPath $managedPython)) { throw "Managed Python 3.11 was not found: $managedPython" }

    Set-Stage 'ocr' 20 'Preparing pinned offline rus+eng OCR runtime'
    if (-not (Test-Path -LiteralPath $OcrPrepare)) { throw "OCR prepare helper was not found: $OcrPrepare" }
    $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $OcrPrepare -RuntimeRoot (Join-Path $Root 'ocr_runtime')
    if ($LASTEXITCODE -ne 0) { throw 'Failed to prepare local OCR runtime.' }

    if ($PreparePortable) {
        Set-Stage 'portable' 35 'Building relocatable File Intelligence Python bundle'
        $portablePython = Join-Path $Root 'python'
        $vendor = Join-Path $Root 'vendor'
        if (Test-Path -LiteralPath $portablePython) { Remove-Item -LiteralPath $portablePython -Recurse -Force }
        if (Test-Path -LiteralPath $vendor) { Remove-Item -LiteralPath $vendor -Recurse -Force }
        Copy-Item -LiteralPath (Split-Path -Parent $managedPython) -Destination $portablePython -Recurse -Force
        New-Item -ItemType Directory -Force -Path $vendor | Out-Null
        & $uv pip install --python $managedPython --target $vendor --requirements $Requirements
        if ($LASTEXITCODE -ne 0) { throw 'Failed to build portable File Intelligence dependencies.' }
        $portableExe = Join-Path $portablePython 'python.exe'
        if (-not (Test-Path -LiteralPath $portableExe)) { throw "Portable Python missing: $portableExe" }
        $oldPath = $env:PYTHONPATH
        try {
            $env:PYTHONPATH = $vendor
            & $portableExe -c "import pypdf,pypdfium2,PIL,fastapi; import local_ocr; assert local_ocr.health()['available']; print('AURORA_FILE_PORTABLE_READY')"
            if ($LASTEXITCODE -ne 0) { throw 'Portable File Intelligence verification failed.' }
        } finally { $env:PYTHONPATH = $oldPath }
    } else {
        Set-Stage 'venv' 35 'Creating isolated File Intelligence environment'
        if (-not (Test-Path -LiteralPath $VenvPython)) {
            & $uv venv --python 3.11 $Venv
            if ($LASTEXITCODE -ne 0) { throw 'Failed to create File Intelligence environment.' }
        }
        Set-Stage 'dependencies' 55 'Installing local document/image/video parsers'
        & $uv pip install --python $VenvPython --requirements $Requirements
        if ($LASTEXITCODE -ne 0) { throw 'Failed to install File Intelligence dependencies.' }
        & $VenvPython -c "import pypdf,pypdfium2,PIL,fastapi; import local_ocr; assert local_ocr.health()['available']; print('AURORA_FILE_INTELLIGENCE_READY')"
        if ($LASTEXITCODE -ne 0) { throw 'File Intelligence verification failed.' }
    }

    Set-Stage 'ready' 100 'File Intelligence with offline OCR is ready'
    Write-Host 'AuroraFox File Intelligence installed.' -ForegroundColor Green
} catch {
    Set-Stage 'error' 0 $_.Exception.Message
    throw
}
