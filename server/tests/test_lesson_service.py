"""Unit tests for `app.services.lesson_service.extract_lesson_payload`.

Two regression guards live here:

1. ``test_lesson_system_prompt_mentions_json`` — when
   ``response_format={"type": "json_object"}`` is set on a
   ``chat.completions.create`` call, OpenAI's server-side guardrail
   rejects the request with HTTP 400 / ``BadRequestError`` if the
   ``messages`` payload doesn't contain the literal word "json"
   somewhere. The original V0.7 import bug (`PR #49`) was exactly
   that: the prompt described the output fields in detail but never
   said "JSON". The error rolled up as Starlette's bare
   ``Internal Server Error`` 500 because the router only catches
   ``LlmConfigError`` / ``LlmCallError``.

2. ``test_extract_lesson_payload_wraps_openai_error`` — the second
   half of the same fix: any ``openai.OpenAIError`` (BadRequest,
   Authentication, RateLimit, APIConnection, …) raised inside
   ``extract_lesson_payload`` MUST be re-raised as ``LlmCallError`` so
   the router's existing ``except LlmCallError`` path returns a
   structured 502 ``LLM_CALL_FAILED`` instead of a bare 500.

These tests intentionally do NOT make a real OpenAI call — the live
smoke is gated behind ``LIVE_OPENAI=1`` in ``test_llm_live_smoke.py``.
"""

from __future__ import annotations

import openai
import pytest

from app.services import lesson_service, llm_service
from app.services.llm_service import LlmCallError


def test_lesson_system_prompt_mentions_json() -> None:
    """Prompt must contain the literal token 'json' (case-insensitive)
    so OpenAI's `response_format=json_object` guardrail accepts it."""
    assert "json" in lesson_service._LESSON_SYSTEM_PROMPT.lower(), (
        "_LESSON_SYSTEM_PROMPT must contain the literal word 'json' "
        "somewhere — OpenAI rejects `response_format=json_object` "
        "calls whose messages omit it. See module docstring."
    )


def test_lesson_system_prompt_requests_example_zh() -> None:
    """Bilingual review in parent UI — prompt should ask for optional ``example_zh``."""
    assert "example_zh" in lesson_service._LESSON_SYSTEM_PROMPT, (
        "_LESSON_SYSTEM_PROMPT must request optional `example_zh` per word."
    )


def test_lesson_system_prompt_requests_example_en() -> None:
    """Prompt must keep asking for the per-word ``example_en`` field
    used downstream for cloze (fill-in-the-blank) exercises. Dropping
    this would silently regress the parent-admin import contract: the
    LessonImportDraft would still validate (the field is optional in
    storage) but cloze generation would have no source sentence."""
    assert "example_en" in lesson_service._LESSON_SYSTEM_PROMPT, (
        "_LESSON_SYSTEM_PROMPT must request `example_en` per word — "
        "downstream cloze generation depends on it."
    )


@pytest.mark.asyncio
async def test_extract_lesson_payload_wraps_openai_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Any `openai.OpenAIError` from `chat.completions.create` must be
    re-raised as `LlmCallError`, not bubble up as the raw OpenAI
    exception. Without this wrap, the router's `except LlmCallError`
    misses it and the user gets Starlette's bare 500 page instead of
    the structured `502 LLM_CALL_FAILED` body."""
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test-not-real")
    from app.config import get_settings  # noqa: PLC0415

    get_settings.cache_clear()
    await llm_service.reset_openai_client()

    class _FakeCompletions:
        async def create(self, **_kwargs: object) -> None:
            # Use the abstract base `OpenAIError` so the test doesn't
            # have to construct an `httpx.Response` for `BadRequestError`.
            # The except clause in `extract_lesson_payload` catches the
            # base, so the contract under test is identical.
            raise openai.OpenAIError("simulated openai failure")

    class _FakeChat:
        completions = _FakeCompletions()

    class _FakeClient:
        chat = _FakeChat()

    monkeypatch.setattr(llm_service, "_get_openai_client", lambda: _FakeClient())

    with pytest.raises(LlmCallError) as excinfo:
        await lesson_service.extract_lesson_payload(b"fake-image-bytes", "image/jpeg")

    assert "OpenAI vision call failed" in str(excinfo.value)
    assert isinstance(excinfo.value.__cause__, openai.OpenAIError)


@pytest.mark.asyncio
async def test_extract_lesson_payload_bounds_openai_call_below_function_timeout(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Cron must regain control before Vercel kills the serverless function."""
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test-not-real")
    from app.config import get_settings  # noqa: PLC0415

    get_settings.cache_clear()
    await llm_service.reset_openai_client()

    seen_kwargs: dict[str, object] = {}

    class _FakeMessage:
        content = (
            '{"category_id":"lesson","label_en":"Lesson",'
            '"label_zh":"Lesson","words":[]}'
        )

    class _FakeChoice:
        message = _FakeMessage()

    class _FakeCompletion:
        choices = [_FakeChoice()]

    class _FakeCompletions:
        async def create(self, **kwargs: object) -> _FakeCompletion:
            seen_kwargs.update(kwargs)
            return _FakeCompletion()

    class _FakeChat:
        completions = _FakeCompletions()

    class _FakeClient:
        chat = _FakeChat()

    monkeypatch.setattr(llm_service, "_get_openai_client", lambda: _FakeClient())

    await lesson_service.extract_lesson_payload(b"fake-image-bytes", "image/jpeg")

    assert seen_kwargs["timeout"] == lesson_service.OPENAI_VISION_TIMEOUT_SECONDS
    assert seen_kwargs["timeout"] < 60.0
