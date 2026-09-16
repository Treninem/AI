from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

from api.account_store import AccountStore
from api.account_web import create_account_web_router


def _client(tmp_path: Path):
    accounts = AccountStore(tmp_path / "api")
    app = FastAPI()
    app.include_router(create_account_web_router(accounts))
    return accounts, TestClient(app)


def test_email_verification_link_consumes_one_time_token(tmp_path: Path):
    accounts, client = _client(tmp_path)
    created = accounts.register("web@example.com", "verification page password", "Web")
    token = created["verification_token"]

    response = client.get("/verify-email", params={"token": token})
    assert response.status_code == 200
    assert "Email подтверждён" in response.text
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["referrer-policy"] == "no-referrer"
    assert "default-src 'none'" in response.headers["content-security-policy"]

    reused = client.get("/verify-email", params={"token": token})
    assert reused.status_code == 400
    assert "Ссылка недействительна" in reused.text


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

    old_login = False
    try:
        accounts.login("reset-web@example.com", "old reset page password", "PC", "pytest")
        old_login = True
    except Exception:
        pass
    assert old_login is False
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
