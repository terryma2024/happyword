"""V0.6.6 — child-side wishlist + redemption-request APIs.

These are mounted under `/api/v1/child` and authenticated by the device
JWT via `current_device_binding`. The dep also rejects revoked bindings
with 404 BINDING_REVOKED.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING

from fastapi import APIRouter, Body, Depends, HTTPException, Query, status

from app.deps import current_device_binding
from app.schemas.cloud_wishlist import (
    ChildWishlistSyncIn,
    ChildWishlistSyncOut,
    CloudWishlistItemOut,
    CloudWishlistListOut,
)
from app.schemas.redemption import (
    RedemptionPollOut,
    RedemptionRequestCreateIn,
    RedemptionRequestListOut,
    RedemptionRequestOut,
)
from app.services import cloud_wishlist_service, redemption_service

if TYPE_CHECKING:
    from app.models.cloud_wishlist_item import CloudWishlistItem
    from app.models.device_binding import DeviceBinding
    from app.models.redemption_request import RedemptionRequest


router = APIRouter(prefix="/api/v1/child", tags=["child-wishlist"])


def _now_ms() -> int:
    return int(datetime.now(tz=UTC).timestamp() * 1000)


def _wishlist_to_out(item: CloudWishlistItem) -> CloudWishlistItemOut:
    return CloudWishlistItemOut.model_validate(
        {
            "item_id": item.item_id,
            "child_profile_id": item.child_profile_id,
            "display_name": item.display_name,
            "cost_coins": item.cost_coins,
            "icon_emoji": item.icon_emoji,
            "state": str(item.state),
            "is_parent_curated": item.is_parent_curated,
            "created_by": str(item.created_by),
            "created_at": item.created_at,
            "updated_at": item.updated_at,
        }
    )


def _redemption_to_out(req: RedemptionRequest) -> RedemptionRequestOut:
    return RedemptionRequestOut.model_validate(
        {
            "request_id": req.request_id,
            "child_profile_id": req.child_profile_id,
            "wishlist_item_id": req.wishlist_item_id,
            "cost_coins_at_request": req.cost_coins_at_request,
            "requested_at": req.requested_at,
            "status": str(req.status),
            "decided_at": req.decided_at,
            "decided_by": req.decided_by,
            "decision_note": req.decision_note,
            "expires_at": req.expires_at,
        }
    )


@router.get("/wishlist", response_model=CloudWishlistListOut)
async def list_wishlist(
    binding: DeviceBinding = Depends(current_device_binding),
) -> CloudWishlistListOut:
    items = await cloud_wishlist_service.list_active_for_device(
        profile_id=binding.child_profile_id
    )
    return CloudWishlistListOut(items=[_wishlist_to_out(i) for i in items])


@router.post(
    "/wishlist/sync-custom",
    response_model=ChildWishlistSyncOut,
)
async def sync_custom(
    payload: ChildWishlistSyncIn,
    binding: DeviceBinding = Depends(current_device_binding),
) -> ChildWishlistSyncOut:
    items = await cloud_wishlist_service.upsert_custom_from_device(
        profile_id=binding.child_profile_id,
        family_id=binding.family_id,
        items=payload.items,
    )
    return ChildWishlistSyncOut(
        accepted=len(items),
        items=[_wishlist_to_out(i) for i in items],
    )


@router.post(
    "/redemption-requests",
    response_model=RedemptionRequestOut,
    status_code=status.HTTP_201_CREATED,
)
async def submit_redemption(
    payload: RedemptionRequestCreateIn = Body(...),
    binding: DeviceBinding = Depends(current_device_binding),
) -> RedemptionRequestOut:
    try:
        req = await redemption_service.submit_request(
            profile_id=binding.child_profile_id,
            family_id=binding.family_id,
            device_binding_id=binding.binding_id,
            wishlist_item_id=payload.wishlist_item_id,
        )
    except cloud_wishlist_service.ItemNotFound as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": {
                    "code": "WISHLIST_ITEM_NOT_FOUND",
                    "message": "Wishlist item not in your profile",
                }
            },
        ) from e
    except cloud_wishlist_service.InactiveItem as e:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "error": {
                    "code": "ITEM_INACTIVE",
                    "message": "Wishlist item is not active",
                }
            },
        ) from e
    return _redemption_to_out(req)


@router.get(
    "/redemption-requests",
    response_model=RedemptionRequestListOut,
)
async def list_pending(
    binding: DeviceBinding = Depends(current_device_binding),
) -> RedemptionRequestListOut:
    rows = await redemption_service.list_pending_for_device(
        profile_id=binding.child_profile_id
    )
    return RedemptionRequestListOut(items=[_redemption_to_out(r) for r in rows])


@router.get(
    "/redemption-requests/poll",
    response_model=RedemptionPollOut,
)
async def poll_decisions(
    since_ms: int = Query(default=0, ge=0),
    binding: DeviceBinding = Depends(current_device_binding),
) -> RedemptionPollOut:
    rows = await redemption_service.poll_for_device(
        profile_id=binding.child_profile_id, since_ms=since_ms
    )
    return RedemptionPollOut(
        items=[_redemption_to_out(r) for r in rows],
        server_now_ms=_now_ms(),
    )


@router.post("/unbind", status_code=status.HTTP_200_OK)
async def post_unbind(
    binding: DeviceBinding = Depends(current_device_binding),
) -> dict[str, str]:
    """V0.6.7 — explicit device unbind. Sets revoked_at; subsequent
    /api/v1/child/* calls with the same token return 404 BINDING_REVOKED.
    """
    from app.models.audit_log import ActorRole  # noqa: PLC0415
    from app.services import audit_service  # noqa: PLC0415

    if binding.revoked_at is None:
        binding.revoked_at = datetime.now(tz=UTC)
        await binding.save()
        await audit_service.record(
            actor_role=ActorRole.DEVICE,
            actor_id=binding.binding_id,
            action="device.unbind",
            target_collection="device_bindings",
            target_id=binding.binding_id,
            payload_summary={"family_id": binding.family_id},
        )
    return {"status": "unbound"}


__all__ = ["router"]
