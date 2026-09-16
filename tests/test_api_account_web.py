from __future__ import annotations

from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from api.account_store import AccountStore, AuthenticationError
from api.account_web import create_account_web_router


def _client(tmp_path: Path):
    accounts = AccountStore(tmp_path / "api")
    app = FastAPI()
    app.include_router(create_account_web_router(accounts))
    return accounts, TestClient(app)


def _bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_email_verification_get_is_non_mutating_and_post_consumes_token(tmp_path: Path):
    accounts, client = _client(tmp_path)
    password = "verification page password"
    created = accounts.register("web@example.com", password, "Web")
    token = created["verification_token"]

    with pytest.raises(AuthenticationError, match="verification"):
        accounts.login("web@example.com", password, "PC", "pytest")
    with accounts.database.connection() as connection:
        assert connection.execute("SELECT COUNT(*) FROM auth_sessions").fetchone()[0] == 0

    # Link scanners/prefetchers may issue GET automatically. GET must therefore
    # render a confirmation form without consuming the one-time credential.
    page = client.get("/verify-email", params={"token": token})
    assert page.status_code == 200
    assert "Подтвердите email" in page.text
    assert 'method="post"' in page.text
    assert 'action="/verify-email"' in page.text
    assert token in page.text
    assert page.headers["cache-control"] == "no-store"
    assert page.headers["referrer-policy"] == "no-referrer"
    assert "default-src 'none'" in page.headers["content-security-policy"]
    with pytest.raises(AuthenticationError, match="verification"):
        accounts.login("web@example.com", password, "PC", "pytest")

    confirmed = client.post("/verify-email", data={"token": token})
    assert confirmed.status_code == 200
    assert "Email подтверждён" in confirmed.text
    assert accounts.login("web@example.com", password, "PC", "pytest")["access_token"]

    reused = client.post("/verify-email", data={"token": token})
    assert reused.status_code == 400
    assert "Ссылка недействительна" in reused.text


def test_verification_page_rejects_non_form_payload_and_invalid_token(tmp_path: Path):
    _, client = _client(tmp_path)
    wrong_type = client.post("/verify-email", json={"token": "x" * 20})
    assert wrong_type.status_code == 415

    invalid = client.post("/verify-email", data={"token": "x" * 20})
    assert invalid.status_code == 400
    assert "Ссылка недействительна" in invalid.text


def test_password_reset_link_renders_form_and_resets_password(tmp_path: Path):
    accounts, client = _client(tmp_path)
    created = accounts.register("reset-web@example.com", "old reset page password", "Reset")
    accounts.verify_email(created["verification_token"])
    reset_token = accounts.request_password_reset("reset-web@example.com")
    assert reset_token is not None

    page = client.get("/reset-password", params={"token": reset_token})
    assert page.status_code == 200
    assert 'action="/reset-password"' in page.text
    assert 'name="confirm_password"' in page.text
    assert reset_token in page.text

    mismatch = client.post(
        "/reset-password",
        data={"token": reset_token, "new_password": "new reset page password", "confirm_password": "different password"},
    )
    assert mismatch.status_code == 400

    changed = client.post(
        "/reset-password",
        data={
            "token": reset_token,
            "new_password": "new reset page password",
            "confirm_password": "new reset page password",
        },
    )
    assert changed.status_code == 200
    assert "Пароль изменён" in changed.text

    with pytest.raises(AuthenticationError):
        accounts.login("reset-web@example.com", "old reset page password", "PC", "pytest")
    assert accounts.login("reset-web@example.com", "new reset page password", "PC", "pytest")["access_token"]


def test_reset_page_rejects_non_form_payload_and_invalid_token(tmp_path: Path):
    _, client = _client(tmp_path)
    wrong_type = client.post("/reset-password", json={"token": "x" * 20, "new_password": "abcdefghij"})
    assert wrong_type.status_code == 415

    invalid = client.post(
        "/reset-password",
        data={"token": "x" * 20, "new_password": "abcdefghij", "confirm_password": "abcdefghij"},
    )
    assert invalid.status_code == 400
    assert "Не удалось сменить пароль" in invalid.text


def test_personal_logout_revokes_account_family_and_guest_identity(tmp_path: Path):
    accounts, client = _client(tmp_path)

    created = accounts.register("logout@example.com", "logout account password", "Logout")
    accounts.verify_email(created["verification_token"])
    session = accounts.login("logout@example.com", "logout account password", "PC", "pytest")
    account_logout = client.post("/v1/auth/logout", headers=_bearer(session["access_token"]))
    assert account_logout.status_code == 200, account_logout.text
    assert account_logout.json() == {"ok": True, "revoked": True}
    assert accounts.verify_access(session["access_token"]) is None
    with pytest.raises(AuthenticationError):
        accounts.refresh(session["refresh_token"])

    guest = accounts.create_guest("Guest", "pytest")
    assert accounts.verify_guest(guest["guest_token"]) is not None
    guest_logout = client.post("/v1/auth/logout", headers=_bearer(guest["guest_token"]))
    assert guest_logout.status_code == 200, guest_logout.text
    assert guest_logout.json() == {"ok": True, "revoked": True}
    assert accounts.verify_guest(guest["guest_token"]) is None
    with accounts.database.connection() as connection:
        guest_row = connection.execute(
            "SELECT revoked_at FROM guests WHERE id=?",
            (guest["guest_id"],),
        ).fetchone()
        device_row = connection.execute(
            "SELECT revoked_at FROM devices WHERE id=?",
            (guest["device_id"],),
        ).fetchone()
    assert guest_row["revoked_at"] is not None
    assert device_row["revoked_at"] is not None

    missing = client.post("/v1/auth/logout")
    assert missing.status_code == 401
    stale = client.post("/v1/auth/logout", headers=_bearer(guest["guest_token"]))
    assert stale.status_code == 401

    schema_paths = client.get("/openapi.json").json()["paths"]
    assert "/v1/auth/logout" in schema_paths
    assert "/verify-email" not in schema_paths
    assert "/reset-password" not in schema_paths
