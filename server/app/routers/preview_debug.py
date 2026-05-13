"""Preview-only debug session API for client/server investigations."""

from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Header, HTTPException, status
from pydantic import BaseModel, Field

from app.models.debug_trace import DebugTrace
from app.services import preview_debug_service

router = APIRouter(prefix="/api/v1/debug", tags=["debug"])


class DebugSessionCreateIn(BaseModel):
    problem: str = Field(min_length=1, max_length=1000)
    preview_url: str = Field(min_length=1, max_length=500)
    branch: str | None = Field(default=None, max_length=200)
    deployment_id: str | None = Field(default=None, max_length=120)
    created_by: str | None = Field(default=None, max_length=120)


class DebugSessionOut(BaseModel):
    session_id: str
    problem: str
    preview_url: str
    branch: str | None
    deployment_id: str | None
    created_by: str
    created_at: datetime
    expires_at: datetime
    active: bool
    stopped_at: datetime | None


class DebugTraceOut(BaseModel):
    correlation_id: str
    method: str
    path: str
    query: str
    status_code: int
    duration_ms: float
    request_headers: dict[str, str]
    response_headers: dict[str, str]
    request_body: dict[str, Any] | None
    response_body: dict[str, Any] | None
    ts: datetime


class DebugTraceListOut(BaseModel):
    session_id: str
    traces: list[DebugTraceOut]


def _aware(dt: datetime | None) -> datetime | None:
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=UTC)
    return dt


def _session_out(session: object) -> DebugSessionOut:
    return DebugSessionOut(
        session_id=session.session_id,
        problem=session.problem,
        preview_url=session.preview_url,
        branch=session.branch,
        deployment_id=session.deployment_id,
        created_by=session.created_by,
        created_at=_aware(session.created_at),
        expires_at=_aware(session.expires_at),
        active=session.active,
        stopped_at=_aware(session.stopped_at),
    )


@router.post("/sessions", response_model=DebugSessionOut, status_code=status.HTTP_201_CREATED)
async def create_session(
    payload: DebugSessionCreateIn,
    authorization: str | None = Header(None, alias="Authorization"),
) -> DebugSessionOut:
    preview_debug_service.require_preview_debug_auth(authorization)
    session = await preview_debug_service.create_debug_session(
        problem=payload.problem,
        preview_url=payload.preview_url,
        branch=payload.branch,
        deployment_id=payload.deployment_id,
        created_by=payload.created_by,
    )
    return _session_out(session)


@router.post("/sessions/{session_id}/stop", response_model=DebugSessionOut)
async def stop_session(
    session_id: str,
    authorization: str | None = Header(None, alias="Authorization"),
) -> DebugSessionOut:
    preview_debug_service.require_preview_debug_auth(authorization)
    session = await preview_debug_service.stop_debug_session(session_id)
    if session is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Debug session not found")
    return _session_out(session)


@router.get("/sessions/{session_id}/traces", response_model=DebugTraceListOut)
async def list_traces(
    session_id: str,
    authorization: str | None = Header(None, alias="Authorization"),
    limit: int = 200,
) -> DebugTraceListOut:
    preview_debug_service.require_preview_debug_auth(authorization)
    cap = max(1, min(limit, 1000))
    rows = (
        await DebugTrace.find(DebugTrace.session_id == session_id)
        .sort("+ts")
        .limit(cap)
        .to_list()
    )
    return DebugTraceListOut(
        session_id=session_id,
        traces=[DebugTraceOut.model_validate(row, from_attributes=True) for row in rows],
    )
