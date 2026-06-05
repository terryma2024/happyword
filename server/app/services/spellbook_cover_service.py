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
        "Create one polished 128x128 PNG isometric app icon on a transparent background.\n"
        "Template lock: repeat the same single-book template every time. Use one "
        "flat-lying closed book, a closed magic book filling about 86% of the canvas, "
        "front cover visible in a diagonal flat book orientation, spine on the left, "
        "seen from above in a low 3/4 isometric camera angle. The long axis runs from "
        "upper-left to lower-right across the canvas. The front cover is a slanted "
        "parallelogram, not a vertical rectangle; the book lies flat, not standing "
        "upright. The top edge slants gently down to the right, the bottom edge is "
        "short, and the right page block visible as thin cream page strips. "
        "Show thick cream pages only on the bottom and right edges, four gold corner "
        "protectors, small gold rivets, one ribbon bookmark near the lower-left corner, "
        "and one circular "
        "center emblem around 30% of the front cover.\n"
        "Style reference: whimsical children's learning game icon, crisp 3D cartoon, "
        "clean silhouette, saturated but balanced colors, soft shadows painted only on "
        "the book, readable at tiny app icon size.\n"
        "Variation rule: Only vary the book color and the center emblem based on the "
        "pack theme and sample words. Keep the book shape, camera angle, gold hardware, "
        "page block, four corner protectors, center emblem position, and ribbon "
        "bookmark consistent every time. Use one solid cover color, not split color "
        "panels.\n"
        "Center emblem: use a simple symbolic object for the pack theme inside the "
        "round medallion, no text.\n"
        "Magical cover details: add a few tiny gold stars, small magical sparkles, "
        "and thin golden orbit arcs on the cover around the center emblem. Keep these "
        "decorations sparse, symmetric, and flat on the book cover.\n"
        "Text ban: no words anywhere. Do not draw the pack name, Magic, ABC, title, "
        "label, letters, numbers, runes, captions, stamps, or text-like marks.\n"
        "Avoid: open book, multiple books, human characters, background scenery, UI "
        "frames, checkerboard pattern, watermarks, logos, photorealism, standing "
        "vertical book, upright book on its edge, vertical rectangle cover, messy "
        "perspective, cropped corners, extra objects outside the book.\n\n"
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
