"""Lesson photo import service (V0.5.5).

Three responsibilities:

1. Persist the raw uploaded image somewhere stable (Vercel Blob in
   production, a stub URL when ``BLOB_READ_WRITE_TOKEN`` is unset). The
   import flow needs the URL to be in the DB row so admins can audit
   the source after approval.
2. Extract structured ``{category_id, label_en, label_zh, story_zh,
   words[]}`` from the uploaded image via OpenAI vision. The function
   :func:`extract_lesson_payload` is the boundary tests own (they
   monkeypatch it to return a fixed dict).
3. Approve a draft → create the Category + batch-upsert the Words,
   skipping any whose ids already exist (so admin-edited rows survive).
"""

from datetime import UTC, datetime
from typing import Any

from app.models.category import Category
from app.models.lesson_import_draft import LessonImportDraft
from app.models.word import Word
from app.services import llm_service
from app.services.llm_service import LlmCallError, LlmConfigError

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
    """Run the OpenAI vision call and return (model, structured payload).

    Tests override this to skip the real network call. The production
    path reuses `llm_service.extract_target_vocabulary` only as a
    last-resort fallback; V0.5.5's structured output is richer and uses
    its own prompt, so we ship a fresh thin wrapper.
    """
    import base64  # noqa: PLC0415

    import openai  # noqa: PLC0415

    from app.config import get_settings  # noqa: PLC0415

    settings = get_settings()
    if not settings.openai_api_key:
        raise LlmConfigError("OPENAI_API_KEY is not configured on this server instance.")

    # Reuse the shared client cache so tests can also reset us via
    # `llm_service.reset_openai_client()`.
    client = llm_service._get_openai_client()  # noqa: SLF001 - shared cache

    encoded = base64.b64encode(image_bytes).decode("ascii")
    image_url = f"data:{mime};base64,{encoded}"

    try:
        completion = await client.chat.completions.create(
            model=settings.openai_model_vision,
            messages=[
                {"role": "system", "content": _LESSON_SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": "Extract the lesson metadata + words."},
                        {"type": "image_url", "image_url": {"url": image_url}},
                    ],
                },
            ],
            response_format={"type": "json_object"},
            temperature=0,
        )
    except openai.OpenAIError as exc:
        # Without this catch, OpenAI client exceptions (BadRequestError,
        # AuthenticationError, RateLimitError, APIConnectionError, …)
        # bubble past the router's narrow `except LlmCallError` and the
        # user gets Starlette's bare `Internal Server Error` 500 instead
        # of the structured 502 LLM_CALL_FAILED. Wrap once here so every
        # OpenAI failure travels the same blessed path.
        raise LlmCallError(f"OpenAI vision call failed: {exc}") from exc
    content = completion.choices[0].message.content
    if not content:
        raise LlmCallError("OpenAI vision returned no JSON content")
    import json  # noqa: PLC0415

    try:
        payload = json.loads(content)
    except json.JSONDecodeError as exc:
        raise LlmCallError(f"OpenAI returned invalid JSON: {exc}") from exc
    if not isinstance(payload, dict):
        raise LlmCallError("OpenAI vision payload is not an object")
    return settings.openai_model_vision, payload


# --------------------------------------------------------------------------
# Approval orchestration
# --------------------------------------------------------------------------


def _effective_extracted(draft: LessonImportDraft) -> dict[str, Any]:
    """Return the admin-edited payload if present, else the raw extraction.

    V0.7: `draft.extracted` is `dict | None` while a draft is in
    `extracting` / `extract_failed`. The approval flow is gated on
    `_ensure_pending`, so by the time we get here `extracted` is
    always populated; the assertion guards against future callers
    wiring this up to a non-pending draft and getting a confusing
    `None.get(...)` error inside the upsert loop.
    """
    if draft.edited_extracted is not None:
        return draft.edited_extracted
    if draft.extracted is None:
        msg = (
            f"approve_lesson_draft called on draft {draft.id} with "
            f"status={draft.status!r} but no extracted payload — this "
            f"is a programmer error; only pending drafts are approvable."
        )
        raise RuntimeError(msg)
    return draft.extracted


async def approve_lesson_draft(draft: LessonImportDraft, *, reviewer: str) -> dict[str, Any]:
    """Apply ``draft`` to the DB:

      * upsert the Category (creating if missing, updating story / labels
        if it already exists),
      * for each word in `extracted.words[]`, insert a new Word row
        unless one with the same id already exists; skip on conflict.

    Returns a structured ``approval_summary`` containing the touched
    Category and lists of created / skipped words. The caller is
    responsible for persisting the summary onto the draft.
    """
    payload = _effective_extracted(draft)
    cat_id = str(payload["category_id"]).strip().lower()
    label_en = str(payload.get("label_en", cat_id))
    label_zh = str(payload.get("label_zh", cat_id))
    story_zh = payload.get("story_zh")
    words: list[dict[str, Any]] = list(payload.get("words", []))

    now = datetime.now(tz=UTC)
    cat = await Category.find_one(Category.id == cat_id)
    if cat is None:
        cat = Category(
            id=cat_id,
            label_en=label_en,
            label_zh=label_zh,
            story_zh=story_zh,
            source_image_url=draft.source_image_url,
            source="lesson-import",
            created_at=now,
            updated_at=now,
        )
        await cat.insert()
    else:
        # Touch story_zh / labels only — never flip a manual category to
        # lesson-import (that would erase the audit trail).
        cat.label_en = label_en
        cat.label_zh = label_zh
        if story_zh:
            cat.story_zh = story_zh
        cat.updated_at = now
        await cat.save()

    created: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    for w in words:
        word_text = str(w["word"]).strip().lower()
        word_id = f"{cat_id}-{word_text}"
        existing = await Word.find_one(Word.id == word_id)
        if existing is not None:
            skipped.append({"id": word_id, "word": word_text, "reason": "DUPLICATE_ID"})
            continue
        await Word(
            id=word_id,
            word=word_text,
            meaningZh=str(w.get("meaningZh", "")),
            category=cat_id,
            difficulty=int(w.get("difficulty", 1)),
            created_at=now,
            updated_at=now,
        ).insert()
        created.append({"id": word_id, "word": word_text})

    return {
        "category": {
            "id": cat.id,
            "label_en": cat.label_en,
            "label_zh": cat.label_zh,
            "story_zh": cat.story_zh,
            "source_image_url": cat.source_image_url,
            "source": cat.source,
            "created_at": cat.created_at,
            "updated_at": cat.updated_at,
        },
        "created_words": created,
        "skipped_words": skipped,
        "reviewer": reviewer,
    }
