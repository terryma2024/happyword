"""V0.6.8 — device-side self-edit of the bound child profile.

Mounted under `/api/v1/child` and authenticated by the device JWT via
`current_device_binding` (same precedent as `child_wishlist.post_unbind`).

Kids set display name and pick an avatar emoji from `BoundDeviceInfoPage`
(HarmonyOS). Parents can still override from the web
(`PUT /api/v1/parent/children/{id}`).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from fastapi import APIRouter, Depends, HTTPException, status

from app.deps import current_device_binding
from app.schemas.child_self import (
    ChildSelfProfileOut,
    ChildSelfProfileUpdateIn,
)
from app.services.child_profile_service import (
    ChildProfileNotFound,
    update,
)

if TYPE_CHECKING:
    from app.models.device_binding import DeviceBinding


router = APIRouter(prefix="/api/v1/child", tags=["child-profile"])


@router.put("/profile", response_model=ChildSelfProfileOut)
async def put_self_profile(
    payload: ChildSelfProfileUpdateIn,
    binding: DeviceBinding = Depends(current_device_binding),
) -> ChildSelfProfileOut:
    # Reject whitespace-only nicknames up front. The service silently
    # ignores them (treats as no-op), but for an explicit user action
    # we prefer a 400 so the device can show the rejection inline.
    if not payload.nickname.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "error": {
                    "code": "INVALID_NICKNAME",
                    "message": "Nickname must not be empty",
                }
            },
        )
    try:
        profile = await update(
            profile_id=binding.child_profile_id,
            family_id=binding.family_id,
            nickname=payload.nickname,
            avatar_emoji=payload.avatar_emoji,
        )
    except ChildProfileNotFound as e:
        # Should be unreachable in practice: current_device_binding
        # already gates revoked bindings with 404 BINDING_REVOKED, and
        # soft-deleting a profile revokes its binding. Kept as a
        # defensive 404 so a stale token after a manual DB fix-up still
        # produces a well-shaped error envelope.
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": {
                    "code": "CHILD_NOT_FOUND",
                    "message": "Child profile not found",
                }
            },
        ) from e
    return ChildSelfProfileOut(
        profile_id=profile.profile_id,
        family_id=profile.family_id,
        nickname=profile.nickname,
        avatar_emoji=profile.avatar_emoji,
        updated_at=profile.updated_at,
    )


__all__ = ["router"]
