"""Admin stats response (V0.5.7).

Single endpoint payload that summarises everything an operator wants
to glance at — collection sizes plus pointer freshness + queue depths
for the LLM / lesson review backlogs.
"""

from datetime import datetime

from pydantic import BaseModel, ConfigDict


class StatsOut(BaseModel):
    model_config = ConfigDict(extra="forbid")

    user_count: int
    word_count: int  # excludes soft-deleted rows (matches client view)
    category_count: int
    pack_count: int

    latest_version: int | None
    last_published_at: datetime | None

    llm_draft_pending: int
    lesson_import_draft_pending: int
