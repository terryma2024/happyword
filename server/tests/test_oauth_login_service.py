"""Unit tests for Google OAuth parent login resolution."""

from __future__ import annotations

from datetime import UTC, datetime

import pytest

from app.models.family import Family
from app.models.oauth_identity import OAuthIdentity, OAuthProvider
from app.models.user import User, UserRole
from app.services.family_service import ParentLoginSuspended
from app.services.oauth_login_service import (
    GoogleUserClaims,
    OAuthRoleMismatch,
    resolve_google_login,
)


def _claims(*, sub: str = "google-sub-1", email: str = "parent@example.com") -> GoogleUserClaims:
    return GoogleUserClaims(subject=sub, email=email, email_verified=True)


@pytest.mark.asyncio
async def test_login_new_google_user_creates_family_and_identity(db: object) -> None:
    user, family = await resolve_google_login(_claims(email="new@example.com"))
    assert user.role == UserRole.PARENT
    assert user.email == "new@example.com"
    assert family.family_id == user.family_id
    identity = await OAuthIdentity.find_one(
        OAuthIdentity.provider == OAuthProvider.GOOGLE,
        OAuthIdentity.provider_subject == "google-sub-1",
    )
    assert identity is not None
    assert identity.user_id == user.username


@pytest.mark.asyncio
async def test_login_existing_identity_returns_same_user(db: object) -> None:
    now = datetime.now(tz=UTC)
    user = User(
        username="parent-aaaa",
        password_hash=None,
        role=UserRole.PARENT,
        created_at=now,
        family_id="fam-bbbb",
        email="existing@example.com",
    )
    await user.insert()
    await Family(
        family_id="fam-bbbb",
        owner_user_id=user.username,
        primary_email="existing@example.com",
        created_at=now,
        updated_at=now,
    ).insert()
    await OAuthIdentity(
        provider=OAuthProvider.GOOGLE,
        provider_subject="google-sub-2",
        user_id=user.username,
        email="existing@example.com",
        email_verified=True,
        linked_at=now,
    ).insert()

    resolved_user, _family = await resolve_google_login(
        _claims(sub="google-sub-2", email="existing@example.com")
    )
    assert resolved_user.username == user.username
    assert await User.count() == 1


@pytest.mark.asyncio
async def test_login_merges_by_email(db: object) -> None:
    now = datetime.now(tz=UTC)
    user = User(
        username="parent-cccc",
        password_hash=None,
        role=UserRole.PARENT,
        created_at=now,
        family_id="fam-dddd",
        email="merge@example.com",
    )
    await user.insert()
    await Family(
        family_id="fam-dddd",
        owner_user_id=user.username,
        primary_email="merge@example.com",
        created_at=now,
        updated_at=now,
    ).insert()

    resolved_user, _family = await resolve_google_login(
        _claims(sub="google-sub-3", email="merge@example.com")
    )
    assert resolved_user.username == user.username
    identity = await OAuthIdentity.find_one(
        OAuthIdentity.provider_subject == "google-sub-3",
    )
    assert identity is not None


@pytest.mark.asyncio
async def test_login_rejects_admin_email(db: object) -> None:
    now = datetime.now(tz=UTC)
    await User(
        username="admin1",
        password_hash="hash",
        role=UserRole.ADMIN,
        created_at=now,
        email="admin@example.com",
    ).insert()

    with pytest.raises(OAuthRoleMismatch):
        await resolve_google_login(_claims(email="admin@example.com"))


@pytest.mark.asyncio
async def test_login_rejects_suspended_parent(db: object) -> None:
    now = datetime.now(tz=UTC)
    await User(
        username="parent-susp",
        password_hash=None,
        role=UserRole.PARENT,
        created_at=now,
        family_id="fam-susp",
        email="suspended@example.com",
        parent_login_suspended_at=now,
    ).insert()
    await Family(
        family_id="fam-susp",
        owner_user_id="parent-susp",
        primary_email="suspended@example.com",
        created_at=now,
        updated_at=now,
    ).insert()

    with pytest.raises(ParentLoginSuspended):
        await resolve_google_login(_claims(email="suspended@example.com"))
