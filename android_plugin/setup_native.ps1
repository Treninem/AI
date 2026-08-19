$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$thirdParty = Join-Path $root "plugin/src/main/cpp/third_party"
$libs = Join-Path $root "plugin/libs"
$voiceAssets = Join-Path $root "plugin/src/main/assets/voice"
$temp = Join-Path ([IO.Path]::GetTempPath()) "aurorafox-android-voice"
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
        Invoke-WebRequest -Uri $url -OutFile $dest
    }
}

function Extract-TarBz2($archive, $dest, $expectedFolder) {
    if (Test-Path (Join-Path $dest $expectedFolder)) { return }
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

# Russian Piper fallback voice.
$ttsName = "vits-piper-ru_RU-denis-medium"
$ttsArchive = Join-Path $temp "$ttsName.tar.bz2"
Download-IfMissing "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$ttsName.tar.bz2" $ttsArchive
Extract-TarBz2 $ttsArchive $voiceAssets $ttsName

# Multilingual Whisper tiny through sherpa-onnx for fully offline Android STT.
$sttName = "sherpa-onnx-whisper-tiny"
$sttArchive = Join-Path $temp "$sttName.tar.bz2"
Download-IfMissing "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$sttName.tar.bz2" $sttArchive
Extract-TarBz2 $sttArchive $voiceAssets $sttName

Write-Host "Native and Android voice sources are ready." -ForegroundColor Green
Write-Host "llama.cpp  $llamaRevision"
Write-Host "wasm3       $wasm3Revision"
Write-Host "sherpa-onnx $sherpaVersion"
Write-Host "Voice assets: $voiceAssets"
