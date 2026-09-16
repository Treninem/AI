from __future__ import annotations

import ipaddress
import json
import threading
import time
from collections import defaultdict, deque
from typing import Any, Awaitable, Callable


PUBLIC_AUTH_PATHS = {
    "/v1/auth/register",
    "/v1/auth/verify-email",
    "/v1/auth/resend-verification",
    "/v1/auth/login",
    "/v1/auth/refresh",
    "/v1/auth/password-reset/request",
    "/v1/auth/password-reset/confirm",
    "/v1/auth/guest",
    "/verify-email",
    "/reset-password",
}


class PublicAuthRateLimitMiddleware:
    """Small single-process abuse guard for public account endpoints.

    The deployment currently runs one Uvicorn process, so an in-memory limiter is
    deterministic and dependency-free. X-Forwarded-For is trusted only when the
    direct ASGI peer is loopback (the local Caddy reverse proxy); direct Internet
    clients cannot spoof their rate-limit identity with that header.
    """

    def __init__(
        self,
        app: Callable[..., Awaitable[Any]],
        limit: int = 20,
        window_seconds: float = 60.0,
    ):
        self.app = app
        self.limit = max(1, int(limit))
        self.window_seconds = max(1.0, float(window_seconds))
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    @staticmethod
    def _header(scope: dict[str, Any], name: bytes) -> str:
        for key, value in scope.get("headers", []):
            if bytes(key).lower() == name:
                try:
                    return bytes(value).decode("latin-1").strip()
                except Exception:
                    return ""
        return ""

    @classmethod
    def _client_identity(cls, scope: dict[str, Any]) -> str:
        client = scope.get("client") or ("unknown", 0)
        peer = str(client[0] if isinstance(client, (tuple, list)) and client else "unknown")
        try:
            peer_ip = ipaddress.ip_address(peer)
        except ValueError:
            return peer[:128]
        if peer_ip.is_loopback:
            forwarded = cls._header(scope, b"x-forwarded-for")
            if forwarded:
                first = forwarded.split(",", 1)[0].strip()
                try:
                    return str(ipaddress.ip_address(first))
                except ValueError:
                    pass
        return str(peer_ip)

    def _allowed(self, key: str) -> bool:
        now = time.monotonic()
        with self._lock:
            queue = self._hits[key]
            while queue and now - queue[0] >= self.window_seconds:
                queue.popleft()
            if len(queue) >= self.limit:
                return False
            queue.append(now)
            return True

    async def _reject(self, send: Callable[[dict[str, Any]], Awaitable[None]]) -> None:
        payload = json.dumps(
            {"detail": "AuroraFox public authentication rate limit exceeded"},
            separators=(",", ":"),
        ).encode("utf-8")
        await send(
            {
                "type": "http.response.start",
                "status": 429,
                "headers": [
                    (b"content-type", b"application/json"),
                    (b"content-length", str(len(payload)).encode("ascii")),
                    (b"cache-control", b"no-store"),
                    (b"retry-after", str(max(1, int(self.window_seconds))).encode("ascii")),
                ],
            }
        )
        await send({"type": "http.response.body", "body": payload, "more_body": False})

    async def __call__(self, scope, receive, send) -> None:
        if scope.get("type") != "http" or str(scope.get("path", "")) not in PUBLIC_AUTH_PATHS:
            await self.app(scope, receive, send)
            return
        identity = self._client_identity(scope)
        method = str(scope.get("method", "GET")).upper()
        path = str(scope.get("path", ""))
        if not self._allowed(f"{method}:{path}:{identity}"):
            await self._reject(send)
            return
        await self.app(scope, receive, send)
