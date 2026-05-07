"""V0.6.1 — notification_service.send_otp_email tests (Chinese-only template + degraded path)."""

import pytest


@pytest.mark.asyncio
async def test_send_otp_email_records_chinese_subject_and_body() -> None:
    from app.services.email_provider import RecordingEmailProvider
    from app.services.notification_service import send_otp_email

    provider = RecordingEmailProvider()
    await send_otp_email(
        provider,
        to="parent@example.com",
        code="824193",
        expires_in_minutes=10,
    )
    assert len(provider.outbox) == 1
    msg = provider.outbox[0]
    assert msg["to"] == "parent@example.com"
    assert "824193" in msg["subject"]
    assert "验证码" in msg["subject"]
    # Chinese-only body (per spec §14 r3 lock-in #1): no English words like "verify"/"OTP".
    body_lower = msg["text"].lower()
    assert "824193" in msg["text"]
    assert "验证码" in msg["text"]
    assert "10 分钟" in msg["text"] or "10分钟" in msg["text"]
    for forbidden in ("verify", "otp", "verification", "expires"):
        assert forbidden not in body_lower, f"English keyword leaked into body: {forbidden}"


@pytest.mark.asyncio
async def test_send_otp_email_includes_spam_hint() -> None:
    from app.services.email_provider import RecordingEmailProvider
    from app.services.notification_service import send_otp_email

    provider = RecordingEmailProvider()
    await send_otp_email(provider, to="a@b.com", code="000000", expires_in_minutes=10)
    msg = provider.outbox[0]
    # Per spec §12 risk row: include a垃圾邮件 hint to mitigate国内邮箱误判.
    assert "垃圾" in msg["text"]


@pytest.mark.asyncio
async def test_send_otp_email_degraded_when_provider_fails() -> None:
    from app.services.email_provider import EmailDeliveryError
    from app.services.notification_service import EmailDeliveryDegraded, send_otp_email

    class _FailingProvider:
        async def send(
            self, *, to: str, subject: str, html: str, text: str
        ) -> None:
            raise EmailDeliveryError("simulated auth fail")

    with pytest.raises(EmailDeliveryDegraded, match="simulated auth fail"):
        await send_otp_email(
            _FailingProvider(),
            to="x@y.com",
            code="111111",
            expires_in_minutes=10,
        )
