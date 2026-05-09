"""LessonImportDraft (V0.5.5; async-extract refactor V0.7).

A single lesson-import workflow:

1. POST /lessons/import — fast path, **no LLM call**: textbook photo
   uploads to blob; a draft row is inserted with `status="extracting"`
   and `extracted=None`. Returns immediately so the parent admin
   client never waits on OpenAI Vision (the synchronous version
   tripped the simulator's NAT idle timeout, see git log around
   `e50cf97`).
2. Vercel cron (`POST /admin/cron/extract-pending`, scheduled)
   atomically claims one `extracting` draft, calls
   `lesson_service.extract_lesson_payload`, and either:
     • on success, writes `extracted` + `model` and flips status to
       `pending` (待复核 — the existing parent-review state).
     • on failure, increments `extract_attempts` and records
       `extract_last_error_*` for triage. After
       `MAX_EXTRACT_ATTEMPTS` failures the status flips to
       `extract_failed` and stays there until manually retried.
3. Parent admin reviews and approves / rejects as before.

Status machine:
    extracting ──success──▶ pending ──approve──▶ approved
                                    └─reject───▶ rejected
       │
       └──MAX_EXTRACT_ATTEMPTS failures──▶ extract_failed
"""

from datetime import UTC, datetime
from typing import Annotated, Any, Literal

from beanie import Document, Indexed
from pydantic import Field


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


LessonDraftStatus = Literal[
    "extracting",
    "pending",
    "approved",
    "rejected",
    "extract_failed",
]


class LessonImportDraft(Document):
    source_image_url: str
    # `extracted` is None while status=="extracting" (no LLM call yet)
    # and while status=="extract_failed" (the LLM never produced a
    # valid payload). Becomes a dict once the cron extraction
    # succeeds — at that point status flips to "pending".
    extracted: dict[str, Any] | None = None
    edited_extracted: dict[str, Any] | None = None
    status: Annotated[LessonDraftStatus, Indexed()] = "extracting"
    created_at: datetime = Field(default_factory=_utcnow)
    reviewed_at: datetime | None = None
    reviewer: str | None = None
    # `model` is None until the cron extraction succeeds; we don't
    # know which OpenAI model handled the draft until that point.
    model: str | None = None
    prompt_version: int = 1
    approval_summary: dict[str, Any] | None = None

    # ---- Async extraction telemetry (V0.7) -------------------------
    # Bumped each time the cron router calls
    # `extract_lesson_payload(payload, mime)` for this draft —
    # whether the call succeeds or raises. Used to (a) cap retries
    # at `MAX_EXTRACT_ATTEMPTS` and (b) order claim queries so
    # never-attempted drafts are picked first.
    extract_attempts: int = 0
    # Wall-clock timestamp of the most recent extraction attempt.
    # Doubles as a soft "lease": a cron worker that crashes mid-
    # extraction will NOT prevent the next worker from re-claiming
    # the draft, because we only filter on `status` and
    # `extract_attempts`, not on the timestamp.
    extract_last_attempted_at: datetime | None = None
    # Coarse failure code so the parent admin UI can decide whether
    # to surface a retry button vs. an "infra not configured"
    # explanation. Mirrors the codes the synchronous import
    # endpoint used to raise as 502/503: `LLM_CALL_FAILED`,
    # `LLM_NOT_CONFIGURED`, `EXTRACT_TIMEOUT`, etc.
    extract_last_error_code: str | None = None
    # Truncated free-form error message; safe to render in the UI.
    extract_last_error_message: str | None = None
    # Truncated traceback, for backend triage only — never rendered
    # in the parent UI. ~4 KiB cap is enforced by the writer.
    extract_last_error_traceback: str | None = None

    class Settings:
        name = "lesson_import_drafts"
