"""V0.6.4 — LWW sync engine for cloud-stored learning records.

The sync algorithm (spec §7.4):

  for each incoming item:
      row = SyncedWordStat.find_one({child_profile_id, word_id})
      if row is None:
          insert with item fields
          accepted += word_id
      elif item.last_answered_ms > row.last_answered_ms:
          overwrite all 9 numeric fields + memory_state from item
          accepted += word_id
      elif item.last_answered_ms < row.last_answered_ms:
          rejected += word_id
          server_pulls += row.snapshot()
      else:
          # equal → idempotent no-op (treat as accepted to keep LWW stable)
          accepted += word_id
  server_pulls += rows updated since synced_through_ms not in incoming list

The service never raises on unexpected payloads — invalid items are
filtered upstream by Pydantic. Family-mismatch checks live in the
router which knows the device binding's family scope.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import TYPE_CHECKING

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


def _apply(row: SyncedWordStat, item: WordStatItem, device_id: str) -> None:
    row.seen_count = item.seen_count
    row.correct_count = item.correct_count
    row.wrong_count = item.wrong_count
    row.last_answered_ms = item.last_answered_ms
    row.last_correct_ms = item.last_correct_ms
    row.next_review_ms = item.next_review_ms
    row.memory_state = item.memory_state
    row.consecutive_correct = item.consecutive_correct
    row.consecutive_wrong = item.consecutive_wrong
    row.mastery = item.mastery
    row.last_synced_from_device_id = device_id
    row.updated_at = datetime.now(tz=UTC)


async def sync(
    *,
    child_profile_id: str,
    items: Sequence[WordStatItem],
    requesting_device_id: str,
    synced_through_ms: int = 0,
) -> SyncResult:
    result = SyncResult(server_now_ms=_now_ms())
    incoming_ids: set[str] = set()

    for item in items:
        incoming_ids.add(item.word_id)
        row = await SyncedWordStat.find_one(
            SyncedWordStat.child_profile_id == child_profile_id,
            SyncedWordStat.word_id == item.word_id,
        )
        if row is None:
            row = SyncedWordStat(
                child_profile_id=child_profile_id,
                word_id=item.word_id,
                updated_at=datetime.now(tz=UTC),
            )
            _apply(row, item, requesting_device_id)
            await row.insert()
            result.accepted.append(item.word_id)
            continue
        if item.last_answered_ms > row.last_answered_ms:
            _apply(row, item, requesting_device_id)
            await row.save()
            result.accepted.append(item.word_id)
        elif item.last_answered_ms < row.last_answered_ms:
            result.rejected.append(item.word_id)
            result.server_pulls.append(_row_to_pull(row))
        else:
            # Equal timestamps → idempotent. Treat as accepted so the
            # client can clear its dirty flag, but skip the DB write.
            result.accepted.append(item.word_id)

    if synced_through_ms > 0:
        # Pull server-newer rows the client doesn't know about.
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
