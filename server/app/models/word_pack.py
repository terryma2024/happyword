"""Word pack snapshot (V0.5.3).

Each `POST /admin/packs/publish` writes one of these documents. The
`words` and `categories` (V0.5.5) lists are full JSON snapshots dumped
from the live Word / Category collections at publish time — rollback
flips a pointer (see :mod:`app.models.pack_pointer`); it does not
re-derive content from the live data, which gives us safe undo even
after admins keep editing.
"""

from datetime import UTC, datetime
from typing import Annotated

from beanie import Document, Indexed
from pydantic import Field


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


class WordPack(Document):
    # Monotonically increasing pack version. We do NOT mark this
    # `Indexed(unique=True)` because Atlas would build the unique index
    # on a non-`_id` field; mongomock-motor does support this so it's
    # safe (unlike the historic `_id` issue from V0.5.1). Indexed(unique)
    # is fine here because the field is NOT `id`.
    version: Annotated[int, Indexed(unique=True)]
    schema_version: int = 1
    words: list[dict[str, object]]
    categories: list[dict[str, object]] | None = None
    published_at: datetime = Field(default_factory=_utcnow)
    published_by: str
    notes: str | None = None

    class Settings:
        name = "word_packs"
