from __future__ import annotations

import asyncio
import json

from api.request_limits import RequestBodyLimitMiddleware


def _scope(headers=None, scope_type="http"):
    return {
        "type": scope_type,
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": "POST",
        "scheme": "http",
        "path": "/test",
        "raw_path": b"/test",
        "query_string": b"",
        "headers": headers or [],
        "client": ("127.0.0.1", 1),
        "server": ("127.0.0.1", 80),
    }


def test_content_length_over_limit_is_rejected_before_downstream():
    called = False
    sent = []

    async def app(scope, receive, send):
        nonlocal called
        called = True

    async def receive():
        raise AssertionError("receive must not be called for early length rejection")

    async def send(message):
        sent.append(message)

    middleware = RequestBodyLimitMiddleware(app, max_bytes=8)
    asyncio.run(middleware(_scope([(b"content-length", b"9")]), receive, send))

    assert called is False
    assert sent[0]["type"] == "http.response.start"
    assert sent[0]["status"] == 413
    body = json.loads(sent[1]["body"])
    assert body["detail"] == "AuroraFox API request body too large"


def test_chunked_body_is_counted_and_rejected_without_content_length():
    sent = []
    chunks = iter(
        [
            {"type": "http.request", "body": b"12345", "more_body": True},
            {"type": "http.request", "body": b"6789", "more_body": False},
        ]
    )

    async def receive():
        return next(chunks)

    async def send(message):
        sent.append(message)

    async def app(scope, receive, send):
        await receive()
        await receive()
        raise AssertionError("oversized body must interrupt downstream parsing")

    middleware = RequestBodyLimitMiddleware(app, max_bytes=8)
    asyncio.run(middleware(_scope(), receive, send))
    assert sent[0]["status"] == 413


def test_body_within_limit_reaches_downstream_unchanged():
    sent = []
    chunks = iter(
        [
            {"type": "http.request", "body": b"abc", "more_body": True},
            {"type": "http.request", "body": b"def", "more_body": False},
        ]
    )
    observed = []

    async def receive():
        return next(chunks)

    async def send(message):
        sent.append(message)

    async def app(scope, receive, send):
        observed.append((await receive())["body"])
        observed.append((await receive())["body"])
        await send({"type": "http.response.start", "status": 204, "headers": []})
        await send({"type": "http.response.body", "body": b"", "more_body": False})

    middleware = RequestBodyLimitMiddleware(app, max_bytes=6)
    asyncio.run(middleware(_scope(), receive, send))
    assert observed == [b"abc", b"def"]
    assert sent[0]["status"] == 204


def test_websocket_scope_is_not_body_limited():
    called = False

    async def app(scope, receive, send):
        nonlocal called
        called = True

    async def receive():
        return {"type": "websocket.disconnect", "code": 1000}

    async def send(message):
        return None

    middleware = RequestBodyLimitMiddleware(app, max_bytes=1)
    asyncio.run(middleware(_scope(scope_type="websocket"), receive, send))
    assert called is True
