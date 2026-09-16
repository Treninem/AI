from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL_BYTES = "1282439264"
MODEL_SHA = "d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5"


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_canonical_version_is_v1_3() -> None:
    state = json.loads(read("project/version.json"))
    assert state["version"] == "V1.3.0.0"
    assert state["numeric"] == "1.3.0.0"
    assert state["android_version_code"] == 100005


def test_bundled_core_has_pinned_integrity_contract() -> None:
    source = read("scripts/bundled_core_model.gd")
    assert 'const BUNDLED_RESOURCE := "res://models/aurorafox-core.gguf"' in source
    assert 'const BUNDLED_WINDOWS_RELATIVE := "core_runtime/engine/aurorafox-core.gguf"' in source
    assert f"const EXPECTED_BYTES := {MODEL_BYTES}" in source
    assert f'const EXPECTED_SHA256 := "{MODEL_SHA}"' in source
    assert "ensure_android_private_copy" in source
    assert "bundled AuroraFox Core integrity check failed" in source


def test_normal_ai_client_uses_bundled_core_and_does_not_require_ollama() -> None:
    client = read("scripts/ai_client.gd")
    runtime = read("scripts/aurora_core_runtime.gd")
    assert "AuroraBundledCoreModel.runtime_candidate()" in client
    assert 'info["operational_without_ollama"] = true' in client
    assert "var allow_ollama_fallback := false" in runtime
    assert runtime.index("var local := await _chat_local") < runtime.index("if allow_ollama_fallback")
    assert 'OS.get_name() != "Android"' in runtime


def test_normal_scene_has_no_model_setup_wizard() -> None:
    scene = read("main.tscn")
    assert "models/model_setup_wizard.gd" not in scene
    assert "ModelSetup" not in scene


def test_windows_build_requires_engine_and_bundled_weights() -> None:
    build = read("build/build_windows.ps1")
    assert "prepare_bundled_windows_core.ps1" in build
    assert 'llama-server.exe' in build
    assert 'aurorafox-core.gguf' in build
    assert MODEL_BYTES in build
    assert MODEL_SHA in build
    assert "bundled AuroraFox Core remains mandatory" in build


def test_android_build_and_export_require_bundled_weights() -> None:
    build = read("build/build_android.ps1")
    presets = read("export_presets.cfg")
    assert "prepare_bundled_core_model.ps1" in build
    assert "models/aurorafox-core.gguf" in build
    assert MODEL_BYTES in build
    assert MODEL_SHA in build
    assert 'include_filter="update/release_public.pub,models/aurorafox-core.gguf"' in presets
    assert 'package/unique_name="com.aurorafox.ai"' in presets
    assert 'version/name="1.3.0.0"' in presets


def test_windows_and_android_package_strategies_are_intentional() -> None:
    presets = read("export_presets.cfg")
    # Windows copies the large model next to the engine instead of embedding it
    # in the PCK. Android must embed it because it is provisioned from res://.
    assert 'exclude_filter="models/aurorafox-core.gguf"' in presets
    assert presets.count("models/aurorafox-core.gguf") >= 2
