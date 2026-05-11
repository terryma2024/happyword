"""Unit tests for the per-PR DB cleanup script."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock

import pytest
from pymongo.errors import OperationFailure

from scripts.e2e_drop_old_pr_dbs import (
    UnsafePattern,
    _list_candidate_dbs,
    _matches_safe_pattern,
    drop_stale,
)


def test_safe_pattern_must_end_with_known_suffix() -> None:
    """Patterns must end with `_e2e$`, `_test$`, or `_ci$`."""
    assert _matches_safe_pattern(r"^happyword_pr_\d+_e2e$") is True
    assert _matches_safe_pattern(r"^happyword_pr_\d+_test$") is True
    assert _matches_safe_pattern(r"^happyword_pr_\d+_ci$") is True


def test_safe_pattern_rejects_unsafe_suffix() -> None:
    """Unsafe patterns are rejected so a typo can't drop production."""
    assert _matches_safe_pattern(r".*") is False
    assert _matches_safe_pattern(r"^happyword_") is False
    assert _matches_safe_pattern(r"^happyword_prod$") is False


def test_list_candidate_dbs_filters_by_regex_only() -> None:
    """Filtering by regex returns only matching DB names; ages aren't checked here."""
    all_names = [
        "happyword_pr_42_e2e",
        "happyword_pr_43_e2e",
        "happyword_staging",
        "happyword_prod",
        "admin",
    ]
    matched = _list_candidate_dbs(all_names, r"^happyword_pr_\d+_e2e$")
    assert sorted(matched) == ["happyword_pr_42_e2e", "happyword_pr_43_e2e"]


@pytest.mark.asyncio
async def test_drop_stale_dry_run_only_lists() -> None:
    """`--dry-run` reports candidates without dropping anything."""
    client = MagicMock()
    client.list_database_names = AsyncMock(return_value=["happyword_pr_1_e2e", "happyword_staging"])
    client.drop_database = AsyncMock()
    fake_now = datetime.now(tz=UTC)
    fake_old = fake_now - timedelta(days=20)

    async def fake_age(_client: object, name: str) -> datetime:
        return fake_old if name == "happyword_pr_1_e2e" else fake_now

    dropped, candidates = await drop_stale(
        client,
        pattern=r"^happyword_pr_\d+_e2e$",
        older_than_days=14,
        dry_run=True,
        age_resolver=fake_age,
    )
    assert candidates == ["happyword_pr_1_e2e"]
    assert dropped == []
    client.drop_database.assert_not_awaited()


@pytest.mark.asyncio
async def test_drop_stale_drops_only_old_matching() -> None:
    """Without dry-run, drops DBs that match pattern AND are old enough."""
    client = MagicMock()
    client.list_database_names = AsyncMock(return_value=[
        "happyword_pr_1_e2e", "happyword_pr_2_e2e", "happyword_staging",
    ])
    client.drop_database = AsyncMock()
    fake_now = datetime.now(tz=UTC)

    async def fake_age(_client: object, name: str) -> datetime:
        if name == "happyword_pr_1_e2e":
            return fake_now - timedelta(days=20)   # old → drop
        if name == "happyword_pr_2_e2e":
            return fake_now - timedelta(days=5)    # young → keep
        return fake_now

    dropped, candidates = await drop_stale(
        client,
        pattern=r"^happyword_pr_\d+_e2e$",
        older_than_days=14,
        dry_run=False,
        age_resolver=fake_age,
    )
    assert candidates == ["happyword_pr_1_e2e", "happyword_pr_2_e2e"]
    assert dropped == ["happyword_pr_1_e2e"]
    client.drop_database.assert_awaited_once_with("happyword_pr_1_e2e")


@pytest.mark.asyncio
async def test_drop_stale_can_drop_empty_dbs_but_excludes_current() -> None:
    """Failed preview startups can leave empty PR DBs that still consume collections."""
    client = MagicMock()
    client.list_database_names = AsyncMock(
        return_value=[
            "happyword_pr_60_e2e",
            "happyword_pr_61_e2e",
            "happyword_staging",
        ]
    )
    client.drop_database = AsyncMock()

    async def fake_age(_client: object, _name: str) -> datetime | None:
        return None

    dropped, candidates = await drop_stale(
        client,
        pattern=r"^happyword_pr_\d+_e2e$",
        older_than_days=14,
        dry_run=False,
        drop_empty=True,
        exclude_names={"happyword_pr_61_e2e"},
        age_resolver=fake_age,
    )
    assert candidates == ["happyword_pr_60_e2e", "happyword_pr_61_e2e"]
    assert dropped == ["happyword_pr_60_e2e"]
    client.drop_database.assert_awaited_once_with("happyword_pr_60_e2e")


@pytest.mark.asyncio
async def test_drop_stale_can_ignore_unauthorized_drop_errors() -> None:
    """CI cleanup is best-effort when the E2E Mongo user cannot drop old DBs."""
    client = MagicMock()
    client.list_database_names = AsyncMock(return_value=["happyword_pr_30_e2e"])
    client.drop_database = AsyncMock(
        side_effect=OperationFailure("user is not allowed to do action [dropDatabase]")
    )

    async def fake_age(_client: object, _name: str) -> datetime | None:
        return None

    ignored_errors: list[str] = []
    dropped, candidates = await drop_stale(
        client,
        pattern=r"^happyword_pr_\d+_e2e$",
        older_than_days=14,
        dry_run=False,
        drop_empty=True,
        ignore_drop_errors=True,
        ignored_drop_errors=ignored_errors,
        age_resolver=fake_age,
    )

    assert candidates == ["happyword_pr_30_e2e"]
    assert dropped == []
    assert len(ignored_errors) == 1
    assert "happyword_pr_30_e2e" in ignored_errors[0]
    assert "dropDatabase" in ignored_errors[0]


@pytest.mark.asyncio
async def test_drop_stale_falls_back_to_dropping_collections() -> None:
    """Dropping collections frees Atlas quota when dropDatabase is disallowed."""
    stale_db = MagicMock()
    stale_db.list_collection_names = AsyncMock(return_value=["words", "word_packs"])
    stale_db.drop_collection = AsyncMock()

    client = MagicMock()
    client.list_database_names = AsyncMock(return_value=["happyword_pr_30_e2e"])
    client.drop_database = AsyncMock(
        side_effect=OperationFailure("user is not allowed to do action [dropDatabase]")
    )
    client.__getitem__.return_value = stale_db

    async def fake_age(_client: object, _name: str) -> datetime | None:
        return None

    dropped, candidates = await drop_stale(
        client,
        pattern=r"^happyword_pr_\d+_e2e$",
        older_than_days=14,
        dry_run=False,
        drop_empty=True,
        drop_collections_on_drop_error=True,
        age_resolver=fake_age,
    )

    assert candidates == ["happyword_pr_30_e2e"]
    assert dropped == ["happyword_pr_30_e2e"]
    stale_db.list_collection_names.assert_awaited_once()
    stale_db.drop_collection.assert_any_await("words")
    stale_db.drop_collection.assert_any_await("word_packs")


@pytest.mark.asyncio
async def test_unsafe_pattern_raises() -> None:
    """`drop_stale` raises `UnsafePattern` for unsafe regex inputs."""
    client = MagicMock()
    with pytest.raises(UnsafePattern):
        await drop_stale(
            client,
            pattern=r".*",
            older_than_days=1,
            dry_run=True,
            age_resolver=AsyncMock(),
        )
