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
    assert "FileAccess.get_sha256(temp).to_lower()" in source
    assert "copied_hash != EXPECTED_SHA256" in source


def test_normal_ai_client_is_self_primary_and_does_not_require_external_ai() -> None:
    client = read("scripts/ai_client.gd")
    runtime = read("scripts/aurora_core_runtime.gd")

    assert "AuroraBundledCoreModel.runtime_candidate()" in client
    assert 'info["self_primary"] = true' in client
    assert 'info["external_ai_required"] = false' in client
    assert 'info["normal_chat_external_fallback"] = false' in client
    assert 'info["operational_without_ollama"] = true' in client

    assert 'const LEGACY_OLLAMA_DEFAULT_MODEL := "qwen3:8b"' in client
    assert 'const LEGACY_OLLAMA_DEFAULT_URL := "http://127.0.0.1:11434"' in client
    assert "const DEFAULT_MODEL" not in client
    assert 'var model_source := "aurora_core"' not in client
    assert "configure_ollama_compatibility" in client

    # The normal intelligence path must be local-only. Compatibility is a
    # separate explicit method and therefore cannot silently become AgentCore's base.
    chat_block = client.split("func chat(messages:", 1)[1].split("func chat_with_compatibility", 1)[0]
    compatibility_block = client.split("func chat_with_compatibility", 1)[1].split("func import_knowledge_text", 1)[0]
    assert "core_runtime._chat_local" in chat_block
    assert "core_runtime.chat(" not in chat_block
    assert "core_runtime.chat(" in compatibility_block

    assert "var allow_ollama_fallback := false" in runtime
    assert runtime.index("var local := await _chat_local") < runtime.index("if allow_ollama_fallback")
    assert 'OS.get_name() != "Android"' in runtime


def test_core_improvement_uses_normal_self_primary_ai_path() -> None:
    pipeline = read("scripts/core_improvement_pipeline.gd")
    assert 'var response := await ai.chat([{"role":"user", "content":prompt}], 0.12)' in pipeline
    assert 'var response := await ai.chat([{"role":"user", "content":prompt}], 0.0)' in pipeline
    assert "chat_with_compatibility" not in pipeline


def test_hard_self_reliance_requirement_is_documented_for_all_agents() -> None:
    agents = read("AGENTS.md")
    master = read("docs/PROJECT_MASTER_LOG.md")
    readme = read("README.md")
    assert "self-primary and self-reliant" in agents
    assert "HARD PRODUCT INVARIANT" in agents
    assert "depend and rely on its own Core" in agents
    assert "External systems may be used only as **optional tools or information sources**" in agents
    assert "зависит и полагается только на себя" in master
    assert "ЖЁСТКИЙ АРХИТЕКТУРНЫЙ ИНВАРИАНТ" in master
    assert "Жёсткий принцип самостоятельности" in readme


def test_normal_scene_has_no_model_setup_wizard() -> None:
    scene = read("main.tscn")
    assert "models/model_setup_wizard.gd" not in scene
    assert "ModelSetup" not in scene


def test_windows_build_requires_engine_and_bundled_weights() -> None:
    build = read("build/build_windows.ps1")
    assert "prepare_bundled_windows_core.ps1" in build
    assert "llama-server.exe" in build
    assert "aurorafox-core.gguf" in build
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
    assert 'exclude_filter="models/aurorafox-core.gguf"' in presets
    assert presets.count("models/aurorafox-core.gguf") >= 2
