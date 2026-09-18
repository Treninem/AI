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

$uv = Join-Path $repoRoot 'runtime/windows/uv/uv.exe'
if (-not (Test-Path $uv)) { throw 'Managed uv is missing. Run voice/install_voice.ps1 first.' }
# uv-created environments do not contain pip by default.
& $uv pip install --python $python "pyinstaller==6.16.0"
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
# Resolve the already prepared pinned TTS package without any network lookup.
$modelName = [string]$config.silero.model
$env:AURORAFOX_BUILD_SILERO_MODEL = $modelName
try {
    $resolveSilero = @'
import os
from pathlib import Path
from urllib.parse import urlparse
import silero
from omegaconf import OmegaConf
root = Path(silero.__file__).resolve().parent
manifest = root.parent.parent / 'models.yml'
if not manifest.is_file():
    manifest = Path.cwd() / 'latest_silero_models.yml'
assert manifest.is_file(), 'Prepared Silero manifest is missing'
config = OmegaConf.load(manifest)
url = config.tts_models.ru[os.environ['AURORAFOX_BUILD_SILERO_MODEL']].latest.package
package = root / 'model' / Path(urlparse(url).path).name
assert package.is_file(), 'Prepared Silero model package is missing'
print(package)
'@
    $sileroPackage = & $python -c $resolveSilero
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve prepared local Silero package' }
    $sileroDir = Join-Path $backend 'models/silero'
    New-Item -ItemType Directory -Force -Path $sileroDir | Out-Null
    Copy-Item -LiteralPath ([string]$sileroPackage).Trim() -Destination (Join-Path $sileroDir 'aurorafox-silero.pt') -Force
    $config.silero | Add-Member -NotePropertyName package_path -NotePropertyValue 'models/silero/aurorafox-silero.pt' -Force
} finally {
    Remove-Item Env:AURORAFOX_BUILD_SILERO_MODEL -ErrorAction SilentlyContinue
}
$config.wake.vosk_model = 'models/vosk-model-small-ru-0.22'
$config | ConvertTo-Json -Depth 12 | Set-Content -Path $configPath -Encoding UTF8

Write-Host "Portable Aurora Voice backend: $exe" -ForegroundColor Green
