"""V0.8.8 — Idempotent cloud sync for daily check-ins and coin txns."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import TYPE_CHECKING, Any

from beanie.odm.enums import SortDirection

from app.models.child_checkin import ChildCheckIn
from app.models.cloud_coin_txn import CloudCoinTxn
from app.schemas.checkins import CloudCoinTxnIn, CloudCoinTxnOut

if TYPE_CHECKING:
    from collections.abc import Sequence


def _now_ms() -> int:
    return int(datetime.now(tz=UTC).timestamp() * 1000)


@dataclass
class CheckInSyncResult:
    checked_day_keys: list[str] = field(default_factory=list)
    weekly_bonus_day_keys: list[str] = field(default_factory=list)
    coin_txns: list[CloudCoinTxnOut] = field(default_factory=list)
    server_now_ms: int = 0


def _coin_to_out(row: CloudCoinTxn) -> CloudCoinTxnOut:
    return CloudCoinTxnOut(
        txn_id=row.txn_id,
        ts=row.ts,
        delta=row.delta,
        reason=row.reason,
        balance_after=row.balance_after,
        updated_at=row.updated_at,
    )


async def sync(
    *,
    child_profile_id: str,
    checked_day_keys: Sequence[str],
    weekly_bonus_day_keys: Sequence[str],
    coin_txns: Sequence[CloudCoinTxnIn],
    requesting_device_id: str,
) -> CheckInSyncResult:
    now = datetime.now(tz=UTC)
    _ = weekly_bonus_day_keys
    unique_days = sorted(set(checked_day_keys))
    if unique_days:
        checkin_collection = ChildCheckIn.get_motor_collection()
        await asyncio.gather(
            *(
                checkin_collection.update_one(
                    {"child_profile_id": child_profile_id, "day_key": day_key},
                    {
                        "$set": {
                            "source_device_id": requesting_device_id,
                            "updated_at": now,
                        }
                    },
                    upsert=True,
                )
                for day_key in unique_days
            )
        )

    unique_txns: dict[str, CloudCoinTxnIn] = {}
    for txn in coin_txns:
        unique_txns[txn.txn_id] = txn
    if unique_txns:
        txn_collection = CloudCoinTxn.get_motor_collection()
        await asyncio.gather(
            *(
                txn_collection.update_one(
                    {"child_profile_id": child_profile_id, "txn_id": txn_id},
                    {"$setOnInsert": _txn_insert_payload(txn, requesting_device_id, now)},
                    upsert=True,
                )
                for txn_id, txn in unique_txns.items()
            )
        )

    return await list_all(child_profile_id=child_profile_id)


async def list_all(*, child_profile_id: str) -> CheckInSyncResult:
    rows = await ChildCheckIn.find(
        ChildCheckIn.child_profile_id == child_profile_id,
        sort=[("day_key", SortDirection.ASCENDING)],
    ).to_list()
    txns = await CloudCoinTxn.find(
        CloudCoinTxn.child_profile_id == child_profile_id,
        sort=[("ts", SortDirection.ASCENDING), ("txn_id", SortDirection.ASCENDING)],
    ).to_list()
    txn_out = [_coin_to_out(row) for row in txns]
    weekly_days = sorted(
        {
            row.reason.removeprefix("checkin-weekly-bonus:")
            for row in txns
            if row.reason.startswith("checkin-weekly-bonus:")
        }
    )
    return CheckInSyncResult(
        checked_day_keys=[row.day_key for row in rows],
        weekly_bonus_day_keys=weekly_days,
        coin_txns=txn_out,
        server_now_ms=_now_ms(),
    )


def _txn_insert_payload(
    txn: CloudCoinTxnIn, device_id: str, now: datetime
) -> dict[str, Any]:
    return {
        "ts": txn.ts,
        "delta": txn.delta,
        "reason": txn.reason,
        "balance_after": txn.balance_after,
        "source_device_id": device_id,
        "updated_at": now,
    }
