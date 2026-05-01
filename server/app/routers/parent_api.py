"""V0.6.2 — parent JSON APIs for devices + child profile management.

Cookie-authenticated; all queries are scoped to the parent's `family_id`
to prevent cross-family reads.
"""

from __future__ import annotations

import time
from typing import TYPE_CHECKING

from beanie.odm.enums import SortDirection
from fastapi import APIRouter, Depends, HTTPException, Path, Query, status

from app.deps import current_parent_user
from app.models.child_profile import ChildProfile
from app.models.device_binding import DeviceBinding
from app.schemas.cloud_wishlist import (
    CloudWishlistCreateIn,
    CloudWishlistItemOut,
    CloudWishlistListOut,
    CloudWishlistPatchIn,
)
from app.schemas.parent_child import (
    ChildProfileOut,
    ChildProfileUpdateIn,
    DeviceListOut,
    DeviceOut,
)
from app.schemas.parent_report import ChildReportOut
from app.schemas.redemption import (
    RedemptionDecisionIn,
    RedemptionRequestListOut,
    RedemptionRequestOut,
)
from app.services import cloud_wishlist_service, redemption_service
from app.services.child_profile_service import (
    ChildProfileNotFound,
    soft_delete,
    update,
)
from app.services.parent_report_service import (
    ChildProfileNotFoundForReport,
    build_report,
)

if TYPE_CHECKING:
    from app.models.user import User

router = APIRouter(prefix="/api/v1/parent", tags=["parent-children"])


@router.get("/devices", response_model=DeviceListOut)
async def list_devices(
    user: User = Depends(current_parent_user),
) -> DeviceListOut:
    rows = await DeviceBinding.find(
        DeviceBinding.family_id == (user.family_id or ""),
        sort=[("created_at", SortDirection.DESCENDING)],
    ).to_list()
    return DeviceListOut(
        devices=[
            DeviceOut(
                binding_id=r.binding_id,
                family_id=r.family_id,
                device_id=r.device_id,
                child_profile_id=r.child_profile_id,
                user_agent=r.user_agent,
                created_at=r.created_at,
                last_seen_at=r.last_seen_at,
                revoked_at=r.revoked_at,
            )
            for r in rows
        ],
        total=len(rows),
    )


@router.put(
    "/children/{profile_id}",
    response_model=ChildProfileOut,
)
async def put_child(
    payload: ChildProfileUpdateIn,
    profile_id: str = Path(min_length=8, max_length=64),
    user: User = Depends(current_parent_user),
) -> ChildProfileOut:
    try:
        profile = await update(
            profile_id=profile_id,
            family_id=user.family_id or "",
            nickname=payload.nickname,
            avatar_emoji=payload.avatar_emoji,
        )
    except ChildProfileNotFound as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": {
                    "code": "CHILD_NOT_FOUND",
                    "message": "Child profile not in your family",
                }
            },
        ) from e
    return ChildProfileOut(
        profile_id=profile.profile_id,
        family_id=profile.family_id,
        binding_id=profile.binding_id,
        nickname=profile.nickname,
        avatar_emoji=profile.avatar_emoji,
        created_at=profile.created_at,
        updated_at=profile.updated_at,
    )


@router.delete(
    "/children/{profile_id}",
    status_code=status.HTTP_200_OK,
)
async def delete_child(
    profile_id: str = Path(min_length=8, max_length=64),
    user: User = Depends(current_parent_user),
) -> dict[str, str]:
    try:
        await soft_delete(profile_id=profile_id, family_id=user.family_id or "")
    except ChildProfileNotFound as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": {
                    "code": "CHILD_NOT_FOUND",
                    "message": "Child profile not in your family",
                }
            },
        ) from e
    return {"status": "deleted"}


@router.get(
    "/children/{profile_id}/report",
    response_model=ChildReportOut,
)
async def get_child_report(
    profile_id: str = Path(min_length=8, max_length=64),
    lookback_days: int = Query(default=7, ge=1, le=90),
    user: User = Depends(current_parent_user),
) -> ChildReportOut:
    try:
        return await build_report(
            family_id=user.family_id or "",
            child_profile_id=profile_id,
            lookback_days=lookback_days,
            now_ms=int(time.time() * 1000),
        )
    except ChildProfileNotFoundForReport as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": {
                    "code": "CHILD_NOT_FOUND",
                    "message": "Child profile not in your family",
                }
            },
        ) from e


@router.get("/children", response_model=list[ChildProfileOut])
async def list_children(
    user: User = Depends(current_parent_user),
) -> list[ChildProfileOut]:
    rows = await ChildProfile.find(
        ChildProfile.family_id == (user.family_id or ""),
        ChildProfile.deleted_at == None,  # noqa: E711
    ).to_list()
    return [
        ChildProfileOut(
            profile_id=r.profile_id,
            family_id=r.family_id,
            binding_id=r.binding_id,
            nickname=r.nickname,
            avatar_emoji=r.avatar_emoji,
            created_at=r.created_at,
            updated_at=r.updated_at,
        )
        for r in rows
    ]


# ---------------------------------------------------------------------------
# Cloud wishlist (V0.6.6)
# ---------------------------------------------------------------------------


def _wishlist_to_out(item: object) -> CloudWishlistItemOut:
    # Avoid importing the model in the router header; it's already in scope
    # via the service. Pydantic still validates the shape.
    return CloudWishlistItemOut.model_validate(
        {
            "item_id": item.item_id,  # type: ignore[attr-defined]
            "child_profile_id": item.child_profile_id,  # type: ignore[attr-defined]
            "display_name": item.display_name,  # type: ignore[attr-defined]
            "cost_coins": item.cost_coins,  # type: ignore[attr-defined]
            "icon_emoji": item.icon_emoji,  # type: ignore[attr-defined]
            "state": str(item.state),  # type: ignore[attr-defined]
            "is_parent_curated": item.is_parent_curated,  # type: ignore[attr-defined]
            "created_by": str(item.created_by),  # type: ignore[attr-defined]
            "created_at": item.created_at,  # type: ignore[attr-defined]
            "updated_at": item.updated_at,  # type: ignore[attr-defined]
        }
    )


def _redemption_to_out(req: object) -> RedemptionRequestOut:
    return RedemptionRequestOut.model_validate(
        {
            "request_id": req.request_id,  # type: ignore[attr-defined]
            "child_profile_id": req.child_profile_id,  # type: ignore[attr-defined]
            "wishlist_item_id": req.wishlist_item_id,  # type: ignore[attr-defined]
            "cost_coins_at_request": req.cost_coins_at_request,  # type: ignore[attr-defined]
            "requested_at": req.requested_at,  # type: ignore[attr-defined]
            "status": str(req.status),  # type: ignore[attr-defined]
            "decided_at": req.decided_at,  # type: ignore[attr-defined]
            "decided_by": req.decided_by,  # type: ignore[attr-defined]
            "decision_note": req.decision_note,  # type: ignore[attr-defined]
            "expires_at": req.expires_at,  # type: ignore[attr-defined]
        }
    )


def _profile_404() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail={
            "error": {
                "code": "CHILD_NOT_FOUND",
                "message": "Child profile not in your family",
            }
        },
    )


def _item_404() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail={
            "error": {
                "code": "WISHLIST_ITEM_NOT_FOUND",
                "message": "Wishlist item not in your family",
            }
        },
    )


def _request_404() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail={
            "error": {
                "code": "REDEMPTION_NOT_FOUND",
                "message": "Redemption request not in your family",
            }
        },
    )


def _already_decided_409() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail={
            "error": {
                "code": "ALREADY_DECIDED",
                "message": "Redemption request already decided",
            }
        },
    )


@router.get(
    "/children/{profile_id}/wishlist",
    response_model=CloudWishlistListOut,
)
async def list_child_wishlist(
    profile_id: str = Path(min_length=8, max_length=64),
    user: User = Depends(current_parent_user),
) -> CloudWishlistListOut:
    try:
        items = await cloud_wishlist_service.list_for_parent(
            profile_id=profile_id, family_id=user.family_id or ""
        )
    except cloud_wishlist_service.ProfileNotFound as e:
        raise _profile_404() from e
    return CloudWishlistListOut(items=[_wishlist_to_out(i) for i in items])


@router.post(
    "/children/{profile_id}/wishlist",
    response_model=CloudWishlistItemOut,
    status_code=status.HTTP_201_CREATED,
)
async def create_child_wishlist_item(
    payload: CloudWishlistCreateIn,
    profile_id: str = Path(min_length=8, max_length=64),
    user: User = Depends(current_parent_user),
) -> CloudWishlistItemOut:
    try:
        item = await cloud_wishlist_service.create_for_parent(
            profile_id=profile_id,
            family_id=user.family_id or "",
            display_name=payload.display_name,
            cost_coins=payload.cost_coins,
            icon_emoji=payload.icon_emoji,
        )
    except cloud_wishlist_service.ProfileNotFound as e:
        raise _profile_404() from e
    return _wishlist_to_out(item)


@router.put(
    "/wishlist-items/{item_id}",
    response_model=CloudWishlistItemOut,
)
async def patch_wishlist_item(
    payload: CloudWishlistPatchIn,
    item_id: str = Path(min_length=4, max_length=64),
    user: User = Depends(current_parent_user),
) -> CloudWishlistItemOut:
    try:
        item = await cloud_wishlist_service.patch_for_parent(
            item_id=item_id,
            family_id=user.family_id or "",
            display_name=payload.display_name,
            cost_coins=payload.cost_coins,
            icon_emoji=payload.icon_emoji,
        )
    except cloud_wishlist_service.ItemNotFound as e:
        raise _item_404() from e
    return _wishlist_to_out(item)


@router.delete(
    "/wishlist-items/{item_id}",
    response_model=CloudWishlistItemOut,
)
async def archive_wishlist_item(
    item_id: str = Path(min_length=4, max_length=64),
    user: User = Depends(current_parent_user),
) -> CloudWishlistItemOut:
    try:
        item = await cloud_wishlist_service.archive_for_parent(
            item_id=item_id, family_id=user.family_id or ""
        )
    except cloud_wishlist_service.ItemNotFound as e:
        raise _item_404() from e
    return _wishlist_to_out(item)


# ---------------------------------------------------------------------------
# Redemption requests (V0.6.6)
# ---------------------------------------------------------------------------


@router.get(
    "/redemption-requests",
    response_model=RedemptionRequestListOut,
)
async def list_redemption_requests(
    pending_only: bool = Query(default=True),
    user: User = Depends(current_parent_user),
) -> RedemptionRequestListOut:
    if pending_only:
        rows = await redemption_service.list_pending_for_family(
            family_id=user.family_id or ""
        )
    else:
        rows = await redemption_service.list_recent_for_family(
            family_id=user.family_id or ""
        )
    return RedemptionRequestListOut(items=[_redemption_to_out(r) for r in rows])


@router.post(
    "/redemption-requests/{request_id}/approve",
    response_model=RedemptionRequestOut,
)
async def approve_redemption(
    payload: RedemptionDecisionIn,
    request_id: str = Path(min_length=4, max_length=64),
    user: User = Depends(current_parent_user),
) -> RedemptionRequestOut:
    try:
        req = await redemption_service.approve(
            request_id=request_id,
            family_id=user.family_id or "",
            decided_by=user.username,
            note=payload.note,
        )
    except redemption_service.RequestNotFound as e:
        raise _request_404() from e
    except redemption_service.AlreadyDecided as e:
        raise _already_decided_409() from e
    return _redemption_to_out(req)


@router.post(
    "/redemption-requests/{request_id}/reject",
    response_model=RedemptionRequestOut,
)
async def reject_redemption(
    payload: RedemptionDecisionIn,
    request_id: str = Path(min_length=4, max_length=64),
    user: User = Depends(current_parent_user),
) -> RedemptionRequestOut:
    try:
        req = await redemption_service.reject(
            request_id=request_id,
            family_id=user.family_id or "",
            decided_by=user.username,
            note=payload.note,
        )
    except redemption_service.RequestNotFound as e:
        raise _request_404() from e
    except redemption_service.AlreadyDecided as e:
        raise _already_decided_409() from e
    return _redemption_to_out(req)
