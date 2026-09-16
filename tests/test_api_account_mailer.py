from __future__ import annotations

from email.message import EmailMessage
from pathlib import Path

import pytest

from api.account_mailer import AccountMailConfig, AccountMailError, AccountMailer


ROOT = Path(__file__).resolve().parents[1]


def config(**overrides) -> AccountMailConfig:
    values = {
        "host": "smtp.example.test",
        "port": 587,
        "username": "aurorafox",
        "password": "secret-from-env",
        "sender": "AuroraFox <no-reply@example.test>",
        "public_url": "https://auth.aurorafox.ru",
        "security": "starttls",
    }
    values.update(overrides)
    return AccountMailConfig(**values)


def test_verification_and_reset_messages_contain_only_one_time_link():
    mailer = AccountMailer(config())
    verify: EmailMessage = mailer._message("user@example.test", "verify_email", "af_verify_A+B/C")
    reset: EmailMessage = mailer._message("user@example.test", "reset_password", "af_reset_secret")
    assert "https://auth.aurorafox.ru/verify-email?token=af_verify_A%2BB%2FC" in verify.get_content()
    assert "https://auth.aurorafox.ru/reset-password?token=af_reset_secret" in reset.get_content()
    assert "secret-from-env" not in verify.as_string()
    assert "secret-from-env" not in reset.as_string()


def test_transport_requires_configuration_and_rejects_unknown_security():
    with pytest.raises(AccountMailError, match="not configured"):
        AccountMailer(config(host="")).send_token("user@example.test", "verify_email", "token")
    with pytest.raises(AccountMailError, match="Unsupported account mail purpose"):
        AccountMailer(config())._message("user@example.test", "other", "token")


def test_account_action_url_must_be_clean_https_origin():
    assert config().configured is True
    assert config(public_url="https://auth.aurorafox.ru/").configured is True
    invalid_urls = (
        "http://auth.aurorafox.ru",
        "https://user:password@auth.aurorafox.ru",
        "https://auth.aurorafox.ru:8443",
        "https://auth.aurorafox.ru/account",
        "https://auth.aurorafox.ru/?next=evil",
        "https://auth.aurorafox.ru/#fragment",
        "https://auth.aurorafox.ru:bad",
        "not-a-url",
    )
    for public_url in invalid_urls:
        assert config(public_url=public_url).configured is False, public_url
    with pytest.raises(AccountMailError, match="not configured|not secure"):
        AccountMailer(config(public_url="https://auth.aurorafox.ru/account")).send_token(
            "user@example.test", "reset_password", "one-time"
        )


def test_malformed_recipient_header_fails_closed_before_smtp_connect(monkeypatch):
    connected = False

    class UnexpectedSMTP:
        def __init__(self, *args, **kwargs):
            nonlocal connected
            connected = True
            raise AssertionError("SMTP must not be reached for an invalid header")

    monkeypatch.setattr("api.account_mailer.smtplib.SMTP", UnexpectedSMTP)
    with pytest.raises(AccountMailError, match="delivery failed"):
        AccountMailer(config()).send_token(
            "user@example.test\r\nBcc: attacker@example.test",
            "verify_email",
            "one-time",
        )
    assert connected is False


def test_starttls_happens_before_authentication(monkeypatch):
    events: list[str] = []

    class FakeSMTP:
        def __init__(self, host, port, timeout):
            events.append(f"connect:{host}:{port}")

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def ehlo(self):
            events.append("ehlo")

        def starttls(self, context):
            events.append("starttls")

        def login(self, username, password):
            events.append("login")
            assert password == "secret-from-env"

        def send_message(self, message):
            events.append("send")

    monkeypatch.setattr("api.account_mailer.smtplib.SMTP", FakeSMTP)
    AccountMailer(config()).send_token("user@example.test", "verify_email", "one-time")
    assert events.index("starttls") < events.index("login") < events.index("send")


def test_reg_ru_verifier_binds_account_action_url_to_trusted_origin():
    verifier = (ROOT / "deploy/reg_ru/verify.sh").read_text(encoding="utf-8")
    assert "from urllib.parse import urlsplit" in verifier
    assert 'expected_action_host = "auth.aurorafox.ru" if api_url.hostname == "api.aurorafox.ru" else api_url.hostname' in verifier
    assert 'action_url.hostname == expected_action_host' in verifier
    assert 'action_url.port in {None, 443}' in verifier
    assert 'action_url.path in {"", "/"} and not action_url.query and not action_url.fragment' in verifier
