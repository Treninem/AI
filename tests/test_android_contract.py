from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE_SHA = "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5"
CORE_BYTES = 1282439264


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
    require(
        'include_filter="update/release_public.pub,models/aurorafox-core.gguf"' in preset,
        "Android export no longer includes the built-in AuroraFox Core weights",
    )

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
    require("prepare_bundled_core_model.ps1" in build_script, "Android build does not stage built-in AuroraFox Core")
    require("models/aurorafox-core.gguf" in build_script, "Android bundled Core export path drifted")
    require(str(CORE_BYTES) in build_script, "Android bundled Core byte contract is missing")
    require(CORE_SHA in build_script, "Android bundled Core SHA-256 contract is missing")
    require("Android APK is too small to contain bundled AuroraFox Core" in build_script, "APK size gate for bundled Core is missing")

    model_helper = read("build/prepare_bundled_core_model.ps1")
    require(CORE_SHA in model_helper, "Core preparation helper SHA-256 drifted")
    require(str(CORE_BYTES) in model_helper, "Core preparation helper byte count drifted")
    require("Test-CoreModel" in model_helper, "Core preparation helper no longer verifies the packaged weights")

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
    require(
        "return await core_runtime.chat(_with_knowledge(messages), temperature)" in ai_client,
        "AIClient.chat does not delegate inference to AuroraFox Core",
    )
    require(
        'info["operational_without_ollama"] = true' in ai_client,
        "AIClient no longer guarantees operation independent of Ollama",
    )
    require("AuroraBundledCoreModel.runtime_candidate()" in ai_client, "AIClient does not select the built-in Core automatically")

    bundled = read("scripts/bundled_core_model.gd")
    require('BUNDLED_RESOURCE := "res://models/aurorafox-core.gguf"' in bundled, "Android built-in Core resource path drifted")
    require(CORE_SHA in bundled, "Runtime built-in Core SHA-256 drifted")
    require(str(CORE_BYTES) in bundled, "Runtime built-in Core byte count drifted")
    require("ensure_android_private_copy" in bundled, "Android no longer silently provisions the bundled Core")

    core_runtime = read("scripts/aurora_core_runtime.gd")
    core_chat = core_runtime.split("func _chat_local(messages: Array, temperature: float) -> Dictionary:", 1)[1].split(
        "func _chat_ollama", 1
    )[0]
    require('if OS.get_name() == "Android":' in core_chat, "AuroraCoreRuntime lacks Android branch")
    require("android_runtime.is_available()" in core_chat, "AuroraCoreRuntime does not validate Android runtime")
    require('caps.get("llama_cpp", false)' in core_chat, "AuroraCoreRuntime does not require Android llama.cpp capability")
    require("android_runtime.chat(" in core_chat, "AuroraCoreRuntime does not invoke embedded Android inference")
    require("127.0.0.1:11434" not in core_chat, "Android local chat branch directly references Ollama")
    require("var allow_ollama_fallback := false" in core_runtime, "Ollama compatibility must be opt-in")
    require("OS.get_name() != \"Android\"" in core_runtime, "Ollama compatibility route is not excluded on Android")

    first_run = read("scripts/android_first_run.gd")
    require("AuroraFox готов." not in first_run, "Android model installer still claims full AuroraFox readiness")
    require("_ensure_bundled_core" in first_run, "Android first run does not silently provision built-in Core")
    require("Скачать рекомендуемую модель" not in first_run, "Android still exposes a model download wizard")
    require("Выбрать GGUF" not in first_run, "Android still exposes a GGUF chooser")
    require("FileDialog" not in first_run, "Android first run still exposes a model file picker")

    settings_fix = read("scripts/settings_visual_fix.gd")
    require('button.visible = false' in settings_fix, "Normal settings no longer hide model-management controls")
    require("AuroraFox Core встроен в приложение" in settings_fix, "Settings do not describe the built-in Core")

    manifest = read("android_plugin/plugin/src/main/AndroidManifest.xml")
    require("REQUEST_INSTALL_PACKAGES" in manifest, "Android updater install permission is missing")
    require("AuroraUpdateProvider" in manifest, "Android update provider is missing")

    gradle = read("android_plugin/plugin/build.gradle.kts")
    require("compileSdk = 35" in gradle, "Android plugin compileSdk drifted")
    require("minSdk = 26" in gradle, "Android plugin minSdk drifted")
    require('abiFilters += listOf("arm64-v8a", "x86_64")' in gradle, "Android plugin ABI drifted")
    require('implementation("org.godotengine:godot:4.7.1.stable")' in gradle, "Godot Android plugin dependency drifted")
    require(
        'implementation("com.tom-roush:pdfbox-android:$pdfBoxAndroidVersion")' in gradle,
        "Android local PDF text dependency is missing from plugin build",
    )

    export_plugin = read("addons/AuroraFoxRuntime/export_plugin.gd")
    require(
        'com.tom-roush:pdfbox-android:2.0.27.0' in export_plugin,
        "PDFBox dependency is not exported into the final Godot APK",
    )
    require(
        "return PackedStringArray([_pdfbox_dependency])" in export_plugin,
        "Godot Android export no longer exposes PDFBox Maven dependency",
    )

    file_runtime = read("android_plugin/plugin/src/main/java/com/aurorafox/runtime/AndroidFileRuntime.kt")
    require("PDFBoxResourceLoader.init" in file_runtime, "Android PDFBox runtime is not initialized")
    require("PDDocument.load(file).use" in file_runtime, "Android PDF text path does not open PDF locally")
    require("PDFTextStripper()" in file_runtime, "Android PDF text layer is not extracted")
    require('"engine" to "pdfbox-android"' in file_runtime, "Android PDF extraction engine metadata drifted")
    require('"offline" to true' in file_runtime, "Android PDF extraction must remain offline")
    require("PdfRenderer" not in file_runtime, "Android PDF path regressed to metadata-only PdfRenderer")

    print(
        f"AURORA_ANDROID_CONTRACT_OK version=V{numeric} code={state['android_version_code']} "
        f"abis=arm64-v8a,x86_64 pdf=offline core=bundled"
    )


if __name__ == "__main__":
    main()
