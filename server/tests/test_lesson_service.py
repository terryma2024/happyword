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

from types import SimpleNamespace

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


def test_lesson_provider_registry_includes_initial_providers() -> None:
    from app.services.llm_providers import LESSON_PROVIDER_SPECS  # noqa: PLC0415

    assert set(LESSON_PROVIDER_SPECS) >= {"openai", "qwen", "doubao", "kimi"}
    assert LESSON_PROVIDER_SPECS["qwen"].default_vision_model == "qwen3.6-plus"
    assert LESSON_PROVIDER_SPECS["doubao"].default_vision_model == "doubao-seed-2-0-pro-260215"
    assert LESSON_PROVIDER_SPECS["kimi"].default_vision_model == "kimi-k2.6"
    assert LESSON_PROVIDER_SPECS["kimi"].api_key_env == "MOONSHOT_API_KEY"
    assert LESSON_PROVIDER_SPECS["openai"].api_key_env == "OPENAI_API_KEY"


@pytest.mark.asyncio
async def test_extract_lesson_payload_routes_qwen_to_responses_api(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("LLM_PROVIDER", "qwen")
    monkeypatch.setenv("DASHSCOPE_API_KEY", "sk-test-dashscope")
    monkeypatch.setenv("MONGODB_URI", "mongodb://localhost:27017")
    monkeypatch.setenv("MONGO_DB_NAME", "happyword_test")
    monkeypatch.setenv("JWT_SECRET", "test-secret-32-bytes-please-pad")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_USER", "admin")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_PASS", "pw")
    from app.config import get_settings  # noqa: PLC0415
    from app.services import llm_providers  # noqa: PLC0415

    get_settings.cache_clear()
    captured: dict[str, object] = {}

    class _FakeResponses:
        async def create(self, **kwargs: object) -> object:
            captured.update(kwargs)
            message = SimpleNamespace(
                type="message",
                content=[
                    SimpleNamespace(
                        text='```json\n{"category_id":"lesson","label_en":"Lesson","label_zh":"课","words":[]}\n```'
                    )
                ],
            )
            return SimpleNamespace(output=[message])

    class _FakeClient:
        responses = _FakeResponses()

    monkeypatch.setattr(
        llm_providers,
        "_build_openai_compatible_client",
        lambda **_kwargs: _FakeClient(),
    )

    model_used, payload = await lesson_service.extract_lesson_payload(
        b"fake-image-bytes",
        "image/jpeg",
    )

    assert model_used == "qwen3.6-plus"
    assert captured["model"] == "qwen3.6-plus"
    assert captured["extra_body"] == {"enable_thinking": True}
    first_content = captured["input"][0]["content"]  # type: ignore[index]
    assert first_content[0]["type"] == "input_image"
    assert first_content[0]["image_url"].startswith("data:image/jpeg;base64,")
    assert first_content[1]["type"] == "input_text"
    assert payload == {"category_id": "lesson", "label_en": "Lesson", "label_zh": "课", "words": []}


@pytest.mark.asyncio
async def test_extract_lesson_payload_routes_doubao_to_responses_api(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("LLM_PROVIDER", "doubao")
    monkeypatch.setenv("ARK_API_KEY", "ark-test")
    monkeypatch.setenv("MONGODB_URI", "mongodb://localhost:27017")
    monkeypatch.setenv("MONGO_DB_NAME", "happyword_test")
    monkeypatch.setenv("JWT_SECRET", "test-secret-32-bytes-please-pad")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_USER", "admin")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_PASS", "pw")
    from app.config import get_settings  # noqa: PLC0415
    from app.services import llm_providers  # noqa: PLC0415

    get_settings.cache_clear()
    captured: dict[str, object] = {}

    class _FakeResponses:
        async def create(self, **kwargs: object) -> object:
            captured.update(kwargs)
            message = SimpleNamespace(
                type="message",
                content=[SimpleNamespace(text='{"category_id":"lesson","words":[]}')],
            )
            return SimpleNamespace(output=[message])

    class _FakeClient:
        responses = _FakeResponses()

    monkeypatch.setattr(
        llm_providers,
        "_build_openai_compatible_client",
        lambda **_kwargs: _FakeClient(),
    )

    model_used, payload = await lesson_service.extract_lesson_payload(
        b"fake-image-bytes",
        "image/jpeg",
    )

    assert model_used == "doubao-seed-2-0-pro-260215"
    assert captured["model"] == "doubao-seed-2-0-pro-260215"
    assert "extra_body" not in captured
    assert payload == {"category_id": "lesson", "words": []}


@pytest.mark.asyncio
async def test_extract_lesson_payload_routes_kimi_to_chat_completions(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("LLM_PROVIDER", "kimi")
    monkeypatch.setenv("MOONSHOT_API_KEY", "moonshot-test")
    monkeypatch.setenv("MONGODB_URI", "mongodb://localhost:27017")
    monkeypatch.setenv("MONGO_DB_NAME", "happyword_test")
    monkeypatch.setenv("JWT_SECRET", "test-secret-32-bytes-please-pad")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_USER", "admin")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_PASS", "pw")
    from app.config import get_settings  # noqa: PLC0415
    from app.services import llm_providers  # noqa: PLC0415

    get_settings.cache_clear()
    captured_client: dict[str, object] = {}
    captured_request: dict[str, object] = {}

    class _FakeMessage:
        content = '{"category_id":"lesson","words":[]}'

    class _FakeChoice:
        message = _FakeMessage()

    class _FakeCompletion:
        choices = [_FakeChoice()]

    class _FakeCompletions:
        async def create(self, **kwargs: object) -> object:
            captured_request.update(kwargs)
            return _FakeCompletion()

    class _FakeChat:
        completions = _FakeCompletions()

    class _FakeClient:
        chat = _FakeChat()

    def _fake_client(**kwargs: object) -> _FakeClient:
        captured_client.update(kwargs)
        return _FakeClient()

    monkeypatch.setattr(llm_providers, "_build_openai_compatible_client", _fake_client)

    model_used, payload = await lesson_service.extract_lesson_payload(
        b"fake-image-bytes",
        "image/jpeg",
    )

    assert model_used == "kimi-k2.6"
    assert captured_client == {
        "api_key": "moonshot-test",
        "base_url": "https://api.moonshot.cn/v1",
    }
    assert captured_request["model"] == "kimi-k2.6"
    assert captured_request["response_format"] == {"type": "json_object"}
    assert captured_request["extra_body"] == {"thinking": {"type": "disabled"}}
    first_content = captured_request["messages"][1]["content"]  # type: ignore[index]
    assert first_content[0]["type"] == "image_url"
    assert first_content[0]["image_url"]["url"].startswith("data:image/jpeg;base64,")
    assert first_content[1]["type"] == "text"
    assert payload == {"category_id": "lesson", "words": []}


@pytest.mark.asyncio
async def test_extract_lesson_payload_requires_selected_provider_key(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("LLM_PROVIDER", "qwen")
    monkeypatch.delenv("DASHSCOPE_API_KEY", raising=False)
    monkeypatch.setenv("MONGODB_URI", "mongodb://localhost:27017")
    monkeypatch.setenv("MONGO_DB_NAME", "happyword_test")
    monkeypatch.setenv("JWT_SECRET", "test-secret-32-bytes-please-pad")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_USER", "admin")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_PASS", "pw")
    from app.config import get_settings  # noqa: PLC0415
    from app.services.llm_service import LlmConfigError  # noqa: PLC0415

    get_settings.cache_clear()

    with pytest.raises(LlmConfigError) as excinfo:
        await lesson_service.extract_lesson_payload(b"fake-image-bytes", "image/jpeg")

    assert "DASHSCOPE_API_KEY" in str(excinfo.value)


@pytest.mark.asyncio
async def test_extract_target_vocabulary_routes_qwen_scan_words(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("LLM_PROVIDER", "qwen")
    monkeypatch.setenv("DASHSCOPE_API_KEY", "sk-test-dashscope")
    monkeypatch.setenv("MONGODB_URI", "mongodb://localhost:27017")
    monkeypatch.setenv("MONGO_DB_NAME", "happyword_test")
    monkeypatch.setenv("JWT_SECRET", "test-secret-32-bytes-please-pad")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_USER", "admin")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_PASS", "pw")
    from app.config import get_settings  # noqa: PLC0415
    from app.services import llm_providers  # noqa: PLC0415

    get_settings.cache_clear()
    captured: dict[str, object] = {}

    class _FakeResponses:
        async def create(self, **kwargs: object) -> object:
            captured.update(kwargs)
            message = SimpleNamespace(
                type="message",
                content=[
                    SimpleNamespace(
                        text='{"words":[{"word":"shirt","gloss_zh":"衬衫"}],"note":"ok"}'
                    )
                ],
            )
            return SimpleNamespace(output=[message])

    class _FakeClient:
        responses = _FakeResponses()

    monkeypatch.setattr(
        llm_providers,
        "_build_openai_compatible_client",
        lambda **_kwargs: _FakeClient(),
    )

    model_used, result = await llm_service.extract_target_vocabulary(
        b"fake-image-bytes",
        mime="image/jpeg",
    )

    assert model_used == "qwen3.6-plus"
    assert captured["model"] == "qwen3.6-plus"
    assert captured["extra_body"] == {"enable_thinking": True}
    assert [word.word for word in result.words] == ["shirt"]
    assert result.words[0].gloss_zh == "衬衫"


@pytest.mark.asyncio
async def test_extract_target_vocabulary_routes_kimi_scan_words(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("LLM_PROVIDER", "kimi")
    monkeypatch.setenv("MOONSHOT_API_KEY", "moonshot-test")
    monkeypatch.setenv("MONGODB_URI", "mongodb://localhost:27017")
    monkeypatch.setenv("MONGO_DB_NAME", "happyword_test")
    monkeypatch.setenv("JWT_SECRET", "test-secret-32-bytes-please-pad")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_USER", "admin")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_PASS", "pw")
    from app.config import get_settings  # noqa: PLC0415
    from app.services import llm_providers  # noqa: PLC0415

    get_settings.cache_clear()
    captured: dict[str, object] = {}

    class _FakeMessage:
        content = '{"words":[{"word":"shirt","gloss_zh":"衬衫"}],"note":"ok"}'

    class _FakeChoice:
        message = _FakeMessage()

    class _FakeCompletion:
        choices = [_FakeChoice()]

    class _FakeCompletions:
        async def create(self, **kwargs: object) -> object:
            captured.update(kwargs)
            return _FakeCompletion()

    class _FakeChat:
        completions = _FakeCompletions()

    class _FakeClient:
        chat = _FakeChat()

    monkeypatch.setattr(
        llm_providers,
        "_build_openai_compatible_client",
        lambda **_kwargs: _FakeClient(),
    )

    model_used, result = await llm_service.extract_target_vocabulary(
        b"fake-image-bytes",
        mime="image/jpeg",
    )

    assert model_used == "kimi-k2.6"
    assert captured["model"] == "kimi-k2.6"
    assert captured["extra_body"] == {"thinking": {"type": "disabled"}}
    assert [word.word for word in result.words] == ["shirt"]
    assert result.words[0].gloss_zh == "衬衫"
