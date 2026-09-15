from __future__ import annotations

from typing import Any


class ResilientChatRouter:
    """Route chat without making any compatibility provider mandatory."""

    def __init__(self, bridge, local_core, ollama, knowledge, *, ollama_enabled: bool = False) -> None:
        self.bridge = bridge
        self.local_core = local_core
        self.ollama = ollama
        self.knowledge = knowledge
        self.ollama_enabled = bool(ollama_enabled)

    def execute(
        self,
        message: str,
        context: list[dict[str, Any]],
        mode: str,
        temperature: float,
        conversation_id: str,
        metadata: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        metadata = metadata or {}
        messages = list(context) + [{"role": "user", "content": message}]
        failures: list[dict[str, str]] = []

        if mode == "ollama":
            result = self._try_ollama(messages, temperature, failures, explicit=True)
            if result is not None:
                result["fallbacks"] = failures
                return result

        if mode in {"auto", "agent"}:
            try:
                result = self.bridge.chat(message, context, conversation_id, metadata)
                if isinstance(result, dict) and result.get("ok", False):
                    return {
                        "ok": True,
                        "content": str(result.get("content", "")),
                        "runtime": "aurorafox-agent",
                        "model": str(result.get("model", "agent")),
                        "details": result.get("details", {}),
                        "fallbacks": failures,
                    }
                failures.append({"runtime": "aurorafox-agent", "error": str(result.get("error", "bridge rejected request")) if isinstance(result, dict) else "invalid bridge result"})
            except Exception as exc:
                failures.append({"runtime": "aurorafox-agent", "error": str(exc)})

        try:
            result = self.local_core.chat(messages, temperature=temperature)
            if isinstance(result, dict) and result.get("ok", False):
                result["fallbacks"] = failures
                return result
            failures.append({"runtime": "aurorafox-local-core", "error": str(result.get("error", "local Core rejected request")) if isinstance(result, dict) else "invalid local Core result"})
        except Exception as exc:
            failures.append({"runtime": "aurorafox-local-core", "error": str(exc)})

        if mode != "ollama" and self.ollama_enabled:
            result = self._try_ollama(messages, temperature, failures, explicit=False)
            if result is not None:
                result["fallbacks"] = failures
                return result

        # A broken/missing Ollama adapter must never turn the whole AuroraFox API
        # into a 503. Return the best deterministic local answer that is still
        # available from Core Knowledge instead.
        result = self.knowledge.reply(message)
        result["fallbacks"] = failures
        return result

    def _try_ollama(
        self,
        messages: list[dict[str, Any]],
        temperature: float,
        failures: list[dict[str, str]],
        *,
        explicit: bool,
    ) -> dict[str, Any] | None:
        if not explicit and not self.ollama_enabled:
            return None
        try:
            result = self.ollama.chat(messages, temperature=temperature)
            if isinstance(result, dict) and result.get("ok", False):
                return result
            failures.append({"runtime": "ollama", "error": str(result.get("error", "Ollama rejected request")) if isinstance(result, dict) else "invalid Ollama result"})
        except Exception as exc:
            failures.append({"runtime": "ollama", "error": str(exc)})
        return None
