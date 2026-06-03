from __future__ import annotations

from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from httpx import AsyncClient


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("path", "expected"),
    [
        ("/privacy", "魔法背单词隐私政策"),
        ("/terms", "魔法背单词用户协议"),
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


@pytest.mark.asyncio
async def test_public_pages_include_icp_footer(client: AsyncClient) -> None:
    response = await client.get("/privacy")

    assert response.status_code == 200
    assert "沪ICP备2026023209号-1" in response.text
    assert 'href="https://beian.miit.gov.cn/"' in response.text


@pytest.mark.asyncio
async def test_privacy_page_matches_current_cloudbase_stack(client: AsyncClient) -> None:
    response = await client.get("/privacy")

    assert response.status_code == 200
    assert "最后更新：2026-06-03" in response.text
    assert "腾讯云 CloudBase Run" in response.text
    assert "腾讯 COS" in response.text
    assert "上海 Lighthouse MongoDB" in response.text
    assert "通义千问（Qwen）视觉能力" in response.text
    assert "Vercel 托管和对象存储" not in response.text
    assert "OpenAI 视觉能力" not in response.text
