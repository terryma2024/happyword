"""V0.6.1 — atomic Family + parent User creation."""

import secrets
from datetime import UTC, datetime

from app.models.family import Family
from app.models.user import User, UserRole


def _gen_id(prefix: str) -> str:
    return f"{prefix}-{secrets.token_hex(4)}"


async def create_family_for_parent(*, email: str) -> tuple[Family, User]:
    """Idempotently create a Family + parent User keyed by `email`.

    If a parent User with `email` already exists, returns the existing pair
    without creating duplicates. If a User exists but its Family does not
    (a partially-failed prior create), heals the missing Family.
    """
    existing_user = await User.find_one(
        User.email == email, User.role == UserRole.PARENT
    )
    if existing_user is not None:
        family = await Family.find_one(Family.owner_user_id == existing_user.username)
        if family is not None:
            return family, existing_user
        family = await _insert_family(
            email=email, owner_user_id=existing_user.username
        )
        if existing_user.family_id is None:
            existing_user.family_id = family.family_id
            await existing_user.save()
        return family, existing_user

    now = datetime.now(tz=UTC)
    user_id = _gen_id("parent")
    family = await _insert_family(email=email, owner_user_id=user_id)
    user = User(
        username=user_id,
        password_hash=None,
        role=UserRole.PARENT,
        created_at=now,
        family_id=family.family_id,
        email=email,
        display_name=email.split("@", 1)[0],
    )
    await user.insert()
    return family, user


async def _insert_family(*, email: str, owner_user_id: str) -> Family:
    now = datetime.now(tz=UTC)
    family = Family(
        family_id=_gen_id("fam"),
        owner_user_id=owner_user_id,
        primary_email=email,
        created_at=now,
        updated_at=now,
    )
    await family.insert()
    return family
