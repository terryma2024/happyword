"""V0.6.2 — short-lived pairing tokens issued by the parent web.

The parent visits `/parent/devices/add`; the page calls `POST /api/v1/parent/
pair/create` which produces a `PairToken` row. The QR encodes the token URL
(`{PARENT_WEB_BASE_URL}/p/<token-prefix>`), and the page also surfaces a
6-digit human-readable `short_code` fallback for "I can't scan" flows. The
client posts either `token` or `short_code` to `/api/v1/pair/redeem` along
with its persistent device id.
"""

from datetime import datetime
from enum import StrEnum
from typing import Annotated

from beanie import Document, Indexed


class PairTokenStatus(StrEnum):
    PENDING = "pending"
    REDEEMED = "redeemed"
    CANCELLED = "cancelled"
    EXPIRED = "expired"


class PairToken(Document):
    token: Annotated[str, Indexed(unique=True)]  # 32-char hex
    short_code: Annotated[str, Indexed(unique=True)]  # 6-digit numeric, base-10
    family_id: Annotated[str, Indexed()]
    created_by_parent_id: str

    status: PairTokenStatus = PairTokenStatus.PENDING
    created_at: datetime
    expires_at: datetime
    redeemed_at: datetime | None = None
    cancelled_at: datetime | None = None

    redeemed_by_device_id: str | None = None
    redeemed_binding_id: str | None = None

    class Settings:
        name = "pair_tokens"
        indexes = [[("status", 1), ("expires_at", 1)]]
