from __future__ import annotations

import os
import smtplib
import ssl
from dataclasses import dataclass
from email.message import EmailMessage
from urllib.parse import quote, urlsplit


class AccountMailError(RuntimeError):
    pass


@dataclass(frozen=True)
class AccountMailConfig:
    host: str
    port: int
    username: str
    password: str
    sender: str
    public_url: str
    security: str = "starttls"
    timeout: float = 10.0

    @classmethod
    def from_env(cls) -> "AccountMailConfig":
        try:
            port = int(os.getenv("AURORAFOX_SMTP_PORT", "587"))
        except ValueError:
            port = 587
        try:
            timeout = float(os.getenv("AURORAFOX_SMTP_TIMEOUT_SECONDS", "10"))
        except ValueError:
            timeout = 10.0
        return cls(
            host=os.getenv("AURORAFOX_SMTP_HOST", "").strip(),
            port=max(1, min(65535, port)),
            username=os.getenv("AURORAFOX_SMTP_USERNAME", "").strip(),
            password=os.getenv("AURORAFOX_SMTP_PASSWORD", ""),
            sender=os.getenv("AURORAFOX_SMTP_SENDER", "").strip(),
            public_url=(
                os.getenv("AURORAFOX_ACCOUNT_PUBLIC_URL", "").strip()
                or os.getenv("AURORAFOX_PUBLIC_URL", "").strip()
            ),
            security=os.getenv("AURORAFOX_SMTP_SECURITY", "starttls").strip().lower() or "starttls",
            timeout=max(1.0, min(60.0, timeout)),
        )

    @property
    def public_url_is_secure(self) -> bool:
        try:
            parsed = urlsplit(self.public_url)
        except Exception:
            return False
        # Verification/reset links carry one-time bearer credentials. Production
        # transport must never emit them onto a clear-text external HTTP link.
        return parsed.scheme.lower() == "https" and bool(parsed.hostname) and not parsed.username and not parsed.password

    @property
    def configured(self) -> bool:
        credentials_ready = not self.username or bool(self.password)
        return bool(
            self.host
            and self.port
            and self.sender
            and self.public_url_is_secure
            and credentials_ready
            and self.security in {"starttls", "ssl"}
        )


class AccountMailer:
    """Small SMTP boundary for one-time account links.

    Raw verification/reset tokens exist only in memory long enough to construct
    and submit the message. The database stores token hashes only. SMTP secrets
    are injected through the process environment and never written by this class.
    """

    def __init__(self, config: AccountMailConfig):
        self.config = config

    def _link(self, purpose: str, token: str) -> str:
        base = self.config.public_url.rstrip("/")
        route = "verify-email" if purpose == "verify_email" else "reset-password"
        return f"{base}/{route}?token={quote(token, safe='')}"

    def _message(self, recipient: str, purpose: str, token: str) -> EmailMessage:
        message = EmailMessage()
        message["From"] = self.config.sender
        message["To"] = recipient
        if purpose == "verify_email":
            message["Subject"] = "AuroraFox — подтверждение email"
            intro = "Подтвердите email для аккаунта AuroraFox:"
            expiry = "Ссылка действует ограниченное время."
        elif purpose == "reset_password":
            message["Subject"] = "AuroraFox — восстановление пароля"
            intro = "Для смены пароля AuroraFox откройте ссылку:"
            expiry = "Если вы не запрашивали смену пароля, проигнорируйте письмо."
        else:
            raise AccountMailError("Unsupported account mail purpose")
        message.set_content(f"{intro}\n\n{self._link(purpose, token)}\n\n{expiry}\n")
        return message

    def send_token(self, recipient: str, purpose: str, token: str) -> None:
        if not self.config.configured:
            raise AccountMailError("Account email transport is not configured or action URL is not secure")
        message = self._message(recipient, purpose, token)
        context = ssl.create_default_context()
        try:
            if self.config.security == "ssl":
                with smtplib.SMTP_SSL(
                    self.config.host, self.config.port, timeout=self.config.timeout, context=context
                ) as client:
                    self._authenticate(client)
                    client.send_message(message)
                return
            if self.config.security != "starttls":
                raise AccountMailError("Unsupported SMTP security mode")
            with smtplib.SMTP(self.config.host, self.config.port, timeout=self.config.timeout) as client:
                client.ehlo()
                client.starttls(context=context)
                client.ehlo()
                self._authenticate(client)
                client.send_message(message)
        except AccountMailError:
            raise
        except Exception as exc:
            raise AccountMailError("Account email delivery failed") from exc

    def _authenticate(self, client: smtplib.SMTP) -> None:
        if self.config.username:
            if not self.config.password:
                raise AccountMailError("SMTP password is missing")
            client.login(self.config.username, self.config.password)
