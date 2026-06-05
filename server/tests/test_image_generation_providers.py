from __future__ import annotations

import base64
from types import SimpleNamespace
from typing import Any

import httpx
import pytest


def test_image_provider_options_read_home_env_fallback(
    monkeypatch: pytest.MonkeyPatch, tmp_path
) -> None:
    from app.config import get_settings
    from app.services import image_generation_providers as providers

    home_env = tmp_path / ".env"
    home_env.write_text("OPENAI_API_KEY=home-openai-key\n", encoding="utf-8")
    monkeypatch.setattr(providers.Path, "home", lambda: tmp_path)
    monkeypatch.setenv("OPENAI_API_KEY", "")
    get_settings.cache_clear()

    options = providers.image_provider_options()
    openai = next(option for option in options if option.provider.id == "openai")

    assert openai.api_key_configured is True
    assert openai.model == "gpt-image-2"


def test_image_provider_options_include_doubao_with_ark_api_key(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.config import get_settings
    from app.services import image_generation_providers as providers

    monkeypatch.setenv("ARK_API_KEY", "ark-test-key")
    monkeypatch.setenv("DOUBAO_MODEL_IMAGE", "doubao-test-image")
    get_settings.cache_clear()

    options = providers.image_provider_options()
    doubao = next(option for option in options if option.provider.id == "doubao")

    assert doubao.provider.display_name == "Doubao Seedream"
    assert doubao.provider.api_key_env == "ARK_API_KEY"
    assert doubao.api_key_configured is True
    assert doubao.model == "doubao-test-image"


@pytest.mark.asyncio
async def test_effective_image_provider_uses_system_config_override(db: object) -> None:
    from app.services import image_generation_providers as providers
    from app.services.system_config_service import set_image_provider_override

    _ = db
    await set_image_provider_override(provider_id="qwen", updated_by="admin")

    status = await providers.effective_image_provider_status()

    assert status.provider.id == "qwen"
    assert status.source == "system_config"


@pytest.mark.asyncio
async def test_openai_gpt_image_request_omits_legacy_response_format(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services import image_generation_providers as providers

    captured: dict[str, object] = {}

    class FakeImages:
        async def generate(self, **kwargs: object) -> SimpleNamespace:
            assert "response_format" not in kwargs
            captured.update(kwargs)
            encoded = base64.b64encode(b"fake-png-bytes").decode("ascii")
            return SimpleNamespace(data=[SimpleNamespace(b64_json=encoded)])

    class FakeAsyncOpenAI:
        def __init__(self, *, api_key: str) -> None:
            assert api_key == "test-key"
            self.images = FakeImages()

    monkeypatch.setattr(providers, "AsyncOpenAI", FakeAsyncOpenAI)

    payload = await providers._generate_openai_image(
        provider=providers.IMAGE_PROVIDER_SPECS["openai"],
        api_key="test-key",
        model="gpt-image-1",
        prompt="spellbook",
        timeout_seconds=12.0,
    )

    assert payload == b"fake-png-bytes"
    assert captured["model"] == "gpt-image-1"
    assert captured["output_format"] == "png"
    assert captured["background"] == "transparent"


@pytest.mark.asyncio
async def test_openai_image_request_omits_transparent_background_for_gpt_image_2(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services import image_generation_providers as providers

    captured: dict[str, object] = {}

    class FakeImages:
        async def generate(self, **kwargs: object) -> SimpleNamespace:
            assert "background" not in kwargs
            captured.update(kwargs)
            encoded = base64.b64encode(b"fake-png-bytes").decode("ascii")
            return SimpleNamespace(data=[SimpleNamespace(b64_json=encoded)])

    class FakeAsyncOpenAI:
        def __init__(self, *, api_key: str) -> None:
            self.images = FakeImages()

    monkeypatch.setattr(providers, "AsyncOpenAI", FakeAsyncOpenAI)

    payload = await providers._generate_openai_image(
        provider=providers.IMAGE_PROVIDER_SPECS["openai"],
        api_key="test-key",
        model="gpt-image-2",
        prompt="spellbook",
        timeout_seconds=12.0,
    )

    assert payload == b"fake-png-bytes"
    assert captured["model"] == "gpt-image-2"


@pytest.mark.asyncio
async def test_qwen_image_uses_multimodal_generation_endpoint(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services import image_generation_providers as providers

    requests: list[tuple[str, str, dict[str, Any] | None]] = []

    class FakeResponse:
        def __init__(
            self,
            *,
            json_body: dict[str, Any] | None = None,
            content: bytes = b"",
        ) -> None:
            self._json_body = json_body or {}
            self.content = content

        def json(self) -> dict[str, Any]:
            return self._json_body

        def raise_for_status(self) -> None:
            return None

    class FakeAsyncClient:
        def __init__(self, *, timeout: float) -> None:
            assert timeout == 12.0

        async def __aenter__(self) -> FakeAsyncClient:
            return self

        async def __aexit__(self, *exc: object) -> None:
            return None

        async def post(
            self,
            url: str,
            *,
            json: dict[str, Any],
            headers: dict[str, str],
        ) -> FakeResponse:
            requests.append(("POST", url, json))
            assert "X-DashScope-Async" not in headers
            return FakeResponse(
                json_body={
                    "output": {
                        "choices": [
                            {
                                "message": {
                                    "content": [
                                        {
                                            "image": "https://assets.example.test/qwen.png"
                                        }
                                    ]
                                }
                            }
                        ]
                    }
                }
            )

        async def get(
            self,
            url: str,
            *,
            headers: dict[str, str] | None = None,
        ) -> FakeResponse:
            requests.append(("GET", url, None))
            assert url == "https://assets.example.test/qwen.png"
            return FakeResponse(content=b"qwen-image-bytes")

    monkeypatch.setattr(providers.httpx, "AsyncClient", FakeAsyncClient)

    payload = await providers._generate_dashscope_image(
        provider=providers.IMAGE_PROVIDER_SPECS["qwen"],
        api_key="dashscope-test",
        model="qwen-image-2.0-pro",
        base_url="https://dashscope.aliyuncs.com",
        prompt="spellbook cover",
        timeout_seconds=12.0,
    )

    assert payload == b"qwen-image-bytes"
    method, url, body = requests[0]
    assert method == "POST"
    assert url == "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"
    assert body == {
        "model": "qwen-image-2.0-pro",
        "input": {
            "messages": [
                {
                    "role": "user",
                    "content": [{"text": "spellbook cover"}],
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


@pytest.mark.asyncio
async def test_qwen_image_raises_when_response_has_no_image_url(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services import image_generation_providers as providers

    class FakeResponse:
        def __init__(
            self,
            *,
            json_body: dict[str, Any] | None = None,
            content: bytes = b"",
        ) -> None:
            self._json_body = json_body or {}
            self.content = content

        def json(self) -> dict[str, Any]:
            return self._json_body

        def raise_for_status(self) -> None:
            return None

    class FakeAsyncClient:
        def __init__(self, *, timeout: float) -> None:
            _ = timeout

        async def __aenter__(self) -> FakeAsyncClient:
            return self

        async def __aexit__(self, *exc: object) -> None:
            return None

        async def post(
            self,
            url: str,
            *,
            json: dict[str, Any],
            headers: dict[str, str],
        ) -> FakeResponse:
            _ = url, json, headers
            return FakeResponse(json_body={"output": {"choices": []}})

        async def get(
            self,
            url: str,
            *,
            headers: dict[str, str] | None = None,
        ) -> FakeResponse:
            _ = url, headers
            return FakeResponse(content=b"qwen-image-bytes")

    monkeypatch.setattr(providers.httpx, "AsyncClient", FakeAsyncClient)

    with pytest.raises(providers.LlmCallError, match="returned no image URL"):
        await providers._generate_dashscope_image(
            provider=providers.IMAGE_PROVIDER_SPECS["qwen"],
            api_key="dashscope-test",
            model="qwen-image-2.0-pro",
            base_url="https://dashscope.aliyuncs.com",
            prompt="spellbook cover",
            timeout_seconds=12.0,
        )


@pytest.mark.asyncio
async def test_doubao_image_request_posts_to_ark_and_downloads_image(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services import image_generation_providers as providers

    calls: list[tuple[str, str, dict[str, Any] | None, dict[str, str] | None]] = []

    class FakeAsyncClient:
        def __init__(self, *, timeout: float) -> None:
            assert timeout == 12.0

        async def __aenter__(self) -> FakeAsyncClient:
            return self

        async def __aexit__(self, *exc: object) -> None:
            return None

        async def post(
            self,
            url: str,
            *,
            json: dict[str, Any],
            headers: dict[str, str],
        ) -> httpx.Response:
            calls.append(("POST", url, json, headers))
            return httpx.Response(
                200,
                request=httpx.Request("POST", url),
                json={"data": [{"url": "https://assets.example.test/generated.png"}]},
            )

        async def get(self, url: str) -> httpx.Response:
            calls.append(("GET", url, None, None))
            return httpx.Response(
                200,
                request=httpx.Request("GET", url),
                content=b"downloaded-image-bytes",
            )

    monkeypatch.setattr(providers.httpx, "AsyncClient", FakeAsyncClient)

    payload = await providers._generate_doubao_image(
        provider=providers.IMAGE_PROVIDER_SPECS["doubao"],
        api_key="ark-test-key",
        model="doubao-seedream-4-5-251128",
        prompt="spellbook",
        timeout_seconds=12.0,
    )

    assert payload == b"downloaded-image-bytes"
    assert calls == [
        (
            "POST",
            "https://ark.cn-beijing.volces.com/api/v3/images/generations",
            {
                "model": "doubao-seedream-4-5-251128",
                "prompt": "spellbook",
                "sequential_image_generation": "disabled",
                "response_format": "url",
                "size": "2K",
                "stream": False,
                "watermark": True,
            },
            {
                "Authorization": "Bearer ark-test-key",
                "Content-Type": "application/json",
            },
        ),
        ("GET", "https://assets.example.test/generated.png", None, None),
    ]


@pytest.mark.asyncio
async def test_doubao_image_generation_maps_missing_url_to_llm_call_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services import image_generation_providers as providers
    from app.services.llm_service import LlmCallError

    class FakeAsyncClient:
        def __init__(self, *, timeout: float) -> None:
            _ = timeout

        async def __aenter__(self) -> FakeAsyncClient:
            return self

        async def __aexit__(self, *exc: object) -> None:
            return None

        async def post(
            self,
            url: str,
            *,
            json: dict[str, Any],
            headers: dict[str, str],
        ) -> httpx.Response:
            _ = (url, json, headers)
            return httpx.Response(
                200,
                request=httpx.Request("POST", url),
                json={"data": [{}]},
            )

    monkeypatch.setattr(providers.httpx, "AsyncClient", FakeAsyncClient)

    with pytest.raises(LlmCallError, match="returned no image URL"):
        await providers._generate_doubao_image(
            provider=providers.IMAGE_PROVIDER_SPECS["doubao"],
            api_key="ark-test-key",
            model="doubao-seedream-4-5-251128",
            prompt="spellbook",
            timeout_seconds=12.0,
        )


@pytest.mark.asyncio
async def test_doubao_image_generation_maps_http_error_to_llm_call_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services import image_generation_providers as providers
    from app.services.llm_service import LlmCallError

    class FakeAsyncClient:
        def __init__(self, *, timeout: float) -> None:
            _ = timeout

        async def __aenter__(self) -> FakeAsyncClient:
            return self

        async def __aexit__(self, *exc: object) -> None:
            return None

        async def post(
            self,
            url: str,
            *,
            json: dict[str, Any],
            headers: dict[str, str],
        ) -> httpx.Response:
            _ = (json, headers)
            request = httpx.Request("POST", url)
            return httpx.Response(500, request=request, text="boom")

    monkeypatch.setattr(providers.httpx, "AsyncClient", FakeAsyncClient)

    with pytest.raises(LlmCallError, match="Doubao Seedream image call failed"):
        await providers._generate_doubao_image(
            provider=providers.IMAGE_PROVIDER_SPECS["doubao"],
            api_key="ark-test-key",
            model="doubao-seedream-4-5-251128",
            prompt="spellbook",
            timeout_seconds=12.0,
        )


@pytest.mark.asyncio
async def test_generate_spellbook_cover_png_routes_to_doubao_provider(
    db: object,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.config import get_settings
    from app.services import image_generation_providers as providers

    _ = db
    monkeypatch.setenv("IMAGE_PROVIDER", "doubao")
    monkeypatch.setenv("ARK_API_KEY", "ark-test-key")
    monkeypatch.setenv("DOUBAO_MODEL_IMAGE", "doubao-test-image")
    get_settings.cache_clear()
    captured: dict[str, object] = {}

    async def fake_generate_doubao_image(**kwargs: object) -> bytes:
        captured.update(kwargs)
        return b"doubao-png-bytes"

    monkeypatch.setattr(providers, "_generate_doubao_image", fake_generate_doubao_image)

    model, payload = await providers.generate_spellbook_cover_png(
        pack_name="Fruit Forest",
        words=[{"word": "apple"}],
        prompt="custom spellbook prompt",
        timeout_seconds=12.0,
    )

    assert model == "doubao-test-image"
    assert payload == b"doubao-png-bytes"
    assert captured["provider"] == providers.IMAGE_PROVIDER_SPECS["doubao"]
    assert captured["api_key"] == "ark-test-key"
    assert captured["model"] == "doubao-test-image"
    assert captured["prompt"] == "custom spellbook prompt"
