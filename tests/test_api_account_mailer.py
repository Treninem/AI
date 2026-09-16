from __future__ import annotations

from email.message import EmailMessage

import pytest

from api.account_mailer import AccountMailConfig, AccountMailError, AccountMailer


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


def test_account_action_url_must_be_https_and_have_no_embedded_credentials():
    assert config().configured is True
    assert config(public_url="http://auth.aurorafox.ru").configured is False
    assert config(public_url="https://user:password@auth.aurorafox.ru").configured is False
    assert config(public_url="not-a-url").configured is False
    with pytest.raises(AccountMailError, match="not configured|not secure"):
        AccountMailer(config(public_url="http://auth.aurorafox.ru")).send_token(
            "user@example.test", "reset_password", "one-time"
        )


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
