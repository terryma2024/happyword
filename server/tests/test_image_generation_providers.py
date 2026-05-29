from __future__ import annotations

import base64
from types import SimpleNamespace

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
