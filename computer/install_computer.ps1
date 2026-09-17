$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $Root
$RuntimeRoot = Join-Path $ProjectRoot 'runtime\windows'
$EnsureUv = Join-Path $ProjectRoot 'runtime\ensure_uv.ps1'
$Uv = Join-Path $RuntimeRoot 'uv\uv.exe'
$Venv = Join-Path $Root '.venv'
$Python = Join-Path $Venv 'Scripts\python.exe'

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

if (-not (Test-Path -LiteralPath $Python)) {
    & $Uv venv --python 3.11 $Venv
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create Computer Agent environment' }
}

& $Uv pip install --python $Python -r (Join-Path $Root 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Failed to install Computer Agent dependencies' }

Write-Host ''
Write-Host 'AuroraFox Computer Agent installed.' -ForegroundColor Green
Write-Host 'System Python is not required; AuroraFox uses its managed Python 3.11 runtime.'
Write-Host 'Planning is performed by the bundled AuroraFox Core; Ollama or cloud AI is not required.'
Write-Host "Start with: $Python $Root\computer_service.py"
Write-Host 'Emergency stop while Windows automation is running: move the mouse to the upper-left corner.'
