from datetime import datetime

import pytest
from httpx import AsyncClient


async def test_preview_debug_routes_are_hidden_until_enabled(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("PREVIEW_DEBUG_ENABLED", "false")
    monkeypatch.setenv("PREVIEW_DEBUG_SECRET", "test-debug-secret")

    resp = await client.post(
        "/api/v1/debug/sessions",
        headers={"Authorization": "Bearer test-debug-secret"},
        json={"problem": "cannot sync", "preview_url": "https://example.vercel.app"},
    )

    assert resp.status_code == 404


async def test_preview_debug_session_records_redacted_request_trace(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("PREVIEW_DEBUG_ENABLED", "true")
    monkeypatch.setenv("PREVIEW_DEBUG_SECRET", "test-debug-secret")
    monkeypatch.setenv("PREVIEW_DEBUG_BODY_LIMIT_BYTES", "200")
    monkeypatch.setenv("VERCEL_ENV", "preview")

    created = await client.post(
        "/api/v1/debug/sessions",
        headers={"Authorization": "Bearer test-debug-secret"},
        json={
            "problem": "health probe fails from HarmonyOS",
            "preview_url": "https://happyword-git-debug-terrymas-projects.vercel.app",
            "branch": "codex/debug",
            "deployment_id": "dpl_test",
            "created_by": "pytest",
        },
    )

    assert created.status_code == 201
    payload = created.json()
    session_id = payload["session_id"]
    assert payload["active"] is True
    assert datetime.fromisoformat(payload["expires_at"]).tzinfo is not None

    health = await client.get(
        "/api/v1/health",
        headers={
            "x-hw-debug-session": session_id,
            "Authorization": "Bearer device-token",
            "Cookie": "wm_session=secret-cookie",
            "x-vercel-protection-bypass": "bypass-secret",
        },
    )
    assert health.status_code == 200

    traces = await client.get(
        f"/api/v1/debug/sessions/{session_id}/traces",
        headers={"Authorization": "Bearer test-debug-secret"},
    )

    assert traces.status_code == 200
    rows = traces.json()["traces"]
    assert len(rows) == 1
    row = rows[0]
    assert row["method"] == "GET"
    assert row["path"] == "/api/v1/health"
    assert row["status_code"] == 200
    assert row["request_headers"]["authorization"] == "[redacted]"
    assert row["request_headers"]["cookie"] == "[redacted]"
    assert row["request_headers"]["x-vercel-protection-bypass"] == "[redacted]"
    assert row["response_body"]["truncated"] is False
    assert row["response_body"]["text"].startswith('{"ok":true')

    rejected = await client.post(
        "/api/v1/health",
        headers={"x-hw-debug-session": session_id},
        json={"password": "please-do-not-store", "profile": {"api_key": "openai-secret"}},
    )
    assert rejected.status_code == 405

    traces = await client.get(
        f"/api/v1/debug/sessions/{session_id}/traces",
        headers={"Authorization": "Bearer test-debug-secret"},
    )
    post_row = traces.json()["traces"][1]
    assert post_row["request_body"]["json"]["password"] == "[redacted]"
    assert post_row["request_body"]["json"]["profile"]["api_key"] == "[redacted]"
    assert "please-do-not-store" not in post_row["request_body"]["text"]
    assert "openai-secret" not in post_row["request_body"]["text"]


async def test_preview_debug_session_stop_disables_trace_capture(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("PREVIEW_DEBUG_ENABLED", "true")
    monkeypatch.setenv("PREVIEW_DEBUG_SECRET", "test-debug-secret")
    monkeypatch.setenv("VERCEL_ENV", "preview")

    created = await client.post(
        "/api/v1/debug/sessions",
        headers={"Authorization": "Bearer test-debug-secret"},
        json={"problem": "stop capture", "preview_url": "https://example.vercel.app"},
    )
    session_id = created.json()["session_id"]

    stopped = await client.post(
        f"/api/v1/debug/sessions/{session_id}/stop",
        headers={"Authorization": "Bearer test-debug-secret"},
    )
    assert stopped.status_code == 200
    assert stopped.json()["active"] is False
    assert datetime.fromisoformat(stopped.json()["stopped_at"]).tzinfo is not None

    await client.get("/api/v1/health", headers={"x-hw-debug-session": session_id})
    traces = await client.get(
        f"/api/v1/debug/sessions/{session_id}/traces",
        headers={"Authorization": "Bearer test-debug-secret"},
    )

    assert traces.status_code == 200
    assert traces.json()["traces"] == []


async def test_preview_debug_rejects_production_even_when_enabled(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("PREVIEW_DEBUG_ENABLED", "true")
    monkeypatch.setenv("PREVIEW_DEBUG_SECRET", "test-debug-secret")
    monkeypatch.setenv("VERCEL_ENV", "production")

    resp = await client.post(
        "/api/v1/debug/sessions",
        headers={"Authorization": "Bearer test-debug-secret"},
        json={"problem": "prod should be hidden", "preview_url": "https://happyword.cool"},
    )

    assert resp.status_code == 404
