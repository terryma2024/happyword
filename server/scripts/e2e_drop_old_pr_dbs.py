"""Drops Atlas DBs whose name matches a regex AND are older than N days.

Usage::

    uv run python scripts/e2e_drop_old_pr_dbs.py \\
        --pattern '^happyword_pr_\\d+_e2e$' \\
        --older-than-days 14 \\
        --drop-empty \\
        --drop-collections-on-drop-error \\
        --exclude happyword_pr_61_e2e \\
        [--dry-run]

Safety:
- The regex MUST end with `_e2e$`, `_test$`, or `_ci$`. Refuses otherwise.
- DB age = max `_id.getTimestamp()` across the DB's collections.
- Empty matching DBs are kept by default. Pass `--drop-empty` when running
  cleanup in CI before E2E reset; failed preview startups can leave empty
  per-PR DBs that still consume Atlas collection quota.
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
from pymongo.errors import PyMongoError

if TYPE_CHECKING:
    from collections.abc import Awaitable, Callable, Iterable

_SAFE_SUFFIX_RE = re.compile(r"_(e2e|test|ci)\$$")


class UnsafePattern(RuntimeError):
    """Raised when the regex doesn't end with `_e2e$`, `_test$`, or `_ci$`."""


def _matches_safe_pattern(pattern: str) -> bool:
    return bool(_SAFE_SUFFIX_RE.search(pattern))


def _list_candidate_dbs(all_names: list[str], pattern: str) -> list[str]:
    rx = re.compile(pattern)
    return [n for n in all_names if rx.match(n)]


async def _db_age(client: object, name: str) -> datetime | None:
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
    return latest


async def _drop_all_collections(client: object, name: str) -> int:
    """Drop every collection in one DB, returning how many were dropped."""
    db = client[name]  # type: ignore[index]
    collection_names = await db.list_collection_names()
    for coll in collection_names:
        await db.drop_collection(coll)
    return len(collection_names)


async def drop_stale(
    client: object,  # AsyncIOMotorClient OR test mock — duck-typed
    *,
    pattern: str,
    older_than_days: int,
    dry_run: bool,
    drop_empty: bool = False,
    exclude_names: Iterable[str] = (),
    drop_collections_on_drop_error: bool = False,
    ignore_drop_errors: bool = False,
    ignored_drop_errors: list[str] | None = None,
    age_resolver: Callable[[object, str], Awaitable[datetime | None]] = _db_age,
) -> tuple[list[str], list[str]]:
    """Returns (dropped, candidates). `dropped` is empty when `dry_run`."""
    if not _matches_safe_pattern(pattern):
        raise UnsafePattern(
            f"Pattern {pattern!r} must end with _e2e$, _test$, or _ci$.",
        )
    all_names = await client.list_database_names()  # type: ignore[attr-defined]
    candidates = _list_candidate_dbs(all_names, pattern)
    cutoff = datetime.now(tz=UTC) - timedelta(days=older_than_days)
    excluded = {name for name in exclude_names if name}
    dropped: list[str] = []
    for name in candidates:
        if name in excluded:
            continue
        age = await age_resolver(client, name)
        should_drop = (age is None and drop_empty) or (
            age is not None and age < cutoff
        )
        if should_drop and not dry_run:
            try:
                await client.drop_database(name)  # type: ignore[attr-defined]
            except PyMongoError as exc:
                if drop_collections_on_drop_error:
                    try:
                        dropped_count = await _drop_all_collections(client, name)
                    except PyMongoError as coll_exc:
                        if not ignore_drop_errors:
                            raise
                        if ignored_drop_errors is not None:
                            ignored_drop_errors.append(
                                f"{name}: dropDatabase failed: {exc}; "
                                f"dropCollection failed: {coll_exc}"
                            )
                        continue
                    if dropped_count > 0:
                        dropped.append(name)
                    continue
                if not ignore_drop_errors:
                    raise
                if ignored_drop_errors is not None:
                    ignored_drop_errors.append(f"{name}: {exc}")
                continue
            else:
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
    parser.add_argument(
        "--drop-empty",
        action="store_true",
        help="Drop matching DBs with no ObjectId documents.",
    )
    parser.add_argument(
        "--exclude",
        dest="exclude_names",
        action="append",
        default=[],
        help="DB name to protect from dropping; may be passed multiple times.",
    )
    parser.add_argument(
        "--drop-collections-on-drop-error",
        action="store_true",
        help="If dropDatabase is denied, drop every collection in the stale DB.",
    )
    parser.add_argument(
        "--ignore-drop-errors",
        action="store_true",
        help="Continue when a matching stale DB cannot be dropped.",
    )
    args = parser.parse_args(argv)

    uri = os.environ.get("E2E_MONGODB_URI", "").strip()
    if not uri:
        print("E2E_MONGODB_URI must be set.", file=sys.stderr)
        return 2

    client: AsyncIOMotorClient[dict[str, object]] = AsyncIOMotorClient(uri)
    try:
        try:
            ignored_drop_errors: list[str] = []
            dropped, candidates = await drop_stale(
                client,
                pattern=args.pattern,
                older_than_days=args.older_than_days,
                dry_run=args.dry_run,
                drop_empty=args.drop_empty,
                exclude_names=args.exclude_names,
                drop_collections_on_drop_error=args.drop_collections_on_drop_error,
                ignore_drop_errors=args.ignore_drop_errors,
                ignored_drop_errors=ignored_drop_errors,
            )
        except UnsafePattern as exc:
            print(f"Refusing: {exc}", file=sys.stderr)
            return 3

        print(f"Candidates ({len(candidates)}): {candidates}")
        print(f"Dropped     ({len(dropped)}): {dropped}")
        if ignored_drop_errors:
            print(
                f"Ignored drop errors ({len(ignored_drop_errors)}): "
                f"{ignored_drop_errors}"
            )
        if args.dry_run and candidates:
            print("(dry-run: nothing dropped)")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_amain(sys.argv[1:])))
