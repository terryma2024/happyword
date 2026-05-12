from __future__ import annotations

import pytest
from httpx import ASGITransport, AsyncClient


async def _make_parent_client(*, email: str = "import@example.com") -> tuple[AsyncClient, str]:
    from app.main import app
    from app.services.auth_service import create_session_token
    from app.services.family_service import create_family_for_parent

    family, user = await create_family_for_parent(email=email)
    token = create_session_token(role="parent", identifier=user.username)
    return (
        AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
            cookies={"wm_session": token},
        ),
        family.family_id,
    )


@pytest.mark.asyncio
async def test_import_image_writes_draft_only(
    db: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.services import family_pack_import_service

    async def fake_extract(payload: bytes, mime: str) -> tuple[str, dict[str, object]]:
        return (
            "fake-model",
            {
                "title": "Unit 1",
                "category": {"id": "unit1", "labelZh": "第一单元"},
                "words": [
                    {
                        "word": "apple",
                        "meaningZh": "苹果",
                        "category": "fruit",
                        "difficulty": 1,
                        "example_en": "I eat an apple.",
                        "example_zh": "我吃了一个苹果。",
                    },
                    {
                        "word": "banana",
                        "meaningZh": "香蕉",
                        "category": "fruit",
                        "difficulty": 1,
                        "example_en": "This is a banana.",
                    },
                ],
            },
        )

    monkeypatch.setattr(family_pack_import_service, "extract_family_pack_image", fake_extract)

    async def fake_upload(payload: bytes, mime: str) -> str:
        return "mock://family-pack-image.png"

    monkeypatch.setattr(family_pack_import_service, "upload_family_pack_image", fake_upload)

    ac, family_id = await _make_parent_client()
    prefix = f"fam-{family_id.removeprefix('fam-')[:8]}-"
    async with ac:
        created = await ac.post("/api/v1/parent/family-packs", json={"name": "Photo"})
        pack_id = created.json()["pack_id"]
        resp = await ac.post(
            f"/api/v1/parent/family-packs/{pack_id}/import-image",
            files={"image": ("page.png", b"fake-png", "image/png")},
        )
        detail = await ac.get(f"/api/v1/parent/family-packs/{pack_id}")

    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["imported_count"] == 2
    assert body["draft"]["word_count"] == 2
    assert body["source_image_url"] == "mock://family-pack-image.png"
    assert detail.json()["pointer"] is None
    ids = {w["id"] for w in detail.json()["draft"]["words"]}
    assert ids == {f"{prefix}apple", f"{prefix}banana"}
    by_id = {w["id"]: w for w in detail.json()["draft"]["words"]}
    assert by_id[f"{prefix}apple"].get("exampleEn") == "I eat an apple."
    assert by_id[f"{prefix}apple"].get("exampleZh") == "我吃了一个苹果。"
    assert by_id[f"{prefix}banana"].get("exampleEn") == "This is a banana."


def test_extracted_words_to_rows_maps_example_fields(db: object) -> None:
    from app.services.family_pack_import_service import extracted_words_to_rows

    rows = extracted_words_to_rows(
        family_id="fam-aaaaaaaa",
        extracted={
            "category_id": "zoo",
            "words": [
                {
                    "word": "cat",
                    "meaningZh": "猫",
                    "difficulty": 2,
                    "example_en": "The cat sleeps.",
                    "example_zh": "猫在睡觉。",
                },
                {
                    "word": "dog",
                    "meaningZh": "狗",
                    "difficulty": 2,
                    "example": {"en": "A dog runs.", "zh": "狗在跑。"},
                },
            ],
        },
    )
    assert rows[0]["example_en"] == "The cat sleeps."
    assert rows[0]["example_zh"] == "猫在睡觉。"
    assert rows[1]["example_en"] == "A dog runs."
    assert rows[1]["example_zh"] == "狗在跑。"


@pytest.mark.asyncio
async def test_import_image_rejects_text_file(db: object) -> None:
    ac, _ = await _make_parent_client(email="bad-import@example.com")
    async with ac:
        created = await ac.post("/api/v1/parent/family-packs", json={"name": "Bad"})
        pack_id = created.json()["pack_id"]
        resp = await ac.post(
            f"/api/v1/parent/family-packs/{pack_id}/import-image",
            files={"image": ("notes.txt", b"hello", "text/plain")},
        )

    assert resp.status_code == 415
    assert resp.json()["detail"]["error"]["code"] == "UNSUPPORTED_MEDIA_TYPE"
