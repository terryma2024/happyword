"""Generate and persist spellbook cover images for vocabulary packs."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from io import BytesIO
from typing import TYPE_CHECKING, Any

from PIL import Image

from app.services import blob_service, image_generation_providers

if TYPE_CHECKING:
    from app.models.family_pack_definition import FamilyPackDefinition

_WORD_PREVIEW_LIMIT = 20


def _compact_word(item: dict[str, Any]) -> dict[str, Any]:
    compact: dict[str, Any] = {}
    for key in ("word", "meaningZh", "meaning_zh", "category"):
        value = item.get(key)
        if value is not None:
            compact[key] = value
    return compact


def build_spellbook_cover_prompt(*, pack_name: str, words: list[dict[str, Any]]) -> str:
    preview = [_compact_word(w) for w in words[:_WORD_PREVIEW_LIMIT]]
    return (
        "Create a polished 128x128 PNG icon on a transparent background.\n"
        "Subject: one magical vocabulary book, closed or slightly open, "
        "readable at app icon size.\n"
        "Style: whimsical children's learning game, bright, clean silhouette, "
        "no text, no letters.\n"
        "Avoid: UI frames, background scenery, watermarks, logos, photorealism.\n\n"
        f"Pack name: {pack_name.strip() or 'Vocabulary Pack'}\n"
        f"Sample words JSON: {json.dumps(preview, ensure_ascii=False)}"
    )


def _normalize_cover_png(image_bytes: bytes) -> bytes:
    image = Image.open(BytesIO(image_bytes)).convert("RGBA")
    image.thumbnail((128, 128), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    x = (128 - image.width) // 2
    y = (128 - image.height) // 2
    canvas.alpha_composite(image, (x, y))
    out = BytesIO()
    canvas.save(out, format="PNG", optimize=True)
    return out.getvalue()


async def generate_and_attach_spellbook_cover(
    *,
    definition: FamilyPackDefinition,
    words: list[dict[str, Any]],
) -> tuple[str, str, FamilyPackDefinition]:
    prompt = build_spellbook_cover_prompt(pack_name=definition.name, words=words)
    model, image_bytes = await image_generation_providers.generate_spellbook_cover_png(
        pack_name=definition.name,
        words=words,
        prompt=prompt,
    )
    image_bytes = _normalize_cover_png(image_bytes)
    public_url = await blob_service.upload_spellbook_cover(
        definition.pack_id,
        image_bytes,
        "image/png",
    )
    scene = dict(definition.scene)
    scene["spellbookCoverUrl"] = public_url
    definition.scene = scene
    definition.updated_at = datetime.now(tz=UTC)
    await definition.save()
    return model, public_url, definition
