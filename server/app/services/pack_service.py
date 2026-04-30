"""Pack publish / rollback / serialize service (V0.5.3 -> V0.5.6).

Layout note: the public `/api/v1/packs/latest.json` endpoint imports
:func:`get_current_pack_payload` so that the wire schema stays in one
place across schema_version bumps (v1 today; v2 in V0.5.4 with LLM
fields; v4 in V0.5.5 with categories[]; v5 in V0.5.6 with
illustration/audio URLs).
"""

from datetime import UTC, datetime
from typing import Any

from app.models.pack_pointer import PackPointer
from app.models.word import Word
from app.models.word_pack import WordPack


class PackError(RuntimeError):
    """Raised when a pack operation cannot proceed (empty / no-prev / etc.)."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


# ---------------------------------------------------------------------------
# Word -> pack-JSON serialization
# ---------------------------------------------------------------------------


def serialize_word_for_pack(w: Word) -> dict[str, Any]:
    """Convert one Word document to the wire shape consumed by clients.

    V0.5.3 wire shape (schema_version=1) has the original 5 fields. Later
    sub-versions (V0.5.4 distractors / example, V0.5.6 illustration /
    audio URLs) extend this dict — that's why the function is open to
    new fields rather than driven by a fixed Pydantic model.
    """
    return {
        "id": w.id,
        "word": w.word,
        "meaningZh": w.meaningZh,
        "category": w.category,
        "difficulty": w.difficulty,
    }


def derive_schema_version(words: list[dict[str, Any]]) -> int:
    """Pick the lowest schema_version that can losslessly represent ``words``.

    The hierarchy is v1 (baseline) < v2 (LLM) < v4 (+categories — set by
    caller, not inferred from words) < v5 (+illustration/audio).
    Categories live on the snapshot, not on words, so this function only
    surfaces v1 / v2 / v5; the caller bumps to v4 if it has categories.
    """
    if any("illustrationUrl" in w or "audioUrl" in w for w in words):
        return 5
    if any("distractors" in w or "example" in w for w in words):
        return 2
    return 1


# ---------------------------------------------------------------------------
# Publish / rollback
# ---------------------------------------------------------------------------


async def _live_active_words() -> list[Word]:
    """Words eligible for publishing — soft-deleted rows are excluded."""
    rows: list[Word] = await Word.find(
        Word.deleted_at == None  # noqa: E711 (Beanie demands `==` for None)
    ).to_list()
    return rows


async def publish_pack(*, published_by: str, notes: str | None = None) -> WordPack:
    """Snapshot the current Word collection into a new WordPack.

    Bumps :class:`PackPointer` (creating it on first publish), keeping
    `previous_version` for one-step rollback.
    """
    rows = await _live_active_words()
    if not rows:
        raise PackError("EMPTY_PACK", "No active words to publish")

    serialised_words = [serialize_word_for_pack(w) for w in rows]
    schema_v = derive_schema_version(serialised_words)
    pointer = await PackPointer.find_one(PackPointer.singleton_key == "main")
    next_version = (pointer.current_version + 1) if pointer is not None else 1

    pack = WordPack(
        version=next_version,
        schema_version=schema_v,
        words=serialised_words,
        published_by=published_by,
        notes=notes,
        published_at=datetime.now(tz=UTC),
    )
    await pack.insert()

    if pointer is None:
        pointer = PackPointer(current_version=next_version, previous_version=None)
        await pointer.insert()
    else:
        pointer.previous_version = pointer.current_version
        pointer.current_version = next_version
        await pointer.save()

    return pack


async def rollback_pack() -> PackPointer:
    """Flip the pointer to ``previous_version``. Idempotent on its own,
    but successive rollbacks oscillate (current↔previous swap) so the
    operator should re-publish to break out of that.
    """
    pointer = await PackPointer.find_one(PackPointer.singleton_key == "main")
    if pointer is None or pointer.previous_version is None:
        raise PackError("NO_PREVIOUS_VERSION", "No previous pack version to roll back to")
    new_current = pointer.previous_version
    new_previous = pointer.current_version
    pointer.current_version = new_current
    pointer.previous_version = new_previous
    await pointer.save()
    return pointer


# ---------------------------------------------------------------------------
# Read paths used by /api/v1/packs/latest.json + /admin/packs
# ---------------------------------------------------------------------------


async def get_current_pack() -> WordPack | None:
    """Return the WordPack the pointer currently aims at, or None."""
    pointer = await PackPointer.find_one(PackPointer.singleton_key == "main")
    if pointer is None:
        return None
    pack = await WordPack.find_one(WordPack.version == pointer.current_version)
    return pack


async def get_pack_by_version(version: int) -> WordPack | None:
    return await WordPack.find_one(WordPack.version == version)


async def get_current_pack_payload() -> tuple[int, dict[str, Any]]:
    """Wire payload for `/api/v1/packs/latest.json`.

    Returns ``(version, payload)``. Falls back to a live (non-snapshot)
    pack when no publish has happened yet — V0.5.1 dev / pre-publish
    behaviour. Live fallback always reports ``version=0``, schema_v1.
    """
    pack = await get_current_pack()
    if pack is not None:
        payload: dict[str, Any] = {
            "version": pack.version,
            "schema_version": pack.schema_version,
            "published_at": pack.published_at.isoformat(),
            "words": pack.words,
        }
        if pack.categories is not None:
            payload["categories"] = pack.categories
        return pack.version, payload

    # No pack ever published — serve a synthetic v0 from live Word rows.
    rows = await _live_active_words()
    payload = {
        "version": 0,
        "schema_version": 1,
        "published_at": datetime.now(tz=UTC).isoformat(),
        "words": [serialize_word_for_pack(w) for w in rows],
    }
    return 0, payload
