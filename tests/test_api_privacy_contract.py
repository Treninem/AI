from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_api_chat_uses_private_agent_memory_and_experience():
    bridge = read("api/agent_bridge.gd")
    assert "ApiPrivateMemoryView.new(memory)" in bridge
    assert "ApiPrivateExperienceStore.new()" in bridge
    assert '"privacy": "conversation_scoped"' in bridge
    assert '"shared_episodic_memory": false' in bridge


def test_private_memory_view_exposes_knowledge_not_episodic_memory():
    view = read("api/private_memory_view.gd")
    assert "func remember(" in view
    assert "pass" in view
    assert "return []" in view
    assert "shared_store.retrieve(query, limit, false, true)" in view
    assert 'status["episodic_memory_visible"] = false' in view


def test_private_experience_never_persists_request_local_failures_or_skills():
    store = read("api/private_experience_store.gd")
    assert "extends ExperienceStore" in store
    assert "func _save_array" in store
    assert "pass" in store.split("func _save_array", 1)[1]


def test_feedback_requires_explicit_global_learning_opt_in():
    bridge = read("api/agent_bridge.gd")
    assert 'metadata.get("share_for_learning", false)' in bridge
    assert '"global_learning": false' in bridge
    assert '"global_learning": true' in bridge


def test_implicit_fallback_learning_is_private_by_default():
    sync = read("api/learning_sync.py")
    assert 'kind != "api_interaction"' in sync
    assert 'metadata.get("share_for_learning", False)' in sync
    assert '"skipped_private": True' in sync


def test_personal_account_chat_cannot_enter_shared_learning_implicitly():
    server = read("api/server.py")
    assert 'str(record.get("auth_kind", "api_key")) == "api_key"' in server
    assert '"auth_kind": "account_session"' in read("api/account_store.py")
    assert '"auth_kind": "guest_session"' in read("api/account_store.py")
    assert '"memory.write"' not in read("api/account_store.py").split("USER_SCOPES = [", 1)[1].split("]", 1)[0]


def test_normal_server_chat_never_auto_falls_back_to_optional_ollama():
    server = read("api/server.py")
    assert 'if mode in {"auto", "agent"}:' in server
    assert 'provider_policy": "agent_then_local_core_then_local_knowledge;ollama_explicit_compatibility_only"' in server
    normal_block = server.split('if mode in {"auto", "agent"}:', 1)[1].split('messages = list(context)', 1)[0]
    assert "ollama.chat" not in normal_block
