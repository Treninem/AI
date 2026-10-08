from __future__ import annotations

import importlib
import sys
from pathlib import Path

import pytest
from fastapi import Request
from fastapi.testclient import TestClient

from api.account_mailer import AccountMailError


def _load_server(monkeypatch, root: Path, *, dev_tokens: bool = False, max_body: int = 24 * 1024 * 1024, max_in_flight=None):
    monkeypatch.setenv("AURORAFOX_USER_DIR", str(root))
    monkeypatch.setenv("AURORAFOX_ACCOUNT_EXPOSE_DEV_TOKENS", "1" if dev_tokens else "0")
    monkeypatch.setenv("AURORAFOX_API_MAX_BODY_BYTES", str(max_body))
    if max_in_flight is None:
        monkeypatch.delenv("AURORAFOX_API_MAX_IN_FLIGHT_BODY_BYTES", raising=False)
    else:
        monkeypatch.setenv("AURORAFOX_API_MAX_IN_FLIGHT_BODY_BYTES", str(max_in_flight))
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


def _healthy_readiness_dependencies(server) -> None:
    server.database.integrity_check = lambda: {
        "ok": True,
        "schema_version": 3,
        "journal_mode": "wal",
        "integrity": "ok",
        "foreign_key_errors": 0,
    }
    server.learning.status = lambda: {"ok": True}


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


def test_ready_ignores_noncritical_storage_warnings_and_redacts_details(tmp_path: Path, monkeypatch):
    server = _load_server(monkeypatch, tmp_path, dev_tokens=True)
    _healthy_readiness_dependencies(server)
    server.persistence.status = lambda: {
        "ok": True,
        "hard_pressure": False,
        "attention_required": True,
        "warnings": ["database_size", "pending_learning_protected"],
        "disk_free_bytes": 123,
        "counts": {"accounts": 999},
        "sizes": {"database_bytes": 456},
    }
    client = TestClient(server.app)

    response = client.get("/ready")

    assert response.status_code == 200, response.text
    assert response.json()["storage"] == {"ok": True, "hard_pressure": False}
    assert "disk_free_bytes" not in response.text
    assert "database_size" not in response.text
    assert '"counts"' not in response.text
    assert '"sizes"' not in response.text


def test_ready_fails_closed_on_critical_storage_pressure_without_leaking_capacity(tmp_path: Path, monkeypatch):
    server = _load_server(monkeypatch, tmp_path, dev_tokens=True)
    _healthy_readiness_dependencies(server)
    server.persistence.status = lambda: {
        "ok": False,
        "hard_pressure": True,
        "attention_required": True,
        "warnings": ["disk_free_critical"],
        "disk_free_bytes": 1,
        "counts": {"accounts": 123},
        "sizes": {"database_bytes": 987654321},
    }
    client = TestClient(server.app)

    response = client.get("/ready")

    assert response.status_code == 503, response.text
    assert response.json()["detail"]["storage"] == {"ok": False, "hard_pressure": True}
    assert "disk_free_bytes" not in response.text
    assert "disk_free_critical" not in response.text
    assert '"counts"' not in response.text
    assert '"sizes"' not in response.text


def test_ready_fails_closed_when_storage_status_raises_without_leaking_error(tmp_path: Path, monkeypatch):
    server = _load_server(monkeypatch, tmp_path, dev_tokens=True)
    _healthy_readiness_dependencies(server)

    def fail_storage_status():
        raise OSError("/secret/volume inspection failed")

    server.persistence.status = fail_storage_status
    client = TestClient(server.app)

    response = client.get("/ready")

    assert response.status_code == 503, response.text
    assert response.json()["detail"]["storage"] == {"ok": False, "hard_pressure": False}
    assert "/secret/volume" not in response.text
    assert "inspection failed" not in response.text


@pytest.mark.parametrize("request_budget,aggregate,status", [(0, 0, 200), (0, 64, 413), (64, 0, 413), (256, 256, 200)])
def test_real_server_uses_independent_startup_body_policy(tmp_path, monkeypatch, request_budget, aggregate, status):
    server = _load_server(monkeypatch, tmp_path, max_body=request_budget, max_in_flight=aggregate)

    @server.app.post("/test/owner-body-policy")
    async def body_probe(request: Request):
        return {"bytes": len(await request.body())}

    client = TestClient(server.app)
    response = client.post("/test/owner-body-policy", content=b"x" * 128,
                           headers={"X-AuroraFox-API-Max-Body-Bytes": "0"})
    assert response.status_code == status, response.text
    if status == 200:
        assert response.json() == {"bytes": 128}
    assert server.MAX_API_BODY_BYTES == request_budget
    assert server.MAX_API_IN_FLIGHT_BODY_BYTES == aggregate


@pytest.mark.parametrize("request_budget,aggregate", [(-1, 64), (64, -1)])
def test_real_server_rejects_invalid_startup_budget(tmp_path, monkeypatch, request_budget, aggregate):
    with pytest.raises(ValueError, match="nonnegative integer"):
        _load_server(monkeypatch, tmp_path, max_body=request_budget, max_in_flight=aggregate)


@pytest.mark.parametrize("context_budget,expected", [(0, 30), (3, 3), (24, 24)])
def test_real_authenticated_chat_uses_owner_context_and_retention(tmp_path, monkeypatch, context_budget, expected):
    monkeypatch.setenv("AURORAFOX_API_CONVERSATION_MAX_MESSAGES", "0")
    monkeypatch.setenv("AURORAFOX_API_CONVERSATION_CONTEXT_MESSAGES", str(context_budget))
    server = _load_server(monkeypatch, tmp_path)
    token, principal = server.keys.create("owner-context", ["chat"])
    for index in range(30):
        server.conversations.append(principal["id"], "history", "user", str(index))
    observed = []

    def execution(message, context, *args):
        observed.append(context)
        return {"ok": True, "content": "reply", "runtime": "aurorafox-agent"}

    monkeypatch.setattr(server, "_execute_chat", execution)
    client = TestClient(server.app)
    payload = {"message": "next", "conversation_id": "history", "metadata": {"context_messages": 0, "max_messages": 1}}
    assert client.post("/v1/chat", json=payload).status_code == 401
    response = client.post("/v1/chat", json=payload, headers={"Authorization": "Bearer " + token})
    assert response.status_code == 200, response.text
    assert [row["content"] for row in observed[0]] == [str(i) for i in range(30 - expected, 30)]
    assert len(server.conversations.get(principal["id"], "history")["messages"]) == 32
    assert server.conversations.max_messages == 0


@pytest.mark.parametrize("budget", [4, 100, 0])
def test_actual_api_text_models_honor_owner_policy(tmp_path, monkeypatch, budget):
    from pydantic import ValidationError
    for key in ("AURORAFOX_API_CHAT_MAX_CHARS", "AURORAFOX_API_KNOWLEDGE_MAX_CHARS", "AURORAFOX_API_NOTE_MAX_CHARS"):
        monkeypatch.setenv(key, str(budget))
    server = _load_server(monkeypatch, tmp_path)
    text = "x" * (budget if budget else 200001)
    assert server.ChatRequest(message=text).message == text
    assert server.LearningRequest(content=text).content == text
    feedback = server.FeedbackRequest(conversation_id="history", score=0, message=text, answer=text, corrected_answer=text, note=text)
    assert feedback.note == text
    assert server.FileAnalyzeRequest(filename="file.txt", content_base64="eA==", question=text).question == text
    if budget:
        for model, kwargs in [(server.ChatRequest, {"message": text + "x"}),
                              (server.LearningRequest, {"content": text + "x"}),
                              (server.FeedbackRequest, {"conversation_id": "history", "score": 0, "note": text + "x"}),
                              (server.FileAnalyzeRequest, {"filename": "file.txt", "content_base64": "eA==", "question": text + "x"})]:
            with pytest.raises(ValidationError):
                model(**kwargs)
    with pytest.raises(ValidationError):
        server.ChatRequest(message="")
    with pytest.raises(ValidationError):
        server.FeedbackRequest(conversation_id="history", score=2)


def test_authenticated_http_cannot_override_owner_text_policy(tmp_path, monkeypatch):
    monkeypatch.setenv("AURORAFOX_API_CHAT_MAX_CHARS", "4")
    server = _load_server(monkeypatch, tmp_path)
    token, _ = server.keys.create("text-policy", ["chat"])
    executed = []

    def execute(message, *args):
        executed.append(message)
        return {"ok": True, "content": "reply", "runtime": "aurorafox-agent"}

    monkeypatch.setattr(server, "_execute_chat", execute)
    client = TestClient(server.app)
    headers = {"Authorization": "Bearer " + token, "X-AuroraFox-API-Chat-Max-Chars": "0"}
    assert client.post("/v1/chat", json={"message": "12345", "metadata": {"chat_max_chars": 0}}, headers=headers).status_code == 422
    assert executed == []
    assert client.post("/v1/chat", json={"message": "1234"}, headers=headers).status_code == 200
    assert executed == ["1234"]


@pytest.mark.parametrize("key", ["AURORAFOX_API_CHAT_MAX_CHARS", "AURORAFOX_API_KNOWLEDGE_MAX_CHARS", "AURORAFOX_API_NOTE_MAX_CHARS"])
def test_invalid_api_text_budget_fails_startup(tmp_path, monkeypatch, key):
    monkeypatch.setenv(key, "-1")
    with pytest.raises(ValueError, match=key):
        _load_server(monkeypatch, tmp_path)
