param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$voiceRoot = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $voiceRoot "..")).Path
if (-not $OutputDir) { $OutputDir = Join-Path $repoRoot "build\voice_backend" }
$python = Join-Path $voiceRoot ".venv\Scripts\python.exe"
$server = Join-Path $voiceRoot "python\aurora_voice_server.py"
$work = Join-Path $repoRoot "build\.voice_pyinstaller"
$spec = Join-Path $repoRoot "build\.voice_spec"

if (-not (Test-Path $python)) { throw "Voice .venv is missing. Run voice/install_voice.ps1 first." }
if (-not (Test-Path $server)) { throw "aurora_voice_server.py is missing" }

& $python -m pip install --disable-pip-version-check "pyinstaller==6.16.0"
if ($LASTEXITCODE -ne 0) { throw "PyInstaller installation failed" }

if (Test-Path $OutputDir) { Remove-Item $OutputDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $OutputDir,$work,$spec | Out-Null

$args = @(
    '-m', 'PyInstaller',
    '--noconfirm', '--clean', '--onedir', '--windowed',
    '--name', 'AuroraVoiceBackend',
    '--distpath', $OutputDir,
    '--workpath', $work,
    '--specpath', $spec,
    '--paths', (Join-Path $voiceRoot 'python'),
    '--collect-all', 'silero',
    '--collect-all', 'silero_vad',
    '--collect-all', 'vosk',
    '--collect-all', 'transformers',
    '--collect-all', 'torch',
    '--collect-all', 'torchaudio',
    '--collect-all', 'sounddevice',
    '--collect-all', 'soundfile',
    '--collect-all', 'onnxruntime',
    $server
)
& $python @args
if ($LASTEXITCODE -ne 0) { throw "AuroraVoiceBackend.exe build failed" }

$backend = Join-Path $OutputDir 'AuroraVoiceBackend'
$exe = Join-Path $backend 'AuroraVoiceBackend.exe'
if (-not (Test-Path $exe)) { throw "Portable voice backend executable was not produced" }

# Server resolves config from the backend root in onedir mode. Copy a production config
# where wake model is resolved relative to the parent voice directory.
Copy-Item (Join-Path $voiceRoot 'config') (Join-Path $backend 'config') -Recurse -Force
$configPath = Join-Path $backend 'config\voice_config.json'
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$config.wake.vosk_model = 'models/vosk-model-small-ru-0.22'
$config | ConvertTo-Json -Depth 12 | Set-Content -Path $configPath -Encoding UTF8

Write-Host "Portable Aurora Voice backend: $exe" -ForegroundColor Green
