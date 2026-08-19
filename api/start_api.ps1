param(
    [string]$HostAddress = "127.0.0.1",
    [int]$Port = 8768
)

$ErrorActionPreference = 'Stop'
$ApiRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppRoot = Split-Path -Parent $ApiRoot
$Installer = Join-Path $ApiRoot 'install_api.ps1'
$Pythonw = Join-Path $ApiRoot '.venv\Scripts\pythonw.exe'
$LogRoot = Join-Path $env:USERPROFILE '.aurorafox\api'
$StdOut = Join-Path $LogRoot 'api_stdout.log'
$StdErr = Join-Path $LogRoot 'api_stderr.log'

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

if (-not (Test-Path -LiteralPath $Pythonw)) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $Installer
    if ($LASTEXITCODE -ne 0) { throw 'AuroraFox API installation failed.' }
}

$env:AURORAFOX_API_HOST = $HostAddress
$env:AURORAFOX_API_PORT = [string]$Port
$env:AURORAFOX_USER_DIR = (Join-Path $env:USERPROFILE '.aurorafox')

$arguments = @('-m', 'api.app')
$process = Start-Process -FilePath $Pythonw -ArgumentList $arguments -WorkingDirectory $AppRoot -WindowStyle Hidden -RedirectStandardOutput $StdOut -RedirectStandardError $StdErr -PassThru

Write-Host ("AuroraFox API started: PID {0}, http://{1}:{2}" -f $process.Id, $HostAddress, $Port)
