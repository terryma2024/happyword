from datetime import UTC, datetime

import pytest

from app.models.user import User, UserRole


@pytest.mark.asyncio
async def test_create_and_read_user(db: object) -> None:
    u = User(
        username="alice",
        password_hash="bcrypt-hash",
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()

    found = await User.find_one(User.username == "alice")
    assert found is not None
    assert found.role is UserRole.ADMIN
    assert found.last_login_at is None


@pytest.mark.asyncio
async def test_username_is_unique(db: object) -> None:
    base = {
        "password_hash": "x",
        "role": UserRole.ADMIN,
        "created_at": datetime.now(tz=UTC),
    }
    await User(username="bob", **base).insert()
    with pytest.raises(Exception):
        await User(username="bob", **base).insert()
