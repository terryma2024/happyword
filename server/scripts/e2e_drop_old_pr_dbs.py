"""Drops Atlas DBs whose name matches a regex AND are older than N days.

Usage::

    uv run python scripts/e2e_drop_old_pr_dbs.py \\
        --pattern '^happyword_pr_\\d+_e2e$' \\
        --older-than-days 14 \\
        [--dry-run]

Safety:
- The regex MUST end with `_e2e$`, `_test$`, or `_ci$`. Refuses otherwise.
- DB age = max `_id.getTimestamp()` across the DB's collections; falls
  back to "now" when a DB has no documents (so empty DBs are never
  accidentally dropped on first run).
"""

from __future__ import annotations

import argparse
import asyncio
import os
import re
import sys
from datetime import UTC, datetime, timedelta
from typing import TYPE_CHECKING

from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorClient

if TYPE_CHECKING:
    from collections.abc import Awaitable, Callable

_SAFE_SUFFIX_RE = re.compile(r"_(e2e|test|ci)\$$")


class UnsafePattern(RuntimeError):
    """Raised when the regex doesn't end with `_e2e$`, `_test$`, or `_ci$`."""


def _matches_safe_pattern(pattern: str) -> bool:
    return bool(_SAFE_SUFFIX_RE.search(pattern))


def _list_candidate_dbs(all_names: list[str], pattern: str) -> list[str]:
    rx = re.compile(pattern)
    return [n for n in all_names if rx.match(n)]


async def _db_age(client: object, name: str) -> datetime:
    """Estimate DB age via the newest `_id` ObjectId across collections."""
    db = client[name]  # type: ignore[index]
    latest: datetime | None = None
    for coll in await db.list_collection_names():
        doc = await db[coll].find_one(sort=[("_id", -1)], projection={"_id": 1})
        if doc is None:
            continue
        oid = doc["_id"]
        if isinstance(oid, ObjectId):
            ts = oid.generation_time.astimezone(UTC)
            if latest is None or ts > latest:
                latest = ts
    return latest or datetime.now(tz=UTC)


async def drop_stale(
    client: object,  # AsyncIOMotorClient OR test mock — duck-typed
    *,
    pattern: str,
    older_than_days: int,
    dry_run: bool,
    age_resolver: Callable[[object, str], Awaitable[datetime]] = _db_age,
) -> tuple[list[str], list[str]]:
    """Returns (dropped, candidates). `dropped` is empty when `dry_run`."""
    if not _matches_safe_pattern(pattern):
        raise UnsafePattern(
            f"Pattern {pattern!r} must end with _e2e$, _test$, or _ci$.",
        )
    all_names = await client.list_database_names()  # type: ignore[attr-defined]
    candidates = _list_candidate_dbs(all_names, pattern)
    cutoff = datetime.now(tz=UTC) - timedelta(days=older_than_days)
    dropped: list[str] = []
    for name in candidates:
        age = await age_resolver(client, name)
        if age < cutoff and not dry_run:
            await client.drop_database(name)  # type: ignore[attr-defined]
            dropped.append(name)
    return dropped, candidates


async def _amain(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--pattern",
        required=True,
        help="DB-name regex (must end in _e2e$ / _test$ / _ci$).",
    )
    parser.add_argument("--older-than-days", type=int, required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    uri = os.environ.get("E2E_MONGODB_URI", "").strip()
    if not uri:
        print("E2E_MONGODB_URI must be set.", file=sys.stderr)
        return 2

    client: AsyncIOMotorClient[dict[str, object]] = AsyncIOMotorClient(uri)
    try:
        try:
            dropped, candidates = await drop_stale(
                client,
                pattern=args.pattern,
                older_than_days=args.older_than_days,
                dry_run=args.dry_run,
            )
        except UnsafePattern as exc:
            print(f"Refusing: {exc}", file=sys.stderr)
            return 3

        print(f"Candidates ({len(candidates)}): {candidates}")
        print(f"Dropped     ({len(dropped)}): {dropped}")
        if args.dry_run and candidates:
            print("(dry-run: nothing dropped)")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_amain(sys.argv[1:])))
