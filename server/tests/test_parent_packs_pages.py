from __future__ import annotations

from typing import TYPE_CHECKING
from urllib.parse import urlencode

import pytest
from bs4 import BeautifulSoup
from httpx import ASGITransport, AsyncClient

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


@pytest.fixture
async def parent_client(db: object) -> AsyncIterator[tuple[AsyncClient, str]]:
    from app.main import app
    from app.services.auth_service import create_session_token
    from app.services.family_service import create_family_for_parent

    _, user = await create_family_for_parent(email="packs-page@example.com")
    fid = user.family_id or "_"
    token = create_session_token(role="parent", identifier=user.username)
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        cookies={"wm_session": token},
        follow_redirects=False,
    ) as ac:
        yield ac, fid


@pytest.mark.asyncio
async def test_parent_packs_requires_login(db: object) -> None:
    from app.main import app

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        follow_redirects=False,
    ) as ac:
        resp = await ac.get("/family/_/packs/")

        assert resp.status_code in (303, 307)
        loc = resp.headers.get("location", "")
        assert loc.endswith("/family/login") or loc.endswith("/family/login/")


@pytest.mark.asyncio
async def test_parent_packs_list_renders_empty_state(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, fid = parent_client
    resp = await ac.get(f"/family/{fid}/packs/")
    assert resp.status_code == 200
    soup = BeautifulSoup(resp.text, "html.parser")
    assert soup.find(id="packs-list") is not None
    assert "还没有词库" in resp.text
    assert f"/family/{fid}/packs/new" in resp.text


@pytest.mark.asyncio
async def test_create_pack_form_redirects_to_detail(parent_client: tuple[AsyncClient, str]) -> None:
    ac, fid = parent_client
    resp = await ac.post(
        f"/family/{fid}/packs/",
        data={"name": "三年级上 Unit 1", "description": "课本第一单元"},
    )
    assert resp.status_code in (303, 307)
    assert resp.headers["location"].startswith(f"/family/{fid}/packs/pck-")


@pytest.mark.asyncio
async def test_parent_packs_list_renders_delete_form(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, fid = parent_client
    created = await ac.post(f"/api/v1/family/{fid}/family-packs", json={"name": "Delete UI"})
    pack_id = created.json()["pack_id"]

    resp = await ac.get(f"/family/{fid}/packs/")

    assert resp.status_code == 200
    soup = BeautifulSoup(resp.text, "html.parser")
    form = soup.find(id=f"pack-delete-form-{pack_id}")
    detail_link = soup.find("a", href=f"/family/{fid}/packs/{pack_id}")
    assert detail_link is not None
    assert form is not None
    assert form.get("method") == "post"
    assert form.get("action") == f"/family/{fid}/packs/{pack_id}/delete"
    assert "确认删除词库 Delete UI" in (form.get("onsubmit") or "")
    assert form.find("button", string="删除") is not None


@pytest.mark.asyncio
async def test_parent_pack_delete_form_removes_pack_records(
    parent_client: tuple[AsyncClient, str],
) -> None:
    from app.models.family_pack_definition import FamilyPackDefinition
    from app.models.family_pack_draft import FamilyPackDraft
    from app.models.family_pack_pointer import FamilyPackPointer
    from app.models.family_word_pack import FamilyWordPack

    ac, fid = parent_client
    created = await ac.post(f"/api/v1/family/{fid}/family-packs", json={"name": "Delete Pack"})
    pack_id = created.json()["pack_id"]
    await ac.put(
        f"/api/v1/family/{fid}/family-packs/{pack_id}/draft/words/apple",
        json={"source": "global"},
    )
    await ac.post(f"/api/v1/family/{fid}/family-packs/{pack_id}/publish", json={"notes": "v1"})
    await ac.put(
        f"/api/v1/family/{fid}/family-packs/{pack_id}/draft/words/banana",
        json={"source": "global"},
    )
    await ac.post(f"/api/v1/family/{fid}/family-packs/{pack_id}/publish", json={"notes": "v2"})

    resp = await ac.post(f"/family/{fid}/packs/{pack_id}/delete")

    assert resp.status_code in (303, 307)
    assert resp.headers["location"] == f"/family/{fid}/packs/?flash_ok=deleted"
    assert await FamilyPackDefinition.find_one(FamilyPackDefinition.pack_id == pack_id) is None
    assert await FamilyPackDraft.find_one(FamilyPackDraft.pack_definition_id == pack_id) is None
    assert await FamilyPackPointer.find_one(FamilyPackPointer.pack_definition_id == pack_id) is None
    assert await FamilyWordPack.find(FamilyWordPack.pack_definition_id == pack_id).count() == 0
    detail = await ac.get(f"/api/v1/family/{fid}/family-packs/{pack_id}")
    assert detail.status_code == 404
    listed = await ac.get(f"/family/{fid}/packs/")
    assert "Delete Pack" not in listed.text


@pytest.mark.asyncio
async def test_pack_detail_renders_draft_table(parent_client: tuple[AsyncClient, str]) -> None:
    ac, fid = parent_client
    created = await ac.post(f"/api/v1/family/{fid}/family-packs", json={"name": "Detail"})
    pack_id = created.json()["pack_id"]
    resp = await ac.get(f"/family/{fid}/packs/{pack_id}")
    assert resp.status_code == 200
    soup = BeautifulSoup(resp.text, "html.parser")
    assert soup.find(id="draft-word-table") is not None
    assert "发布词库" in resp.text
    assert f"/family/{fid}/packs/{pack_id}/import" in resp.text


@pytest.mark.asyncio
async def test_pack_detail_renders_title_edit_form(parent_client: tuple[AsyncClient, str]) -> None:
    ac, fid = parent_client
    created = await ac.post(
        f"/api/v1/family/{fid}/family-packs",
        json={
            "name": "Old title",
            "scene": {
                "storyEn": "A small story waits on the card.",
                "storyZh": "卡片上等着一个小故事。",
            },
        },
    )
    pack_id = created.json()["pack_id"]

    resp = await ac.get(f"/family/{fid}/packs/{pack_id}")

    assert resp.status_code == 200
    soup = BeautifulSoup(resp.text, "html.parser")
    form = soup.find(id="pack-title-form")
    title_input = soup.find(id="pack-title-input")
    submit = soup.find(id="pack-title-submit")
    assert form is not None
    assert form.get("action") == f"/family/{fid}/packs/{pack_id}/metadata"
    assert title_input is not None
    assert title_input.get("name") == "name"
    assert title_input.get("value") == "Old title"
    assert title_input.get("data-original-value") == "Old title"
    assert submit is not None
    assert "hidden" in (submit.get("class") or [])
    assert soup.find("textarea", attrs={"name": "storyEn"}) is not None
    assert soup.find("textarea", attrs={"name": "storyZh"}) is not None
    story_button = soup.find(id="pack-story-generate-submit")
    assert story_button is not None
    assert story_button.get_text(strip=True) == "🔄"
    assert story_button.get("form") == "pack-story-generate-form"
    assert "A small story waits on the card." in resp.text
    assert "卡片上等着一个小故事。" in resp.text
    assert 'titleInput.addEventListener("input"' in resp.text
    assert "titleSubmit.classList.toggle" in resp.text


@pytest.mark.asyncio
async def test_pack_detail_renders_batch_delete_controls(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, fid = parent_client
    created = await ac.post(f"/api/v1/family/{fid}/family-packs", json={"name": "Batch"})
    pack_id = created.json()["pack_id"]
    prefix = f"fam-{fid.removeprefix('fam-')[:8]}-"
    word_ids = [f"{prefix}apple", f"{prefix}banana"]
    for word_id, word in zip(word_ids, ["apple", "banana"], strict=True):
        upserted = await ac.put(
            f"/api/v1/family/{fid}/family-packs/{pack_id}/draft/words/{word_id}",
            json={
                "source": "custom",
                "word": word,
                "meaning_zh": word,
                "category": "fruit",
                "difficulty": 1,
            },
        )
        assert upserted.status_code == 200

    resp = await ac.get(f"/family/{fid}/packs/{pack_id}")

    assert resp.status_code == 200
    soup = BeautifulSoup(resp.text, "html.parser")
    form = soup.find(id="draft-batch-delete-form")
    select_all = soup.find(id="draft-select-all")
    checkboxes = soup.find_all("input", attrs={"name": "word_ids"})
    submit = soup.find(id="draft-batch-delete-submit")
    assert form is not None
    assert form.get("action") == f"/family/{fid}/packs/{pack_id}/draft/batch-delete"
    assert select_all is not None
    assert select_all.get("data-role") == "draft-select-all"
    assert [box.get("value") for box in checkboxes] == word_ids
    assert all(box.get("form") == "draft-batch-delete-form" for box in checkboxes)
    assert submit is not None
    assert submit.has_attr("disabled")
    assert "draftSelectAll.addEventListener" in resp.text
    assert "draftBatchDeleteSubmit.disabled" in resp.text


@pytest.mark.asyncio
async def test_batch_delete_form_removes_selected_words(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, fid = parent_client
    created = await ac.post(f"/api/v1/family/{fid}/family-packs", json={"name": "Batch delete"})
    pack_id = created.json()["pack_id"]
    prefix = f"fam-{fid.removeprefix('fam-')[:8]}-"
    word_ids = [f"{prefix}apple", f"{prefix}banana", f"{prefix}pear"]
    for word_id, word in zip(word_ids, ["apple", "banana", "pear"], strict=True):
        upserted = await ac.put(
            f"/api/v1/family/{fid}/family-packs/{pack_id}/draft/words/{word_id}",
            json={
                "source": "custom",
                "word": word,
                "meaning_zh": word,
                "category": "fruit",
                "difficulty": 1,
            },
        )
        assert upserted.status_code == 200

    resp = await ac.post(
        f"/family/{fid}/packs/{pack_id}/draft/batch-delete",
        content=urlencode([("word_ids", word_ids[0]), ("word_ids", word_ids[2])]),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )

    assert resp.status_code in (303, 307)
    assert resp.headers["location"] == f"/family/{fid}/packs/{pack_id}"
    detail = await ac.get(f"/api/v1/family/{fid}/family-packs/{pack_id}")
    remaining = [word["id"] for word in detail.json()["draft"]["words"]]
    assert remaining == [word_ids[1]]


@pytest.mark.asyncio
async def test_pack_detail_renders_split_controls(parent_client: tuple[AsyncClient, str]) -> None:
    ac, fid = parent_client
    created = await ac.post(f"/api/v1/family/{fid}/family-packs", json={"name": "Split UI"})
    pack_id = created.json()["pack_id"]
    resp = await ac.get(f"/family/{fid}/packs/{pack_id}")

    assert resp.status_code == 200
    soup = BeautifulSoup(resp.text, "html.parser")
    form = soup.find(id="draft-split-form")
    dialog = soup.find(id="draft-split-dialog")
    submit = soup.find(id="draft-split-submit")
    move_button = soup.find(id="draft-split-move-open")
    copy_button = soup.find(id="draft-split-copy-open")
    assert form is not None
    assert form.get("action") == f"/family/{fid}/packs/{pack_id}/draft/split"
    assert dialog is not None
    assert dialog.find("input", attrs={"name": "new_name"}) is not None
    assert dialog.find("input", attrs={"name": "new_description"}) is not None
    mode = dialog.find("input", attrs={"name": "mode"})
    assert mode is not None
    assert mode.get("type") == "hidden"
    assert soup.find("select", attrs={"name": "mode"}) is None
    assert move_button is not None
    assert move_button.get_text(strip=True) == "移动到新包"
    assert copy_button is not None
    assert copy_button.get_text(strip=True) == "复制到新包"
    assert submit is not None
    assert move_button.has_attr("disabled")
    assert copy_button.has_attr("disabled")


@pytest.mark.asyncio
async def test_split_form_moves_selected_words_to_new_pack(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, fid = parent_client
    created = await ac.post(
        f"/api/v1/family/{fid}/family-packs", json={"name": "Split Form Source"}
    )
    pack_id = created.json()["pack_id"]
    for word_id in ("global-a", "global-b", "global-c"):
        await ac.put(
            f"/api/v1/family/{fid}/family-packs/{pack_id}/draft/words/{word_id}",
            json={"source": "global"},
        )

    resp = await ac.post(
        f"/family/{fid}/packs/{pack_id}/draft/split",
        content=urlencode(
            [
                ("word_ids", "global-a"),
                ("word_ids", "global-c"),
                ("new_name", "Split Form New"),
                ("new_description", "from form"),
                ("mode", "move"),
            ]
        ),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )

    assert resp.status_code in (303, 307)
    assert resp.headers["location"].startswith(f"/family/{fid}/packs/pck-")
    assert "split_ok=move" in resp.headers["location"]

    source = await ac.get(f"/api/v1/family/{fid}/family-packs/{pack_id}")
    assert [w["id"] for w in source.json()["draft"]["words"]] == ["global-b"]


@pytest.mark.asyncio
async def test_pack_title_form_updates_definition(parent_client: tuple[AsyncClient, str]) -> None:
    ac, fid = parent_client
    created = await ac.post(f"/api/v1/family/{fid}/family-packs", json={"name": "Old title"})
    pack_id = created.json()["pack_id"]

    resp = await ac.post(
        f"/family/{fid}/packs/{pack_id}/metadata",
        data={"name": "New title"},
    )

    assert resp.status_code in (303, 307)
    assert resp.headers["location"] == f"/family/{fid}/packs/{pack_id}?title_ok=1"
    detail = await ac.get(f"/family/{fid}/packs/{pack_id}")
    assert detail.status_code == 200
    assert "New title" in detail.text
    assert "Old title" not in detail.text
    api_detail = await ac.get(f"/api/v1/family/{fid}/family-packs/{pack_id}")
    assert api_detail.json()["definition"]["name"] == "New title"


@pytest.mark.asyncio
async def test_pack_metadata_form_updates_scene_stories(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, fid = parent_client
    created = await ac.post(
        f"/api/v1/family/{fid}/family-packs",
        json={"name": "Story", "scene": {"bossName": "Keep Me"}},
    )
    pack_id = created.json()["pack_id"]

    resp = await ac.post(
        f"/family/{fid}/packs/{pack_id}/metadata",
        data={
            "name": "Story",
            "storyEn": "A tiny lantern shows the way.",
            "storyZh": "小灯笼照亮了前方的小路。",
        },
    )

    assert resp.status_code in (303, 307)
    api_detail = await ac.get(f"/api/v1/family/{fid}/family-packs/{pack_id}")
    scene = api_detail.json()["definition"]["scene"]
    assert scene["bossName"] == "Keep Me"
    assert scene["storyEn"] == "A tiny lantern shows the way."
    assert scene["storyZh"] == "小灯笼照亮了前方的小路。"


@pytest.mark.asyncio
async def test_pack_story_generate_form_updates_scene_stories(
    parent_client: tuple[AsyncClient, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.services import pack_story_service

    async def fake_generate_pack_story(
        *, pack_name: str, words: list[dict[str, object]]
    ) -> tuple[str, dict[str, str]]:
        assert pack_name == "Generate Story"
        assert words[0]["word"] == "apple"
        return (
            "fake-story-model",
            {
                "storyEn": "Fruit sparks dance beside a brave apple.",
                "storyZh": "水果火花陪着勇敢的苹果跳舞。",
            },
        )

    monkeypatch.setattr(pack_story_service, "generate_pack_story", fake_generate_pack_story)
    ac, fid = parent_client
    created = await ac.post(f"/api/v1/family/{fid}/family-packs", json={"name": "Generate Story"})
    pack_id = created.json()["pack_id"]
    prefix = f"fam-{fid.removeprefix('fam-')[:8]}-"
    await ac.put(
        f"/api/v1/family/{fid}/family-packs/{pack_id}/draft/words/{prefix}apple",
        json={
            "source": "custom",
            "word": "apple",
            "meaning_zh": "苹果",
            "category": "fruit",
            "difficulty": 1,
        },
    )

    resp = await ac.post(f"/family/{fid}/packs/{pack_id}/story/generate")

    assert resp.status_code in (303, 307)
    assert resp.headers["location"] == f"/family/{fid}/packs/{pack_id}?title_ok=1"
    api_detail = await ac.get(f"/api/v1/family/{fid}/family-packs/{pack_id}")
    scene = api_detail.json()["definition"]["scene"]
    assert scene["storyEn"] == "Fruit sparks dance beside a brave apple."
    assert scene["storyZh"] == "水果火花陪着勇敢的苹果跳舞。"


@pytest.mark.asyncio
async def test_pack_import_page_disables_duplicate_submits(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, fid = parent_client
    created = await ac.post(f"/api/v1/family/{fid}/family-packs", json={"name": "Import"})
    pack_id = created.json()["pack_id"]

    resp = await ac.get(f"/family/{fid}/packs/{pack_id}/import")

    assert resp.status_code == 200
    soup = BeautifulSoup(resp.text, "html.parser")
    form = soup.find(id="pack-import-form")
    button = soup.find(id="pack-import-submit")
    assert form is not None
    assert form.get("action") == f"/family/{fid}/packs/{pack_id}/import"
    assert button is not None
    assert button.get("data-submitting-label") == "导入中，请稍候..."
    assert "disabled:cursor-not-allowed" in (button.get("class") or [])
    assert 'form.dataset.submitting === "true"' in resp.text
    assert "submitButton.disabled = true" in resp.text
