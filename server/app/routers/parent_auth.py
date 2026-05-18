"""V0.6.1 — parent OTP authentication API.

Endpoint scope (no cookie required for request-/verify-code; cookie required
for /me and logout). All responses use the project-standard envelope:
`{"detail": {"error": {"code": <STR>, "message": <STR>}}}` for errors and a
plain Pydantic body for success.
"""

from __future__ import annotations

import contextlib
from typing import TYPE_CHECKING

from fastapi import APIRouter, Depends, HTTPException, Path, Response, status

from app.config import get_settings
from app.deps import (
    clear_parent_session_cookie,
    current_parent_user,
    set_parent_session_cookie,
)
from app.deps_email import get_email_provider
from app.models.user import User, UserRole
from app.schemas.parent_auth import (
    ParentMeOut,
    RequestCodeIn,
    RequestCodeOut,
    VerifyCodeIn,
    VerifyCodeOut,
)
from app.schemas.parent_password import PasswordLoginIn, PasswordLoginOut
from app.services.parent_password_service import (
    ParentPasswordError,
    RoleMismatch,
    authenticate_parent_password,
)
from app.services.auth_service import create_session_token
from app.services.family_service import ParentLoginSuspended, create_family_for_parent
from app.services.notification_service import (
    EmailDeliveryDegraded,
    send_otp_email,
)
from app.services.otp_service import (
    OtpExpired,
    OtpInvalid,
    OtpTooManyAttempts,
    request_code,
    verify_code,
)

if TYPE_CHECKING:
    from app.services.email_provider import EmailProvider

router = APIRouter(prefix="/api/v1/family", tags=["parent-auth"])


def _normalize_email(email: str) -> str:
    return email.strip().lower()


def _password_error_http(exc: ParentPasswordError) -> HTTPException:
    return HTTPException(
        status_code=exc.http_status,
        detail={"error": {"code": exc.code, "message": exc.message}},
    )


@router.post(
    "/{family_id}/auth/password-login",
    response_model=PasswordLoginOut,
)
async def post_password_login(
    payload: PasswordLoginIn,
    response: Response,
    family_id: str = Path(min_length=1, max_length=128),
) -> PasswordLoginOut:
    _ = family_id
    email = _normalize_email(payload.email)
    try:
        user = await authenticate_parent_password(email=email, password=payload.password)
    except RoleMismatch as e:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "error": {
                    "code": "ROLE_MISMATCH",
                    "message": "This email belongs to an admin account; use /api/v1/admin/auth/login.",
                }
            },
        ) from e
    except ParentLoginSuspended:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "error": {
                    "code": "PARENT_LOGIN_SUSPENDED",
                    "message": "Parent account login is suspended by an administrator.",
                }
            },
        ) from None
    except ParentPasswordError as e:
        raise _password_error_http(e) from e

    token = create_session_token(role="parent", identifier=user.username)
    set_parent_session_cookie(response, token)
    return PasswordLoginOut(
        user_id=user.username,
        family_id=user.family_id or "",
        email=user.email or email,
        display_name=user.display_name,
    )


@router.post(
    "/{family_id}/auth/request-code",
    response_model=RequestCodeOut,
    status_code=status.HTTP_202_ACCEPTED,
)
async def post_request_code(
    payload: RequestCodeIn,
    family_id: str = Path(min_length=1, max_length=128),
    provider: EmailProvider = Depends(get_email_provider),
) -> RequestCodeOut:
    """Always 202: do NOT reveal whether the email is known (anti-enumeration).

    Sends the OTP email only when not rate-limited. Email-delivery failures
    are degraded silently — the row is persisted and the user can retry; we
    do not leak provider state to the public endpoint.
    """
    _ = family_id  # Decorative until path/session enforcement lands.
    settings = get_settings()
    email = _normalize_email(payload.email)
    row, plain_code = await request_code(email)
    if plain_code is not None:
        # Row persists; user can retry. Do not propagate to caller (anti-enum).
        with contextlib.suppress(EmailDeliveryDegraded):
            await send_otp_email(
                provider,
                to=email,
                code=plain_code,
                expires_in_minutes=settings.otp_expiry_minutes,
            )
    return RequestCodeOut(expires_in_minutes=settings.otp_expiry_minutes)


@router.post(
    "/{family_id}/auth/verify-code",
    response_model=VerifyCodeOut,
)
async def post_verify_code(
    payload: VerifyCodeIn,
    response: Response,
    family_id: str = Path(min_length=1, max_length=128),
) -> VerifyCodeOut:
    _ = family_id  # Decorative until path/session enforcement lands.
    email = _normalize_email(payload.email)

    # Reject admin-owned email addresses up front (avoids creating a stray
    # parent row that collides on the unique email index).
    existing = await User.find_one(User.email == email)
    if existing is not None and existing.role == UserRole.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "error": {
                    "code": "ROLE_MISMATCH",
                    "message": "This email belongs to an admin account; use /api/v1/admin/auth/login.",
                }
            },
        )

    try:
        await verify_code(email=email, code=payload.code)
    except OtpInvalid as e:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error": {"code": "INVALID_CODE", "message": "Invalid verification code."}},
        ) from e
    except OtpTooManyAttempts as e:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail={
                "error": {
                    "code": "TOO_MANY_ATTEMPTS",
                    "message": "Too many wrong attempts; request a new code.",
                }
            },
        ) from e
    except OtpExpired as e:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail={
                "error": {
                    "code": "CODE_EXPIRED",
                    "message": "Verification code expired; request a new one.",
                }
            },
        ) from e

    try:
        family, user = await create_family_for_parent(email=email)
    except ParentLoginSuspended:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "error": {
                    "code": "PARENT_LOGIN_SUSPENDED",
                    "message": "Parent account login is suspended by an administrator.",
                }
            },
        ) from None
    token = create_session_token(role="parent", identifier=user.username)
    set_parent_session_cookie(response, token)

    return VerifyCodeOut(
        user_id=user.username,
        family_id=family.family_id,
        email=user.email or email,
        display_name=user.display_name,
        delivery_degraded=False,
    )


@router.post("/{family_id}/auth/logout", status_code=status.HTTP_200_OK)
async def post_logout(
    response: Response,
    family_id: str = Path(min_length=1, max_length=128),
) -> dict[str, str]:
    _ = family_id
    clear_parent_session_cookie(response)
    return {"status": "logged_out"}


@router.get("/{family_id}/me", response_model=ParentMeOut)
async def get_me(
    family_id: str = Path(min_length=1, max_length=128),
    user: User = Depends(current_parent_user),
) -> ParentMeOut:
    _ = family_id
    return ParentMeOut(
        id=user.username,
        email=user.email or "",
        display_name=user.display_name,
        family_id=user.family_id or "",
        role=user.role.value,
        timezone=user.timezone,
    )
