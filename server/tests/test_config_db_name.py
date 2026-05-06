"""Unit tests for `_resolve_db_name` template substitution."""

from app.config import _resolve_db_name


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


def test_branch_slug_is_capped_at_32_chars() -> None:
    """Branch slug is truncated to 32 chars to keep Mongo DB names sane."""
    long_branch = "feat/a-very-very-very-very-very-very-long-branch-name"
    assert (
        _resolve_db_name("happyword_branch_{branch}_e2e", pr="", branch=long_branch)
        == "happyword_branch_feat_a_very_very_very_very_very__e2e"
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
        _resolve_db_name("hw_pr{pr}_br{branch}_e2e", pr="7", branch="main")
        == "hw_pr7_brmain_e2e"
    )
