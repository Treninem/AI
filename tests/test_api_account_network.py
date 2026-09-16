from __future__ import annotations

import importlib
import os
import sqlite3
import sys
from pathlib import Path

from fastapi.testclient import TestClient

from api.account_mailer import AccountMailError


def _load_server(monkeypatch, root: Path):
    monkeypatch.setenv("AURORAFOX_USER_DIR", str(root))
    monkeypatch.setenv("AURORAFOX_ACCOUNT_EXPOSE_DEV_TOKENS", "1")
    monkeypatch.setenv("AURORAFOX_API_RPM", "10000")
    sys.modules.pop("api.server", None)
    server = importlib.import_module("api.server")
    server.bridge.chat = lambda message, context, conversation_id, metadata: {
        "ok": True,
        "content": f"local:{message}",
        "runtime": "aurorafox-local-core",
        "model": "AuroraFox-Core",
        "details": {"fallback_runtime": "aurorafox-local-core"},
    }
    server.learning.flush = lambda _limit=25: {"ok": True, "attempted": 0, "synced": 0}
    return server


def _register_login(client: TestClient, email: str, password: str, device_name: str):
    registered = client.post(
        "/v1/auth/register",
        json={"email": email, "password": password, "display_name": email.split("@", 1)[0]},
    )
    assert registered.status_code == 200, registered.text
    registration = registered.json()
    assert registration["email_verification_required"] is True
    assert registration["verification_token"].startswith("af_verify_")
    verified = client.post("/v1/auth/verify-email", json={"token": registration["verification_token"]})
    assert verified.status_code == 200, verified.text
    login = client.post(
        "/v1/auth/login",
        json={"email": email, "password": password, "device_name": device_name, "platform": "pytest"},
    )
    assert login.status_code == 200, login.text
    return login.json()


def _bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_smtp_failure_revokes_issued_token_and_immediate_resend_is_not_cooldown_blocked(
    tmp_path: Path, monkeypatch
):
    root = tmp_path / "smtp-failure"
    monkeypatch.setenv("AURORAFOX_USER_DIR", str(root))
    monkeypatch.setenv("AURORAFOX_ACCOUNT_EXPOSE_DEV_TOKENS", "0")
    monkeypatch.setenv("AURORAFOX_API_RPM", "10000")
    monkeypatch.setenv("AURORAFOX_PUBLIC_AUTH_RPM", "10000")
    monkeypatch.setenv("AURORAFOX_SMTP_HOST", "smtp.example.test")
    monkeypatch.setenv("AURORAFOX_SMTP_PORT", "587")
    monkeypatch.setenv("AURORAFOX_SMTP_USERNAME", "")
    monkeypatch.setenv("AURORAFOX_SMTP_PASSWORD", "")
    monkeypatch.setenv("AURORAFOX_SMTP_SENDER", "AuroraFox <no-reply@example.test>")
    monkeypatch.setenv("AURORAFOX_SMTP_SECURITY", "starttls")
    monkeypatch.setenv("AURORAFOX_ACCOUNT_PUBLIC_URL", "https://auth.example.test")
    sys.modules.pop("api.server", None)
    server = importlib.import_module("api.server")

    attempts: list[tuple[str, str, str]] = []

    def fail_delivery(recipient: str, purpose: str, token: str) -> None:
        attempts.append((recipient, purpose, token))
        raise AccountMailError("simulated SMTP outage")

    monkeypatch.setattr(server.account_mailer, "send_token", fail_delivery)
    client = TestClient(server.app)
    email = "smtp-retry@example.com"

    registered = client.post(
        "/v1/auth/register",
        json={"email": email, "password": "smtp retry secure password", "display_name": "SMTP Retry"},
    )
    assert registered.status_code == 200, registered.text
    body = registered.json()
    assert body["email_delivery"] == "retry_required"
    assert "verification_token" not in body
    assert len(attempts) == 1
    first_token = attempts[0][2]

    db_path = server.API_ROOT / "aurorafox.sqlite3"
    with sqlite3.connect(db_path) as connection:
        first_rows = connection.execute(
            "SELECT token_hash, revoked_at FROM account_tokens WHERE purpose='verify_email'"
        ).fetchall()
    assert len(first_rows) == 1
    assert first_rows[0][1] is not None

    # The failed-delivery token is revoked, so the store's five-minute resend
    # cooldown no longer hides a raw token the user never received. A retry can
    # immediately issue a distinct token and reach SMTP again.
    resent = client.post("/v1/auth/resend-verification", json={"email": email})
    assert resent.status_code == 200, resent.text
    assert resent.json() == {"ok": True, "accepted": True}
    assert len(attempts) == 2
    assert attempts[1][2] != first_token

    with sqlite3.connect(db_path) as connection:
        rows = connection.execute(
            "SELECT token_hash, revoked_at FROM account_tokens WHERE purpose='verify_email' ORDER BY rowid"
        ).fetchall()
    assert len(rows) == 2
    assert all(row[1] is not None for row in rows)


def test_account_guest_network_isolation_rotation_conflict_migration_and_restart(tmp_path: Path, monkeypatch):
    server = _load_server(monkeypatch, tmp_path)
    client = TestClient(server.app)

    account_a = _register_login(client, "a@example.com", "account A secure password", "A-PC")
    account_b = _register_login(client, "b@example.com", "account B secure password", "B-PC")
    guest_a = client.post("/v1/auth/guest", json={"device_name": "GA", "platform": "pytest"}).json()
    guest_b = client.post("/v1/auth/guest", json={"device_name": "GB", "platform": "pytest"}).json()

    principals = [
        (account_a["access_token"], "account-a"),
        (account_b["access_token"], "account-b"),
        (guest_a["guest_token"], "guest-a"),
        (guest_b["guest_token"], "guest-b"),
    ]
    for token, owner in principals:
        pushed = client.post(
            "/v1/sync/push",
            headers=_bearer(token),
            json={"items": [{"entity_type": "memory", "entity_id": "same", "base_revision": 0, "payload": {"owner": owner}}]},
        )
        assert pushed.status_code == 200, pushed.text
        assert pushed.json()["results"][0]["status"] == "applied"

    for token, owner in principals:
        pulled = client.get("/v1/sync/pull", headers=_bearer(token))
        assert pulled.status_code == 200, pulled.text
        own = [item for item in pulled.json()["changes"] if item["entity_id"] == "same"]
        assert len(own) == 1
        assert own[0]["payload"] == {"owner": owner}

    # Chat conversation IDs may collide across principals without leaking data.
    for token, owner in principals:
        response = client.post(
            "/v1/chat",
            headers=_bearer(token),
            json={"conversation_id": "same-chat", "message": owner},
        )
        assert response.status_code == 200, response.text
    for token, owner in principals:
        conversation = client.get("/v1/conversations/same-chat", headers=_bearer(token))
        assert conversation.status_code == 200, conversation.text
        contents = [item["content"] for item in conversation.json()["messages"]]
        assert contents == [owner, f"local:{owner}"]

    # Personal principals cannot call the shared Core learning API implicitly.
    denied = client.post(
        "/v1/learn",
        headers=_bearer(account_a["access_token"]),
        json={"content": "private account memory"},
    )
    assert denied.status_code == 403

    # A second device for the same account sees the same sync principal, but a
    # stale base revision creates a preserved conflict rather than last-write-wins.
    second_device = client.post(
        "/v1/auth/login",
        json={
            "email": "a@example.com",
            "password": "account A secure password",
            "device_name": "A-Phone",
            "platform": "pytest",
        },
    ).json()
    update = client.post(
        "/v1/sync/push",
        headers=_bearer(account_a["access_token"]),
        json={"items": [{"entity_type": "memory", "entity_id": "same", "base_revision": 1, "payload": {"owner": "account-a-v2"}}]},
    ).json()
    assert update["results"][0]["revision"] == 2
    stale = client.post(
        "/v1/sync/push",
        headers=_bearer(second_device["access_token"]),
        json={"items": [{"entity_type": "memory", "entity_id": "same", "base_revision": 1, "payload": {"owner": "phone-stale"}}]},
    ).json()
    assert stale["results"][0]["status"] == "conflict"
    conflicts = client.get("/v1/sync/conflicts", headers=_bearer(account_a["access_token"])).json()["conflicts"]
    assert conflicts[0]["incoming"]["payload"] == {"owner": "phone-stale"}

    # Refresh rotates once; replay of the spent token revokes the complete family.
    rotated = client.post("/v1/auth/refresh", json={"refresh_token": account_b["refresh_token"]})
    assert rotated.status_code == 200, rotated.text
    rotated_body = rotated.json()
    replay = client.post("/v1/auth/refresh", json={"refresh_token": account_b["refresh_token"]})
    assert replay.status_code == 401
    assert client.get("/v1/account/devices", headers=_bearer(rotated_body["access_token"])).status_code == 401

    # Guest data moves transactionally into the account. A colliding memory is
    # retained as a conflict and the guest token becomes unusable.
    migrated = client.post(
        "/v1/account/migrate-guest",
        headers=_bearer(account_a["access_token"]),
        json={"guest_token": guest_a["guest_token"]},
    )
    assert migrated.status_code == 200, migrated.text
    assert migrated.json()["conflict_entities"] >= 1
    assert client.get("/v1/sync/pull", headers=_bearer(guest_a["guest_token"])).status_code == 401

    # Re-import the server against the same SQLite file to prove durable session
    # and sync state across a real application restart boundary.
    server = _load_server(monkeypatch, tmp_path)
    restarted = TestClient(server.app)
    pulled_after_restart = restarted.get("/v1/sync/pull", headers=_bearer(account_a["access_token"]))
    assert pulled_after_restart.status_code == 200, pulled_after_restart.text
    assert any(item["entity_id"] == "same" for item in pulled_after_restart.json()["changes"])
    ready = restarted.get("/ready")
    assert ready.status_code == 200, ready.text
    assert ready.json()["database"]["ok"] is True
