"""V0.8.8 — Child-device daily check-in cloud sync APIs."""

from __future__ import annotations

from typing import TYPE_CHECKING

from fastapi import APIRouter, Depends, Path

from app.deps import current_device_binding
from app.schemas.checkins import CheckInListOut, CheckInSyncIn, CheckInSyncOut
from app.services import checkin_sync_service as svc

if TYPE_CHECKING:
    from app.models.device_binding import DeviceBinding


router = APIRouter(prefix="/api/v1/family", tags=["child-checkins"])


@router.post("/{family_id}/checkins/sync", response_model=CheckInSyncOut)
async def sync_checkins(
    body: CheckInSyncIn,
    family_id: str = Path(min_length=1, max_length=128),
    binding: DeviceBinding = Depends(current_device_binding),
) -> CheckInSyncOut:
    _ = family_id
    result = await svc.sync(
        child_profile_id=binding.child_profile_id,
        checked_day_keys=body.checked_day_keys,
        weekly_bonus_day_keys=body.weekly_bonus_day_keys,
        coin_txns=body.coin_txns,
        requesting_device_id=binding.device_id,
    )
    return CheckInSyncOut(
        checked_day_keys=result.checked_day_keys,
        weekly_bonus_day_keys=result.weekly_bonus_day_keys,
        coin_txns=result.coin_txns,
        server_now_ms=result.server_now_ms,
    )


@router.get("/{family_id}/checkins", response_model=CheckInListOut)
async def list_checkins(
    family_id: str = Path(min_length=1, max_length=128),
    binding: DeviceBinding = Depends(current_device_binding),
) -> CheckInListOut:
    _ = family_id
    result = await svc.list_all(child_profile_id=binding.child_profile_id)
    return CheckInListOut(
        checked_day_keys=result.checked_day_keys,
        weekly_bonus_day_keys=result.weekly_bonus_day_keys,
        coin_txns=result.coin_txns,
        server_now_ms=result.server_now_ms,
    )
