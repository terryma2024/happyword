"""V0.6.1 — family_service.create_family_for_parent atomic creation."""

import pytest

from app.models.family import Family
from app.models.user import User, UserRole


@pytest.mark.asyncio
async def test_create_family_for_parent_inserts_family_and_user(db: object) -> None:
    from app.services.family_service import create_family_for_parent

    family, user = await create_family_for_parent(email="alice@example.com")
    assert user.role == UserRole.PARENT
    assert user.email == "alice@example.com"
    assert user.password_hash is None
    assert user.family_id == family.family_id
    assert user.display_name == "alice"
    assert family.primary_email == "alice@example.com"
    assert family.owner_user_id == user.username
    assert family.family_id.startswith("fam-")

    fams = await Family.find(Family.primary_email == "alice@example.com").to_list()
    assert len(fams) == 1
    users = await User.find(User.email == "alice@example.com").to_list()
    assert len(users) == 1


@pytest.mark.asyncio
async def test_create_family_for_parent_idempotent_for_existing(db: object) -> None:
    from app.services.family_service import create_family_for_parent

    fam1, u1 = await create_family_for_parent(email="bob@example.com")
    fam2, u2 = await create_family_for_parent(email="bob@example.com")
    assert fam1.family_id == fam2.family_id
    assert u1.username == u2.username
    assert (await Family.count()) == 1


@pytest.mark.asyncio
async def test_create_family_does_not_collide_with_admin_users(db: object) -> None:
    """Admins live in the same User collection but with role=ADMIN; parent
    creation must not collide on `email` / `username` indexes."""
    from datetime import UTC, datetime

    from app.services.auth_service import hash_password
    from app.services.family_service import create_family_for_parent

    await User(
        username="admin",
        password_hash=hash_password("admin-pw"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    ).insert()

    family, user = await create_family_for_parent(email="parent2@example.com")
    assert user.role == UserRole.PARENT
    assert family.family_id.startswith("fam-")
    assert (await User.count()) == 2  # admin + new parent
