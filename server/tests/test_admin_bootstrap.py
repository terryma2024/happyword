from datetime import UTC, datetime

import pytest

from app.main import bootstrap_admin_user
from app.models.user import User, UserRole
from app.services.auth_service import hash_password, verify_password


@pytest.mark.asyncio
async def test_bootstrap_creates_admin_when_missing(db: object) -> None:
    await bootstrap_admin_user(username="admin", password="seekrit99")
    u = await User.find_one(User.username == "admin")
    assert u is not None
    assert u.role is UserRole.ADMIN
    assert verify_password("seekrit99", u.password_hash)


@pytest.mark.asyncio
async def test_bootstrap_is_idempotent_when_existing_admin_matches(db: object) -> None:
    existing = await User(
        username="admin",
        password_hash=hash_password("original"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    ).insert()
    original_hash = existing.password_hash

    await bootstrap_admin_user(username="admin", password="original")

    u = await User.find_one(User.username == "admin")
    assert u is not None
    assert u.password_hash == original_hash
    assert verify_password("original", u.password_hash)


@pytest.mark.asyncio
async def test_bootstrap_updates_password_when_admin_exists(db: object) -> None:
    await User(
        username="admin",
        password_hash=hash_password("original"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    ).insert()

    await bootstrap_admin_user(username="admin", password="changed")

    u = await User.find_one(User.username == "admin")
    assert u is not None
    assert verify_password("changed", u.password_hash)
    assert not verify_password("original", u.password_hash)
