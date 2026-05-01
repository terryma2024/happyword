"""V0.6.4 — Server-side cloud copy of LearningRecorder per-word stats.

One row per `(child_profile_id, word_id)`. Devices push deltas via
`POST /api/v1/child/word-stats/sync`; LWW resolution by
`last_answered_ms` decides who wins on conflict (spec §6.4 + §7.4).
"""

from datetime import datetime
from typing import Annotated

from beanie import Document, Indexed


class SyncedWordStat(Document):
    child_profile_id: Annotated[str, Indexed()]
    word_id: Annotated[str, Indexed()]
    seen_count: int = 0
    correct_count: int = 0
    wrong_count: int = 0
    last_answered_ms: int = 0
    last_correct_ms: int = 0
    next_review_ms: int = 0
    memory_state: str = "new"
    consecutive_correct: int = 0
    consecutive_wrong: int = 0
    mastery: float = 0.0
    last_synced_from_device_id: str | None = None
    updated_at: datetime

    class Settings:
        name = "synced_word_stats"
        indexes = [[("child_profile_id", 1), ("word_id", 1)]]
