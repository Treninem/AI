param(
    [switch]$PreparePortable
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $Root
$RuntimeRoot = Join-Path $ProjectRoot 'runtime\windows'
$EnsureUv = Join-Path $ProjectRoot 'runtime\ensure_uv.ps1'
$Uv = Join-Path $RuntimeRoot 'uv\uv.exe'
$Venv = Join-Path $Root '.venv'
$Python = Join-Path $Venv 'Scripts\python.exe'
$PortablePython = Join-Path $Root 'python'
$PortableVendor = Join-Path $Root 'vendor'

if (-not (Test-Path -LiteralPath $EnsureUv)) {
    throw 'AuroraFox runtime bootstrap is missing: runtime/ensure_uv.ps1'
}

Write-Host 'Preparing AuroraFox managed Python runtime...' -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File $EnsureUv -RuntimeRoot $RuntimeRoot | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Uv)) {
    throw 'AuroraFox managed Python runtime setup failed'
}

$env:UV_PYTHON_INSTALL_DIR = Join-Path $RuntimeRoot 'python'
$env:UV_CACHE_DIR = Join-Path $RuntimeRoot 'cache'
$env:UV_PYTHON_PREFERENCE = 'only-managed'

if ($PreparePortable) {
    $ManagedPython = ((& $Uv python find 3.11) | Select-Object -Last 1).Trim()
    if (-not (Test-Path -LiteralPath $ManagedPython)) { throw "Managed Python 3.11 was not found: $ManagedPython" }
    if (Test-Path -LiteralPath $PortablePython) { Remove-Item -LiteralPath $PortablePython -Recurse -Force }
    if (Test-Path -LiteralPath $PortableVendor) { Remove-Item -LiteralPath $PortableVendor -Recurse -Force }
    Copy-Item -LiteralPath (Split-Path -Parent $ManagedPython) -Destination $PortablePython -Recurse -Force
    New-Item -ItemType Directory -Force -Path $PortableVendor | Out-Null
    & $Uv pip install --python $ManagedPython --target $PortableVendor -r (Join-Path $Root 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Failed to build portable Computer Agent dependencies' }
    $PortableExe = Join-Path $PortablePython 'python.exe'
    if (-not (Test-Path -LiteralPath $PortableExe)) { throw "Portable Computer Agent Python is missing: $PortableExe" }
    $PreviousPythonPath = $env:PYTHONPATH
    try {
        $env:PYTHONPATH = $PortableVendor
        & $PortableExe -c "import importlib.util as u; required=('fastapi','uvicorn','pydantic','pyautogui','PIL','pywinauto'); assert all(u.find_spec(name) for name in required); print('AURORA_COMPUTER_PORTABLE_READY')"
        if ($LASTEXITCODE -ne 0) { throw 'Portable Computer Agent verification failed' }
    } finally {
        $env:PYTHONPATH = $PreviousPythonPath
    }
} else {
    if (-not (Test-Path -LiteralPath $Python)) {
        & $Uv venv --python 3.11 $Venv
        if ($LASTEXITCODE -ne 0) { throw 'Failed to create Computer Agent environment' }
    }

    & $Uv pip install --python $Python -r (Join-Path $Root 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install Computer Agent dependencies' }
}

Write-Host ''
Write-Host 'AuroraFox Computer Agent installed.' -ForegroundColor Green
Write-Host 'System Python is not required; AuroraFox uses its managed Python 3.11 runtime.'
Write-Host 'Planning is performed by the bundled AuroraFox Core; Ollama or cloud AI is not required.'
if ($PreparePortable) {
    Write-Host "Portable runtime: $PortablePython + $PortableVendor"
} else {
    Write-Host "Start with: $Python $Root\computer_service.py"
}
Write-Host 'Emergency stop while Windows automation is running: move the mouse to the upper-left corner.'
