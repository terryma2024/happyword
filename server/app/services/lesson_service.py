"""Lesson photo import service (V0.5.5).

Responsibilities:

1. Persist the raw uploaded image somewhere stable (Vercel Blob in
   production, a stub URL when ``BLOB_READ_WRITE_TOKEN`` is unset). The
   import flow needs the URL to be in the DB row so admins can audit
   the source after approval.
2. Extract structured ``{category_id, label_en, label_zh, story_zh,
   words[]}`` from the uploaded image via the configured LLM vision
   provider. The function :func:`extract_lesson_payload` is the
   boundary tests own (they monkeypatch it to return a fixed dict).
3. Approval is implemented in :mod:`app.services.family_pack_import_service`
   — words are written only into that family's lesson-import pack (see
   :func:`family_pack_service.ensure_lesson_import_pack_definition`).
"""

from typing import Any

from app.models.lesson_import_draft import LessonImportDraft
from app.services.llm_providers import extract_lesson_payload_with_provider

OPENAI_VISION_TIMEOUT_SECONDS = 45.0

# NOTE: the literal token "JSON" must appear somewhere in this prompt
# (or the user message). When `response_format={"type": "json_object"}`
# is set on `chat.completions.create`, OpenAI's server-side guardrail
# rejects the request with `BadRequestError: 'messages' must contain
# the word 'json' in some form` if the prompt omits it. Removing the
# word here will silently re-break the import flow with a bare 500;
# `tests/test_lesson_service.py::test_lesson_system_prompt_mentions_json`
# guards against that.
_LESSON_SYSTEM_PROMPT = (
    "You are an English-vocabulary extractor for primary-school "
    "teachers. The user uploads a photo of one textbook page or "
    "tutorial sheet. Return a JSON object with these fields:\n"
    "  * `category_id`: a kebab-case slug summarising the page's "
    '    overall theme (e.g. "school-supplies", "weather", '
    '    "animals-jungle"). Lowercase ASCII only.\n'
    "  * `label_en`: **Primary lesson/theme title — English only.** "
    "    1–4 short English words naming the unit topic exactly as a "
    "    teacher would write it on the board (e.g. Clothing, My "
    "    School Bag). ASCII letters and spaces only; no Chinese here.\n"
    "  * `label_zh`: Short Chinese translation of the **same** theme "
    "    as `label_en` (typically ≤6 characters). Must describe the "
    "    identical topic; do not put the English-only heading here "
    "    instead of in `label_en`.\n"
    "  * `story_zh`: an 80-150 character fairy-tale-flavoured Chinese "
    "    intro for HomePage region cards. Optional.\n"
    "  * `words`: array of objects, one per memorisable headword. "
    "    Each object MUST have:\n"
    "      - `word`: the lowercase headword (single English word "
    "        unless it is a proper noun).\n"
    "      - `meaningZh`: short Chinese gloss (typically 1–4 "
    '        characters, e.g. "铅笔").\n'
    "      - `difficulty`: integer 1–5 estimating CEFR level "
    "        (1 = A1 easy, 5 = B1 challenging) based on the page's "
    "        visual level.\n"
    "      - `example_en`: a SHORT example sentence (5–10 English "
    "        words, primary-school grammar) using the headword "
    "        naturally. The headword MUST appear exactly once in "
    "        the sentence so it can be replaced with a blank for a "
    "        cloze (fill-in-the-blank) exercise. Write the FULL "
    "        sentence including the target word; do NOT pre-blank "
    "        it. Avoid sentences whose context is ambiguous "
    "        without the target word.\n"
    "      - `example_zh`: optional one-line Chinese rendering of the "
    "        same example (same meaning as `example_en`). Helps "
    "        parents review imports in the admin UI.\n"
    "    Only include headwords that the student is expected to "
    "    memorise from THIS page; ignore unit titles, grammar "
    "    topics, page numbers, and sentence examples.\n"
    "Return only the JSON object and nothing else."
)


# --------------------------------------------------------------------------
# Boundary functions (tests monkeypatch these)
# --------------------------------------------------------------------------


async def upload_lesson_image(image_bytes: bytes, mime: str) -> str:
    """Persist the original image and return a stable URL.

    V0.5.5: when no Blob token is configured, return a stub URL so the
    admin import flow still works in dev / CI. V0.5.6 swaps this in for
    a real Vercel Blob `httpx.put` (see app/services/blob_service.py).
    """
    from app.services import blob_service  # noqa: PLC0415

    if not blob_service.is_blob_configured():
        digest = blob_service.short_hash(image_bytes)
        ext = mime.removeprefix("image/")
        return f"stub://lessons/{digest}.{ext}"
    return await blob_service.upload_lesson_image(image_bytes, mime)


_DEFAULT_FETCH_MIME = "image/jpeg"


async def fetch_lesson_image(url: str) -> tuple[bytes, str]:
    """Re-download a previously-uploaded lesson image as (bytes, mime).

    Used by the V0.7 cron extractor (`app.routers.admin_cron`) which
    runs in a separate Vercel function from the import handler and
    therefore cannot just keep the bytes in memory. Tests own this
    seam — they monkeypatch this function so the cron path stays
    network-free.

    The returned MIME is sniffed from the response's `content-type`
    header; if the server omits it (some Blob CDN responses do under
    HEAD redirects) we fall back to image/jpeg, which is benign because
    OpenAI's vision endpoint accepts whatever MIME we hand it as long
    as the bytes look like a real image.
    """
    import httpx  # noqa: PLC0415

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.get(url)
        resp.raise_for_status()
        mime = resp.headers.get("content-type", _DEFAULT_FETCH_MIME).split(";")[0].strip()
        if not mime.startswith("image/"):
            mime = _DEFAULT_FETCH_MIME
        return resp.content, mime


async def extract_lesson_payload(image_bytes: bytes, mime: str) -> tuple[str, dict[str, Any]]:
    """Run the configured LLM vision call and return (model, structured payload).

    Tests override this to skip the real network call. The production
    path uses the lesson-specific provider router because V0.5.5's
    structured output is richer than the older vocabulary-only helper.
    """
    return await extract_lesson_payload_with_provider(
        image_bytes,
        mime,
        prompt=_LESSON_SYSTEM_PROMPT,
        timeout_seconds=OPENAI_VISION_TIMEOUT_SECONDS,
    )


# --------------------------------------------------------------------------
# Approval orchestration
# --------------------------------------------------------------------------


def effective_lesson_extracted(draft: LessonImportDraft) -> dict[str, Any]:
    """Return the admin-edited payload if present, else the raw extraction.

    V0.7: `draft.extracted` is `dict | None` while a draft is in
    `extracting` / `extract_failed`. The approval flow is gated in the router
    on ``status == "pending"``, so by the time we get here `extracted` is
    always populated; the assertion guards against future callers
    wiring this up to a non-pending draft and getting a confusing
    `None.get(...)` error inside the upsert loop.
    """
    if draft.edited_extracted is not None:
        return draft.edited_extracted
    if draft.extracted is None:
        msg = (
            f"effective_lesson_extracted called on draft {draft.id} with "
            f"status={draft.status!r} but no extracted payload — this "
            f"is a programmer error; only pending drafts are approvable."
        )
        raise RuntimeError(msg)
    return draft.extracted
