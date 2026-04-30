"""Pydantic schemas for LLM-driven content tooling.

Used by both the OpenAI structured-output call (`response_format=ScanResult`)
and the admin-facing FastAPI route. Keep these strict — OpenAI structured
outputs require every field to be `required` and forbid extras.
"""

from pydantic import BaseModel, ConfigDict, Field


class ScanWord(BaseModel):
    """One vocabulary entry the model believes the student must memorize."""

    model_config = ConfigDict(extra="forbid")

    word: str = Field(
        ...,
        description=(
            "The headword as printed in the textbook's vocabulary list. "
            "Lowercase unless the source is a proper noun. No punctuation."
        ),
    )
    gloss_zh: str = Field(
        ...,
        description=(
            "Short Chinese gloss / translation if it is printed alongside the "
            "headword on the page. Empty string if no Chinese gloss is visible."
        ),
    )


class ScanResult(BaseModel):
    """Top-level structured output for `extract_target_vocabulary`."""

    model_config = ConfigDict(extra="forbid")

    words: list[ScanWord] = Field(
        ...,
        description=(
            "Ordered list of memorisable vocabulary entries, in the order they "
            "appear in the source's primary vocabulary list."
        ),
    )
    note: str = Field(
        ...,
        description=(
            "Free-form note from the model: which list it picked, anything it "
            "rejected (unit titles, grammar topics, page numbers). Empty string "
            "if nothing notable."
        ),
    )


class ScanResponse(BaseModel):
    """API response from `POST /api/v1/admin/llm/scan-words`."""

    model_config = ConfigDict(extra="forbid")

    model: str
    result: ScanResult
