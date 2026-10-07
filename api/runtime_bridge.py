from __future__ import annotations

import json
import os
import socket
import uuid
from pathlib import Path
from typing import Any

from api.local_core_client import AuroraKnowledgeFallback, AuroraLocalCoreClient
from api.provider_resource_policy import nonnegative_seconds, socket_timeout
from api.request_limits import _nonnegative_budget


class AuroraRuntimeBridge:
    def __init__(self, host: str = "127.0.0.1", port: int = 8770, timeout: float | None = None,
                 connect_timeout: float | None = None, max_response_bytes: int | None = None):
        self.host = host
        self.port = port
        self.timeout = nonnegative_seconds(os.getenv("AURORAFOX_API_BRIDGE_READ_SECONDS", "180") if timeout is None else timeout, "AURORAFOX_API_BRIDGE_READ_SECONDS")
        connect_default = min(self.timeout, 8.0) if self.timeout > 0 else 8.0
        self.connect_timeout = nonnegative_seconds(os.getenv("AURORAFOX_API_BRIDGE_CONNECT_SECONDS", str(connect_default)) if connect_timeout is None else connect_timeout, "AURORAFOX_API_BRIDGE_CONNECT_SECONDS")
        self.max_response_bytes = _nonnegative_budget(os.getenv("AURORAFOX_API_BRIDGE_RESPONSE_BYTES", str(8 * 1024 * 1024)) if max_response_bytes is None else max_response_bytes, "AURORAFOX_API_BRIDGE_RESPONSE_BYTES")
        user_root = Path(os.getenv("AURORAFOX_USER_DIR", str(Path.home() / ".aurorafox"))).resolve()
        self.local_core = AuroraLocalCoreClient(user_root)
        self.local_knowledge = AuroraKnowledgeFallback(user_root)

    def request(self, op: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
        request_id = uuid.uuid4().hex
        body = {"request_id": request_id, "op": op, "payload": payload or {}}
        raw = (json.dumps(body, ensure_ascii=False) + "\n").encode("utf-8")
        with socket.create_connection((self.host, self.port), timeout=socket_timeout(self.connect_timeout)) as sock:
            sock.settimeout(socket_timeout(self.timeout))
            sock.sendall(raw)
            buffer = bytearray()
            while True:
                read_bytes = 65536 if self.max_response_bytes == 0 else min(65536, self.max_response_bytes + 1 - len(buffer))
                chunk = sock.recv(read_bytes)
                if not chunk:
                    break
                buffer.extend(chunk)
                newline = buffer.find(b"\n")
                frame_bytes = newline + 1 if newline >= 0 else len(buffer)
                if self.max_response_bytes > 0 and frame_bytes > self.max_response_bytes:
                    raise RuntimeError("AuroraFox bridge response exceeds owner byte budget")
                if newline >= 0:
                    line = bytes(buffer[:newline])
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
