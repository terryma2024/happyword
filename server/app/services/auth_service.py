import time
from typing import Any

import bcrypt
from jose import JWTError, jwt

from app.config import get_settings


class JwtError(Exception):
    """Raised when a token cannot be verified."""


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
