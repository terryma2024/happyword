"""Tests for the CI helper that mirrors preview Mongo DB name resolution."""

import hashlib

from scripts.resolve_preview_db_name import resolve_preview_db_name


def test_resolve_preview_db_name_uses_pr_when_runtime_pr_env_is_present() -> None:
    assert (
        resolve_preview_db_name(
            template="happyword_pr_{pr}_e2e",
            pr="45",
            branch="cursor/devmenu-bypass-secret-automation",
        )
        == "happyword_pr_45_e2e"
    )


def test_resolve_preview_db_name_matches_branch_hash_when_pr_env_is_empty() -> None:
    branch = "cursor/devmenu-bypass-secret-automation"
    expected_hash = hashlib.sha1(branch.encode("utf-8")).hexdigest()[:8]

    assert (
        resolve_preview_db_name(
            template="happyword_pr_{pr}_e2e",
            pr="",
            branch=branch,
        )
        == f"happyword_pr_br_{expected_hash}_e2e"
    )
