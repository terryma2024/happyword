"""V0.6.2 — ChildProfile is the 1:1 sibling of DeviceBinding.

Owns nickname/avatar; later sub-versions hang learning records, wishlist,
and redemption requests off `child_profile_id`. Soft-delete via
`deleted_at` keeps history queryable for 7-day account-deletion grace
(spec §V0.6.7).
"""

from datetime import datetime
from typing import Annotated

from beanie import Document, Indexed


class ChildProfile(Document):
    profile_id: Annotated[str, Indexed(unique=True)]  # "child-<8hex>"
    family_id: Annotated[str, Indexed()]
    binding_id: Annotated[str, Indexed()]
    nickname: str = "宝贝"
    avatar_emoji: str = "🦄"

    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None

    class Settings:
        name = "child_profiles"
        indexes = [[("family_id", 1), ("deleted_at", 1)]]
