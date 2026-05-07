"""V0.6.6 — wire schemas for parent + child wishlist endpoints."""

from __future__ import annotations

from datetime import datetime  # noqa: TC003 — pydantic needs runtime type
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field


class CloudWishlistCreateIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    display_name: Annotated[str, Field(min_length=1, max_length=32)]
    cost_coins: Annotated[int, Field(ge=5, le=200)]
    icon_emoji: Annotated[str, Field(default="🎁", min_length=1, max_length=8)]


class CloudWishlistPatchIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    display_name: Annotated[str | None, Field(default=None, min_length=1, max_length=32)]
    cost_coins: Annotated[int | None, Field(default=None, ge=5, le=200)]
    icon_emoji: Annotated[str | None, Field(default=None, min_length=1, max_length=8)]


class CloudWishlistItemOut(BaseModel):
    item_id: str
    child_profile_id: str
    display_name: str
    cost_coins: int
    icon_emoji: str
    state: Literal["active", "redeemed", "archived"]
    is_parent_curated: bool
    created_by: Literal["parent", "child_device"]
    created_at: datetime
    updated_at: datetime


class CloudWishlistListOut(BaseModel):
    items: list[CloudWishlistItemOut]


# --- Child sync of locally-created custom items ---


class ChildCustomWishlistItemIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    item_id: Annotated[str, Field(min_length=1, max_length=64)]
    display_name: Annotated[str, Field(min_length=1, max_length=32)]
    cost_coins: Annotated[int, Field(ge=5, le=200)]
    icon_emoji: Annotated[str, Field(default="🎁", min_length=1, max_length=8)]


class ChildWishlistSyncIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: list[ChildCustomWishlistItemIn]


class ChildWishlistSyncOut(BaseModel):
    accepted: int
    items: list[CloudWishlistItemOut]
