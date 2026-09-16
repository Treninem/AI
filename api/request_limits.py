from __future__ import annotations

import json
from typing import Any, Awaitable, Callable


DEFAULT_MAX_BODY_BYTES = 24 * 1024 * 1024


class RequestBodyTooLarge(RuntimeError):
    pass


class RequestBodyLimitMiddleware:
    """Pure ASGI request-size guard that also covers chunked bodies.

    Content-Length is rejected before the application is entered. Requests
    without a trustworthy length header are counted while the downstream body
    parser reads ASGI chunks, preventing unbounded JSON/base64 materialization.
    WebSocket scopes are passed through unchanged.
    """

    def __init__(self, app: Callable[..., Awaitable[Any]], max_bytes: int = DEFAULT_MAX_BODY_BYTES):
        self.app = app
        self.max_bytes = max(1, int(max_bytes))

    @staticmethod
    def _content_length(scope: dict[str, Any]) -> int | None:
        for key, value in scope.get("headers", []):
            if bytes(key).lower() != b"content-length":
                continue
            try:
                length = int(bytes(value).decode("ascii").strip())
            except (UnicodeDecodeError, ValueError):
                return None
            return max(0, length)
        return None

    async def _reject(self, send: Callable[[dict[str, Any]], Awaitable[None]]) -> None:
        payload = json.dumps(
            {"detail": "AuroraFox API request body too large"},
            separators=(",", ":"),
        ).encode("utf-8")
        await send(
            {
                "type": "http.response.start",
                "status": 413,
                "headers": [
                    (b"content-type", b"application/json"),
                    (b"content-length", str(len(payload)).encode("ascii")),
                    (b"cache-control", b"no-store"),
                ],
            }
        )
        await send({"type": "http.response.body", "body": payload, "more_body": False})

    async def __call__(self, scope, receive, send) -> None:
        if scope.get("type") != "http":
            await self.app(scope, receive, send)
            return

        content_length = self._content_length(scope)
        if content_length is not None and content_length > self.max_bytes:
            await self._reject(send)
            return

        received = 0
        response_started = False

        async def guarded_receive():
            nonlocal received
            message = await receive()
            if message.get("type") == "http.request":
                received += len(message.get("body", b""))
                if received > self.max_bytes:
                    raise RequestBodyTooLarge
            return message

        async def guarded_send(message):
            nonlocal response_started
            if message.get("type") == "http.response.start":
                response_started = True
            await send(message)

        try:
            await self.app(scope, guarded_receive, guarded_send)
        except RequestBodyTooLarge:
            if response_started:
                raise
            await self._reject(send)
