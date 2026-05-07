"""Unit tests for `_resolve_db_name` template substitution."""

import hashlib

from app.config import _ATLAS_MAX_DB_NAME_BYTES, _resolve_db_name


def test_literal_name_passes_through() -> None:
    """A name with no placeholder is returned verbatim."""
    assert _resolve_db_name("happyword_staging", pr="", branch="main") == "happyword_staging"


def test_pr_substitutes_when_pr_set() -> None:
    """`{pr}` substitutes the Vercel-injected PR id."""
    assert (
        _resolve_db_name("happyword_pr_{pr}_e2e", pr="42", branch="feat/foo")
        == "happyword_pr_42_e2e"
    )


def test_pr_falls_back_to_branch_slug_when_pr_empty() -> None:
    """When PR id is empty, `{pr}` substitutes `branch_<slug>`."""
    assert (
        _resolve_db_name("happyword_pr_{pr}_e2e", pr="", branch="feat/wow")
        == "happyword_pr_branch_feat_wow_e2e"
    )


def test_branch_with_special_chars_is_sanitised() -> None:
    """Non-alphanumeric chars collapse to underscores; leading/trailing trimmed."""
    assert (
        _resolve_db_name("happyword_branch_{branch}_e2e", pr="", branch="-Foo/Bar.Baz!-")
        == "happyword_branch_foo_bar_baz_e2e"
    )


def test_both_placeholders_substitute_independently() -> None:
    """A template containing both `{pr}` and `{branch}` substitutes each."""
    assert (
        _resolve_db_name("hw_pr{pr}_br{branch}_e2e", pr="7", branch="main") == "hw_pr7_brmain_e2e"
    )


def test_long_branch_falls_back_to_hash_to_fit_atlas_38_byte_cap() -> None:
    """The branch from the original AtlasError 8000 bug: the readable
    `happyword_pr_branch_cursor_bump_actions_to_node24_e2e` (53 bytes) would be
    rejected, so we degrade to `happyword_pr_br_<sha1[:8]>_e2e` instead.
    """
    branch = "cursor/bump-actions-to-node24"
    expected_hash = hashlib.sha1(branch.encode("utf-8")).hexdigest()[:8]

    name = _resolve_db_name("happyword_pr_{pr}_e2e", pr="", branch=branch)

    assert name == f"happyword_pr_br_{expected_hash}_e2e"
    assert len(name) <= _ATLAS_MAX_DB_NAME_BYTES


def test_pathological_branch_still_within_atlas_cap() -> None:
    """Even a 200-char branch must produce a name Atlas will accept."""
    branch = "cursor/" + "x" * 200

    name = _resolve_db_name("happyword_pr_{pr}_e2e", pr="", branch=branch)

    assert len(name) <= _ATLAS_MAX_DB_NAME_BYTES


def test_hash_fallback_is_deterministic_per_branch() -> None:
    """Same branch ⇒ same hashed DB name across calls (no per-restart churn)."""
    branch = "cursor/bump-actions-to-node24"

    first = _resolve_db_name("happyword_pr_{pr}_e2e", pr="", branch=branch)
    second = _resolve_db_name("happyword_pr_{pr}_e2e", pr="", branch=branch)

    assert first == second


def test_hash_fallback_distinguishes_distinct_branches() -> None:
    """Different long branches must not collide on the same fallback DB."""
    a = _resolve_db_name("happyword_pr_{pr}_e2e", pr="", branch="cursor/aaaaaaaaaaaaaaaaaaaa")
    b = _resolve_db_name("happyword_pr_{pr}_e2e", pr="", branch="cursor/bbbbbbbbbbbbbbbbbbbb")

    assert a != b


def test_branch_template_also_falls_back_to_hash_when_overflowing() -> None:
    """Templates that only reference `{branch}` get the same protection."""
    long_branch = "feat/a-very-very-very-very-very-very-long-branch-name"
    expected_hash = hashlib.sha1(long_branch.encode("utf-8")).hexdigest()[:8]

    name = _resolve_db_name("happyword_branch_{branch}_e2e", pr="", branch=long_branch)

    assert name == f"happyword_branch_{expected_hash}_e2e"
    assert len(name) <= _ATLAS_MAX_DB_NAME_BYTES


def test_hash_fallback_uses_raw_branch_not_slug() -> None:
    """Two branches that slug-collide should still get distinct DBs."""
    # `feat/foo-bar` and `feat/foo_bar` both slug to `feat_foo_bar`. Make
    # them long enough to trip the fallback so the hash branch matters.
    suffix = "x" * 60
    a = _resolve_db_name("happyword_pr_{pr}_e2e", pr="", branch=f"feat/foo-bar/{suffix}")
    b = _resolve_db_name("happyword_pr_{pr}_e2e", pr="", branch=f"feat/foo_bar/{suffix}")

    assert a != b
