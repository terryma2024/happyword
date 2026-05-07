"""V0.6.6 — child-initiated redemption requests + parent decisions.

Lifecycle:

```
device.submit  ──► RedemptionRequest(status=pending, expires_at=requested_at+7d)
parent.approve ──► status=approved, decided_at, decided_by, decision_note
parent.reject  ──► status=rejected
sweep_expired  ──► status=expired (when expires_at < now)
```

`approve` also flips the underlying `CloudWishlistItem` to `redeemed` so the
device's next wishlist fetch removes it from the active list. Subsequent
parent decisions on an already-decided row return `AlreadyDecided`.
"""

from __future__ import annotations

import secrets
from datetime import UTC, datetime, timedelta
from typing import TYPE_CHECKING

from beanie.odm.enums import SortDirection

from app.models.redemption_request import RedemptionRequest, RedemptionStatus
from app.services import cloud_wishlist_service

if TYPE_CHECKING:
    from app.models.child_profile import ChildProfile
    from app.models.cloud_wishlist_item import CloudWishlistItem

REDEMPTION_TTL = timedelta(days=7)


class RedemptionError(Exception):
    code: str = "REDEMPTION_ERROR"


class RequestNotFound(RedemptionError):
    code = "REQUEST_NOT_FOUND"


class AlreadyDecided(RedemptionError):
    code = "ALREADY_DECIDED"


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


def _gen_id() -> str:
    return f"rdm-{secrets.token_hex(4)}"


# ---------------------------------------------------------------------------
# Device side
# ---------------------------------------------------------------------------


async def submit_request(
    *,
    profile_id: str,
    family_id: str,
    device_binding_id: str,
    wishlist_item_id: str,
) -> RedemptionRequest:
    """Snapshot the item's current cost and create a pending request.

    Item must be ACTIVE for this profile (else `InactiveItem`/`ItemNotFound`
    bubble out from `cloud_wishlist_service`). We don't dedupe on
    (profile, item, pending) — a parent can approve multiple stacked
    requests, and the client overlay will handle the most recent one.

    V0.6.7: also writes a ParentInboxMsg + best-effort sends an email so
    the parent is alerted out-of-band. Email failure is swallowed (the
    request is more important than the notification).
    """
    item = await cloud_wishlist_service.get_active_for_device(
        item_id=wishlist_item_id, profile_id=profile_id
    )
    now = _utcnow()
    req = RedemptionRequest(
        request_id=_gen_id(),
        child_profile_id=profile_id,
        family_id=family_id,
        wishlist_item_id=item.item_id,
        cost_coins_at_request=item.cost_coins,
        requested_at=now,
        status=RedemptionStatus.PENDING,
        device_binding_id=device_binding_id,
        expires_at=now + REDEMPTION_TTL,
    )
    await req.insert()
    await _notify_redemption_request(req=req, item=item)
    return req


async def _notify_redemption_request(
    *, req: RedemptionRequest, item: object
) -> None:
    """Best-effort: write inbox row and try to send the email. Both are
    optional; failures must not bubble back to the device caller."""
    import contextlib  # noqa: PLC0415 — kept local to keep top-level imports lean

    from app.config import get_settings  # noqa: PLC0415
    from app.main import app  # noqa: PLC0415
    from app.models.child_profile import ChildProfile  # noqa: PLC0415
    from app.models.parent_inbox_msg import ParentInboxKind  # noqa: PLC0415
    from app.models.user import User, UserRole  # noqa: PLC0415
    from app.services import notification_service  # noqa: PLC0415

    parent = await User.find_one(
        User.family_id == req.family_id, User.role == UserRole.PARENT
    )
    if parent is None:
        return
    profile = await ChildProfile.find_one(
        ChildProfile.profile_id == req.child_profile_id
    )
    nickname = profile.nickname if profile is not None else "孩子"
    display_name = getattr(item, "display_name", "")
    cost = getattr(item, "cost_coins", 0)

    with contextlib.suppress(Exception):
        await notification_service.write_inbox_msg(
            family_id=req.family_id,
            parent_user_id=parent.username,
            kind=ParentInboxKind.REDEMPTION_REQUEST,
            title=f"{nickname} 想兑换 {display_name}",
            body_md=(
                f"**{nickname}** 想兑换 **{display_name}**（{cost} 金币）。\n"
                f"申请编号：`{req.request_id}`。请到 [兑换审批]"
                f"(/parent/redemptions) 处理。"
            ),
            related_resource={"redemption_request_id": req.request_id},
        )

    settings = get_settings()
    if not settings.notification_email_enabled or parent.email is None:
        return
    provider = getattr(app.state, "email_provider", None)
    if provider is None:
        return
    with contextlib.suppress(Exception):
        await notification_service.send_redemption_email(
            provider,
            to=parent.email,
            child_nickname=nickname,
            item_display_name=display_name,
            cost_coins=cost,
            request_id=req.request_id,
        )


async def list_pending_for_device(
    *, profile_id: str
) -> list[RedemptionRequest]:
    return await RedemptionRequest.find(
        RedemptionRequest.child_profile_id == profile_id,
        RedemptionRequest.status == RedemptionStatus.PENDING,
    ).sort(("requested_at", SortDirection.ASCENDING)).to_list()


async def poll_for_device(
    *, profile_id: str, since_ms: int
) -> list[RedemptionRequest]:
    """Return rows whose `decided_at` is newer than `since_ms`.

    Pending rows are intentionally excluded — the device only needs the
    first poll to render the overlay; subsequent polls just want decisions.
    Expired rows are returned so the overlay can be dismissed.
    """
    since = datetime.fromtimestamp(since_ms / 1000, tz=UTC) if since_ms > 0 else None
    rows = await RedemptionRequest.find(
        RedemptionRequest.child_profile_id == profile_id,
        RedemptionRequest.status != RedemptionStatus.PENDING,
    ).to_list()
    if since is None:
        return rows
    out: list[RedemptionRequest] = []
    for r in rows:
        decided = r.decided_at
        if decided is not None and decided.tzinfo is None:
            decided = decided.replace(tzinfo=UTC)
        if decided is not None and decided >= since:
            out.append(r)
    return out


# ---------------------------------------------------------------------------
# Parent side
# ---------------------------------------------------------------------------


async def list_pending_for_family(
    *, family_id: str
) -> list[RedemptionRequest]:
    return await RedemptionRequest.find(
        RedemptionRequest.family_id == family_id,
        RedemptionRequest.status == RedemptionStatus.PENDING,
    ).sort(("requested_at", SortDirection.ASCENDING)).to_list()


async def list_recent_for_family(
    *, family_id: str, limit: int = 50
) -> list[RedemptionRequest]:
    rows = await RedemptionRequest.find(
        RedemptionRequest.family_id == family_id,
    ).sort(("requested_at", SortDirection.DESCENDING)).to_list()
    return rows[:limit]


async def _load_for_decision(
    *, request_id: str, family_id: str
) -> RedemptionRequest:
    req = await RedemptionRequest.find_one(
        RedemptionRequest.request_id == request_id,
        RedemptionRequest.family_id == family_id,
    )
    if req is None:
        raise RequestNotFound(request_id)
    if req.status != RedemptionStatus.PENDING:
        raise AlreadyDecided(request_id)
    return req


async def approve(
    *,
    request_id: str,
    family_id: str,
    decided_by: str,
    note: str | None,
) -> RedemptionRequest:
    req = await _load_for_decision(request_id=request_id, family_id=family_id)
    now = _utcnow()
    req.status = RedemptionStatus.APPROVED
    req.decided_at = now
    req.decided_by = decided_by
    req.decision_note = note.strip()[:200] if note and note.strip() else None
    await req.save()
    await cloud_wishlist_service.mark_redeemed(item_id=req.wishlist_item_id)
    return req


async def reject(
    *,
    request_id: str,
    family_id: str,
    decided_by: str,
    note: str | None,
) -> RedemptionRequest:
    req = await _load_for_decision(request_id=request_id, family_id=family_id)
    now = _utcnow()
    req.status = RedemptionStatus.REJECTED
    req.decided_at = now
    req.decided_by = decided_by
    req.decision_note = note.strip()[:200] if note and note.strip() else None
    await req.save()
    return req


# ---------------------------------------------------------------------------
# Maintenance
# ---------------------------------------------------------------------------


async def sweep_expired(*, now_ms: int) -> int:
    """Mark all pending rows whose expires_at < now as expired. Returns count."""
    now = datetime.fromtimestamp(now_ms / 1000, tz=UTC)
    pending = await RedemptionRequest.find(
        RedemptionRequest.status == RedemptionStatus.PENDING,
    ).to_list()
    n = 0
    for r in pending:
        exp = r.expires_at
        if exp.tzinfo is None:
            exp = exp.replace(tzinfo=UTC)
        if exp < now:
            r.status = RedemptionStatus.EXPIRED
            r.decided_at = now
            await r.save()
            n += 1
    return n


# Helper used by parent-side rendering: count of currently-bound profiles in
# this family that have a redeemed item but no pending follow-up. Currently
# only used by tests; kept here so the router stays thin.
async def child_summary(
    *, child_profile: ChildProfile, item: CloudWishlistItem
) -> dict[str, str]:
    return {
        "profile_id": child_profile.profile_id,
        "nickname": child_profile.nickname,
        "item_id": item.item_id,
        "display_name": item.display_name,
    }
