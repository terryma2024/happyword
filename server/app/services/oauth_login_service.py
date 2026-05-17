"""Resolve parent User + Family after a verified OAuth IdP identity."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime

from app.models.family import Family
from app.models.oauth_identity import OAuthIdentity, OAuthProvider
from app.models.user import User, UserRole
from app.services.family_service import ParentLoginSuspended, create_family_for_parent


class OAuthRoleMismatch(Exception):
    """Email belongs to an admin account."""


class OAuthEmailUnavailable(Exception):
    """IdP did not supply a verified email for a new account."""


@dataclass(frozen=True)
class OAuthUserClaims:
    subject: str
    email: str | None = None
    email_verified: bool = False


# Backward-compatible alias for Google-specific tests and stubs.
GoogleUserClaims = OAuthUserClaims


def _normalize_email(email: str) -> str:
    return email.strip().lower()


async def resolve_google_login(claims: OAuthUserClaims) -> tuple[User, Family]:
    return await resolve_oauth_login(OAuthProvider.GOOGLE, claims)


async def resolve_apple_login(claims: OAuthUserClaims) -> tuple[User, Family]:
    return await resolve_oauth_login(OAuthProvider.APPLE, claims)


async def resolve_existing_oauth_login(
    provider: OAuthProvider,
    provider_subject: str,
) -> tuple[User, Family] | None:
    existing_identity = await OAuthIdentity.find_one(
        OAuthIdentity.provider == provider,
        OAuthIdentity.provider_subject == provider_subject,
    )
    if existing_identity is None:
        return None
    user = await User.find_one(User.username == existing_identity.user_id)
    if user is None:
        msg = "OAuth identity references missing user"
        raise ValueError(msg)
    if user.parent_login_suspended_at is not None:
        raise ParentLoginSuspended()
    family = await _family_for_user(user)
    return user, family


async def resolve_oauth_login(
    provider: OAuthProvider,
    claims: OAuthUserClaims,
) -> tuple[User, Family]:
    existing = await resolve_existing_oauth_login(provider, claims.subject)
    if existing is not None:
        return existing

    if not claims.email or not claims.email_verified:
        raise OAuthEmailUnavailable()

    email = _normalize_email(claims.email)
    admin = await User.find_one(User.email == email, User.role == UserRole.ADMIN)
    if admin is not None:
        raise OAuthRoleMismatch()

    parent = await User.find_one(User.email == email, User.role == UserRole.PARENT)
    if parent is not None:
        if parent.parent_login_suspended_at is not None:
            raise ParentLoginSuspended()
        await _insert_identity(
            provider=provider,
            provider_subject=claims.subject,
            user_id=parent.username,
            email=email,
            email_verified=claims.email_verified,
        )
        family = await _family_for_user(parent)
        return parent, family

    family, user = await create_family_for_parent(email=email)
    await _insert_identity(
        provider=provider,
        provider_subject=claims.subject,
        user_id=user.username,
        email=email,
        email_verified=claims.email_verified,
    )
    return user, family


async def _family_for_user(user: User) -> Family:
    if not user.family_id:
        msg = "Parent user missing family_id"
        raise ValueError(msg)
    family = await Family.find_one(Family.family_id == user.family_id)
    if family is None:
        msg = "Family not found for parent user"
        raise ValueError(msg)
    return family


async def _insert_identity(
    *,
    provider: OAuthProvider,
    provider_subject: str,
    user_id: str,
    email: str,
    email_verified: bool,
) -> OAuthIdentity:
    row = OAuthIdentity(
        provider=provider,
        provider_subject=provider_subject,
        user_id=user_id,
        email=email,
        email_verified=email_verified,
        linked_at=datetime.now(tz=UTC),
    )
    await row.insert()
    return row
