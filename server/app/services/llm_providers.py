"""LLM provider routing for lesson image extraction.

The lesson import flow has stricter needs than the older word-level
helpers: it needs vision input, deterministic JSON output, and enough
provider metadata for operations to compare/rotate models when one
network path is unavailable.
"""

from __future__ import annotations

import base64
import json
import re
from dataclasses import dataclass
from typing import Any, Literal

import openai
from openai import AsyncOpenAI

from app.config import Settings, get_settings
from app.services.llm_service import LlmCallError, LlmConfigError

ProviderKind = Literal["openai_chat", "openai_compatible_chat", "responses"]


@dataclass(frozen=True)
class LessonProviderSpec:
    id: str
    display_name: str
    kind: ProviderKind
    api_key_env: str
    settings_api_key_attr: str
    settings_model_attr: str
    default_vision_model: str
    base_url: str | None = None
    supports_thinking: bool = False
    disable_thinking: bool = False
    supports_json_object_mode: bool = False
    comparison_notes: str = ""


@dataclass(frozen=True)
class LessonProviderStatus:
    provider: LessonProviderSpec
    model: str
    api_key_configured: bool
    source: str


LESSON_PROVIDER_SPECS: dict[str, LessonProviderSpec] = {
    "openai": LessonProviderSpec(
        id="openai",
        display_name="OpenAI",
        kind="openai_chat",
        api_key_env="OPENAI_API_KEY",
        settings_api_key_attr="openai_api_key",
        settings_model_attr="openai_model_vision",
        default_vision_model="gpt-4o",
        supports_json_object_mode=True,
        comparison_notes=(
            "Baseline accuracy and structured JSON mode; CloudBase China egress may time out."
        ),
    ),
    "qwen": LessonProviderSpec(
        id="qwen",
        display_name="Qwen",
        kind="responses",
        api_key_env="DASHSCOPE_API_KEY",
        settings_api_key_attr="dashscope_api_key",
        settings_model_attr="qwen_model_vision",
        default_vision_model="qwen3.6-plus",
        base_url="https://dashscope.aliyuncs.com/api/v2/apps/protocols/compatible-mode/v1",
        supports_thinking=True,
        comparison_notes=(
            "China-hosted OpenAI-compatible Responses API; good candidate for CloudBase."
        ),
    ),
    "doubao": LessonProviderSpec(
        id="doubao",
        display_name="Doubao",
        kind="responses",
        api_key_env="ARK_API_KEY",
        settings_api_key_attr="ark_api_key",
        settings_model_attr="doubao_model_vision",
        default_vision_model="doubao-seed-2-0-pro-260215",
        base_url="https://ark.cn-beijing.volces.com/api/v3",
        comparison_notes=(
            "China-hosted OpenAI-compatible Responses API; useful second local provider."
        ),
    ),
    "kimi": LessonProviderSpec(
        id="kimi",
        display_name="Kimi",
        kind="openai_compatible_chat",
        api_key_env="MOONSHOT_API_KEY",
        settings_api_key_attr="moonshot_api_key",
        settings_model_attr="kimi_model_vision",
        default_vision_model="kimi-k2.6",
        base_url="https://api.moonshot.cn/v1",
        supports_thinking=True,
        disable_thinking=True,
        supports_json_object_mode=True,
        comparison_notes=(
            "Moonshot OpenAI-compatible Chat Completions API with native multimodal input."
        ),
    ),
}


def _build_image_data_url(image_bytes: bytes, mime: str) -> str:
    encoded = base64.b64encode(image_bytes).decode("ascii")
    return f"data:{mime};base64,{encoded}"


def _selected_lesson_provider(settings: Settings) -> LessonProviderSpec:
    provider = LESSON_PROVIDER_SPECS.get(settings.llm_provider)
    if provider is None:
        available = ", ".join(sorted(LESSON_PROVIDER_SPECS))
        raise LlmConfigError(
            f"Unsupported LLM_PROVIDER={settings.llm_provider!r}; choose one of: {available}."
        )
    return provider


async def _selected_lesson_provider_async(settings: Settings) -> tuple[LessonProviderSpec, str]:
    from app.services.system_config_service import get_llm_provider_override  # noqa: PLC0415

    provider_id = await get_llm_provider_override()
    source = "system_config" if provider_id else "environment"
    selected_id = provider_id or settings.llm_provider
    provider = LESSON_PROVIDER_SPECS.get(selected_id)
    if provider is None:
        available = ", ".join(sorted(LESSON_PROVIDER_SPECS))
        raise LlmConfigError(
            f"Unsupported LLM_PROVIDER={selected_id!r}; choose one of: {available}."
        )
    return provider, source


def _provider_api_key(settings: Settings, provider: LessonProviderSpec) -> str:
    return str(getattr(settings, provider.settings_api_key_attr, "") or "").strip()


def _provider_model(settings: Settings, provider: LessonProviderSpec) -> str:
    configured = str(getattr(settings, provider.settings_model_attr, "") or "").strip()
    return configured or provider.default_vision_model


def is_selected_lesson_provider_configured(settings: Settings | None = None) -> bool:
    settings = settings or get_settings()
    provider = _selected_lesson_provider(settings)
    return bool(_provider_api_key(settings, provider))


def lesson_provider_options(settings: Settings | None = None) -> list[LessonProviderStatus]:
    settings = settings or get_settings()
    return [
        LessonProviderStatus(
            provider=provider,
            model=_provider_model(settings, provider),
            api_key_configured=bool(_provider_api_key(settings, provider)),
            source="option",
        )
        for provider in LESSON_PROVIDER_SPECS.values()
    ]


async def effective_lesson_provider_status(
    settings: Settings | None = None,
) -> LessonProviderStatus:
    settings = settings or get_settings()
    provider, source = await _selected_lesson_provider_async(settings)
    return LessonProviderStatus(
        provider=provider,
        model=_provider_model(settings, provider),
        api_key_configured=bool(_provider_api_key(settings, provider)),
        source=source,
    )


async def is_effective_lesson_provider_configured(
    settings: Settings | None = None,
) -> bool:
    return (await effective_lesson_provider_status(settings)).api_key_configured


def selected_lesson_provider_missing_message(settings: Settings | None = None) -> str:
    settings = settings or get_settings()
    provider = _selected_lesson_provider(settings)
    return (
        f"当前环境选择的 LLM_PROVIDER={provider.id}，但未配置 {provider.api_key_env}"
        "（或值为空），无法解析教材图片。请在部署环境变量中设置该密钥并重启服务后再试。"
    )


async def effective_lesson_provider_missing_message(settings: Settings | None = None) -> str:
    status = await effective_lesson_provider_status(settings)
    provider = status.provider
    return (
        f"当前环境选择的 LLM_PROVIDER={provider.id}，但未配置 {provider.api_key_env}"
        "（或值为空），无法解析教材图片。请在部署环境变量中设置该密钥并重启服务后再试。"
    )


def _require_provider_api_key(settings: Settings, provider: LessonProviderSpec) -> str:
    api_key = _provider_api_key(settings, provider)
    if not api_key:
        raise LlmConfigError(
            f"{provider.api_key_env} is not configured for LLM_PROVIDER={provider.id!r} "
            "on this server instance."
        )
    return api_key


def _build_openai_compatible_client(*, api_key: str, base_url: str | None = None) -> AsyncOpenAI:
    return AsyncOpenAI(api_key=api_key, base_url=base_url)


def _message_text_from_responses_api(response: Any) -> str:
    for item in getattr(response, "output", []) or []:
        if getattr(item, "type", None) != "message":
            continue
        for content in getattr(item, "content", []) or []:
            text = getattr(content, "text", None)
            if isinstance(text, str) and text.strip():
                return text
    raise LlmCallError("LLM vision returned no message text")


_JSON_FENCE_RE = re.compile(r"\A\s*```(?:json|JSON)?\s*(.*?)\s*```\s*\Z", re.DOTALL)


def _json_object_from_text(text: str, *, provider: LessonProviderSpec) -> dict[str, Any]:
    match = _JSON_FENCE_RE.match(text)
    if match:
        text = match.group(1)
    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        raise LlmCallError(f"{provider.display_name} returned invalid JSON: {exc}") from exc
    if not isinstance(payload, dict):
        raise LlmCallError(f"{provider.display_name} vision payload is not an object")
    return payload


async def _extract_lesson_payload_openai_chat(
    *,
    provider: LessonProviderSpec,
    model: str,
    image_bytes: bytes,
    mime: str,
    prompt: str,
    timeout_seconds: float,
) -> tuple[str, dict[str, Any]]:
    from app.services import llm_service  # noqa: PLC0415

    client = llm_service._get_openai_client()  # noqa: SLF001 - shared legacy cache
    image_url = _build_image_data_url(image_bytes, mime)
    try:
        completion = await client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": prompt},
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": "Extract the lesson metadata + words."},
                        {"type": "image_url", "image_url": {"url": image_url}},
                    ],
                },
            ],
            response_format={"type": "json_object"},
            temperature=0,
            timeout=timeout_seconds,
        )
    except openai.OpenAIError as exc:
        raise LlmCallError(f"{provider.display_name} vision call failed: {exc}") from exc

    content = completion.choices[0].message.content
    if not content:
        raise LlmCallError(f"{provider.display_name} vision returned no JSON content")
    return model, _json_object_from_text(content, provider=provider)


async def _extract_lesson_payload_openai_compatible_chat(
    *,
    provider: LessonProviderSpec,
    api_key: str,
    model: str,
    image_bytes: bytes,
    mime: str,
    prompt: str,
    timeout_seconds: float,
) -> tuple[str, dict[str, Any]]:
    client = _build_openai_compatible_client(api_key=api_key, base_url=provider.base_url)
    image_url = _build_image_data_url(image_bytes, mime)
    kwargs: dict[str, Any] = {
        "model": model,
        "messages": [
            {"role": "system", "content": prompt},
            {
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": image_url}},
                    {"type": "text", "text": "Extract the lesson metadata + words."},
                ],
            },
        ],
        "timeout": timeout_seconds,
    }
    if provider.supports_json_object_mode:
        kwargs["response_format"] = {"type": "json_object"}
    if provider.disable_thinking:
        kwargs["extra_body"] = {"thinking": {"type": "disabled"}}

    try:
        completion = await client.chat.completions.create(**kwargs)
    except openai.OpenAIError as exc:
        raise LlmCallError(f"{provider.display_name} vision call failed: {exc}") from exc

    content = completion.choices[0].message.content
    if not content:
        raise LlmCallError(f"{provider.display_name} vision returned no JSON content")
    return model, _json_object_from_text(content, provider=provider)


async def _extract_lesson_payload_responses(
    *,
    provider: LessonProviderSpec,
    api_key: str,
    model: str,
    image_bytes: bytes,
    mime: str,
    prompt: str,
    timeout_seconds: float,
) -> tuple[str, dict[str, Any]]:
    client = _build_openai_compatible_client(api_key=api_key, base_url=provider.base_url)
    image_url = _build_image_data_url(image_bytes, mime)
    kwargs: dict[str, Any] = {
        "model": model,
        "input": [
            {
                "role": "user",
                "content": [
                    {"type": "input_image", "image_url": image_url},
                    {"type": "input_text", "text": prompt},
                ],
            }
        ],
        "timeout": timeout_seconds,
    }
    if provider.supports_thinking:
        kwargs["extra_body"] = {"enable_thinking": True}
    try:
        response = await client.responses.create(**kwargs)
    except openai.OpenAIError as exc:
        raise LlmCallError(f"{provider.display_name} vision call failed: {exc}") from exc

    text = _message_text_from_responses_api(response)
    return model, _json_object_from_text(text, provider=provider)


async def extract_lesson_payload_with_provider(
    image_bytes: bytes,
    mime: str,
    *,
    prompt: str,
    timeout_seconds: float,
) -> tuple[str, dict[str, Any]]:
    settings = get_settings()
    provider, _source = await _selected_lesson_provider_async(settings)
    api_key = _require_provider_api_key(settings, provider)
    model = _provider_model(settings, provider)
    if provider.kind == "openai_chat":
        return await _extract_lesson_payload_openai_chat(
            provider=provider,
            model=model,
            image_bytes=image_bytes,
            mime=mime,
            prompt=prompt,
            timeout_seconds=timeout_seconds,
        )
    if provider.kind == "openai_compatible_chat":
        return await _extract_lesson_payload_openai_compatible_chat(
            provider=provider,
            api_key=api_key,
            model=model,
            image_bytes=image_bytes,
            mime=mime,
            prompt=prompt,
            timeout_seconds=timeout_seconds,
        )
    return await _extract_lesson_payload_responses(
        provider=provider,
        api_key=api_key,
        model=model,
        image_bytes=image_bytes,
        mime=mime,
        prompt=prompt,
        timeout_seconds=timeout_seconds,
    )


async def extract_json_payload_with_provider(
    image_bytes: bytes,
    mime: str,
    *,
    prompt: str,
    timeout_seconds: float,
) -> tuple[str, dict[str, Any]]:
    return await extract_lesson_payload_with_provider(
        image_bytes,
        mime,
        prompt=prompt,
        timeout_seconds=timeout_seconds,
    )


async def extract_json_payload_with_responses_provider(
    image_bytes: bytes,
    mime: str,
    *,
    prompt: str,
    timeout_seconds: float,
) -> tuple[str, dict[str, Any]]:
    settings = get_settings()
    provider, _source = await _selected_lesson_provider_async(settings)
    if provider.kind != "responses":
        raise LlmConfigError(
            f"LLM_PROVIDER={provider.id!r} does not use the Responses API provider path."
        )
    api_key = _require_provider_api_key(settings, provider)
    model = _provider_model(settings, provider)
    return await _extract_lesson_payload_responses(
        provider=provider,
        api_key=api_key,
        model=model,
        image_bytes=image_bytes,
        mime=mime,
        prompt=prompt,
        timeout_seconds=timeout_seconds,
    )
