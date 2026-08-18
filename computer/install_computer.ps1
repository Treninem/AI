$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Venv = Join-Path $Root '.venv'

if (-not (Test-Path $Venv)) {
    py -3.11 -m venv $Venv
}

$Python = Join-Path $Venv 'Scripts\python.exe'
$Pip = Join-Path $Venv 'Scripts\pip.exe'

& $Python -m pip install --upgrade pip
& $Pip install -r (Join-Path $Root 'requirements.txt')

Write-Host 'Checking Ollama...'
$ollama = Get-Command ollama -ErrorAction SilentlyContinue
if ($null -eq $ollama) {
    Write-Warning 'Ollama is not installed or not in PATH. Install Ollama, then run: ollama pull qwen3-vl:8b'
} else {
    & ollama pull qwen3-vl:8b
}

Write-Host ''
Write-Host 'AuroraFox Computer Agent installed.'
Write-Host "Start with: $Python $Root\computer_service.py"
Write-Host 'Emergency stop while automation is running: move the mouse to the upper-left corner.'
