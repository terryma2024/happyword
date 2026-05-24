"""Standalone DB-reset script for the E2E test target.

Truncates every dynamic collection so each CI E2E run starts from a
known-clean state. Refuses to operate on anything that doesn't look
like a dedicated E2E database (name must end in ``_e2e`` / ``_test`` /
``_ci`` and must not contain ``prod``).

What is NOT truncated and why:

- ``users`` — holds the bootstrap admin row plus parent rows. Parent rows
  accumulate here, but every test namespaces its parent email by ``run_id`` so
  they cannot collide; periodic manual cleanup is fine. When
  ``E2E_ADMIN_USER`` / ``E2E_ADMIN_PASS`` are present, reset upserts that admin
  row so the already-running deployment does not need a restart to refresh
  bootstrap credentials.
- ``categories`` — holds the 5 idempotent ``seed_manual_categories``
  rows seeded at startup. Re-seeding only happens at startup, so wiping
  these would break ACAT-1 against an already-running deployment.

Usage::

    cd server
    E2E_MONGODB_URI="mongodb+srv://..." \
    E2E_MONGO_DB_NAME="happyword_e2e" \
    uv run python scripts/e2e_reset_db.py

The script is intentionally self-contained (no ``app`` or ``tests``
imports) so it can run before the test process is even built.
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

import bcrypt
from motor.motor_asyncio import AsyncIOMotorClient

# Mirror Beanie ``Settings.name`` values from ``app/models/*``. Keep in sync
# when models are added/renamed. The collection names below are the actual
# Mongo names, NOT the model class names — e.g. ``audit_log`` is singular
# and ``pack_pointer`` is singular even though the rest are plural.
COLLECTIONS: tuple[str, ...] = (
    "audit_log",
    "child_profiles",
    "cloud_wishlist_items",
    "device_bindings",
    "email_verifications",
    "families",
    "family_pack_definitions",
    "family_pack_drafts",
    "family_pack_pointers",
    "family_word_packs",
    "lesson_import_drafts",
    "llm_drafts",
    "pack_pointer",
    "pair_tokens",
    "parent_inbox_msgs",
    "redemption_requests",
    "synced_word_stats",
    "words",
    "word_packs",
)

_SAFE_SUFFIXES = ("_e2e", "_test", "_ci")
_RAWFILE_CANDIDATES: tuple[Path, ...] = (
    Path("harmonyos/entry/src/main/resources/rawfile/data/words_v1.json"),
    Path("entry/src/main/resources/rawfile/data/words_v1.json"),
)


class UnsafeDatabaseName(RuntimeError):
    """Raised when the target DB name does not look like a dedicated test DB."""


@dataclass(frozen=True)
class ResetSummary:
    truncated_collections: int
    seeded_words_inserted: int
    seeded_words_skipped: int
    admin_upserted: bool


def assert_safe_db_name(name: str) -> None:
    lowered = name.lower()
    if "prod" in lowered:
        raise UnsafeDatabaseName(
            f"Refusing to operate on DB containing 'prod': {name!r}"
        )
    if not any(lowered.endswith(suf) for suf in _SAFE_SUFFIXES):
        raise UnsafeDatabaseName(
            f"E2E_MONGO_DB_NAME must end with one of {_SAFE_SUFFIXES}, got {name!r}"
        )


def _resolve_rawfile_path() -> Path:
    here = Path(__file__).resolve()
    for ancestor in [here.parent, *here.parents]:
        for rel in _RAWFILE_CANDIDATES:
            candidate = ancestor / rel
            if candidate.exists():
                return candidate
    raise FileNotFoundError(
        f"Could not locate any of {', '.join(str(p) for p in _RAWFILE_CANDIDATES)} "
        f"above {here}."
    )


def _rawfile_word_docs(rawfile_path: Path, now: datetime) -> list[dict[str, object]]:
    payload = json.loads(rawfile_path.read_text(encoding="utf-8"))
    raw_words = payload.get("words", [])
    if not isinstance(raw_words, list):
        raise ValueError(f"{rawfile_path} has no list field 'words'")

    docs: list[dict[str, object]] = []
    for entry in raw_words:
        if not isinstance(entry, dict):
            continue
        wid = str(entry["id"])
        docs.append(
            {
                "_id": wid,
                "word": str(entry["word"]),
                "meaningZh": str(entry["meaningZh"]),
                "category": str(entry["category"]),
                "difficulty": int(entry["difficulty"]),
                "created_at": now,
                "updated_at": now,
                "deleted_at": None,
                "distractors": None,
                "example_sentence_en": None,
                "example_sentence_zh": None,
                "illustration_url": None,
                "audio_url": None,
            }
        )
    return docs


async def seed_words_from_rawfile(
    db: object,
    *,
    rawfile_path: Path | None = None,
) -> tuple[int, int]:
    path = rawfile_path or _resolve_rawfile_path()
    docs = _rawfile_word_docs(path, datetime.now(tz=UTC))
    if not docs:
        return 0, 0

    words = db["words"]  # type: ignore[index]
    existing_ids = {
        row["_id"] async for row in words.find({}, {"_id": 1})  # type: ignore[attr-defined]
    }
    to_insert = [doc for doc in docs if doc["_id"] not in existing_ids]
    if to_insert:
        await words.insert_many(to_insert)  # type: ignore[attr-defined]
    return len(to_insert), len(docs) - len(to_insert)


async def upsert_admin_user(db: object, *, username: str, password: str) -> bool:
    now = datetime.now(tz=UTC)
    password_hash = bcrypt.hashpw(
        password.encode("utf-8"), bcrypt.gensalt()
    ).decode("utf-8")
    result = await db["users"].update_one(  # type: ignore[index, attr-defined]
        {"username": username},
        {
            "$set": {
                "password_hash": password_hash,
                "role": "admin",
            },
            "$setOnInsert": {
                "created_at": now,
            },
        },
        upsert=True,
    )
    return result.matched_count > 0 or result.upserted_id is not None


async def reset(
    uri: str,
    name: str,
    *,
    admin_user: str = "",
    admin_pass: str = "",
) -> ResetSummary:
    client: AsyncIOMotorClient[dict[str, object]] = AsyncIOMotorClient(uri)
    try:
        db = client[name]
        for coll in COLLECTIONS:
            await db[coll].delete_many({})
        inserted, skipped = await seed_words_from_rawfile(db)
        admin_upserted = False
        if admin_user and admin_pass:
            admin_upserted = await upsert_admin_user(
                db, username=admin_user, password=admin_pass
            )
        return ResetSummary(
            truncated_collections=len(COLLECTIONS),
            seeded_words_inserted=inserted,
            seeded_words_skipped=skipped,
            admin_upserted=admin_upserted,
        )
    finally:
        client.close()


async def _amain() -> int:
    uri = os.environ.get("E2E_MONGODB_URI", "").strip()
    name = os.environ.get("E2E_MONGO_DB_NAME", "").strip()
    if not uri or not name:
        print(
            "E2E_MONGODB_URI and E2E_MONGO_DB_NAME must both be set.",
            file=sys.stderr,
        )
        return 2

    try:
        assert_safe_db_name(name)
    except UnsafeDatabaseName as exc:
        print(f"Refusing to reset: {exc}", file=sys.stderr)
        return 3

    summary = await reset(
        uri,
        name,
        admin_user=os.environ.get("E2E_ADMIN_USER", "").strip(),
        admin_pass=os.environ.get("E2E_ADMIN_PASS", "").strip(),
    )
    print(
        f"Reset {summary.truncated_collections} collections in db {name!r}. "
        f"Seeded words from rawfile: inserted={summary.seeded_words_inserted} "
        f"skipped={summary.seeded_words_skipped}. "
        f"Admin upserted: {summary.admin_upserted}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_amain()))
