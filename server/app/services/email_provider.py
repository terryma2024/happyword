"""V0.6.1 — EmailProvider Protocol and concrete mail backends.

Per spec §2 / §11: the OTP and notification mail backends share a single
`EmailProvider` Protocol. Local/dev fallback talks to Gmail SMTP via
`aiosmtplib` + a 16-char App Password; CloudBase production should use the
Tencent SES API provider to avoid mainland-to-Google SMTP reachability issues.

Critical Gmail constraint baked in here:
- `From` header MUST equal `SMTP_USERNAME`; otherwise SPF/DKIM fails and the
  mail lands in spam. We assert this at construction time so misconfig fails
  fast at startup instead of producing silent deliverability bugs.
"""

import base64
import hashlib
import hmac
import json
import logging
import time
from collections.abc import Callable, Mapping
from email.message import EmailMessage
from typing import Any, Protocol
from urllib.parse import urlparse

import aiosmtplib
import httpx

from app.config import Settings

logger = logging.getLogger(__name__)


class EmailDeliveryError(Exception):
    """Raised when an EmailProvider cannot complete a send.

    Wraps any underlying provider error (auth, network, throttling). Callers
    should treat this as a soft failure (state still persists) and surface
    `EMAIL_DELIVERY_DEGRADED` to the user.
    """


class EmailProvider(Protocol):
    async def send(
        self,
        *,
        to: str,
        subject: str,
        html: str,
        text: str,
        template_key: str | None = None,
        template_data: Mapping[str, str] | None = None,
    ) -> None: ...


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

    async def send(
        self,
        *,
        to: str,
        subject: str,
        html: str,
        text: str,
        template_key: str | None = None,
        template_data: Mapping[str, str] | None = None,
    ) -> None:
        _ = (template_key, template_data)
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


class TencentSesApiProvider:
    """Send transactional email through Tencent Cloud SES SendEmail API.

    CloudBase production runs in mainland China, where direct Gmail SMTP can be
    unreliable. Tencent SES keeps the critical OTP path on a domestic cloud API.
    """

    _SERVICE = "ses"
    _ACTION = "SendEmail"
    _VERSION = "2020-10-02"

    def __init__(
        self,
        *,
        secret_id: str,
        secret_key: str,
        region: str,
        from_email: str,
        from_name: str,
        reply_to: str,
        template_ids: Mapping[str, int],
        allow_simple: bool,
        timeout: float,
        endpoint: str = "https://ses.tencentcloudapi.com",
        http_client: httpx.AsyncClient | None = None,
        timestamp_provider: Callable[[], int] | None = None,
    ) -> None:
        self._secret_id = secret_id
        self._secret_key = secret_key
        self._region = region
        self._from_email = from_email
        self._from_name = from_name
        self._reply_to = reply_to
        self._template_ids = dict(template_ids)
        self._allow_simple = allow_simple
        self._timeout = timeout
        self._endpoint = endpoint.rstrip("/") + "/"
        self._http_client = http_client
        self._timestamp_provider = timestamp_provider or (lambda: int(time.time()))

    async def send(
        self,
        *,
        to: str,
        subject: str,
        html: str,
        text: str,
        template_key: str | None = None,
        template_data: Mapping[str, str] | None = None,
    ) -> None:
        payload: dict[str, Any] = {
            "FromEmailAddress": self._format_from(),
            "Destination": [to],
            "Subject": subject,
            "TriggerType": 1,
        }
        if self._reply_to:
            payload["ReplyToAddresses"] = self._reply_to

        template_id = self._template_ids.get(template_key or "")
        if template_id:
            payload["Template"] = {
                "TemplateID": template_id,
                "TemplateData": json.dumps(
                    {k: str(v) for k, v in (template_data or {}).items()},
                    ensure_ascii=False,
                    separators=(",", ":"),
                ),
            }
        elif self._allow_simple:
            payload["Simple"] = {
                "Html": base64.b64encode(html.encode("utf-8")).decode("ascii"),
                "Text": base64.b64encode(text.encode("utf-8")).decode("ascii"),
            }
        else:
            raise EmailDeliveryError(
                f"tencent ses template not configured for template_key={template_key!r}"
            )

        await self._post_send_email(payload)

    def _format_from(self) -> str:
        name = self._from_name.strip()
        if not name:
            return self._from_email
        return f"{name} <{self._from_email}>"

    async def _post_send_email(self, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        timestamp = self._timestamp_provider()
        headers = self._signed_headers(body, timestamp)

        try:
            if self._http_client is not None:
                response = await self._http_client.post(
                    self._endpoint,
                    content=body.encode("utf-8"),
                    headers=headers,
                )
            else:
                async with httpx.AsyncClient(timeout=self._timeout, trust_env=False) as client:
                    response = await client.post(
                        self._endpoint,
                        content=body.encode("utf-8"),
                        headers=headers,
                    )
            response.raise_for_status()
            data = response.json()
        except (httpx.HTTPError, ValueError) as e:
            logger.error("Tencent SES request failed: %s", e)
            raise EmailDeliveryError(f"tencent ses request: {e}") from e

        result = data.get("Response") if isinstance(data, dict) else None
        error = result.get("Error") if isinstance(result, dict) else None
        if isinstance(error, dict):
            code = error.get("Code", "Unknown")
            message = error.get("Message", "")
            request_id = result.get("RequestId", "") if isinstance(result, dict) else ""
            logger.error(
                "Tencent SES send failed code=%s request_id=%s message=%s",
                code,
                request_id,
                message,
            )
            raise EmailDeliveryError(
                f"tencent ses {code}: {message} request_id={request_id}"
            )

    def _signed_headers(self, body: str, timestamp: int) -> dict[str, str]:
        parsed = urlparse(self._endpoint)
        host = parsed.netloc
        content_type = "application/json; charset=utf-8"
        date = time.strftime("%Y-%m-%d", time.gmtime(timestamp))

        hashed_payload = hashlib.sha256(body.encode("utf-8")).hexdigest()
        canonical_request = "\n".join(
            [
                "POST",
                "/",
                "",
                f"content-type:{content_type}",
                f"host:{host}",
                "",
                "content-type;host",
                hashed_payload,
            ]
        )
        credential_scope = f"{date}/{self._SERVICE}/tc3_request"
        string_to_sign = "\n".join(
            [
                "TC3-HMAC-SHA256",
                str(timestamp),
                credential_scope,
                hashlib.sha256(canonical_request.encode("utf-8")).hexdigest(),
            ]
        )
        signing_key = self._tencent_cloud_signing_key(date)
        signature = hmac.new(
            signing_key, string_to_sign.encode("utf-8"), hashlib.sha256
        ).hexdigest()
        authorization = (
            "TC3-HMAC-SHA256 "
            f"Credential={self._secret_id}/{credential_scope}, "
            "SignedHeaders=content-type;host, "
            f"Signature={signature}"
        )
        return {
            "Authorization": authorization,
            "Content-Type": content_type,
            "Host": host,
            "X-TC-Action": self._ACTION,
            "X-TC-Version": self._VERSION,
            "X-TC-Timestamp": str(timestamp),
            "X-TC-Region": self._region,
        }

    def _tencent_cloud_signing_key(self, date: str) -> bytes:
        secret_date = hmac.new(
            f"TC3{self._secret_key}".encode(),
            date.encode("utf-8"),
            hashlib.sha256,
        ).digest()
        secret_service = hmac.new(
            secret_date, self._SERVICE.encode("utf-8"), hashlib.sha256
        ).digest()
        return hmac.new(secret_service, b"tc3_request", hashlib.sha256).digest()


class RecordingEmailProvider:
    """In-memory test helper. Captures sends in `.outbox` instead of dialing SMTP."""

    def __init__(self) -> None:
        self.outbox: list[dict[str, object]] = []

    async def send(
        self,
        *,
        to: str,
        subject: str,
        html: str,
        text: str,
        template_key: str | None = None,
        template_data: Mapping[str, str] | None = None,
    ) -> None:
        self.outbox.append(
            {
                "to": to,
                "subject": subject,
                "html": html,
                "text": text,
                "template_key": template_key,
                "template_data": dict(template_data or {}),
            }
        )


def _require_tencent_ses_settings(settings: Settings) -> None:
    missing = []
    if not settings.tencent_ses_secret_id:
        missing.append("TENCENT_SES_SECRET_ID")
    if not settings.tencent_ses_secret_key:
        missing.append("TENCENT_SES_SECRET_KEY")
    if not settings.tencent_ses_from_email:
        missing.append("TENCENT_SES_FROM_EMAIL")
    if not settings.tencent_ses_allow_simple and not settings.tencent_ses_otp_template_id:
        missing.append("TENCENT_SES_OTP_TEMPLATE_ID")
    if missing:
        raise ValueError(
            "Tencent SES email provider is selected but required settings are missing: "
            + ", ".join(missing)
        )


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
    if settings.email_provider == "tencent_ses_api":
        _require_tencent_ses_settings(settings)
        return TencentSesApiProvider(
            secret_id=settings.tencent_ses_secret_id,
            secret_key=settings.tencent_ses_secret_key,
            region=settings.tencent_ses_region,
            endpoint=settings.tencent_ses_endpoint,
            from_email=settings.tencent_ses_from_email,
            from_name=settings.tencent_ses_from_name,
            reply_to=settings.tencent_ses_reply_to,
            template_ids={
                key: value
                for key, value in {
                    "otp": settings.tencent_ses_otp_template_id,
                    "device_unbind_otp": settings.tencent_ses_device_unbind_template_id,
                    "redemption": settings.tencent_ses_redemption_template_id,
                }.items()
                if value
            },
            allow_simple=settings.tencent_ses_allow_simple,
            timeout=settings.smtp_timeout_seconds,
        )
    raise NotImplementedError(
        f"email_provider={settings.email_provider!r} not wired yet "
        "(implemented providers: 'gmail_smtp', 'tencent_ses_api')"
    )
