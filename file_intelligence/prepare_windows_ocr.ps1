param(
    [string]$RuntimeRoot = "",
    [string]$CacheRoot = ""
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RuntimeRoot) { $RuntimeRoot = Join-Path $Root 'ocr_runtime' }
if (-not $CacheRoot) { $CacheRoot = Join-Path ([IO.Path]::GetTempPath()) 'aurorafox-ocr-cache' }
$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$CacheRoot = [IO.Path]::GetFullPath($CacheRoot)
New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null

# Official Tesseract 5.5.3 Windows release asset. The release itself publishes
# the same SHA-256 digest, and AuroraFox verifies the bytes before execution.
$installerName = 'tesseract-ocr-w64-setup-5.5.3.20260724.exe'
$installerUrl = "https://github.com/tesseract-ocr/tesseract/releases/download/5.5.3/$installerName"
$installerSha = 'bee9e3434bd94fd65387d9be28cd467a41f61b1275383b55b0f59a1331270ae4'
$installer = Join-Path $CacheRoot $installerName
$models = @(
    @{ Name='eng.traineddata'; Url='https://github.com/tesseract-ocr/tessdata_fast/raw/4.1.0/eng.traineddata'; Sha='7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2' },
    @{ Name='rus.traineddata'; Url='https://github.com/tesseract-ocr/tessdata_fast/raw/4.1.0/rus.traineddata'; Sha='e16e5e036cce1d9ec2b00063cf8b54472625b9e14d893a169e2b0dedeb4df225' }
)

function Get-Verified([string]$Url, [string]$Path, [string]$Sha) {
    if ((Test-Path -LiteralPath $Path) -and ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -eq $Sha)) { return }
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    Invoke-WebRequest -Uri $Url -OutFile $Path
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Sha) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        throw "SHA-256 mismatch for $Url : $actual"
    }
}

$tesseract = Join-Path $RuntimeRoot 'tesseract.exe'
if (-not (Test-Path -LiteralPath $tesseract)) {
    Get-Verified $installerUrl $installer $installerSha
    if (Test-Path -LiteralPath $RuntimeRoot) { Remove-Item -LiteralPath $RuntimeRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $RuntimeRoot | Out-Null

    # The NSIS installer is a GUI-subsystem executable. Start-Process -Wait
    # provides deterministic completion. /D= must be the final NSIS argument;
    # nested quote characters become part of ArgumentList and can make NSIS
    # ignore the requested directory on paths which do not need quoting.
    $installArgs = @('/S', "/D=$RuntimeRoot")
    $installProcess = Start-Process -FilePath $installer -ArgumentList $installArgs -Wait -PassThru
    if ($null -eq $installProcess) { throw 'Tesseract installer did not return a process handle' }
    if ($installProcess.ExitCode -ne 0) { throw "Tesseract installer failed with exit code $($installProcess.ExitCode)" }
    if (-not (Test-Path -LiteralPath $tesseract)) { throw "Tesseract runtime was not created: $tesseract" }
}

$tessdata = Join-Path $RuntimeRoot 'tessdata'
New-Item -ItemType Directory -Force -Path $tessdata | Out-Null
foreach ($model in $models) {
    $cached = Join-Path $CacheRoot $model.Name
    Get-Verified $model.Url $cached $model.Sha
    $target = Join-Path $tessdata $model.Name
    Copy-Item -LiteralPath $cached -Destination $target -Force
    $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $model.Sha) { throw "Packaged OCR model hash mismatch: $($model.Name)" }
}

$env:TESSDATA_PREFIX = $tessdata
$version = (& $tesseract --version 2>&1 | Select-Object -First 1)
$langs = (& $tesseract --tessdata-dir $tessdata --list-langs 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $langs -notmatch '(?m)^eng\s*$' -or $langs -notmatch '(?m)^rus\s*$') {
    throw "Packaged Tesseract runtime does not expose eng+rus: $langs"
}
Write-Host "AuroraFox local OCR ready: $version" -ForegroundColor Green
Write-Output $tesseract
