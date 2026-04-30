from datetime import UTC, datetime
from typing import Annotated

from beanie import Document, Indexed
from pydantic import Field


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


class Word(Document):
    # Override Beanie's PydanticObjectId-typed id with a stable string slug.
    # MongoDB's `_id` is implicitly unique; declaring `unique=True` on top
    # produces InvalidIndexSpecificationOption (mongomock does not enforce
    # this, which is why local tests miss it). Just type-override the field.
    id: str  # type: ignore[assignment]
    word: str
    meaningZh: str
    category: Annotated[str, Indexed()]
    difficulty: int
    created_at: datetime = Field(default_factory=_utcnow)
    updated_at: datetime = Field(default_factory=_utcnow)
    # Soft-delete timestamp. None == active; non-None == hidden from public
    # pack JSON and from default `/admin/words` listings (V0.5.2).
    deleted_at: datetime | None = None

    # V0.5.4: LLM-generated, admin-approved learner aids. None until an
    # admin reviews & approves an `llm_drafts` row.
    distractors: list[str] | None = None
    example_sentence_en: str | None = None
    example_sentence_zh: str | None = None

    # V0.5.6: Vercel Blob URLs. None means the asset slot is empty and
    # clients must fall back to the bundled rawfile illustration / TTS.
    illustration_url: str | None = None
    audio_url: str | None = None

    class Settings:
        name = "words"
