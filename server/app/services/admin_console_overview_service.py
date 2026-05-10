"""V0.8.2 — aggregate counts for the system administrator dashboard (/admin/)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime

from app.models.audit_log import AuditLog
from app.models.device_binding import DeviceBinding
from app.models.family import Family
from app.models.family_pack_definition import FamilyPackDefinition
from app.models.pack_pointer import PackPointer
from app.models.user import User, UserRole
from app.models.word import Word


@dataclass(frozen=True, slots=True)
class AdminOverviewSnapshot:
    parent_users: int
    families: int
    device_bindings_total: int
    device_bindings_active: int
    device_bindings_revoked: int
    global_words: int
    family_pack_definitions: int
    global_pack_current_version: int | None
    recent_audits: list[AuditLog]


async def build_admin_overview(*, audit_preview_limit: int = 12) -> AdminOverviewSnapshot:
    parent_users = await User.find(User.role == UserRole.PARENT).count()
    families = await Family.count()
    device_bindings_total = await DeviceBinding.count()
    device_bindings_active = await DeviceBinding.find(
        DeviceBinding.revoked_at == None  # noqa: E711
    ).count()
    device_bindings_revoked = max(device_bindings_total - device_bindings_active, 0)
    global_words = await Word.find(Word.deleted_at == None).count()  # noqa: E711
    family_pack_definitions = await FamilyPackDefinition.count()

    pointer = await PackPointer.find_one(PackPointer.singleton_key == "main")
    global_pack_current_version = pointer.current_version if pointer is not None else None

    recent_audits = (
        await AuditLog.find_all().sort("-ts").limit(audit_preview_limit).to_list()
    )

    return AdminOverviewSnapshot(
        parent_users=parent_users,
        families=families,
        device_bindings_total=device_bindings_total,
        device_bindings_active=device_bindings_active,
        device_bindings_revoked=device_bindings_revoked,
        global_words=global_words,
        family_pack_definitions=family_pack_definitions,
        global_pack_current_version=global_pack_current_version,
        recent_audits=recent_audits,
    )


def format_audit_timestamp(ts: datetime) -> str:
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=UTC)
    return ts.astimezone(UTC).strftime("%Y-%m-%d %H:%M") + "（UTC）"
