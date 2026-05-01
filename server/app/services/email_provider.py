"""V0.6.1 — EmailProvider Protocol + GmailSmtpProvider implementation.

Per spec §2 / §11: the OTP and notification mail backends share a single
`EmailProvider` Protocol. The default implementation talks to Gmail SMTP via
`aiosmtplib` + a 16-char App Password. Switching to Resend / SES later only
requires adding a sibling concrete class and extending `build_email_provider`.

Critical Gmail constraint baked in here:
- `From` header MUST equal `SMTP_USERNAME`; otherwise SPF/DKIM fails and the
  mail lands in spam. We assert this at construction time so misconfig fails
  fast at startup instead of producing silent deliverability bugs.
"""

import logging
from email.message import EmailMessage
from typing import Protocol

import aiosmtplib

from app.config import Settings

logger = logging.getLogger(__name__)


class EmailDeliveryError(Exception):
    """Raised when an EmailProvider cannot complete a send.

    Wraps any underlying provider error (auth, network, throttling). Callers
    should treat this as a soft failure (state still persists) and surface
    `EMAIL_DELIVERY_DEGRADED` to the user.
    """


class EmailProvider(Protocol):
    async def send(self, *, to: str, subject: str, html: str, text: str) -> None: ...


class GmailSmtpProvider:
    """Send mail via `smtp.gmail.com:587` (STARTTLS) + App Password.

    When `username`/`password` are blank the provider is "unconfigured" — it
    logs a warning and returns without contacting Gmail. This matches the
    test/dev env where SMTP credentials are intentionally absent.
    """

    def __init__(
        self,
        *,
        host: str,
        port: int,
        username: str,
        password: str,
        from_email: str,
        from_name: str,
        starttls: bool,
        timeout: float,
    ) -> None:
        if username and from_email and from_email != username:
            raise ValueError(
                f"GmailSmtpProvider: SMTP_FROM_EMAIL ({from_email!r}) must equal "
                f"SMTP_USERNAME ({username!r}); Gmail enforces this via SPF/DKIM."
            )
        self._host = host
        self._port = port
        self._username = username
        self._password = password
        self._from_email = from_email or username
        self._from_name = from_name
        self._starttls = starttls
        self._timeout = timeout

    async def send(self, *, to: str, subject: str, html: str, text: str) -> None:
        if not self._username or not self._password:
            logger.warning(
                "GmailSmtpProvider unconfigured (smtp_username/password empty); "
                "skipping email to %s subject=%r",
                to,
                subject,
            )
            return

        msg = EmailMessage()
        msg["From"] = f"{self._from_name} <{self._from_email}>"
        msg["To"] = to
        msg["Subject"] = subject
        msg["Reply-To"] = self._from_email
        msg.set_content(text)
        msg.add_alternative(html, subtype="html")

        try:
            await aiosmtplib.send(
                msg,
                hostname=self._host,
                port=self._port,
                username=self._username,
                password=self._password,
                start_tls=self._starttls,
                timeout=self._timeout,
            )
        except aiosmtplib.SMTPAuthenticationError as e:
            logger.error(
                "Gmail SMTP auth failed for sender=%s -> to=%s: %s",
                self._username,
                to,
                e,
            )
            raise EmailDeliveryError(f"smtp auth: {e}") from e
        except aiosmtplib.SMTPException as e:
            logger.error("Gmail SMTP send failed to=%s: %s", to, e)
            raise EmailDeliveryError(f"smtp send: {e}") from e


class RecordingEmailProvider:
    """In-memory test helper. Captures sends in `.outbox` instead of dialing SMTP."""

    def __init__(self) -> None:
        self.outbox: list[dict[str, str]] = []

    async def send(self, *, to: str, subject: str, html: str, text: str) -> None:
        self.outbox.append({"to": to, "subject": subject, "html": html, "text": text})


def build_email_provider(settings: Settings) -> EmailProvider:
    """Construct the configured EmailProvider implementation.

    Today only `gmail_smtp` is wired. `resend`/`ses` raise NotImplementedError
    so misconfiguration fails fast at startup.
    """
    if settings.email_provider == "gmail_smtp":
        return GmailSmtpProvider(
            host=settings.smtp_host,
            port=settings.smtp_port,
            username=settings.smtp_username,
            password=settings.smtp_password,
            from_email=settings.smtp_from_email,
            from_name=settings.smtp_from_name,
            starttls=settings.smtp_starttls,
            timeout=settings.smtp_timeout_seconds,
        )
    raise NotImplementedError(
        f"email_provider={settings.email_provider!r} not wired yet "
        "(only 'gmail_smtp' is implemented in V0.6.1)"
    )
