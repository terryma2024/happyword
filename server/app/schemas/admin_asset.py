"""Admin asset upload responses (V0.5.6).

Tiny schemas — the upload endpoints just echo the resulting URL so the
client UI can update the asset preview without re-fetching the word.
"""

from pydantic import BaseModel, ConfigDict


class IllustrationOut(BaseModel):
    model_config = ConfigDict(extra="forbid")

    word_id: str
    illustration_url: str | None


class AudioOut(BaseModel):
    model_config = ConfigDict(extra="forbid")

    word_id: str
    audio_url: str | None
