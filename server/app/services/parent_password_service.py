"""Parent web password login and account password management."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from app.config import get_settings
from app.models.user import User, UserRole
from app.services.auth_service import hash_password, verify_password
from app.services.family_service import ParentLoginSuspended
from app.services.otp_service import verify_code

MIN_PASSWORD_LENGTH = 8


class ParentPasswordError(Exception):
    """Base for password flows; carries API error code."""

    code: str = "PASSWORD_ERROR"
    http_status: int = 400

    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message


class EmailNotRegistered(ParentPasswordError):
    code = "EMAIL_NOT_REGISTERED"
    http_status = 404


class PasswordNotSet(ParentPasswordError):
    code = "PASSWORD_NOT_SET"
    http_status = 409


class PasswordInvalid(ParentPasswordError):
    code = "PASSWORD_INVALID"
    http_status = 403


class OldPasswordInvalid(ParentPasswordError):
    code = "OLD_PASSWORD_INVALID"
    http_status = 403


class PasswordLocked(ParentPasswordError):
    code = "TOO_MANY_ATTEMPTS"
    http_status = 410


class RoleMismatch(ParentPasswordError):
    code = "ROLE_MISMATCH"
    http_status = 403


class WeakPassword(ParentPasswordError):
    code = "WEAK_PASSWORD"
    http_status = 400


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


def _to_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


def validate_new_password(password: str) -> None:
    if len(password) < MIN_PASSWORD_LENGTH:
        raise WeakPassword(
            f"Password must be at least {MIN_PASSWORD_LENGTH} characters."
        )


def _ensure_not_locked(user: User) -> None:
    if user.password_locked_until is None:
        return
    if _utcnow() >= _to_utc(user.password_locked_until):
        user.password_locked_until = None
        user.password_failed_attempts = 0
        return
    raise PasswordLocked("Too many failed attempts; try again later.")


async def _record_password_failure(user: User) -> None:
    settings = get_settings()
    user.password_failed_attempts += 1
    if user.password_failed_attempts >= settings.otp_max_attempts:
        user.password_locked_until = _utcnow() + timedelta(
            minutes=settings.password_lockout_minutes
        )
    await user.save()


async def _clear_password_failures(user: User) -> None:
    user.password_failed_attempts = 0
    user.password_locked_until = None


async def authenticate_parent_password(*, email: str, password: str) -> User:
    """Verify email/password for an existing parent; raises ParentPasswordError."""
    existing = await User.find_one(User.email == email)
    if existing is not None and existing.role == UserRole.ADMIN:
        raise RoleMismatch("This email belongs to an admin account.")
    if existing is None:
        raise EmailNotRegistered("No parent account for this email.")
    if existing.role != UserRole.PARENT:
        raise EmailNotRegistered("No parent account for this email.")
    if existing.parent_login_suspended_at is not None:
        raise ParentLoginSuspended() from None
    _ensure_not_locked(existing)
    if existing.password_hash is None:
        raise PasswordNotSet(
            "No password set for this account; use email code or OAuth, "
            "then set a password in Settings."
        )
    if not verify_password(password, existing.password_hash):
        await _record_password_failure(existing)
        raise PasswordInvalid("Incorrect password.")
    await _clear_password_failures(existing)
    existing.last_login_at = _utcnow()
    await existing.save()
    return existing


async def set_parent_password(*, user: User, code: str, new_password: str) -> None:
    """Set or reset password after OTP verification on the user's bound email."""
    if not user.email:
        raise ParentPasswordError("Account has no email; cannot verify OTP.")
    validate_new_password(new_password)
    await verify_code(email=user.email, code=code)
    user.password_hash = hash_password(new_password)
    await _clear_password_failures(user)
    await user.save()


async def change_parent_password(
    *, user: User, old_password: str, new_password: str
) -> None:
    """Change password when the user knows the current password."""
    if user.password_hash is None:
        raise PasswordNotSet("No password set yet.")
    _ensure_not_locked(user)
    validate_new_password(new_password)
    if not verify_password(old_password, user.password_hash):
        await _record_password_failure(user)
        raise OldPasswordInvalid("Current password is incorrect.")
    user.password_hash = hash_password(new_password)
    await _clear_password_failures(user)
    await user.save()
