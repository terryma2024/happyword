"""V0.6.1 — otp_service: request_code + verify_code unit tests."""

import asyncio
from datetime import UTC, datetime, timedelta

import pytest

from app.models.email_verification import EmailVerification, EmailVerificationStatus


@pytest.mark.asyncio
async def test_request_code_creates_pending_row_and_returns_plain_code(db: object) -> None:
    from app.services.otp_service import request_code

    row, code = await request_code(email="parent@example.com")
    assert code is not None and len(code) == 6 and code.isdigit()
    assert row.status == EmailVerificationStatus.PENDING
    assert row.attempts == 0
    pending = await EmailVerification.find(
        EmailVerification.email == "parent@example.com"
    ).to_list()
    assert len(pending) == 1
    # Code is bcrypt-hashed at rest; never stored plaintext.
    assert pending[0].code_hash != code
    assert pending[0].code_hash.startswith("$2")


@pytest.mark.asyncio
async def test_request_code_rate_limited_within_one_minute(db: object) -> None:
    from app.services.otp_service import request_code

    row1, code1 = await request_code(email="x@y.com")
    assert code1 is not None
    row2, code2 = await request_code(email="x@y.com")
    # Second call returns the existing row (no new code minted, no email sent).
    assert code2 is None
    assert row2.id == row1.id
    rows = await EmailVerification.find(EmailVerification.email == "x@y.com").to_list()
    assert len(rows) == 1


@pytest.mark.asyncio
async def test_request_code_after_rate_limit_window_invalidates_old_pending(
    db: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Per spec: a fresh request after the 60s window expires the old pending row."""
    from app.services import otp_service
    from app.services.otp_service import request_code

    real_now = datetime.now(tz=UTC)

    # First call: now
    row1, code1 = await request_code(email="x@y.com")
    assert code1 is not None

    # Time-travel: advance 90 seconds.
    monkeypatch.setattr(otp_service, "_utcnow", lambda: real_now + timedelta(seconds=90))
    row2, code2 = await request_code(email="x@y.com")
    assert code2 is not None  # not rate-limited
    assert row2.id != row1.id

    # Old row should now be expired; new row is pending.
    refreshed = await EmailVerification.get(row1.id)
    assert refreshed is not None
    assert refreshed.status == EmailVerificationStatus.EXPIRED
    new_row = await EmailVerification.get(row2.id)
    assert new_row is not None
    assert new_row.status == EmailVerificationStatus.PENDING


@pytest.mark.asyncio
async def test_verify_code_success_marks_used(db: object) -> None:
    from app.services.otp_service import request_code, verify_code

    row, code = await request_code(email="ok@example.com")
    assert code is not None
    used = await verify_code(email="ok@example.com", code=code)
    assert used.id == row.id
    assert used.status == EmailVerificationStatus.USED
    assert used.used_at is not None


@pytest.mark.asyncio
async def test_verify_code_wrong_increments_attempts(db: object) -> None:
    from app.services.otp_service import OtpInvalid, request_code, verify_code

    row, code = await request_code(email="bad@example.com")
    assert code is not None

    with pytest.raises(OtpInvalid):
        await verify_code(email="bad@example.com", code="000000")

    refreshed = await EmailVerification.get(row.id)
    assert refreshed is not None
    assert refreshed.attempts == 1
    assert refreshed.status == EmailVerificationStatus.PENDING


@pytest.mark.asyncio
async def test_verify_code_too_many_attempts_expires(db: object) -> None:
    from app.services.otp_service import (
        OtpInvalid,
        OtpTooManyAttempts,
        request_code,
        verify_code,
    )

    row, code = await request_code(email="locked@example.com")
    assert code is not None
    # 4 wrong attempts return InvalidOtp; 5th flips the row to expired.
    for _ in range(4):
        with pytest.raises(OtpInvalid):
            await verify_code(email="locked@example.com", code="000000")
    with pytest.raises(OtpTooManyAttempts):
        await verify_code(email="locked@example.com", code="000000")

    refreshed = await EmailVerification.get(row.id)
    assert refreshed is not None
    assert refreshed.status == EmailVerificationStatus.EXPIRED
    assert refreshed.attempts == 5

    # Even the correct code now fails — row is expired.
    from app.services.otp_service import OtpInvalid as _OI

    with pytest.raises(_OI):
        await verify_code(email="locked@example.com", code=code)


@pytest.mark.asyncio
async def test_verify_code_after_expires_at_marks_expired(
    db: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.services import otp_service
    from app.services.otp_service import OtpExpired, request_code, verify_code

    row, code = await request_code(email="late@example.com")
    assert code is not None

    real_now = datetime.now(tz=UTC)
    monkeypatch.setattr(
        otp_service, "_utcnow", lambda: real_now + timedelta(minutes=11)
    )
    with pytest.raises(OtpExpired):
        await verify_code(email="late@example.com", code=code)

    refreshed = await EmailVerification.get(row.id)
    assert refreshed is not None
    assert refreshed.status == EmailVerificationStatus.EXPIRED


@pytest.mark.asyncio
async def test_verify_code_no_pending_row_raises_invalid(db: object) -> None:
    from app.services.otp_service import OtpInvalid, verify_code

    with pytest.raises(OtpInvalid):
        await verify_code(email="ghost@example.com", code="123456")


# Sanity: avoid stray asyncio import lint when above tests don't use it explicitly.
_ = asyncio
