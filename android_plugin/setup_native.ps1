$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$thirdParty = Join-Path $root "plugin\src\main\cpp\third_party"
New-Item -ItemType Directory -Force -Path $thirdParty | Out-Null

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

Ensure-Repo "llama.cpp" "https://github.com/ggml-org/llama.cpp.git"
Ensure-Repo "whisper.cpp" "https://github.com/ggml-org/whisper.cpp.git"
Ensure-Repo "wasm3" "https://github.com/wasm3/wasm3.git"

Write-Host "Native sources are ready in $thirdParty"
Write-Host "Build the Android plugin with Gradle after the Android SDK/NDK is configured."
