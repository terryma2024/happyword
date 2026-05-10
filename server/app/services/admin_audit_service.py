"""V0.8.2 — append-only audit records for system administrator HTML actions."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from app.models.audit_log import ActorRole, AuditLog


async def record_admin_action(
    *,
    admin_username: str,
    action: str,
    target_collection: str | None = None,
    target_id: str | None = None,
    payload_summary: dict[str, Any] | None = None,
) -> None:
    """Persist one audit row; reason + outcomes live under payload_summary."""
    await AuditLog(
        actor_role=ActorRole.ADMIN,
        actor_id=admin_username,
        action=action,
        target_collection=target_collection,
        target_id=target_id,
        payload_summary=payload_summary,
        ts=datetime.now(tz=UTC),
    ).insert()
