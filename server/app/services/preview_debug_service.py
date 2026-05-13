"""Preview-only debug sessions and request trace capture."""

from __future__ import annotations

import json
import logging
import os
import secrets
import time
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

from fastapi import HTTPException, Request, Response, status
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint

from app.models.debug_session import DebugSession
from app.models.debug_trace import DebugTrace

logger = logging.getLogger("uvicorn.error")

DEBUG_SESSION_HEADER = "x-hw-debug-session"
_REDACTED = "[redacted]"
_SENSITIVE_HEADER_NAMES = {
    "authorization",
    "cookie",
    "set-cookie",
    "x-vercel-protection-bypass",
    "x-hw-debug-secret",
}
_SENSITIVE_KEY_FRAGMENTS = ("token", "secret", "password", "jwt", "api_key", "apikey")


def preview_debug_available() -> bool:
    enabled = os.environ.get("PREVIEW_DEBUG_ENABLED", "").strip().lower()
    vercel_env = os.environ.get("VERCEL_ENV", "").strip().lower()
    return enabled in {"1", "true", "yes", "on"} and vercel_env != "production"


def preview_debug_secret() -> str:
    return os.environ.get("PREVIEW_DEBUG_SECRET", "")


def preview_debug_ttl_minutes() -> int:
    raw = os.environ.get("PREVIEW_DEBUG_TTL_MINUTES", "30")
    try:
        return max(1, min(240, int(raw)))
    except ValueError:
        return 30


def preview_debug_body_limit_bytes() -> int:
    raw = os.environ.get("PREVIEW_DEBUG_BODY_LIMIT_BYTES", "4096")
    try:
        return max(0, min(64_000, int(raw)))
    except ValueError:
        return 4096


def require_preview_debug_enabled() -> None:
    if not preview_debug_available():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not Found")


def require_preview_debug_auth(authorization: str | None) -> None:
    require_preview_debug_enabled()
    expected = preview_debug_secret()
    if not expected:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not Found")
    prefix = "Bearer "
    supplied = authorization or ""
    if not supplied.startswith(prefix):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing debug bearer")
    token = supplied[len(prefix) :].strip()
    if not secrets.compare_digest(token, expected):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Bad debug bearer")


async def create_debug_session(
    *,
    problem: str,
    preview_url: str,
    branch: str | None = None,
    deployment_id: str | None = None,
    created_by: str | None = None,
) -> DebugSession:
    now = datetime.now(tz=UTC)
    session = DebugSession(
        session_id=f"dbg_{uuid.uuid4().hex[:16]}",
        problem=problem.strip(),
        preview_url=preview_url.strip(),
        branch=branch.strip() if branch else None,
        deployment_id=deployment_id.strip() if deployment_id else None,
        created_by=(created_by or "operator").strip() or "operator",
        created_at=now,
        expires_at=now + timedelta(minutes=preview_debug_ttl_minutes()),
        active=True,
    )
    await session.insert()
    return session


async def stop_debug_session(session_id: str) -> DebugSession | None:
    session = await DebugSession.find_one(DebugSession.session_id == session_id)
    if session is None:
        return None
    session.active = False
    session.stopped_at = datetime.now(tz=UTC)
    await session.save()
    return session


async def active_debug_session(session_id: str) -> DebugSession | None:
    now = datetime.now(tz=UTC)
    return await DebugSession.find_one(
        DebugSession.session_id == session_id,
        DebugSession.active == True,  # noqa: E712
        DebugSession.expires_at > now,
    )


def redact_headers(headers: dict[str, str]) -> dict[str, str]:
    out: dict[str, str] = {}
    for key, value in headers.items():
        lower = key.lower()
        if lower in _SENSITIVE_HEADER_NAMES or _looks_sensitive(lower):
            out[lower] = _REDACTED
        else:
            out[lower] = value
    return out


def _looks_sensitive(name: str) -> bool:
    return any(fragment in name for fragment in _SENSITIVE_KEY_FRAGMENTS)


def _redact_json(value: Any) -> Any:
    if isinstance(value, dict):
        out: dict[str, Any] = {}
        for key, item in value.items():
            key_str = str(key)
            out[key_str] = _REDACTED if _looks_sensitive(key_str.lower()) else _redact_json(item)
        return out
    if isinstance(value, list):
        return [_redact_json(item) for item in value]
    return value


def summarize_body(body: bytes, content_type: str | None, limit: int) -> dict[str, Any] | None:
    if not body:
        return None
    media = (content_type or "").split(";")[0].strip().lower()
    if (
        media.startswith("image/")
        or media.startswith("audio/")
        or media == "application/octet-stream"
    ):
        return {"bytes": len(body), "content_type": media or "application/octet-stream"}
    truncated = limit > 0 and len(body) > limit
    sample = body[:limit] if limit > 0 else b""
    try:
        text = sample.decode("utf-8", errors="replace")
    except UnicodeDecodeError:
        return {"bytes": len(body), "content_type": media or "unknown"}
    if media == "application/json" or text.lstrip().startswith(("{", "[")):
        try:
            redacted = _redact_json(json.loads(text))
            return {
                "json": redacted,
                "text": json.dumps(redacted, ensure_ascii=False, separators=(",", ":")),
                "truncated": truncated,
                "bytes": len(body),
            }
        except json.JSONDecodeError:
            pass
    return {"text": text, "truncated": truncated, "bytes": len(body)}


class PreviewDebugTraceMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self,
        request: Request,
        call_next: RequestResponseEndpoint,
    ) -> Response:
        if request.url.path.startswith("/api/v1/debug"):
            return await call_next(request)
        session_id = request.headers.get(DEBUG_SESSION_HEADER, "").strip()
        if not session_id or not preview_debug_available():
            return await call_next(request)
        session = await active_debug_session(session_id)
        if session is None:
            return await call_next(request)

        request_body = await request.body()

        async def receive() -> dict[str, object]:
            return {"type": "http.request", "body": request_body, "more_body": False}

        wrapped_request = Request(request.scope, receive)
        start = time.perf_counter()
        response = await call_next(wrapped_request)
        response_body = b""
        async for chunk in response.body_iterator:
            response_body += chunk
        duration_ms = (time.perf_counter() - start) * 1000

        replacement = Response(
            content=response_body,
            status_code=response.status_code,
            headers=dict(response.headers),
            media_type=response.media_type,
        )
        correlation_id = f"hwdbg_{uuid.uuid4().hex[:16]}"
        trace = DebugTrace(
            session_id=session.session_id,
            correlation_id=correlation_id,
            method=request.method,
            path=request.url.path,
            query=request.url.query,
            status_code=response.status_code,
            duration_ms=round(duration_ms, 2),
            request_headers=redact_headers(dict(request.headers)),
            response_headers=redact_headers(dict(response.headers)),
            request_body=summarize_body(
                request_body,
                request.headers.get("content-type"),
                preview_debug_body_limit_bytes(),
            ),
            response_body=summarize_body(
                response_body,
                response.headers.get("content-type"),
                preview_debug_body_limit_bytes(),
            ),
            ts=datetime.now(tz=UTC),
        )
        try:
            await trace.insert()
            logger.info(
                "HW_PREVIEW_DEBUG_TRACE %s",
                json.dumps(
                    {
                        "session_id": session.session_id,
                        "correlation_id": correlation_id,
                        "method": trace.method,
                        "path": trace.path,
                        "status_code": trace.status_code,
                        "duration_ms": trace.duration_ms,
                    },
                    ensure_ascii=False,
                    sort_keys=True,
                ),
            )
        except Exception as exc:  # pragma: no cover - diagnostics must not break app traffic
            logger.warning("HW_PREVIEW_DEBUG_TRACE_WRITE_FAILED %r", exc)
        replacement.headers["x-hw-debug-correlation"] = correlation_id
        return replacement
