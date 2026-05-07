"""V0.6.4 — Wire schemas for cloud LearningRecorder sync.

Mirrors spec §6.4. Request bodies are strict; outbound shapes are stable
snake_case so client-side parsers stay simple.
"""

from __future__ import annotations

from datetime import datetime  # noqa: TC003 — pydantic needs runtime type
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field


class WordStatItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    word_id: Annotated[str, Field(min_length=1, max_length=128)]
    seen_count: Annotated[int, Field(ge=0)] = 0
    correct_count: Annotated[int, Field(ge=0)] = 0
    wrong_count: Annotated[int, Field(ge=0)] = 0
    last_answered_ms: Annotated[int, Field(ge=0)] = 0
    last_correct_ms: Annotated[int, Field(ge=0)] = 0
    next_review_ms: Annotated[int, Field(ge=0)] = 0
    memory_state: Annotated[str, Field(min_length=1, max_length=32)] = "new"
    consecutive_correct: Annotated[int, Field(ge=0)] = 0
    consecutive_wrong: Annotated[int, Field(ge=0)] = 0
    mastery: Annotated[float, Field(ge=0.0, le=1.0)] = 0.0


class WordStatsSyncIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: list[WordStatItem]
    synced_through_ms: Annotated[int, Field(ge=0)] = 0


class WordStatPullItem(BaseModel):
    word_id: str
    seen_count: int
    correct_count: int
    wrong_count: int
    last_answered_ms: int
    last_correct_ms: int
    next_review_ms: int
    memory_state: str
    consecutive_correct: int
    consecutive_wrong: int
    mastery: float
    updated_at: datetime


class WordStatsSyncOut(BaseModel):
    accepted: list[str]
    rejected: list[str]
    server_pulls: list[WordStatPullItem]
    server_now_ms: int


class WordStatsListOut(BaseModel):
    items: list[WordStatPullItem]
    server_now_ms: int
