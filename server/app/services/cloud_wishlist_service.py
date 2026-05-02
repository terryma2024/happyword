"""V0.6.6 — cloud wishlist CRUD scoped by child profile.

Service layer for parent + child wishlist endpoints. Family scoping is
enforced inside the service: every read/write requires `family_id` to
match the profile's family. Cross-family access raises
`ItemNotFound`/`ProfileNotFound` so the router can return 404 without
leaking existence.
"""

from __future__ import annotations

import secrets
from datetime import UTC, datetime
from typing import TYPE_CHECKING

from beanie.odm.enums import SortDirection

from app.models.child_profile import ChildProfile
from app.models.cloud_wishlist_item import (
    CloudWishlistItem,
    WishlistItemCreatedBy,
    WishlistItemState,
)

if TYPE_CHECKING:
    from collections.abc import Iterable

    from app.schemas.cloud_wishlist import ChildCustomWishlistItemIn


class CloudWishlistError(Exception):
    code: str = "CLOUD_WISHLIST_ERROR"


class ProfileNotFound(CloudWishlistError):
    code = "PROFILE_NOT_FOUND"


class ItemNotFound(CloudWishlistError):
    code = "ITEM_NOT_FOUND"


class InactiveItem(CloudWishlistError):
    code = "ITEM_INACTIVE"


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


def _gen_id() -> str:
    return f"wsh-{secrets.token_hex(4)}"


async def _require_profile_in_family(
    *, profile_id: str, family_id: str
) -> ChildProfile:
    profile = await ChildProfile.find_one(
        ChildProfile.profile_id == profile_id,
        ChildProfile.family_id == family_id,
        ChildProfile.deleted_at == None,  # noqa: E711
    )
    if profile is None:
        raise ProfileNotFound(profile_id)
    return profile


# ---------------------------------------------------------------------------
# Parent
# ---------------------------------------------------------------------------


async def list_for_parent(
    *,
    profile_id: str,
    family_id: str,
    include_archived: bool = False,
) -> list[CloudWishlistItem]:
    await _require_profile_in_family(profile_id=profile_id, family_id=family_id)
    query = CloudWishlistItem.find(
        CloudWishlistItem.child_profile_id == profile_id,
    )
    items = await query.sort(
        ("updated_at", SortDirection.DESCENDING)
    ).to_list()
    if include_archived:
        return items
    return [it for it in items if it.state != WishlistItemState.ARCHIVED]


async def create_for_parent(
    *,
    profile_id: str,
    family_id: str,
    display_name: str,
    cost_coins: int,
    icon_emoji: str,
) -> CloudWishlistItem:
    await _require_profile_in_family(profile_id=profile_id, family_id=family_id)
    now = _utcnow()
    item = CloudWishlistItem(
        item_id=_gen_id(),
        child_profile_id=profile_id,
        family_id=family_id,
        display_name=display_name.strip()[:32],
        cost_coins=cost_coins,
        icon_emoji=icon_emoji.strip()[:8] or "🎁",
        state=WishlistItemState.ACTIVE,
        is_parent_curated=True,
        created_by=WishlistItemCreatedBy.PARENT,
        created_at=now,
        updated_at=now,
    )
    await item.insert()
    return item


async def patch_for_parent(
    *,
    item_id: str,
    family_id: str,
    display_name: str | None,
    cost_coins: int | None,
    icon_emoji: str | None,
) -> CloudWishlistItem:
    item = await _load_item_in_family(item_id=item_id, family_id=family_id)
    if item.state == WishlistItemState.ARCHIVED:
        raise ItemNotFound(item_id)
    if display_name is not None and display_name.strip():
        item.display_name = display_name.strip()[:32]
    if cost_coins is not None:
        item.cost_coins = cost_coins
    if icon_emoji is not None and icon_emoji.strip():
        item.icon_emoji = icon_emoji.strip()[:8]
    item.updated_at = _utcnow()
    await item.save()
    return item


async def archive_for_parent(*, item_id: str, family_id: str) -> CloudWishlistItem:
    item = await _load_item_in_family(item_id=item_id, family_id=family_id)
    if item.state == WishlistItemState.ARCHIVED:
        return item
    now = _utcnow()
    item.state = WishlistItemState.ARCHIVED
    item.archived_at = now
    item.updated_at = now
    await item.save()
    return item


async def _load_item_in_family(*, item_id: str, family_id: str) -> CloudWishlistItem:
    item = await CloudWishlistItem.find_one(
        CloudWishlistItem.item_id == item_id,
        CloudWishlistItem.family_id == family_id,
    )
    if item is None:
        raise ItemNotFound(item_id)
    return item


# ---------------------------------------------------------------------------
# Child / device
# ---------------------------------------------------------------------------


async def list_active_for_device(*, profile_id: str) -> list[CloudWishlistItem]:
    items = await CloudWishlistItem.find(
        CloudWishlistItem.child_profile_id == profile_id,
        CloudWishlistItem.state == WishlistItemState.ACTIVE,
    ).sort(("updated_at", SortDirection.DESCENDING)).to_list()
    return items


async def upsert_custom_from_device(
    *,
    profile_id: str,
    family_id: str,
    items: Iterable[ChildCustomWishlistItemIn],
) -> list[CloudWishlistItem]:
    """Best-effort upsert of locally-created custom items.

    Insert-if-absent semantics: items already present (by `item_id`) are
    left untouched so the parent's edits don't get clobbered by a stale
    device push. Returns the list of items as they are now stored.
    """
    await _require_profile_in_family(profile_id=profile_id, family_id=family_id)
    now = _utcnow()
    out: list[CloudWishlistItem] = []
    for inbound in items:
        existing = await CloudWishlistItem.find_one(
            CloudWishlistItem.item_id == inbound.item_id,
            CloudWishlistItem.child_profile_id == profile_id,
        )
        if existing is not None:
            out.append(existing)
            continue
        new = CloudWishlistItem(
            item_id=inbound.item_id,
            child_profile_id=profile_id,
            family_id=family_id,
            display_name=inbound.display_name.strip()[:32],
            cost_coins=inbound.cost_coins,
            icon_emoji=inbound.icon_emoji.strip()[:8] or "🎁",
            state=WishlistItemState.ACTIVE,
            is_parent_curated=False,
            created_by=WishlistItemCreatedBy.CHILD_DEVICE,
            created_at=now,
            updated_at=now,
        )
        await new.insert()
        out.append(new)
    return out


async def get_active_for_device(
    *, item_id: str, profile_id: str
) -> CloudWishlistItem:
    """Used by the redemption service: must be ACTIVE and owned by this profile."""
    item = await CloudWishlistItem.find_one(
        CloudWishlistItem.item_id == item_id,
        CloudWishlistItem.child_profile_id == profile_id,
    )
    if item is None:
        raise ItemNotFound(item_id)
    if item.state != WishlistItemState.ACTIVE:
        raise InactiveItem(item_id)
    return item


async def mark_redeemed(*, item_id: str) -> None:
    """Called by redemption_service after a parent approves redemption."""
    item = await CloudWishlistItem.find_one(CloudWishlistItem.item_id == item_id)
    if item is None or item.state != WishlistItemState.ACTIVE:
        return
    now = _utcnow()
    item.state = WishlistItemState.REDEEMED
    item.updated_at = now
    await item.save()
