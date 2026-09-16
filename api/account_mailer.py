from __future__ import annotations

import smtplib
import ssl
from dataclasses import dataclass
from email.message import EmailMessage
from urllib.parse import quote


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

    @property
    def configured(self) -> bool:
        return bool(self.host and self.port and self.sender and self.public_url)


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
            raise AccountMailError("Account email transport is not configured")
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
            with smtplib.SMTP(self.config.host, self.config.port, timeout=self.config.timeout) as client:
                client.ehlo()
                if self.config.security == "starttls":
                    client.starttls(context=context)
                    client.ehlo()
                elif self.config.security != "plain":
                    raise AccountMailError("Unsupported SMTP security mode")
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
