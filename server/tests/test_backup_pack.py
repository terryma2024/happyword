"""V0.5.7 — backup_pack script.

Behaviour contracts:
- Returns a path under `dist/`, file exists, contains pointer + every WordPack.
- Two consecutive runs produce two distinct files (timestamp suffix).
- Empty DB still produces a valid file with `pointer: null` and `packs: []`.
"""

import asyncio
import json
from datetime import UTC, datetime
from pathlib import Path

import pytest

from app.models.user import User, UserRole
from app.models.word import Word
from app.services.auth_service import hash_password
from app.services.pack_service import publish_pack


@pytest.mark.asyncio
async def test_backup_pack_writes_file_with_pointer_and_packs(db: object, tmp_path: Path) -> None:
    from scripts.backup_pack import backup_to_disk  # noqa: PLC0415

    now = datetime.now(tz=UTC)
    await User(
        username="admin-backup",
        password_hash=hash_password("pw"),
        role=UserRole.ADMIN,
        created_at=now,
    ).insert()
    await Word(
        id="fruit-apple",
        word="apple",
        meaningZh="苹果",
        category="fruit",
        difficulty=1,
        created_at=now,
        updated_at=now,
    ).insert()
    await publish_pack(published_by="admin-backup")

    out_path = await backup_to_disk(out_dir=tmp_path)
    assert out_path.exists()
    assert out_path.parent == tmp_path
    body = json.loads(out_path.read_text(encoding="utf-8"))
    assert body["pointer"] is not None
    assert body["pointer"]["current_version"] == 1
    assert len(body["packs"]) == 1
    assert body["packs"][0]["version"] == 1
    assert body["packs"][0]["words"][0]["id"] == "fruit-apple"


@pytest.mark.asyncio
async def test_backup_pack_two_runs_produce_distinct_files(db: object, tmp_path: Path) -> None:
    from scripts.backup_pack import backup_to_disk  # noqa: PLC0415

    a = await backup_to_disk(out_dir=tmp_path)
    # 1.1 s sleep would slow the suite; the timestamp template is
    # microsecond-precise so back-to-back invocations get unique names.
    await asyncio.sleep(0.005)
    b = await backup_to_disk(out_dir=tmp_path)
    assert a != b
    assert a.exists() and b.exists()


@pytest.mark.asyncio
async def test_backup_pack_handles_empty_db(db: object, tmp_path: Path) -> None:
    from scripts.backup_pack import backup_to_disk  # noqa: PLC0415

    out_path = await backup_to_disk(out_dir=tmp_path)
    body = json.loads(out_path.read_text(encoding="utf-8"))
    assert body["pointer"] is None
    assert body["packs"] == []
