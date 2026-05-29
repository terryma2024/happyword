from __future__ import annotations

from datetime import UTC, datetime

from app.models.system_config import SystemConfig

LLM_PROVIDER_CONFIG_KEY = "llm_provider"
IMAGE_PROVIDER_CONFIG_KEY = "image_provider"


async def get_config_value(key: str) -> str | None:
    row = await SystemConfig.find_one(SystemConfig.key == key)
    if row is None:
        return None
    value = row.value.strip()
    return value or None


async def set_config_value(
    *,
    key: str,
    value: str,
    updated_by: str | None,
) -> SystemConfig:
    clean_value = value.strip()
    row = await SystemConfig.find_one(SystemConfig.key == key)
    now = datetime.now(tz=UTC)
    if row is None:
        row = SystemConfig(
            key=key,
            value=clean_value,
            updated_at=now,
            updated_by=updated_by,
        )
        await row.insert()
        return row
    row.value = clean_value
    row.updated_at = now
    row.updated_by = updated_by
    await row.save()
    return row


async def get_llm_provider_override() -> str | None:
    return await get_config_value(LLM_PROVIDER_CONFIG_KEY)


async def set_llm_provider_override(
    *,
    provider_id: str,
    updated_by: str | None,
) -> SystemConfig:
    return await set_config_value(
        key=LLM_PROVIDER_CONFIG_KEY,
        value=provider_id,
        updated_by=updated_by,
    )


async def get_image_provider_override() -> str | None:
    return await get_config_value(IMAGE_PROVIDER_CONFIG_KEY)


async def set_image_provider_override(
    *,
    provider_id: str,
    updated_by: str | None,
) -> SystemConfig:
    return await set_config_value(
        key=IMAGE_PROVIDER_CONFIG_KEY,
        value=provider_id,
        updated_by=updated_by,
    )
