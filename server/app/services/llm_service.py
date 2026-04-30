"""OpenAI vision integration for extracting memorisable vocabulary.

The single public entry point is :func:`extract_target_vocabulary`. It
sends a base64-encoded image to a vision-capable chat model with a strict
JSON schema (via ``response_format=ScanResult``) so the caller always
gets a typed Pydantic object back. We use the structured-output ``parse``
helper (OpenAI SDK >=1.40), not free-form JSON, to avoid prompt-injection
and parse-error surface area.

The service does not log the raw API key, the raw response body, or the
image bytes. Tests override the OpenAI client at the boundary
(:func:`_get_openai_client`) so unit tests never reach the network.
"""

from __future__ import annotations

import base64
from typing import TYPE_CHECKING

from openai import AsyncOpenAI

from app.config import get_settings
from app.schemas.llm import ScanResult

if TYPE_CHECKING:
    from openai.types.chat import (
        ChatCompletionContentPartImageParam,
        ChatCompletionContentPartTextParam,
        ChatCompletionUserMessageParam,
    )


class LlmConfigError(RuntimeError):
    """Raised when the server has no OPENAI_API_KEY configured."""


class LlmCallError(RuntimeError):
    """Raised when the OpenAI call returns an unparseable / refused result."""


_SYSTEM_PROMPT = (
    "You are an English-vocabulary extractor for a primary-school teacher. "
    "The user uploads a photo of one textbook page. Your single job is to "
    "return the list of headwords that the student is expected to memorise "
    "from THIS page.\n\n"
    "Rules:\n"
    "  * Only include words from the page's primary vocabulary list "
    "    (e.g. the numbered or bulleted 'Vocabulary Preview' / '词汇' / "
    "    'Words to Learn' block).\n"
    "  * NEVER include unit numbers, unit titles, grammar topics "
    "    (e.g. 'Singular/Plural', 'This/That/These/Those'), section "
    "    headers ('Vocabulary Preview', 'Clothing'), page numbers, or "
    "    sentence examples.\n"
    "  * Lowercase the word unless it is a proper noun.\n"
    "  * Keep them in the order printed on the page.\n"
    "  * If a Chinese gloss is printed next to the word, include it in "
    "    `gloss_zh`. Otherwise return an empty string for that field.\n"
    "  * If the page has no vocabulary list at all, return an empty "
    "    `words` array and explain in `note`.\n"
)

_USER_TEXT = "Extract the target vocabulary from this textbook page."

# Module-level client cache. We deliberately avoid `functools.lru_cache`
# because the cached object is an `AsyncOpenAI` (owns an httpx
# connection pool); on serverless the lambda may freeze/thaw and we want
# `reset_openai_client()` to forcibly drop the pool from tests.
_client_cache: AsyncOpenAI | None = None


def _get_openai_client() -> AsyncOpenAI:
    """Return a process-wide AsyncOpenAI bound to the current settings."""
    global _client_cache
    if _client_cache is not None:
        return _client_cache
    settings = get_settings()
    if not settings.openai_api_key:
        raise LlmConfigError("OPENAI_API_KEY is not configured on this server instance.")
    _client_cache = AsyncOpenAI(api_key=settings.openai_api_key)
    return _client_cache


async def reset_openai_client() -> None:
    """Tear down the cached OpenAI client and close its underlying httpx pool.

    Test-only helper. Production code should never call this — Vercel
    will recycle the worker. Pytest must call this to satisfy the
    project-wide `filterwarnings=["error"]` rule (otherwise httpx
    raises ``ResourceWarning`` at interpreter exit).
    """
    global _client_cache
    if _client_cache is None:
        return
    try:
        await _client_cache.close()
    finally:
        _client_cache = None


def _build_image_data_url(image_bytes: bytes, mime: str) -> str:
    encoded = base64.b64encode(image_bytes).decode("ascii")
    return f"data:{mime};base64,{encoded}"


async def extract_target_vocabulary(
    image_bytes: bytes,
    *,
    mime: str = "image/jpeg",
    model: str | None = None,
) -> tuple[str, ScanResult]:
    """Ask the OpenAI vision model for the page's memorisable headwords.

    Returns a tuple ``(model_used, result)`` so callers can echo the model
    name back to the operator (useful for ops debugging).

    Raises:
        LlmConfigError: when the server has no API key configured.
        LlmCallError: when the model returns no parsed payload.
    """
    settings = get_settings()
    client = _get_openai_client()
    chosen_model = model or settings.openai_model_vision

    image_url: ChatCompletionContentPartImageParam = {
        "type": "image_url",
        "image_url": {"url": _build_image_data_url(image_bytes, mime)},
    }
    text_part: ChatCompletionContentPartTextParam = {
        "type": "text",
        "text": _USER_TEXT,
    }
    user_msg: ChatCompletionUserMessageParam = {
        "role": "user",
        "content": [text_part, image_url],
    }

    completion = await client.chat.completions.parse(
        model=chosen_model,
        messages=[
            {"role": "system", "content": _SYSTEM_PROMPT},
            user_msg,
        ],
        response_format=ScanResult,
        temperature=0,
    )
    parsed = completion.choices[0].message.parsed
    if parsed is None:
        # Model refused or returned no structured payload — surface the
        # refusal text to the caller for debugging.
        refusal = completion.choices[0].message.refusal or "(no parsed content)"
        raise LlmCallError(f"OpenAI returned no structured payload: {refusal}")
    return chosen_model, parsed
