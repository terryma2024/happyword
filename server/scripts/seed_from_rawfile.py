"""Idempotently seed `words` collection from the client's rawfile JSON.

The client ships ``entry/src/main/resources/rawfile/data/words_v1.json``
as the cold-start fallback. From V0.5.2 onwards the live source of truth
is MongoDB. This script copies the rawfile rows into the DB so admins
have something to edit before they start adding new words.

**Idempotent**: rows with an existing ``id`` are left untouched. Admin
edits made post-V0.5.2 always win — the script never overwrites.

Local usage (against running Mongo with `MONGODB_URI` set):

    cd server
    uv run python scripts/seed_from_rawfile.py

For CI / tests we expose ``seed_words_from_rawfile`` as a coroutine
(returns ``(inserted, skipped)``) callable from a pytest fixture once
Beanie is initialized.
"""

from __future__ import annotations

import asyncio
import json
import sys
from datetime import UTC, datetime
from pathlib import Path

from beanie import init_beanie
from motor.motor_asyncio import AsyncIOMotorClient

from app.config import get_settings
from app.models.user import User
from app.models.word import Word

# Path is resolved relative to repo root so the script works whether you
# call it from `server/` or via `uv run python -m scripts.seed_from_rawfile`.
_RAWFILE_RELATIVE = Path("entry/src/main/resources/rawfile/data/words_v1.json")


def _resolve_rawfile_path() -> Path:
    """Walk up from `__file__` until we find a parent that contains the rawfile."""
    here = Path(__file__).resolve()
    for ancestor in [here.parent, *here.parents]:
        candidate = ancestor / _RAWFILE_RELATIVE
        if candidate.exists():
            return candidate
    raise FileNotFoundError(
        f"Could not locate {_RAWFILE_RELATIVE} above {here}. "
        "Run the script from inside the happyword repo."
    )


async def seed_words_from_rawfile(*, rawfile_path: Path | None = None) -> tuple[int, int]:
    """Insert any rawfile word that doesn't already exist by id. Returns
    ``(inserted, skipped)``.
    """
    path = rawfile_path or _resolve_rawfile_path()
    payload = json.loads(path.read_text(encoding="utf-8"))
    raw_words: list[dict[str, object]] = payload.get("words", [])

    existing_ids = {w.id async for w in Word.find_all()}
    now = datetime.now(tz=UTC)
    inserted = 0
    skipped = 0
    for entry in raw_words:
        wid = str(entry["id"])
        if wid in existing_ids:
            skipped += 1
            continue
        await Word(
            id=wid,
            word=str(entry["word"]),
            meaningZh=str(entry["meaningZh"]),
            category=str(entry["category"]),
            difficulty=int(entry["difficulty"]),
            created_at=now,
            updated_at=now,
        ).insert()
        inserted += 1
    return inserted, skipped


async def _main() -> None:
    settings = get_settings()
    client: AsyncIOMotorClient[dict[str, object]] = AsyncIOMotorClient(settings.mongo_uri)
    try:
        await init_beanie(
            database=client[settings.mongo_db_name],
            document_models=[User, Word],
        )
        inserted, skipped = await seed_words_from_rawfile()
        print(f"seed-from-rawfile: inserted={inserted} skipped={skipped}")
    finally:
        client.close()


if __name__ == "__main__":  # pragma: no cover - manual ops entry
    try:
        asyncio.run(_main())
    except KeyboardInterrupt:
        sys.exit(130)
