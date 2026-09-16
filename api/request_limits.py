from __future__ import annotations

import json
import threading
from typing import Any, Awaitable, Callable


DEFAULT_MAX_BODY_BYTES = 24 * 1024 * 1024
DEFAULT_MAX_IN_FLIGHT_BODY_BYTES = DEFAULT_MAX_BODY_BYTES * 4
REQUEST_TOO_LARGE_RESPONSE = {
    "status": 413,
    "detail": "AuroraFox API request body too large",
}
REQUEST_CAPACITY_RESPONSE = {
    "status": 503,
    "detail": "AuroraFox API request body capacity temporarily exhausted",
    "retry_after": 1,
}


class RequestBodyTooLarge(RuntimeError):
    pass


class RequestBodyCapacityExceeded(RuntimeError):
    pass


class RequestBodyLimitMiddleware:
    """Pure ASGI request-size and aggregate-memory guard.

    Content-Length is rejected before the application is entered. Requests
    without a trustworthy length header are counted while the downstream body
    parser reads ASGI chunks, preventing unbounded JSON/base64 materialization.

    A second bounded budget covers all HTTP request bodies concurrently being
    processed by this middleware instance. A 1 GiB production VPS must not be
    able to buffer an arbitrary number of individually-valid 24 MiB requests at
    once. Declared lengths reserve capacity before downstream parsing; chunked or
    understated bodies reserve additional capacity as bytes arrive. Capacity is
    released in ``finally`` on success and every failure path.

    WebSocket scopes are passed through unchanged.
    """

    def __init__(
        self,
        app: Callable[..., Awaitable[Any]],
        max_bytes: int = DEFAULT_MAX_BODY_BYTES,
        max_in_flight_bytes: int | None = None,
    ):
        self.app = app
        self.max_bytes = max(1, int(max_bytes))
        configured_budget = (
            self.max_bytes * 4 if max_in_flight_bytes is None else int(max_in_flight_bytes)
        )
        self.max_in_flight_bytes = max(self.max_bytes, configured_budget)
        self._in_flight_bytes = 0
        self._in_flight_lock = threading.Lock()

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

    def _reserve(self, amount: int) -> bool:
        amount = max(0, int(amount))
        if amount == 0:
            return True
        with self._in_flight_lock:
            if self._in_flight_bytes + amount > self.max_in_flight_bytes:
                return False
            self._in_flight_bytes += amount
            return True

    def _release(self, amount: int) -> None:
        amount = max(0, int(amount))
        if amount == 0:
            return
        with self._in_flight_lock:
            self._in_flight_bytes = max(0, self._in_flight_bytes - amount)

    @staticmethod
    async def _json_response(
        send: Callable[[dict[str, Any]], Awaitable[None]],
        *,
        status: int,
        detail: str,
        retry_after: int | None = None,
    ) -> None:
        payload = json.dumps({"detail": detail}, separators=(",", ":")).encode("utf-8")
        headers = [
            (b"content-type", b"application/json"),
            (b"content-length", str(len(payload)).encode("ascii")),
            (b"cache-control", b"no-store"),
        ]
        if retry_after is not None:
            headers.append((b"retry-after", str(max(1, int(retry_after))).encode("ascii")))
        await send({"type": "http.response.start", "status": status, "headers": headers})
        await send({"type": "http.response.body", "body": payload, "more_body": False})

    async def _reject_too_large(self, send: Callable[[dict[str, Any]], Awaitable[None]]) -> None:
        await self._json_response(send, **REQUEST_TOO_LARGE_RESPONSE)

    async def _reject_capacity(self, send: Callable[[dict[str, Any]], Awaitable[None]]) -> None:
        await self._json_response(send, **REQUEST_CAPACITY_RESPONSE)

    async def __call__(self, scope, receive, send) -> None:
        if scope.get("type") != "http":
            await self.app(scope, receive, send)
            return

        content_length = self._content_length(scope)
        if content_length is not None and content_length > self.max_bytes:
            await self._reject_too_large(send)
            return

        reserved = 0
        if content_length:
            if not self._reserve(content_length):
                await self._reject_capacity(send)
                return
            reserved = content_length

        received = 0
        response_started = False

        async def guarded_receive():
            nonlocal received, reserved
            message = await receive()
            if message.get("type") == "http.request":
                new_received = received + len(message.get("body", b""))
                if new_received > self.max_bytes:
                    raise RequestBodyTooLarge
                additional = max(0, new_received - reserved)
                if additional and not self._reserve(additional):
                    raise RequestBodyCapacityExceeded
                reserved += additional
                received = new_received
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
            await self._reject_too_large(send)
        except RequestBodyCapacityExceeded:
            if response_started:
                raise
            await self._reject_capacity(send)
        finally:
            self._release(reserved)
