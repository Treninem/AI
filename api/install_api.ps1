param(
    [string]$StateFile = ""
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ApiRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppRoot = Split-Path -Parent $ApiRoot
$RuntimeScript = Join-Path $AppRoot 'runtime\ensure_uv.ps1'
$RuntimeRoot = Join-Path $AppRoot 'runtime\windows'
$Venv = Join-Path $ApiRoot '.venv'
$Python = Join-Path $Venv 'Scripts\python.exe'
$Requirements = Join-Path $ApiRoot 'requirements.txt'

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
    Set-Stage 'runtime' 10 'Preparing AuroraFox managed Python runtime'
    if (-not (Test-Path -LiteralPath $RuntimeScript)) { throw "runtime/ensure_uv.ps1 was not found: $RuntimeScript" }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $RuntimeScript -RuntimeRoot $RuntimeRoot | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to prepare managed Python runtime.' }

    $uv = Join-Path $RuntimeRoot 'uv\uv.exe'
    if (-not (Test-Path -LiteralPath $uv)) { throw "uv.exe was not found: $uv" }
    $env:UV_PYTHON_INSTALL_DIR = Join-Path $RuntimeRoot 'python'
    $env:UV_CACHE_DIR = Join-Path $RuntimeRoot 'cache'
    $env:UV_PYTHON_PREFERENCE = 'only-managed'

    Set-Stage 'venv' 35 'Creating isolated AuroraFox API environment'
    if (-not (Test-Path -LiteralPath $Python)) {
        & $uv venv --python 3.11 $Venv
        if ($LASTEXITCODE -ne 0) { throw 'Failed to create AuroraFox API environment.' }
    }

    Set-Stage 'dependencies' 65 'Installing AuroraFox API dependencies'
    & $uv pip install --python $Python --requirements $Requirements
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install AuroraFox API dependencies.' }

    Set-Stage 'verify' 90 'Verifying AuroraFox API imports'
    & $Python -c "import fastapi, uvicorn, pydantic, requests; import api.app; print('AURORAFOX_API_READY')"
    if ($LASTEXITCODE -ne 0) { throw 'AuroraFox API import verification failed.' }

    Set-Stage 'ready' 100 'AuroraFox API runtime is ready'
} catch {
    Set-Stage 'error' 0 $_.Exception.Message
    throw
}
