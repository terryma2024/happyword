from __future__ import annotations

from datetime import UTC, datetime
from io import BytesIO

import pytest
from PIL import Image

from app.models.family_pack_definition import FamilyPackDefinition


def test_build_spellbook_cover_prompt_requests_stable_book_icon_composition() -> None:
    from app.services.spellbook_cover_service import build_spellbook_cover_prompt

    prompt = build_spellbook_cover_prompt(
        pack_name="Fruit Forest",
        words=[{"word": "apple", "meaningZh": "苹果"}],
    )

    assert "Fruit Forest" in prompt
    assert "apple" in prompt
    assert "128x128" in prompt
    assert "transparent background" in prompt
    assert "isometric app icon" in prompt
    assert "closed magic book" in prompt
    assert "gold corner protectors" in prompt
    assert "ribbon bookmark" in prompt
    assert "center emblem" in prompt
    assert "Only vary the book color and the center emblem" in prompt
    assert "Template lock" in prompt
    assert "four gold corner protectors" in prompt
    assert "spine on the left" in prompt
    assert "flat-lying closed book" in prompt
    assert "diagonal flat book orientation" in prompt
    assert "long axis runs from upper-left to lower-right" in prompt
    assert "front cover is a slanted parallelogram" in prompt
    assert "not a vertical rectangle" in prompt
    assert "not standing upright" in prompt
    assert "seen from above" in prompt
    assert "thin cream page strips" in prompt
    assert "right page block visible" in prompt
    assert "bookmark near the lower-left corner" in prompt
    assert "center emblem around 30% of the front cover" in prompt
    assert "tiny gold stars" in prompt
    assert "small magical sparkles" in prompt
    assert "thin golden orbit arcs" in prompt
    assert "Do not draw the pack name" in prompt
    assert "no words anywhere" in prompt
    assert "Magic, ABC, title, label" in prompt


@pytest.mark.asyncio
async def test_generate_and_attach_spellbook_cover_uploads_blob_and_updates_scene(
    db: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.services import blob_service, image_generation_providers
    from app.services.spellbook_cover_service import generate_and_attach_spellbook_cover

    _ = db
    definition = FamilyPackDefinition(
        pack_id="gpk-fruit-forest",
        family_id="__global__",
        name="Fruit Forest",
        description=None,
        scene={"storyZh": "水果森林的入口亮了起来。"},
        state="active",
        created_at=datetime.now(tz=UTC),
        updated_at=datetime.now(tz=UTC),
        archived_at=None,
        created_by_parent_id="admin",
    )
    await definition.insert()
    source = BytesIO()
    Image.new("RGBA", (32, 32), (255, 0, 0, 255)).save(source, format="PNG")
    source_png = source.getvalue()

    async def fake_generate_spellbook_cover_png(
        *, pack_name: str, words: list[dict[str, object]], prompt: str
    ) -> tuple[str, bytes]:
        assert pack_name == "Fruit Forest"
        assert words == [{"word": "apple"}]
        assert "Fruit Forest" in prompt
        return "fake-image-model", source_png

    async def fake_upload_spellbook_cover(
        pack_id: str, image_bytes: bytes, mime: str
    ) -> str:
        assert pack_id == "gpk-fruit-forest"
        assert mime == "image/png"
        normalized = Image.open(BytesIO(image_bytes))
        assert normalized.size == (128, 128)
        assert normalized.mode == "RGBA"
        return "https://assets.example.test/spellbook-covers/gpk-fruit-forest.png"

    monkeypatch.setattr(
        image_generation_providers,
        "generate_spellbook_cover_png",
        fake_generate_spellbook_cover_png,
    )
    monkeypatch.setattr(blob_service, "upload_spellbook_cover", fake_upload_spellbook_cover)

    model, url, updated = await generate_and_attach_spellbook_cover(
        definition=definition,
        words=[{"word": "apple"}],
    )

    assert model == "fake-image-model"
    assert url == "https://assets.example.test/spellbook-covers/gpk-fruit-forest.png"
    assert updated.scene == {
        "storyZh": "水果森林的入口亮了起来。",
        "spellbookCoverUrl": url,
    }
