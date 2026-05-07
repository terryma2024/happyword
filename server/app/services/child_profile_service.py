"""V0.6.2 — ChildProfile mutations driven by parent web actions."""

from datetime import UTC, datetime

from app.models.child_profile import ChildProfile
from app.models.device_binding import DeviceBinding


class ChildProfileError(Exception):
    pass


class ChildProfileNotFound(ChildProfileError):
    pass


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


async def update(
    *,
    profile_id: str,
    family_id: str,
    nickname: str | None = None,
    avatar_emoji: str | None = None,
) -> ChildProfile:
    """Partial update; raises ChildProfileNotFound if the profile is in another family."""
    profile = await ChildProfile.find_one(
        ChildProfile.profile_id == profile_id,
        ChildProfile.family_id == family_id,
    )
    if profile is None or profile.deleted_at is not None:
        raise ChildProfileNotFound
    if nickname is not None and nickname.strip():
        profile.nickname = nickname.strip()[:32]
    if avatar_emoji is not None and avatar_emoji.strip():
        profile.avatar_emoji = avatar_emoji.strip()[:8]
    profile.updated_at = _utcnow()
    await profile.save()
    return profile


async def soft_delete(*, profile_id: str, family_id: str) -> None:
    """Soft-delete the profile and revoke its current DeviceBinding so the
    client immediately stops being authorized for /api/v1/child/* requests."""
    profile = await ChildProfile.find_one(
        ChildProfile.profile_id == profile_id,
        ChildProfile.family_id == family_id,
    )
    if profile is None or profile.deleted_at is not None:
        raise ChildProfileNotFound
    now = _utcnow()
    profile.deleted_at = now
    await profile.save()
    binding = await DeviceBinding.find_one(
        DeviceBinding.binding_id == profile.binding_id
    )
    if binding is not None and binding.revoked_at is None:
        binding.revoked_at = now
        await binding.save()
