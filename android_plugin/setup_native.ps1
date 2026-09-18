$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$thirdParty = Join-Path $root "plugin/src/main/cpp/third_party"
$libs = Join-Path $root "plugin/libs"
$voiceAssets = Join-Path $root "plugin/src/main/assets/voice"
$cacheRoot = if ($env:AURORAFOX_NATIVE_CACHE_DIR) {
    [IO.Path]::GetFullPath($env:AURORAFOX_NATIVE_CACHE_DIR)
} else {
    Join-Path ([IO.Path]::GetTempPath()) "aurorafox-android-native-cache"
}
$temp = Join-Path $cacheRoot "voice-archives"
New-Item -ItemType Directory -Force -Path $thirdParty,$libs,$voiceAssets,$temp | Out-Null

# Pinned revisions: do not silently build a different native runtime tomorrow.
$llamaRevision = "6d05498314db1b57f81c271080018aa2d0b89be9"
$wasm3Revision = "2f3123dfbf93e30fe92eeb60a6fdada6b0141a87"

function Ensure-Repo($name, $url, $revision) {
    $dest = Join-Path $thirdParty $name
    if (-not (Test-Path (Join-Path $dest ".git"))) {
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        Write-Host "Cloning $name..."
        git clone --filter=blob:none --no-checkout $url $dest
        if ($LASTEXITCODE -ne 0) { throw "Failed to clone $name" }
    }
    Write-Host "Pinning $name at $revision..."
    git -C $dest fetch --depth 1 origin $revision
    if ($LASTEXITCODE -ne 0) { throw "Failed to fetch pinned revision for $name" }
    git -C $dest checkout --detach --force FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { throw "Failed to checkout pinned revision for $name" }
    $actual = (git -C $dest rev-parse HEAD).Trim()
    if ($actual -ne $revision) { throw "$name revision mismatch: $actual != $revision" }
    git -C $dest clean -fdx
    if ($LASTEXITCODE -ne 0) { throw "Failed to clean $name source tree" }
}

function Patch-Wasm3AndroidCompatibility {
    $sourcePath = Join-Path $thirdParty "wasm3/source/m3_api_wasi.c"
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Pinned wasm3 WASI source is missing: $sourcePath"
    }

    $source = [IO.File]::ReadAllText($sourcePath)
    $includeNeedle = "#include <fcntl.h>"
    if (-not $source.Contains($includeNeedle)) {
        throw "Pinned wasm3 include layout changed; refusing an unverified Android patch"
    }
    if (-not $source.Contains("#include <stdlib.h>")) {
        $source = $source.Replace($includeNeedle, "$includeNeedle`n#include <stdlib.h>")
    }

    $old = @'
#   else
        retlen = getentropy(buf, reqlen) < 0 ? -1 : reqlen;
#   endif
'@
    $replacement = @'
#   elif defined(__ANDROID_API__)
        // Android getentropy() is API 28+, while AuroraFox supports API 26.
        // Bionic arc4random_buf() is available on every Android API level.
        arc4random_buf(buf, reqlen);
        retlen = reqlen;
#   else
        retlen = getentropy(buf, reqlen) < 0 ? -1 : reqlen;
#   endif
'@
    if (-not $source.Contains($old)) {
        throw "Pinned wasm3 random_get layout changed; refusing an unverified Android patch"
    }
    $source = $source.Replace($old, $replacement)
    $utf8 = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($sourcePath, $source, $utf8)

    $verify = [IO.File]::ReadAllText($sourcePath)
    if (-not $verify.Contains("arc4random_buf(buf, reqlen)")) {
        throw "wasm3 Android entropy compatibility patch was not applied"
    }
    Write-Host "Patched pinned wasm3 WASI entropy for Android API 26 compatibility."
}

function Download-IfMissing($url, $dest) {
    if (-not (Test-Path $dest)) {
        Write-Host "Downloading $(Split-Path $dest -Leaf)..."
        $partial = "$dest.download"
        try {
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                try {
                    Invoke-WebRequest -Uri $url -OutFile $partial -TimeoutSec 600
                    Move-Item -LiteralPath $partial -Destination $dest -Force
                    return
                } catch {
                    Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
                    $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
                    if ($attempt -eq 3 -or ($status -ne 0 -and $status -ne 429 -and $status -lt 500)) {
                        throw "Pinned download failed: $(Split-Path $dest -Leaf) attempt=$attempt HTTP=$status"
                    }
                    Write-Host "Retrying pinned download attempt=$attempt HTTP=$status"
                    Start-Sleep -Seconds (3 * $attempt)
                }
            }
        } finally {
            Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host "Using cached $(Split-Path $dest -Leaf)."
    }
}

function Assert-FileIdentity($path, [long]$expectedBytes, $expectedSha256) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Pinned asset is missing: $path"
    }
    $actualBytes = (Get-Item -LiteralPath $path).Length
    if ($actualBytes -ne $expectedBytes) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        throw "Pinned asset byte mismatch: $actualBytes != $expectedBytes"
    }
    $actualSha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha256 -ne $expectedSha256.ToLowerInvariant()) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        throw "Pinned asset SHA-256 mismatch: $actualSha256 != $expectedSha256"
    }
}

function Extract-TarBz2($archive, $dest, $expectedFolder) {
    if (Test-Path (Join-Path $dest $expectedFolder)) {
        Write-Host "Using cached extracted model $expectedFolder."
        return
    }
    if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
        throw "tar is required to unpack Android voice models"
    }
    & tar -xjf $archive -C $dest
    if ($LASTEXITCODE -ne 0) { throw "Failed to extract $archive" }
}

Ensure-Repo "llama.cpp" "https://github.com/ggml-org/llama.cpp.git" $llamaRevision
Ensure-Repo "wasm3" "https://github.com/wasm3/wasm3.git" $wasm3Revision
Patch-Wasm3AndroidCompatibility

# sherpa-onnx is the actual Android speech runtime for both TTS and STT.
# Do not fetch whisper.cpp here: AuroraFox does not compile its JNI adapter,
# and AndroidVoiceRuntime already provides the offline Whisper path via sherpa.
$sherpaVersion = "1.13.4"
$sherpaAar = Join-Path $libs "sherpa-onnx-$sherpaVersion.aar"
Download-IfMissing "https://github.com/k2-fsa/sherpa-onnx/releases/download/v$sherpaVersion/sherpa-onnx-$sherpaVersion.aar" $sherpaAar

# Russian-capable local female TTS candidate. The archive identity is pinned to
# the official sherpa-onnx tts-models release and must fail closed on drift.
$ttsName = "sherpa-onnx-supertonic-3-tts-int8-2026-05-11"
$ttsArchive = Join-Path $temp "$ttsName.tar.bz2"
$ttsFolder = Join-Path $voiceAssets $ttsName
$ttsArchiveBytes = 128774318
$ttsArchiveSha256 = "82fa96f91c4ef8abaae3a14a3f4153facf88bed821d1f7331cec2700f432c427"
$ttsRequiredFiles = @(
    "duration_predictor.int8.onnx",
    "text_encoder.int8.onnx",
    "vector_estimator.int8.onnx",
    "vocoder.int8.onnx",
    "tts.json",
    "unicode_indexer.bin",
    "voice.bin"
)
$ttsMarker = Join-Path $ttsFolder ".aurorafox-source.sha256"

Download-IfMissing "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$ttsName.tar.bz2" $ttsArchive
Assert-FileIdentity $ttsArchive $ttsArchiveBytes $ttsArchiveSha256

$needsTtsExtract = -not (Test-Path -LiteralPath $ttsFolder -PathType Container)
if (-not $needsTtsExtract) {
    if (-not (Test-Path -LiteralPath $ttsMarker -PathType Leaf)) {
        $needsTtsExtract = $true
    } elseif (([IO.File]::ReadAllText($ttsMarker)).Trim().ToLowerInvariant() -ne $ttsArchiveSha256) {
        $needsTtsExtract = $true
    }
    foreach ($required in $ttsRequiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $ttsFolder $required) -PathType Leaf)) {
            $needsTtsExtract = $true
        }
    }
}

if ($needsTtsExtract) {
    if (Test-Path -LiteralPath $ttsFolder) { Remove-Item -LiteralPath $ttsFolder -Recurse -Force }
    Extract-TarBz2 $ttsArchive $voiceAssets $ttsName
    if (-not (Test-Path -LiteralPath $ttsFolder -PathType Container)) {
        throw "Supertonic archive root is missing after extraction: $ttsName"
    }
    foreach ($required in $ttsRequiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $ttsFolder $required) -PathType Leaf)) {
            throw "Supertonic required file is missing after extraction: $required"
        }
    }
    $utf8 = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($ttsMarker, $ttsArchiveSha256, $utf8)
} else {
    Write-Host "Using verified extracted model $ttsName."
}

# Multilingual Whisper tiny through sherpa-onnx for fully offline Android STT.
$sttName = "sherpa-onnx-whisper-tiny"
$sttArchive = Join-Path $temp "$sttName.tar.bz2"
$sttFolder = Join-Path $voiceAssets $sttName
if (-not (Test-Path -LiteralPath $sttFolder)) {
    Download-IfMissing "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$sttName.tar.bz2" $sttArchive
    Extract-TarBz2 $sttArchive $voiceAssets $sttName
} else {
    Write-Host "Using cached extracted model $sttName."
}

Write-Host "Native and Android voice sources are ready." -ForegroundColor Green
Write-Host "llama.cpp  $llamaRevision"
Write-Host "wasm3       $wasm3Revision"
Write-Host "sherpa-onnx $sherpaVersion"
Write-Host "Android TTS $ttsName ($ttsArchiveSha256)"
Write-Host "Voice assets: $voiceAssets"
Write-Host "Native cache: $cacheRoot"
