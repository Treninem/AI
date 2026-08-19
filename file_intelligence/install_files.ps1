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
        [IO.File]::WriteAllText($StateFile, $payload, [Text.UTF8Encoding]::new($false))
    }
}

try {
    Set-Stage 'runtime' 5 'Подготовка локального Python runtime AuroraFox'
    if (-not (Test-Path -LiteralPath $RuntimeScript)) {
        throw "Не найден runtime/ensure_uv.ps1: $RuntimeScript"
    }
    $uvOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $RuntimeScript -RuntimeRoot $RuntimeRoot
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось подготовить managed Python 3.11.' }
    $uv = Join-Path $RuntimeRoot 'uv\uv.exe'
    if (-not (Test-Path -LiteralPath $uv)) { throw "uv.exe не найден: $uv" }

    $env:UV_PYTHON_INSTALL_DIR = Join-Path $RuntimeRoot 'python'
    $env:UV_CACHE_DIR = Join-Path $RuntimeRoot 'cache'
    $env:UV_PYTHON_PREFERENCE = 'only-managed'

    Set-Stage 'venv' 22 'Создание изолированного окружения File Intelligence'
    if (-not (Test-Path -LiteralPath $Python)) {
        & $uv venv --python 3.11 $Venv
        if ($LASTEXITCODE -ne 0) { throw 'Не удалось создать окружение File Intelligence.' }
    }

    Set-Stage 'dependencies' 42 'Установка локальных парсеров документов, изображений и видео'
    & $uv pip install --python $Python --requirements $Requirements
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось установить зависимости File Intelligence.' }

    Set-Stage 'verify' 90 'Проверка импортов и встроенного ffmpeg'
    $check = @'
import imageio_ffmpeg
import pypdf, pypdfium2, docx, openpyxl, xlrd, pptx, PIL, py7zr
from pathlib import Path
exe = Path(imageio_ffmpeg.get_ffmpeg_exe())
assert exe.is_file(), f"ffmpeg missing: {exe}"
print("AURORA_FILE_INTELLIGENCE_READY", exe)
'@
    & $Python -c $check
    if ($LASTEXITCODE -ne 0) { throw 'Проверка File Intelligence не пройдена.' }

    Set-Stage 'ready' 100 'File Intelligence готов к локальной работе'
    Write-Host 'AuroraFox File Intelligence installed.' -ForegroundColor Green
} catch {
    Set-Stage 'error' 0 $_.Exception.Message
    throw
}
