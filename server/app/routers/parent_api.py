"""V0.6.2 — parent JSON APIs for devices + child profile management.

Cookie-authenticated; all queries are scoped to the parent's `family_id`
to prevent cross-family reads.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from beanie.odm.enums import SortDirection
from fastapi import APIRouter, Depends, HTTPException, Path, status

from app.deps import current_parent_user
from app.models.child_profile import ChildProfile
from app.models.device_binding import DeviceBinding
from app.schemas.parent_child import (
    ChildProfileOut,
    ChildProfileUpdateIn,
    DeviceListOut,
    DeviceOut,
)
from app.services.child_profile_service import (
    ChildProfileNotFound,
    soft_delete,
    update,
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
