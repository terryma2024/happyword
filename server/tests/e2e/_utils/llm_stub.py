"""Helpers for deployed E2E tests that exercise LLM routes without live LLM calls."""

import os

import pytest

_HEADER = "x-happyword-e2e-llm-stub"


def llm_stub_headers() -> dict[str, str]:
    secret = os.environ.get("E2E_LLM_STUB_SECRET", "").strip()
    if not secret:
        pytest.skip(
            "E2E_LLM_STUB_SECRET is not set; target must configure the matching "
            "server-side E2E_LLM_STUB_SECRET to run LLM e2e tests"
        )
    return {_HEADER: secret}
