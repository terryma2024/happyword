from __future__ import annotations

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
