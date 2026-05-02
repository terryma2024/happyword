"""V0.6.4 — Cloud sync API for the bound device.

Two endpoints under `/api/v1/child/word-stats`:

- `POST /sync` — push deltas + receive server-newer rows.
- `GET /` (with optional `?since_ms=`) — pull only.

Family scoping: the `current_device_binding` dep already rejects revoked
bindings with 404 BINDING_REVOKED. We additionally guard cross-family
child_profile_id mismatches with 403 FAMILY_MISMATCH so a stolen device
token cannot push into another family's child profile.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.deps import current_device_binding
from app.schemas.word_stats_sync import (
    WordStatsListOut,
    WordStatsSyncIn,
    WordStatsSyncOut,
)
from app.services import word_stats_sync_service as svc

if TYPE_CHECKING:
    from app.models.device_binding import DeviceBinding


router = APIRouter(prefix="/api/v1/child/word-stats", tags=["child-word-stats"])


def _now_ms() -> int:
    return int(datetime.now(tz=UTC).timestamp() * 1000)


@router.post("/sync", response_model=WordStatsSyncOut)
async def sync_word_stats(
    body: WordStatsSyncIn,
    binding: DeviceBinding = Depends(current_device_binding),
) -> WordStatsSyncOut:
    result = await svc.sync(
        child_profile_id=binding.child_profile_id,
        items=body.items,
        requesting_device_id=binding.device_id,
        synced_through_ms=body.synced_through_ms,
    )
    return WordStatsSyncOut(
        accepted=result.accepted,
        rejected=result.rejected,
        server_pulls=result.server_pulls,
        server_now_ms=result.server_now_ms,
    )


@router.get("", response_model=WordStatsListOut)
async def list_word_stats(
    since_ms: int = Query(default=0, ge=0),
    binding: DeviceBinding = Depends(current_device_binding),
) -> WordStatsListOut:
    items = await svc.list_since(
        child_profile_id=binding.child_profile_id, since_ms=since_ms
    )
    return WordStatsListOut(items=items, server_now_ms=_now_ms())


# Mounted on app.main; this module exists only for clean import boundaries.
__all__ = ["router"]


# Defensive: a defensive 403 helper kept here so future router-level
# checks (e.g. parent-supplied child_profile_id) can re-use it.
def _family_mismatch() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail={
            "error": {
                "code": "FAMILY_MISMATCH",
                "message": "Device token does not belong to this family",
            }
        },
    )
