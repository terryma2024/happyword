"""V0.6.3 — Family pack definition model.

Per spec §5.7: a parent-managed word pack is split across four collections.
This is the first one — a `FamilyPackDefinition` carries pack metadata
(name / description / state / timestamps). One family may own many packs;
spec recommends one per textbook unit.
"""

from datetime import datetime
from enum import StrEnum
from typing import Annotated

from beanie import Document, Indexed


class FamilyPackState(StrEnum):
    ACTIVE = "active"
    ARCHIVED = "archived"


class FamilyPackDefinition(Document):
    pack_id: Annotated[str, Indexed(unique=True)]  # "pck-<8-hex>"
    family_id: Annotated[str, Indexed()]
    name: str
    description: str | None = None
    state: FamilyPackState = FamilyPackState.ACTIVE
    created_at: datetime
    updated_at: datetime
    archived_at: datetime | None = None
    created_by_parent_id: str

    class Settings:
        name = "family_pack_definitions"
        indexes = [[("family_id", 1), ("state", 1), ("updated_at", -1)]]
