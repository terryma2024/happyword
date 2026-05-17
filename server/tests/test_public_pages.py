from __future__ import annotations

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("path", "expected"),
    [
        ("/privacy", "魔法背单词隐私政策"),
        ("/terms", "魔法背单词用户协议"),
        ("/support", "魔法背单词支持"),
    ],
)
async def test_public_store_pages_are_reachable_without_login(
    client: AsyncClient, path: str, expected: str
) -> None:
    response = await client.get(path)

    assert response.status_code == 200
    assert expected in response.text
    assert "退出登录" not in response.text
