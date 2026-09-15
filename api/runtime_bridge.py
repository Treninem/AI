from __future__ import annotations

import json
import os
import socket
import uuid
from pathlib import Path
from typing import Any

from api.local_core_client import AuroraKnowledgeFallback, AuroraLocalCoreClient


class AuroraRuntimeBridge:
    def __init__(self, host: str = "127.0.0.1", port: int = 8770, timeout: float = 180.0):
        self.host = host
        self.port = port
        self.timeout = timeout
        user_root = Path(os.getenv("AURORAFOX_USER_DIR", str(Path.home() / ".aurorafox"))).resolve()
        self.local_core = AuroraLocalCoreClient(user_root)
        self.local_knowledge = AuroraKnowledgeFallback(user_root)

    def request(self, op: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
        request_id = uuid.uuid4().hex
        body = {"request_id": request_id, "op": op, "payload": payload or {}}
        raw = (json.dumps(body, ensure_ascii=False) + "\n").encode("utf-8")
        with socket.create_connection((self.host, self.port), timeout=min(self.timeout, 8.0)) as sock:
            sock.settimeout(self.timeout)
            sock.sendall(raw)
            buffer = bytearray()
            while len(buffer) < 8 * 1024 * 1024:
                chunk = sock.recv(65536)
                if not chunk:
                    break
                buffer.extend(chunk)
                if b"\n" in buffer:
                    line = bytes(buffer).split(b"\n", 1)[0]
                    data = json.loads(line.decode("utf-8"))
                    if not isinstance(data, dict):
                        raise RuntimeError("Invalid AuroraFox bridge response")
                    if str(data.get("request_id", "")) != request_id:
                        raise RuntimeError("AuroraFox bridge request id mismatch")
                    return data
        raise RuntimeError("AuroraFox bridge closed without a response")

    def chat(
        self,
        message: str,
        context: list[dict[str, Any]],
        conversation_id: str,
        metadata: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        try:
            return self.request("chat", {
                "message": message,
                "context": context,
                "conversation_id": conversation_id,
                "metadata": metadata or {},
            })
        except Exception as bridge_exc:
            messages = list(context) + [{"role": "user", "content": message}]
            try:
                local = self.local_core.chat(messages, temperature=float((metadata or {}).get("temperature", 0.2)))
                return {
                    "ok": True,
                    "content": str(local.get("content", "")),
                    "model": str(local.get("model", "AuroraFox-Core")),
                    "details": {
                        "fallback_runtime": str(local.get("runtime", "aurorafox-local-core")),
                        "agent_bridge_online": False,
                        "bridge_error": str(bridge_exc)[:1000],
                    },
                }
            except Exception as local_exc:
                local = self.local_knowledge.reply(message)
                return {
                    "ok": True,
                    "content": str(local.get("content", "")),
                    "model": str(local.get("model", "local-knowledge")),
                    "details": {
                        "fallback_runtime": str(local.get("runtime", "aurorafox-local-knowledge")),
                        "agent_bridge_online": False,
                        "bridge_error": str(bridge_exc)[:1000],
                        "local_core_error": str(local_exc)[:1000],
                        "degraded": True,
                    },
                }

    def status(self) -> dict[str, Any]:
        return self.request("status")

    def tools(self) -> dict[str, Any]:
        return self.request("tools")

    def run_tool(self, name: str, args: dict[str, Any]) -> dict[str, Any]:
        return self.request("tool", {"name": name, "args": args})

    def learn(self, event: dict[str, Any]) -> dict[str, Any]:
        return self.request("learn", event)

    def feedback(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self.request("feedback", payload)
