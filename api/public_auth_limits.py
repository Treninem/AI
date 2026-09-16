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
    "/v1/auth/logout",
    "/v1/auth/password-reset/request",
    "/v1/auth/password-reset/confirm",
    "/v1/auth/guest",
    "/verify-email",
    "/reset-password",
}
DEFAULT_MAX_BUCKETS = 10_000
DEFAULT_GLOBAL_LIMIT = 120


class PublicAuthRateLimitMiddleware:
    """Small single-process abuse guard for public account endpoints.

    The deployment currently runs one Uvicorn process, so an in-memory limiter is
    deterministic and dependency-free. X-Forwarded-For is trusted only when the
    direct ASGI peer is loopback (the local Caddy reverse proxy); direct Internet
    clients cannot spoof their rate-limit identity with that header.

    Bucket state is deliberately bounded. A stream of unique client identities
    must not be able to grow the process dictionary without limit; when the cap is
    full we first reap expired buckets and then fail closed for a new identity.

    A second process-wide budget protects the small 1-vCPU server from distributed
    public-auth bursts where every request arrives from a different IP and would
    therefore evade a per-client limiter. It is intentionally shared by all public
    auth paths, including guest creation, registration and password hashing.
    """

    def __init__(
        self,
        app: Callable[..., Awaitable[Any]],
        limit: int = 20,
        window_seconds: float = 60.0,
        max_buckets: int = DEFAULT_MAX_BUCKETS,
        global_limit: int = DEFAULT_GLOBAL_LIMIT,
    ):
        self.app = app
        self.limit = max(1, int(limit))
        self.window_seconds = max(1.0, float(window_seconds))
        self.max_buckets = max(1, int(max_buckets))
        self.global_limit = max(self.limit, int(global_limit))
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._global_hits: deque[float] = deque()
        self._lock = threading.Lock()
        self._checks = 0

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

    def _reap_expired_locked(self, now: float) -> None:
        while self._global_hits and now - self._global_hits[0] >= self.window_seconds:
            self._global_hits.popleft()
        expired: list[str] = []
        for key, queue in self._hits.items():
            while queue and now - queue[0] >= self.window_seconds:
                queue.popleft()
            if not queue:
                expired.append(key)
        for key in expired:
            self._hits.pop(key, None)

    def _allowed(self, key: str) -> bool:
        now = time.monotonic()
        with self._lock:
            self._checks += 1
            while self._global_hits and now - self._global_hits[0] >= self.window_seconds:
                self._global_hits.popleft()
            if len(self._global_hits) >= self.global_limit:
                return False

            queue = self._hits.get(key)
            if queue is not None:
                while queue and now - queue[0] >= self.window_seconds:
                    queue.popleft()
                if not queue:
                    self._hits.pop(key, None)
                    queue = None

            # Periodic cleanup keeps ordinary traffic compact. Capacity cleanup is
            # also forced before rejecting a previously unseen identity.
            if self._checks % 256 == 0:
                self._reap_expired_locked(now)
                queue = self._hits.get(key)
                if len(self._global_hits) >= self.global_limit:
                    return False
            if queue is None and len(self._hits) >= self.max_buckets:
                self._reap_expired_locked(now)
                queue = self._hits.get(key)
                if queue is None and len(self._hits) >= self.max_buckets:
                    return False

            if queue is None:
                queue = deque()
                self._hits[key] = queue
            if len(queue) >= self.limit:
                return False
            queue.append(now)
            self._global_hits.append(now)
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
        path = str(scope.get("path", ""))
        method = str(scope.get("method", "GET")).upper()
        if (
            scope.get("type") != "http"
            or path not in PUBLIC_AUTH_PATHS
            or method == "OPTIONS"
        ):
            await self.app(scope, receive, send)
            return
        identity = self._client_identity(scope)
        if not self._allowed(f"{method}:{path}:{identity}"):
            await self._reject(send)
            return
        await self.app(scope, receive, send)
