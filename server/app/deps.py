import time

from fastapi import Cookie, Depends, HTTPException, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import get_settings
from app.models.user import User, UserRole
from app.services.auth_service import (
    JwtError,
    create_session_token,
    decode_access_token,
    decode_typed_token,
)

_bearer = HTTPBearer(auto_error=False)


async def current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> User:
    if creds is None or creds.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": {"code": "UNAUTHORIZED", "message": "Missing bearer token"}},
        )
    try:
        payload = decode_access_token(creds.credentials)
    except JwtError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": {"code": "UNAUTHORIZED", "message": "Invalid or expired token"}},
        ) from None
    sub = payload.get("sub")
    if not isinstance(sub, str):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": {"code": "UNAUTHORIZED", "message": "Token missing subject"}},
        )
    user = await User.find_one(User.username == sub)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": {"code": "UNAUTHORIZED", "message": "User not found"}},
        )
    return user


async def current_admin_user(user: User = Depends(current_user)) -> User:
    """Authorize-only wrapper requiring `role == ADMIN`. Returns 403 otherwise."""
    if user.role != UserRole.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error": {"code": "FORBIDDEN", "message": "Admin role required"}},
        )
    return user


def set_parent_session_cookie(response: Response, token: str) -> None:
    """Set the parent session cookie with project-standard attrs.

    Centralized so both `current_parent_user` (renewal path) and
    `parent_auth.verify_code` (initial issue) emit the same cookie shape.
    """
    settings = get_settings()
    response.set_cookie(
        key=settings.session_cookie_name,
        value=token,
        max_age=settings.parent_session_expire_hours * 3600,
        httponly=True,
        secure=settings.parent_web_base_url.startswith("https"),
        samesite="lax",
        domain=settings.session_cookie_domain or None,
        path="/",
    )


def clear_parent_session_cookie(response: Response) -> None:
    settings = get_settings()
    response.delete_cookie(
        key=settings.session_cookie_name,
        domain=settings.session_cookie_domain or None,
        path="/",
    )


async def current_parent_user(
    response: Response,
    cookie_token: str | None = Cookie(default=None, alias="wm_session"),
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> User:
    """Authenticate a parent. Cookie first, then `Authorization: Bearer <token>`.

    Renews the session cookie if the token's `iat` is older than
    `parent_session_renew_after_days` (spec §14 r3 lock-in #2: iat>7d只续).
    """
    settings = get_settings()
    token = cookie_token
    via_cookie = token is not None
    if not token and creds is not None and creds.scheme.lower() == "bearer":
        token = creds.credentials
        via_cookie = False
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": {"code": "UNAUTHORIZED", "message": "Missing parent session"}},
        )
    try:
        typed = decode_typed_token(token)
    except JwtError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": {"code": "UNAUTHORIZED", "message": "Invalid parent session"}},
        ) from None
    if typed.role != "parent":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error": {"code": "FORBIDDEN", "message": "Parent role required"}},
        )
    user = await User.find_one(
        User.username == typed.identifier, User.role == UserRole.PARENT
    )
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": {"code": "UNAUTHORIZED", "message": "Parent not found"}},
        )

    # Cookie renewal: only when authenticated via cookie AND token iat is stale.
    if via_cookie:
        try:
            payload = decode_access_token(token)
        except JwtError:
            payload = {}
        iat_raw = payload.get("iat", 0)
        try:
            iat = int(iat_raw)
        except (TypeError, ValueError):
            iat = 0
        renew_after_seconds = settings.parent_session_renew_after_days * 86400
        if (int(time.time()) - iat) > renew_after_seconds:
            new_token = create_session_token(role="parent", identifier=user.username)
            set_parent_session_cookie(response, new_token)

    return user
