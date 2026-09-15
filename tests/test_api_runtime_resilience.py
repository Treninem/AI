from __future__ import annotations

from pathlib import Path

from api.ollama_client import OllamaClient
from api.runtime_bridge import AuroraRuntimeBridge


def test_explicit_ollama_mode_falls_back_to_aurora_local_core(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setenv("AURORAFOX_USER_DIR", str(tmp_path))
    client = OllamaClient("http://127.0.0.1:9", "missing:model")
    monkeypatch.setattr(client, "models", lambda: (_ for _ in ()).throw(ConnectionError("ollama offline")))
    monkeypatch.setattr(
        client.local_core,
        "chat",
        lambda messages, temperature=0.2: {
            "ok": True,
            "content": "local core answer",
            "model": "AuroraFox-Core",
            "runtime": "aurorafox-local-core",
        },
    )
    result = client.chat([{"role": "user", "content": "hello"}])
    assert result["ok"] is True
    assert result["content"] == "local core answer"
    assert result["runtime"] == "aurorafox-local-core"
    assert result["compatibility_fallback"]["from"] == "ollama"


def test_bridge_failure_falls_back_to_local_core_instead_of_raising(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setenv("AURORAFOX_USER_DIR", str(tmp_path))
    bridge = AuroraRuntimeBridge(port=9)
    monkeypatch.setattr(bridge, "request", lambda *_args, **_kwargs: (_ for _ in ()).throw(ConnectionError("bridge offline")))
    monkeypatch.setattr(
        bridge.local_core,
        "chat",
        lambda messages, temperature=0.2: {
            "ok": True,
            "content": "answer without bridge",
            "model": "AuroraFox-Core",
            "runtime": "aurorafox-local-core",
        },
    )
    result = bridge.chat("hello", [], "conversation")
    assert result["ok"] is True
    assert result["content"] == "answer without bridge"
    assert result["details"]["fallback_runtime"] == "aurorafox-local-core"
    assert result["details"]["agent_bridge_online"] is False


def test_total_runtime_failure_still_returns_local_knowledge(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setenv("AURORAFOX_USER_DIR", str(tmp_path))
    knowledge = tmp_path / "knowledge"
    knowledge.mkdir(parents=True)
    (knowledge / "knowledge.jsonl").write_text(
        '{"text":"AuroraFox local recovery keeps working without Ollama", "source":"fixture"}\n',
        encoding="utf-8",
    )
    client = OllamaClient("http://127.0.0.1:9")
    monkeypatch.setattr(client, "models", lambda: (_ for _ in ()).throw(ConnectionError("ollama offline")))
    monkeypatch.setattr(client.local_core, "chat", lambda *_args, **_kwargs: (_ for _ in ()).throw(RuntimeError("core offline")))
    result = client.chat([{"role": "user", "content": "AuroraFox recovery Ollama"}])
    assert result["ok"] is True
    assert result["runtime"] == "aurorafox-local-knowledge"
    assert "local recovery" in result["content"]


def test_total_runtime_failure_without_matching_knowledge_is_still_non_503(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setenv("AURORAFOX_USER_DIR", str(tmp_path))
    client = OllamaClient("http://127.0.0.1:9")
    monkeypatch.setattr(client, "models", lambda: (_ for _ in ()).throw(ConnectionError("ollama offline")))
    monkeypatch.setattr(client.local_core, "chat", lambda *_args, **_kwargs: (_ for _ in ()).throw(RuntimeError("core offline")))
    result = client.chat([{"role": "user", "content": "unique query"}])
    assert result["ok"] is True
    assert result["runtime"] == "aurorafox-local-deterministic"
    assert result["degraded"] is True
