param(
    [string]$ArtifactPath = '',
    [string]$PackDir = 'D:\Desktop\AuroraFox-production-test-20260921-223011\knowledge-pack',
    [string]$ReportDir = '',
    [string]$AndroidSdkRoot = '',
    [string]$AvdName = 'AuroraFox_Acceptance_API_35',
    [string]$SystemImage = 'system-images;android-35;google_apis;x86_64',
    [int]$BootTimeoutSeconds = 900,
    [int]$AcceptanceTimeoutSeconds = 7200,
    [bool]$InstallSdkComponents = $true,
    [switch]$KeepEmulator
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedArtifactDigest = 'e56bc27f48a5f860f8fa5bb6a0b6fde6f0c809adf1e38f3bfe4928a3e1c82d28'
$ExpectedApkShaFile = 'production-knowledge-acceptance.sha256'
$Harness = Join-Path $PSScriptRoot 'android_installed_production_knowledge_pack.ps1'

function Resolve-ExistingFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File is missing: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-AndroidSdk {
    param([string]$Requested)
    $candidates = @(
        $Requested,
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'platform-tools\adb.exe')) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw @"
Android SDK was not found. Install Android Studio, open SDK Manager once, and install:
  Android SDK Platform-Tools
  Android Emulator
Then rerun this script. The script will install the pinned API 35 system image itself.
"@
}

function Find-SdkTool {
    param(
        [Parameter(Mandatory=$true)][string]$SdkRoot,
        [Parameter(Mandatory=$true)][string]$Name
    )
    $match = Get-ChildItem -LiteralPath $SdkRoot -Recurse -File -Filter $Name -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($null -eq $match) {
        throw "Android SDK tool is missing: $Name under $SdkRoot"
    }
    return $match.FullName
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [string]$InputText = ''
    )
    if ([string]::IsNullOrEmpty($InputText)) {
        $output = & $FilePath @Arguments 2>&1
    } else {
        $output = $InputText | & $FilePath @Arguments 2>&1
    }
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed ($LASTEXITCODE): $($Arguments -join ' ')$([Environment]::NewLine)$($output -join [Environment]::NewLine)"
    }
    return @($output)
}

function Resolve-Artifact {
    param(
        [string]$Requested,
        [Parameter(Mandatory=$true)][string]$RunRoot
    )
    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        return (Resolve-Path -LiteralPath $Requested).Path
    }
    $roots = @(
        (Join-Path $env:USERPROFILE 'Downloads'),
        'D:\Desktop',
        (Join-Path $env:USERPROFILE 'Desktop')
    ) | Where-Object { Test-Path -LiteralPath $_ }
    $matches = foreach ($root in $roots) {
        Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -like 'android-production-knowledge-acceptance*.zip' -or
                $_.Name -eq 'AuroraFox-Android-Production-Knowledge-Acceptance.apk'
            }
    }
    $selected = @($matches | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
    if ($selected.Count -ne 1) {
        throw 'APK artifact was not found. Download GitHub Actions artifact 10691590889 and pass its ZIP or extracted directory with -ArtifactPath.'
    }
    return $selected[0].FullName
}

function Resolve-ApkFromArtifact {
    param(
        [Parameter(Mandatory=$true)][string]$Artifact,
        [Parameter(Mandatory=$true)][string]$RunRoot
    )
    $item = Get-Item -LiteralPath $Artifact
    if ($item.PSIsContainer) {
        $artifactRoot = $item.FullName
    } elseif ($item.Extension -ieq '.apk') {
        return $item.FullName
    } elseif ($item.Extension -ieq '.zip') {
        $actualDigest = (Get-FileHash -Algorithm SHA256 -LiteralPath $item.FullName).Hash.ToLowerInvariant()
        if ($actualDigest -ne $ExpectedArtifactDigest) {
            throw "Workflow artifact ZIP SHA-256 mismatch: $actualDigest"
        }
        $artifactRoot = Join-Path $RunRoot 'artifact'
        New-Item -ItemType Directory -Force $artifactRoot | Out-Null
        Expand-Archive -LiteralPath $item.FullName -DestinationPath $artifactRoot -Force
    } else {
        throw "Unsupported artifact path: $Artifact"
    }

    $apk = @(Get-ChildItem -LiteralPath $artifactRoot -Recurse -File -Filter 'AuroraFox-Android-Production-Knowledge-Acceptance.apk')
    if ($apk.Count -ne 1) {
        throw "Expected exactly one acceptance APK, found $($apk.Count)."
    }
    $shaFile = Get-ChildItem -LiteralPath $artifactRoot -Recurse -File -Filter $ExpectedApkShaFile | Select-Object -First 1
    if ($null -ne $shaFile) {
        $expected = ((Get-Content -LiteralPath $shaFile.FullName -Raw) -split '\s+')[0].Trim().ToLowerInvariant()
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $apk[0].FullName).Hash.ToLowerInvariant()
        if ($expected -ne $actual) {
            throw "Acceptance APK SHA-256 mismatch: $actual"
        }
    }
    return $apk[0].FullName
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This orchestrator must run on Windows.'
}
if (-not (Test-Path -LiteralPath $Harness -PathType Leaf)) {
    throw "Strict Android acceptance harness is missing: $Harness"
}
$resolvedPack = (Resolve-Path -LiteralPath $PackDir).Path
if (-not (Test-Path -LiteralPath (Join-Path $resolvedPack 'manifest.json') -PathType Leaf)) {
    throw "Exact extracted production pack is missing manifest.json: $resolvedPack"
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runRoot = if ([string]::IsNullOrWhiteSpace($ReportDir)) {
    "D:\Desktop\AuroraFox-android-production-test-$stamp"
} else {
    $ReportDir
}
New-Item -ItemType Directory -Force $runRoot | Out-Null
$runRoot = (Resolve-Path -LiteralPath $runRoot).Path

$sdk = Resolve-AndroidSdk -Requested $AndroidSdkRoot
$adb = Resolve-ExistingFile -Path (Join-Path $sdk 'platform-tools\adb.exe')
$sdkmanager = Find-SdkTool -SdkRoot $sdk -Name 'sdkmanager.bat'
$avdmanager = Find-SdkTool -SdkRoot $sdk -Name 'avdmanager.bat'

if ($InstallSdkComponents) {
    $yes = ((1..200 | ForEach-Object { 'y' }) -join [Environment]::NewLine)
    [void](Invoke-Checked -FilePath $sdkmanager -Arguments @("--sdk_root=$sdk", '--licenses') -InputText $yes)
    [void](Invoke-Checked -FilePath $sdkmanager -Arguments @("--sdk_root=$sdk", 'platform-tools', 'emulator', $SystemImage))
}

$emulator = Find-SdkTool -SdkRoot $sdk -Name 'emulator.exe'
$accel = & $emulator -accel-check 2>&1
$accel | Set-Content -LiteralPath (Join-Path $runRoot 'emulator-accel-check.txt') -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
    throw "Android hardware acceleration is unavailable. Enable CPU virtualization in BIOS/UEFI and Windows Hypervisor Platform, reboot, then rerun. Details: $($accel -join ' ')"
}

$avds = @(& $emulator -list-avds 2>&1)
if ($avds -notcontains $AvdName) {
    $created = 'no' | & $avdmanager create avd --force --name $AvdName --package $SystemImage --device 'pixel_6' 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Cannot create AVD $AvdName. $($created -join [Environment]::NewLine)"
    }
}

$artifact = Resolve-Artifact -Requested $ArtifactPath -RunRoot $runRoot
$apk = Resolve-ApkFromArtifact -Artifact $artifact -RunRoot $runRoot
Write-Host "APK=$apk"
Write-Host "PACK=$resolvedPack"
Write-Host "REPORT=$runRoot"

& $adb kill-server *> $null
$emulatorArgs = @(
    "-avd", $AvdName,
    '-no-snapshot',
    '-no-boot-anim',
    '-no-audio',
    '-no-window',
    '-gpu', 'swiftshader_indirect',
    '-wipe-data'
)
$emulatorProcess = Start-Process -FilePath $emulator -ArgumentList $emulatorArgs -PassThru
$emulatorProcess.Id | Set-Content -LiteralPath (Join-Path $runRoot 'emulator.pid.txt') -Encoding ASCII

try {
    $deadline = [DateTime]::UtcNow.AddSeconds($BootTimeoutSeconds)
    $booted = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($emulatorProcess.HasExited) {
            throw "Android emulator exited before boot. ExitCode=$($emulatorProcess.ExitCode)"
        }
        $devices = @((& $adb devices) | Select-String -Pattern '^emulator-[0-9]+\s+device$')
        if ($devices.Count -eq 1) {
            $complete = (& $adb shell getprop sys.boot_completed 2>$null | Out-String).Trim()
            if ($complete -eq '1') {
                $booted = $true
                break
            }
        }
        Start-Sleep -Seconds 5
    }
    if (-not $booted) {
        throw "Android emulator did not boot within $BootTimeoutSeconds seconds."
    }

    $allReady = @((& $adb devices) | Select-String -Pattern '^[^\s]+\s+device$')
    if ($allReady.Count -ne 1) {
        throw "Exactly one Android target is required; found $($allReady.Count). Disconnect phones and close other emulators."
    }

    $rootOutput = & $adb root 2>&1
    $rootOutput | Set-Content -LiteralPath (Join-Path $runRoot 'adb-root.txt') -Encoding UTF8
    & $adb wait-for-device
    $uid = (& $adb shell id -u 2>&1 | Out-String).Trim()
    if ($uid -ne '0') {
        throw "The selected system image does not permit adb root (uid=$uid). Delete AVD $AvdName and rerun with the pinned Google APIs image."
    }

    & $Harness -ApkPath $apk -PackDir $resolvedPack -ReportDir $runRoot -Adb $adb -TimeoutSeconds $AcceptanceTimeoutSeconds
    $report = Join-Path $runRoot 'report.json'
    if (-not (Test-Path -LiteralPath $report -PathType Leaf)) {
        throw "Acceptance success marker returned without report.json: $report"
    }
    Write-Host 'AURORA_WINDOWS_ANDROID_PRODUCTION_ORCHESTRATION_OK'
    Write-Host "REPORT=$report"
} finally {
    if (-not $KeepEmulator -and $null -ne $emulatorProcess -and -not $emulatorProcess.HasExited) {
        & $adb emu kill *> $null
        [void]$emulatorProcess.WaitForExit(30000)
    }
}
