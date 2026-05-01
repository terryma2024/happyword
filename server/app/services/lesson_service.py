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

_LESSON_SYSTEM_PROMPT = (
    "You are an English-vocabulary extractor for primary-school "
    "teachers. The user uploads a photo of one textbook page or "
    "tutorial sheet. Return:\n"
    "  * `category_id`: a kebab-case slug summarising the page's "
    '    overall theme (e.g. "school-supplies", "weather", '
    '    "animals-jungle"). Lowercase ASCII only.\n'
    "  * `label_en` / `label_zh`: short human-readable labels (≤4 "
    "    English words / ≤6 Chinese characters).\n"
    "  * `story_zh`: an 80-150 character fairy-tale-flavoured Chinese "
    "    intro for HomePage region cards. Optional.\n"
    "  * `words`: ONLY headwords that the student is expected to "
    "    memorise from THIS page. Lowercase, single English words. "
    "    Difficulty 1-5 based on visual estimate of page level.\n"
    "Strict: ignore unit titles, grammar topics, page numbers, and "
    "sentence examples."
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


async def extract_lesson_payload(image_bytes: bytes, mime: str) -> tuple[str, dict[str, Any]]:
    """Run the OpenAI vision call and return (model, structured payload).

    Tests override this to skip the real network call. The production
    path reuses `llm_service.extract_target_vocabulary` only as a
    last-resort fallback; V0.5.5's structured output is richer and uses
    its own prompt, so we ship a fresh thin wrapper.
    """
    import base64  # noqa: PLC0415

    from app.config import get_settings  # noqa: PLC0415

    settings = get_settings()
    if not settings.openai_api_key:
        raise LlmConfigError("OPENAI_API_KEY is not configured on this server instance.")

    # Reuse the shared client cache so tests can also reset us via
    # `llm_service.reset_openai_client()`.
    client = llm_service._get_openai_client()  # noqa: SLF001 - shared cache

    encoded = base64.b64encode(image_bytes).decode("ascii")
    image_url = f"data:{mime};base64,{encoded}"

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
    """Return the admin-edited payload if present, else the raw extraction."""
    return draft.edited_extracted or draft.extracted


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
