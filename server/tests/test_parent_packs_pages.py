from __future__ import annotations

from typing import TYPE_CHECKING

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
async def test_parent_packs_list_renders_empty_state(parent_client: tuple[AsyncClient, str]) -> None:
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
async def test_pack_import_page_disables_duplicate_submits(parent_client: tuple[AsyncClient, str]) -> None:
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
    assert 'submitButton.disabled = true' in resp.text
