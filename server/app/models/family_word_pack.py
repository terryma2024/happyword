"""V0.6.3 — Family word pack snapshot.

Every successful publish on a `FamilyPackDefinition` writes a new
`FamilyWordPack` row keyed by `(pack_definition_id, version)` — versions
are independent per pack. The pointer in `FamilyPackPointer` selects the
current version for any given pack.
"""

from datetime import datetime
from typing import Annotated, Any

from beanie import Document, Indexed


class FamilyWordPack(Document):
    pack_definition_id: Annotated[str, Indexed()]
    family_id: Annotated[str, Indexed()]
    version: int
    words: list[dict[str, Any]]  # ≤ FAMILY_PACK_MAX_WORDS
    schema_version: int
    published_at: datetime
    published_by_parent_id: str
    notes: str | None = None

    class Settings:
        name = "family_word_packs"
        indexes = [[("pack_definition_id", 1), ("version", -1)]]
