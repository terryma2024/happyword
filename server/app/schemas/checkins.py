"""V0.8.8 — Wire schemas for child check-in / coin sync."""

from __future__ import annotations

from datetime import datetime  # noqa: TC003 - pydantic needs runtime type
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field

DayKey = Annotated[str, Field(pattern=r"^\d{4}-\d{2}-\d{2}$")]


class CloudCoinTxnIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    txn_id: Annotated[str, Field(min_length=1, max_length=128)]
    ts: Annotated[int, Field(ge=0)]
    delta: int
    reason: Annotated[str, Field(min_length=1, max_length=128)]
    balance_after: int


class CheckInSyncIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    checked_day_keys: list[DayKey] = Field(default_factory=list)
    weekly_bonus_day_keys: list[DayKey] = Field(default_factory=list)
    coin_txns: list[CloudCoinTxnIn] = Field(default_factory=list)
    synced_through_ms: Annotated[int, Field(ge=0)] = 0


class CloudCoinTxnOut(BaseModel):
    txn_id: str
    ts: int
    delta: int
    reason: str
    balance_after: int
    updated_at: datetime


class CheckInSyncOut(BaseModel):
    checked_day_keys: list[str]
    weekly_bonus_day_keys: list[str]
    coin_txns: list[CloudCoinTxnOut]
    server_now_ms: int


class CheckInListOut(CheckInSyncOut):
    pass
