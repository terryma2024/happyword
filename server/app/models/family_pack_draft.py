"""V0.6.3 — Family pack draft model.

One draft per `FamilyPackDefinition`. Drafts hold the working set of word
entries; publishing snapshots them into a `FamilyWordPack` version. Each
draft is capped at `FAMILY_PACK_MAX_WORDS` (default 50) — see §5.7.
"""

from datetime import datetime
from typing import Annotated, Any

from beanie import Document, Indexed


class FamilyPackDraft(Document):
    pack_definition_id: Annotated[str, Indexed(unique=True)]  # 1:1 to FamilyPackDefinition.pack_id
    family_id: Annotated[str, Indexed()]
    # Each entry carries the same shape as a global WordPack entry, plus an
    # optional `hidden: true` marker that means "exclude this global word in
    # this family". See spec §5.7 + §7.6 merge rules.
    words: list[dict[str, Any]] = []
    updated_at: datetime
    updated_by_parent_id: str

    class Settings:
        name = "family_pack_drafts"
