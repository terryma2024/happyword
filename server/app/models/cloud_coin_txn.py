"""V0.8.8 — Cloud copy of local coin transactions."""

from datetime import datetime
from typing import Annotated

from beanie import Document, Indexed


class CloudCoinTxn(Document):
    child_profile_id: Annotated[str, Indexed()]
    txn_id: Annotated[str, Indexed()]
    ts: int
    delta: int
    reason: str
    balance_after: int
    source_device_id: str | None = None
    updated_at: datetime

    class Settings:
        name = "cloud_coin_txns"
        indexes = [[("child_profile_id", 1), ("txn_id", 1)]]
