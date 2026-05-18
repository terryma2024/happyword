from __future__ import annotations

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("path", "expected"),
    [
        ("/privacy", "魔法背单词隐私政策"),
        ("/support", "魔法背单词支持"),
        ("/report_and_appeal", "投诉与举报入口"),
    ],
)
async def test_public_store_pages_are_reachable_without_login(
    client: AsyncClient, path: str, expected: str
) -> None:
    response = await client.get(path)

    assert response.status_code == 200
    assert expected in response.text
    assert "退出登录" not in response.text


@pytest.mark.asyncio
async def test_report_and_appeal_page_includes_contact_email(client: AsyncClient) -> None:
    response = await client.get("/report_and_appeal")

    assert response.status_code == 200
    assert "matianyi2023@gmail.com" in response.text
    assert "投诉" in response.text
    assert "举报" in response.text
