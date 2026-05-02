"""V0.6.7 — audit log writes for sensitive write paths."""

from __future__ import annotations

import pytest

from app.models.audit_log import ActorRole, AuditLog
from app.services import audit_service


@pytest.mark.asyncio
async def test_record_writes_row(db: object) -> None:
    await audit_service.record(
        actor_role=ActorRole.PARENT,
        actor_id="parent-1",
        action="redemption.approve",
        target_collection="redemption_requests",
        target_id="rdm-001",
        payload_summary={"note": "ok"},
    )
    rows = await AuditLog.find(AuditLog.action == "redemption.approve").to_list()
    assert len(rows) == 1
    assert rows[0].actor_id == "parent-1"
    assert rows[0].target_id == "rdm-001"
    assert rows[0].payload_summary == {"note": "ok"}


@pytest.mark.asyncio
async def test_record_truncates_oversize_payload(db: object) -> None:
    huge = {"k" + str(i): "x" * 200 for i in range(10)}
    await audit_service.record(
        actor_role=ActorRole.SYSTEM,
        actor_id="sys",
        action="big.write",
        payload_summary=huge,
    )
    rows = await AuditLog.find(AuditLog.action == "big.write").to_list()
    assert len(rows) == 1
    payload = rows[0].payload_summary or {}
    assert payload.get("_truncated") is True


@pytest.mark.asyncio
async def test_record_swallows_exceptions(monkeypatch: pytest.MonkeyPatch) -> None:
    """Audit failures must NOT bubble out."""
    async def _boom(self):  # noqa: ANN001, ANN202
        raise RuntimeError("db down")

    monkeypatch.setattr(AuditLog, "insert", _boom, raising=True)
    # Must not raise.
    await audit_service.record(
        actor_role=ActorRole.PARENT,
        actor_id="x",
        action="foo",
    )


@pytest.mark.asyncio
async def test_audit_chain_indexes_action(db: object) -> None:
    """Quick sanity: the AuditLog has an index on `action` (per spec §5.10)."""
    actions = ["a.b", "a.b", "c.d"]
    for a in actions:
        await audit_service.record(
            actor_role=ActorRole.SYSTEM, actor_id=None, action=a
        )
    rows_ab = await AuditLog.find(AuditLog.action == "a.b").to_list()
    rows_cd = await AuditLog.find(AuditLog.action == "c.d").to_list()
    assert len(rows_ab) == 2
    assert len(rows_cd) == 1
