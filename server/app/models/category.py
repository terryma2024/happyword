"""Category collection (V0.5.5).

A category groups Words and seeds the HomePage region cards' fairy-tale
intro text (`story_zh`). V0.5.5 introduces two sources:

  * ``manual`` — seeded at server start for the 5 legacy regions
    (fruit / place / home / animal / ocean) so old packs upgrade
    without admin action.
  * ``lesson-import`` — created from a lesson photo import flow once
    an admin approves the LessonImportDraft.

The V0.5.5 client only renders ``story_zh`` below already-existing
region cards; new categories don't auto-populate the picker (that's
V0.6+ work). The pack JSON contract (schema_v4) carries
``categories[]`` so clients can swap on it later without a server
release.
"""

from datetime import UTC, datetime
from typing import Literal

from beanie import Document
from pydantic import Field


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


CategorySource = Literal["manual", "lesson-import"]


class Category(Document):
    # We DO NOT add `Indexed(unique=True)` on a non-`_id` field here —
    # we already pay that price on `word_packs.version` to be MongoDB-
    # compatible. For Category we rely on the `id: str` override + the
    # service layer's `find_one(...)` checks.
    id: str  # type: ignore[assignment]
    label_en: str
    label_zh: str
    story_zh: str | None = None
    source_image_url: str | None = None
    source: CategorySource = "manual"
    created_at: datetime = Field(default_factory=_utcnow)
    updated_at: datetime = Field(default_factory=_utcnow)

    class Settings:
        name = "categories"
