"""V0.6.7 — thin write helper for AuditLog.

All sensitive write paths funnel through `record(...)`. The payload
summary is truncated to keep the row small. Failures are logged
but never raised — observability shouldn't break business logic.
"""

from __future__ import annotations

import json
import logging
from datetime import UTC, datetime
from typing import Any

from app.models.audit_log import ActorRole, AuditLog

_log = logging.getLogger(__name__)
MAX_PAYLOAD_BYTES: int = 512


def _truncate_payload(payload: dict[str, Any] | None) -> dict[str, Any] | None:
    if payload is None:
        return None
    try:
        encoded: str = json.dumps(payload, ensure_ascii=False, sort_keys=True)
    except (TypeError, ValueError):
        return None
    if len(encoded.encode("utf-8")) <= MAX_PAYLOAD_BYTES:
        return payload
    truncated: dict[str, Any] = {}
    truncated["_truncated"] = True
    for k, v in payload.items():
        truncated[k] = str(v)[:64]
        try:
            test = json.dumps(truncated, ensure_ascii=False, sort_keys=True)
        except (TypeError, ValueError):
            return {"_truncated": True}
        if len(test.encode("utf-8")) > MAX_PAYLOAD_BYTES:
            truncated.pop(k, None)
            break
    return truncated


async def record(
    *,
    actor_role: ActorRole | str,
    actor_id: str | None,
    action: str,
    target_collection: str | None = None,
    target_id: str | None = None,
    payload_summary: dict[str, Any] | None = None,
) -> None:
    role = actor_role if isinstance(actor_role, ActorRole) else ActorRole(actor_role)
    try:
        await AuditLog(
            actor_role=role,
            actor_id=actor_id,
            action=action,
            target_collection=target_collection,
            target_id=target_id,
            payload_summary=_truncate_payload(payload_summary),
            ts=datetime.now(tz=UTC),
        ).insert()
    except Exception as e:  # noqa: BLE001 — never raise out of audit
        _log.warning("audit_log.record failed: %s", e)
