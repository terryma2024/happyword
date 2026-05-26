"""V0.8.2 — queries and privileged actions for the `/admin/` HTML console."""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any, Literal

from beanie.operators import Or, RegEx

from app.models.audit_log import AuditLog
from app.models.child_profile import ChildProfile
from app.models.device_binding import DeviceBinding
from app.models.family import Family
from app.models.family_pack_definition import FamilyPackDefinition
from app.models.family_pack_draft import FamilyPackDraft
from app.models.pack_pointer import PackPointer
from app.models.user import User, UserRole
from app.services import family_pack_service as fps
from app.services import global_pack_service as gpk_svc
from app.services import pack_service
from app.services.admin_audit_service import record_admin_action

REASON_MIN_LEN = 4


@dataclass(frozen=True)
class AdminFamilyPackCopySummary:
    source_pack_id: str
    source_family_id: str
    target_pack_id: str
    target_family_id: str
    copied_word_count: int
    deleted_source: bool


def validate_reason_text(reason: str | None) -> str:
    r = (reason or "").strip()
    if len(r) < REASON_MIN_LEN:
        raise ValueError("操作说明至少需要 4 个字符。")
    return r


def _regex_contains(pattern: str) -> str:
    return re.escape(pattern)


async def search_parent_users(
    *,
    q: str | None,
    page: int,
    page_size: int,
) -> tuple[list[User], int]:
    skip = max(page - 1, 0) * page_size
    raw = (q or "").strip()
    base = User.role == UserRole.PARENT
    if raw:
        safe = _regex_contains(raw)
        filt = User.find(
            base,
            Or(
                RegEx(User.email, pattern=safe, options="i"),
                RegEx(User.username, pattern=safe, options="i"),
                RegEx(User.family_id, pattern=safe, options="i"),
                RegEx(User.display_name, pattern=safe, options="i"),
            ),
        )
    else:
        filt = User.find(base)
    total = await filt.count()
    rows = await filt.sort("-created_at").skip(skip).limit(page_size).to_list()
    return rows, total


async def load_parent_detail(
    *, username: str
) -> tuple[
    User | None,
    Family | None,
    list[DeviceBinding],
    list[ChildProfile],
    list[FamilyPackDefinition],
]:
    user = await User.find_one(User.username == username, User.role == UserRole.PARENT)
    if user is None:
        return None, None, [], [], []
    family = await Family.find_one(Family.owner_user_id == user.username)
    if family is None:
        return user, None, [], [], []
    bindings = (
        await DeviceBinding.find(DeviceBinding.family_id == family.family_id)
        .sort("-created_at")
        .to_list()
    )
    profiles = await ChildProfile.find(ChildProfile.family_id == family.family_id).to_list()
    packs = (
        await FamilyPackDefinition.find(FamilyPackDefinition.family_id == family.family_id)
        .sort("-updated_at")
        .to_list()
    )
    return user, family, bindings, profiles, packs


async def search_device_bindings(
    *,
    q: str | None,
    page: int,
    page_size: int,
) -> tuple[list[DeviceBinding], int]:
    skip = max(page - 1, 0) * page_size
    raw = (q or "").strip()
    if raw:
        safe = _regex_contains(raw)
        filt = DeviceBinding.find(
            Or(
                RegEx(DeviceBinding.binding_id, pattern=safe, options="i"),
                RegEx(DeviceBinding.device_id, pattern=safe, options="i"),
                RegEx(DeviceBinding.family_id, pattern=safe, options="i"),
                RegEx(DeviceBinding.child_profile_id, pattern=safe, options="i"),
            ),
        )
    else:
        filt = DeviceBinding.find_all()
    total = await filt.count()
    rows = await filt.sort("-created_at").skip(skip).limit(page_size).to_list()
    return rows, total


async def search_family_pack_definitions(
    *,
    q: str | None,
    page: int,
    page_size: int,
) -> tuple[list[FamilyPackDefinition], int]:
    skip = max(page - 1, 0) * page_size
    raw = (q or "").strip()
    and_parts: list[dict[str, Any]] = [
        {"family_id": {"$ne": fps.GLOBAL_PACK_FAMILY_ID}},
    ]
    if raw:
        safe = _regex_contains(raw)
        and_parts.append(
            {
                "$or": [
                    {"pack_id": {"$regex": safe, "$options": "i"}},
                    {"name": {"$regex": safe, "$options": "i"}},
                    {"family_id": {"$regex": safe, "$options": "i"}},
                ]
            }
        )
    match: dict[str, Any] = {"$and": and_parts} if len(and_parts) > 1 else and_parts[0]
    filt = FamilyPackDefinition.find(match)
    total = await filt.count()
    rows = await filt.sort("-updated_at").skip(skip).limit(page_size).to_list()
    return rows, total


async def search_audit_logs(
    *,
    q_action: str | None,
    page: int,
    page_size: int,
) -> tuple[list[AuditLog], int]:
    skip = max(page - 1, 0) * page_size
    raw = (q_action or "").strip()
    if raw:
        safe = _regex_contains(raw)
        filt = AuditLog.find(RegEx(AuditLog.action, pattern=safe, options="i"))
    else:
        filt = AuditLog.find_all()
    total = await filt.count()
    rows = await filt.sort("-ts").skip(skip).limit(page_size).to_list()
    return rows, total


async def load_global_pack_console_context() -> dict[str, Any]:
    pointer = await PackPointer.find_one(PackPointer.singleton_key == "main")
    current = await pack_service.get_current_pack()
    return {
        "pointer": pointer,
        "current_pack": current,
        "current_word_count": len(current.words) if current is not None else 0,
    }


async def list_global_pack_definitions_with_summary(
    *, include_archived: bool = True
) -> list[dict[str, Any]]:
    """Global pack definitions plus draft word counts for the admin table."""
    defs = await gpk_svc.list_definitions(include_archived=include_archived)
    rows: list[dict[str, Any]] = []
    for d in defs:
        draft_doc = await FamilyPackDraft.find_one(
            FamilyPackDraft.pack_definition_id == d.pack_id
        )
        draft_n = len(draft_doc.words) if draft_doc else 0
        rows.append({"definition": d, "draft_word_count": draft_n})
    return rows


async def load_global_pack_definition_console(*, pack_id: str) -> dict[str, Any]:
    try:
        definition = await gpk_svc.get_definition(pack_id=pack_id)
    except gpk_svc.PackNotFound as exc:
        raise LookupError("pack_not_found") from exc
    draft_doc = await FamilyPackDraft.find_one(
        FamilyPackDraft.pack_definition_id == pack_id
    )
    draft_words = list(draft_doc.words) if draft_doc else []
    draft_word_count = len(draft_words)
    ptr, published = await gpk_svc.current_pack(pack_id=pack_id)
    return {
        "definition": definition,
        "draft_words": draft_words,
        "draft_word_count": draft_word_count,
        "pointer": ptr,
        "published_word_count": len(published.words) if published else 0,
        "published_version": published.version if published else None,
    }


# -- mutations -----------------------------------------------------------------


async def admin_suspend_parent(
    *, admin_username: str, parent_username: str, reason: str
) -> None:
    r = validate_reason_text(reason)
    user = await User.find_one(User.username == parent_username, User.role == UserRole.PARENT)
    if user is None:
        raise LookupError("parent_not_found")
    now = datetime.now(tz=UTC)
    user.parent_login_suspended_at = now
    await user.save()
    await record_admin_action(
        admin_username=admin_username,
        action="parent.suspend_login",
        target_collection="users",
        target_id=parent_username,
        payload_summary={"reason": r, "suspended_at": now.isoformat()},
    )


async def admin_restore_parent(
    *, admin_username: str, parent_username: str, reason: str
) -> None:
    r = validate_reason_text(reason)
    user = await User.find_one(User.username == parent_username, User.role == UserRole.PARENT)
    if user is None:
        raise LookupError("parent_not_found")
    before = user.parent_login_suspended_at
    user.parent_login_suspended_at = None
    await user.save()
    await record_admin_action(
        admin_username=admin_username,
        action="parent.restore_login",
        target_collection="users",
        target_id=parent_username,
        payload_summary={"reason": r, "had_suspended_at": before.isoformat() if before else None},
    )


async def admin_revoke_device_binding(
    *, admin_username: str, binding_id: str, reason: str
) -> None:
    r = validate_reason_text(reason)
    binding = await DeviceBinding.find_one(DeviceBinding.binding_id == binding_id)
    if binding is None:
        raise LookupError("binding_not_found")
    if binding.revoked_at is not None:
        await record_admin_action(
            admin_username=admin_username,
            action="device.revoke.idempotent",
            target_collection="device_bindings",
            target_id=binding_id,
            payload_summary={"reason": r, "note": "already_revoked"},
        )
        return
    now = datetime.now(tz=UTC)
    binding.revoked_at = now
    await binding.save()
    await record_admin_action(
        admin_username=admin_username,
        action="device.revoke",
        target_collection="device_bindings",
        target_id=binding_id,
        payload_summary={
            "reason": r,
            "family_id": binding.family_id,
            "device_id": binding.device_id,
            "revoked_at": now.isoformat(),
        },
    )


async def admin_restore_device_binding(
    *, admin_username: str, binding_id: str, reason: str
) -> None:
    r = validate_reason_text(reason)
    binding = await DeviceBinding.find_one(DeviceBinding.binding_id == binding_id)
    if binding is None:
        raise LookupError("binding_not_found")
    if binding.revoked_at is None:
        await record_admin_action(
            admin_username=admin_username,
            action="device.restore.idempotent",
            target_collection="device_bindings",
            target_id=binding_id,
            payload_summary={"reason": r, "note": "already_active"},
        )
        return

    active_for_device = await DeviceBinding.find(
        DeviceBinding.device_id == binding.device_id,
        DeviceBinding.revoked_at == None,  # noqa: E711
    ).to_list()
    conflict = next((b for b in active_for_device if b.binding_id != binding_id), None)
    if conflict is not None:
        raise ValueError("该设备已有有效绑定，请先撤销当前有效绑定后再恢复。")

    before = binding.revoked_at
    now = datetime.now(tz=UTC)
    binding.revoked_at = None
    binding.last_seen_at = now
    await binding.save()

    child = await ChildProfile.find_one(
        ChildProfile.profile_id == binding.child_profile_id,
        ChildProfile.family_id == binding.family_id,
    )
    if child is not None:
        child.binding_id = binding.binding_id
        child.deleted_at = None
        child.updated_at = now
        await child.save()

    await record_admin_action(
        admin_username=admin_username,
        action="device.restore",
        target_collection="device_bindings",
        target_id=binding_id,
        payload_summary={
            "reason": r,
            "family_id": binding.family_id,
            "device_id": binding.device_id,
            "had_revoked_at": before.isoformat() if before else None,
            "restored_at": now.isoformat(),
        },
    )


async def admin_publish_global_pack(
    *,
    admin_username: str,
    notes: str | None,
) -> None:
    notes_clean = (notes or "").strip() or None
    try:
        pack = await pack_service.publish_pack(
            published_by=f"admin:{admin_username}",
            notes=notes_clean,
        )
    except pack_service.PackError as exc:
        raise ValueError(exc.message) from exc
    await record_admin_action(
        admin_username=admin_username,
        action="global_pack.publish",
        target_collection="word_pack",
        target_id=str(pack.version),
        payload_summary={"notes": notes_clean, "word_count": len(pack.words)},
    )


async def admin_rollback_global_pack(*, admin_username: str, reason: str) -> None:
    r = validate_reason_text(reason)
    try:
        ptr = await pack_service.rollback_pack()
    except pack_service.PackError as exc:
        raise ValueError(exc.message) from exc
    await record_admin_action(
        admin_username=admin_username,
        action="global_pack.rollback",
        target_collection="pack_pointer",
        target_id="main",
        payload_summary={
            "reason": r,
            "current_version": ptr.current_version,
            "previous_version": ptr.previous_version,
        },
    )


async def admin_create_global_pack_definition(
    *,
    admin_username: str,
    name: str,
    description: str | None,
    pack_id: str | None,
) -> FamilyPackDefinition:
    name_clean = name.strip()
    if not name_clean:
        raise ValueError("名称不能为空。")
    pid = (pack_id or "").strip() or None
    try:
        d = await gpk_svc.create_definition(
            name=name_clean,
            admin_id=admin_username,
            description=(description or "").strip() or None,
            pack_id=pid,
        )
    except gpk_svc.NameTaken as exc:
        raise ValueError(str(exc)) from exc
    except gpk_svc.InvalidPayload as exc:
        raise ValueError(str(exc)) from exc
    await record_admin_action(
        admin_username=admin_username,
        action="global_pack.definition_create",
        target_collection="family_pack_definitions",
        target_id=d.pack_id,
        payload_summary={"name": d.name},
    )
    return d


async def admin_publish_global_pack_definition(
    *,
    admin_username: str,
    pack_id: str,
    notes: str | None,
) -> None:
    notes_clean = (notes or "").strip() or None
    try:
        pack = await gpk_svc.publish(
            pack_id=pack_id,
            admin_id=admin_username,
            notes=notes_clean,
        )
    except gpk_svc.PackNotFound as exc:
        raise LookupError("pack_not_found") from exc
    except gpk_svc.EmptyPack as exc:
        raise ValueError(str(exc)) from exc
    except gpk_svc.WordLimitExceeded as exc:
        raise ValueError(str(exc)) from exc
    await record_admin_action(
        admin_username=admin_username,
        action="global_pack.definition_publish",
        target_collection="family_pack_definitions",
        target_id=pack_id,
        payload_summary={
            "notes": notes_clean,
            "version": pack.version,
            "word_count": len(pack.words),
        },
    )


async def admin_rollback_global_pack_definition(
    *, admin_username: str, pack_id: str, reason: str
) -> None:
    r = validate_reason_text(reason)
    try:
        ptr = await gpk_svc.rollback(pack_id=pack_id)
    except gpk_svc.PackNotFound as exc:
        raise LookupError("pack_not_found") from exc
    except gpk_svc.NoPreviousVersion as exc:
        raise ValueError(str(exc)) from exc
    await record_admin_action(
        admin_username=admin_username,
        action="global_pack.definition_rollback",
        target_collection="family_pack_definitions",
        target_id=pack_id,
        payload_summary={
            "reason": r,
            "current_version": ptr.current_version,
            "previous_version": ptr.previous_version,
        },
    )


async def admin_delete_global_pack_definition(
    *, admin_username: str, pack_id: str, reason: str
) -> gpk_svc.GlobalPackDeleteSummary:
    r = validate_reason_text(reason)
    try:
        summary = await gpk_svc.delete_definition(pack_id=pack_id)
    except gpk_svc.PackNotFound as exc:
        raise LookupError("pack_not_found") from exc
    await record_admin_action(
        admin_username=admin_username,
        action="global_pack.definition_delete",
        target_collection="family_pack_definitions",
        target_id=pack_id,
        payload_summary={"reason": r, **summary.__dict__},
    )
    return summary


async def _next_copy_name(*, base_name: str, target_family_id: str) -> str:
    root = base_name.strip() or "Copied pack"
    candidates = [root, f"{root} (copy)"]
    for n in range(2, 101):
        candidates.append(f"{root} (copy {n})")
    for candidate in candidates:
        existing = await FamilyPackDefinition.find(
            FamilyPackDefinition.family_id == target_family_id,
            FamilyPackDefinition.name == candidate,
        ).first_or_none()
        if existing is None:
            return candidate
    raise ValueError("目标范围内同名词包过多，请先重命名后再复制。")


async def admin_family_pack_copy(
    *,
    admin_username: str,
    source_pack_id: str,
    target_kind: Literal["global", "family"],
    target_family_id: str | None,
    delete_source: bool,
    reason: str,
) -> AdminFamilyPackCopySummary:
    r = validate_reason_text(reason)
    source = await FamilyPackDefinition.find_one(
        FamilyPackDefinition.pack_id == source_pack_id
    )
    if source is None:
        raise LookupError("pack_not_found")
    if source.family_id == fps.GLOBAL_PACK_FAMILY_ID:
        raise ValueError("请通过「全局词库」页面管理官方全局词包。")

    if target_kind == "global":
        resolved_target_family_id = fps.GLOBAL_PACK_FAMILY_ID
    elif target_kind == "family":
        fid = (target_family_id or "").strip()
        if not fid:
            raise ValueError("目标 family_id 不能为空。")
        if fid == source.family_id:
            raise ValueError("请选择另外一个 family 作为复制目标。")
        target_family = await Family.find_one(Family.family_id == fid)
        if target_family is None:
            raise ValueError("未找到目标 family。")
        resolved_target_family_id = fid
    else:
        raise ValueError("未知复制目标。")

    target_name = await _next_copy_name(
        base_name=source.name,
        target_family_id=resolved_target_family_id,
    )
    source_draft = await FamilyPackDraft.find_one(
        FamilyPackDraft.pack_definition_id == source.pack_id,
        FamilyPackDraft.family_id == source.family_id,
    )
    copied_words = [dict(word) for word in source_draft.words] if source_draft else []

    if target_kind == "global":
        target = await gpk_svc.create_definition(
            name=target_name,
            admin_id=admin_username,
            description=source.description,
            scene=dict(source.scene),
        )
    else:
        target = await fps.create_definition(
            family_id=resolved_target_family_id,
            name=target_name,
            description=source.description,
            scene=dict(source.scene),
            parent_user_id=f"admin:{admin_username}",
        )

    now = datetime.now(tz=UTC)
    target_draft = FamilyPackDraft(
        pack_definition_id=target.pack_id,
        family_id=target.family_id,
        words=copied_words,
        updated_at=now,
        updated_by_parent_id=f"admin:{admin_username}",
    )
    await target_draft.insert()
    target.updated_at = now
    await target.save()

    if delete_source:
        await fps.delete_definition(pack_id=source.pack_id, family_id=source.family_id)

    summary = AdminFamilyPackCopySummary(
        source_pack_id=source.pack_id,
        source_family_id=source.family_id,
        target_pack_id=target.pack_id,
        target_family_id=target.family_id,
        copied_word_count=len(copied_words),
        deleted_source=delete_source,
    )
    await record_admin_action(
        admin_username=admin_username,
        action=(
            "family_pack.copy_to_global"
            if target_kind == "global"
            else "family_pack.copy_to_family"
        ),
        target_collection="family_pack_definitions",
        target_id=source.pack_id,
        payload_summary={"reason": r, **summary.__dict__},
    )
    return summary


async def admin_family_pack_unarchive(
    *, admin_username: str, pack_id: str, reason: str
) -> None:
    r = validate_reason_text(reason)
    definition = await FamilyPackDefinition.find_one(FamilyPackDefinition.pack_id == pack_id)
    if definition is None:
        raise LookupError("pack_not_found")
    if definition.family_id == fps.GLOBAL_PACK_FAMILY_ID:
        raise ValueError("请通过「全局词库」页面管理官方全局词包。")
    try:
        await fps.unarchive(pack_id=pack_id, family_id=definition.family_id)
    except fps.NameTaken as exc:
        raise ValueError(
            "与其他活跃词包名称冲突，家长需先在后台改名后再恢复。"
        ) from exc
    await record_admin_action(
        admin_username=admin_username,
        action="family_pack.unarchive",
        target_collection="family_pack_definitions",
        target_id=pack_id,
        payload_summary={"reason": r, "family_id": definition.family_id},
    )


async def admin_family_pack_rollback(
    *, admin_username: str, pack_id: str, reason: str
) -> None:
    r = validate_reason_text(reason)
    definition = await FamilyPackDefinition.find_one(FamilyPackDefinition.pack_id == pack_id)
    if definition is None:
        raise LookupError("pack_not_found")
    if definition.family_id == fps.GLOBAL_PACK_FAMILY_ID:
        raise ValueError("请通过「全局词库」页面执行全局词包回滚。")
    try:
        ptr = await fps.rollback(definition=definition)
    except fps.NoPreviousVersion as exc:
        raise ValueError("没有可回滚的历史版本。") from exc
    await record_admin_action(
        admin_username=admin_username,
        action="family_pack.rollback",
        target_collection="family_pack_definitions",
        target_id=pack_id,
        payload_summary={
            "reason": r,
            "family_id": definition.family_id,
            "pointer_current": ptr.current_version,
            "pointer_previous": ptr.previous_version,
        },
    )


async def admin_family_pack_delete(
    *, admin_username: str, pack_id: str, reason: str
) -> fps.FamilyPackDeleteSummary:
    r = validate_reason_text(reason)
    definition = await FamilyPackDefinition.find_one(FamilyPackDefinition.pack_id == pack_id)
    if definition is None:
        raise LookupError("pack_not_found")
    if definition.family_id == fps.GLOBAL_PACK_FAMILY_ID:
        raise ValueError("请通过「全局词库」页面删除官方全局词包。")
    try:
        summary = await fps.delete_definition(
            pack_id=pack_id,
            family_id=definition.family_id,
        )
    except fps.PackNotFound as exc:
        raise LookupError("pack_not_found") from exc
    await record_admin_action(
        admin_username=admin_username,
        action="family_pack.definition_delete",
        target_collection="family_pack_definitions",
        target_id=pack_id,
        payload_summary={
            "reason": r,
            "family_id": definition.family_id,
            **summary.__dict__,
        },
    )
    return summary
