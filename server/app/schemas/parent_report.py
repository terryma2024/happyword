"""V0.6.5 — wire schemas for the parent-side learning report.

Mirrors the client-side `LearningReport` so the parent web can render
the same KPIs the child sees on `LearningReportPage`.
"""

from __future__ import annotations

from datetime import datetime  # noqa: TC003 — Pydantic needs runtime type

from pydantic import BaseModel, Field


class CategoryReportOut(BaseModel):
    """One category bucket. `display_name` is server-localized so the
    parent web doesn't need a translation table to show "水果" / etc."""

    category: str
    display_name: str
    total_seen: int = 0
    total_correct: int = 0
    accuracy_pct: int = 0  # 0..100 rounded


class ChildReportOut(BaseModel):
    """Aggregate per-child report. Field set is identical to the client's
    `LearningReport`; field names use snake_case (parent web reads JSON)."""

    child_profile_id: str
    nickname: str
    total_words: int = 0
    total_seen: int = 0
    total_correct: int = 0
    accuracy_pct: int = 0
    new_count: int = 0
    learning_count: int = 0
    familiar_count: int = 0
    mastered_count: int = 0
    review_due_count: int = 0
    review_done_today_count: int = 0
    review_completion_pct: int = 0
    categories: list[CategoryReportOut] = Field(default_factory=list)
    weak_categories: list[CategoryReportOut] = Field(default_factory=list)
    today_review_done: int = 0  # alias for review_done_today_count
    today_review_due: int = 0   # alias for review_due_count
    lookback_days: int = 7
    generated_at: datetime
    last_synced_at: datetime | None = None
