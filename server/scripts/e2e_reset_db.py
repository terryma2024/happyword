"""Standalone DB-reset script for the E2E test target.

Truncates every dynamic collection so each CI E2E run starts from a
known-clean state. Refuses to operate on anything that doesn't look
like a dedicated E2E database (name must end in ``_e2e`` / ``_test`` /
``_ci`` and must not contain ``prod``).

What is NOT truncated and why:

- ``users`` — holds the bootstrap admin row created by FastAPI startup
  from ``ADMIN_BOOTSTRAP_USER`` / ``ADMIN_BOOTSTRAP_PASS``. Wiping it
  would leave the deployed server with no admin and break the next
  ``E2E_ADMIN_USER`` login. Parent rows accumulate here too, but every
  test namespaces its parent email by ``run_id`` so they cannot
  collide; periodic manual cleanup is fine.
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
import os
import sys

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


class UnsafeDatabaseName(RuntimeError):
    """Raised when the target DB name does not look like a dedicated test DB."""


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


async def reset(uri: str, name: str) -> int:
    client: AsyncIOMotorClient[dict[str, object]] = AsyncIOMotorClient(uri)
    try:
        db = client[name]
        for coll in COLLECTIONS:
            await db[coll].delete_many({})
        return len(COLLECTIONS)
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

    truncated = await reset(uri, name)
    print(f"Reset {truncated} collections in db {name!r}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_amain()))
