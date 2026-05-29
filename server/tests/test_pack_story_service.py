from __future__ import annotations

import pytest


def test_build_pack_story_prompt_requests_bilingual_story_json() -> None:
    from app.services.pack_story_service import build_pack_story_prompt

    prompt = build_pack_story_prompt(
        pack_name="School Castle",
        words=[
            {
                "word": "book",
                "meaningZh": "书",
                "category": "school",
                "difficulty": 1,
            }
        ],
    )

    assert "story_en" in prompt
    assert "story_zh" in prompt
    assert "scene.storyEn" in prompt
    assert "scene.storyZh" in prompt
    assert "School Castle" in prompt
    assert "book" in prompt


@pytest.mark.asyncio
async def test_generate_pack_story_normalizes_provider_payload(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services import llm_providers
    from app.services.pack_story_service import generate_pack_story

    async def fake_generate_json_text_with_provider(
        *, prompt: str, timeout_seconds: float
    ) -> tuple[str, dict[str, object]]:
        assert "Fruit Forest" in prompt
        assert timeout_seconds > 0
        return (
            "fake-story-model",
            {
                "story_en": "Fruit lanterns sparkle beside every new word.",
                "story_zh": "水果灯笼在每个新单词旁闪闪发光。",
            },
        )

    monkeypatch.setattr(
        llm_providers,
        "generate_json_text_with_provider",
        fake_generate_json_text_with_provider,
    )

    model, story = await generate_pack_story(
        pack_name="Fruit Forest",
        words=[{"word": "apple", "meaningZh": "苹果", "difficulty": 1}],
    )

    assert model == "fake-story-model"
    assert story == {
        "storyEn": "Fruit lanterns sparkle beside every new word.",
        "storyZh": "水果灯笼在每个新单词旁闪闪发光。",
    }
