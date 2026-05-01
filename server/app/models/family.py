"""V0.6.1 — Family aggregate.

A family is created on a parent's first successful OTP verification. It owns
devices, child profiles, family word packs, wishlist items, and redemption
requests in subsequent V0.6 sub-versions.

We use a separate `family_id` business field (`fam-<8-hex>`) instead of
overriding `_id` because of the V0.5.1 lesson: Indexed(unique=True) on `_id`
double-indexes and confuses both Atlas and mongomock-motor.
"""

from datetime import datetime
from typing import Annotated

from beanie import Document, Indexed


class Family(Document):
    family_id: Annotated[str, Indexed(unique=True)]  # "fam-<8-hex>"
    owner_user_id: Annotated[str, Indexed(unique=True)]  # 1:1 to the parent User
    primary_email: Annotated[str, Indexed(unique=True)]
    created_at: datetime
    updated_at: datetime

    class Settings:
        name = "families"
