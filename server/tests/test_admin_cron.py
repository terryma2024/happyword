"""V0.7 — GET/POST /api/v1/admin/cron/extract-pending behaviour contract.

This is the second half of the async lesson-import refactor. The
import endpoint (`tests/test_admin_lessons.py`) now creates drafts
in `status="extracting"` without calling OpenAI; this cron route is
the worker that picks those up and runs the slow LLM extraction.

Behaviour we pin:

1. **Auth** — without a matching `Authorization: Bearer $CRON_SECRET`
   header the route returns 401 and the LLM is not called. Vercel
   cron schedules use ``GET`` and attach this header automatically (see
   ``server/vercel.json``), and an unauthenticated public hit must never
   be able to drain the queue / spam OpenAI.
2. **Success path** — exactly one `extracting` draft gets claimed,
   the LLM seam returns a payload, and the draft flips to `pending`
   with `extracted` + `model` populated and `extract_attempts==1`.
3. **Failure path (transient)** — `LlmCallError` increments
   `extract_attempts`, records `extract_last_error_*`, and **leaves**
   status as `extracting` so the next cron tick retries.
4. **Failure path (terminal)** — once attempts reach
   `MAX_EXTRACT_ATTEMPTS`, the draft flips to `extract_failed` and
   subsequent cron ticks no longer re-claim it.
5. **Config error** — `LlmConfigError` is treated as terminal
   (status flips to `extract_failed` immediately): re-attempting
   without operator action would just keep losing OpenAI quota /
   spamming logs.
6. **No-op** — when no drafts are in `extracting` the route returns
   `{"claimed": 0, ...}` and does not touch the LLM.
7. **FIFO** — drafts with fewer attempts are claimed first, then
   the oldest by `created_at`. This guards against a poison-pill
   draft starving fresh ones out.
"""

from datetime import UTC, datetime
from typing import TYPE_CHECKING

import pytest

from app.models.lesson_import_draft import LessonImportDraft
from app.services.llm_service import LlmCallError, LlmConfigError

if TYPE_CHECKING:
    from httpx import AsyncClient


_CRON_SECRET = "test-cron-secret-please-change"
_CRON_PATH = "/api/v1/admin/cron/extract-pending"


_FIXED_EXTRACTED: dict[str, object] = {
    "category_id": "cron-test",
    "label_en": "Cron Test",
    "label_zh": "定时任务测试",
    "story_zh": "故事……",
    "words": [{"word": "alpha", "meaningZh": "甲", "difficulty": 1}],
}


@pytest.fixture(autouse=True)
def _set_cron_secret(monkeypatch: pytest.MonkeyPatch) -> None:
    """Cron auth comparison reads `CRON_SECRET` directly from env, not
    via `Settings`, because adding a typed setting purely for one
    runtime-only secret is overkill. The router uses
    `os.environ.get("CRON_SECRET")` (see app/routers/admin_cron.py)."""
    monkeypatch.setenv("CRON_SECRET", _CRON_SECRET)


def _bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _stub_extractor_returns(monkeypatch: pytest.MonkeyPatch, payload: dict[str, object]) -> None:
    from app.services import lesson_service

    async def _fake(image_bytes: bytes, mime: str) -> tuple[str, dict[str, object]]:
        assert image_bytes == b"\xff\xd8\xff\xe0fakejpg"
        assert mime == "image/jpeg"
        return "gpt-4o-stub", payload

    monkeypatch.setattr(lesson_service, "extract_lesson_payload", _fake)


def _stub_extractor_raises(monkeypatch: pytest.MonkeyPatch, exc: BaseException) -> None:
    from app.services import lesson_service

    async def _explode(image_bytes: bytes, mime: str) -> tuple[str, dict[str, object]]:
        raise exc

    monkeypatch.setattr(lesson_service, "extract_lesson_payload", _explode)


def _stub_blob_fetch(
    monkeypatch: pytest.MonkeyPatch,
    payload: bytes = b"\xff\xd8\xff\xe0fakejpg",
) -> None:
    """The cron router needs the image bytes to send to OpenAI again; in
    production it re-downloads from `draft.source_image_url`. In tests
    we stub `lesson_service.fetch_lesson_image` so the cron path stays
    network-free."""
    from app.services import lesson_service

    async def _fake(url: str) -> tuple[bytes, str]:
        assert url == "stub://lessons/cron.jpg"
        return payload, "image/jpeg"

    monkeypatch.setattr(lesson_service, "fetch_lesson_image", _fake)


async def _seed_extracting_draft(*, attempts: int = 0) -> LessonImportDraft:
    draft = LessonImportDraft(
        source_image_url="stub://lessons/cron.jpg",
        extracted=None,
        status="extracting",
        extract_attempts=attempts,
        prompt_version=1,
    )
    await draft.insert()
    return draft


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_cron_extract_rejects_missing_auth(
    client: "AsyncClient", db: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob_fetch(monkeypatch)
    _stub_extractor_returns(monkeypatch, _FIXED_EXTRACTED)
    await _seed_extracting_draft()

    resp = await client.post(_CRON_PATH)
    assert resp.status_code == 401, resp.text


@pytest.mark.asyncio
async def test_cron_extract_rejects_wrong_secret(
    client: "AsyncClient", db: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob_fetch(monkeypatch)
    _stub_extractor_returns(monkeypatch, _FIXED_EXTRACTED)
    await _seed_extracting_draft()

    resp = await client.post(_CRON_PATH, headers=_bearer("not-the-secret"))
    assert resp.status_code == 401, resp.text


@pytest.mark.asyncio
async def test_cron_extract_rejects_when_secret_unset(
    client: "AsyncClient", db: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Failing-closed: if the operator forgets to set CRON_SECRET in the
    environment, the route must reject every request rather than
    accepting a literal-empty bearer."""
    monkeypatch.delenv("CRON_SECRET", raising=False)
    _stub_blob_fetch(monkeypatch)
    _stub_extractor_returns(monkeypatch, _FIXED_EXTRACTED)
    await _seed_extracting_draft()

    resp = await client.post(_CRON_PATH, headers=_bearer(""))
    assert resp.status_code == 401, resp.text
    resp2 = await client.post(_CRON_PATH, headers=_bearer(_CRON_SECRET))
    assert resp2.status_code == 401, resp2.text


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_cron_extract_success_flips_to_pending(
    client: "AsyncClient", db: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob_fetch(monkeypatch)
    _stub_extractor_returns(monkeypatch, _FIXED_EXTRACTED)
    draft = await _seed_extracting_draft()

    resp = await client.post(_CRON_PATH, headers=_bearer(_CRON_SECRET))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["claimed"] == 1
    assert body["succeeded"] == 1
    assert body["failed"] == 0

    refreshed = await LessonImportDraft.get(draft.id)
    assert refreshed is not None
    assert refreshed.status == "pending"
    assert refreshed.model == "gpt-4o-stub"
    assert refreshed.extracted is not None
    assert refreshed.extracted["category_id"] == "cron-test"
    assert refreshed.extract_attempts == 1
    assert refreshed.extract_last_error_code is None
    assert refreshed.extract_last_error_message is None
    assert refreshed.extract_last_attempted_at is not None


# ---------------------------------------------------------------------------
# Transient failure
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_cron_extract_transient_failure_increments_and_keeps_extracting(
    client: "AsyncClient", db: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    _stub_blob_fetch(monkeypatch)
    _stub_extractor_raises(monkeypatch, LlmCallError("upstream HTTP 502 from OpenAI"))
    draft = await _seed_extracting_draft(attempts=0)

    resp = await client.post(_CRON_PATH, headers=_bearer(_CRON_SECRET))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["claimed"] == 1
    assert body["succeeded"] == 0
    assert body["failed"] == 1

    refreshed = await LessonImportDraft.get(draft.id)
    assert refreshed is not None
    # First failure: still re-claimable on the next tick.
    assert refreshed.status == "extracting"
    assert refreshed.extract_attempts == 1
    assert refreshed.extract_last_error_code == "LLM_CALL_FAILED"
    assert refreshed.extract_last_error_message is not None
    assert "OpenAI" in refreshed.extract_last_error_message
    assert refreshed.extract_last_error_traceback is not None


@pytest.mark.asyncio
async def test_cron_extract_terminal_failure_after_max_attempts(
    client: "AsyncClient", db: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Seed a draft that has already failed twice, then run a tick whose
    LLM call also fails. Total attempts hit MAX_EXTRACT_ATTEMPTS=3 and
    the draft must flip to `extract_failed`.

    Pinning MAX=3 here means the test will fail loudly if someone
    quietly bumps the cap; flagging that is the point."""
    from app.routers import admin_cron as cron_router

    _stub_blob_fetch(monkeypatch)
    _stub_extractor_raises(monkeypatch, LlmCallError("upstream still 502"))
    draft = await _seed_extracting_draft(attempts=cron_router.MAX_EXTRACT_ATTEMPTS - 1)

    resp = await client.post(_CRON_PATH, headers=_bearer(_CRON_SECRET))
    assert resp.status_code == 200, resp.text

    refreshed = await LessonImportDraft.get(draft.id)
    assert refreshed is not None
    assert refreshed.extract_attempts == cron_router.MAX_EXTRACT_ATTEMPTS
    assert refreshed.status == "extract_failed"
    # Subsequent tick must NOT re-claim a terminal draft.
    resp2 = await client.post(_CRON_PATH, headers=_bearer(_CRON_SECRET))
    body2 = resp2.json()
    assert body2["claimed"] == 0


@pytest.mark.asyncio
async def test_cron_extract_config_error_is_terminal(
    client: "AsyncClient", db: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    """`LlmConfigError` means the operator hasn't wired up
    `OPENAI_API_KEY`; retrying on every scheduled tick would just spam logs and
    waste cron budget. Treat as terminal so the failed draft surfaces
    in the parent admin UI immediately."""
    _stub_blob_fetch(monkeypatch)
    _stub_extractor_raises(monkeypatch, LlmConfigError("OPENAI_API_KEY is not configured"))
    draft = await _seed_extracting_draft(attempts=0)

    resp = await client.post(_CRON_PATH, headers=_bearer(_CRON_SECRET))
    assert resp.status_code == 200, resp.text

    refreshed = await LessonImportDraft.get(draft.id)
    assert refreshed is not None
    assert refreshed.status == "extract_failed"
    assert refreshed.extract_last_error_code == "LLM_NOT_CONFIGURED"


# ---------------------------------------------------------------------------
# No-op + FIFO
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_cron_extract_noop_when_nothing_pending(
    client: "AsyncClient", db: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    """No `extracting` drafts → no LLM call, no DB write, returns
    `claimed=0`. The tripwire below ensures the seam is never touched."""
    from app.services import lesson_service

    async def _explode(image_bytes: bytes, mime: str) -> tuple[str, dict[str, object]]:
        msg = "extract_lesson_payload was called when no drafts were pending"
        raise AssertionError(msg)

    async def _explode_fetch(url: str) -> tuple[bytes, str]:
        msg = "fetch_lesson_image was called when no drafts were pending"
        raise AssertionError(msg)

    monkeypatch.setattr(lesson_service, "extract_lesson_payload", _explode)
    monkeypatch.setattr(lesson_service, "fetch_lesson_image", _explode_fetch)

    resp = await client.post(_CRON_PATH, headers=_bearer(_CRON_SECRET))
    assert resp.status_code == 200, resp.text
    assert resp.json() == {"claimed": 0, "succeeded": 0, "failed": 0}


@pytest.mark.asyncio
async def test_cron_extract_accepts_get_for_vercel_cron(
    client: "AsyncClient", db: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Vercel Cron invokes the configured URL with GET; POST remains for
    manual triggers and tests."""
    from app.services import lesson_service

    async def _explode(image_bytes: bytes, mime: str) -> tuple[str, dict[str, object]]:
        msg = "extract_lesson_payload was called when no drafts were pending"
        raise AssertionError(msg)

    async def _explode_fetch(url: str) -> tuple[bytes, str]:
        msg = "fetch_lesson_image was called when no drafts were pending"
        raise AssertionError(msg)

    monkeypatch.setattr(lesson_service, "extract_lesson_payload", _explode)
    monkeypatch.setattr(lesson_service, "fetch_lesson_image", _explode_fetch)

    resp = await client.get(_CRON_PATH, headers=_bearer(_CRON_SECRET))
    assert resp.status_code == 200, resp.text
    assert resp.json() == {"claimed": 0, "succeeded": 0, "failed": 0}


@pytest.mark.asyncio
async def test_cron_extract_picks_never_attempted_first(
    client: "AsyncClient", db: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Two extracting drafts: one already attempted twice and recently
    failed, one fresh. The fresh draft (extract_attempts=0) wins,
    because (a) starvation guard and (b) the previous failure already
    waited at least one cron tick."""
    _stub_blob_fetch(monkeypatch)
    _stub_extractor_returns(monkeypatch, _FIXED_EXTRACTED)

    older_with_attempts = LessonImportDraft(
        source_image_url="stub://lessons/cron.jpg",
        extracted=None,
        status="extracting",
        extract_attempts=2,
        prompt_version=1,
        created_at=datetime(2024, 1, 1, tzinfo=UTC),
    )
    await older_with_attempts.insert()
    fresh = LessonImportDraft(
        source_image_url="stub://lessons/cron.jpg",
        extracted=None,
        status="extracting",
        extract_attempts=0,
        prompt_version=1,
        created_at=datetime(2024, 6, 1, tzinfo=UTC),
    )
    await fresh.insert()

    resp = await client.post(_CRON_PATH, headers=_bearer(_CRON_SECRET))
    assert resp.status_code == 200, resp.text
    assert resp.json()["claimed"] == 1

    fresh_after = await LessonImportDraft.get(fresh.id)
    older_after = await LessonImportDraft.get(older_with_attempts.id)
    assert fresh_after is not None and older_after is not None
    assert fresh_after.status == "pending"
    assert older_after.status == "extracting"
