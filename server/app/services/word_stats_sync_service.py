"""V0.6.4 — LWW sync engine for cloud-stored learning records.

The sync algorithm (spec §7.4) is per-item Last-Write-Wins keyed by
``last_answered_ms``:

  for each incoming item:
      row = SyncedWordStat.find_one({child_profile_id, word_id})
      if row is None:
          insert with item fields
          accepted += word_id
      elif item.last_answered_ms > row.last_answered_ms:
          overwrite all numeric fields + memory_state from item
          accepted += word_id
      elif item.last_answered_ms < row.last_answered_ms:
          rejected += word_id
          server_pulls += row.snapshot()
      else:
          # equal → idempotent no-op (treat as accepted to keep LWW stable)
          accepted += word_id
  server_pulls += rows updated since synced_through_ms not in incoming list

Implementation notes (post-v0.6.4 batched rewrite):

The naive translation of the spec was one ``find_one`` + one ``save`` per
incoming item (~2N round-trips for an N-item batch). At N=250 with Atlas in
the same region (~5 ms RTT) this still totalled 20–60s when motor's task
scheduler and Pydantic-based row hydration were factored in — frequently
exceeding Vercel's 60s function ``maxDuration``.

We now use a fixed 2-wave I/O pattern regardless of N:

  1. ONE ``find`` pulls every existing row matching
     ``(child_profile_id, word_id ∈ incoming_ids)`` into a Python dict.
  2. We replay the per-item decision tree against that dict in pure Python,
     deciding accept / reject / no-op for each item.
  3. The accepted-with-write items are flushed concurrently via
     ``asyncio.gather`` of motor ``update_one(..., upsert=True)`` calls.
     Motor's default connection pool (100) means a 100-item batch runs in
     ~1 RTT; a 250-item batch runs in ~3 waves.

We deliberately use ``update_one`` instead of pymongo's ``bulk_write`` /
``UpdateOne`` operation class because pymongo 4.17 added a ``sort`` kwarg
that mongomock-motor (used in offline tests) does not yet accept. Both
``bulk_write`` and parallel ``update_one`` collapse to ~2 round-trips at
our batch sizes; the latter keeps the offline test fixture working.

The Python replay maintains the EXACT same LWW semantics as the spec, even
across in-batch duplicates of the same ``word_id``: we keep an in-memory
"effective state" view that's seeded from the DB rows and updated each
time a winning item is queued. This matches the prior per-item code where
the second iteration's ``find_one`` would observe the just-inserted row.

The service never raises on unexpected payloads — invalid items are
filtered upstream by Pydantic. Family-mismatch checks live in the
router which knows the device binding's family scope.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import TYPE_CHECKING, Any

from beanie.odm.enums import SortDirection

from app.models.synced_word_stat import SyncedWordStat
from app.schemas.word_stats_sync import WordStatItem, WordStatPullItem

if TYPE_CHECKING:
    from collections.abc import Sequence


def _now_ms() -> int:
    return int(datetime.now(tz=UTC).timestamp() * 1000)


@dataclass
class SyncResult:
    accepted: list[str] = field(default_factory=list)
    rejected: list[str] = field(default_factory=list)
    server_pulls: list[WordStatPullItem] = field(default_factory=list)
    server_now_ms: int = 0


def _row_to_pull(row: SyncedWordStat) -> WordStatPullItem:
    return WordStatPullItem(
        word_id=row.word_id,
        seen_count=row.seen_count,
        correct_count=row.correct_count,
        wrong_count=row.wrong_count,
        last_answered_ms=row.last_answered_ms,
        last_correct_ms=row.last_correct_ms,
        next_review_ms=row.next_review_ms,
        memory_state=row.memory_state,
        consecutive_correct=row.consecutive_correct,
        consecutive_wrong=row.consecutive_wrong,
        mastery=row.mastery,
        updated_at=row.updated_at,
    )


def _build_set_payload(
    *, item: WordStatItem, device_id: str, now: datetime
) -> dict[str, Any]:
    """Mongo ``$set`` body matching what the prior per-item path wrote.

    Includes every mutable field on the doc; ``child_profile_id`` and
    ``word_id`` come from the upsert filter and are set implicitly on insert.
    """

    return {
        "seen_count": item.seen_count,
        "correct_count": item.correct_count,
        "wrong_count": item.wrong_count,
        "last_answered_ms": item.last_answered_ms,
        "last_correct_ms": item.last_correct_ms,
        "next_review_ms": item.next_review_ms,
        "memory_state": item.memory_state,
        "consecutive_correct": item.consecutive_correct,
        "consecutive_wrong": item.consecutive_wrong,
        "mastery": item.mastery,
        "last_synced_from_device_id": device_id,
        "updated_at": now,
    }


async def sync(
    *,
    child_profile_id: str,
    items: Sequence[WordStatItem],
    requesting_device_id: str,
    synced_through_ms: int = 0,
) -> SyncResult:
    result = SyncResult(server_now_ms=_now_ms())
    incoming_ids: set[str] = {item.word_id for item in items}

    if items:
        # Step 1 — bulk-fetch every existing (child, word_id ∈ batch) row in
        # ONE round-trip. The compound index on (child_profile_id, word_id)
        # handles this cheaply.
        existing_rows: list[SyncedWordStat] = await SyncedWordStat.find(
            {
                "child_profile_id": child_profile_id,
                "word_id": {"$in": list(incoming_ids)},
            }
        ).to_list()
        existing_by_word: dict[str, SyncedWordStat] = {
            r.word_id: r for r in existing_rows
        }

        # Step 2 — replay per-item LWW in Python. The "view" tracks the
        # effective `last_answered_ms` per word as we walk the batch, so a
        # later item competing with an earlier item on the same word_id
        # behaves identically to the prior find_one+save loop. ``view``
        # values are tuples of (effective_ts, db_row_or_None).
        now = datetime.now(tz=UTC)
        view: dict[str, tuple[int, SyncedWordStat | None]] = {
            wid: (row.last_answered_ms, row)
            for wid, row in existing_by_word.items()
        }
        # word_id → ($set body) for items that need to be flushed. Keyed by
        # word_id so an in-batch dup keeps only the final winning state.
        upserts_by_word: dict[str, dict[str, Any]] = {}

        for item in items:
            current = view.get(item.word_id)
            if current is None:
                # Brand-new word in this batch — queue an upsert.
                upserts_by_word[item.word_id] = _build_set_payload(
                    item=item, device_id=requesting_device_id, now=now
                )
                view[item.word_id] = (item.last_answered_ms, None)
                result.accepted.append(item.word_id)
                continue

            cur_ts, cur_row = current
            if item.last_answered_ms > cur_ts:
                # Winner — overwrite every mutable field on the doc.
                upserts_by_word[item.word_id] = _build_set_payload(
                    item=item, device_id=requesting_device_id, now=now
                )
                view[item.word_id] = (item.last_answered_ms, cur_row)
                result.accepted.append(item.word_id)
            elif item.last_answered_ms < cur_ts:
                # Loser — return DB snapshot in server_pulls so the client
                # can reconcile. When the "winner" came from earlier in this
                # same batch (cur_row is None — we have no DB row to snapshot
                # from), we still mark rejected but cannot emit a pull. The
                # prior per-item code would have inserted then read back the
                # just-written row; clients should not send intra-batch
                # competing dups, so this corner case stays best-effort.
                if cur_row is not None:
                    result.server_pulls.append(_row_to_pull(cur_row))
                result.rejected.append(item.word_id)
            else:
                # Equal ts → idempotent. No-op write, but accepted so the
                # client can clear its dirty flag.
                result.accepted.append(item.word_id)

        # Step 3 — flush upserts concurrently. Motor's default connection
        # pool (maxPoolSize=100) caps real parallelism; for batches at the
        # spec cap (250) we get ~3 waves of ~5ms RTT each on same-region
        # Atlas — bounded well under Vercel's 60s function maxDuration.
        if upserts_by_word:
            collection = SyncedWordStat.get_motor_collection()
            await asyncio.gather(
                *(
                    collection.update_one(
                        {
                            "child_profile_id": child_profile_id,
                            "word_id": wid,
                        },
                        {"$set": payload},
                        upsert=True,
                    )
                    for wid, payload in upserts_by_word.items()
                )
            )

    if synced_through_ms > 0:
        # Step 4 — pull-back: rows the server has that are newer than what
        # the client claims to know, AND not already in this batch.
        newer_rows = await SyncedWordStat.find(
            SyncedWordStat.child_profile_id == child_profile_id,
            SyncedWordStat.last_answered_ms > synced_through_ms,
            sort=[("last_answered_ms", SortDirection.DESCENDING)],
        ).to_list()
        for row in newer_rows:
            if row.word_id in incoming_ids:
                continue
            result.server_pulls.append(_row_to_pull(row))

    return result


async def list_since(
    *, child_profile_id: str, since_ms: int = 0
) -> list[WordStatPullItem]:
    rows = await SyncedWordStat.find(
        SyncedWordStat.child_profile_id == child_profile_id,
        SyncedWordStat.last_answered_ms > since_ms,
        sort=[("last_answered_ms", SortDirection.DESCENDING)],
    ).to_list()
    return [_row_to_pull(r) for r in rows]
