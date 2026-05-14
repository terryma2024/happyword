"""V0.7 — Vercel cron worker for async lesson-import extraction.

Why this exists
===============

The synchronous import flow (V0.5.5–V0.6.x) called the OpenAI vision
API inside the request handler. That worked on a real Huawei device
but failed reliably on the HarmonyOS simulator: QEMU's user-mode NAT
drops idle TCP flows after ~900ms, OpenAI vision routinely takes
8–15s, so the connection died mid-request and the user saw
`网络异常，请检查重试` even though the upload itself had landed.
Streaming / heartbeat workarounds (`e50cf97`, `3101fb3`, `a4af3c0`)
were defeated by Vercel's own ~5s response buffering, so V0.7 splits
the flow:

  1. ``POST /api/v1/family/{family_id}/lessons/import`` — fast path. Uploads the
     image to Blob, inserts a draft in ``status="extracting"``,
     returns immediately.
  2. **This router** — runs on the scheduled Vercel cron (``GET`` or
     ``POST`` to the same path; Vercel's cron runner uses ``GET``),
     claims one ``extracting`` draft, calls ``extract_lesson_payload``, and
     either flips the draft to ``pending`` (待复核) or records a
     structured error and (after ``MAX_EXTRACT_ATTEMPTS`` failures)
     ``extract_failed``.

Auth
====

The route reads ``CRON_SECRET`` from the environment and rejects any
request whose ``Authorization: Bearer ...`` header doesn't match.
Vercel's cron infrastructure attaches that header automatically when
``vercel.json`` declares the cron path; without it, an attacker
hitting this URL could drain the queue and cost us OpenAI quota.

Behaviour summary (matches `tests/test_admin_cron.py`):

* ``LlmConfigError`` → terminal (``extract_failed``); operator
  needs to wire ``OPENAI_API_KEY`` before retries make sense.
* ``LlmCallError`` (or any other downstream failure) → transient.
  Increment ``extract_attempts``; if it reaches
  ``MAX_EXTRACT_ATTEMPTS`` flip to ``extract_failed``, otherwise
  leave the row in ``extracting`` so the next tick retries.
* No ``extracting`` draft to claim → return ``claimed=0`` and do
  not call the LLM (or the blob fetch).
* Process at most one draft per tick. Keeping each tick bounded avoids
  blowing through the 60s function timeout when OpenAI is slow.
"""

from __future__ import annotations

import logging
import os
import secrets
import traceback
from datetime import UTC, datetime

from fastapi import APIRouter, Header, HTTPException, status

from app.models.lesson_import_draft import LessonImportDraft
from app.services import lesson_service
from app.services.llm_service import LlmConfigError

logger = logging.getLogger("uvicorn.error")

router = APIRouter(prefix="/api/v1/admin/cron", tags=["admin-cron"])


# Cap on extraction retries before a draft flips to `extract_failed`.
# Three attempts ≈ three scheduled ticks of cron coverage for a transient
# upstream blip; beyond that the failure is almost certainly
# structural (bad image, prompt regression, persistent OpenAI 5xx)
# and surfacing it to the operator beats burning more quota.
MAX_EXTRACT_ATTEMPTS = 3

# Truncation caps for the persisted error fields. Mongo rows live for
# weeks; without a cap a single 50 KiB OpenAI traceback could bloat
# the listing endpoint and the parent admin UI. The message gets
# rendered to the user verbatim so it's tighter; the traceback is
# operator-only so it can carry more context.
_ERROR_MESSAGE_MAX = 1024
_ERROR_TRACEBACK_MAX = 4096


def _truncate(value: str, limit: int) -> str:
    if len(value) <= limit:
        return value
    return value[: limit - 1] + "…"


def _verify_cron_auth(authorization: str | None) -> None:
    """Constant-time compare of `Authorization: Bearer ...` against
    `CRON_SECRET`. Fails closed: missing-or-empty `CRON_SECRET` env
    causes every request to reject with 401, matching the behaviour
    pinned by `test_cron_extract_rejects_when_secret_unset`."""
    expected = os.environ.get("CRON_SECRET", "").strip()
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={
                "error": {
                    "code": "CRON_SECRET_NOT_CONFIGURED",
                    "message": "CRON_SECRET is not set on this server instance.",
                }
            },
        )
    if authorization is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Missing Authorization header")
    expected_header = f"Bearer {expected}"
    if not secrets.compare_digest(authorization, expected_header):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Bad Authorization header")


async def _claim_next_extracting() -> LessonImportDraft | None:
    """Pick the most-deserving ``extracting`` draft.

    Ordering: ascending ``extract_attempts`` then ascending
    ``created_at``. That way a poison-pill draft (one that keeps
    raising ``LlmCallError``) cannot starve fresh uploads — every new
    arrival has ``extract_attempts=0`` and jumps the queue. The
    poisoned draft still gets retried during quiet periods, until it
    either succeeds or hits ``MAX_EXTRACT_ATTEMPTS``.
    """
    # Pass field names as strings rather than class attributes because
    # Beanie's `.sort` typing only accepts `str | tuple[str, SortDirection] |
    # list[tuple[str, SortDirection]]` — passing the descriptor objects
    # works at runtime but mypy refuses it.
    return (
        await LessonImportDraft.find(LessonImportDraft.status == "extracting")
        .sort("+extract_attempts", "+created_at")
        .first_or_none()
    )


async def _record_failure(
    draft: LessonImportDraft,
    *,
    error_code: str,
    exc: BaseException,
    terminal: bool,
) -> None:
    """Persist a structured failure record on the draft.

    `terminal=True` flips the draft to `extract_failed` regardless of
    `extract_attempts`. We use it for `LlmConfigError` (operator
    misconfig — retrying is futile) and for the final attempt of the
    transient-failure ladder.

    The traceback is captured even on terminal failures so the
    operator can reach the original stack from the Mongo row alone.
    """
    draft.extract_last_error_code = error_code
    msg = str(exc) or exc.__class__.__name__
    draft.extract_last_error_message = _truncate(msg, _ERROR_MESSAGE_MAX)
    tb = "".join(traceback.format_exception(type(exc), exc, exc.__traceback__))
    draft.extract_last_error_traceback = _truncate(tb, _ERROR_TRACEBACK_MAX)
    if terminal:
        draft.status = "extract_failed"
    await draft.save()


@router.get(
    "/extract-pending",
    status_code=status.HTTP_200_OK,
    operation_id="admin_cron_extract_pending_get",
)
@router.post(
    "/extract-pending",
    status_code=status.HTTP_200_OK,
    operation_id="admin_cron_extract_pending_post",
)
async def extract_pending(
    authorization: str | None = Header(None),
) -> dict[str, int]:
    """Claim and process at most one ``extracting`` draft.

    Returns a tiny summary so cron logs in Vercel show whether
    anything was done on this tick:

        {"claimed": 0|1, "succeeded": 0|1, "failed": 0|1}

    The numbers are 0/1 today because we cap at one draft per tick;
    if we ever lift that cap they widen naturally.
    """
    _verify_cron_auth(authorization)

    draft = await _claim_next_extracting()
    if draft is None:
        return {"claimed": 0, "succeeded": 0, "failed": 0}

    # Bump the attempt counter + timestamp before the LLM call so that
    # if the function is killed mid-call we never come back and treat
    # this as a "first attempt" again. (Beanie autosaves are cheap;
    # the cron tick already cost us a roundtrip to Mongo on the claim.)
    draft.extract_attempts += 1
    draft.extract_last_attempted_at = datetime.now(tz=UTC)
    await draft.save()

    try:
        image_bytes, mime = await lesson_service.fetch_lesson_image(draft.source_image_url)
        model_name, extracted = await lesson_service.extract_lesson_payload(image_bytes, mime)
    except LlmConfigError as exc:
        # Operator hasn't set OPENAI_API_KEY (or equivalent). Retrying
        # on every scheduled tick would spam logs and waste quota; mark the row
        # terminal so the parent admin UI shows it immediately.
        logger.warning("Cron extract: LlmConfigError on draft %s: %s", draft.id, exc)
        await _record_failure(draft, error_code="LLM_NOT_CONFIGURED", exc=exc, terminal=True)
        return {"claimed": 1, "succeeded": 0, "failed": 1}
    except Exception as exc:  # noqa: BLE001 - intentional catch-all; see below
        # Treat every non-config failure as transient up to
        # MAX_EXTRACT_ATTEMPTS. We catch `Exception` deliberately:
        # `LlmCallError`, `httpx.HTTPError`, JSON decode errors, even
        # an unforeseen `KeyError` from a future LLM response shape
        # all need to land in the "increment + record + maybe-retry"
        # path. The cron must NEVER bubble an unhandled exception out
        # to Vercel, because (a) Vercel would mark the function as
        # failed and retry the cron tick, racing on the same draft
        # without `extract_attempts` reflecting reality, and (b) the
        # operator loses the structured `extract_last_error_*`
        # debug surface that's the whole point of V0.7.
        terminal = draft.extract_attempts >= MAX_EXTRACT_ATTEMPTS
        logger.warning(
            "Cron extract: %s on draft %s (attempt %d/%d, terminal=%s): %s",
            type(exc).__name__,
            draft.id,
            draft.extract_attempts,
            MAX_EXTRACT_ATTEMPTS,
            terminal,
            exc,
        )
        await _record_failure(draft, error_code="LLM_CALL_FAILED", exc=exc, terminal=terminal)
        return {"claimed": 1, "succeeded": 0, "failed": 1}

    # Success: fill in the LLM-derived fields and flip to pending so
    # the parent-admin reviewer sees the draft in their inbox.
    draft.extracted = extracted
    draft.model = model_name
    draft.status = "pending"
    draft.extract_last_error_code = None
    draft.extract_last_error_message = None
    draft.extract_last_error_traceback = None
    await draft.save()
    logger.info(
        "Cron extract: draft %s extracted on attempt %d (model=%s)",
        draft.id,
        draft.extract_attempts,
        model_name,
    )
    return {"claimed": 1, "succeeded": 1, "failed": 0}


__all__ = ["MAX_EXTRACT_ATTEMPTS", "router"]