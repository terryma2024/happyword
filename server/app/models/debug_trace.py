"""Request/response trace rows captured for preview debug sessions."""

from datetime import datetime
from typing import Annotated, Any

from beanie import Document, Indexed


class DebugTrace(Document):
    session_id: Annotated[str, Indexed()]
    correlation_id: Annotated[str, Indexed(unique=True)]
    method: str
    path: str
    query: str
    status_code: int
    duration_ms: float
    request_headers: dict[str, str]
    response_headers: dict[str, str]
    request_body: dict[str, Any] | None = None
    response_body: dict[str, Any] | None = None
    ts: Annotated[datetime, Indexed()]

    class Settings:
        name = "debug_traces"
        indexes = [[("session_id", 1), ("ts", 1)], [("path", 1), ("ts", -1)]]
