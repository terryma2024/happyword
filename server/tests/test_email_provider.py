"""V0.6.1 — EmailProvider Protocol + GmailSmtpProvider + RecordingEmailProvider tests."""

from unittest.mock import AsyncMock

import aiosmtplib
import pytest


@pytest.mark.asyncio
async def test_recording_provider_captures_sends() -> None:
    from app.services.email_provider import RecordingEmailProvider

    provider = RecordingEmailProvider()
    await provider.send(to="a@b.com", subject="hi", html="<p>hi</p>", text="hi")
    await provider.send(to="c@d.com", subject="hi2", html="<p>hi2</p>", text="hi2")
    assert len(provider.outbox) == 2
    assert provider.outbox[0]["to"] == "a@b.com"
    assert provider.outbox[1]["subject"] == "hi2"


@pytest.mark.asyncio
async def test_gmail_provider_unconfigured_noops(monkeypatch: pytest.MonkeyPatch) -> None:
    """When smtp_username='' the provider must NOT touch aiosmtplib."""
    from app.services import email_provider as ep

    called = False

    async def _fail_send(*args: object, **kwargs: object) -> None:
        nonlocal called
        called = True

    monkeypatch.setattr(ep.aiosmtplib, "send", _fail_send)
    provider = ep.GmailSmtpProvider(
        host="smtp.gmail.com",
        port=587,
        username="",
        password="",
        from_email="",
        from_name="x",
        starttls=True,
        timeout=10.0,
    )
    await provider.send(to="x@y.com", subject="s", html="<p>h</p>", text="t")
    assert called is False


def test_gmail_provider_rejects_mismatched_from() -> None:
    from app.services.email_provider import GmailSmtpProvider

    with pytest.raises(ValueError, match="SMTP_FROM_EMAIL"):
        GmailSmtpProvider(
            host="smtp.gmail.com",
            port=587,
            username="me@gmail.com",
            password="pw",
            from_email="someone-else@gmail.com",
            from_name="x",
            starttls=True,
            timeout=10.0,
        )


def test_gmail_provider_uses_username_when_from_blank() -> None:
    from app.services.email_provider import GmailSmtpProvider

    provider = GmailSmtpProvider(
        host="smtp.gmail.com",
        port=587,
        username="me@gmail.com",
        password="pw",
        from_email="",
        from_name="WordMagic",
        starttls=True,
        timeout=10.0,
    )
    assert provider._from_email == "me@gmail.com"  # noqa: SLF001 — internal-by-design


@pytest.mark.asyncio
async def test_gmail_provider_send_invokes_aiosmtplib(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services import email_provider as ep

    captured: dict[str, object] = {}

    async def _spy_send(message: object, /, **kwargs: object) -> None:
        captured["message"] = message
        captured.update(kwargs)

    monkeypatch.setattr(ep.aiosmtplib, "send", _spy_send)
    provider = ep.GmailSmtpProvider(
        host="smtp.gmail.com",
        port=587,
        username="me@gmail.com",
        password="pw",
        from_email="me@gmail.com",
        from_name="WordMagic",
        starttls=True,
        timeout=10.0,
    )
    await provider.send(to="you@gmail.com", subject="hello", html="<p>h</p>", text="t")
    assert captured["hostname"] == "smtp.gmail.com"
    assert captured["port"] == 587
    assert captured["username"] == "me@gmail.com"
    assert captured["password"] == "pw"
    assert captured["start_tls"] is True
    msg = captured["message"]
    assert msg["To"] == "you@gmail.com"  # type: ignore[index]
    assert msg["Subject"] == "hello"  # type: ignore[index]
    assert "WordMagic" in msg["From"]  # type: ignore[index]
    assert "me@gmail.com" in msg["From"]  # type: ignore[index]


@pytest.mark.asyncio
async def test_gmail_provider_auth_error_raises_delivery_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services import email_provider as ep

    async def _raise(*args: object, **kwargs: object) -> None:
        raise aiosmtplib.SMTPAuthenticationError(535, "bad creds")

    monkeypatch.setattr(ep.aiosmtplib, "send", _raise)
    provider = ep.GmailSmtpProvider(
        host="smtp.gmail.com",
        port=587,
        username="me@gmail.com",
        password="pw",
        from_email="me@gmail.com",
        from_name="x",
        starttls=True,
        timeout=10.0,
    )
    with pytest.raises(ep.EmailDeliveryError, match="smtp auth"):
        await provider.send(to="x@y.com", subject="s", html="<p>h</p>", text="t")


@pytest.mark.asyncio
async def test_gmail_provider_generic_smtp_error_raises_delivery_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services import email_provider as ep

    async def _raise(*args: object, **kwargs: object) -> None:
        raise aiosmtplib.SMTPException("boom")

    monkeypatch.setattr(ep.aiosmtplib, "send", _raise)
    provider = ep.GmailSmtpProvider(
        host="smtp.gmail.com",
        port=587,
        username="me@gmail.com",
        password="pw",
        from_email="me@gmail.com",
        from_name="x",
        starttls=True,
        timeout=10.0,
    )
    with pytest.raises(ep.EmailDeliveryError, match="smtp send"):
        await provider.send(to="x@y.com", subject="s", html="<p>h</p>", text="t")


def test_build_email_provider_gmail_smtp_default() -> None:
    from app.config import get_settings
    from app.services.email_provider import GmailSmtpProvider, build_email_provider

    settings = get_settings()
    provider = build_email_provider(settings)
    # In test env smtp_* are blank, so the provider is constructed but unconfigured.
    assert isinstance(provider, GmailSmtpProvider)


def test_build_email_provider_unknown_raises() -> None:
    from app.config import Settings
    from app.services.email_provider import build_email_provider

    settings = Settings(
        mongo_uri="x",
        mongo_db_name="x",
        jwt_secret="x" * 32,
        admin_bootstrap_user="x",
        admin_bootstrap_pass="x",
        email_provider="resend",  # type: ignore[arg-type]
    )
    with pytest.raises(NotImplementedError, match="resend"):
        build_email_provider(settings)


# Suppress unused import lint (AsyncMock kept for future tests of async call counting).
_ = AsyncMock
