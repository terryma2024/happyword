"""Image-generation provider routing for spellbook cover art."""

from __future__ import annotations

import base64
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

import httpx
import openai
from dotenv import dotenv_values
from openai import AsyncOpenAI

from app.config import Settings, get_settings
from app.services.llm_service import LlmCallError, LlmConfigError

ImageProviderKind = Literal["openai_images", "dashscope_image", "ark_image"]


@dataclass(frozen=True)
class ImageProviderSpec:
    id: str
    display_name: str
    kind: ImageProviderKind
    api_key_env: str
    settings_api_key_attr: str
    settings_model_attr: str
    default_model: str
    base_url_attr: str | None = None
    comparison_notes: str = ""


@dataclass(frozen=True)
class ImageProviderStatus:
    provider: ImageProviderSpec
    model: str
    api_key_configured: bool
    source: str


IMAGE_PROVIDER_SPECS: dict[str, ImageProviderSpec] = {
    "openai": ImageProviderSpec(
        id="openai",
        display_name="OpenAI Images",
        kind="openai_images",
        api_key_env="OPENAI_API_KEY",
        settings_api_key_attr="openai_api_key",
        settings_model_attr="openai_model_image",
        default_model="gpt-image-2",
        comparison_notes="海外默认封面生成 Provider，支持透明背景 PNG。",
    ),
    "qwen": ImageProviderSpec(
        id="qwen",
        display_name="Qwen Image",
        kind="dashscope_image",
        api_key_env="DASHSCOPE_API_KEY",
        settings_api_key_attr="dashscope_api_key",
        settings_model_attr="qwen_model_image",
        default_model="qwen-image-2.0-pro",
        base_url_attr="qwen_image_base_url",
        comparison_notes="国内可用的阿里云百炼 / DashScope 图片生成 Provider。",
    ),
    "doubao": ImageProviderSpec(
        id="doubao",
        display_name="Doubao Seedream",
        kind="ark_image",
        api_key_env="ARK_API_KEY",
        settings_api_key_attr="ark_api_key",
        settings_model_attr="doubao_model_image",
        default_model="doubao-seedream-4-5-251128",
        comparison_notes="国内可用的火山方舟 / 豆包 Seedream 图片生成 Provider。",
    ),
}

_OPENAI_TRANSPARENT_BACKGROUND_MODELS = frozenset({"gpt-image-1"})


def _home_env_value(name: str) -> str:
    path = Path.home() / ".env"
    if not path.exists():
        return ""
    value = dotenv_values(path).get(name)
    return value.strip() if isinstance(value, str) else ""


def _env_or_home(name: str) -> str:
    return os.environ.get(name, "").strip() or _home_env_value(name)


def _provider_api_key(settings: Settings, provider: ImageProviderSpec) -> str:
    configured = str(getattr(settings, provider.settings_api_key_attr, "") or "").strip()
    return configured or _env_or_home(provider.api_key_env)


def _provider_model(settings: Settings, provider: ImageProviderSpec) -> str:
    configured = str(getattr(settings, provider.settings_model_attr, "") or "").strip()
    return configured or provider.default_model


def _provider_base_url(settings: Settings, provider: ImageProviderSpec) -> str:
    if provider.base_url_attr is None:
        return ""
    return str(getattr(settings, provider.base_url_attr, "") or "").rstrip("/")


def image_provider_options(settings: Settings | None = None) -> list[ImageProviderStatus]:
    settings = settings or get_settings()
    return [
        ImageProviderStatus(
            provider=provider,
            model=_provider_model(settings, provider),
            api_key_configured=bool(_provider_api_key(settings, provider)),
            source="option",
        )
        for provider in IMAGE_PROVIDER_SPECS.values()
    ]


async def _selected_image_provider_async(
    settings: Settings,
) -> tuple[ImageProviderSpec, str]:
    from app.services.system_config_service import get_image_provider_override  # noqa: PLC0415

    provider_id = await get_image_provider_override()
    source = "system_config" if provider_id else "environment"
    selected_id = provider_id or settings.image_provider
    provider = IMAGE_PROVIDER_SPECS.get(selected_id)
    if provider is None:
        available = ", ".join(sorted(IMAGE_PROVIDER_SPECS))
        raise LlmConfigError(
            f"Unsupported IMAGE_PROVIDER={selected_id!r}; choose one of: {available}."
        )
    return provider, source


async def effective_image_provider_status(
    settings: Settings | None = None,
) -> ImageProviderStatus:
    settings = settings or get_settings()
    provider, source = await _selected_image_provider_async(settings)
    return ImageProviderStatus(
        provider=provider,
        model=_provider_model(settings, provider),
        api_key_configured=bool(_provider_api_key(settings, provider)),
        source=source,
    )


async def is_effective_image_provider_configured(settings: Settings | None = None) -> bool:
    return (await effective_image_provider_status(settings)).api_key_configured


async def test_image_provider_connectivity(
    *,
    provider_id: str,
    settings: Settings | None = None,
) -> ImageProviderStatus:
    settings = settings or get_settings()
    provider = IMAGE_PROVIDER_SPECS.get(provider_id)
    if provider is None:
        available = ", ".join(sorted(IMAGE_PROVIDER_SPECS))
        raise LlmConfigError(
            f"Unsupported image provider {provider_id!r}; choose one of: {available}."
        )
    _require_provider_api_key(settings, provider)
    return ImageProviderStatus(
        provider=provider,
        model=_provider_model(settings, provider),
        api_key_configured=True,
        source="connectivity_test",
    )


def _require_provider_api_key(settings: Settings, provider: ImageProviderSpec) -> str:
    api_key = _provider_api_key(settings, provider)
    if not api_key:
        raise LlmConfigError(
            f"{provider.api_key_env} is not configured for IMAGE_PROVIDER={provider.id!r}."
        )
    return api_key


def _image_bytes_from_openai_response(response: Any) -> bytes:
    data = getattr(response, "data", None) or []
    if not data:
        raise LlmCallError("Image provider returned no image data")
    encoded = getattr(data[0], "b64_json", None)
    if isinstance(encoded, str) and encoded.strip():
        return base64.b64decode(encoded)
    raise LlmCallError("Image provider did not return base64 PNG data")


async def _generate_openai_image(
    *,
    provider: ImageProviderSpec,
    api_key: str,
    model: str,
    prompt: str,
    timeout_seconds: float,
) -> bytes:
    client = AsyncOpenAI(api_key=api_key)
    kwargs: dict[str, Any] = {
        "model": model,
        "prompt": prompt,
        "size": "1024x1024",
        "n": 1,
        "output_format": "png",
        "timeout": timeout_seconds,
    }
    if model in _OPENAI_TRANSPARENT_BACKGROUND_MODELS:
        kwargs["background"] = "transparent"
    try:
        response = await client.images.generate(**kwargs)
    except openai.OpenAIError as exc:
        raise LlmCallError(f"{provider.display_name} image call failed: {exc}") from exc
    return _image_bytes_from_openai_response(response)


async def _generate_dashscope_image(
    *,
    provider: ImageProviderSpec,
    api_key: str,
    model: str,
    base_url: str,
    prompt: str,
    timeout_seconds: float,
) -> bytes:
    origin = base_url or "https://dashscope.aliyuncs.com"
    create_url = f"{origin}/api/v1/services/aigc/multimodal-generation/generation"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": model,
        "input": {
            "messages": [
                {
                    "role": "user",
                    "content": [{"text": prompt}],
                }
            ]
        },
        "parameters": {
            "negative_prompt": "",
            "prompt_extend": True,
            "watermark": False,
            "size": "2048*2048",
        },
    }
    try:
        async with httpx.AsyncClient(timeout=timeout_seconds) as client:
            created = await client.post(create_url, json=payload, headers=headers)
            created.raise_for_status()
            image_url = _image_url_from_dashscope_response(provider, created.json())
            image = await client.get(image_url)
            image.raise_for_status()
            return image.content
    except httpx.HTTPError as exc:
        raise LlmCallError(f"{provider.display_name} image call failed: {exc}") from exc
    except ValueError as exc:
        raise LlmCallError(f"{provider.display_name} returned invalid JSON") from exc


def _image_url_from_dashscope_response(provider: ImageProviderSpec, body: dict[str, Any]) -> str:
    output = body.get("output")
    if not isinstance(output, dict):
        raise LlmCallError(f"{provider.display_name} returned no image URL")
    choices = output.get("choices")
    if not isinstance(choices, list):
        raise LlmCallError(f"{provider.display_name} returned no image URL")
    for choice in choices:
        if not isinstance(choice, dict):
            continue
        message = choice.get("message")
        if not isinstance(message, dict):
            continue
        content = message.get("content")
        if not isinstance(content, list):
            continue
        for item in content:
            if not isinstance(item, dict):
                continue
            image_url = item.get("image")
            if isinstance(image_url, str) and image_url.strip():
                return image_url
    raise LlmCallError(f"{provider.display_name} returned no image URL")


def _image_url_from_ark_response(provider: ImageProviderSpec, body: dict[str, Any]) -> str:
    data = body.get("data") or []
    if not isinstance(data, list) or not data:
        raise LlmCallError(f"{provider.display_name} returned no image data")
    first = data[0]
    if not isinstance(first, dict):
        raise LlmCallError(f"{provider.display_name} returned invalid image data")
    image_url = first.get("url")
    if not isinstance(image_url, str) or not image_url.strip():
        raise LlmCallError(f"{provider.display_name} returned no image URL")
    return image_url


async def _generate_doubao_image(
    *,
    provider: ImageProviderSpec,
    api_key: str,
    model: str,
    prompt: str,
    timeout_seconds: float,
) -> bytes:
    create_url = "https://ark.cn-beijing.volces.com/api/v3/images/generations"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": model,
        "prompt": prompt,
        "sequential_image_generation": "disabled",
        "response_format": "url",
        "size": "2K",
        "stream": False,
        "watermark": True,
    }
    try:
        async with httpx.AsyncClient(timeout=timeout_seconds) as client:
            created = await client.post(create_url, json=payload, headers=headers)
            created.raise_for_status()
            image_url = _image_url_from_ark_response(provider, created.json())
            image = await client.get(image_url)
            image.raise_for_status()
            return image.content
    except httpx.HTTPError as exc:
        raise LlmCallError(f"{provider.display_name} image call failed: {exc}") from exc
    except ValueError as exc:
        raise LlmCallError(f"{provider.display_name} returned invalid JSON") from exc


async def generate_spellbook_cover_png(
    *,
    pack_name: str,
    words: list[dict[str, object]],
    prompt: str | None = None,
    timeout_seconds: float = 90.0,
) -> tuple[str, bytes]:
    settings = get_settings()
    provider, _source = await _selected_image_provider_async(settings)
    api_key = _require_provider_api_key(settings, provider)
    model = _provider_model(settings, provider)
    use_prompt = prompt or f"128x128 transparent icon for a magical vocabulary book: {pack_name}"
    _ = words
    if provider.kind == "openai_images":
        return (
            model,
            await _generate_openai_image(
                provider=provider,
                api_key=api_key,
                model=model,
                prompt=use_prompt,
                timeout_seconds=timeout_seconds,
            ),
        )
    if provider.kind == "dashscope_image":
        return (
            model,
            await _generate_dashscope_image(
                provider=provider,
                api_key=api_key,
                model=model,
                base_url=_provider_base_url(settings, provider),
                prompt=use_prompt,
                timeout_seconds=timeout_seconds,
            ),
        )
    if provider.kind == "ark_image":
        return (
            model,
            await _generate_doubao_image(
                provider=provider,
                api_key=api_key,
                model=model,
                prompt=use_prompt,
                timeout_seconds=timeout_seconds,
            ),
        )
    raise LlmConfigError(f"Unsupported image provider kind {provider.kind!r}.")
