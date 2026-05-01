import time
from dataclasses import dataclass
from typing import Any, Literal, get_args

import bcrypt
from jose import JWTError, jwt

from app.config import get_settings


class JwtError(Exception):
    """Raised when a token cannot be verified."""


SessionRole = Literal["admin", "parent", "device"]
_VALID_ROLES = set(get_args(SessionRole))


@dataclass(frozen=True)
class TypedSubject:
    """Decoded V0.6+ session token sub: `<role>:<identifier>`."""

    role: SessionRole
    identifier: str

    @property
    def sub(self) -> str:
        return f"{self.role}:{self.identifier}"


def hash_password(plain: str) -> str:
    """Return a bcrypt hash of the password using a fresh salt per call."""
    return bcrypt.hashpw(plain.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    """Constant-time bcrypt comparison; returns False on malformed hash."""
    try:
        return bcrypt.checkpw(plain.encode("utf-8"), hashed.encode("utf-8"))
    except ValueError:
        return False


def create_access_token(subject: str, expires_in: int | None = None) -> str:
    settings = get_settings()
    if expires_in is None:
        expires_in = settings.jwt_expire_hours * 3600
    now = int(time.time())
    payload: dict[str, Any] = {"sub": subject, "iat": now, "exp": now + expires_in}
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def decode_access_token(token: str) -> dict[str, Any]:
    settings = get_settings()
    try:
        decoded: dict[str, Any] = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
        return decoded
    except JWTError as e:
        raise JwtError(str(e)) from e


def create_session_token(
    *,
    role: SessionRole,
    identifier: str,
    expires_in: int | None = None,
) -> str:
    """V0.6+ typed session token: sub = `<role>:<identifier>`.

    Parent sessions default to `parent_session_expire_hours` (30 days).
    Admin tokens emitted via this path replace the legacy bare-username sub
    over time; the legacy `create_access_token` is preserved for V0.5
    `/api/v1/auth/login` backward compatibility.
    """
    settings = get_settings()
    if expires_in is None:
        expires_in = settings.parent_session_expire_hours * 3600
    now = int(time.time())
    payload: dict[str, Any] = {
        "sub": f"{role}:{identifier}",
        "iat": now,
        "exp": now + expires_in,
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def decode_typed_token(token: str) -> TypedSubject:
    """Decode a V0.6+ typed token; raises JwtError on bad/legacy/unknown sub."""
    payload = decode_access_token(token)
    sub = payload.get("sub")
    if not isinstance(sub, str) or ":" not in sub:
        raise JwtError("token sub missing role prefix")
    role, _, identifier = sub.partition(":")
    if role not in _VALID_ROLES:
        raise JwtError(f"unknown role {role!r}")
    if not identifier:
        raise JwtError("empty identifier")
    return TypedSubject(role=role, identifier=identifier)  # type: ignore[arg-type]
