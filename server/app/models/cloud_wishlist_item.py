"""V0.6.6 — cloud copy of a single wishlist entry.

A `CloudWishlistItem` is owned by a child profile (per `child_profile_id`)
and lives across active / redeemed / archived states. Items can be created
either by the parent (curated) or by the child device (synced from the
client's local wishlist).
"""

from datetime import datetime
from enum import StrEnum
from typing import Annotated

from beanie import Document, Indexed


class WishlistItemState(StrEnum):
    ACTIVE = "active"
    REDEEMED = "redeemed"
    ARCHIVED = "archived"


class WishlistItemCreatedBy(StrEnum):
    PARENT = "parent"
    CHILD_DEVICE = "child_device"


class CloudWishlistItem(Document):
    item_id: Annotated[str, Indexed(unique=True)]  # "wsh-<8hex>"
    child_profile_id: Annotated[str, Indexed()]
    family_id: Annotated[str, Indexed()]
    display_name: str
    cost_coins: int  # 5..200
    icon_emoji: str = "🎁"
    state: WishlistItemState = WishlistItemState.ACTIVE
    is_parent_curated: bool = True
    created_by: WishlistItemCreatedBy = WishlistItemCreatedBy.PARENT
    created_at: datetime
    updated_at: datetime
    archived_at: datetime | None = None

    class Settings:
        name = "cloud_wishlist_items"
        indexes = [[("child_profile_id", 1), ("state", 1), ("updated_at", -1)]]
