from __future__ import annotations

import importlib
import sys
from pathlib import Path

from fastapi.testclient import TestClient

from api.account_mailer import AccountMailError


def _load_server(monkeypatch, root: Path, *, dev_tokens: bool = False, max_body: int = 24 * 1024 * 1024):
    monkeypatch.setenv("AURORAFOX_USER_DIR", str(root))
    monkeypatch.setenv("AURORAFOX_ACCOUNT_EXPOSE_DEV_TOKENS", "1" if dev_tokens else "0")
    monkeypatch.setenv("AURORAFOX_API_MAX_BODY_BYTES", str(max_body))
    monkeypatch.setenv("AURORAFOX_API_RPM", "10000")
    monkeypatch.setenv("AURORAFOX_SMTP_HOST", "smtp.example.test")
    monkeypatch.setenv("AURORAFOX_SMTP_PORT", "587")
    monkeypatch.setenv("AURORAFOX_SMTP_USERNAME", "aurorafox")
    monkeypatch.setenv("AURORAFOX_SMTP_PASSWORD", "smtp-secret")
    monkeypatch.setenv("AURORAFOX_SMTP_SENDER", "AuroraFox <no-reply@example.test>")
    monkeypatch.setenv("AURORAFOX_SMTP_SECURITY", "starttls")
    monkeypatch.setenv("AURORAFOX_ACCOUNT_PUBLIC_URL", "https://auth.example.test")
    sys.modules.pop("api.server", None)
    return importlib.import_module("api.server")


def test_production_account_routes_deliver_tokens_without_returning_them(tmp_path: Path, monkeypatch):
    server = _load_server(monkeypatch, tmp_path)
    deliveries: list[tuple[str, str, str]] = []
    server.account_mailer.send_token = lambda email, purpose, token: deliveries.append((email, purpose, token))
    client = TestClient(server.app)

    registered = client.post(
        "/v1/auth/register",
        json={"email": "mail@example.com", "password": "mail delivery password", "display_name": "Mail"},
    )
    assert registered.status_code == 200, registered.text
    body = registered.json()
    assert body["email_delivery"] == "sent"
    assert "verification_token" not in body
    assert deliveries[-1][0:2] == ("mail@example.com", "verify_email")
    verification_token = deliveries[-1][2]
    assert verification_token.startswith("af_verify_")

    verified = client.post("/v1/auth/verify-email", json={"token": verification_token})
    assert verified.status_code == 200, verified.text

    reset = client.post("/v1/auth/password-reset/request", json={"email": "mail@example.com"})
    assert reset.status_code == 200, reset.text
    assert reset.json() == {"ok": True, "accepted": True}
    assert deliveries[-1][0:2] == ("mail@example.com", "reset_password")
    reset_token = deliveries[-1][2]
    assert reset_token.startswith("af_reset_")

    changed = client.post(
        "/v1/auth/password-reset/confirm",
        json={"token": reset_token, "new_password": "new mail delivery password"},
    )
    assert changed.status_code == 200, changed.text
    old_login = client.post(
        "/v1/auth/login",
        json={"email": "mail@example.com", "password": "mail delivery password", "device_name": "PC"},
    )
    assert old_login.status_code == 401
    new_login = client.post(
        "/v1/auth/login",
        json={"email": "mail@example.com", "password": "new mail delivery password", "device_name": "PC"},
    )
    assert new_login.status_code == 200, new_login.text


def test_mail_transport_failure_never_exposes_raw_token(tmp_path: Path, monkeypatch):
    server = _load_server(monkeypatch, tmp_path)

    def fail_delivery(email, purpose, token):
        raise AccountMailError("simulated outage")

    server.account_mailer.send_token = fail_delivery
    client = TestClient(server.app)
    registered = client.post(
        "/v1/auth/register",
        json={"email": "outage@example.com", "password": "outage safe password", "display_name": "Outage"},
    )
    assert registered.status_code == 200, registered.text
    body = registered.json()
    assert body["email_delivery"] == "retry_required"
    assert "verification_token" not in body

    resend = client.post("/v1/auth/resend-verification", json={"email": "outage@example.com"})
    assert resend.status_code == 200, resend.text
    assert resend.json() == {"ok": True, "accepted": True}
    assert "verification_token" not in resend.text

    reset_unknown = client.post("/v1/auth/password-reset/request", json={"email": "unknown@example.com"})
    assert reset_unknown.status_code == 200
    assert reset_unknown.json() == {"ok": True, "accepted": True}


def test_production_account_creation_fails_closed_when_mail_is_unconfigured(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("AURORAFOX_USER_DIR", str(tmp_path))
    monkeypatch.setenv("AURORAFOX_ACCOUNT_EXPOSE_DEV_TOKENS", "0")
    monkeypatch.delenv("AURORAFOX_SMTP_HOST", raising=False)
    monkeypatch.delenv("AURORAFOX_SMTP_SENDER", raising=False)
    monkeypatch.delenv("AURORAFOX_ACCOUNT_PUBLIC_URL", raising=False)
    monkeypatch.delenv("AURORAFOX_PUBLIC_URL", raising=False)
    sys.modules.pop("api.server", None)
    server = importlib.import_module("api.server")
    client = TestClient(server.app)

    response = client.post(
        "/v1/auth/register",
        json={"email": "blocked@example.com", "password": "blocked secure password"},
    )
    assert response.status_code == 503
    with server.database.connection() as connection:
        assert connection.execute("SELECT COUNT(*) FROM accounts").fetchone()[0] == 0


def test_server_rejects_oversized_json_before_route_validation(tmp_path: Path, monkeypatch):
    server = _load_server(monkeypatch, tmp_path, dev_tokens=True, max_body=64)
    client = TestClient(server.app)

    oversized = client.post(
        "/v1/auth/guest",
        json={"device_name": "x" * 100, "platform": "pytest"},
    )
    assert oversized.status_code == 413, oversized.text
    assert oversized.json()["detail"] == "AuroraFox API request body too large"

    small = client.post("/v1/auth/guest", json={"device_name": "G", "platform": "t"})
    assert small.status_code == 200, small.text
    assert small.json()["guest_token"].startswith("af_guest_")
