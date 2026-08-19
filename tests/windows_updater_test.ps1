$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$root = Join-Path $env:RUNNER_TEMP 'aurorafox-updater-integration'
$install = Join-Path $root 'AuroraFox'
$newRoot = Join-Path $root 'new-build'
$package = Join-Path $root 'AuroraFox-Windows.zip'
$health = Join-Path $root 'health.ok'

Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $install,$newRoot | Out-Null

$healthCmd = @'
@echo off
if "%~1"=="--" shift
if "%~1"=="--aurora-update-health" (
  >"%~2" echo ok
)
exit /b 0
'@

# Existing installation.
Set-Content -Path (Join-Path $install 'health.cmd') -Value $healthCmd -Encoding ASCII
Set-Content -Path (Join-Path $install 'version.txt') -Value 'old' -Encoding ASCII
New-Item -ItemType Directory -Force -Path (Join-Path $install 'voice\models') | Out-Null
Set-Content -Path (Join-Path $install 'voice\models\keep.txt') -Value 'persistent-model' -Encoding ASCII
New-Item -ItemType Directory -Force -Path (Join-Path $install 'file_intelligence\.venv') | Out-Null
Set-Content -Path (Join-Path $install 'file_intelligence\.venv\keep.txt') -Value 'persistent-file-runtime' -Encoding ASCII
New-Item -ItemType Directory -Force -Path (Join-Path $install 'runtime\windows\python') | Out-Null
Set-Content -Path (Join-Path $install 'runtime\windows\python\keep.txt') -Value 'persistent-managed-python' -Encoding ASCII

# Incoming update. It deliberately also has voice/models so preservation tests the merge path.
Set-Content -Path (Join-Path $newRoot 'health.cmd') -Value $healthCmd -Encoding ASCII
Set-Content -Path (Join-Path $newRoot 'version.txt') -Value 'new' -Encoding ASCII
New-Item -ItemType Directory -Force -Path (Join-Path $newRoot 'voice\models') | Out-Null
Set-Content -Path (Join-Path $newRoot 'voice\models\new.txt') -Value 'new-runtime-file' -Encoding ASCII
New-Item -ItemType Directory -Force -Path (Join-Path $newRoot 'file_intelligence') | Out-Null
Set-Content -Path (Join-Path $newRoot 'file_intelligence\file_service.py') -Value '# new service' -Encoding ASCII
Compress-Archive -Path (Join-Path $newRoot '*') -DestinationPath $package -CompressionLevel Fastest
$sha = (Get-FileHash -Path $package -Algorithm SHA256).Hash.ToLowerInvariant()

# A real short-lived parent verifies Wait-ForExit instead of using a fake PID.
$parent = Start-Process powershell.exe -ArgumentList @('-NoProfile','-Command','Start-Sleep -Milliseconds 700') -PassThru -WindowStyle Hidden
$updater = Join-Path $repo 'update\windows_updater.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $updater `
    -Package $package `
    -InstallDir $install `
    -ParentPid $parent.Id `
    -ExeName 'health.cmd' `
    -ExpectedSha256 $sha `
    -HealthFile $health

if ($LASTEXITCODE -ne 0) { throw "windows_updater.ps1 returned $LASTEXITCODE" }
if (-not (Test-Path $health)) { throw 'New installation did not produce update health marker' }
if ((Get-Content (Join-Path $install 'version.txt') -Raw).Trim() -ne 'new') { throw 'New installation was not activated' }
if (-not (Test-Path (Join-Path $install 'voice\models\keep.txt'))) { throw 'Existing local model was not preserved' }
if (-not (Test-Path (Join-Path $install 'voice\models\new.txt'))) { throw 'New runtime content was lost during preservation' }
if (-not (Test-Path (Join-Path $install 'file_intelligence\.venv\keep.txt'))) { throw 'File Intelligence virtual environment was not preserved' }
if (-not (Test-Path (Join-Path $install 'runtime\windows\python\keep.txt'))) { throw 'Managed Python runtime was not preserved' }
if (-not (Test-Path (Join-Path $install 'file_intelligence\file_service.py'))) { throw 'New File Intelligence service was lost' }
if (Test-Path $package) { throw 'Verified update package was not cleaned after success' }

$backup = @(Get-ChildItem $root -Directory -Filter 'AuroraFox.__old_*' -ErrorAction SilentlyContinue)
if ($backup.Count -ne 0) { throw 'Successful updater left a rollback directory behind' }

Write-Host 'AURORA_WINDOWS_UPDATER_INTEGRATION_OK' -ForegroundColor Green
