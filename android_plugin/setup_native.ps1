$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$thirdParty = Join-Path $root "plugin\src\main\cpp\third_party"
$libs = Join-Path $root "plugin\libs"
$voiceAssets = Join-Path $root "plugin\src\main\assets\voice"
$temp = Join-Path $env:TEMP "aurorafox-android-voice"
New-Item -ItemType Directory -Force -Path $thirdParty,$libs,$voiceAssets,$temp | Out-Null

function Ensure-Repo($name, $url) {
    $dest = Join-Path $thirdParty $name
    if (Test-Path (Join-Path $dest ".git")) {
        Write-Host "Updating $name..."
        git -C $dest pull --ff-only
    } else {
        Write-Host "Cloning $name..."
        git clone --depth 1 $url $dest
    }
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
        throw "tar.exe is required to unpack Android voice models"
    }
    & tar -xjf $archive -C $dest
    if ($LASTEXITCODE -ne 0) { throw "Failed to extract $archive" }
}

Ensure-Repo "llama.cpp" "https://github.com/ggml-org/llama.cpp.git"
Ensure-Repo "whisper.cpp" "https://github.com/ggml-org/whisper.cpp.git"
Ensure-Repo "wasm3" "https://github.com/wasm3/wasm3.git"

# sherpa-onnx is used only for local Android speech. The AAR contains its JNI libraries.
$sherpaVersion = "1.13.4"
$sherpaAar = Join-Path $libs "sherpa-onnx-$sherpaVersion.aar"
Download-IfMissing "https://github.com/k2-fsa/sherpa-onnx/releases/download/v$sherpaVersion/sherpa-onnx-$sherpaVersion.aar" $sherpaAar

# Original Russian AuroraFox mobile fallback voice. This is a generic Piper model, not a cloned real person.
$ttsName = "vits-piper-ru_RU-irina-medium"
$ttsArchive = Join-Path $temp "$ttsName.tar.bz2"
Download-IfMissing "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$ttsName.tar.bz2" $ttsArchive
Extract-TarBz2 $ttsArchive $voiceAssets $ttsName

# Multilingual Whisper tiny for offline Android Russian STT.
$sttName = "sherpa-onnx-whisper-tiny"
$sttArchive = Join-Path $temp "$sttName.tar.bz2"
Download-IfMissing "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$sttName.tar.bz2" $sttArchive
Extract-TarBz2 $sttArchive $voiceAssets $sttName

Write-Host "Native and Android voice sources are ready." -ForegroundColor Green
Write-Host "Voice assets: $voiceAssets"
Write-Host "Build the Android plugin with Gradle after Android SDK/NDK is configured."
