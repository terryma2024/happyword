"""V0.6.1 — OTP issuance + verification.

Pure persistence-layer service. Does NOT send email itself; the router calls
`notification_service.send_otp_email(provider, ...)` with the plain code
returned by `request_code`. Keeping the side-effect outside means tests
don't need to mock SMTP just to exercise rate-limiting or attempt counting.

Security stance:
- 6-digit decimal code, generated via `secrets.randbelow` (CSPRNG).
- Only the bcrypt hash is persisted; we never log the plain code.
- Per-email 1/min request rate-limit (returning the existing pending row).
- Per-OTP 5-attempt cap; on cap reach the row is moved to `expired`.
- Successful verify moves the row to `used`; row is single-use.
- `verify_code` always works against the latest pending row only — older
  pending rows are pre-emptively expired by `request_code`.
"""

import secrets
from datetime import UTC, datetime, timedelta

from beanie.odm.enums import SortDirection

from app.config import get_settings
from app.models.email_verification import EmailVerification, EmailVerificationStatus
from app.services.auth_service import hash_password, verify_password


class OtpVerificationError(Exception):
    """Base class for OTP verification failures."""


class OtpInvalid(OtpVerificationError):
    """Code did not match (wrong code, no pending row, or already-expired row)."""


class OtpExpired(OtpVerificationError):
    """Pending row exists but `expires_at` has passed."""


class OtpTooManyAttempts(OtpVerificationError):
    """Attempt count reached `otp_max_attempts`; row is now expired."""


def _utcnow() -> datetime:
    """Indirection so tests can monkeypatch a clock without freezing real time."""
    return datetime.now(tz=UTC)


def _to_utc(dt: datetime) -> datetime:
    """Coerce a possibly-naive datetime (mongomock round-trip) to UTC-aware.

    MongoDB stores BSON datetimes in UTC milliseconds; both pymongo and
    mongomock-motor return them as naive `datetime` objects on the Python
    side, which then cannot be compared to our tz-aware `_utcnow()`.
    """
    if dt.tzinfo is None:
        return dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


def _generate_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


async def request_code(email: str) -> tuple[EmailVerification, str | None]:
    """Issue or rate-limit-replay an OTP row for `email`.

    Returns `(row, plain_code)`. When `plain_code is None` the caller MUST
    NOT send a new email (rate-limit hit) — the existing pending row is
    returned so the caller can still respond 202 to the user.
    """
    settings = get_settings()
    now = _utcnow()
    cutoff = now - timedelta(seconds=settings.otp_request_min_interval_seconds)

    recent = await EmailVerification.find_one(
        EmailVerification.email == email,
        EmailVerification.status == EmailVerificationStatus.PENDING,
        EmailVerification.created_at > cutoff,
    )
    if recent is not None:
        return recent, None

    # Invalidate any stale pending rows for this email (one-pending-row invariant).
    stale = await EmailVerification.find(
        EmailVerification.email == email,
        EmailVerification.status == EmailVerificationStatus.PENDING,
    ).to_list()
    for s in stale:
        s.status = EmailVerificationStatus.EXPIRED
        await s.save()

    code = _generate_code()
    row = EmailVerification(
        email=email,
        code_hash=hash_password(code),
        status=EmailVerificationStatus.PENDING,
        attempts=0,
        created_at=now,
        expires_at=now + timedelta(minutes=settings.otp_expiry_minutes),
    )
    await row.insert()
    return row, code


async def verify_code(*, email: str, code: str) -> EmailVerification:
    """Verify `code` against the latest pending row for `email`.

    Raises one of the OtpVerificationError subclasses on failure; returns the
    used row on success. Caller is expected to commit the new parent session
    cookie only when this returns successfully.
    """
    settings = get_settings()
    now = _utcnow()

    row = await EmailVerification.find(
        EmailVerification.email == email,
        EmailVerification.status == EmailVerificationStatus.PENDING,
        sort=[("created_at", SortDirection.DESCENDING)],
    ).first_or_none()
    if row is None:
        raise OtpInvalid

    if now >= _to_utc(row.expires_at):
        row.status = EmailVerificationStatus.EXPIRED
        await row.save()
        raise OtpExpired

    if not verify_password(code, row.code_hash):
        row.attempts += 1
        if row.attempts >= settings.otp_max_attempts:
            row.status = EmailVerificationStatus.EXPIRED
            await row.save()
            raise OtpTooManyAttempts
        await row.save()
        raise OtpInvalid

    row.status = EmailVerificationStatus.USED
    row.used_at = now
    await row.save()
    return row
