param(
    [Parameter(Mandatory=$true)][string]$Package,
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [Parameter(Mandatory=$true)][int]$ParentPid,
    [Parameter(Mandatory=$true)][string]$ExeName,
    [Parameter(Mandatory=$true)][string]$ExpectedSha256,
    [Parameter(Mandatory=$true)][string]$HealthFile
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-UpdateLog([string]$Message) {
    try {
        $logDir = Split-Path -Parent $HealthFile
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        Add-Content -Path (Join-Path $logDir 'windows_updater.log') -Value "[$(Get-Date -Format s)] $Message" -Encoding UTF8
    } catch {}
}

function Wait-ForExit([int]$Pid, [int]$TimeoutSec = 90) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $p = Get-Process -Id $Pid -ErrorAction SilentlyContinue
        if (-not $p) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return $false
}

function Preserve-LocalRuntime([string]$OldRoot, [string]$NewRoot) {
    # Large local runtimes/models are user-installed once and should not be downloaded
    # on every AuroraFox code update. Failures here are non-fatal: the first-run setup
    # can repair/re-download them later.
    $paths = @(
        'voice\.venv',
        'voice\models',
        'computer\.venv',
        'computer\models'
    )
    foreach ($relative in $paths) {
        try {
            $source = Join-Path $OldRoot $relative
            $target = Join-Path $NewRoot $relative
            if (-not (Test-Path -LiteralPath $source)) { continue }
            if (Test-Path -LiteralPath $target) {
                Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
                    Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force -ErrorAction Stop
                }
            } else {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
                Copy-Item -LiteralPath $source -Destination $target -Recurse -Force -ErrorAction Stop
            }
            Write-UpdateLog "Preserved $relative"
        } catch {
            Write-UpdateLog "Runtime preservation warning for $relative : $($_.Exception.Message)"
        }
    }
}

$Package = [IO.Path]::GetFullPath($Package)
$InstallDir = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
$ExpectedSha256 = $ExpectedSha256.ToLowerInvariant()
$parentDir = Split-Path -Parent $InstallDir
$name = Split-Path -Leaf $InstallDir
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$staging = Join-Path $parentDir ($name + '.__new_' + $stamp)
$backup = Join-Path $parentDir ($name + '.__old_' + $stamp)
$newExe = Join-Path $InstallDir $ExeName

Write-UpdateLog "Updater started package=$Package install=$InstallDir parent=$ParentPid"

try {
    if (-not (Test-Path -LiteralPath $Package -PathType Leaf)) { throw 'Update package is missing' }
    $actual = (Get-FileHash -LiteralPath $Package -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $ExpectedSha256) { throw "SHA-256 mismatch: $actual" }

    if (-not (Wait-ForExit -Pid $ParentPid)) { throw 'AuroraFox did not exit in time' }

    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    Expand-Archive -LiteralPath $Package -DestinationPath $staging -Force

    if (-not (Test-Path -LiteralPath (Join-Path $staging $ExeName))) {
        $entries = @(Get-ChildItem -LiteralPath $staging -Force)
        if ($entries.Count -eq 1 -and $entries[0].PSIsContainer -and (Test-Path -LiteralPath (Join-Path $entries[0].FullName $ExeName))) {
            $inner = $entries[0].FullName
            Get-ChildItem -LiteralPath $inner -Force | ForEach-Object { Move-Item -LiteralPath $_.FullName -Destination $staging -Force }
            Remove-Item -LiteralPath $inner -Recurse -Force
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $staging $ExeName))) { throw 'New package does not contain AuroraFox.exe' }

    if (Test-Path -LiteralPath $HealthFile) { Remove-Item -LiteralPath $HealthFile -Force }
    if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }

    Write-UpdateLog 'Switching application directories'
    Move-Item -LiteralPath $InstallDir -Destination $backup
    try {
        Move-Item -LiteralPath $staging -Destination $InstallDir
    } catch {
        if (Test-Path -LiteralPath $InstallDir) { Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue }
        Move-Item -LiteralPath $backup -Destination $InstallDir
        throw
    }

    Preserve-LocalRuntime -OldRoot $backup -NewRoot $InstallDir

    if (-not (Test-Path -LiteralPath $newExe)) { throw 'Updated executable disappeared after switch' }
    Write-UpdateLog 'Launching updated AuroraFox for health confirmation'
    $newProcess = Start-Process -FilePath $newExe -ArgumentList @('--', '--aurora-update-health', $HealthFile) -PassThru

    $deadline = (Get-Date).AddSeconds(45)
    $healthy = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $HealthFile) { $healthy = $true; break }
        if ($newProcess.HasExited) { break }
        Start-Sleep -Milliseconds 350
    }

    if (-not $healthy) {
        Write-UpdateLog 'Health check failed, rolling back'
        try { if (-not $newProcess.HasExited) { Stop-Process -Id $newProcess.Id -Force -ErrorAction SilentlyContinue } } catch {}
        Start-Sleep -Milliseconds 500
        if (Test-Path -LiteralPath $InstallDir) { Remove-Item -LiteralPath $InstallDir -Recurse -Force }
        Move-Item -LiteralPath $backup -Destination $InstallDir
        $oldExe = Join-Path $InstallDir $ExeName
        if (Test-Path -LiteralPath $oldExe) { Start-Process -FilePath $oldExe | Out-Null }
        throw 'Updated AuroraFox did not pass startup health check; rollback completed'
    }

    Write-UpdateLog 'Update health check passed'
    Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Package -Force -ErrorAction SilentlyContinue
    Write-UpdateLog 'Update completed successfully'
    exit 0
}
catch {
    Write-UpdateLog ("ERROR: " + $_.Exception.Message)
    try {
        if ((Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $InstallDir)) {
            Move-Item -LiteralPath $backup -Destination $InstallDir
        }
    } catch {
        Write-UpdateLog ("Rollback recovery failed: " + $_.Exception.Message)
    }
    exit 1
}
