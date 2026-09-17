from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = "sherpa-onnx-supertonic-3-tts-int8-2026-05-11"
ARCHIVE_BYTES = 128774318
ARCHIVE_SHA256 = "82fa96f91c4ef8abaae3a14a3f4153facf88bed821d1f7331cec2700f432c427"
REQUIRED = (
    "duration_predictor.int8.onnx",
    "text_encoder.int8.onnx",
    "vector_estimator.int8.onnx",
    "vocoder.int8.onnx",
    "tts.json",
    "unicode_indexer.bin",
    "voice.bin",
)


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    runtime = read("android_plugin/plugin/src/main/java/com/aurorafox/runtime/AndroidVoiceRuntime.kt")
    setup = read("android_plugin/setup_native.ps1")
    gradle = read("android_plugin/plugin/build.gradle.kts")

    require(MODEL in runtime, "Android runtime is not pointed at the pinned Supertonic 3 asset root")
    require("OfflineTtsSupertonicModelConfig" in runtime, "Android runtime does not configure Supertonic")
    require("OfflineTtsVitsModelConfig" not in runtime, "Android runtime still compiles the Piper/VITS TTS path")
    require('extra = mapOf("lang" to supertonicLanguage)' in runtime, "Supertonic generation does not select Russian")
    require('private val supertonicLanguage = "ru"' in runtime, "Android Supertonic language must remain Russian")
    require('private val supertonicSpeakerId = 0' in runtime, "Current isolated female-candidate runtime must use F1/sid 0")
    require('private val supertonicSpeakerName = "F1"' in runtime, "Current isolated female-candidate metadata must match sid 0")
    require('put("engine", "sherpa-onnx-supertonic-3")' in runtime, "Runtime metadata does not identify Supertonic")
    require("piper-denis" not in runtime.lower(), "Male Piper Denis runtime path is still active")
    require("vits-piper-ru_RU-denis-medium" not in runtime, "Male Piper Denis asset root is still active")
    require("http://" not in runtime and "https://" not in runtime, "Android runtime must not download TTS assets")

    for filename in REQUIRED:
        require(filename in runtime, f"Runtime is missing required Supertonic file contract: {filename}")
        require(filename in setup, f"Build staging is missing required Supertonic file contract: {filename}")

    require(MODEL in setup, "Build staging does not use the audited Supertonic archive name")
    require(str(ARCHIVE_BYTES) in setup, "Build staging does not pin audited Supertonic archive bytes")
    require(ARCHIVE_SHA256 in setup, "Build staging does not pin audited Supertonic SHA-256")
    require("Assert-FileIdentity" in setup, "Build staging no longer fails closed on archive identity")
    require(".aurorafox-source.sha256" in setup, "Extracted Supertonic cache lacks source identity marker")
    require("Remove-Item -LiteralPath $ttsFolder -Recurse -Force" in setup, "Stale extracted Supertonic assets are not replaced")
    require("github.com/k2-fsa/sherpa-onnx/releases/download/tts-models" in setup, "Supertonic build source drifted")
    require("vits-piper-ru_RU-denis-medium" not in setup, "Male Piper Denis is still staged into the Android build")

    require('val sherpaVersion = "1.13.4"' in gradle, "sherpa-onnx dependency drifted from the verified Supertonic API")
    require("compileOnly(files(sherpaAar))" in gradle, "Android plugin no longer compiles against the pinned sherpa AAR")

    print(
        "AURORA_ANDROID_VOICE_SUPERTONIC_CONTRACT_OK "
        f"model={MODEL} bytes={ARCHIVE_BYTES} sha256={ARCHIVE_SHA256} candidate=F1 sid=0 lang=ru"
    )


if __name__ == "__main__":
    main()
