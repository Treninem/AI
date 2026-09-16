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


def test_concurrent_declared_bodies_respect_aggregate_budget_and_release_it():
    async def scenario():
        entered = asyncio.Event()
        release = asyncio.Event()
        first_sent = []
        blocked_sent = []
        retry_sent = []
        calls = 0

        async def app(scope, receive, send):
            nonlocal calls
            calls += 1
            entered.set()
            await release.wait()
            await send({"type": "http.response.start", "status": 204, "headers": []})
            await send({"type": "http.response.body", "body": b"", "more_body": False})

        async def receive():
            return {"type": "http.request", "body": b"", "more_body": False}

        async def first_send(message):
            first_sent.append(message)

        async def blocked_send(message):
            blocked_sent.append(message)

        async def retry_send(message):
            retry_sent.append(message)

        middleware = RequestBodyLimitMiddleware(app, max_bytes=8, max_in_flight_bytes=8)
        first = asyncio.create_task(
            middleware(_scope([(b"content-length", b"8")]), receive, first_send)
        )
        await entered.wait()

        # The first request owns the whole aggregate budget even before its body
        # is parsed. A second otherwise-valid request must fail fast and must not
        # enter the downstream application.
        await middleware(_scope([(b"content-length", b"1")]), receive, blocked_send)
        assert blocked_sent[0]["status"] == 503
        assert (b"retry-after", b"1") in blocked_sent[0]["headers"]
        assert json.loads(blocked_sent[1]["body"])["detail"].endswith(
            "capacity temporarily exhausted"
        )
        assert calls == 1

        release.set()
        await first
        assert first_sent[0]["status"] == 204
        assert middleware._in_flight_bytes == 0

        # Budget is released in finally; a later request immediately succeeds.
        await middleware(_scope([(b"content-length", b"1")]), receive, retry_send)
        assert retry_sent[0]["status"] == 204
        assert calls == 2
        assert middleware._in_flight_bytes == 0

    asyncio.run(scenario())


def test_chunked_body_respects_aggregate_budget():
    async def scenario():
        entered = asyncio.Event()
        release = asyncio.Event()
        blocked_sent = []

        async def app(scope, receive, send):
            if scope.get("headers"):
                entered.set()
                await release.wait()
                await send({"type": "http.response.start", "status": 204, "headers": []})
                await send({"type": "http.response.body", "body": b"", "more_body": False})
                return
            await receive()
            raise AssertionError("chunked request must stop when aggregate budget is exhausted")

        async def empty_receive():
            return {"type": "http.request", "body": b"", "more_body": False}

        chunk_sent = False

        async def chunk_receive():
            nonlocal chunk_sent
            if chunk_sent:
                return {"type": "http.request", "body": b"", "more_body": False}
            chunk_sent = True
            return {"type": "http.request", "body": b"123", "more_body": False}

        async def sink(_message):
            return None

        async def blocked_send(message):
            blocked_sent.append(message)

        middleware = RequestBodyLimitMiddleware(app, max_bytes=8, max_in_flight_bytes=8)
        first = asyncio.create_task(
            middleware(_scope([(b"content-length", b"6")]), empty_receive, sink)
        )
        await entered.wait()
        await middleware(_scope(), chunk_receive, blocked_send)
        assert blocked_sent[0]["status"] == 503
        assert middleware._in_flight_bytes == 6
        release.set()
        await first
        assert middleware._in_flight_bytes == 0

    asyncio.run(scenario())


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
