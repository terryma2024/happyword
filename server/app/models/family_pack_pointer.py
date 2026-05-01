"""V0.6.3 — Family pack pointer.

One pointer per `FamilyPackDefinition`. Holds the current/previous version
selectors so we can publish (current=N, previous=N-1) and rollback (swap
current↔previous). A pack with no published version has no pointer row.
"""

from datetime import datetime
from typing import Annotated

from beanie import Document, Indexed


class FamilyPackPointer(Document):
    pack_definition_id: Annotated[str, Indexed(unique=True)]
    family_id: Annotated[str, Indexed()]
    current_version: int
    previous_version: int | None = None
    updated_at: datetime

    class Settings:
        name = "family_pack_pointers"
