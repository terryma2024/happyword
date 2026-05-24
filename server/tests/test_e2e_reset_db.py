"""Unit coverage for the E2E database reset helper."""

from __future__ import annotations

import pytest

from app.models.word import Word
from app.services.auth_service import verify_password
from scripts.e2e_reset_db import seed_words_from_rawfile, upsert_admin_user


@pytest.mark.asyncio
async def test_e2e_reset_seed_inserts_rawfile_words(db: object) -> None:
    inserted, skipped = await seed_words_from_rawfile(db)

    assert inserted == 50
    assert skipped == 0
    assert await Word.find_all().count() == 50
    apple = await Word.find_one(Word.id == "fruit-apple")
    assert apple is not None
    assert apple.word == "apple"
    assert apple.meaningZh == "苹果"


@pytest.mark.asyncio
async def test_e2e_reset_seed_is_idempotent(db: object) -> None:
    await seed_words_from_rawfile(db)
    inserted, skipped = await seed_words_from_rawfile(db)

    assert inserted == 0
    assert skipped == 50
    assert await Word.find_all().count() == 50


@pytest.mark.asyncio
async def test_e2e_reset_upserts_admin_user(db: object) -> None:
    from app.models.user import User, UserRole

    assert await upsert_admin_user(db, username="ci-admin", password="secret-1")

    admin = await User.find_one(User.username == "ci-admin")
    assert admin is not None
    assert admin.role == UserRole.ADMIN
    assert admin.password_hash is not None
    assert verify_password("secret-1", admin.password_hash)

    assert await upsert_admin_user(db, username="ci-admin", password="secret-2")

    updated = await User.find_one(User.username == "ci-admin")
    assert updated is not None
    assert updated.password_hash is not None
    assert verify_password("secret-2", updated.password_hash)
