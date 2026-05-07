"""V0.6.7 — parent account scheduled-deletion + cascade.

Flow per spec §6.7:

```
parent.delete           → user.scheduled_deletion_at = now + 7d
parent.cancel-delete    → user.scheduled_deletion_at = None
sweep_scheduled_deletes → if scheduled_deletion_at < now: cascade
```

Cascade order (reverse of dependency, so child rows go first):

  redemption_requests → cloud_wishlist_items → synced_word_stats
  → child_profiles → device_bindings → family_pack_pointers
  → family_word_packs → family_pack_drafts → family_pack_definitions
  → parent_inbox_msgs → email_verifications → pair_tokens
  → family → user

Each step writes an `audit_log` row with the cascade target's
collection name + row count.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from app.models.audit_log import ActorRole
from app.models.child_profile import ChildProfile
from app.models.cloud_wishlist_item import CloudWishlistItem
from app.models.device_binding import DeviceBinding
from app.models.email_verification import EmailVerification
from app.models.family import Family
from app.models.family_pack_definition import FamilyPackDefinition
from app.models.family_pack_draft import FamilyPackDraft
from app.models.family_pack_pointer import FamilyPackPointer
from app.models.family_word_pack import FamilyWordPack
from app.models.pair_token import PairToken
from app.models.parent_inbox_msg import ParentInboxMsg
from app.models.redemption_request import RedemptionRequest
from app.models.synced_word_stat import SyncedWordStat
from app.models.user import User, UserRole
from app.services import audit_service

GRACE_PERIOD = timedelta(days=7)


class AccountDeletionError(Exception):
    code: str = "ACCOUNT_DELETION_ERROR"


class UserNotFound(AccountDeletionError):
    code = "USER_NOT_FOUND"


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


def grace_days_remaining(*, scheduled: datetime | None, now: datetime | None = None) -> int:
    if scheduled is None:
        return 0
    n = now or _utcnow()
    sched = scheduled if scheduled.tzinfo is not None else scheduled.replace(tzinfo=UTC)
    remaining = (sched - n).days
    return max(0, remaining)


async def schedule_deletion(
    *, user_id: str, requested_by: str
) -> datetime:
    user = await User.find_one(
        User.username == user_id, User.role == UserRole.PARENT
    )
    if user is None:
        raise UserNotFound(user_id)
    scheduled_at = _utcnow() + GRACE_PERIOD
    user.scheduled_deletion_at = scheduled_at
    await user.save()
    await audit_service.record(
        actor_role=ActorRole.PARENT,
        actor_id=requested_by,
        action="account.delete_request",
        target_collection="users",
        target_id=user.username,
        payload_summary={"scheduled_for": scheduled_at.isoformat()},
    )
    return scheduled_at


async def cancel_deletion(
    *, user_id: str, requested_by: str
) -> bool:
    user = await User.find_one(
        User.username == user_id, User.role == UserRole.PARENT
    )
    if user is None:
        raise UserNotFound(user_id)
    if user.scheduled_deletion_at is None:
        return False
    user.scheduled_deletion_at = None
    await user.save()
    await audit_service.record(
        actor_role=ActorRole.PARENT,
        actor_id=requested_by,
        action="account.delete_cancel",
        target_collection="users",
        target_id=user.username,
    )
    return True


async def sweep_scheduled_deletes(*, now: datetime | None = None) -> int:
    """Cascade-delete every parent whose scheduled_deletion_at is in the past.

    Returns the count of users actually deleted.
    """
    cutoff = now or _utcnow()
    pending = await User.find(
        User.role == UserRole.PARENT,
        User.scheduled_deletion_at != None,  # noqa: E711
    ).to_list()
    n = 0
    for u in pending:
        sched = u.scheduled_deletion_at
        if sched is None:
            continue
        if sched.tzinfo is None:
            sched = sched.replace(tzinfo=UTC)
        if sched > cutoff:
            continue
        await cascade_delete_user(user=u)
        n += 1
    return n


async def cascade_delete_user(*, user: User) -> None:
    family_id = user.family_id or ""
    audit_chain: list[tuple[str, int]] = []

    if family_id:
        audit_chain.append(
            ("redemption_requests", await _delete_by_family(RedemptionRequest, family_id))
        )
        audit_chain.append(
            ("cloud_wishlist_items", await _delete_by_family(CloudWishlistItem, family_id))
        )
        audit_chain.append(
            ("synced_word_stats", await _delete_synced_word_stats_for_family(family_id))
        )
        audit_chain.append(
            ("child_profiles", await _delete_by_family(ChildProfile, family_id))
        )
        audit_chain.append(
            ("device_bindings", await _delete_by_family(DeviceBinding, family_id))
        )
        audit_chain.append(
            ("family_pack_pointers", await _delete_by_family(FamilyPackPointer, family_id))
        )
        audit_chain.append(
            ("family_word_packs", await _delete_by_family(FamilyWordPack, family_id))
        )
        audit_chain.append(
            ("family_pack_drafts", await _delete_by_family(FamilyPackDraft, family_id))
        )
        audit_chain.append(
            ("family_pack_definitions", await _delete_by_family(FamilyPackDefinition, family_id))
        )
        audit_chain.append(
            ("families", await _delete_family(family_id))
        )

    audit_chain.append(("parent_inbox_msgs", await _delete_inbox(user.username)))
    if user.email:
        audit_chain.append(("email_verifications", await _delete_email_verifications(user.email)))
    audit_chain.append(("pair_tokens", await _delete_pair_tokens(family_id)))

    await user.delete()
    audit_chain.append(("users", 1))

    for collection, deleted in audit_chain:
        if deleted == 0:
            continue
        await audit_service.record(
            actor_role=ActorRole.SYSTEM,
            actor_id=user.username,
            action="account.delete_commit",
            target_collection=collection,
            target_id=family_id or user.username,
            payload_summary={"deleted": deleted},
        )


async def _delete_by_family(model_cls: type, family_id: str) -> int:
    rows = await model_cls.find(  # type: ignore[attr-defined]
        model_cls.family_id == family_id  # type: ignore[attr-defined]
    ).to_list()
    n = len(rows)
    for r in rows:
        await r.delete()
    return n


async def _delete_synced_word_stats_for_family(family_id: str) -> int:
    profiles = await ChildProfile.find(
        ChildProfile.family_id == family_id
    ).to_list()
    profile_ids = [p.profile_id for p in profiles]
    if not profile_ids:
        return 0
    rows = await SyncedWordStat.find(
        {"child_profile_id": {"$in": profile_ids}}
    ).to_list()
    n = len(rows)
    for r in rows:
        await r.delete()
    return n


async def _delete_family(family_id: str) -> int:
    family = await Family.find_one(Family.family_id == family_id)
    if family is None:
        return 0
    await family.delete()
    return 1


async def _delete_inbox(parent_user_id: str) -> int:
    rows = await ParentInboxMsg.find(
        ParentInboxMsg.parent_user_id == parent_user_id
    ).to_list()
    n = len(rows)
    for r in rows:
        await r.delete()
    return n


async def _delete_email_verifications(email: str) -> int:
    rows = await EmailVerification.find(EmailVerification.email == email).to_list()
    n = len(rows)
    for r in rows:
        await r.delete()
    return n


async def _delete_pair_tokens(family_id: str) -> int:
    if not family_id:
        return 0
    rows = await PairToken.find(PairToken.family_id == family_id).to_list()
    n = len(rows)
    for r in rows:
        await r.delete()
    return n


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------


async def export_account_data(
    *, user: User
) -> dict[str, list[dict[str, object]]]:
    """Return a JSON-shaped snapshot for `/api/v1/parent/account/export`.

    The router can stream this as a multipart download; for V0.6.7 we
    keep the implementation simple (single JSON response) so the test
    asserts the structure rather than the multipart wire format.
    """
    family_id = user.family_id or ""
    profiles = await ChildProfile.find(
        ChildProfile.family_id == family_id
    ).to_list() if family_id else []
    bindings = await DeviceBinding.find(
        DeviceBinding.family_id == family_id
    ).to_list() if family_id else []
    wishlist = await CloudWishlistItem.find(
        CloudWishlistItem.family_id == family_id
    ).to_list() if family_id else []
    redemptions = await RedemptionRequest.find(
        RedemptionRequest.family_id == family_id
    ).to_list() if family_id else []
    inbox = await ParentInboxMsg.find(
        ParentInboxMsg.parent_user_id == user.username
    ).to_list()
    snapshot: dict[str, list[dict[str, object]]] = {
        "child_profiles": [_profile_dict(p) for p in profiles],
        "device_bindings": [_binding_dict(b) for b in bindings],
        "wishlist_items": [_wishlist_dict(w) for w in wishlist],
        "redemption_requests": [_redemption_dict(r) for r in redemptions],
        "inbox_messages": [_inbox_dict(m) for m in inbox],
    }
    return snapshot


def _profile_dict(p: ChildProfile) -> dict[str, object]:
    return {
        "profile_id": p.profile_id,
        "nickname": p.nickname,
        "avatar_emoji": p.avatar_emoji,
        "created_at": p.created_at.isoformat(),
    }


def _binding_dict(b: DeviceBinding) -> dict[str, object]:
    return {
        "binding_id": b.binding_id,
        "device_id": b.device_id,
        "child_profile_id": b.child_profile_id,
        "created_at": b.created_at.isoformat(),
        "revoked_at": b.revoked_at.isoformat() if b.revoked_at else None,
    }


def _wishlist_dict(w: CloudWishlistItem) -> dict[str, object]:
    return {
        "item_id": w.item_id,
        "display_name": w.display_name,
        "cost_coins": w.cost_coins,
        "state": str(w.state),
        "created_at": w.created_at.isoformat(),
    }


def _redemption_dict(r: RedemptionRequest) -> dict[str, object]:
    return {
        "request_id": r.request_id,
        "wishlist_item_id": r.wishlist_item_id,
        "status": str(r.status),
        "cost_coins_at_request": r.cost_coins_at_request,
        "requested_at": r.requested_at.isoformat(),
    }


def _inbox_dict(m: ParentInboxMsg) -> dict[str, object]:
    return {
        "msg_id": m.msg_id,
        "kind": str(m.kind),
        "title": m.title,
        "body_md": m.body_md,
        "created_at": m.created_at.isoformat(),
    }
