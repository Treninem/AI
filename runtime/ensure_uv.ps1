param(
    [string]$Version = "0.12.1",
    [string]$RuntimeRoot = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if (-not $RuntimeRoot) {
    $RuntimeRoot = Join-Path $PSScriptRoot "windows"
}
$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$uvDir = Join-Path $RuntimeRoot "uv"
$uvExe = Join-Path $uvDir "uv.exe"
$pythonDir = Join-Path $RuntimeRoot "python"
$cacheDir = Join-Path $RuntimeRoot "cache"

New-Item -ItemType Directory -Force -Path $uvDir,$pythonDir,$cacheDir | Out-Null

function Test-Uv([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        & $Path --version | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

if (-not (Test-Uv $uvExe)) {
    $installerUrl = "https://astral.sh/uv/$Version/install.ps1"
    Write-Host "Preparing AuroraFox managed Python runtime with uv $Version..." -ForegroundColor Cyan
    $installer = Invoke-RestMethod -Uri $installerUrl -Method Get
    if (-not $installer) { throw "Failed to download uv installer" }

    $oldUnmanaged = $env:UV_UNMANAGED_INSTALL
    $oldNoPath = $env:UV_NO_MODIFY_PATH
    try {
        $env:UV_UNMANAGED_INSTALL = $uvDir
        $env:UV_NO_MODIFY_PATH = "1"
        & ([ScriptBlock]::Create([string]$installer))
    } finally {
        $env:UV_UNMANAGED_INSTALL = $oldUnmanaged
        $env:UV_NO_MODIFY_PATH = $oldNoPath
    }
}

if (-not (Test-Uv $uvExe)) {
    throw "AuroraFox uv runtime was not installed correctly: $uvExe"
}

$env:UV_PYTHON_INSTALL_DIR = $pythonDir
$env:UV_CACHE_DIR = $cacheDir
$env:UV_PYTHON_PREFERENCE = "only-managed"

# Installs a private CPython only when it is missing; no system Python is required.
& $uvExe python install 3.11
if ($LASTEXITCODE -ne 0) { throw "AuroraFox managed Python 3.11 setup failed" }

Write-Output $uvExe
