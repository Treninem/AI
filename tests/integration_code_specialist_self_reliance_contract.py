from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CODE_SPECIALIST = ROOT / "scripts" / "code_specialist.gd"


def _function_body(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.find(marker)
    assert start >= 0, f"missing {marker}"
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_code_specialist_setup_does_not_depend_on_removed_ai_client_transport_fields() -> None:
    source = CODE_SPECIALIST.read_text(encoding="utf-8")
    setup = _function_body(source, "setup(")

    assert "ai_client.base_url" not in setup, (
        "CodeSpecialist.setup must not read AIClient.base_url: the normal AuroraFox Core API no longer "
        "exposes an Ollama transport URL, and doing so crashes scene startup."
    )


def test_code_specialist_normal_chat_uses_aurorafox_core_instead_of_direct_ollama_http() -> None:
    source = CODE_SPECIALIST.read_text(encoding="utf-8")
    chat = _function_body(source, "_chat_code(")
    lower = chat.lower()

    assert "await general_ai.chat(messages, temperature)" in chat, (
        "CodeSpecialist normal generation must delegate to AIClient.chat(), whose normal path is bundled "
        "AuroraFox Core."
    )
    assert "httprequest.new()" not in lower, (
        "CodeSpecialist normal generation must not create a direct provider HTTP request."
    )
    assert "ollama" not in lower, (
        "Ollama may exist only behind explicit compatibility APIs; it cannot be the normal CodeSpecialist path."
    )
    assert "/api/chat" not in lower, (
        "Provider-specific chat endpoints are forbidden in CodeSpecialist normal generation."
    )
