from __future__ import annotations

import asyncio
import json

from api.public_auth_limits import PublicAuthRateLimitMiddleware


def _scope(path="/v1/auth/login", client=("203.0.113.10", 1234), headers=None, method="POST"):
    return {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": method,
        "scheme": "https",
        "path": path,
        "raw_path": path.encode("ascii"),
        "query_string": b"",
        "headers": headers or [],
        "client": client,
        "server": ("127.0.0.1", 8768),
    }


async def _run_once(middleware, scope):
    sent = []

    async def receive():
        return {"type": "http.request", "body": b"", "more_body": False}

    async def send(message):
        sent.append(message)

    await middleware(scope, receive, send)
    return sent


def test_public_auth_path_is_limited_per_client_and_endpoint():
    calls = []

    async def app(scope, receive, send):
        calls.append((scope["method"], scope["path"]))
        await send({"type": "http.response.start", "status": 204, "headers": []})
        await send({"type": "http.response.body", "body": b"", "more_body": False})

    middleware = PublicAuthRateLimitMiddleware(app, limit=2, window_seconds=60)
    first = asyncio.run(_run_once(middleware, _scope()))
    second = asyncio.run(_run_once(middleware, _scope()))
    third = asyncio.run(_run_once(middleware, _scope()))
    assert first[0]["status"] == 204
    assert second[0]["status"] == 204
    assert third[0]["status"] == 429
    assert len(calls) == 2
    assert json.loads(third[1]["body"])["detail"].startswith("AuroraFox public authentication")

    # A different public auth endpoint has a separate per-client bucket.
    other = asyncio.run(_run_once(middleware, _scope(path="/v1/auth/password-reset/request")))
    assert other[0]["status"] == 204


def test_global_budget_blocks_distributed_auth_burst_and_recovers(monkeypatch):
    calls = 0
    clock = [100.0]
    monkeypatch.setattr("api.public_auth_limits.time.monotonic", lambda: clock[0])

    async def app(scope, receive, send):
        nonlocal calls
        calls += 1
        await send({"type": "http.response.start", "status": 204, "headers": []})
        await send({"type": "http.response.body", "body": b"", "more_body": False})

    middleware = PublicAuthRateLimitMiddleware(
        app,
        limit=2,
        window_seconds=60,
        max_buckets=10,
        global_limit=2,
    )
    first = asyncio.run(
        _run_once(middleware, _scope(path="/v1/auth/guest", client=("203.0.113.1", 1)))
    )
    second = asyncio.run(
        _run_once(middleware, _scope(path="/v1/auth/register", client=("203.0.113.2", 1)))
    )
    blocked = asyncio.run(
        _run_once(middleware, _scope(path="/v1/auth/login", client=("203.0.113.3", 1)))
    )
    assert first[0]["status"] == 204
    assert second[0]["status"] == 204
    assert blocked[0]["status"] == 429
    assert calls == 2
    assert len(middleware._global_hits) == 2
    assert len(middleware._hits) == 2

    # Expired global capacity is reclaimed just like per-client buckets; a
    # distributed burst cannot permanently wedge public authentication.
    clock[0] = 161.0
    recovered = asyncio.run(
        _run_once(middleware, _scope(path="/v1/auth/login", client=("203.0.113.3", 1)))
    )
    assert recovered[0]["status"] == 204
    assert calls == 3
    assert len(middleware._global_hits) == 1


def test_bucket_state_is_bounded_and_expired_capacity_is_reclaimed(monkeypatch):
    calls = 0
    clock = [100.0]
    monkeypatch.setattr("api.public_auth_limits.time.monotonic", lambda: clock[0])

    async def app(scope, receive, send):
        nonlocal calls
        calls += 1
        await send({"type": "http.response.start", "status": 204, "headers": []})
        await send({"type": "http.response.body", "body": b"", "more_body": False})

    middleware = PublicAuthRateLimitMiddleware(
        app,
        limit=5,
        window_seconds=60,
        max_buckets=2,
    )
    first = asyncio.run(_run_once(middleware, _scope(client=("203.0.113.1", 1))))
    second = asyncio.run(_run_once(middleware, _scope(client=("203.0.113.2", 1))))
    blocked = asyncio.run(_run_once(middleware, _scope(client=("203.0.113.3", 1))))
    assert first[0]["status"] == 204
    assert second[0]["status"] == 204
    assert blocked[0]["status"] == 429
    assert len(middleware._hits) == 2
    assert calls == 2

    # Once the old window has elapsed, a new identity reaps stale buckets before
    # it is admitted. The hard state bound remains intact.
    clock[0] = 161.0
    reclaimed = asyncio.run(_run_once(middleware, _scope(client=("203.0.113.3", 1))))
    assert reclaimed[0]["status"] == 204
    assert len(middleware._hits) <= 2
    assert calls == 3


def test_unrelated_api_path_is_not_public_auth_limited():
    calls = 0

    async def app(scope, receive, send):
        nonlocal calls
        calls += 1
        await send({"type": "http.response.start", "status": 204, "headers": []})
        await send({"type": "http.response.body", "body": b"", "more_body": False})

    middleware = PublicAuthRateLimitMiddleware(app, limit=1, window_seconds=60)
    for _ in range(5):
        sent = asyncio.run(_run_once(middleware, _scope(path="/health", method="GET")))
        assert sent[0]["status"] == 204
    assert calls == 5


def test_forwarded_for_is_trusted_only_from_loopback_proxy():
    async def app(scope, receive, send):
        await send({"type": "http.response.start", "status": 204, "headers": []})
        await send({"type": "http.response.body", "body": b"", "more_body": False})

    forwarded = [(b"x-forwarded-for", b"198.51.100.42")]
    middleware = PublicAuthRateLimitMiddleware(app, limit=1, window_seconds=60)

    # Direct peer is public, so spoofed XFF is ignored. Changing XFF cannot evade
    # the bucket tied to the real direct client address.
    direct_one = asyncio.run(_run_once(middleware, _scope(client=("203.0.113.20", 1), headers=forwarded)))
    direct_two = asyncio.run(
        _run_once(
            middleware,
            _scope(client=("203.0.113.20", 1), headers=[(b"x-forwarded-for", b"198.51.100.99")]),
        )
    )
    assert direct_one[0]["status"] == 204
    assert direct_two[0]["status"] == 429

    # Local Caddy may provide the original client address via XFF; separate real
    # clients then receive independent buckets.
    proxy_middleware = PublicAuthRateLimitMiddleware(app, limit=1, window_seconds=60)
    proxied_one = asyncio.run(
        _run_once(proxy_middleware, _scope(client=("127.0.0.1", 4567), headers=forwarded))
    )
    proxied_two = asyncio.run(
        _run_once(
            proxy_middleware,
            _scope(client=("127.0.0.1", 4567), headers=[(b"x-forwarded-for", b"198.51.100.99")]),
        )
    )
    assert proxied_one[0]["status"] == 204
    assert proxied_two[0]["status"] == 204


def test_websocket_is_untouched():
    called = False

    async def app(scope, receive, send):
        nonlocal called
        called = True

    middleware = PublicAuthRateLimitMiddleware(app, limit=1, window_seconds=60)
    scope = {"type": "websocket", "path": "/v1/ws", "client": ("203.0.113.1", 1), "headers": []}

    async def receive():
        return {"type": "websocket.disconnect", "code": 1000}

    async def send(message):
        return None

    asyncio.run(middleware(scope, receive, send))
    assert called is True
