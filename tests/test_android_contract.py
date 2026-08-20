from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def main() -> None:
    state = json.loads(read("project/version.json"))
    numeric = str(state.get("numeric", "")).strip()
    require(bool(re.fullmatch(r"\d+\.\d+\.\d+\.\d+", numeric)), "invalid canonical version")

    preset = read("export_presets.cfg")
    require('name="Android"' in preset, "Android export preset is missing")
    require(f'version/name="{numeric}"' in preset, "Android versionName is not synchronized")
    require(f'version/code={int(state["android_version_code"])}' in preset, "Android versionCode is not synchronized")
    require('package/unique_name="com.aurorafox.ai"' in preset, "Android package id changed")
    require('gradle_build/min_sdk="26"' in preset, "Android minSdk must remain 26")
    require('gradle_build/target_sdk="35"' in preset, "Android targetSdk must remain 35")
    require('architectures/arm64-v8a=true' in preset, "Android arm64 build is disabled")
    require('architectures/x86_64=true' in preset, "Android x86_64 build is required for exact-APK emulator validation")
    require('permissions/internet=true' in preset, "Android internet permission is missing")
    require('permissions/record_audio=true' in preset, "Android microphone permission is missing")

    project = read("project.godot")
    require(
        "textures/vram_compression/import_etc2_astc=true" in project,
        "Android ETC2/ASTC texture import must be enabled for export",
    )

    build_script = read("build/build_android.ps1")
    require("[switch]$AllowUnsignedRelease" in build_script, "CI unsigned export switch is missing")
    require("package/signed=false" in build_script, "unsigned CI export is not implemented")
    require("Restored signed Android export preset" in build_script, "signed preset restoration guard is missing")
    require(
        '--install-android-build-template --export-release "Android"' in build_script,
        "Android build template installation must be coupled to export so Godot exits",
    )
    require(
        build_script.count("--install-android-build-template") == 1,
        "Android build template installation must not run as a standalone Godot process",
    )

    artifact = read(".github/workflows/android-apk-artifact.yml")
    require("-AllowUnsignedRelease" in artifact, "APK artifact workflow does not use controlled unsigned export")
    require("V1.0.0.0" not in artifact, "APK artifact workflow contains a stale hard-coded version")
    require("project/version.json" in artifact, "APK artifact workflow does not derive canonical version")
    require("apksigner" in artifact and "aapt" in artifact, "APK signature/package validation is missing")
    require("android-emulator-runner" in artifact and "arch: x86_64" in artifact, "Android emulator validation is missing")
    require('adb install -r "$APK_PATH"' in artifact, "Android artifact smoke does not install the generated APK")
    emulator_script = artifact.split("script: |", 1)[1].split("- name: Upload APK artifact", 1)[0]
    require("set -eu" in emulator_script, "Android emulator smoke must fail fast under POSIX /bin/sh")
    require("pipefail" not in emulator_script, "Android emulator smoke uses Bash-only pipefail under POSIX /bin/sh")
    require("emulator-pid.txt" in emulator_script, "Android emulator smoke does not persist PID across runner shell commands")
    require(
        "; exit 1; fi" in emulator_script,
        "Android emulator crash check must stay on one line because the runner executes every line separately",
    )
    require(
        not any(line.strip() in {"then", "fi"} for line in emulator_script.splitlines()),
        "Android emulator smoke contains a multiline shell conditional that the runner cannot preserve",
    )
    require(
        emulator_script.index("adb logcat -d") < emulator_script.index("test -s build/android/emulator-pid.txt"),
        "Android failure diagnostics must be captured before the process liveness assertion",
    )

    release = read(".github/workflows/release.yml")
    require("Install and launch signed APK on Android 35" in release, "production Android emulator gate is missing")
    require("arch: x86_64" in release, "production Android emulator ABI drifted")
    require("dist/AuroraFox-Android.apk" in release, "production APK path changed unexpectedly")
    release_emulator_script = release.split("Install and launch signed APK on Android 35", 1)[1].split(
        "- name: Upload Android artifact", 1
    )[0]
    require("set -eu" in release_emulator_script, "production emulator smoke must use POSIX fail-fast mode")
    require("pipefail" not in release_emulator_script, "production emulator smoke uses Bash-only pipefail")
    require(
        "release-emulator-pid.txt" in release_emulator_script,
        "production emulator smoke does not persist PID across runner shell commands",
    )
    require(
        "; exit 1; fi" in release_emulator_script,
        "production emulator crash check must stay on one line",
    )
    require(
        not any(line.strip() in {"then", "fi"} for line in release_emulator_script.splitlines()),
        "production emulator smoke contains a multiline shell conditional",
    )

    ai_client = read("scripts/ai_client.gd")
    android_branch = ai_client.split('func chat(messages: Array, temperature: float = 0.2) -> Dictionary:', 1)[1].split('func _chat_ollama', 1)[0]
    require('if OS.get_name() == "Android":' in android_branch, "AIClient.chat lacks Android branch")
    require("android_runtime.is_available()" in android_branch, "AIClient.chat does not validate Android runtime")
    require("return await _chat_ollama" in android_branch, "desktop Ollama route is missing")
    require(
        android_branch.index('return await _chat_ollama') > android_branch.index('if OS.get_name() == "Android":'),
        "Android routing structure is malformed",
    )
    require("127.0.0.1:11434" not in android_branch, "Android chat branch directly references desktop Ollama")

    first_run = read("scripts/android_first_run.gd")
    require("AuroraFox готов." not in first_run, "Android model installer still claims full AuroraFox readiness")

    manifest = read("android_plugin/plugin/src/main/AndroidManifest.xml")
    require("REQUEST_INSTALL_PACKAGES" in manifest, "Android updater install permission is missing")
    require("AuroraUpdateProvider" in manifest, "Android update provider is missing")

    gradle = read("android_plugin/plugin/build.gradle.kts")
    require("compileSdk = 35" in gradle, "Android plugin compileSdk drifted")
    require("minSdk = 26" in gradle, "Android plugin minSdk drifted")
    require('abiFilters += listOf("arm64-v8a", "x86_64")' in gradle, "Android plugin ABI drifted")
    require('implementation("org.godotengine:godot:4.7.1.stable")' in gradle, "Godot Android plugin dependency drifted")

    print(f"AURORA_ANDROID_CONTRACT_OK version=V{numeric} code={state['android_version_code']} abis=arm64-v8a,x86_64")


if __name__ == "__main__":
    main()

