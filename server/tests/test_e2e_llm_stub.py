"""Tests for the request-scoped E2E LLM stub used by deployed E2E tests."""

from app.schemas.llm import ScanResult


async def test_e2e_llm_stub_short_circuits_vision_and_text_paths() -> None:
    from app.services import e2e_llm_stub, llm_providers, llm_service

    token = e2e_llm_stub.enable()
    try:
        model, lesson_payload = await llm_providers.extract_lesson_payload_with_provider(
            b"fake-image",
            "image/jpeg",
            prompt="Return lesson JSON",
            timeout_seconds=1,
        )
        assert model == "e2e-llm-stub"
        assert lesson_payload["words"][0]["word"] == "apple"

        model, story_payload = await llm_providers.generate_json_text_with_provider(
            prompt="Return story JSON",
            timeout_seconds=1,
        )
        assert model == "e2e-llm-stub"
        assert story_payload["story_en"] == "Apple and banana open a tiny market."

        model, scan_result = await llm_service.extract_target_vocabulary(
            b"fake-image",
            mime="image/jpeg",
        )
        assert model == "e2e-llm-stub"
        assert isinstance(scan_result, ScanResult)
        assert scan_result.words[1].word == "banana"

        model, distractors = await llm_service.extract_word_distractors(
            type("WordStub", (), {"word": "apple", "meaningZh": "苹果"})()
        )
        assert model == "e2e-llm-stub"
        assert distractors == ["pear", "grape", "orange"]
    finally:
        e2e_llm_stub.disable(token)
